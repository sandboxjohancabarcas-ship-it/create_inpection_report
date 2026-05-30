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
          await db.execute('CREATE TABLE doors (id INTEGER PRIMARY KEY, doorAlias TEXT, roomDesignation TEXT, pos INTEGER, dinConfiguration TEXT, fittingType TEXT, closerType TEXT)');
          await db.execute('CREATE TABLE inspections (inspectionId INTEGER PRIMARY KEY, auftragsnummer TEXT)');
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
  });
}