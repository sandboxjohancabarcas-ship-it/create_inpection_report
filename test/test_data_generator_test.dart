import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/test_data_generator.dart';
import 'dart:io';

void main() {
  // Initialize SQLite FFI for Desktop environment testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('TestDataGenerator Integration Test', () {
    setUp(() async {
      // Ensure a clean database state for testing the generator logic
      await DatabaseService.closeDb();
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/door_inspection.db';
      if (await File(path).exists()) await File(path).delete();
    });

    test('The generator should populate the Master DB with consistent records', () async {
      // Execute generation with small parameters for efficient testing
      await TestDataGenerator.generate(
        numCustomers: 1,
        numObjectsPerCustomer: 1,
        numDoorsPerObject: 2,
        numInspectionsPerObject: 1,
      );

      // Verify Door creation and alias logic
      final doors = await DatabaseService.getAllDoors();
      expect(doors.length, 2);
      expect(doors.first.doorAlias, 'IND-GEW-EG-101');

      // Verify Inspection metadata persistence with English keys (jobNumber)
      final inspections = await DatabaseService.searchInspections('');
      expect(inspections.length, 1);
      expect(inspections.first['jobNumber'], contains('AUFTRAG'));
    });
  });
}