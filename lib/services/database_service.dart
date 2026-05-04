import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:create_inpection_report/models/models.dart';
import 'package:create_inpection_report/models/error_catalog.dart';
import 'package:create_inpection_report/models/inspection_error.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> getDb() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'door_inspection.db');

    _db = await openDatabase(
      path,
      version: 7,
      onCreate: (db, version) async {
        // Doors table
        await db.execute('''
          CREATE TABLE doors (
            -- Inspection Metadata
            customerName TEXT,
            customerAddress TEXT,
            contactPerson TEXT,
            jobNumber TEXT,
            inspectionDate TEXT,
            inspectorName TEXT,
            
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
            normReference TEXT DEFAULT ''
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

        // InspectionErrors table (simplified for direct door errors)
        await db.execute('''
          CREATE TABLE inspection_errors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            doorId INTEGER,
            errorId INTEGER,
            notes TEXT,
            status TEXT DEFAULT 'open',
            reportedDate TEXT,
            resolvedDate TEXT,
            FOREIGN KEY (doorId) REFERENCES doors (id),
            FOREIGN KEY (errorId) REFERENCES error_catalog (errorId)
          );
        ''');

        // ErrorRequests table
        await db.execute('''
          CREATE TABLE error_requests (
            requestId INTEGER PRIMARY KEY AUTOINCREMENT,
            proposedCode TEXT,
            proposedDescription TEXT,
            category TEXT,
            inspectionDoorId INTEGER,
            date TEXT,
            status TEXT DEFAULT 'pending',
            managerNotes TEXT,
            replacedByErrorId INTEGER
          );
        ''');

        // Seed the error catalog on first create
        await _seedErrorCatalog(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
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
          
          // Create inspection_errors table if it doesn't exist
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS inspection_errors (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                doorId INTEGER,
                errorId INTEGER,
                notes TEXT,
                status TEXT DEFAULT 'open',
                reportedDate TEXT,
                resolvedDate TEXT,
                FOREIGN KEY (doorId) REFERENCES doors (id),
                FOREIGN KEY (errorId) REFERENCES error_catalog (errorId)
              );
            ''');
          } catch (e) {
            print('Inspection errors table creation error: $e');
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

  static Future<void> insertDoor(Door door) async {
    final db = await getDb();
    await db.insert(
      'doors',
      door.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  /// Insert a single error catalog entry.
  static Future<int> insertErrorCatalogItem(ErrorCatalog item) async {
    final db = await getDb();
    return await db.insert(
      'error_catalog',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore, // skip if code already exists
    );
  }

  /// Return every entry in the catalog, ordered by category then code.
  static Future<List<ErrorCatalog>> getAllErrorCatalogItems() async {
    final db = await getDb();
    final maps = await db.query(
      'error_catalog',
      orderBy: 'category ASC, code ASC',
    );
    return maps.map((m) => ErrorCatalog.fromMap(m)).toList();
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

  static Future<void> deleteErrorCatalog(int errorId) async {
    final db = await getDb();
    await db.delete(
      'error_catalog',
      where: 'errorId = ?',
      whereArgs: [errorId],
    );
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

  /// Delete a catalog entry (admin use only).
  static Future<void> deleteErrorCatalogItem(int errorId) async {
    final db = await getDb();
    await db.delete(
      'error_catalog',
      where: 'errorId = ?',
      whereArgs: [errorId],
    );
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

  // ─────────────────────────────────────────────────────────────
  // ERROR REQUESTS
  // ─────────────────────────────────────────────────────────────

  /// Submit a new error request (inspector proposes a missing error type).
  static Future<int> insertErrorRequest(ErrorRequest request) async {
    final db = await getDb();
    return await db.insert('error_requests', request.toMap());
  }

  /// All pending requests — shown in the manager dashboard.
  static Future<List<ErrorRequest>> getPendingErrorRequests() async {
    final db = await getDb();
    final maps = await db.query(
      'error_requests',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'date DESC',
    );
    return maps.map((m) => ErrorRequest.fromMap(m)).toList();
  }

  /// Approve: add to catalog, mark request as approved.
  static Future<void> approveErrorRequest(
      int requestId, ErrorCatalog newEntry) async {
    final db = await getDb();
    final newId = await db.insert('error_catalog', newEntry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.update(
      'error_requests',
      {'status': 'approved'},
      where: 'requestId = ?',
      whereArgs: [requestId],
    );
    // Also update the inspection_door_error that triggered this request
    // so it now points to the real catalog entry.
    final req = await db.query('error_requests',
        where: 'requestId = ?', whereArgs: [requestId], limit: 1);
    if (req.isNotEmpty && newId > 0) {
      final inspectionDoorId = req.first['inspectionDoorId'];
      await db.update(
        'inspection_door_errors',
        {'errorId': newId},
        where: 'inspectionDoorId = ? AND errorId IS NULL',
        whereArgs: [inspectionDoorId],
      );
    }
  }

  /// Reject: manager picks an existing catalog entry to replace the request.
  /// The chosen errorId is applied to the inspection_door_error row.
  static Future<void> rejectErrorRequest(
      int requestId, int replacedByErrorId, String managerNotes) async {
    final db = await getDb();
    await db.update(
      'error_requests',
      {
        'status': 'rejected',
        'replacedByErrorId': replacedByErrorId,
        'managerNotes': managerNotes,
      },
      where: 'requestId = ?',
      whereArgs: [requestId],
    );
    // Replace the temporary null errorId with the chosen real one
    final req = await db.query('error_requests',
        where: 'requestId = ?', whereArgs: [requestId], limit: 1);
    if (req.isNotEmpty) {
      final inspectionDoorId = req.first['inspectionDoorId'];
      await db.update(
        'inspection_door_errors',
        {'errorId': replacedByErrorId},
        where: 'inspectionDoorId = ? AND errorId IS NULL',
        whereArgs: [inspectionDoorId],
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SEED DATA  ← error codes/descriptions supplied by user
  // ─────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────
  // INSPECTION ERRORS
  // ─────────────────────────────────────────────────────────────

  static Future<void> insertInspectionError(InspectionError error) async {
    final db = await getDb();
    await db.insert(
      'inspection_errors',
      error.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<InspectionError>> getInspectionErrorsForDoor(int doorId) async {
    final db = await getDb();
    final maps = await db.query(
      'inspection_errors',
      where: 'doorId = ?',
      whereArgs: [doorId],
      orderBy: 'reportedDate DESC',
    );
    return maps.map((m) => InspectionError.fromMap(m)).toList();
  }

  static Future<void> updateInspectionErrorStatus(int errorId, String status) async {
    final db = await getDb();
    await db.update(
      'inspection_errors',
      {
        'status': status,
        'resolvedDate': status == 'resolved' ? DateTime.now().toIso8601String() : null,
      },
      where: 'id = ?',
      whereArgs: [errorId],
    );
  }

  static Future<void> deleteInspectionError(int errorId) async {
    final db = await getDb();
    await db.delete(
      'inspection_errors',
      where: 'id = ?',
      whereArgs: [errorId],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ERROR CATALOG
  // ─────────────────────────────────────────────────────────────

  static Future<void> insertErrorCatalog(ErrorCatalog error) async {
    final db = await getDb();
    await db.insert(
      'error_catalog',
      error.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<ErrorCatalog>> getAllErrorCatalog() async {
    final db = await getDb();
    final maps = await db.query('error_catalog', orderBy: 'category, code');
    return maps.map((m) => ErrorCatalog.fromMap(m)).toList();
  }

  // ─────────────────────────────────────────────────────────────
  // SEED DATA
  // ─────────────────────────────────────────────────────────────

  static Future<void> _seedErrorCatalog(Database db) async {
    print('Seeding error catalog...');
    final standardErrors = DoorErrorCatalog.getStandardErrors();
    print('Found ${standardErrors.length} errors to seed');
    
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
}
