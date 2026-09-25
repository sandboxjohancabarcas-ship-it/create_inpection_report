import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Provisional Alias & Dual Alias Identification Tests', () {
    late String masterPath;
    late String localPath;

    setUp(() async {
      final dbPath = await getDatabasesPath();
      masterPath = p.join(dbPath, 'door_inspection.db');
      localPath = p.join(dbPath, 'working.db');

      await DatabaseService.closeDb();
      await LocalDatabaseService.closeDb();

      try { if (await File(masterPath).exists()) await File(masterPath).delete(); } catch (_) {}
      try { if (await File(localPath).exists()) await File(localPath).delete(); } catch (_) {}

      final masterDb = await DatabaseService.getDb();
      await masterDb.delete('inspection_door_errors');
      await masterDb.delete('inspection_doors');
      await masterDb.delete('inspections');
      await masterDb.delete('doors');

      final localDb = await LocalDatabaseService.getDb();
      await localDb.delete('inspection_door_errors');
      await localDb.delete('inspection_doors');
      await localDb.delete('inspections');
      await localDb.delete('doors');
    });

    tearDown(() async {
      await DatabaseService.closeDb();
      await LocalDatabaseService.closeDb();
    });

    test('Door generates and stores provisionalAlias upon creation', () async {
      final generatedAlias = Door.generateAlias(projectNumber: 'P-100', pos: 1, floor: 'EG', doorNumber: '101');
      final door = Door(
        id: null,
        pos: 1,
        doorAlias: generatedAlias,
        provisionalAlias: generatedAlias,
        doorNumber: '101',
        floor: 'EG',
        roomNumber: '101',
        roomDesignation: 'Büro',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Hörmann',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: 'None',
        lockDimensions: '55/72',
        closerOnHingeSide: true,
        closerOnOppositeSide: false,
        escapeDoorControl: 'Nein',
        accessControl: 'Nein',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: true,
        fittingType: 'Drücker',
        panicFunction: 'Nein',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
      );

      final doorId = await DatabaseService.insertDoor(door);
      expect(doorId, greaterThan(0));

      final fetchedByAlias = await DatabaseService.getDoorByAlias(generatedAlias);
      expect(fetchedByAlias, isNotNull);
      expect(fetchedByAlias!.doorAlias, generatedAlias);
      expect(fetchedByAlias.provisionalAlias, generatedAlias);
    });

    test('Updating scanned doorAlias preserves the original provisionalAlias', () async {
      final provisional = 'KUNDE-HAUPT-EG-102';
      final initialDoor = Door(
        id: null,
        pos: 2,
        doorAlias: provisional,
        provisionalAlias: provisional,
        doorNumber: '102',
        floor: 'EG',
        roomNumber: '102',
        roomDesignation: 'Lager',
        doorType: 'T30',
        wingCount: 1,
        material: 'Holz',
        manufacturer: 'Dorma',
        dinConfiguration: 'DIN R',
        closerType: 'TS93',
        closingSequenceSystem: 'None',
        lockDimensions: '55/72',
        closerOnHingeSide: true,
        closerOnOppositeSide: false,
        escapeDoorControl: 'Nein',
        accessControl: 'Nein',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: true,
        fittingType: 'Drücker',
        panicFunction: 'Nein',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
      );

      final doorId = await DatabaseService.insertDoor(initialDoor);

      // Inspector scans a physical barcode: BARCODE-PHYS-8888
      final newScannedBarcode = 'BARCODE-PHYS-8888';
      await DatabaseService.updateDoorAlias(doorId, newScannedBarcode);

      // Verify that getDoorByAlias finds the door using EITHER alias
      final foundByPhysicalBarcode = await DatabaseService.getDoorByAlias(newScannedBarcode);
      expect(foundByPhysicalBarcode, isNotNull);
      expect(foundByPhysicalBarcode!.id, doorId);
      expect(foundByPhysicalBarcode.doorAlias, newScannedBarcode);
      expect(foundByPhysicalBarcode.provisionalAlias, provisional);

      final foundByProvisional = await DatabaseService.getDoorByAlias(provisional);
      expect(foundByProvisional, isNotNull);
      expect(foundByProvisional!.id, doorId);
      expect(foundByProvisional.doorAlias, newScannedBarcode);
      expect(foundByProvisional.provisionalAlias, provisional);
    });
  });
}
