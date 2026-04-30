import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:create_inpection_report/models/models.dart';


class DatabaseService {
  //This keeps a single copy of the database connection open.Prevents opening multiple connections unnecessarily.
  static Database? _db;

 // Open or create the database
//   This is the entry point: whenever your app needs the database, it calls getDb().
// If the database is already open, it just returns it.
// If not, it opens/creates it.
  static Future<Database> getDb() async {
    if (_db != null) return _db!;

// getDatabasesPath() gives you the folder where Flutter stores SQLite files.
// join() combines that folder with your chosen filename (door_inspection.db)
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'door_inspection.db');

//opens the file if it exists, or creates it if not.
_db = await openDatabase(
  path,
  version: 1,
  onCreate: (db, version) async {
    // Doors table
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

    // InspectionDoors table (junction between inspections and doors)
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

    // ErrorCatalog table (master list of errors)
    await db.execute('''
      CREATE TABLE error_catalog (
        errorId INTEGER PRIMARY KEY,
        code TEXT,
        description TEXT,
        category TEXT
      );
    ''');

    // InspectionDoorErrors table (errors found during inspection)
    await db.execute('''
      CREATE TABLE inspection_door_errors (
        id INTEGER PRIMARY KEY,
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

    // ErrorRequests table (proposals for new error types)
    await db.execute('''
      CREATE TABLE error_requests (
        requestId INTEGER PRIMARY KEY,
        proposedDescription TEXT,
        category TEXT,
        inspectorId INTEGER,
        date TEXT,
        status TEXT,
        managerNotes TEXT
      );
    ''');
  },
  );

    return _db!;
  }
    // Insert a new door
  static Future<void> insertDoor(Door door) async {
    final db = await getDb();
    await db.insert(
      'doors',
      door.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, // replaces if same id exists
    );
  }

  static Future<List<Door>> getAllDoors() async {
    final db = await getDb();
    final maps = await db.query('doors');
    return maps.map((map) => Door.fromMap(map)).toList();
  }
  //This finds the door by its id and updates all fields with the new values from toMap().
  static Future<void> updateDoor(Door door) async {
    final db = await getDb();
    await db.update(
      'doors',
      door.toMap(),
      where: 'id = ?',
      whereArgs: [door.id],
    );
  }
  //This removes the door with the given id.
  static Future<void> deleteDoor(int id) async {
    final db = await getDb();
    await db.delete(
      'doors',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
// Creates the SQLite table for storing inspection records.
// Each inspection belongs to exactly one door (doorId foreign key).
// This table stores dynamic inspection results, not static door properties.
  static Future<void> createInspectionTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inspections (
        id INTEGER PRIMARY KEY,              -- Unique ID for each inspection
        doorId INTEGER NOT NULL,             -- Foreign key: which door was inspected
        date TEXT NOT NULL,                  -- Date of inspection (ISO string)
        inspectorName TEXT,                  -- Name of the inspector
        notes TEXT,                          -- Optional notes about the inspection
        doorFunctionOK INTEGER NOT NULL,     -- 1 = OK, 0 = not OK
        escapeRouteSignage INTEGER NOT NULL, -- 1 = present, 0 = missing
        panicFunction TEXT,                  -- B / E / None
        accessControl TEXT,                  -- Access control system used
        FOREIGN KEY (doorId) REFERENCES doors(id)
      )
    ''');
  }

}
