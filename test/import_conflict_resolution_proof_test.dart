import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/batch_migration_service.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/door_options_service.dart';
import 'package:wartungstool/services/door_validator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  // Initialize FFI for SQLite desktop test execution
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Proof of Manager Dropdown Conflict Resolution on Package Import', () {
    late String tempDbPath;

    setUp(() async {
      final tempDir = await Directory.systemTemp.createTemp('proof_test_');
      tempDbPath = '${tempDir.path}/inspector_package.db';

      // Reset options with baseline master dropdown values
      DoorOptionsService.reset();
      DoorOptionsService.setMockOptions({
        'approvalNumber': {'options': ['?'], 'default': '?'},
        'manufacturerNumber': {'options': ['?'], 'default': '?'},
        'dopNumber': {'options': ['?'], 'default': '?'},
        'manufacturer': {'options': ['?', 'Hörmann', 'Schüco'], 'default': '?'},
        'doorType': {'options': ['?', 'T30-1'], 'default': '?'},
      });
    });

    test('Inspector introduces new custom value -> Package Import flags conflict -> Manager resolves by adding to master dropdown options', () async {
      // ───────────────────────────────────────────────────────────────────────
      // STEP 1: INSPECTOR CREATES INSPECTION WITH CUSTOM DROPDOWN VALUES
      // Inspector types custom value "Z-999-PROOF-APPROVAL" for Zulassungsnummer
      // and custom manufacturer "SuperDoor-GmbH"
      // ───────────────────────────────────────────────────────────────────────
      final packageDb = await openDatabase(tempDbPath, version: 20, onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE doors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pos INTEGER,
            doorAlias TEXT,
            doorNumber TEXT,
            floor TEXT,
            roomNumber TEXT,
            roomDesignation TEXT,
            doorType TEXT,
            wingCount INTEGER,
            material TEXT,
            manufacturer TEXT,
            dinConfiguration TEXT,
            closerType TEXT,
            closingSequenceSystem TEXT,
            lockDimensions TEXT,
            closerOnHingeSide INTEGER,
            closerOnOppositeSide INTEGER,
            lintelHeightUnder1m INTEGER,
            escapeDoorControl INTEGER,
            accessControl TEXT,
            escapeRouteSituation INTEGER,
            escapeRouteSignage INTEGER,
            blindCylinder INTEGER,
            pzCylinder INTEGER,
            fittingType TEXT,
            panicFunction TEXT,
            escapeDirectionRespected INTEGER,
            fullPanicStandWing INTEGER,
            doorFunctionOK INTEGER,
            approvalNumber TEXT,
            manufacturerNumber TEXT,
            dopNumber TEXT,
            lintelHeightOver1m INTEGER,
            lintelHeightValue INTEGER,
            manufactureYear TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE inspections (
            inspectionId INTEGER PRIMARY KEY AUTOINCREMENT,
            clientName TEXT,
            objectAddress TEXT,
            date TEXT,
            contactPerson TEXT,
            inspectorName TEXT,
            jobNumber TEXT,
            projectNumber TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE inspection_doors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inspectionId INTEGER,
            doorId INTEGER,
            status TEXT,
            notes TEXT,
            attachments TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE inspection_door_errors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inspectionDoorId INTEGER,
            errorCode TEXT,
            notes TEXT,
            attachments TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE error_catalog (
            errorId INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT,
            category TEXT,
            description TEXT,
            status TEXT
          )
        ''');
      });

      final inspectorDoor = Door(
        id: null,
        pos: 1,
        doorAlias: 'PROOF-ALIAS-001',
        doorNumber: '101',
        floor: 'EG',
        roomNumber: '1.01',
        roomDesignation: 'Eingang',
        doorType: 'T30-1',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'SuperDoor-GmbH', // <-- NEW CUSTOM VALUE ADDED BY INSPECTOR!
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: 'Nein',
        lockDimensions: '35/92/9',
        closerOnHingeSide: true,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: false,
        accessControl: 'Nein',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: true,
        fittingType: 'D-D',
        panicFunction: 'Nein',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
        approvalNumber: 'Z-999-PROOF-APPROVAL', // <-- NEW CUSTOM VALUE ADDED BY INSPECTOR!
        manufacturerNumber: 'H-88-PROOF',       // <-- NEW CUSTOM VALUE ADDED BY INSPECTOR!
        dopNumber: 'DoP-77-PROOF',              // <-- NEW CUSTOM VALUE ADDED BY INSPECTOR!
      );

      final insertedDoorId = await packageDb.insert('doors', inspectorDoor.toMap()..remove('id'));
      await packageDb.insert('inspections', {
        'clientName': 'Proof Client',
        'objectAddress': 'Test Str 1',
        'date': '2026-09-07',
        'jobNumber': 'JOB-PROOF-100',
      });
      await packageDb.insert('inspection_doors', {
        'inspectionId': 1,
        'doorId': insertedDoorId,
        'status': 'Completed',
      });
      await packageDb.close();

      // ───────────────────────────────────────────────────────────────────────
      // STEP 2: MANAGER IMPORTS THE INSPECTOR'S PACKAGE FILE VIA BATCH MIGRATION SERVICE
      // Verify that BatchMigrationService collects package door conflicts for Manager review!
      // ───────────────────────────────────────────────────────────────────────
      final batchResult = await BatchMigrationService.migrateFiles([File(tempDbPath)]);

      // PROOF ASSERTION 1: Package import returned conflict review items for Manager!
      expect(batchResult.doorConflicts.isNotEmpty, isTrue, reason: 'Manager MUST be raised conflict items for new custom dropdown entries');
      
      final customConflicts = batchResult.doorConflicts
          .where((c) => c.type == DoorConflictType.newDropdownOption)
          .toList();

      expect(customConflicts.length, greaterThanOrEqualTo(4));
      final flaggedFields = customConflicts.map((c) => c.fieldName).toList();
      expect(flaggedFields, containsAll(['approvalNumber', 'manufacturerNumber', 'dopNumber', 'manufacturer']));

      // Verify the UI prompt message shown to Manager
      final approvalConflict = customConflicts.firstWhere((c) => c.fieldName == 'approvalNumber');
      expect(approvalConflict.incomingValue, 'Z-999-PROOF-APPROVAL');
      expect(approvalConflict.message, contains('Z-999-PROOF-APPROVAL'));
      expect(approvalConflict.resolution, DoorResolutionAction.addToMasterOptions);

      // ───────────────────────────────────────────────────────────────────────
      // STEP 3: MANAGER ACCEPTS AND ADOPTS THE NEW VALUES INTO MASTER DROPDOWN OPTIONS
      // Calling DatabaseService.applyDoorConflictResolutions as done by DoorConflictReviewPage
      // ───────────────────────────────────────────────────────────────────────
      await DatabaseService.applyDoorConflictResolutions(customConflicts);

      // PROOF ASSERTION 2: Master options now contain the Inspector's custom entries!
      expect(DoorOptionsService.getStringOptions('approvalNumber'), contains('Z-999-PROOF-APPROVAL'));
      expect(DoorOptionsService.getStringOptions('manufacturerNumber'), contains('H-88-PROOF'));
      expect(DoorOptionsService.getStringOptions('dopNumber'), contains('DoP-77-PROOF'));
      expect(DoorOptionsService.getStringOptions('manufacturer'), contains('SuperDoor-GmbH'));
    });
  });
}
