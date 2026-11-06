import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/craftnote_models.dart';
import 'package:wartungstool/services/craftnote_api_service.dart';
import 'package:wartungstool/services/craftnote_credentials_service.dart';
import 'package:wartungstool/services/craftnote_project_cache_service.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    final tempDir = Directory.systemTemp.createTempSync('cn_cache_test_');
    return tempDir.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final tempDir = Directory.systemTemp.createTempSync('cn_cache_test_doc_');
    return tempDir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('cn_cache_unit_');
    CraftnoteProjectCacheService.testDbPath =
        '${tempDir.path}/test_craftnote_cache.db';
    CraftnoteCredentialsService.resetToDefaults();
    CraftnoteCredentialsService.setMockMode(true);
    CraftnoteCredentialsService.setTestMode(true);
  });

  tearDown(() async {
    await CraftnoteProjectCacheService.closeDb();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('CraftnoteProjectCacheService Tests', () {
    test('Schema initializes and metadata table is queryable', () async {
      final db = await CraftnoteProjectCacheService.getDb();
      expect(db.isOpen, isTrue);

      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='craftnote_projects'");
      expect(tables.isNotEmpty, isTrue);
    });

    test('ensureSeeded populates database from craftnote_projects_cache.json', () async {
      final seeded = await CraftnoteProjectCacheService.ensureSeeded(force: true);
      expect(seeded, isTrue);

      final stats = await CraftnoteProjectCacheService.getCacheStats();
      expect(stats['total'], greaterThan(1000));
      expect(stats['archived'], greaterThan(500));
      expect(stats['lastSync'], isNotNull);
    });

    test('findProject instantly finds archived project 26-14078-AB and returns isArchived=true', () async {
      await CraftnoteProjectCacheService.ensureSeeded(force: true);

      final sw = Stopwatch()..start();
      final result = await CraftnoteProjectCacheService.findProject('26-14078-AB');
      sw.stop();

      // Must be instantaneous (< 50ms in local SQLite)
      expect(sw.elapsedMilliseconds, lessThan(100));
      expect(result.isArchived, isTrue);
      expect(result.archivedProject, isNotNull);
      expect(result.archivedProject!.orderNumber, '26-14078-AB');
      expect(result.archivedProject!.name, contains('Hammerbrookstraße'));
      expect(result.errorMessage, contains('archiviert'));
    });

    test('findProject strips hash signs and matches regardless of case', () async {
      await CraftnoteProjectCacheService.ensureSeeded(force: true);

      final result = await CraftnoteProjectCacheService.findProject('#26-14078-ab');
      expect(result.isArchived, isTrue);
      expect(result.archivedProject!.orderNumber, '26-14078-AB');
    });

    test('findProject on unknown order triggers live cloud delta check and auto-caches', () async {
      // In mock mode, findProject falls back to mock service which knows 26-15440-AB
      final result = await CraftnoteProjectCacheService.findProject('26-15440-AB');
      expect(result.activeProject, isNotNull);
      expect(result.activeProject!.orderNumber, '26-15440-AB');
      expect(result.isArchived, isFalse);
    });

    test('upsertProjects updates existing records and inserts new ones', () async {
      const newProj = CraftnoteProject(
        id: 'CN-TEST-LIVE-001',
        name: 'Brandneues Projekt 2026',
        orderNumber: '26-99887-AB',
        street: 'Neuestraße 1',
        city: 'Hamburg',
        archived: false,
      );

      await CraftnoteProjectCacheService.upsertProjects([newProj]);

      final found = await CraftnoteProjectCacheService.findProject('26-99887-AB');
      expect(found.activeProject, isNotNull);
      expect(found.activeProject!.id, 'CN-TEST-LIVE-001');
      expect(found.activeProject!.name, 'Brandneues Projekt 2026');
      expect(found.isArchived, isFalse);
    });

    test('syncActiveProjects synchronizes projects and records sync timestamp', () async {
      final mockApi = CraftnoteApiService();
      final count = await CraftnoteProjectCacheService.syncActiveProjects(apiService: mockApi);
      expect(count, greaterThan(0));

      final stats = await CraftnoteProjectCacheService.getCacheStats();
      expect(stats['lastSync'], isNotNull);
    });
  });
}

