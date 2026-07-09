import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';

void main() {
  // Initialize Flutter binding so rootBundle (used by checkAndInitializeCatalog) is available
  TestWidgetsFlutterBinding.ensureInitialized();

  // Setup for Windows/Linux testing environment
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DatabaseService Catalog Init Tests', () {
    setUp(() async {
      // Start each test with an empty catalog table
      final db = await DatabaseService.getDb();
      await db.delete('error_catalog');
    });

    test('checkAndInitializeCatalog should populate DB from bundled asset when empty', () async {
      // Catalog table is empty after setUp — initialize from bundled error_catalog.csv asset
      await DatabaseService.checkAndInitializeCatalog();

      final catalog = await DatabaseService.getAllErrorCatalog();

      // The bundled CSV has at least 21 entries (codes 1..21); verify a known one
      expect(catalog.isNotEmpty, isTrue,
          reason: 'Catalog should be populated from the bundled asset');
      expect(
        catalog.any((item) => item.code == '1'),
        isTrue,
        reason: 'Entry with code "1" (Kein Zugang/Keine Prüfung) must be present',
      );
      expect(
        catalog.firstWhere((item) => item.code == '1').description,
        equals('Kein Zugang/Keine Prüfung'),
      );
    });

    test('checkAndInitializeCatalog should skip seeding when catalog already has entries', () async {
      // Pre-populate with one entry
      final db = await DatabaseService.getDb();
      await db.insert('error_catalog', {
        'code': 'EXISTING',
        'description': 'Pre-existing entry',
      });

      await DatabaseService.checkAndInitializeCatalog();

      final catalog = await DatabaseService.getAllErrorCatalog();

      // Should NOT have overwritten with bundled data — still only the pre-existing entry
      expect(catalog.length, equals(1));
      expect(catalog.first.code, equals('EXISTING'));
    });
  });
}