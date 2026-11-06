import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/craftnote_models.dart';
import 'craftnote_api_service.dart';
import 'craftnote_credentials_service.dart';

/// Local high-performance SQLite cache and sync engine for Craftnote projects.
/// Enables instantaneous (< 5ms) project lookups across 10,000+ facilities without
/// streaming large datasets across HTTP on every search.
class CraftnoteProjectCacheService {
  static Database? _db;

  /// Custom path override for unit testing
  static String? testDbPath;

  /// In-memory override for test suite isolation
  static bool useInMemoryDb = false;

  static Future<String> _resolveDbPath() async {
    if (testDbPath != null) return testDbPath!;
    if (useInMemoryDb) return inMemoryDatabasePath;

    if (Platform.isWindows || Platform.isLinux) {
      try {
        final dir = await getApplicationSupportDirectory();
        final supportDir = Directory(p.join(dir.path, 'WartungsTool'));
        if (!await supportDir.exists()) {
          await supportDir.create(recursive: true);
        }
        return p.join(supportDir.path, 'craftnote_cache.db');
      } catch (_) {}
    }
    try {
      final dbPath = await getDatabasesPath();
      return p.join(dbPath, 'craftnote_cache.db');
    } catch (_) {
      return 'craftnote_cache.db';
    }
  }

