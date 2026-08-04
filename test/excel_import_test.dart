import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';
import 'package:wartungstool/services/local_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ExcelDataImporter Service Tests', () {
    setUp(() async {
      final db = await DatabaseService.getDb();
      await db.delete('inspections');
      await db.delete('doors');
      await db.delete('inspection_doors');
      await db.delete('inspection_door_errors');
      await db.delete('error_catalog');
    });

    test('Door.generateAlias generates distinct aliases when floor differs for same doorNumber', () {
      final egAlias = Door.generateAlias('Stadt Geesthacht', 'Regenbogen', '1', floor: 'EG');
      final ogAlias = Door.generateAlias('Stadt Geesthacht', 'Regenbogen', '1', floor: '1.OG');

      expect(egAlias, isNot(equals(ogAlias)));
      expect(egAlias, contains('EG'));
      expect(ogAlias, contains('1OG'));
    });

    test('Inserting doors with same doorNumber on different floors preserves both records', () async {
      final egDoor = Door(
        id: null,
        pos: 1,
        doorAlias: Door.generateAlias('Client', 'Address', '1', floor: 'EG'),
        doorNumber: '1',
        floor: 'EG',
        roomNumber: '101',
        roomDesignation: 'Büro',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Dorma',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: '',
        lockDimensions: '',
        closerOnHingeSide: false,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: false,
        accessControl: '',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: false,
        fittingType: '',
        panicFunction: '',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
      );

      final ogDoor = Door(
        id: null,
        pos: 2,
        doorAlias: Door.generateAlias('Client', 'Address', '1', floor: '1.OG'),
        doorNumber: '1',
        floor: '1.OG',
        roomNumber: '201',
        roomDesignation: 'Büro',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Dorma',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: '',
        lockDimensions: '',
        closerOnHingeSide: false,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: false,
        accessControl: '',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: false,
        fittingType: '',
        panicFunction: '',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
      );

      await DatabaseService.insertDoor(egDoor);
      await DatabaseService.insertDoor(ogDoor);

      final allDoors = await DatabaseService.getAllDoors();
      expect(allDoors.length, equals(2), reason: 'Both EG and 1.OG doors should exist without overwriting');
    });

    test('importFromFile should parse doors and inspections correctly', () async {
      final file = File(r'GAEB\25-12115-AB P-003341 Fam. Zentrum Regenbogen, Neuer Krug 31 Türen KINCHI TEST.xlsx');
      expect(file.existsSync(), isTrue, reason: 'Excel file must exist');

      final result = await ExcelDataImporter.importFromFile(file);

      expect(result.sheetsProcessed, equals(1));
      expect(result.doorsImported, equals(38));
      expect(result.errorsLinked, equals(34));
      expect(result.warnings.isEmpty, isTrue);

      final db = await DatabaseService.getDb();
      
      final inspectionsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inspections')) ?? 0;
      final doorsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM doors')) ?? 0;
      final junctionsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inspection_doors')) ?? 0;
      final errorsLinkedCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inspection_door_errors')) ?? 0;

      expect(inspectionsCount, equals(1));
      expect(doorsCount, equals(38));
      expect(junctionsCount, equals(38));
      expect(errorsLinkedCount, equals(34));

      // Verify that all linked errors have non-empty errorCode natural keys in Master DB
      final masterErrorRows = await db.query('inspection_door_errors');
      for (final row in masterErrorRows) {
        final code = row['errorCode'] as String? ?? '';
        expect(code.isNotEmpty, isTrue, reason: 'All imported errors must have a populated errorCode natural key');
      }

      // Verify cross-database transfer via job package download to LocalDatabaseService
      final inspectionRow = (await db.query('inspections')).first;
      final inspectionId = inspectionRow['inspectionId'] as int;

      await LocalDatabaseService.downloadJobPackage(inspectionIds: [inspectionId]);

      final localDb = await LocalDatabaseService.getDb();
      final localErrorCount = Sqflite.firstIntValue(await localDb.rawQuery('SELECT COUNT(*) FROM inspection_door_errors')) ?? 0;
      expect(localErrorCount, equals(34), reason: 'Local DB should receive all 34 errors via job package download');

      final localErrorRows = await localDb.query('inspection_door_errors');
      for (final row in localErrorRows) {
        final code = row['errorCode'] as String? ?? '';
        expect(code.isNotEmpty, isTrue, reason: 'Local DB errors must retain valid errorCode natural keys');
      }
    });
  });
}
