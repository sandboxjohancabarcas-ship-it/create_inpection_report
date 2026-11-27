import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/batch_migration_service.dart';
import 'package:wartungstool/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('BatchMigrationService Extension Validation Tests', () {
    test('isCompliantFile accurately identifies supported extensions', () {
      expect(BatchMigrationService.isCompliantFile('inspection_package.db'), isTrue);
      expect(BatchMigrationService.isCompliantFile('doors_export.db3'), isTrue);
      expect(BatchMigrationService.isCompliantFile('package.wartung'), isTrue);
      expect(BatchMigrationService.isCompliantFile('door_inventory.xlsx'), isTrue);
      expect(BatchMigrationService.isCompliantFile('macro_inventory.xlsm'), isTrue);
      expect(BatchMigrationService.isCompliantFile('macro_inventory.xlms'), isTrue);
      expect(BatchMigrationService.isCompliantFile('door_list.csv'), isTrue);
      expect(BatchMigrationService.isCompliantFile('image.png'), isFalse);
      expect(BatchMigrationService.isCompliantFile('customer_spec.pdf'), isFalse);
      expect(BatchMigrationService.isCompliantFile('notes.txt'), isFalse);
      expect(BatchMigrationService.isCompliantFile('archive.zip'), isFalse);
    });

    test('migrateSingleFile correctly skips unsupported files with itemized report', () async {
      final dummyFile = File('test_unsupported.txt');
      final result = await BatchMigrationService.migrateSingleFile(dummyFile);

      expect(result.isSkipped, isTrue);
      expect(result.isSuccess, isFalse);
      expect(result.fileName, 'test_unsupported.txt');
      expect(result.fileReports.length, 1);
      expect(result.fileReports.first.status, contains('Nicht unterstützt'));
    });

    test('migrateSingleFile recognizes and imports window inspection Excel correctly', () async {
      final db = await DatabaseService.getDb();
      await db.delete('inspections');
      await db.delete('windows');
      await db.delete('inspection_windows');
      await db.delete('inspection_window_errors');

      final windowExcel = File('test/test_data/test_template/24-00000-AB P-000000 Fensterliste Aktuell 20.08.2024.xlsx');
      final result = await BatchMigrationService.migrateSingleFile(windowExcel);

      expect(result.isSuccess, isTrue);
      expect(result.assetType, equals('window'));
      expect(result.isWindow, isTrue);
      expect(result.newWindowsCount, greaterThan(200));
      expect(result.totalItems, greaterThan(200));
      expect(result.newDoorsCount, equals(0));

      // Report verification
      final report = result.importReport;
      expect(report, isNotNull);
      expect(report!.effectiveAssetType, equals('window'));
      expect(report.isWindowReport, isTrue);
      expect(report.totalItemsProcessed, greaterThan(200));
      expect(report.newWindowsCount, greaterThan(200));
      expect(report.newDoorsCount, equals(0));
    });

    test('migrateSingleFile recognizes and imports RWA / smoke ventilation Excel correctly', () async {
      final db = await DatabaseService.getDb();
      await db.delete('inspections');
      await db.delete('inspection_rwa_errors');
      await db.delete('inspection_rwa_settings');
      await db.delete('inspection_rwa');
      await db.delete('rwa_systems');

      final rwaExcel = File('test/test_data/RWA-Anlagen/26-14517-AB P-000893 Checkliste RWA-Anlage-1 Gebäude G.xlsx');
      final result = await BatchMigrationService.migrateSingleFile(rwaExcel);

      expect(result.isSuccess, isTrue);
      expect(result.assetType, equals('rwa'));
      expect(result.isRwa, isTrue);
      expect(result.isWindow, isFalse);
      expect(result.newRwaCount, equals(1));
      expect(result.totalItems, equals(1));
      expect(result.newDoorsCount, equals(0));
      expect(result.newWindowsCount, equals(0));

      // Report verification
      final report = result.importReport;
      expect(report, isNotNull);
      expect(report!.effectiveAssetType, equals('rwa'));
      expect(report.isRwaReport, isTrue);
      expect(report.isWindowReport, isFalse);
      expect(report.totalItemsProcessed, equals(1));
      expect(report.newRwaCount, equals(1));
      expect(report.newDoorsCount, equals(0));
      expect(report.newWindowsCount, equals(0));
    });
  });
}
