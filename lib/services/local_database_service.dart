// Local Database Service for Inspector Mobile App (Offline Work)
// Handles temporary data for current inspections: doors, errors, requests

import 'package:create_inpection_report/models/models.dart';
import 'package:create_inpection_report/services/database_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabaseService {
  static Database? _db;

  static Future<Database> getDb() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'working.db');

    _db = await openDatabase(
      path,
      version: 2,  // Increment version for schema changes
      onCreate: (db, version) async {
        // Doors table (local copy for current inspection)
        await db.execute('''
          CREATE TABLE doors (
            id INTEGER PRIMARY KEY,
            pos INTEGER,
            doorNumber TEXT,
            floor TEXT,
            roomNumber TEXT,
            roomDesignation TEXT,
            doorType TEXT,
            wingCount INTEGER,
            material TEXT,
            manufacturer TEXT,
            dinConfiguration TEXT,
            closerType TEXT,
            closingSequenceSystem TEXT,
            lockDimensions TEXT,
            closerOnHingeSide INTEGER,
            closerOnOppositeSide INTEGER,
            lintelHeightUnder1m INTEGER,
            escapeDoorControl INTEGER,
            accessControl TEXT,
            escapeRouteSituation INTEGER,
            escapeRouteSignage INTEGER,
            blindCylinder INTEGER,
            pzCylinder INTEGER,
            fittingType TEXT,
            panicFunction TEXT,
            escapeDirectionRespected INTEGER,
            fullPanicStandWing INTEGER,
            doorFunctionOK INTEGER,            
            -- Add sync status for local DB
            syncStatus TEXT DEFAULT 'pending'  -- 'pending', 'synced'
          );
        ''');

        // Inspections table (local)
        await db.execute('''
          CREATE TABLE inspections (
            inspectionId INTEGER PRIMARY KEY AUTOINCREMENT,
            clientName TEXT,
            objectAddress TEXT,
            date TEXT,
            contactPerson TEXT,
            inspectorName TEXT,
            auftragsnummer TEXT,
            syncStatus TEXT DEFAULT 'pending'
          );
        ''');

        // InspectionDoors table (local)
        await db.execute('''
          CREATE TABLE inspection_doors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inspectionId INTEGER,
            doorId INTEGER,
            status TEXT,
            notes TEXT,
            attachments TEXT,
            syncStatus TEXT DEFAULT 'pending',
            FOREIGN KEY (inspectionId) REFERENCES inspections (inspectionId),
            FOREIGN KEY (doorId) REFERENCES doors (id)
          );
        ''');

        // InspectionDoorErrors table (local)
        await db.execute('''
          CREATE TABLE inspection_door_errors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inspectionDoorId INTEGER,
            errorId INTEGER,
            quantity INTEGER,
            severity TEXT,
            notes TEXT,
            resolutionStatus TEXT,
            syncStatus TEXT DEFAULT 'pending',
            FOREIGN KEY (inspectionDoorId) REFERENCES inspection_doors (id)
          );
        ''');

        // ErrorRequests table removed - functionality moved to error_catalog

        // Local error catalog (subset or copy from main, if needed)
        await db.execute('''
          CREATE TABLE error_catalog (
            errorId INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE,
            description TEXT,
            category TEXT,
            severity TEXT DEFAULT 'medium',
            recommendation TEXT DEFAULT '',
            normReference TEXT DEFAULT '',
            syncStatus TEXT DEFAULT 'synced',  -- Usually synced from main
            status TEXT NOT NULL DEFAULT 'Approved',
            requestedBy TEXT,
            requestDate TEXT,
            sourceInspectionDoorId INTEGER
          );
        ''');

        // Seed the error catalog on first create
        await _seedErrorCatalog(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Change 3: Remove metadata columns from doors table
          await db.execute('ALTER TABLE doors DROP COLUMN customerName');
          await db.execute('ALTER TABLE doors DROP COLUMN customerAddress');
          await db.execute('ALTER TABLE doors DROP COLUMN contactPerson');
          await db.execute('ALTER TABLE doors DROP COLUMN jobNumber');
          await db.execute('ALTER TABLE doors DROP COLUMN inspectionDate');
          await db.execute('ALTER TABLE doors DROP COLUMN inspectorName');

          // Change 1: Add consolidation columns to error_catalog
          try {
            await db.execute("ALTER TABLE error_catalog ADD COLUMN status TEXT NOT NULL DEFAULT 'Approved'");
            await db.execute("ALTER TABLE error_catalog ADD COLUMN requestedBy TEXT");
            await db.execute("ALTER TABLE error_catalog ADD COLUMN requestDate TEXT");
            await db.execute("ALTER TABLE error_catalog ADD COLUMN sourceInspectionDoorId INTEGER");
          } catch (e) {
            print('Local DB: Consolidation columns might already exist in error_catalog: $e');
          }

          // Remove error_requests table
          await db.execute('DROP TABLE IF EXISTS error_requests');

          print('Local Database upgraded to version $newVersion: Schema aligned with main DB.');
        }
      },
    );

    // This was the end of the class, but methods below were outside.
    return _db!;
  }

  // ─────────────────────────────────────────────────────────────
  // GENERAL UTILITIES
  // ─────────────────────────────────────────────────────────────

  // CRUD methods similar to original, but for local DB
  // e.g., insertDoor, getAllDoors, etc.
  // Add syncStatus handling

  static Future<void> markAsSynced(String table, int id, {String idColumn = 'id'}) async {
    final db = await getDb();
    await db.update(table, {'syncStatus': 'synced'}, where: '$idColumn = ?', whereArgs: [id]);
  }

  /// Pushes all pending records from working.db (Android) to door_inspection.db (Windows)
  static Future<void> syncToMainDatabase() async {
    try {
      print('Starting synchronization to main database...');
      int syncCount = 0;

      // 1. Sync Inspections
      final pendingInspections = await getPendingInspections();
      for (var inspection in pendingInspections) {
        final data = Map<String, dynamic>.from(inspection)..remove('syncStatus');
        await DatabaseService.insertInspection(data);
        await markAsSynced('inspections', inspection['inspectionId'], idColumn: 'inspectionId');
        syncCount++;
      }

      // 2. Sync Doors
      final pendingDoors = await getPendingDoors();
      for (var doorMap in pendingDoors) {
        final door = Door.fromMap(doorMap);
        // DatabaseService.insertDoor handles syncStatus removal internally now
        await DatabaseService.insertDoor(door);
        await markAsSynced('doors', door.id);
        syncCount++;
      }

      // 3. Sync Inspection Doors
      final pendingInspDoors = await getPendingInspectionDoors();
      for (var inspDoor in pendingInspDoors) {
        final data = Map<String, dynamic>.from(inspDoor)..remove('syncStatus');
        await DatabaseService.insertInspectionDoor(data);
        await markAsSynced('inspection_doors', inspDoor['id']);
        syncCount++;
      }

      // 4. Sync Inspection Door Errors
      final pendingErrors = await getPendingInspectionDoorErrors();
      for (var errorMap in pendingErrors) {
        final error = InspectionDoorError.fromMap(errorMap);
        // Ensure models without internal strip logic are handled
        await DatabaseService.insertInspectionDoorError(error);
        await markAsSynced('inspection_door_errors', errorMap['id']);
        syncCount++;
      }

      print('Synchronization finished. Synced $syncCount items.');
    } catch (e) {
      print('Critical error during synchronization: $e');
      // Rethrow to allow the UI to catch and show an error message
      rethrow;
    }
  }

  /// Downloads a complete job from the Main DB to the local Working DB.
  /// This is the primary "Manager -> Inspector" handoff logic.
  static Future<void> downloadJobData({
    required String clientName,
    required String jobNumber,
    required String date,
  }) async {
    try {
      print('Downloading Job-Specific Data: $clientName - $jobNumber...');

      // 1. Fetch job-specific data from Main DB
      final mainInspection = await DatabaseService.getInspectionByCriteria(
          clientName: clientName, jobNumber: jobNumber, date: date);
      final doorList = await DatabaseService.getDoorsByInspectionCriteria(
          clientName: clientName, jobNumber: jobNumber, date: date);
      if (mainInspection == null) throw Exception('Job not found in Main DB');

      // 2. Clear current Working DB to ensure isolation
      await clearSyncedData();

      final db = await getDb();
      await db.transaction((txn) async {
        // 3. Populate local Inspection metadata
        await txn.insert('inspections', mainInspection, conflictAlgorithm: ConflictAlgorithm.replace);

        // 4. Populate local Doors
        for (var door in doorList) {
          await txn.insert('doors', door.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

      print('Download complete. Ready for offline inspection.');
    } catch (e) {
      print('Error downloading job: $e');
      rethrow;
    }
  }

  // Clear local data after sync
  static Future<void> clearSyncedData() async {
    final db = await getDb();
    await db.delete('doors'); // Clear all doors for a new job
    await db.delete('inspections'); // Clear all inspections
    await db.delete('inspection_doors'); // Clear all inspection_doors
    await db.delete('inspection_door_errors'); // Clear all inspection_door_errors
    
    // Note: error_catalog is NOT deleted here as it is global app data
    print('Local working.db cleared.');
  }

  // ─────────────────────────────────────────────────────────────
  // DOORS
  // ─────────────────────────────────────────────────────────────

  static Future<int> insertDoor(Door door) async {
    final db = await getDb();
    return await db.insert('doors', door.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getAllDoors() async {
    final db = await getDb();
    return await db.query('doors');
  }

  static Future<void> updateDoor(Door door) async {
    final db = await getDb();
    await db.update('doors', door.toMap(), where: 'id = ?', whereArgs: [door.id]);
  }

  static Future<void> deleteDoor(int id) async {
    final db = await getDb();
    await db.delete('doors', where: 'id = ?', whereArgs: [id]);
  }

  // ─────────────────────────────────────────────────────────────
  // INSPECTIONS
  // ─────────────────────────────────────────────────────────────

  static Future<int> insertInspection(Map<String, dynamic> inspection) async {
    final db = await getDb();
    return await db.insert('inspections', inspection, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ─────────────────────────────────────────────────────────────
  // INSPECTION DOORS
  // ─────────────────────────────────────────────────────────────

  // TODO: Add methods to retrieve inspection_doors for a given inspectionId
  // TODO: Add methods to update inspection_doors status

  static Future<int> insertInspectionDoor(Map<String, dynamic> inspectionDoor) async {
    final db = await getDb();
    return await db.insert('inspection_doors', inspectionDoor, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ─────────────────────────────────────────────────────────────
  // INSPECTION DOOR ERRORS (LOCAL)
  // ─────────────────────────────────────────────────────────────

  static Future<int> insertInspectionDoorError(InspectionDoorError error) async {
    final db = await getDb();
    return await db.insert(
      'inspection_door_errors',
      error.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // This method was missing its body in the previous diff, restoring it.
  static Future<List<InspectionDoorError>> getErrorsForInspectionDoor(int inspectionDoorId) async {
    final db = await getDb();
    final maps = await db.query(
      'inspection_door_errors',
      where: 'inspectionDoorId = ?',
      whereArgs: [inspectionDoorId],
    );
    return maps.map((m) => InspectionDoorError.fromMap(m)).toList();
  }

  static Future<List<Map<String, dynamic>>> getDetailedErrorsForInspectionDoor(int inspectionDoorId) async {
    final db = await getDb();
    return await db.rawQuery('''
      SELECT ide.*, ec.code, ec.description, ec.category
      FROM inspection_door_errors ide
      INNER JOIN error_catalog ec ON ide.errorId = ec.errorId
      WHERE ide.inspectionDoorId = ?
    ''', [inspectionDoorId]);
  }
  static Future<void> deleteInspectionDoorError(int id) async {
    final db = await getDb();
    await db.delete('inspection_door_errors', where: 'id = ?', whereArgs: [id]);
  }

  // ─────────────────────────────────────────────────────────────
  // SYNC STATUS QUERIES
  // ─────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> _getPending(String table) async {
    final db = await getDb();
    return await db.query(table, where: 'syncStatus = ?', whereArgs: ['pending']);
  }

  static Future<List<Map<String, dynamic>>> getPendingDoors() => _getPending('doors');
  static Future<List<Map<String, dynamic>>> getPendingInspections() => _getPending('inspections');
  static Future<List<Map<String, dynamic>>> getPendingInspectionDoors() => _getPending('inspection_doors');
  static Future<List<Map<String, dynamic>>> getPendingInspectionDoorErrors() => _getPending('inspection_door_errors');

  /// Returns the junction record for a door in a specific inspection
  static Future<Map<String, dynamic>?> getInspectionDoor(int inspectionId, int doorId) async {
    final db = await getDb();
    final maps = await db.query(
      'inspection_doors',
      where: 'inspectionId = ? AND doorId = ?',
      whereArgs: [inspectionId, doorId],
      limit: 1,
    );
    return maps.isNotEmpty ? maps.first : null;
  }

  // ─────────────────────────────────────────────────────────────
  // ERROR CATALOG (LOCAL COPY)
  // ─────────────────────────────────────────────────────────────

  /// Specifically refreshes the local error catalog from the main database
  /// without clearing other job-related data (doors, inspections).
  static Future<void> refreshLocalCatalogFromMain() async {
    try {
      print('Refreshing local error catalog from main database...');
      // Fetch current master list from main DB
      final masterCatalog = await DatabaseService.getAllErrorCatalog();
      
      // Delegate the insertion to the standard catalog update routine
      await insertErrorCatalogItems(masterCatalog);
      print('Catalog refresh complete. ${masterCatalog.length} items synchronized.');
    } catch (e) {
      print('Error refreshing catalog: $e');
      rethrow;
    }
  }

  static Future<List<ErrorCatalog>> searchErrorCatalog(String query) async {
    final db = await getDb();
    final maps = await db.query(
      'error_catalog',
      where: 'LOWER(code) LIKE LOWER(?) OR LOWER(description) LIKE LOWER(?)',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'category, code',
      limit: 50,
    );
    return maps.map((m) => ErrorCatalog.fromMap(m)).toList();
  }

  static Future<List<String>> getErrorCatalogCategories() async {
    final db = await getDb();
    final maps = await db.rawQuery(
      'SELECT DISTINCT category FROM error_catalog ORDER BY category ASC',
    );
    return maps.map((m) => m['category'] as String).toList();
  }

  static Future<List<ErrorCatalog>> getErrorCatalogByCategory(String category) async {
    final db = await getDb();
    final maps = await db.query(
      'error_catalog',
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'code',
    );
    return maps.map((m) => ErrorCatalog.fromMap(m)).toList();
  }

  /// Fetch a single catalog entry by its ID from the local copy.
  static Future<ErrorCatalog?> getErrorCatalogItemById(int errorId) async {
    final db = await getDb();
    final maps = await db.query(
      'error_catalog',
      where: 'errorId = ?',
      whereArgs: [errorId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ErrorCatalog.fromMap(maps.first);
  }

  /// Insert a list of error catalog items into the local DB.
  /// Used for synchronizing from the Main DB or saving provisional local errors.
  static Future<void> insertErrorCatalogItems(List<ErrorCatalog> items) async {
    final db = await getDb();
    await db.transaction((txn) async {
      await _batchInsertCatalog(txn, items, ConflictAlgorithm.replace);
    });
    print('Inserted ${items.length} error catalog items into local DB.');
  }

  // This helper method needs to be inside the class.
  static Future<void> _batchInsertCatalog(DatabaseExecutor db, List<ErrorCatalog> items, ConflictAlgorithm algorithm) async {
    final batch = db.batch();
    for (final item in items) {
      batch.insert('error_catalog', item.toMap(), conflictAlgorithm: algorithm);
    }
    await batch.commit(noResult: true);
  }

  // This helper method needs to be inside the class.
  static Future<void> _seedErrorCatalog(Database db) async {
    final standardErrors = DoorErrorCatalog.getStandardErrors();
    
    final existingCount = await db.rawQuery('SELECT COUNT(*) as count FROM error_catalog');
    final count = existingCount.first['count'] as int;
    if (count > 0) return;
    
    await db.transaction((txn) async {
      await _batchInsertCatalog(
        txn,
        standardErrors,
        ConflictAlgorithm.ignore,
      );
    });
  }
}