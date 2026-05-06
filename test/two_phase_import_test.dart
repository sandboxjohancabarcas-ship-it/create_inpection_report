import 'package:flutter_test/flutter_test.dart';
import 'package:create_inpection_report/models/error_catalog.dart';
import 'package:create_inpection_report/services/database_service.dart';

void main() {
  group('Two-Phase Import Tests', () {
    setUp(() async {
      // Clear database before each test
      await DatabaseService.clearErrorCatalog();
    });

    test('Phase 1: Non-conflict items import immediately', () async {
      // Create test data with no conflicts
      final testData = [
        ErrorCatalog(
          code: 'TEST-001',
          description: 'Test error 1',
          category: 'Test',
          severity: 'medium',
        ),
        ErrorCatalog(
          code: 'TEST-002', 
          description: 'Test error 2',
          category: 'Test',
          severity: 'high',
        ),
      ];

      // Phase 1: Import non-conflict items
      final result = await DatabaseService.mergeErrorCatalog(testData);

      // Verify Phase 1 results
      expect(result.insertedCount, equals(2));
      expect(result.conflicts.length, equals(0));
      expect(result.duplicateCount, equals(0));

      // Verify items are actually in database
      final catalogItems = await DatabaseService.getAllErrorCatalogItems();
      expect(catalogItems.length, equals(2));
      expect(catalogItems.any((item) => item.code == 'TEST-001'), isTrue);
      expect(catalogItems.any((item) => item.code == 'TEST-002'), isTrue);
    });

    test('Phase 2: Conflicts handled separately from successful imports', () async {
      // First, insert some existing data
      final existingData = [
        ErrorCatalog(
          code: 'EXIST-001',
          description: 'Existing error',
          category: 'Existing',
          severity: 'medium',
        ),
      ];
      await DatabaseService.insertErrorCatalogItem(existingData[0]);

      // Create test data with conflicts and non-conflicts
      final testData = [
        ErrorCatalog(
          code: 'NEW-001',
          description: 'New error 1',
          category: 'New',
          severity: 'medium',
        ),
        ErrorCatalog(
          code: 'EXIST-001',
          description: 'Existing error - MODIFIED',
          category: 'Modified',
          severity: 'high', // Different severity creates conflict
        ),
        ErrorCatalog(
          code: 'NEW-002',
          description: 'New error 2',
          category: 'New',
          severity: 'low',
        ),
      ];

      // Phase 1: Import - should import non-conflicts, identify conflicts
      final result = await DatabaseService.mergeErrorCatalog(testData);

      // Verify Phase 1 results
      expect(result.insertedCount, equals(2)); // NEW-001 and NEW-002
      expect(result.conflicts.length, equals(1)); // EXIST-001 conflict
      expect(result.conflicts.first.code, equals('EXIST-001'));

      // Verify non-conflict items are in database
      final catalogItems = await DatabaseService.getAllErrorCatalogItems();
      expect(catalogItems.length, equals(3)); // 1 existing + 2 new
      expect(catalogItems.any((item) => item.code == 'NEW-001'), isTrue);
      expect(catalogItems.any((item) => item.code == 'NEW-002'), isTrue);
      expect(catalogItems.any((item) => item.code == 'EXIST-001'), isTrue);
    });

    test('Conflict resolution preserves successful imports', () async {
      // Setup existing data
      final existingData = [
        ErrorCatalog(
          code: 'EXIST-001',
          description: 'Existing error',
          category: 'Existing',
          severity: 'medium',
        ),
      ];
      await DatabaseService.insertErrorCatalogItem(existingData[0]);

      // Create test data with conflicts and non-conflicts
      final testData = [
        ErrorCatalog(
          code: 'NEW-001',
          description: 'New error 1',
          category: 'New',
          severity: 'medium',
        ),
        ErrorCatalog(
          code: 'EXIST-001',
          description: 'Existing error - MODIFIED',
          category: 'Modified',
          severity: 'high',
        ),
      ];

      // Phase 1: Import
      final result = await DatabaseService.mergeErrorCatalog(testData);
      
      // Verify non-conflict imported
      expect(result.insertedCount, equals(1));
      expect(result.conflicts.length, equals(1));

      // Simulate conflict resolution cancellation (do nothing with conflicts)
      // The successful import should remain
      final catalogItems = await DatabaseService.getAllErrorCatalogItems();
      expect(catalogItems.length, equals(2)); // 1 existing + 1 new
      expect(catalogItems.any((item) => item.code == 'NEW-001'), isTrue);
      
      // Verify the existing item is unchanged
      final existingItem = catalogItems.firstWhere((item) => item.code == 'EXIST-001');
      expect(existingItem.description, equals('Existing error'));
      expect(existingItem.severity, equals('medium'));
    });

    test('Duplicate handling works correctly', () async {
      // Setup existing data
      final existingData = [
        ErrorCatalog(
          code: 'DUPLICATE-001',
          description: 'Duplicate error',
          category: 'Duplicate',
          severity: 'medium',
        ),
      ];
      await DatabaseService.insertErrorCatalogItem(existingData[0]);

      // Create test data with exact duplicate and new item
      final testData = [
        ErrorCatalog(
          code: 'NEW-001',
          description: 'New error 1',
          category: 'New',
          severity: 'medium',
        ),
        ErrorCatalog(
          code: 'DUPLICATE-001',
          description: 'Duplicate error',
          category: 'Duplicate',
          severity: 'medium',
        ),
      ];

      // Phase 1: Import
      final result = await DatabaseService.mergeErrorCatalog(testData);

      // Verify results
      expect(result.insertedCount, equals(1)); // Only NEW-001
      expect(result.duplicateCount, equals(1)); // DUPLICATE-001
      expect(result.conflicts.length, equals(0));

      // Verify database state
      final catalogItems = await DatabaseService.getAllErrorCatalogItems();
      expect(catalogItems.length, equals(2)); // 1 existing + 1 new
    });

    test('Description conflict detection works', () async {
      // Setup existing data
      final existingData = [
        ErrorCatalog(
          code: 'EXIST-001',
          description: 'Same description',
          category: 'Existing',
          severity: 'medium',
        ),
      ];
      await DatabaseService.insertErrorCatalogItem(existingData[0]);

      // Create test data with same description but different code
      final testData = [
        ErrorCatalog(
          code: 'DIFFERENT-CODE',
          description: 'Same description',
          category: 'New',
          severity: 'high',
        ),
      ];

      // Phase 1: Import
      final result = await DatabaseService.mergeErrorCatalog(testData);

      // Should detect description conflict
      expect(result.insertedCount, equals(0));
      expect(result.conflicts.length, equals(1));
      expect(result.conflicts.first.reason, contains('same description has a different code'));
    });
  });
}
