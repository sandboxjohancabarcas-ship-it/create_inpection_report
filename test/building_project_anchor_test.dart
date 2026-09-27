import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/door.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';

Door _makeTestDoor({
  int? id,
  required int pos,
  required String doorNumber,
  required String floor,
  required String roomDesignation,
  String? doorAlias,
  String? provisionalAlias,
  String manufacturer = 'HÖRMANN',
  String material = 'Stahl',
}) {
  return Door(
    id: id ?? 1,
    pos: pos,
    doorAlias: doorAlias,
    provisionalAlias: provisionalAlias,
    doorNumber: doorNumber,
    floor: floor,
    roomNumber: '01',
    roomDesignation: roomDesignation,
    doorType: 'T30',
    wingCount: 1,
    material: material,
    manufacturer: manufacturer,
    dinConfiguration: 'DIN L',
    closerType: 'TS93',
    closingSequenceSystem: 'Keine',
    lockDimensions: '72mm',
    closerOnHingeSide: false,
    closerOnOppositeSide: false,
    lintelHeightInsideOver1m: false,
    lintelHeightOutsideOver1m: false,
    escapeDoorControl: 'Nein',
    accessControl: 'Nein',
    escapeRouteSituation: false,
    escapeRouteSignage: false,
    blindCylinder: false,
    pzCylinder: false,
    fittingType: 'Drücker',
    panicFunction: 'Nein',
    escapeDirectionRespected: false,
    fullPanicStandWing: false,
    doorFunctionOK: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await DatabaseService.clearDatabase();
    final masterDb = await DatabaseService.getDb();
    await masterDb.delete('doors');
    await masterDb.delete('inspections');
    await masterDb.delete('inspection_doors');
    await masterDb.delete('inspection_door_errors');
    await masterDb.delete('error_catalog');

    final localDb = await LocalDatabaseService.getDb();
    await localDb.delete('doors');
    await localDb.delete('inspections');
    await localDb.delete('inspection_doors');
    await localDb.delete('inspection_door_errors');
    await localDb.delete('error_catalog');
  });

  tearDown(() async {
    await DatabaseService.closeDb();
    await LocalDatabaseService.closeDb();
  });

  group('Building / Project Anchor & Zero-Door Onboarding Tests', () {
    test('1. Zero-door Kickoff package export from Manager and import on Inspector device', () async {
      // 1. Manager creates a new inspection template with 0 doors for a new building
      final int inspectionId = await DatabaseService.insertInspection({
        'clientName': 'Neuer Kunde Holding AG',
        'objectAddress': 'Musterstraße 42, 80331 München',
        'jobNumber': 'AUFTRAG-2026-001',
        'projectNumber': 'P-MUC-42',
        'date': '2026-10-01T09:00:00.000',
        'contactPerson': 'Herr Vor-Ort',
        'inspectorName': 'Max Prüfer',
        'isLocked': 0,
      });

      // Verify created in Master DB with 0 doors
      final masterInsp = await DatabaseService.getInspectionById(inspectionId);
      expect(masterInsp, isNotNull);
      expect(masterInsp!['projectNumber'], equals('P-MUC-42'));
      
      final masterDoors = await DatabaseService.getDoorsByInspectionIds([inspectionId]);
      expect(masterDoors, isEmpty);

      // 2. Manager exports inspection package to a temp file
      final tempDir = Directory.systemTemp.createTempSync('wartung_test_');
      final exportFilePath = '${tempDir.path}/kickoff_package.db';

      await DatabaseService.exportJobPackage([inspectionId], destinationPath: exportFilePath);
      expect(File(exportFilePath).existsSync(), isTrue);

      // 3. Simulate clean Inspector tablet receiving the package
      final localDb = await LocalDatabaseService.getDb();
      await localDb.delete('doors');
      await localDb.delete('inspections');
      await localDb.delete('inspection_doors');
      await localDb.delete('inspection_door_errors');
      await localDb.delete('error_catalog');

      final importReport = await LocalDatabaseService.importAndMergePackage(exportFilePath);
      expect(importReport.newInspectionsCount, equals(1));
      expect(importReport.newDoorsCount, equals(0));

      // 4. Verify Local DB has the zero-door kickoff template
      final localInspections = await LocalDatabaseService.getAllInspections();
      expect(localInspections.length, equals(1));
      expect(localInspections.first['jobNumber'], equals('AUFTRAG-2026-001'));
      expect(localInspections.first['projectNumber'], equals('P-MUC-42'));
      expect(localInspections.first['objectAddress'], equals('Musterstraße 42, 80331 München'));

      final localDoors = await LocalDatabaseService.getDoorsByInspectionId(localInspections.first['inspectionId']);
      expect(localDoors, isEmpty);

      // Clean up temp file
      tempDir.deleteSync(recursive: true);
    });

    test('2. Inspector adds new door to zero-door template, inheriting project number and building alias', () async {
      // Setup local kickoff inspection template in Local DB
      final int localInspId = await LocalDatabaseService.insertInspection({
        'clientName': 'Kunde Facility Management',
        'objectAddress': 'Technologiepark 7, Berlin',
        'jobNumber': 'JOB-BER-01',
        'projectNumber': 'BER-07',
        'date': '2026-09-27T10:00:00.000',
        'contactPerson': 'Frau Hausmeister',
        'inspectorName': 'Anna Inspektor',
        'isLocked': 0,
      });

      // Inspector creates a new door on-site
      final localInsp = await LocalDatabaseService.getInspectionById(localInspId);
      expect(localInsp, isNotNull);

      final projectNumber = localInsp!['projectNumber'] as String;
      const int pos = 1;
      const String floor = 'EG';
      const String doorNumber = '01';

      // Alias is built from projectNumber, pos, floor, doorNumber
      final generatedAlias = Door.generateAlias(
        projectNumber: projectNumber,
        pos: pos,
        floor: floor,
        doorNumber: doorNumber,
      );
      expect(generatedAlias, equals('BER-07-1-EG-01'));

      final door = _makeTestDoor(
        id: 10,
        pos: pos,
        doorNumber: doorNumber,
        floor: floor,
        roomDesignation: 'Haupteingang',
        doorAlias: generatedAlias,
        provisionalAlias: generatedAlias,
        manufacturer: 'Dorma',
      );

      final int newDoorId = await LocalDatabaseService.insertDoor(door);
      expect(newDoorId, greaterThan(0));

      // Link door to inspection
      await LocalDatabaseService.insertInspectionDoor({
        'inspectionId': localInspId,
        'doorId': newDoorId,
        'status': 'Done',
      });

      // Verify door is linked and searchable
      final doorsInInspection = await LocalDatabaseService.getDoorsByInspectionId(localInspId);
      expect(doorsInInspection.length, equals(1));
      expect(doorsInInspection.first.doorAlias, equals('BER-07-1-EG-01'));
      expect(doorsInInspection.first.roomDesignation, equals('Haupteingang'));
    });

    test('3. Address/building update propagates across all linked inspections for that project', () async {
      // Create 2 inspections for the same physical project building across different years
      final int insp2025 = await DatabaseService.insertInspection({
        'clientName': 'Münchner Gewerbehof GmbH',
        'objectAddress': 'Altstraße 10, München',
        'jobNumber': 'JOB-2025',
        'projectNumber': 'PRJ-MUC-10',
        'date': '2025-05-10T00:00:00.000',
      });

      final int insp2026 = await DatabaseService.insertInspection({
        'clientName': 'Münchner Gewerbehof GmbH',
        'objectAddress': 'Altstraße 10, München',
        'jobNumber': 'JOB-2026',
        'projectNumber': 'PRJ-MUC-10',
        'date': '2026-05-10T00:00:00.000',
      });

      // Insert a door linked to insp2025
      final door1Id = await DatabaseService.insertDoor(_makeTestDoor(
        id: 101,
        pos: 1,
        floor: 'OG1',
        doorNumber: '101',
        roomDesignation: 'Büro 1.01',
        doorAlias: 'PRJ-MUC-10-1-OG1-101',
      ));
      await DatabaseService.insertInspectionDoor({
        'inspectionId': insp2025,
        'doorId': door1Id,
        'status': 'Done',
      });

      // Manager updates address typo and normalizes project number across the building
      final updatedCount = await DatabaseService.updateProjectBuildingData(
        currentProjectNumber: 'PRJ-MUC-10',
        newProjectNumber: 'PRJ-MUC-10-NEU',
        newObjectAddress: 'Neustraße 10a, 80333 München',
      );

      expect(updatedCount, equals(2));

      // Verify both inspections updated
      final updatedInsp2025 = await DatabaseService.getInspectionById(insp2025);
      final updatedInsp2026 = await DatabaseService.getInspectionById(insp2026);

      expect(updatedInsp2025!['objectAddress'], equals('Neustraße 10a, 80333 München'));
      expect(updatedInsp2025['projectNumber'], equals('PRJ-MUC-10-NEU'));

      expect(updatedInsp2026!['objectAddress'], equals('Neustraße 10a, 80333 München'));
      expect(updatedInsp2026['projectNumber'], equals('PRJ-MUC-10-NEU'));

      // Verify door alias updated to match the new project number
      final updatedDoor = await DatabaseService.getDoorByAlias('PRJ-MUC-10-NEU-1-OG1-101');
      expect(updatedDoor, isNotNull);
      expect(updatedDoor!.id, equals(door1Id));
    });

    test('4. Tenant change (clientName) retains all physical door hardware records under the same project', () async {
      // Tenant 1 leases building PRJ-B7
      final int inspTenant1 = await DatabaseService.insertInspection({
        'clientName': 'Firma Alt AG',
        'objectAddress': 'Industriepark 7, Stuttgart',
        'jobNumber': 'STG-2024',
        'projectNumber': 'PRJ-B7',
        'date': '2024-03-01T00:00:00.000',
      });

      final doorId = await DatabaseService.insertDoor(_makeTestDoor(
        id: 201,
        pos: 1,
        doorNumber: 'E01',
        floor: 'EG',
        roomDesignation: 'Serverraum',
        doorAlias: 'PRJ-B7-1-EG-E01',
        manufacturer: 'HÖRMANN',
        material: 'Stahl',
      ));

      await DatabaseService.insertInspectionDoor({
        'inspectionId': inspTenant1,
        'doorId': doorId,
        'status': 'Done',
      });

      // Tenant moves out, new tenant moves into the same building
      final int inspTenant2 = await DatabaseService.insertInspection({
        'clientName': 'Neue Software GmbH (Nachmieter)',
        'objectAddress': 'Industriepark 7, Stuttgart',
        'jobNumber': 'STG-2026',
        'projectNumber': 'PRJ-B7',
        'date': '2026-03-01T00:00:00.000',
      });

      // Link existing physical door to new inspection
      await DatabaseService.insertInspectionDoor({
        'inspectionId': inspTenant2,
        'doorId': doorId,
        'status': 'InProgress',
      });

      // Verify door persists with hardware details and alias unchanged
      final doorsTenant2 = await DatabaseService.getDoorsByInspectionIds([inspTenant2]);
      expect(doorsTenant2.length, equals(1));
      expect(doorsTenant2.first.id, equals(doorId));
      expect(doorsTenant2.first.doorAlias, equals('PRJ-B7-1-EG-E01'));
      expect(doorsTenant2.first.manufacturer, equals('HÖRMANN'));
      expect(doorsTenant2.first.roomDesignation, equals('Serverraum'));

      // Verify door history contains both tenants
      final history = await DatabaseService.getDoorHistoryData(doorId: doorId);
      expect(history, isNotNull);
      expect(history!['totalInspections'], equals(2));
    });
  });
}
