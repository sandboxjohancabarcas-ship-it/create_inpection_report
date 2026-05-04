import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:create_inpection_report/models/models.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> getDb() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'door_inspection.db');

    _db = await openDatabase(
      path,
      version: 2,
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
            category TEXT
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
  static Future<List<ErrorCatalog>> getErrorCatalogByCategory(
      String category) async {
    final db = await getDb();
    final maps = await db.query(
      'error_catalog',
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'code ASC',
    );
    return maps.map((m) => ErrorCatalog.fromMap(m)).toList();
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

  static Future<void> _seedErrorCatalog(Database db) async {
    // Errors will be added here in the next step
    // once codes and descriptions are provided.
  }
}
