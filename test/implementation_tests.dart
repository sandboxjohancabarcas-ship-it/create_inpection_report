import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/models/models.dart';
import 'dart:io';

void main() {
  // Setup for Windows/Desktop testing environment
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    // Start with a clean slate for each test
    // On Windows, we must close the database connection to release the file lock
    // before attempting to delete the physical file.
    await DatabaseService.closeDb();

    final dbPath = await getDatabasesPath();
    final path = '$dbPath/door_inspection.db';
    if (await File(path).exists()) await File(path).delete();
    await DatabaseService.getDb();
  });

  tearDown(() async {
    // Explicitly release file locks after each test to prevent PathAccessExceptions on Windows
    await DatabaseService.closeDb();
  });

  tearDownAll(() async {
    // Final cleanup: Remove all temporary database files created during testing
    final dbPath = await getDatabasesPath();
    final mainDb = File('$dbPath/door_inspection.db');
    if (await mainDb.exists()) await mainDb.delete();
  });

  group('Sync Logic Tests', () {
    // EASY: Verify that the Door Model correctly handles the Alias business key
    test('Easy: Door Model Alias Integrity', () {
      final door = Door(
        id: 1,
        pos: 1,
        doorAlias: 'KUNDE-ADRESSE-T01',
        doorNumber: 'T01',
        floor: 'EG',
        roomNumber: '1',
        roomDesignation: 'Flur',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Dorma',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: 'None',
        lockDimensions: '72/8',
        closerOnHingeSide: true,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: false,
        accessControl: 'None',
        escapeRouteSituation: true,
        escapeRouteSignage: true,
        blindCylinder: false,
        pzCylinder: true,
        fittingType: 'Drücker',
        panicFunction: 'E',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
      );
      
      final map = door.toMap();
      expect(map['doorAlias'], equals('KUNDE-ADRESSE-T01'));
      expect(Door.fromMap(map).doorAlias, equals('KUNDE-ADRESSE-T01'));
    });

    // MEDIUM: Verify Selective Export correctly "prunes" (deletes) unselected data
    test('Medium: Selective Export Pruning Logic', () async {
      final dbPath = await getDatabasesPath();
      final exportPath = '$dbPath/selective_export.db';
      if (await File(exportPath).exists()) await File(exportPath).delete();

      // 1. Setup local DB with 2 doors
      final lDb = await LocalDatabaseService.getDb();
      await lDb.insert('doors', {'doorNumber': 'D1', 'doorAlias': 'A1', 'pos': 1});
      await lDb.insert('doors', {'doorNumber': 'D2', 'doorAlias': 'A2', 'pos': 2});

      // 2. Export only the first door (ID 1)
      await LocalDatabaseService.exportSelectiveJobPackage([1], exportPath);

      // 3. Verify the exported file only contains 1 door
      final checkDb = await openDatabase(exportPath);
      final count = Sqflite.firstIntValue(await checkDb.rawQuery('SELECT COUNT(*) FROM doors'));
      await checkDb.close();
      
      expect(count, equals(1));
    });
  });
}