  static Future<Database> getDb() async {
    if (_db != null && _db!.isOpen) return _db!;

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final path = await _resolveDbPath();
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
    );
    return _db!;
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS craftnote_projects (
        id TEXT PRIMARY KEY,
        name TEXT,
        orderNumber TEXT,
        street TEXT,
        zipcode TEXT,
        city TEXT,
        country TEXT,
        clientName TEXT,
        clientEmail TEXT,
        clientPhone TEXT,
        statusId TEXT,
        archived INTEGER DEFAULT 0,
        noteContent TEXT,
        lastSyncedAt INTEGER
      );
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cn_order ON craftnote_projects (orderNumber COLLATE NOCASE);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cn_archived ON craftnote_projects (archived);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cn_name ON craftnote_projects (name COLLATE NOCASE);');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS craftnote_cache_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      );
    ''');
  }

  /// Closes database connection (useful during teardown in tests)
  static Future<void> closeDb() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }

  /// Ensures initial historical dataset is loaded into the local SQLite table.
  /// If database table is empty, reads the bundled seed JSON and bulk-inserts
  /// records inside a high-speed SQLite transaction.
  static Future<bool> ensureSeeded({
    bool force = false,
    void Function(String message)? onProgress,
  }) async {
    final db = await getDb();
    final countResult =
        await db.rawQuery('SELECT COUNT(*) as count FROM craftnote_projects');
    final count = Sqflite.firstIntValue(countResult) ?? 0;

    if (count > 0 && !force) {
      return true;
    }

    onProgress?.call('Initialisiere lokalen Craftnote-Katalog...');

    String? jsonContent;

    // 1. Try loading from bundled Flutter assets
    try {
      jsonContent = await rootBundle.loadString('craftnote_projects_cache.json');
    } catch (_) {}

    // 2. Fallback to filesystem (CLI, desktop development, or tests)
    if (jsonContent == null || jsonContent.isEmpty) {
      final potentialFiles = [
        File('craftnote_projects_cache.json'),
        File('../craftnote_projects_cache.json'),
        File('assets/craftnote_projects_cache.json'),
      ];
      for (final f in potentialFiles) {
        if (f.existsSync()) {
          try {
            jsonContent = f.readAsStringSync();
            break;
          } catch (_) {}
        }
      }
    }

    if (jsonContent == null || jsonContent.isEmpty) {
      return false;
    }

    try {
      final dynamic decoded = jsonDecode(jsonContent);
      if (decoded is! List) return false;

      final list = decoded;
      final total = list.length;
      final now = DateTime.now().millisecondsSinceEpoch;

      onProgress?.call('Importiere $total Projekte in den lokalen Index...');

      // Bulk insert in SQLite transaction chunks of 500 for optimal performance & low RAM usage
      const chunkSize = 500;
      for (int i = 0; i < list.length; i += chunkSize) {
        final chunk = list.skip(i).take(chunkSize).toList();
        await db.transaction((txn) async {
          final batch = txn.batch();
          for (final item in chunk) {
            if (item is! Map<String, dynamic>) continue;
            final p = CraftnoteProject.fromJson(item);
            batch.rawInsert('''
              INSERT OR REPLACE INTO craftnote_projects (
                id, name, orderNumber, street, zipcode, city, country,
                clientName, clientEmail, clientPhone, statusId, archived, noteContent, lastSyncedAt
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', [
              p.id,
              p.name,
              p.orderNumber,
              p.street,
              p.zipcode,
              p.city,
              p.country,
              p.clientName,
              p.clientEmail,
              p.clientPhone,
              p.statusId,
              p.archived ? 1 : 0,
              p.noteContent,
              now,
            ]);
          }
          await batch.commit(noResult: true);
        });
      }

      await db.rawInsert('''
        INSERT OR REPLACE INTO craftnote_cache_meta (key, value)
        VALUES ('last_sync_time', ?)
      ''', [DateTime.now().toIso8601String()]);

      onProgress?.call('Katalog-Initialisierung abgeschlossen ($total Projekte).');
      return true;
    } catch (e) {
      print('[CraftnoteProjectCacheService] Error seeding cache: $e');
      return false;
    }
  }

  /// Instant < 5ms local lookup for project by orderNumber, UUID, or query.
  /// If not found in the local database, automatically falls back to an
  /// on-demand live cloud check for recent Craftnote active projects.
  static Future<CraftnoteProjectSearchResult> findProject(
    String queryOrOrder, {
    CraftnoteApiService? apiService,
    void Function(String message)? onProgress,
  }) async {
    final cleanInput = queryOrOrder.replaceAll('#', '').trim();
    if (cleanInput.isEmpty) {
      return const CraftnoteProjectSearchResult(
        errorMessage: 'Bitte geben Sie eine Auftragsnummer oder einen Suchbegriff ein.',
      );
    }

    // Ensure database exists and is pre-seeded
    await ensureSeeded(onProgress: onProgress);

    final db = await getDb();

    // 1. Direct query on exact orderNumber (fastest, indexed)
    List<Map<String, dynamic>> results = await db.rawQuery(
      'SELECT * FROM craftnote_projects WHERE orderNumber = ? COLLATE NOCASE LIMIT 1',
      [cleanInput],
    );

    // 2. Fallback query on project UUID or name / partial order
    if (results.isEmpty) {
      results = await db.rawQuery(
        '''
        SELECT * FROM craftnote_projects 
        WHERE id = ? 
           OR orderNumber LIKE ? 
           OR name LIKE ?
        LIMIT 1
        ''',
        [cleanInput, '%$cleanInput%', '%$cleanInput%'],
      );
    }

    if (results.isNotEmpty) {
      final project = _mapRowToProject(results.first);

      if (project.archived) {
        return CraftnoteProjectSearchResult(
          archivedProject: project,
          isArchived: true,
          errorMessage:
              'Das Craftnote-Projekt "${project.name}" (#${project.orderNumber.isNotEmpty ? project.orderNumber : project.id}) ist bereits archiviert und kann nicht mehr bearbeitet oder importiert werden.\n\nBitte aktivieren Sie das Projekt in Craftnote, falls es erneut bearbeitet werden soll.',
        );
      }

      return CraftnoteProjectSearchResult(
        activeProject: project,
        isArchived: false,
      );
    }

    // 3. Cache Miss: Perform on-demand live delta check against Craftnote Cloud
    final service = apiService ?? CraftnoteApiService();
    if (CraftnoteCredentialsService.isMockMode) {
      // In mock mode, defer directly to mock API service
      return await service.findProjectWithArchiveCheck(orderNumber: cleanInput);
    }

    onProgress?.call('Auftrag nicht im lokalen Index. Prüfe aktuelle Craftnote-Cloud...');

    try {
      // Fetch newest active projects (Page 1) to catch recently created orders
      final recentActive = await service.getProjects(limit: 100, status: 'active');
      if (recentActive.isNotEmpty) {
        await upsertProjects(recentActive);

        // Check if target project is in this recent batch
        final cleanLower = cleanInput.toLowerCase();
        final match = recentActive.firstWhere(
          (p) =>
              p.orderNumber.toLowerCase() == cleanLower ||
              p.id.toLowerCase() == cleanLower ||
              p.name.toLowerCase().contains(cleanLower),
          orElse: () => const CraftnoteProject(id: '', name: ''),
        );

        if (match.id.isNotEmpty) {
          if (match.archived) {
            return CraftnoteProjectSearchResult(
              archivedProject: match,
              isArchived: true,
              errorMessage:
                  'Das Craftnote-Projekt "${match.name}" (#${match.orderNumber}) ist bereits archiviert und kann nicht mehr bearbeitet oder importiert werden.\n\nBitte aktivieren Sie das Projekt in Craftnote, falls es erneut bearbeitet werden soll.',
            );
          }
          return CraftnoteProjectSearchResult(
            activeProject: match,
            isArchived: false,
          );
        }
      }

      // Check newest archived projects as secondary fallback
      onProgress?.call('Prüfe kürzlich archivierte Projekte...');
      final recentArchived =
          await service.getProjects(limit: 100, status: 'archived');
      if (recentArchived.isNotEmpty) {
        await upsertProjects(recentArchived);

        final cleanLower = cleanInput.toLowerCase();
        final matchArchived = recentArchived.firstWhere(
          (p) =>
              p.orderNumber.toLowerCase() == cleanLower ||
              p.id.toLowerCase() == cleanLower ||
              p.name.toLowerCase().contains(cleanLower),
          orElse: () => const CraftnoteProject(id: '', name: ''),
        );

        if (matchArchived.id.isNotEmpty) {
          return CraftnoteProjectSearchResult(
            archivedProject: matchArchived,
            isArchived: true,
            errorMessage:
                'Das Craftnote-Projekt "${matchArchived.name}" (#${matchArchived.orderNumber}) ist archiviert und kann nicht importiert werden.',
          );
        }
      }
    } catch (e) {
      print('[CraftnoteProjectCacheService] Live check fallback error: $e');
    }

    return CraftnoteProjectSearchResult(
      errorMessage:
          'Kein Craftnote-Projekt mit Auftragsnummer "$cleanInput" gefunden.\n'
          'Bitte überprüfen Sie die Nummer oder stellen Sie sicher, dass das Projekt in Craftnote angelegt wurde.',
    );
  }

  /// Bulk upserts fetched projects into the local SQLite cache table.
  static Future<void> upsertProjects(List<CraftnoteProject> projects) async {
    if (projects.isEmpty) return;
    final db = await getDb();
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final p in projects) {
        batch.rawInsert('''
          INSERT OR REPLACE INTO craftnote_projects (
            id, name, orderNumber, street, zipcode, city, country,
            clientName, clientEmail, clientPhone, statusId, archived, noteContent, lastSyncedAt
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          p.id,
          p.name,
          p.orderNumber,
          p.street,
          p.zipcode,
          p.city,
          p.country,
          p.clientName,
          p.clientEmail,
          p.clientPhone,
          p.statusId,
          p.archived ? 1 : 0,
          p.noteContent,
          now,
        ]);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Synchronizes all currently active projects (~520) from Craftnote into the cache
  /// using high-speed token cursor pagination (`paginationMode=token&startAfter=...`).
  static Future<int> syncActiveProjects({
    CraftnoteApiService? apiService,
    void Function(String message)? onProgress,
  }) async {
    final service = apiService ?? CraftnoteApiService();
    int totalSynced = 0;
    String? cursorId;
    const pageSize = 100;
    const maxPages = 15; // Safeguard (520 active projects take ~6 pages)

    onProgress?.call('Starte Synchronisation aktiver Projekte...');

    for (int page = 0; page < maxPages; page++) {
      onProgress?.call('Lade aktive Projekte... (Seite ${page + 1})');
      final pageProjects = await service.getProjects(
        limit: pageSize,
        status: 'active',
        startAfter: cursorId,
      );

      if (pageProjects.isEmpty) break;

      await upsertProjects(pageProjects);
      totalSynced += pageProjects.length;
      cursorId = pageProjects.last.id;

      if (pageProjects.length < pageSize) break;
    }

    final db = await getDb();
    await db.rawInsert('''
      INSERT OR REPLACE INTO craftnote_cache_meta (key, value)
      VALUES ('last_sync_time', ?)
    ''', [DateTime.now().toIso8601String()]);

    onProgress?.call('Synchronisation abgeschlossen: $totalSynced Projekte aktualisiert.');
    return totalSynced;
  }

  /// Returns total counts of cached projects and last synchronization timestamp.
  static Future<Map<String, dynamic>> getCacheStats() async {
    final db = await getDb();
    final totalRes =
        await db.rawQuery('SELECT COUNT(*) as count FROM craftnote_projects');
    final activeRes = await db.rawQuery(
        'SELECT COUNT(*) as count FROM craftnote_projects WHERE archived = 0');
    final archivedRes = await db.rawQuery(
        'SELECT COUNT(*) as count FROM craftnote_projects WHERE archived = 1');
    final metaRes = await db.rawQuery(
        "SELECT value FROM craftnote_cache_meta WHERE key = 'last_sync_time' LIMIT 1");

    return {
      'total': Sqflite.firstIntValue(totalRes) ?? 0,
      'active': Sqflite.firstIntValue(activeRes) ?? 0,
      'archived': Sqflite.firstIntValue(archivedRes) ?? 0,
      'lastSync': metaRes.isNotEmpty ? metaRes.first['value'] : null,
    };
  }

  static CraftnoteProject _mapRowToProject(Map<String, dynamic> row) {
    return CraftnoteProject(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      orderNumber: row['orderNumber']?.toString() ?? '',
      street: row['street']?.toString() ?? '',
      zipcode: row['zipcode']?.toString() ?? '',
      city: row['city']?.toString() ?? '',
      country: row['country']?.toString() ?? '',
      clientName: row['clientName']?.toString() ?? '',
      clientEmail: row['clientEmail']?.toString(),
      clientPhone: row['clientPhone']?.toString(),
      statusId: row['statusId']?.toString(),
      archived: row['archived'] == 1,
      noteContent: row['noteContent']?.toString(),
    );
  }
}
