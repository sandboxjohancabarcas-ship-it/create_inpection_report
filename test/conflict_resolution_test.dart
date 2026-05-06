import 'package:flutter_test/flutter_test.dart';
import 'package:create_inpection_report/models/error_catalog.dart';
import 'package:create_inpection_report/services/database_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Initialize sqflite for testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ErrorCatalog Model Tests', () {
    test('isSameContent returns true for identical entries', () {
      // Test: ErrorCatalog.isSameContent() method
      // Functionality: Compares all import-relevant fields for equality
      // How: Create two identical ErrorCatalog objects and verify isSameContent returns true
      final error1 = ErrorCatalog(
        code: 'TEST-001',
        description: 'Test error',
        category: 'Test',
        severity: 'medium',
        recommendation: 'Fix it',
        normReference: 'DIN 123',
      );

      final error2 = ErrorCatalog(
        code: 'TEST-001',
        description: 'Test error',
        category: 'Test',
        severity: 'medium',
        recommendation: 'Fix it',
        normReference: 'DIN 123',
      );

      expect(error1.isSameContent(error2), true);
    });

    test('isSameContent returns false for different entries', () {
      // Test: ErrorCatalog.isSameContent() method
      // Functionality: Detects differences in any import-relevant field
      // How: Create two ErrorCatalog objects with different severity and verify isSameContent returns false
      final error1 = ErrorCatalog(
        code: 'TEST-001',
        description: 'Test error',
        category: 'Test',
        severity: 'medium',
        recommendation: 'Fix it',
        normReference: 'DIN 123',
      );

      final error2 = ErrorCatalog(
        code: 'TEST-001',
        description: 'Test error',
        category: 'Test',
        severity: 'high', // Different severity
        recommendation: 'Fix it',
        normReference: 'DIN 123',
      );

      expect(error1.isSameContent(error2), false);
    });
  });

  group('Database Merge Tests', () {
    late Database db;

    setUp(() async {
      // Create in-memory database for testing
      db = await openDatabase(':memory:', version: 7,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE error_catalog (
              errorId INTEGER PRIMARY KEY AUTOINCREMENT,
              code TEXT UNIQUE,
              description TEXT,
              category TEXT,
              severity TEXT DEFAULT 'medium',
              recommendation TEXT DEFAULT '',
              normReference TEXT DEFAULT ''
            );
          ''');
        });
    });

    tearDown(() async {
      await db.close();
    });

    test('mergeErrorCatalog inserts new entries successfully', () async {
      // Test: DatabaseService.mergeErrorCatalog() method
      // Functionality: Inserts new error catalog entries that don't conflict
      // How: Create new ErrorCatalog entries, call mergeErrorCatalog, verify they are inserted
      final errors = [
        ErrorCatalog(
          code: 'NEW-001',
          description: 'New error 1',
          category: 'Test',
          severity: 'low',
        ),
        ErrorCatalog(
          code: 'NEW-002',
          description: 'New error 2',
          category: 'Test',
          severity: 'high',
        ),
      ];

      final result = await db.transaction<ImportResult>((txn) async {
        return await DatabaseService.mergeErrorCatalog(errors);
      });

      expect(result.insertedCount, 2);
      expect(result.duplicateCount, 0);
      expect(result.conflicts.length, 0);

      // Verify entries were inserted
      final inserted = await db.query('error_catalog');
      expect(inserted.length, 2);
    });

    test('mergeErrorCatalog detects duplicate entries', () async {
      // Test: DatabaseService.mergeErrorCatalog() method
      // Functionality: Skips entries that are identical to existing ones
      // How: Insert an entry first, then try to merge the same entry, verify duplicate count increases
      final error = ErrorCatalog(
        code: 'DUP-001',
        description: 'Duplicate error',
        category: 'Test',
        severity: 'medium',
        recommendation: 'Fix it',
        normReference: 'DIN 123',
      );

      // Insert first
      await db.insert('error_catalog', error.toMap());

      // Try to merge the same entry
      final result = await db.transaction<ImportResult>((txn) async {
        return await DatabaseService.mergeErrorCatalog([error]);
      });

      expect(result.insertedCount, 0);
      expect(result.duplicateCount, 1);
      expect(result.conflicts.length, 0);

      // Verify only one entry exists
      final entries = await db.query('error_catalog');
      expect(entries.length, 1);
    });

    test('mergeErrorCatalog detects code conflicts', () async {
      // Test: DatabaseService.mergeErrorCatalog() method
      // Functionality: Detects when same code exists with different data
      // How: Insert entry with code 'CONFLICT-001', then try to merge different entry with same code
      final existing = ErrorCatalog(
        code: 'CONFLICT-001',
        description: 'Existing error',
        category: 'Test',
        severity: 'low',
      );

      final incoming = ErrorCatalog(
        code: 'CONFLICT-001', // Same code
        description: 'Different error', // Different description
        category: 'Test',
        severity: 'high',
      );

      // Insert existing
      await db.insert('error_catalog', existing.toMap());

      // Try to merge conflicting entry
      final result = await db.transaction<ImportResult>((txn) async {
        return await DatabaseService.mergeErrorCatalog([incoming]);
      });

      expect(result.insertedCount, 0);
      expect(result.duplicateCount, 0);
      expect(result.conflicts.length, 1);
      expect(result.conflicts[0].code, 'CONFLICT-001');
      expect(result.conflicts[0].reason, 'Existing entry with same code has different data');
    });

    test('mergeErrorCatalog detects description conflicts', () async {
      // Test: DatabaseService.mergeErrorCatalog() method
      // Functionality: Detects when same description exists with different code
      // How: Insert entry, then try to merge entry with same description but different code
      final existing = ErrorCatalog(
        code: 'DESC-001',
        description: 'Same description',
        category: 'Test',
        severity: 'medium',
      );

      final incoming = ErrorCatalog(
        code: 'DESC-002', // Different code
        description: 'Same description', // Same description
        category: 'Test',
        severity: 'medium',
      );

      // Insert existing
      await db.insert('error_catalog', existing.toMap());

      // Try to merge conflicting entry
      final result = await db.transaction<ImportResult>((txn) async {
        return await DatabaseService.mergeErrorCatalog([incoming]);
      });

      expect(result.insertedCount, 0);
      expect(result.duplicateCount, 0);
      expect(result.conflicts.length, 1);
      expect(result.conflicts[0].reason, 'Existing entry with same description has a different code (DESC-001)');
    });
  });

  group('Conflict Resolution Tests', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(':memory:', version: 7,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE error_catalog (
              errorId INTEGER PRIMARY KEY AUTOINCREMENT,
              code TEXT UNIQUE,
              description TEXT,
              category TEXT,
              severity TEXT DEFAULT 'medium',
              recommendation TEXT DEFAULT '',
              normReference TEXT DEFAULT ''
            );
          ''');
        });
    });

    tearDown(() async {
      await db.close();
    });

    test('applyConflictResolutions replaces existing entry', () async {
      // Test: DatabaseService.applyConflictResolutions() method
      // Functionality: Replaces existing entry with incoming data when replaceExisting action chosen
      // How: Create conflict resolution with replaceExisting action, apply it, verify entry is updated
      final existing = ErrorCatalog(
        code: 'REPLACE-001',
        description: 'Old description',
        category: 'Test',
        severity: 'low',
      );

      final incoming = ErrorCatalog(
        code: 'REPLACE-001',
        description: 'New description',
        category: 'Test',
        severity: 'high',
      );

      final conflict = ImportConflict(
        code: 'REPLACE-001',
        description: 'New description',
        incoming: incoming,
        existing: existing,
        reason: 'Test conflict',
      );

      final resolution = ConflictResolution(
        conflict: conflict,
        action: ResolutionAction.replaceExisting,
      );

      // Insert existing entry
      await db.insert('error_catalog', existing.toMap());

      // Apply resolution
      await db.transaction((txn) async {
        await DatabaseService.applyConflictResolutions([resolution]);
      });

      // Verify entry was replaced
      final updated = await db.query('error_catalog', where: 'code = ?', whereArgs: ['REPLACE-001']);
      expect(updated.length, 1);
      expect(updated[0]['description'], 'New description');
      expect(updated[0]['severity'], 'high');
    });

    test('applyConflictResolutions adds entry as new', () async {
      // Test: DatabaseService.applyConflictResolutions() method
      // Functionality: Adds incoming entry with new code when addAsNew action chosen
      // How: Create conflict resolution with addAsNew action and new code, apply it, verify new entry exists
      final existing = ErrorCatalog(
        code: 'ORIGINAL-001',
        description: 'Original error',
        category: 'Test',
        severity: 'medium',
      );

      final incoming = ErrorCatalog(
        code: 'ORIGINAL-001',
        description: 'New error',
        category: 'Test',
        severity: 'high',
      );

      final conflict = ImportConflict(
        code: 'ORIGINAL-001',
        description: 'New error',
        incoming: incoming,
        existing: existing,
        reason: 'Test conflict',
      );

      final resolution = ConflictResolution(
        conflict: conflict,
        action: ResolutionAction.addAsNew,
        newCode: 'NEW-001',
      );

      // Insert existing entry
      await db.insert('error_catalog', existing.toMap());

      // Apply resolution
      await db.transaction((txn) async {
        await DatabaseService.applyConflictResolutions([resolution]);
      });

      // Verify both entries exist
      final all = await db.query('error_catalog');
      expect(all.length, 2);

      final newEntry = all.firstWhere((row) => row['code'] == 'NEW-001');
      expect(newEntry['description'], 'New error');
      expect(newEntry['severity'], 'high');
    });

    test('applyConflictResolutions skips conflicting entry', () async {
      // Test: DatabaseService.applyConflictResolutions() method
      // Functionality: Leaves both entries unchanged when skip action chosen
      // How: Create conflict resolution with skip action, apply it, verify no changes made
      final existing = ErrorCatalog(
        code: 'SKIP-001',
        description: 'Existing error',
        category: 'Test',
        severity: 'medium',
      );

      final incoming = ErrorCatalog(
        code: 'SKIP-001',
        description: 'Incoming error',
        category: 'Test',
        severity: 'high',
      );

      final conflict = ImportConflict(
        code: 'SKIP-001',
        description: 'Incoming error',
        incoming: incoming,
        existing: existing,
        reason: 'Test conflict',
      );

      final resolution = ConflictResolution(
        conflict: conflict,
        action: ResolutionAction.skip,
      );

      // Insert existing entry
      await db.insert('error_catalog', existing.toMap());

      // Apply resolution
      await db.transaction((txn) async {
        await DatabaseService.applyConflictResolutions([resolution]);
      });

      // Verify only original entry exists unchanged
      final all = await db.query('error_catalog');
      expect(all.length, 1);
      expect(all[0]['description'], 'Existing error');
      expect(all[0]['severity'], 'medium');
    });
  });
}