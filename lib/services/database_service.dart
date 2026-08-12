import 'dart:io';
import 'package:wartungstool/models/models.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Master Database Service (Manager Role)
/// This is a stub to allow the project to compile for Windows.
class DatabaseService {
  static Database? _db;

  static Future<Database> getDb() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'door_inspection.db');
    print('[DatabaseService] Opening Master DB at: $path');

    _db = await openDatabase(
      path,
      version: 18, // v18: Added errorCode natural key to inspection_door_errors
      onCreate: (db, version) async {
        // Doors table
        await db.execute('''
          CREATE TABLE doors (
            -- Door Technical Specifications
            id INTEGER PRIMARY KEY,
            pos INTEGER,
            doorAlias TEXT UNIQUE,
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
        await db.execute('CREATE UNIQUE INDEX idx_doors_alias ON doors (doorAlias)');

        // Inspections table
        await db.execute('''
          CREATE TABLE inspections (
            inspectionId INTEGER PRIMARY KEY,
            clientName TEXT,
            objectAddress TEXT,
            date TEXT,
            contactPerson TEXT,
            inspectorName TEXT,
            jobNumber TEXT
          );
        ''');
        await db.execute('CREATE INDEX idx_insp_client ON inspections (clientName)');
        await db.execute('CREATE INDEX idx_insp_job ON inspections (jobNumber)');
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
            errorCode TEXT NOT NULL DEFAULT '',
            quantity INTEGER,
            severity TEXT,
            notes TEXT,
            resolutionStatus TEXT,
            attachments TEXT DEFAULT '',
            FOREIGN KEY (inspectionDoorId) REFERENCES inspection_doors (id),
            FOREIGN KEY (errorId) REFERENCES error_catalog (errorId)
          );
        ''');

        // ErrorRequests table removed - functionality moved to error_catalog
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Reordered to chronological sequence for data integrity
        if (oldVersion < 7) {
          try {
            await db.execute('ALTER TABLE error_catalog ADD COLUMN severity TEXT DEFAULT \'medium\'');
            await db.execute('ALTER TABLE error_catalog ADD COLUMN recommendation TEXT DEFAULT \'\'');
            await db.execute('ALTER TABLE error_catalog ADD COLUMN normReference TEXT DEFAULT \'\'');
            await db.execute("ALTER TABLE error_catalog ADD COLUMN status TEXT NOT NULL DEFAULT 'Approved'");
            await db.execute("ALTER TABLE error_catalog ADD COLUMN requestedBy TEXT");
            await db.execute("ALTER TABLE error_catalog ADD COLUMN requestDate TEXT");
            await db.execute("ALTER TABLE error_catalog ADD COLUMN sourceInspectionDoorId INTEGER");
          } catch (e) { print('Catalog migration warning: $e'); }
          
        }

        if (oldVersion < 8) {
          await db.execute('DROP TABLE IF EXISTS inspection_errors');
        }

        if (oldVersion < 9) {
          // Metadata removal from doors table - now handled in inspections table
          final cols = ['customerName', 'customerAddress', 'contactPerson', 'jobNumber', 'inspectionDate', 'inspectorName'];
          for (var col in cols) {
            try { await db.execute('ALTER TABLE doors DROP COLUMN $col'); } catch (_) {}
          }
        }

        if (oldVersion < 10) {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_doors_number ON doors (doorNumber)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_insp_client ON inspections (clientName)');
          // Handle the transition from German to English column naming in migrations
          try {
            await db.execute('CREATE INDEX IF NOT EXISTS idx_insp_job ON inspections (jobNumber)');
          } catch (_) {
            await db.execute('CREATE INDEX IF NOT EXISTS idx_insp_job ON inspections (auftragsnummer)');
          }
          await db.execute('CREATE INDEX IF NOT EXISTS idx_insp_date ON inspections (date)');
        }

        if (oldVersion < 11) {
          try {
            await db.execute('ALTER TABLE doors ADD COLUMN doorAlias TEXT');
            await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_doors_alias ON doors (doorAlias)');
          } catch (_) {}
        }

        if (oldVersion < 12) {
          await db.execute("UPDATE doors SET dinConfiguration = 'DIN L' WHERE dinConfiguration = 'L'");
          await db.execute("UPDATE doors SET dinConfiguration = 'DIN R' WHERE dinConfiguration = 'R'");
        }

        if (oldVersion < 16) {
          // Normalization of technical keys to match UI dropdowns exactly
          await db.execute("UPDATE doors SET closerType = 'TS93' WHERE closerType IN ('TS 5000', 'TS93 G') OR closerType IS NULL");
          await db.execute("UPDATE doors SET manufacturer = 'Dorma' WHERE manufacturer = 'HÖRMANN' OR manufacturer IS NULL");
          await db.execute("UPDATE doors SET fittingType = 'Drücker' WHERE fittingType = 'Drücker/Drücker' OR fittingType IS NULL");
        }

        if (oldVersion < 17) {
          try {
            await db.execute("ALTER TABLE inspection_door_errors ADD COLUMN attachments TEXT DEFAULT ''");
            print('[DatabaseService] Main DB upgraded to v17: attachments column added.');
          } catch (e) {
            print('Main DB migration warning (attachments): \$e');
          }
        }

        if (oldVersion < 18) {
          try {
            await db.execute("ALTER TABLE inspection_door_errors ADD COLUMN errorCode TEXT NOT NULL DEFAULT ''");
            // Backfill errorCode from error_catalog for existing rows
            await db.execute('''
              UPDATE inspection_door_errors
              SET errorCode = COALESCE(
                (SELECT code FROM error_catalog WHERE error_catalog.errorId = inspection_door_errors.errorId),
                ''
              )
              WHERE errorCode IS NULL OR errorCode = ''
            ''');
            print('[DatabaseService] Main DB upgraded to v18: errorCode column added and backfilled.');
          } catch (e) {
            print('Main DB migration warning (errorCode): \$e');
          }
        }
      },
    );

    await populateMissingAliases(_db!);

    return _db!;
  }

  static Future<void> populateMissingAliases(Database db, {bool isLocal = false}) async {
    final List<Map<String, dynamic>> rows = await db.rawQuery('''
      SELECT d.id, d.doorNumber, d.floor, i.clientName, i.objectAddress
      FROM doors d
      LEFT JOIN inspection_doors id ON d.id = id.doorId
      LEFT JOIN inspections i ON id.inspectionId = i.inspectionId
      WHERE d.doorAlias IS NULL
    ''');
    
    if (rows.isEmpty) return;
    
    print('[DatabaseService] Populating missing aliases for ${rows.length} doors (isLocal: $isLocal)...');
    
    for (final row in rows) {
      final id = row['id'] as int;
      final doorNumber = row['doorNumber'] as String? ?? '0';
      final floor = row['floor'] as String? ?? '';
      final clientName = row['clientName'] as String? ?? '';
      final objectAddress = row['objectAddress'] as String? ?? '';
      
      String generated = Door.generateAlias(clientName, objectAddress, doorNumber, floor: floor);
      if (generated.isEmpty) {
        generated = 'DOOR-$id';
      }
      
      // Ensure uniqueness
      String uniqueAlias = generated;
      int suffix = 1;
      while (true) {
        final existing = await db.query(
          'doors',
          columns: ['id'],
          where: 'doorAlias = ?',
          whereArgs: [uniqueAlias],
        );
        if (existing.isEmpty) {
          break;
        }
        // If it exists, append suffix, ensuring max 12 chars
        final suffixStr = '-$suffix';
        final maxBaseLen = 12 - suffixStr.length;
        final base = generated.length > maxBaseLen ? generated.substring(0, maxBaseLen) : generated;
        uniqueAlias = '$base$suffixStr';
        suffix++;
      }
      
      await db.update(
        'doors',
        {'doorAlias': uniqueAlias},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    print('[DatabaseService] Finished populating missing aliases.');
  }

  /// Safely deletes the database file from the system.
  static Future<void> clearDatabase() async {
    await closeDb();
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'door_inspection.db');
    print('[DatabaseService] Deleting database file at: $path');
    await deleteDatabase(path);
    print('Database cleared at: $path');
  }

  // ─────────────────────────────────────────────────────────────
  // DOORS
  // ─────────────────────────────────────────────────────────────

  /// Closes the database connection.
  /// Used primarily in tests to allow for clean setup/teardown.
  static Future<void> closeDb() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }

  static Future<int> insertDoor(Door door) async {
    final db = await getDb();
    if (door.id == null && door.doorAlias != null && door.doorAlias!.trim().isNotEmpty) {
      final existing = await db.query(
        'doors',
        columns: ['id'],
        where: 'doorAlias = ?',
        whereArgs: [door.doorAlias!.trim()],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final existingId = existing.first['id'] as int;
        final doorToUpdate = door.copyWith(id: existingId);
        await db.update(
          'doors',
          doorToUpdate.toMap(),
          where: 'id = ?',
          whereArgs: [existingId],
        );
        return existingId;
      }
    }
    final id = await db.insert(
      'doors',
      door.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  static Future<Door?> getDoorByAlias(String alias) async {
    final db = await getDb();
    final maps = await db.query('doors', where: 'doorAlias = ?', whereArgs: [alias], limit: 1);
    return maps.isNotEmpty ? Door.fromMap(maps.first) : null;
  }

  static Future<int> insertInspection(Map<String, dynamic> inspectionData) async {
    final db = await getDb();
    return await db.insert(
      'inspections',
      inspectionData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, dynamic>?> getInspectionById(int inspectionId) async {
    final db = await getDb();
    final maps = await db.query(
      'inspections',
      where: 'inspectionId = ?',
      whereArgs: [inspectionId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first;
  }

  static Future<void> updateInspection(Map<String, dynamic> inspectionData) async {
    final db = await getDb();
    final id = inspectionData['inspectionId'];
    if (id == null) return;
    await db.update(
      'inspections',
      inspectionData,
      where: 'inspectionId = ?',
      whereArgs: [id],
    );
  }

  /// Searches inspections by client name, job number, date, or door number.
  /// Limits results to 50 jobs for performance.
  static Future<List<Map<String, dynamic>>> searchInspections(String query) async {
    final db = await getDb();
    if (query.trim().isEmpty) {
      return await db.query('inspections', orderBy: 'date DESC', limit: 50);
    }

    final searchTerm = '%$query%';
    return await db.rawQuery('''
      SELECT DISTINCT i.* FROM inspections i
      LEFT JOIN inspection_doors id ON i.inspectionId = id.inspectionId
      LEFT JOIN doors d ON id.doorId = d.id
      WHERE i.clientName LIKE ? 
         OR i.jobNumber LIKE ? 
         OR i.date LIKE ? 
         OR i.objectAddress LIKE ? 
         OR d.doorNumber LIKE ?
      ORDER BY i.date DESC
      LIMIT 50
    ''', [searchTerm, searchTerm, searchTerm, searchTerm, searchTerm]);
  }

  /// Performs a global search across all doors in the master database.
  /// Using the doorAlias allows searching by Customer, Address, or Door Number.
  static Future<List<Door>> searchDoorsGlobal(String query) async {
    final db = await getDb();
    if (query.trim().isEmpty) {
      return await getAllDoors();
    }
    final searchTerm = '%$query%';
    final List<Map<String, dynamic>> results = await db.query(
      'doors',
      where: 'doorAlias LIKE ? OR doorNumber LIKE ? OR roomDesignation LIKE ?',
      whereArgs: [searchTerm, searchTerm, searchTerm],
      limit: 50,
    );
    return results.map((m) => Door.fromMap(m)).toList();
  }

  /// Fetches inspection IDs based on Client and Object.
  /// Allows for "Wide Spectrum" selection (Latest vs All History).
  static Future<List<int>> getInspectionIdsByCriteria({
    required String clientName,
    required String objectAddress,
    bool latestOnly = false,
  }) async {
    final db = await getDb();
    final List<Map<String, dynamic>> maps = await db.query(
      'inspections',
      columns: ['inspectionId'],
      where: 'clientName = ? AND objectAddress = ?',
      whereArgs: [clientName, objectAddress],
      orderBy: 'date DESC',
      limit: latestOnly ? 1 : null,
    );
    return maps.map((m) => m['inspectionId'] as int).toList();
  }

  /// Returns all doors associated with a list of inspection IDs.
  /// Supports optional query to search by door number, room description, room designation, error description/code/notes.
  static Future<List<Door>> getDoorsByInspectionIds(List<int> inspectionIds, {String query = ''}) async {
    if (inspectionIds.isEmpty) return [];
    final db = await getDb();
    final String idString = inspectionIds.join(',');
    final cleanQuery = query.trim();

    if (cleanQuery.isEmpty) {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT d.* 
        FROM doors d
        INNER JOIN inspection_doors id ON d.id = id.doorId
        WHERE id.inspectionId IN ($idString)
        ORDER BY d.pos ASC, d.doorNumber ASC
      ''');
      return maps.map((map) => Door.fromMap(map)).toList();
    }

    final searchTerm = '%$cleanQuery%';
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT DISTINCT d.* 
      FROM doors d
      INNER JOIN inspection_doors id ON d.id = id.doorId
      LEFT JOIN inspection_door_errors ide ON id.id = ide.inspectionDoorId
      LEFT JOIN error_catalog ec ON (ide.errorId = ec.errorId OR (ide.errorCode IS NOT NULL AND ide.errorCode != '' AND ide.errorCode = ec.code))
      WHERE id.inspectionId IN ($idString)
        AND (
          d.doorNumber LIKE ? 
          OR d.roomNumber LIKE ? 
          OR d.roomDesignation LIKE ?
          OR d.doorAlias LIKE ?
          OR d.floor LIKE ?
          OR id.notes LIKE ?
          OR ide.errorCode LIKE ?
          OR ide.notes LIKE ?
          OR ec.code LIKE ? 
          OR ec.description LIKE ?
          OR ec.category LIKE ?
        )
      ORDER BY d.pos ASC, d.doorNumber ASC
    ''', [
      searchTerm, searchTerm, searchTerm, searchTerm, searchTerm,
      searchTerm, searchTerm, searchTerm, searchTerm, searchTerm, searchTerm
    ]);

    return maps.map((map) => Door.fromMap(map)).toList();
  }

  /// Returns a map of doorId -> DoorErrorSummary for a given inspection ID.
  static Future<Map<int, DoorErrorSummary>> getDoorErrorSummariesForInspection(int inspectionId) async {
    final db = await getDb();
    final List<Map<String, dynamic>> rows = await db.rawQuery('''
      SELECT 
        id.doorId,
        COUNT(ide.id) AS total_errors,
        SUM(CASE WHEN LOWER(COALESCE(ide.resolutionStatus, 'open')) != 'resolved' THEN 1 ELSE 0 END) AS open_errors,
        SUM(CASE WHEN LOWER(COALESCE(ide.resolutionStatus, 'open')) = 'resolved' THEN 1 ELSE 0 END) AS resolved_errors
      FROM inspection_doors id
      LEFT JOIN inspection_door_errors ide ON id.id = ide.inspectionDoorId
      WHERE id.inspectionId = ?
      GROUP BY id.doorId
    ''', [inspectionId]);

    final Map<int, DoorErrorSummary> map = {};
    for (final row in rows) {
      final doorId = row['doorId'] as int?;
      if (doorId != null) {
        final total = (row['total_errors'] as num?)?.toInt() ?? 0;
        final open = (row['open_errors'] as num?)?.toInt() ?? 0;
        final resolved = (row['resolved_errors'] as num?)?.toInt() ?? 0;
        map[doorId] = DoorErrorSummary(
          totalErrors: total,
          openErrors: open,
          resolvedErrors: resolved,
        );
      }
    }
    return map;
  }


  static Future<int> insertInspectionDoor(Map<String, dynamic> data) async {
    final db = await getDb();
    return await db.insert(
      'inspection_doors',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Fetches all junction records for a specific inspection from Main DB
  static Future<List<Map<String, dynamic>>> getInspectionDoorsByInspectionId(int inspectionId) async {
    final db = await getDb();
    return await db.query(
      'inspection_doors',
      where: 'inspectionId = ?',
      whereArgs: [inspectionId],
    );
  }

  /// Fetches all errors for a set of inspection door IDs from Main DB
  static Future<List<Map<String, dynamic>>> getErrorsForInspectionDoorIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final db = await getDb();
    final String idString = ids.join(',');
    return await db.rawQuery('''
      SELECT ide.*,
             COALESCE(ec.code, ide.errorCode, 'UNKNOWN') AS code,
             COALESCE(ec.description, ide.notes, 'Keine Beschreibung') AS description
      FROM inspection_door_errors ide
      LEFT JOIN error_catalog ec ON ide.errorId = ec.errorId
      WHERE ide.inspectionDoorId IN ($idString)
    ''');
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
      whereArgs: [door.id!],
    );
  }

  static Future<void> deleteDoor(int id) async {
    final db = await getDb();
    await db.delete('doors', where: 'id = ?', whereArgs: [id]);
  }

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

  /// Fetches a single error catalog entry by its primary key.
  static Future<ErrorCatalog?> getErrorCatalogItemById(int id) async {
    final db = await getDb();
    final maps = await db.query(
      'error_catalog',
      where: 'errorId = ?',
      whereArgs: [id],
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
    return await db.insert(
      'inspection_door_errors',
      error.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> deleteInspectionDoorError(int id) async {
    final db = await getDb();
    await db.delete('inspection_door_errors', where: 'id = ?', whereArgs: [id]);
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

  /// Fetches detailed errors joined with error_catalog info for a single inspection door from Main DB.
  static Future<List<Map<String, dynamic>>> getDetailedErrorsForInspectionDoor(int inspectionDoorId) async {
    final db = await getDb();
    return await db.rawQuery('''
      SELECT ide.*,
             COALESCE(ec.code, ide.errorCode, 'UNKNOWN') AS code,
             COALESCE(ec.description, ide.notes, 'Keine Beschreibung') AS description,
             COALESCE(ec.category, '') AS category
      FROM inspection_door_errors ide
      LEFT JOIN error_catalog ec ON ide.errorId = ec.errorId
      WHERE ide.inspectionDoorId = ?
    ''', [inspectionDoorId]);
  }

  static Future<void> insertErrorCatalog(ErrorCatalog error) async {
    final db = await getDb();
    await db.insert(
      'error_catalog',
      error.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Search error catalog by code or description
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

  static Future<void> clearErrorCatalog() async {
    final db = await getDb();
    await db.delete('error_catalog');
  }

  /// Merges an inspection result package (.db file) from an inspector into the Master DB.
  /// Uses Job Number (auftragsnummer) and Door Alias as correlation keys.
  static Future<void> importAndMergePackage(String packagePath) async {
    final masterDb = await getDb();
    final packageDb = await openDatabase(packagePath, readOnly: true);

    try {
      await masterDb.transaction((txn) async {
        // 1. Get all data from package
        final pDoors = await packageDb.query('doors');
        final pInspections = await packageDb.query('inspections');
        final pJunctions = await packageDb.query('inspection_doors');
        final pErrors = await packageDb.query('inspection_door_errors');
        // Import ALL catalog entries (not just Pending) to enable errorId remapping
        final pCatalog = await packageDb.query('error_catalog');

        // 2. Merge ALL Catalog Entries and build catalogIdMap (packageId → masterId)
        //    Keyed by `code` so IDs are remapped correctly across different DBs.
        final Map<int, int> catalogIdMap = {};
        for (var row in pCatalog) {
          final packageCatalogId = row['errorId'] as int;
          final code = row['code'] as String? ?? '';
          final status = row['status'] as String? ?? 'Approved';
          final data = Map<String, dynamic>.from(row)..remove('errorId');
          int masterCatalogId;
          final existing = await txn.query('error_catalog',
              columns: ['errorId'], where: 'code = ?', whereArgs: [code], limit: 1);
          if (existing.isNotEmpty) {
            masterCatalogId = existing.first['errorId'] as int;
            // Only overwrite if the incoming entry is Pending (a new proposal)
            if (status == 'Pending') {
              await txn.update('error_catalog', data,
                  where: "errorId = ? AND status = 'Pending'",
                  whereArgs: [masterCatalogId]);
            }
          } else {
            masterCatalogId = await txn.insert(
                'error_catalog', data,
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          catalogIdMap[packageCatalogId] = masterCatalogId;
        }


        // 3. Merge Doors and create ID Mapping (Package ID -> Master ID)
        Map<int, int> doorIdMap = {};
        for (var row in pDoors) {
          final alias = row['doorAlias'] as String;
          final packageId = row['id'] as int;

          // Check if door exists in Master by Alias
          final existing = await txn.query('doors', where: 'doorAlias = ?', whereArgs: [alias], limit: 1);
          
          int masterId;
          final data = Map<String, dynamic>.from(row);
          
          if (existing.isNotEmpty) {
            masterId = existing.first['id'] as int;
            await txn.update('doors', data, where: 'id = ?', whereArgs: [masterId]);
          } else {
            masterId = await txn.insert('doors', data..remove('id'));
          }
          doorIdMap[packageId] = masterId;
        }

        // 4. Merge Inspections and create ID Mapping (Package ID -> Master ID)
        Map<int, int> inspectionIdMap = {};
        for (var row in pInspections) {
          final jobNum = (row['jobNumber'] ?? row['auftragsnummer'] ?? '') as String;
          final packageId = row['inspectionId'] as int;

          final existing = await txn.query('inspections', where: 'jobNumber = ?', whereArgs: [jobNum], limit: 1);
          
          int masterId;
          final data = Map<String, dynamic>.from(row);

          if (existing.isNotEmpty) {
            masterId = existing.first['inspectionId'] as int;
            await txn.update('inspections', data, where: 'inspectionId = ?', whereArgs: [masterId]);
          } else {
            masterId = await txn.insert('inspections', data..remove('inspectionId'));
          }
          inspectionIdMap[packageId] = masterId;
        }

        // 5. Merge Junctions (inspection_doors)
        Map<int, int> junctionIdMap = {};
        for (var row in pJunctions) {
          final packageId = row['id'] as int;
          final mDoorId = doorIdMap[row['doorId']];
          final mInspId = inspectionIdMap[row['inspectionId']];

          if (mDoorId == null || mInspId == null) continue;

          final data = Map<String, dynamic>.from(row)
            ..['doorId'] = mDoorId
            ..['inspectionId'] = mInspId
            ..remove('id');

          // Check if this door/job combo already has a junction
          final existing = await txn.query('inspection_doors', 
              where: 'inspectionId = ? AND doorId = ?', whereArgs: [mInspId, mDoorId], limit: 1);

          int masterId;
          if (existing.isNotEmpty) {
            masterId = existing.first['id'] as int;
            await txn.update('inspection_doors', data, where: 'id = ?', whereArgs: [masterId]);
          } else {
            masterId = await txn.insert('inspection_doors', data);
          }
          junctionIdMap[packageId] = masterId;
        }

        // Build reverse lookup: masterCatalogId → code for errorCode population
        final Map<int, String> masterIdToCode = {};
        for (final entry in catalogIdMap.entries) {
          final masterCatId = entry.value;
          // Look up code for this master catalog entry
          final catRow = await txn.query('error_catalog',
              columns: ['code'], where: 'errorId = ?', whereArgs: [masterCatId], limit: 1);
          if (catRow.isNotEmpty) {
            masterIdToCode[masterCatId] = catRow.first['code'] as String? ?? '';
          }
        }

        // 6. Merge Errors — remap errorId via catalogIdMap to prevent FK mismatch
        for (var row in pErrors) {
          final mJunctionId = junctionIdMap[row['inspectionDoorId']];
          if (mJunctionId == null) continue;

          final packageErrorId = row['errorId'] as int?;
          int? mappedErrorId = packageErrorId != null
              ? catalogIdMap[packageErrorId]
              : null;

          // FIX 4: Fallback — if catalogIdMap lookup failed (e.g. due to ID mismatch
          // from the inspector's local DB), try to resolve via errorCode natural key.
          final String rawErrorCode = row['errorCode'] as String? ?? '';
          if (mappedErrorId == null && rawErrorCode.isNotEmpty) {
            final fallback = await txn.query('error_catalog',
                columns: ['errorId'], where: 'code = ?', whereArgs: [rawErrorCode], limit: 1);
            if (fallback.isNotEmpty) {
              mappedErrorId = fallback.first['errorId'] as int;
            }
          }

          final errorCode = (mappedErrorId != null ? masterIdToCode[mappedErrorId] : null)
              ?? rawErrorCode;

          final data = Map<String, dynamic>.from(row)
            ..['inspectionDoorId'] = mJunctionId
            ..['errorId'] = mappedErrorId
            ..['errorCode'] = errorCode
            ..remove('id');

          // Check if an error entry for this door junction and error code/ID already exists in Master DB.
          List<Map<String, dynamic>> existingErrors = [];
          if (errorCode.isNotEmpty) {
            existingErrors = await txn.query(
              'inspection_door_errors',
              where: 'inspectionDoorId = ? AND errorCode = ?',
              whereArgs: [mJunctionId, errorCode],
              limit: 1,
            );
          }
          if (existingErrors.isEmpty && mappedErrorId != null) {
            existingErrors = await txn.query(
              'inspection_door_errors',
              where: 'inspectionDoorId = ? AND errorId = ?',
              whereArgs: [mJunctionId, mappedErrorId],
              limit: 1,
            );
          }

          if (existingErrors.isNotEmpty) {
            final existingMasterErrorId = existingErrors.first['id'] as int;
            await txn.update(
              'inspection_door_errors',
              data,
              where: 'id = ?',
              whereArgs: [existingMasterErrorId],
            );
          } else {
            await txn.insert(
              'inspection_door_errors',
              data,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      });
    } finally {
      await packageDb.close();
    }
  }

  static Future<ImportResult> mergeErrorCatalog(List<ErrorCatalog> errors) async {
    final db = await getDb();
    
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
            break;
          case ResolutionAction.replaceExisting:
            await txn.update(
              'error_catalog',
              resolution.conflict.incoming.toMap(),
              where: 'code = ?',
              whereArgs: [resolution.conflict.code],
            );
            break;
          case ResolutionAction.addAsNew:
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
            break;
        }
      }
    });
  }

  /// Records a successful API upload for later reference/deletion
  static Future<void> recordApiUpload(String jobNumber, String fileName, int documentId) async {
    final db = await getDb();
    await db.insert('api_uploads', {
      'jobNumber': jobNumber,
      'fileName': fileName,
      'documentId': documentId,
      'uploadDate': DateTime.now().toIso8601String(),
    });
  }

  /// Deletes specific inspections and their associated data (junctions, errors, API records).
  static Future<void> deleteInspections(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await getDb();
    final idString = ids.join(',');

    await db.transaction((txn) async {
      // 1. Delete associated error instances
      await txn.execute('''
        DELETE FROM inspection_door_errors 
        WHERE inspectionDoorId IN (SELECT id FROM inspection_doors WHERE inspectionId IN ($idString))
      ''');

      // 2. Delete door-inspection junctions
      await txn.delete('inspection_doors', where: 'inspectionId IN ($idString)');

      // 3. Delete the job records themselves
      await txn.delete('inspections', where: 'inspectionId IN ($idString)');
    });
  }

  /// Clears all inspection data from the database while preserving Doors and Error Catalog.
  static Future<void> purgeAllInspections() async {
    final db = await getDb();
    await db.transaction((txn) async {
      await txn.delete('inspection_door_errors');
      await txn.delete('inspection_doors');
      await txn.delete('inspections');
    });
  }

  static Future<List<ErrorCatalog>> getAllErrorCatalog({String? status}) async {
    final db = await getDb();
    final maps = await db.query(
      'error_catalog',
      where: status != null ? 'status = ?' : null,
      whereArgs: status != null ? [status] : null,
      orderBy: 'category, code',
    );
    return maps.map((m) => ErrorCatalog.fromMap(m)).toList();
  }

  /// Fetches unique categories currently present in the error catalog.
  static Future<List<String>> getErrorCatalogCategories() async {
    final db = await getDb();
    final maps = await db.rawQuery(
      'SELECT DISTINCT category FROM error_catalog ORDER BY category ASC',
    );
    return maps.map((m) => m['category'] as String).toList();
  }

  static Future<void> deleteErrorCatalog(int errorId) async {
    final db = await getDb();
    await db.delete(
      'error_catalog',
      where: 'errorId = ?',
      whereArgs: [errorId],
    );
  }
  // ─────────────────────────────────────────────────────────────
  // SEED DATA
  // ─────────────────────────────────────────────────────────────

  /// Startup module to check and initialize the Error Catalog.
  static Future<void> checkAndInitializeCatalog() async {
    final db = await getDb();
    
    final existingCount = await db.rawQuery('SELECT COUNT(*) as count FROM error_catalog');
    final count = Sqflite.firstIntValue(existingCount) ?? 0;
    
    if (count > 0) {
      print('[Catalog] Database has $count entries. Initialization skipped.');
      return;
    }

    final dbPath = await getDatabasesPath();
    final csvFile = File(join(dirname(dbPath), 'WartungsTool', 'error_catalog.csv'));

    if (await csvFile.exists()) {
      print('[Catalog] Found CSV at ${csvFile.path}. Importing...');
      try {
        final content = await csvFile.readAsString();
        final List<ErrorCatalog> errors = _parseCsv(content);
        await mergeErrorCatalog(errors);
        print('[Catalog] Import successful. ${errors.length} items added.');
      } catch (e) {
        print('[Catalog] CSV Parse Error: $e');
      }
    } else {
      print('[Catalog] No external CSV found. Loading from internal assets...');
      try {
        final content = await rootBundle.loadString('error_catalog.csv');
        final List<ErrorCatalog> errors = _parseCsv(content);
        await mergeErrorCatalog(errors);
        print('[Catalog] Internal Seed successful.');
      } catch (e) {
        print('[Catalog] Asset Load Error: $e');
      }
    }
  }

  /// Simple CSV parser for Error Catalog items
  static List<ErrorCatalog> _parseCsv(String csv) {
    final List<ErrorCatalog> results = [];
    final lines = csv.split('\n');
    for (var line in lines) {
      final parts = line.split(',').map((p) => p.trim()).toList();
      if (parts.length >= 2 && parts[0].isNotEmpty) {
        results.add(ErrorCatalog(
          code: parts[0],
          description: parts[1],
          category: parts.length > 2 ? parts[2] : 'Allgemein',
          severity: parts.length > 3 ? parts[3] : 'medium',
          recommendation: parts.length > 4 ? parts[4] : '',
          normReference: parts.length > 5 ? parts[5] : '',
        ));
      }
    }
    return results;
  }
}
