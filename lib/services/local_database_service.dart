// Local Database Service for Inspector Mobile App (Offline Work)
// Handles temporary data for current inspections: doors, errors, requests

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabaseService {
  static Database? _db;

  static Future<Database> getDb() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'local_inspection.db');

    _db = await openDatabase(
      path,
      version: 1,  // Start fresh for local
      onCreate: (db, version) async {
        // Doors table (local copy for current inspection)
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
            doorFunctionOK INTEGER,
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

        // ErrorRequests table (local, for new error proposals)
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
            syncStatus TEXT DEFAULT 'pending'
          );
        ''');

        // Local error catalog (subset or copy from main, if needed)
        await db.execute('''
          CREATE TABLE error_catalog (
            errorId INTEGER PRIMARY KEY,
            code TEXT UNIQUE,
            description TEXT,
            category TEXT,
            severity TEXT DEFAULT 'medium',
            recommendation TEXT DEFAULT '',
            normReference TEXT DEFAULT '',
            syncStatus TEXT DEFAULT 'synced'  -- Usually synced from main
          );
        ''');
      },
    );

    return _db!;
  }

  // CRUD methods similar to original, but for local DB
  // e.g., insertDoor, getAllDoors, etc.
  // Add syncStatus handling

  static Future<void> markAsSynced(String table, int id) async {
    final db = await getDb();
    await db.update(table, {'syncStatus': 'synced'}, where: 'id = ?', whereArgs: [id]);
  }

  // Clear local data after sync
  static Future<void> clearSyncedData() async {
    final db = await getDb();
    await db.delete('doors', where: 'syncStatus = ?', whereArgs: ['synced']);
    await db.delete('inspections', where: 'syncStatus = ?', whereArgs: ['synced']);
    // etc.
  }

  // CRUD Methods for local DB
  static Future<void> insertDoor(Map<String, dynamic> door) async {
    final db = await getDb();
    await db.insert('doors', door, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getAllDoors() async {
    final db = await getDb();
    return await db.query('doors');
  }

  static Future<void> updateDoor(Map<String, dynamic> door) async {
    final db = await getDb();
    await db.update('doors', door, where: 'id = ?', whereArgs: [door['id']]);
  }

  static Future<void> deleteDoor(int id) async {
    final db = await getDb();
    await db.delete('doors', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> insertInspection(Map<String, dynamic> inspection) async {
    final db = await getDb();
    await db.insert('inspections', inspection, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> insertInspectionDoor(Map<String, dynamic> inspectionDoor) async {
    final db = await getDb();
    await db.insert('inspection_doors', inspectionDoor, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getPendingDoors() async {
    final db = await getDb();
    return await db.query('doors', where: 'syncStatus = ?', whereArgs: ['pending']);
  }

  static Future<List<Map<String, dynamic>>> getPendingInspections() async {
    final db = await getDb();
    return await db.query('inspections', where: 'syncStatus = ?', whereArgs: ['pending']);
  }

  static Future<List<Map<String, dynamic>>> getPendingInspectionDoors() async {
    final db = await getDb();
    return await db.query('inspection_doors', where: 'syncStatus = ?', whereArgs: ['pending']);
  }
}