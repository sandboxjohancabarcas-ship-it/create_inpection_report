import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/services/batch_migration_service.dart';

void main() {
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
  });
}
