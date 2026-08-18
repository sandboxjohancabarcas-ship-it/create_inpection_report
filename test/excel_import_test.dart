import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
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

      try {
        final localDb = await LocalDatabaseService.getDb();
        await localDb.delete('inspections');
        await localDb.delete('doors');
        await localDb.delete('inspection_doors');
        await localDb.delete('inspection_door_errors');
        await localDb.delete('error_catalog');
      } catch (_) {}
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

    final testDataDir = Directory(r'C:\Users\Cabarcas\WartungTool\create_inpection_report-1\test\test_data');
    final filesToTest = testDataDir.existsSync()
        ? testDataDir
            .listSync()
            .where((entity) => entity is File && entity.path.endsWith('.xlsx'))
            .cast<File>()
            .toList()
        : <File>[];

    for (final file in filesToTest) {
      final filename = p.basename(file.path);

      test('importFromFile should parse doors and inspections correctly for $filename', () async {
        final bytes = await file.readAsBytes();
        final decoder = SpreadsheetDecoder.decodeBytes(bytes);
        final hasFehler = decoder.tables.containsKey('Fehlerübersicht');

        if (!hasFehler) {
          // This file is known to miss the "Fehlerübersicht" worksheet
          expect(
            () => ExcelDataImporter.importFromFile(file),
            throwsA(isA<Exception>().having((e) => e.toString(), 'description', contains('Fehlerübersicht'))),
          );
          return;
        }

        final result = await ExcelDataImporter.importFromFile(file);

        expect(result.sheetsProcessed, greaterThanOrEqualTo(1));
        expect(result.doorsImported, greaterThan(0));

        if (result.warnings.isNotEmpty) {
          print('INFO: Warnings parsed for $filename:\n${result.warnings.join('\n')}');
        }

        final db = await DatabaseService.getDb();
        
        final inspectionsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inspections')) ?? 0;
        final doorsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM doors')) ?? 0;
        final junctionsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inspection_doors')) ?? 0;
        final errorsLinkedCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inspection_door_errors')) ?? 0;

        print('--- DIAGNOSTICS FOR $filename ---');
        print('result.sheetsProcessed: ${result.sheetsProcessed}');
        print('result.doorsImported: ${result.doorsImported}');
        print('result.errorsLinked: ${result.errorsLinked}');
        print('Master DB inspectionsCount: $inspectionsCount');
        print('Master DB doorsCount: $doorsCount');
        print('Master DB junctionsCount: $junctionsCount');
        print('Master DB errorsLinkedCount: $errorsLinkedCount');

        expect(inspectionsCount, equals(result.sheetsProcessed));
        expect(doorsCount, lessThanOrEqualTo(result.doorsImported));
        expect(junctionsCount, equals(result.doorsImported));
        expect(errorsLinkedCount, equals(result.errorsLinked));

        // Verify that all linked errors have non-empty errorCode natural keys in Master DB
        final masterErrorRows = await db.query('inspection_door_errors');
        for (final row in masterErrorRows) {
          final code = row['errorCode'] as String? ?? '';
          expect(code.isNotEmpty, isTrue, reason: 'All imported errors must have a populated errorCode natural key');
        }

        // Verify cross-database transfer via job package download to LocalDatabaseService
        final inspections = await db.query('inspections');
        final inspectionIds = inspections.map((r) => r['inspectionId'] as int).toList();

        await LocalDatabaseService.downloadJobPackage(inspectionIds: inspectionIds);

        final localDb = await LocalDatabaseService.getDb();
        final localInspectionsCount = Sqflite.firstIntValue(await localDb.rawQuery('SELECT COUNT(*) FROM inspections')) ?? 0;
        final localDoorsCount = Sqflite.firstIntValue(await localDb.rawQuery('SELECT COUNT(*) FROM doors')) ?? 0;
        final localJunctionsCount = Sqflite.firstIntValue(await localDb.rawQuery('SELECT COUNT(*) FROM inspection_doors')) ?? 0;
        final localErrorCount = Sqflite.firstIntValue(await localDb.rawQuery('SELECT COUNT(*) FROM inspection_door_errors')) ?? 0;

        print('Local DB inspectionsCount: $localInspectionsCount');
        print('Local DB doorsCount: $localDoorsCount');
        print('Local DB junctionsCount: $localJunctionsCount');
        print('Local DB localErrorCount: $localErrorCount');

        expect(localInspectionsCount, equals(inspectionsCount));
        expect(localDoorsCount, equals(doorsCount));
        expect(localJunctionsCount, equals(junctionsCount));
        expect(localErrorCount, equals(result.errorsLinked), reason: 'Local DB should receive all errors via job package download');

        final localErrorRows = await localDb.query('inspection_door_errors');
        for (final row in localErrorRows) {
          final code = row['errorCode'] as String? ?? '';
          expect(code.isNotEmpty, isTrue, reason: 'Local DB errors must retain valid errorCode natural keys');
        }
      });
    }
  });
}
