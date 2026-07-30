import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/services/test_data_generator.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Import/Export Compatibility Verification', () {
    setUp(() async {
      // Clean Master DB file
      await DatabaseService.closeDb();
      final dbPath = await getDatabasesPath();
      final masterPath = p.join(dbPath, 'door_inspection.db');
      if (await File(masterPath).exists()) {
        await File(masterPath).delete();
      }

      // Clean Local DB file
      await LocalDatabaseService.closeDb();
      final localPath = p.join(dbPath, 'working.db');
      if (await File(localPath).exists()) {
        await File(localPath).delete();
      }
    });

    test('Flow test: generate -> downloadJobPackage -> export -> import', () async {
      // 1. Generate test data in master DB
      await TestDataGenerator.generate(
        numCustomers: 1,
        numObjectsPerCustomer: 1,
        numDoorsPerObject: 2,
        numInspectionsPerObject: 1,
      );

      final inspections = await DatabaseService.searchInspections('');
      expect(inspections.isNotEmpty, true);
      final inspectionId = inspections.first['inspectionId'] as int;

      // 2. Download Job Package to local DB
      await LocalDatabaseService.downloadJobPackage(inspectionIds: [inspectionId]);

      // 3. Export Working DB
      final dbPath = await getDatabasesPath();
      final exportPath = p.join(dbPath, 'export_test.db');
      if (await File(exportPath).exists()) {
        await File(exportPath).delete();
      }

      await LocalDatabaseService.exportWorkingDb(exportPath);
      expect(await File(exportPath).exists(), true);

      // 4. Try to import the exported DB into working.db
      // Let's first clean working.db so we can see if it gets successfully imported/restored
      await LocalDatabaseService.closeDb();
      final localPath = p.join(dbPath, 'working.db');
      if (await File(localPath).exists()) {
        await File(localPath).delete();
      }

      try {
        await LocalDatabaseService.importWorkingDb(exportPath);
        print('SUCCESSFULLY IMPORTED DATABASE!');
      } catch (e) {
        print('IMPORT FAILED WITH ERROR: $e');
        fail('Import failed: $e');
      } finally {
        if (await File(exportPath).exists()) {
          await File(exportPath).delete();
        }
      }
    });
  });
}
