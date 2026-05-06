// Main Database Service for Central History
// Contains complete history of inspections, doors, errors, catalog
// Data is synced from local DB after report generation

import 'package:create_inpection_report/models/models.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class MainDatabaseService {
  static Database? _db;

  static Future<Database> getDb() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'main_history.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Same tables as local, but for history
        // Doors table
        await db.execute('''
          CREATE TABLE doors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customerName TEXT,
            customerAddress TEXT,
            contactPerson TEXT,
            jobNumber TEXT,
            inspectionDate TEXT,
            inspectorName TEXT,
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
            inspectionId INTEGER PRIMARY KEY AUTOINCREMENT,
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
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inspectionId INTEGER,
            doorId INTEGER,
            status TEXT,
            notes TEXT,
            attachments TEXT,
            FOREIGN KEY (inspectionId) REFERENCES inspections (inspectionId),
            FOREIGN KEY (doorId) REFERENCES doors (id)
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

        // ErrorCatalog table (complete catalog)
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

        // Seed error catalog on main DB creation
        await _seedErrorCatalog(db);
      },
    );

    return _db!;
  }

  // Seed error catalog (same as original)
  static Future<void> _seedErrorCatalog(Database db) async {
    final standardErrors = DoorErrorCatalog.getStandardErrors();
    for (final error in standardErrors) {
      await db.insert('error_catalog', error.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // CRUD methods for main DB
  static Future<void> insertDoor(Map<String, dynamic> door) async {
    final db = await getDb();
    // Remove syncStatus for main DB since it's not needed there
    final doorData = Map<String, dynamic>.from(door)..remove('syncStatus');
    await db.insert('doors', doorData, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getAllDoors() async {
    final db = await getDb();
    return await db.query('doors');
  }

  static Future<void> insertInspection(Map<String, dynamic> inspection) async {
    final db = await getDb();
    // Remove syncStatus for main DB
    final inspectionData = Map<String, dynamic>.from(inspection)..remove('syncStatus');
    await db.insert('inspections', inspectionData, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> insertInspectionDoor(Map<String, dynamic> inspectionDoor) async {
    final db = await getDb();
    // Remove syncStatus for main DB
    final inspectionDoorData = Map<String, dynamic>.from(inspectionDoor)..remove('syncStatus');
    await db.insert('inspection_doors', inspectionDoorData, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}