import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'dart:io';

void main() {
  // Setup for Windows/Linux testing environment
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DatabaseService CSV Import Tests', () {
    const String csvPath = 'error_catalog.csv';

    setUp(() async {
      // Ensure we start with a clean state for the test
      if (await File(csvPath).exists()) await File(csvPath).delete();
      // Note: You would typically point DatabaseService to a temporary test DB here
    });

    tearDown(() async {
      if (await File(csvPath).exists()) await File(csvPath).delete();
    });

    test('checkAndInitializeCatalog should populate DB from CSV when empty', () async {
      // 1. Create a dummy CSV file in the root
      final csvFile = File(csvPath);
      await csvFile.writeAsString(
        'code,description,category,severity,recommendation\n'
        'TEST-001,Test Error Description,TestCategory,high,TestRecommendation'
      );

      // 2. Run the initialization logic
      // Assuming checkAndInitializeCatalog is the method name in DatabaseService
      await DatabaseService.checkAndInitializeCatalog();

      // 3. Verify the data was inserted
      final catalog = await DatabaseService.getAllErrorCatalog();
      
      expect(catalog.any((item) => item.code == 'TEST-001'), isTrue);
      expect(catalog.firstWhere((item) => item.code == 'TEST-001').description, 
             equals('Test Error Description'));
    });
  });
}