import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/models/models.dart';
import 'dart:io';

void main() {
  // Setup for Windows/Desktop testing environment
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    // Ensure the database is closed before clearing files
    await DatabaseService.closeDb();

    final dbPath = await getDatabasesPath();
    final path = '$dbPath/door_inspection.db';
    if (await File(path).exists()) await File(path).delete();
    
    // Re-initialize Master DB
    await DatabaseService.getDb();
  });

  tearDown(() async {
    await DatabaseService.closeDb();
  });

  tearDownAll(() async {
    final dbPath = await getDatabasesPath();
    final mainDb = File('$dbPath/door_inspection.db');
    final pkgDb = File('$dbPath/test_package.db');
    if (await mainDb.exists()) await mainDb.delete();
    if (await pkgDb.exists()) await pkgDb.delete();
  });

  group('Merge & Conflict Logic Tests', () {
    test('Merge Logic updates existing Door via Alias (Upsert)', () async {
      final dbPath = await getDatabasesPath();
      final packagePath = '$dbPath/test_package.db';
      if (await File(packagePath).exists()) await File(packagePath).delete();

      // 1. Create a Door in Master DB (Pre-existing record)
      final masterDb = await DatabaseService.getDb();
      await masterDb.insert('doors', {
        'doorAlias': 'UNIQUE-001', 
        'roomDesignation': 'Alt', 
        'pos': 1,
        'dinConfiguration': 'DIN L'
      });

      // 2. Create a "Result Package" mimicking an inspector's mobile DB
      final pkgDb = await openDatabase(packagePath, version: 15, 
        onCreate: (db, v) async {
          await db.execute('CREATE TABLE doors (id INTEGER PRIMARY KEY, doorAlias TEXT UNIQUE, roomDesignation TEXT, pos INTEGER, dinConfiguration TEXT, fittingType TEXT, closerType TEXT)');
          await db.execute('CREATE TABLE inspections (inspectionId INTEGER PRIMARY KEY, jobNumber TEXT)');
          await db.execute('CREATE TABLE inspection_doors (id INTEGER PRIMARY KEY, inspectionId INTEGER, doorId INTEGER)');
          await db.execute('CREATE TABLE inspection_door_errors (id INTEGER PRIMARY KEY, inspectionDoorId INTEGER)');
          await db.execute('CREATE TABLE error_catalog (errorId INTEGER PRIMARY KEY, status TEXT)');
        }
      );
      // Insert same Alias but with updated roomDesignation ('Neu') and correct technical keys
      await pkgDb.insert('doors', {
        'id': 1, 
        'doorAlias': 'UNIQUE-001', 
        'roomDesignation': 'Neu', 
        'pos': 1,
        'dinConfiguration': 'DIN L',
        'fittingType': 'Drücker',
        'closerType': 'TS93'
      });
      await pkgDb.close();

      // 3. Execute the Merge Logic
      await DatabaseService.importAndMergePackage(packagePath);

      // 4. Verify results: Record should be updated, not duplicated
      final results = await masterDb.query('doors', where: 'doorAlias = ?', whereArgs: ['UNIQUE-001']);
      expect(results.length, equals(1), reason: 'Duplicate door created instead of updating existing one');
      expect(results.first['roomDesignation'], equals('Neu'), reason: 'Data was not updated during merge');
    });

    test('Merge doors should trigger detailed diagnostics when property conflicts reach 20', () async {
      final masterDb = await DatabaseService.getDb();
      
      // 1. Create a dummy inspection in Master DB to act as the source of existing doors
      final inspectionId = await masterDb.insert('inspections', {
        'jobNumber': 'JOB-OLD-01',
        'date': '2025-01-01',
        'clientName': 'Kunde Alt',
        'objectAddress': 'Adresse Alt',
      });

      final List<Door> incomingDoors = [];
      
      // 2. Insert 20 doors in Master DB and link them to the old inspection
      for (int i = 1; i <= 20; i++) {
        final alias = 'DIAG-DOOR-${i.toString().padLeft(3, '0')}';
        
        final door = Door(
          id: null,
          pos: i,
          doorAlias: alias,
          doorNumber: 'T-${i}',
          floor: 'EG',
          roomNumber: 'R-$i',
          roomDesignation: 'Büro $i', // original value
          doorType: '',
          wingCount: 1,
          material: '',
          manufacturer: '',
          dinConfiguration: '',
          closerType: '',
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
          escapeDirectionRespected: false,
          fullPanicStandWing: false,
          doorFunctionOK: true,
        );

        final doorId = await masterDb.insert('doors', door.toMap()..remove('id'));

        await masterDb.insert('inspection_doors', {
          'inspectionId': inspectionId,
          'doorId': doorId,
          'status': 'Failed',
          'notes': 'Vorherige Notiz',
        });

        // Add to incoming doors list with a different room designation to trigger a conflict
        incomingDoors.add(door.copyWith(roomDesignation: 'Küche $i'));
      }

      // 3. Execute mergeDoors
      final mergeResult = await DatabaseService.mergeDoors(
        incomingDoors,
        jobNumber: 'JOB-NEW-02',
        sourceContext: 'Blatt: "Türen 2026"',
      );

      // 4. Verify results
      expect(mergeResult.conflicts.length, equals(20));
      expect(mergeResult.technicalCount, equals(20));

      // The 20th conflict (at index 19) should have the detailed diagnostic text appended to its message
      final lastConflict = mergeResult.conflicts[19];
      expect(lastConflict.message, contains('[DIAGNOSE]'));
      expect(lastConflict.message, contains('JOB-OLD-01')); // original job
      expect(lastConflict.message, contains('JOB-NEW-02')); // current job
      expect(lastConflict.message, contains('Türen 2026')); // current context
    });

    test('Merge doors sliding chronological window rules (3-year threshold)', () async {
      final masterDb = await DatabaseService.getDb();

      // Ensure fresh start of log file
      final logFile = File('migration_protocol.log');
      if (await logFile.exists()) await logFile.delete();

      // Helper to create a door instance
      Door createTestDoor(String alias, String room) {
        return Door(
          id: null,
          pos: 1,
          doorAlias: alias,
          doorNumber: '1',
          floor: 'EG',
          roomNumber: '101',
          roomDesignation: room,
          doorType: '',
          wingCount: 1,
          material: '',
          manufacturer: '',
          dinConfiguration: '',
          closerType: '',
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
          escapeDirectionRespected: false,
          fullPanicStandWing: false,
          doorFunctionOK: true,
        );
      }

      // Case A: Discrepancy <= 3 years (e.g. DB = 2024, Incoming = 2025) -> triggers conflict
      final doorIdA = await masterDb.insert('doors', createTestDoor('DOOR-A', 'Büro A').toMap()..remove('id'));
      final inspIdA = await masterDb.insert('inspections', {'jobNumber': 'JOB-A-OLD', 'date': '2024-05-15'});
      await masterDb.insert('inspection_doors', {'inspectionId': inspIdA, 'doorId': doorIdA, 'status': 'Passed'});

      // Case B: Discrepancy > 3 years, Incoming is newer (e.g. DB = 2020, Incoming = 2025) -> auto-updates DB without conflict
      final doorIdB = await masterDb.insert('doors', createTestDoor('DOOR-B', 'Büro B (Alt)').toMap()..remove('id'));
      final inspIdB = await masterDb.insert('inspections', {'jobNumber': 'JOB-B-OLD', 'date': '2020-05-15'});
      await masterDb.insert('inspection_doors', {'inspectionId': inspIdB, 'doorId': doorIdB, 'status': 'Passed'});

      // Case C: Discrepancy > 3 years, DB is newer (e.g. DB = 2025, Incoming = 2020) -> keeps DB properties without conflict
      final doorIdC = await masterDb.insert('doors', createTestDoor('DOOR-C', 'Büro C (Neu)').toMap()..remove('id'));
      final inspIdC = await masterDb.insert('inspections', {'jobNumber': 'JOB-C-NEW', 'date': '2025-05-15'});
      await masterDb.insert('inspection_doors', {'inspectionId': inspIdC, 'doorId': doorIdC, 'status': 'Passed'});

      // Let's run a sheet-like process using ExcelDataImporter logs/logic flow or directly mergeDoors.
      // We will perform the imports chronologically newest-first!
      // Incoming data:
      final incomingA = createTestDoor('DOOR-A', 'Küche A'); // 1 year diff (within 3yr)
      final incomingB = createTestDoor('DOOR-B', 'Küche B (Neu)'); // 5 year diff (incoming is newer)
      final incomingC = createTestDoor('DOOR-C', 'Küche C (Alt)'); // 5 year diff (incoming is older)

      // 1. Run merge for Case A: diff is 2025 - 2024 = 1 year (within 3-year window)
      final mergeA = await DatabaseService.mergeDoors(
        [incomingA],
        jobNumber: 'JOB-A-NEW',
        sourceContext: 'Import 2025',
        currentInspectionDate: '2025-05-15',
      );
      expect(mergeA.conflicts.length, equals(1), reason: 'Should generate conflict since discrepancy is within 3 years');
      expect(mergeA.protocolLogs.first, contains('[CONFLICT QUEUED]'));

      // 2. Run merge for Case B: diff is 2025 - 2020 = 5 years (older than 3 years, incoming is newer)
      final mergeB = await DatabaseService.mergeDoors(
        [incomingB],
        jobNumber: 'JOB-B-NEW',
        sourceContext: 'Import 2025',
        currentInspectionDate: '2025-05-15',
      );
      expect(mergeB.conflicts.length, equals(0), reason: 'Should not generate conflict since age diff is 5 years');
      expect(mergeB.protocolLogs.first, contains('[AUTO-UPDATE]'));
      
      // Verify DB was auto-updated for DOOR-B
      final dbRowsB = await masterDb.query('doors', where: 'doorAlias = ?', whereArgs: ['DOOR-B']);
      expect(dbRowsB.first['roomDesignation'], equals('Küche B (Neu)'), reason: 'DB properties should be auto-updated to newer incoming values');

      // 3. Run merge for Case C: diff is 2025 - 2020 = 5 years (older than 3 years, DB is newer)
      final mergeC = await DatabaseService.mergeDoors(
        [incomingC],
        jobNumber: 'JOB-C-OLD',
        sourceContext: 'Import 2020',
        currentInspectionDate: '2020-05-15',
      );
      expect(mergeC.conflicts.length, equals(0), reason: 'Should not generate conflict since age diff is 5 years');
      expect(mergeC.protocolLogs.first, contains('[SKIPPED STALE]'));

      // Verify DB was NOT updated for DOOR-C (newer DB values kept)
      final dbRowsC = await masterDb.query('doors', where: 'doorAlias = ?', whereArgs: ['DOOR-C']);
      expect(dbRowsC.first['roomDesignation'], equals('Büro C (Neu)'), reason: 'DB properties should keep newer DB values');
    });
  });
}