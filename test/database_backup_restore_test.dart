import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/widgets/app_version_dialog.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseService.closeDb();
    await LocalDatabaseService.closeDb();
  });

  group('Database Backup and Restore Service Tests', () {
    test(
        'Master DB exportMasterDb and importMasterDb backup and restore data completely',
        () async {
      final db = await DatabaseService.getDb();
      final uniqueAlias =
          'BC-BACKUP-TEST-${DateTime.now().microsecondsSinceEpoch}';

      final doorId = await db.insert('doors', {
        'pos': 99,
        'doorAlias': uniqueAlias,
        'doorNumber': 'T-BACKUP',
        'doorType': 'T90',
        'floor': 'OG3',
      });

      final inspId = await db.insert('inspections', {
        'clientName': 'Backup Test Client',
        'objectAddress': 'Backup Weg 1',
        'inspectorName': 'Tester',
        'date': '2026-10-08',
      });

      // 1. Export backup
      final backupPath =
          '${Directory.systemTemp.path}/test_master_backup_${DateTime.now().microsecondsSinceEpoch}.db';
      await DatabaseService.exportMasterDb(backupPath);
      final backupFile = File(backupPath);
      expect(await backupFile.exists(), true);
      expect(await backupFile.length(), greaterThan(0));

      // 2. Modify live database (insert new record)
      final liveDb = await DatabaseService.getDb();
      await liveDb.insert('doors', {
        'pos': 100,
        'doorAlias': 'BC-MODIFIED-${DateTime.now().microsecondsSinceEpoch}',
        'doorNumber': 'T-NEW',
        'doorType': 'T30',
        'floor': 'EG',
      });

      // 3. Restore backup
      await DatabaseService.importMasterDb(backupPath);

      // 4. Verify restored state
      final restoredDb = await DatabaseService.getDb();
      final doors = await restoredDb
          .query('doors', where: 'doorAlias = ?', whereArgs: [uniqueAlias]);
      expect(doors.isNotEmpty, true);
      expect(doors.first['doorNumber'], 'T-BACKUP');

      final newDoors = await restoredDb
          .query('doors', where: 'doorNumber = ?', whereArgs: ['T-NEW']);
      expect(newDoors.isEmpty, true);

      await backupFile.delete();
    });

    test(
        'Local DB exportWorkingDb and importWorkingDb backup and restore inspector data completely',
        () async {
      final localDb = await LocalDatabaseService.getDb();
      final uniqueAlias =
          'BC-LOCAL-BACKUP-${DateTime.now().microsecondsSinceEpoch}';

      await localDb.insert(
          'doors',
          {
            'pos': 42,
            'doorAlias': uniqueAlias,
            'doorNumber': 'T-LOCAL',
            'doorType': 'T30',
            'floor': 'EG',
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      await localDb.insert(
          'inspections',
          {
            'inspectionId': 555,
            'clientName': 'Local Backup Client',
            'objectAddress': 'Local Weg 2',
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      // 1. Export backup
      final backupPath =
          '${Directory.systemTemp.path}/test_local_backup_${DateTime.now().microsecondsSinceEpoch}.db';
      await LocalDatabaseService.exportWorkingDb(backupPath);
      final backupFile = File(backupPath);
      expect(await backupFile.exists(), true);
      expect(await backupFile.length(), greaterThan(0));

      // 2. Modify live working DB
      final liveLocalDb = await LocalDatabaseService.getDb();
      await liveLocalDb.insert('doors', {
        'pos': 999,
        'doorAlias':
            'BC-LOCAL-MODIFIED-${DateTime.now().microsecondsSinceEpoch}',
        'doorNumber': 'T-LOCAL-NEW',
        'doorType': 'T60',
      });

      // 3. Restore backup
      await LocalDatabaseService.importWorkingDb(backupPath);

      // 4. Verify restored state
      final restoredLocalDb = await LocalDatabaseService.getDb();
      final doors = await restoredLocalDb
          .query('doors', where: 'doorAlias = ?', whereArgs: [uniqueAlias]);
      expect(doors.isNotEmpty, true);
      expect(doors.first['doorNumber'], 'T-LOCAL');

      final newDoors = await restoredLocalDb
          .query('doors', where: 'doorNumber = ?', whereArgs: ['T-LOCAL-NEW']);
      expect(newDoors.isEmpty, true);

      await backupFile.delete();
    });

    test(
        'hasInspectionsToSave returns false when working DB is empty, and true when inspections or doors exist',
        () async {
      final localDb = await LocalDatabaseService.getDb();
      await localDb.delete('doors');
      await localDb.delete('inspections');

      // 1. Empty DB -> should return false (no request needed)
      final hasDataEmpty = await LocalDatabaseService.hasInspectionsToSave();
      expect(hasDataEmpty, isFalse);

      // 2. DB with inspection -> should return true (request needed)
      await localDb.insert('inspections', {
        'inspectionId': 999,
        'clientName': 'Client To Save',
        'objectAddress': 'Test Strasse 1',
      });
      final hasDataWithInsp = await LocalDatabaseService.hasInspectionsToSave();
      expect(hasDataWithInsp, isTrue);

      // 3. Clear inspections, add door -> should return true
      await localDb.delete('inspections');
      await localDb.insert('doors', {
        'pos': 1,
        'doorAlias': 'DOOR-SAVE-CHECK',
        'doorNumber': 'D-1',
      });
      final hasDataWithDoor = await LocalDatabaseService.hasInspectionsToSave();
      expect(hasDataWithDoor, isTrue);
    });
  });

  group('AppVersionDialog Widget Rendering Tests', () {
    testWidgets('AppVersionDialog renders app info and backup/restore controls',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppVersionDialog(isManager: false),
          ),
        ),
      );

      expect(find.text('App-Informationen'), findsOneWidget);
      expect(find.text('WartungsTool - Türinspektion'), findsOneWidget);
      expect(find.text('Datenbank-Verwaltung'), findsOneWidget);
      expect(find.text('Backup erstellen'), findsOneWidget);
      expect(find.text('Wiederherstellen'), findsOneWidget);
      expect(find.byIcon(Icons.backup_outlined), findsOneWidget);
      expect(find.byIcon(Icons.restore_page_outlined), findsOneWidget);
    });

    testWidgets('AppVersionDialog in Manager mode renders Manager-Portal info',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppVersionDialog(isManager: true),
          ),
        ),
      );

      expect(find.textContaining('Manager-Portal'), findsOneWidget);
      expect(find.text('Backup erstellen'), findsOneWidget);
      expect(find.text('Wiederherstellen'), findsOneWidget);
    });
  });
}
