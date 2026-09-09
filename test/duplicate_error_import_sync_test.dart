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
    final exportPath = p.join(dbPath, 'exported_working_test.db');

    try {
      if (await File(masterPath).exists()) await File(masterPath).delete();
    } catch (e) {
      final db = await DatabaseService.getDb();
      await db.delete('inspections');
      await db.delete('doors');
      await db.delete('inspection_doors');
      await db.delete('inspection_door_errors');
      await db.delete('error_catalog');
    }

    try {
      if (await File(localPath).exists()) await File(localPath).delete();
    } catch (_) {
      final db = await LocalDatabaseService.getDb();
      await db.delete('inspections');
      await db.delete('doors');
      await db.delete('inspection_doors');
      await db.delete('inspection_door_errors');
      await db.delete('error_catalog');
    }

    try {
      if (await File(exportPath).exists()) await File(exportPath).delete();
    } catch (_) {}
  });

  tearDown(() async {
    await DatabaseService.closeDb();
    await LocalDatabaseService.closeDb();
  });

  group('Duplicate Error Import Sync Fix Verification', () {
    test('Inspector modifications to assigned door error updates existing record in Master DB without duplicates', () async {
      final masterDb = await DatabaseService.getDb();

      // 1. Clean Master DB tables
      await masterDb.delete('inspection_door_errors');
      await masterDb.delete('inspection_doors');
      await masterDb.delete('inspections');
      await masterDb.delete('doors');
      await masterDb.delete('error_catalog');

      // 2. Insert Master Catalog Entry
      await DatabaseService.insertErrorCatalog(ErrorCatalog(
        errorId: 100,
        code: 'ERR_LOCK_01',
        description: 'Schloss klemmt',
        category: 'Schloss',
        severity: 'medium',
      ));

      // 3. Insert Master Door, Inspection, Junction, and assigned Error
      final doorId = await DatabaseService.insertDoor(Door(
        id: 1,
        doorNumber: 'T-101',
        doorAlias: 'CLIENT_ADDR_T-101',
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
        lintelHeightInsideOver1m: false,
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
        'date': '2026-08-04',
        'contactPerson': 'Tester',
        'inspectorName': 'Inspector 1',
        'jobNumber': 'JOB-SYNC-MOD-01',
      });

      final inspDoorId = await DatabaseService.insertInspectionDoor({
        'id': 10,
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': 'Failed',
        'notes': 'Schloss defekt',
      });

      await DatabaseService.insertInspectionDoorError(InspectionDoorError(
        id: 50,
        inspectionDoorId: inspDoorId,
        errorId: 100,
        errorCode: 'ERR_LOCK_01',
        quantity: 1,
        severity: 'medium',
        notes: 'Initial defect note before inspector modification',
        resolutionStatus: 'open',
      ));

      // 4. Download Job Package to Inspector Local DB (working.db)
      await LocalDatabaseService.downloadJobPackage(inspectionIds: [inspectionId]);

      // Verify local DB has the initial error
      final initialLocalErrors = await LocalDatabaseService.getErrorsForInspectionDoor(inspDoorId);
      expect(initialLocalErrors.length, equals(1));
      expect(initialLocalErrors.first.notes, equals('Initial defect note before inspector modification'));

      // 5. Inspector modifies the assigned error in working.db
      final modifiedError = initialLocalErrors.first.copyWith(
        notes: 'Inspector updated note: replaced latch mechanism',
        resolutionStatus: 'in_progress',
        severity: 'high',
      );
      await LocalDatabaseService.insertInspectionDoorError(modifiedError);

      // Verify local DB still has 1 updated error
      final updatedLocalErrors = await LocalDatabaseService.getErrorsForInspectionDoor(inspDoorId);
      expect(updatedLocalErrors.length, equals(1));
      expect(updatedLocalErrors.first.notes, equals('Inspector updated note: replaced latch mechanism'));

      // 6. Export working.db as a package and import/merge into Master DB
      final dbPath = await getDatabasesPath();
      final exportPackagePath = p.join(dbPath, 'exported_working_test.db');
      await LocalDatabaseService.exportWorkingDb(exportPackagePath);

      // Import & Merge into Master DB
      await DatabaseService.importAndMergePackage(exportPackagePath);

      // 7. ASSERT: Master DB contains ONLY ONE error record for the door (NO DUPLICATE)
      final masterErrors = await DatabaseService.getErrorsForInspectionDoor(inspDoorId);
      expect(masterErrors.length, equals(1), reason: 'Master DB should contain exactly 1 error record, not duplicate');
      expect(masterErrors.first.errorCode, equals('ERR_LOCK_01'));
      expect(masterErrors.first.notes, equals('Inspector updated note: replaced latch mechanism'));
      expect(masterErrors.first.resolutionStatus, equals('in_progress'));
      expect(masterErrors.first.severity, equals('high'));

      // Cleanup export file
      if (await File(exportPackagePath).exists()) await File(exportPackagePath).delete();
    });
  });
}
