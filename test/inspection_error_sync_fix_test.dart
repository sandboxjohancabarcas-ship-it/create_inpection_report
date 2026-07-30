import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseService.closeDb();
    await LocalDatabaseService.closeDb();

    final dbPath = await getDatabasesPath();
    final masterPath = p.join(dbPath, 'door_inspection.db');
    final localPath = p.join(dbPath, 'working.db');

    if (await File(masterPath).exists()) await File(masterPath).delete();
    if (await File(localPath).exists()) await File(localPath).delete();
  });

  tearDown(() async {
    await DatabaseService.closeDb();
    await LocalDatabaseService.closeDb();
  });

  group('Inspection Error Sync Fixes Verification', () {
    test('Fix 1 & 2: downloadJobPackage remaps local errorId and getDetailedErrorsForInspectionDoor uses LEFT JOIN', () async {
      final masterDb = await DatabaseService.getDb();

      // Clean tables
      await masterDb.delete('inspection_door_errors');
      await masterDb.delete('inspection_doors');
      await masterDb.delete('inspections');
      await masterDb.delete('doors');
      await masterDb.delete('error_catalog');

      // Insert catalog entry with high errorId (e.g. 500)
      await DatabaseService.insertErrorCatalog(ErrorCatalog(
        errorId: 500,
        code: 'ERR_TEST_SYNC_01',
        description: 'Test Door Lock Defect',
        category: 'Schloss',
        severity: 'high',
      ));

      // Insert master door and inspection
      final doorId = await DatabaseService.insertDoor(Door(
        id: 1,
        doorNumber: 'T-100',
        doorAlias: 'CLIENT_ADDR_T-100',
        pos: 1,
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
        doorFunctionOK: false,
      ));

      final inspectionId = await DatabaseService.insertInspection({
        'inspectionId': 1,
        'clientName': 'Test Client',
        'objectAddress': 'Test Address',
        'date': '2026-07-30',
        'contactPerson': 'Tester',
        'inspectorName': 'Inspector 1',
        'jobNumber': 'JOB-2026-01',
      });

      final inspDoorId = await DatabaseService.insertInspectionDoor({
        'id': 10,
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': 'Failed',
        'notes': 'Schloss defekt',
      });

      await DatabaseService.insertInspectionDoorError(InspectionDoorError(
        inspectionDoorId: inspDoorId,
        errorId: 500,
        errorCode: 'ERR_TEST_SYNC_01',
        quantity: 1,
        severity: 'high',
        notes: 'Test lock note',
      ));

      // Execute Download to Local DB
      await LocalDatabaseService.downloadJobPackage(inspectionIds: [inspectionId]);

      // Query Local DB detailed errors
      final detailedErrors = await LocalDatabaseService.getDetailedErrorsForInspectionDoor(inspDoorId);
      expect(detailedErrors.length, equals(1));
      expect(detailedErrors.first['code'], equals('ERR_TEST_SYNC_01'));
      expect(detailedErrors.first['description'], equals('Test Door Lock Defect'));
    });

    test('Fix 4: importAndMergePackage falls back to errorCode natural key when errorId mismatch occurs', () async {
      final dbPath = await getDatabasesPath();
      final packagePath = p.join(dbPath, 'package_test.db');
      if (await File(packagePath).exists()) await File(packagePath).delete();

      final masterDb = await DatabaseService.getDb();
      await masterDb.delete('inspection_door_errors');
      await masterDb.delete('inspection_doors');
      await masterDb.delete('inspections');
      await masterDb.delete('doors');
      await masterDb.delete('error_catalog');

      // Master catalog has ID 10 for code 'ERR_CLOSER_99'
      await DatabaseService.insertErrorCatalog(ErrorCatalog(
        errorId: 10,
        code: 'ERR_CLOSER_99',
        description: 'Türschließer defekt',
        category: 'Schließer',
        severity: 'medium',
      ));

      // Package DB has errorId 999 (mismatched) for the same errorCode 'ERR_CLOSER_99'
      final pkgDb = await openDatabase(packagePath, version: 18,
        onCreate: (db, v) async {
          await db.execute('CREATE TABLE doors (id INTEGER PRIMARY KEY, doorAlias TEXT UNIQUE, doorNumber TEXT)');
          await db.execute('CREATE TABLE inspections (inspectionId INTEGER PRIMARY KEY, jobNumber TEXT)');
          await db.execute('CREATE TABLE inspection_doors (id INTEGER PRIMARY KEY, inspectionId INTEGER, doorId INTEGER)');
          await db.execute('CREATE TABLE inspection_door_errors (id INTEGER PRIMARY KEY, inspectionDoorId INTEGER, errorId INTEGER, errorCode TEXT, quantity INTEGER, severity TEXT, notes TEXT)');
          await db.execute('CREATE TABLE error_catalog (errorId INTEGER PRIMARY KEY, code TEXT UNIQUE, description TEXT, category TEXT, status TEXT)');
        }
      );

      await pkgDb.insert('doors', {'id': 1, 'doorAlias': 'ALIAS-001', 'doorNumber': 'T-01'});
      await pkgDb.insert('inspections', {'inspectionId': 1, 'jobNumber': 'JOB-MERGE-01'});
      await pkgDb.insert('inspection_doors', {'id': 100, 'inspectionId': 1, 'doorId': 1});
      await pkgDb.insert('error_catalog', {'errorId': 999, 'code': 'ERR_CLOSER_99', 'description': 'Türschließer defekt', 'category': 'Schließer', 'status': 'Approved'});
      await pkgDb.insert('inspection_door_errors', {
        'id': 1,
        'inspectionDoorId': 100,
        'errorId': 999, // Mismatched ID from local DB
        'errorCode': 'ERR_CLOSER_99',
        'quantity': 1,
        'severity': 'medium',
        'notes': 'Inspector note',
      });
      await pkgDb.close();

      // Merge package into Master
      await DatabaseService.importAndMergePackage(packagePath);

      // Verify merged error in Master DB by fetching master junctions
      final masterJunctions = await DatabaseService.getInspectionDoorsByInspectionId(1);
      expect(masterJunctions.length, equals(1));
      final masterJunctionId = masterJunctions.first['id'] as int;

      final errorsInMaster = await DatabaseService.getErrorsForInspectionDoorIds([masterJunctionId]);
      expect(errorsInMaster.length, equals(1));
      expect(errorsInMaster.first['code'], equals('ERR_CLOSER_99'));
      expect(errorsInMaster.first['description'], equals('Türschließer defekt'));

      if (await File(packagePath).exists()) await File(packagePath).delete();
    });
  });
}
