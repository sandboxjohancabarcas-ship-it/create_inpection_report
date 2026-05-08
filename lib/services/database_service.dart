import 'package:create_inpection_report/models/models.dart';
import 'package:create_inpection_report/models/inspection.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> getDb() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'door_inspection.db');

    _db = await openDatabase(
      path,
      version: 10,
      onCreate: (db, version) async {
        // Doors table
        await db.execute('''
          CREATE TABLE doors (
            -- Door Technical Specifications
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
            doorFunctionOK INTEGER
          );
        ''');
        await db.execute('CREATE INDEX idx_doors_number ON doors (doorNumber)');

        // Inspections table
        await db.execute('''
          CREATE TABLE inspections (
            inspectionId INTEGER PRIMARY KEY,
            clientName TEXT,
            objectAddress TEXT,
            date TEXT,
            contactPerson TEXT,
            inspectorName TEXT,
            auftragsnummer TEXT
          );
        ''');
        await db.execute('CREATE INDEX idx_insp_client ON inspections (clientName)');
        await db.execute('CREATE INDEX idx_insp_job ON inspections (auftragsnummer)');
        await db.execute('CREATE INDEX idx_insp_date ON inspections (date)');

        // InspectionDoors table
        await db.execute('''
          CREATE TABLE inspection_doors (
            id INTEGER PRIMARY KEY,
            inspectionId INTEGER,
            doorId INTEGER,
            status TEXT,
            notes TEXT,
            attachments TEXT,
            FOREIGN KEY (inspectionId) REFERENCES inspections (inspectionId),
            FOREIGN KEY (doorId) REFERENCES doors (id)
          );
        ''');

        // ErrorCatalog table
        await db.execute('''
          CREATE TABLE error_catalog (
            errorId INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE,
            description TEXT,
            category TEXT,
            severity TEXT DEFAULT 'medium',
            recommendation TEXT DEFAULT '',
            normReference TEXT DEFAULT '',
            status TEXT NOT NULL DEFAULT 'Approved',
            requestedBy TEXT,
            requestDate TEXT,
            sourceInspectionDoorId INTEGER
          );
        ''');

        // InspectionDoorErrors table
        await db.execute('''
          CREATE TABLE inspection_door_errors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inspectionDoorId INTEGER,
            errorId INTEGER,
            quantity INTEGER,
            severity TEXT,
            notes TEXT,
            resolutionStatus TEXT,
            FOREIGN KEY (inspectionDoorId) REFERENCES inspection_doors (id),
            FOREIGN KEY (errorId) REFERENCES error_catalog (errorId)
          );
        ''');

        // ErrorRequests table removed - functionality moved to error_catalog
        // Seed the error catalog on first create
        await _seedErrorCatalog(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 10) {
          // Change 4: Performance Indices for high volume doors (2,000+ records)
          await db.execute('CREATE INDEX IF NOT EXISTS idx_doors_number ON doors (doorNumber)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_insp_client ON inspections (clientName)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_insp_job ON inspections (auftragsnummer)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_insp_date ON inspections (date)');
          print('Database version 10: Performance indices created.');
        }

        if (oldVersion < 9) {
          // Change 3: Remove metadata columns from doors table
          await db.execute('ALTER TABLE doors DROP COLUMN customerName');
          await db.execute('ALTER TABLE doors DROP COLUMN customerAddress');
          await db.execute('ALTER TABLE doors DROP COLUMN contactPerson');
          await db.execute('ALTER TABLE doors DROP COLUMN jobNumber');
          await db.execute('ALTER TABLE doors DROP COLUMN inspectionDate');
          await db.execute('ALTER TABLE doors DROP COLUMN inspectorName');
        }

        if (oldVersion < 8) {
          // Redundancy Removal: Drop the legacy inspection_errors table
          await db.execute('DROP TABLE IF EXISTS inspection_errors');
        }

        if (oldVersion < 7) {
          // Add missing columns to error_catalog table
          try {
            await db.execute('ALTER TABLE error_catalog ADD COLUMN severity TEXT DEFAULT \'medium\'');
          } catch (e) {
            print('Severity column already exists or other error: $e');
          }
          try {
            await db.execute('ALTER TABLE error_catalog ADD COLUMN recommendation TEXT DEFAULT \'\'');
          } catch (e) {
            print('Recommendation column already exists or other error: $e');
          }
          try {
            await db.execute('ALTER TABLE error_catalog ADD COLUMN normReference TEXT DEFAULT \'\'');
          } catch (e) {
            print('NormReference column already exists or other error: $e');
          }

          // Add consolidation columns for Change 1 if not already present
          try {
            await db.execute("ALTER TABLE error_catalog ADD COLUMN status TEXT NOT NULL DEFAULT 'Approved'");
            await db.execute("ALTER TABLE error_catalog ADD COLUMN requestedBy TEXT");
            await db.execute("ALTER TABLE error_catalog ADD COLUMN requestDate TEXT");
            await db.execute("ALTER TABLE error_catalog ADD COLUMN sourceInspectionDoorId INTEGER");
          } catch (e) {
            print('Consolidation columns might already exist: $e');
          }
          
          
          // Reseed the error catalog with new data
          await db.delete('error_catalog');
          await _seedErrorCatalog(db);
        }
      },
    );

    return _db!;
  }

  // ─────────────────────────────────────────────────────────────
  // DOORS
  // ─────────────────────────────────────────────────────────────

  static Future<int> insertDoor(Door door) async {
    final db = await getDb();
    // Strip syncStatus as main DB doesn't have this column
    final data = door.toMap()..remove('syncStatus');
    await db.insert( // This returns the ID of the inserted row
      'doors',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return door.id; // Return the ID that was used for insertion
  }

  // ─────────────────────────────────────────────────────────────
  // INSPECTIONS
  // ─────────────────────────────────────────────────────────────

  static Future<int> insertInspection(Map<String, dynamic> inspectionData) async {
    final db = await getDb();
    // Strip syncStatus as main DB doesn't have this column
    final data = Map<String, dynamic>.from(inspectionData)..remove('syncStatus');
    return await db.insert(
      'inspections',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns all inspections stored in the main database
  static Future<List<Map<String, dynamic>>> getAllInspections() async {
    final db = await getDb();
    return await db.query('inspections', orderBy: 'date DESC');
  }

  /// Fetches a specific inspection record by its identifying criteria
  static Future<Map<String, dynamic>?> getInspectionByCriteria({
    required String clientName,
    required String jobNumber,
    required String date,
  }) async {
    final db = await getDb();
    final List<Map<String, dynamic>> maps = await db.query(
      'inspections',
      where: 'clientName = ? AND auftragsnummer = ? AND date = ?',
      whereArgs: [clientName, jobNumber, date],
      limit: 1,
    );
    return maps.isNotEmpty ? maps.first : null;
  }

  static Future<int> insertInspectionDoor(Map<String, dynamic> data) async {
    final db = await getDb();
    // Strip syncStatus as main DB doesn't have this column
    final cleanData = Map<String, dynamic>.from(data)..remove('syncStatus');
    return await db.insert(
      'inspection_doors',
      cleanData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns doors filtered by specific inspection criteria (The "Download" filter)
  static Future<List<Door>> getDoorsByInspectionCriteria({
    required String clientName,
    required String jobNumber,
    required String date,
  }) async {
    final db = await getDb();
    
    // Perform a three-way join to isolate the doors for a specific job
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT d.* 
      FROM doors d
      INNER JOIN inspection_doors id ON d.id = id.doorId
      INNER JOIN inspections i ON i.inspectionId = id.inspectionId
      WHERE i.clientName = ? 
        AND i.auftragsnummer = ? 
        AND i.date = ?
    ''', [clientName, jobNumber, date]);

    if (maps.isEmpty) {
      print('No doors found for $clientName / $jobNumber');
    }
    return maps.map((map) => Door.fromMap(map)).toList();
  }

  static Future<List<Door>> getAllDoors() async {
    final db = await getDb();
    final maps = await db.query('doors');
    return maps.map((map) => Door.fromMap(map)).toList();
  }

  static Future<void> updateDoor(Door door) async {
    final db = await getDb();
    await db.update(
      'doors',
      door.toMap(),
      where: 'id = ?',
      whereArgs: [door.id],
    );
  }

  static Future<void> deleteDoor(int id) async {
    final db = await getDb();
    await db.delete('doors', where: 'id = ?', whereArgs: [id]);
  }

  // ─────────────────────────────────────────────────────────────
  // ERROR CATALOG
  // ─────────────────────────────────────────────────────────────

  /// Return all entries for a specific category.
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

  static Future<void> deleteErrorCatalog(int errorId) async {
    final db = await getDb();
    await db.delete(
      'error_catalog',
      where: 'errorId = ?',
      whereArgs: [errorId],
    );
  }

  // Compatibility methods for legacy error management calls
  static Future<List<InspectionDoorError>> getInspectionErrorsForDoor(int doorId) async {
    final db = await getDb();
    final List<Map<String, dynamic>> maps = await db.query(
      'inspection_door_errors',
      where: 'inspectionDoorId = ?',
      whereArgs: [doorId],
    );
    return maps.map((m) => InspectionDoorError.fromMap(m)).toList();
  }

  static Future<int> insertInspectionError(InspectionDoorError error) async {
    return await insertInspectionDoorError(error);
  }

  /// Delete a door error (compatibility alias)
  static Future<void> deleteInspectionError(int id) async {
    await deleteInspectionDoorError(id);
  }

  static Future<void> updateInspectionErrorStatus(int id, String status) async {
    final db = await getDb();
    await db.update('inspection_door_errors', {'resolutionStatus': status}, where: 'id = ?', whereArgs: [id]);
  }

  /// Return all distinct categories in the catalog.
  static Future<List<String>> getErrorCatalogCategories() async {
    final db = await getDb();
    final maps = await db.rawQuery(
      'SELECT DISTINCT category FROM error_catalog ORDER BY category ASC',
    );
    return maps.map((m) => m['category'] as String).toList();
  }

  /// Fetch a single catalog entry by its ID.
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

  // ─────────────────────────────────────────────────────────────
  // INSPECTION DOOR ERRORS
  // ─────────────────────────────────────────────────────────────

  /// Save an error found on a door during an inspection.
  static Future<int> insertInspectionDoorError(
      InspectionDoorError error) async {
    final db = await getDb();
    // Strip syncStatus as main DB doesn't have this column
    final data = error.toMap()..remove('syncStatus');
    return await db.insert(
      'inspection_door_errors',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load all errors recorded for a specific inspection-door record.
  static Future<List<InspectionDoorError>> getErrorsForInspectionDoor(
      int inspectionDoorId) async {
    final db = await getDb();
    final maps = await db.query(
      'inspection_door_errors',
      where: 'inspectionDoorId = ?',
      whereArgs: [inspectionDoorId],
    );
    return maps.map((m) => InspectionDoorError.fromMap(m)).toList();
  }

  /// Delete a single error entry (e.g. inspector removes it before saving).
  static Future<void> deleteInspectionDoorError(int id) async {
    final db = await getDb();
    await db.delete(
      'inspection_door_errors',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> insertErrorCatalog(ErrorCatalog error) async {
    final db = await getDb();
    await db.insert(
      'error_catalog',
      error.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<ImportResult> mergeErrorCatalog(List<ErrorCatalog> errors) async {
    final db = await getDb();
    
    // Phase 1: Import all non-conflict items immediately
    final phase1Result = await _importNonConflictItems(db, errors);
    
    // Phase 2: Return conflicts for separate processing
    return phase1Result;
  }

  static Future<ImportResult> _importNonConflictItems(Database db, List<ErrorCatalog> errors) async {
    return await db.transaction<ImportResult>((txn) async {
      final existingRows = await txn.query('error_catalog');
      final existingByCode = <String, ErrorCatalog>{};
      final existingByDescription = <String, ErrorCatalog>{};

      for (final row in existingRows) {
        final item = ErrorCatalog.fromMap(row);
        existingByCode[item.code] = item;
        existingByDescription[item.description.toLowerCase()] = item;
      }

      int insertedCount = 0;
      int duplicateCount = 0;
      final conflicts = <ImportConflict>[];

      for (final error in errors) {
        final existingForCode = existingByCode[error.code];
        if (existingForCode != null) {
          if (existingForCode.isSameContent(error)) {
            duplicateCount++;
            continue;
          }

          conflicts.add(ImportConflict(
            code: error.code,
            description: error.description,
            incoming: error,
            existing: existingForCode,
            reason: 'Existing entry with same code has different data',
          ));
          continue;
        }

        final existingForDescription = existingByDescription[error.description.toLowerCase()];
        if (existingForDescription != null && existingForDescription.code != error.code) {
          conflicts.add(ImportConflict(
            code: error.code,
            description: error.description,
            incoming: error,
            existing: existingForDescription,
            reason: 'Existing entry with same description has a different code (${existingForDescription.code})',
          ));
          continue;
        }

        await txn.insert(
          'error_catalog',
          error.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        insertedCount++;
        existingByCode[error.code] = error;
        existingByDescription[error.description.toLowerCase()] = error;
      }

      return ImportResult(
        insertedCount: insertedCount,
        duplicateCount: duplicateCount,
        conflicts: conflicts,
      );
    });
  }

  static Future<void> applyConflictResolutions(List<ConflictResolution> resolutions) async {
    final db = await getDb();
    return await db.transaction((txn) async {
      for (final resolution in resolutions) {
        switch (resolution.action) {
          case ResolutionAction.keepExisting:
            // Do nothing - keep existing record
            break;

          case ResolutionAction.replaceExisting:
            // Update existing record with incoming data
            await txn.update(
              'error_catalog',
              resolution.conflict.incoming.toMap(),
              where: 'code = ?',
              whereArgs: [resolution.conflict.code],
            );
            break;

          case ResolutionAction.addAsNew:
            // Insert incoming record with new code
            final newError = resolution.conflict.incoming.copyWith(
              code: resolution.newCode ?? '${resolution.conflict.code}_new',
            );
            await txn.insert(
              'error_catalog',
              newError.toMap(),
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            break;

          case ResolutionAction.skip:
            // Do nothing - skip incoming record
            break;
        }
      }
    });
  }

  static Future<List<ErrorCatalog>> getAllErrorCatalog() async {
    final db = await getDb();
    final maps = await db.query('error_catalog', orderBy: 'category, code');
    return maps.map((m) => ErrorCatalog.fromMap(m)).toList();
  }

  /// Search error catalog by code or description
  static Future<List<ErrorCatalog>> searchErrorCatalog(String query) async {
    print('Database search for: "$query"');
    final db = await getDb();
    final maps = await db.query(
      'error_catalog',
      where: 'LOWER(code) LIKE LOWER(?) OR LOWER(description) LIKE LOWER(?)',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'category, code',
      limit: 50, // Limit results to prevent overflow
    );
    print('Database search returned ${maps.length} results');
    return maps.map((m) => ErrorCatalog.fromMap(m)).toList();
  }

  // ─────────────────────────────────────────────────────────────
  // SEED DATA
  // ─────────────────────────────────────────────────────────────

  static Future<void> _seedErrorCatalog(Database db) async {
    print('Seeding error catalog...');
    final standardErrors = DoorErrorCatalog.getStandardErrors();
    print('Found ${standardErrors.length} errors to seed');
    
    // Check if catalog already has data
    final existingCount = await db.rawQuery('SELECT COUNT(*) as count FROM error_catalog');
    final count = existingCount.first['count'] as int;
    print('Existing error catalog entries: $count');
    
    if (count > 0) {
      print('Error catalog already seeded, skipping...');
      return;
    }
    
    for (final error in standardErrors) {
      try {
        await db.insert(
          'error_catalog',
          error.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } catch (e) {
        print('Error seeding ${error.code}: $e');
      }
    }
    print('Error catalog seeding completed');
  }

  // Manual seeding method for testing
  static Future<void> seedErrorCatalogManually() async {
    final db = await getDb();
    
    // Clear existing catalog
    await db.delete('error_catalog');
    print('Cleared existing error catalog');
    
    // Seed with new data
    await _seedErrorCatalog(db);
    print('Manual seeding completed');
  }

  static Future<void> clearErrorCatalog() async {
    final db = await getDb();
    await db.delete('error_catalog');
    print('Error catalog cleared');
  }
}
