// Local Database Service for Inspector Mobile App (Offline Work)
// Handles temporary data for current inspections: doors, errors, requests

import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/door_validator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LocalDatabaseService {
  static Database? _db;

  static Future<String> _getWorkingDbPath() async {
    if (Platform.isWindows || Platform.isLinux) {
      try {
        final directory = await getApplicationSupportDirectory();
        return join(directory.path, 'working.db');
      } catch (e) {
        print('[LocalDatabaseService] Fallback to default databases path: $e');
      }
    }
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'working.db');
  }

  static Future<Database> getDb() async {
    if (_db != null) return _db!;

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final path = await _getWorkingDbPath();

    _db = await openDatabase(
      path,
      version: 10,  // v10: Added new door properties (approvalNumber, manufacturerNumber, dopNumber, lintelHeightOver1m, lintelHeightValue, manufactureYear)
      onCreate: (db, version) async {
        // Doors table (local copy for current inspection)
        await db.execute('''
          CREATE TABLE doors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
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
            doorFunctionOK INTEGER,
            approvalNumber TEXT DEFAULT '?',
            manufacturerNumber TEXT DEFAULT '?',
            dopNumber TEXT DEFAULT '?',
            lintelHeightOver1m INTEGER DEFAULT 0,
            lintelHeightValue INTEGER,
            manufactureYear TEXT DEFAULT '?'
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
            jobNumber TEXT,
            projectNumber TEXT
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
            errorCode TEXT NOT NULL DEFAULT '',
            quantity INTEGER,
            severity TEXT,
            notes TEXT,
            resolutionStatus TEXT,
            attachments TEXT DEFAULT '',
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
            status TEXT NOT NULL DEFAULT 'Approved',
            requestedBy TEXT,
            requestDate TEXT,
            sourceInspectionDoorId INTEGER
          );
        ''');


        // Add indices for optimized searching
        await db.execute('CREATE INDEX IF NOT EXISTS idx_local_doors_number ON doors (doorNumber)');
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_local_doors_alias ON doors (doorAlias)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_local_ec_description ON error_catalog (description)');
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
        if (oldVersion < 3) {
          // Add indices for optimized searching in existing databases
          await db.execute('CREATE INDEX IF NOT EXISTS idx_local_doors_number ON doors (doorNumber)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_local_ec_description ON error_catalog (description)');
          print('Local Database upgraded to version 3: Search indices created.');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE doors ADD COLUMN doorAlias TEXT');
          await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_local_doors_alias ON doors (doorAlias)');
          print('Local Database upgraded to version 4: Door Alias added.');
        }
        if (oldVersion < 5) {
          // Data Migration: Normalize values to prevent Dropdown crashes in local DB
          await db.execute("UPDATE doors SET dinConfiguration = 'DIN L' WHERE dinConfiguration = 'L'");
          await db.execute("UPDATE doors SET dinConfiguration = 'DIN R' WHERE dinConfiguration = 'R'");
          await db.execute("UPDATE doors SET closerType = 'TS93' WHERE closerType = 'TS 5000'");
          await db.execute("UPDATE doors SET manufacturer = 'Dorma' WHERE manufacturer = 'HÖRMANN'");
          await db.execute("UPDATE doors SET fittingType = 'Drücker' WHERE fittingType = 'Drücker/Drücker'");
          print('Local Database upgraded to version 5: Values normalized.');
        }
        if (oldVersion < 6) {
          // Comprehensive Normalization for Local DB
          await db.execute("UPDATE doors SET closerType = 'TS93' WHERE closerType = 'TS 5000' OR closerType IS NULL");
          await db.execute("UPDATE doors SET manufacturer = 'Dorma' WHERE manufacturer = 'HÖRMANN' OR manufacturer IS NULL");
          await db.execute("UPDATE doors SET fittingType = 'Drücker' WHERE fittingType = 'Drücker/Drücker' OR fittingType IS NULL");
          await db.execute("UPDATE doors SET dinConfiguration = 'DIN L' WHERE dinConfiguration = 'L' OR dinConfiguration IS NULL");
          await db.execute("UPDATE doors SET dinConfiguration = 'DIN R' WHERE dinConfiguration = 'R'");
          print('Local Database upgraded to version 6: Comprehensive values normalized.');
        }
        if (oldVersion < 7) {
          try {
            await db.execute("ALTER TABLE inspection_door_errors ADD COLUMN attachments TEXT DEFAULT ''");
            print('Local Database upgraded to version 7: attachments column added to inspection_door_errors.');
          } catch (e) {
            print('Local DB migration warning (attachments): \$e');
          }
        }
        if (oldVersion < 8) {
          try {
            await db.execute("ALTER TABLE inspection_door_errors ADD COLUMN errorCode TEXT NOT NULL DEFAULT ''");
            // Backfill errorCode from local error_catalog
            await db.execute('''
              UPDATE inspection_door_errors
              SET errorCode = COALESCE(
                (SELECT code FROM error_catalog WHERE error_catalog.errorId = inspection_door_errors.errorId),
                ''
              )
              WHERE errorCode IS NULL OR errorCode = ''
            ''');
            print('Local Database upgraded to version 8: errorCode column added and backfilled.');
          } catch (e) {
            print('Local DB migration warning (errorCode): \$e');
          }
        }

        if (oldVersion < 9) {
          try {
            await db.execute('ALTER TABLE inspections ADD COLUMN projectNumber TEXT');
            print('Local Database upgraded to version 9: projectNumber column added.');
          } catch (e) {
            print('Local DB migration warning (projectNumber): $e');
          }
        }

        if (oldVersion < 10) {
          try {
            await db.execute("ALTER TABLE doors ADD COLUMN approvalNumber TEXT DEFAULT '?'");
            await db.execute("ALTER TABLE doors ADD COLUMN manufacturerNumber TEXT DEFAULT '?'");
            await db.execute("ALTER TABLE doors ADD COLUMN dopNumber TEXT DEFAULT '?'");
            await db.execute("ALTER TABLE doors ADD COLUMN lintelHeightOver1m INTEGER DEFAULT 0");
            await db.execute("ALTER TABLE doors ADD COLUMN lintelHeightValue INTEGER");
            await db.execute("ALTER TABLE doors ADD COLUMN manufactureYear TEXT DEFAULT '?'");
            print('Local Database upgraded to version 10: new door properties added.');
          } catch (e) {
            print('Local DB migration warning (v10 columns): $e');
          }
        }
      },
    );

    await _populateMissingAliases(_db!);

    return _db!;
  }

  static Future<void> _populateMissingAliases(Database db) async {
    final List<Map<String, dynamic>> rows = await db.rawQuery('''
      SELECT d.id, d.doorNumber, d.floor, i.clientName, i.objectAddress
      FROM doors d
      LEFT JOIN inspection_doors id ON d.id = id.doorId
      LEFT JOIN inspections i ON id.inspectionId = i.inspectionId
      WHERE d.doorAlias IS NULL
    ''');
    
    if (rows.isEmpty) return;
    
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
  }

  /// Updates the doorAlias for a door ID in local working.db.
  static Future<int> updateDoorAlias(int doorId, String newAlias) async {
    final db = await getDb();
    final cleanAlias = newAlias.trim();
    return await db.update(
      'doors',
      {'doorAlias': cleanAlias},
      where: 'id = ?',
      whereArgs: [doorId],
    );
  }

  /// Downloads a Job Package (one or many inspections) from the Main DB.
  /// This enables the "Wide Spectrum" of history or single jobs.
  static Future<void> downloadJobPackage({
    required List<int> inspectionIds,
  }) async {
    try {
      if (inspectionIds.isEmpty) return;
      print('Downloading Job Package for ${inspectionIds.length} inspections...');

      // 1. Fetch all related records from Master DB using our new batch helpers
      final doorList = await DatabaseService.getDoorsByInspectionIds(inspectionIds);
      
      final List<Map<String, dynamic>> allJunctions = [];
      for (int id in inspectionIds) {
        allJunctions.addAll(await DatabaseService.getInspectionDoorsByInspectionId(id));
      }
      
      final List<int> junctionIds = allJunctions.map((j) => j['id'] as int).toList();
      final errorList = await DatabaseService.getErrorsForInspectionDoorIds(junctionIds);

      // Resolve full inspection objects for the local DB
      final allMainInspections = await DatabaseService.searchInspections('');
      final selectedInspections = allMainInspections
          .where((i) => inspectionIds.contains(i['inspectionId']))
          .toList();

      // Fetch the full approved catalog to include in the package
      final masterCatalog = await DatabaseService.getAllErrorCatalog(status: 'Approved');

      final db = await getDb();
      await db.transaction((txn) async {
        // Purge old local job data to enforce Isolation Protocol
        await txn.delete('inspection_door_errors');
        await txn.delete('inspection_doors');
        await txn.delete('inspections');
        await txn.delete('doors');

        // 3. Populate local Inspections from the downloaded package
        for (var insp in selectedInspections) {
          final Map<String, dynamic> data = Map<String, dynamic>.from(insp);
          // Ensure legacy packages are mapped to new English keys
          if (data.containsKey('auftragsnummer') && !data.containsKey('jobNumber')) {
            data['jobNumber'] = data['auftragsnummer'];
          }
          data.remove('doorCount');
          await txn.insert('inspections', data, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (var junction in allJunctions) {
          await txn.insert('inspection_doors', junction, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (var door in doorList) {
          await txn.insert('doors', door.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // FIX 1: Insert catalog BEFORE errors so we can remap errorId FKs.
        // The Master DB and Local DB have independent AUTOINCREMENT sequences,
        // so we must ensure the local catalog IDs are established first.
        await _batchInsertCatalog(txn, masterCatalog, ConflictAlgorithm.replace);

        // Build a code → local errorId mapping for FK remapping
        final localCatalogRows = await txn.query('error_catalog');
        final Map<String, int> codeToLocalErrorId = {};
        for (final row in localCatalogRows) {
          final code = row['code'] as String? ?? '';
          final localId = row['errorId'] as int;
          if (code.isNotEmpty) {
            codeToLocalErrorId[code] = localId;
          }
        }

        for (var error in errorList) {
          // Filter out JOIN-injected columns that don't exist in the local table
          final data = Map<String, dynamic>.from(error)
            ..remove('code')
            ..remove('description');

          // Remap errorId to the local catalog's ID using the errorCode natural key
          final String errorCode = data['errorCode'] as String? ?? '';
          if (errorCode.isNotEmpty && codeToLocalErrorId.containsKey(errorCode)) {
            data['errorId'] = codeToLocalErrorId[errorCode];
          }

          await txn.insert('inspection_door_errors', data, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    } catch (e) {
      print('Critical error during package download: $e');
      rethrow;
    }
  }

  /// Creates a specific result package containing only the selected doors and their inspections.
  /// This implements the "Inspector Export" requirement.
  static Future<void> exportSelectiveJobPackage(List<int> doorIds, String destinationPath) async {
    if (doorIds.isEmpty) throw Exception('Keine Türen ausgewählt.');

    // 1. Create a full copy of the current working DB as a starting point
    await exportWorkingDb(destinationPath);

    // 2. Open the copy and prune non-selected data
    final db = await openDatabase(destinationPath);
    try {
      await db.transaction((txn) async {
        final idList = doorIds.join(',');

        // Remove doors not in selection
        await txn.delete('doors', where: 'id NOT IN ($idList)');

        // Remove junctions not linked to these doors
        await txn.delete('inspection_doors', where: 'doorId NOT IN ($idList)');

        // Remove inspections that no longer have any linked doors in this package
        await txn.execute('''
          DELETE FROM inspections 
          WHERE inspectionId NOT IN (SELECT DISTINCT inspectionId FROM inspection_doors)
        ''');

        // Remove errors not linked to remaining junctions
        await txn.execute('''
          DELETE FROM inspection_door_errors 
          WHERE inspectionDoorId NOT IN (SELECT id FROM inspection_doors)
        ''');
      });
    } finally {
      await db.close();
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

  /// Purges only the data associated with specific inspections (e.g., after a successful export).
  static Future<void> purgeExportedData(List<int> inspectionIds) async {
    if (inspectionIds.isEmpty) return;
    final db = await getDb();
    final idStr = inspectionIds.join(',');
    
    print('Purging exported data for inspections: $idStr');
    
    await db.transaction((txn) async {
      // 1. Delete errors associated with the junctions of these inspections
      await txn.execute('''
        DELETE FROM inspection_door_errors 
        WHERE inspectionDoorId IN (SELECT id FROM inspection_doors WHERE inspectionId IN ($idStr))
      ''');
      
      // 2. Delete the junctions
      await txn.delete('inspection_doors', where: 'inspectionId IN ($idStr)');
      
      // 3. Delete the inspection records
      await txn.delete('inspections', where: 'inspectionId IN ($idStr)');
      
      // 4. Delete doors that are no longer linked to ANY remaining inspection
      await txn.execute('DELETE FROM doors WHERE id NOT IN (SELECT DISTINCT doorId FROM inspection_doors)');
    });
  }

  // ─────────────────────────────────────────────────────────────
  // DOORS
  // ─────────────────────────────────────────────────────────────

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
    return await db.insert(
      'doors', 
      door.toMap(), 
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Creates a new door record found by an inspector in the field.
  /// Uses a manual door number and generates a clean TMP- alias for tracking.
  static Future<int> createNewDoorInField(String doorNumber) async {
    final door = Door(
      id: null, // Pass null for auto-incrementing ID
      pos: 0, // Default position for new field entries
      doorNumber: doorNumber, // Inspector manually enters this
      doorAlias: Door.generateTemporaryAlias(doorNumber),
      floor: '',
      roomNumber: '',
      roomDesignation: '',
      doorType: '',
      wingCount: 1,
      material: '',
      manufacturer: '',
      dinConfiguration: 'DIN L',
      closerType: 'TS93',
      closingSequenceSystem: '', // Added this parameter
      lockDimensions: '',
      closerOnHingeSide: false,
      closerOnOppositeSide: false,
      lintelHeightUnder1m: false,
      escapeDoorControl: false,
      accessControl: '',
      escapeRouteSituation: false,
      escapeRouteSignage: false,
      blindCylinder: false,
      pzCylinder: false,
      fittingType: '',
      panicFunction: '',
      escapeDirectionRespected: true,
      fullPanicStandWing: false,
      doorFunctionOK: true,
    );
    return await insertDoor(door);
  }

  static Future<List<Door>> getAllDoors() async {
    final db = await getDb();
    final maps = await db.query('doors');
    return maps.map((m) => Door.fromMap(m)).toList();
  }

  static Future<Door?> getDoorByAlias(String alias) async {
    final db = await getDb();
    final maps = await db.query('doors', where: 'doorAlias = ?', whereArgs: [alias], limit: 1);
    return maps.isNotEmpty ? Door.fromMap(maps.first) : null;
  }

  /// Searches doors by doorNumber, error code, or error description.
  /// Uses a join across junctions to find doors with specific errors.
  static Future<List<Door>> searchDoors(String query) async {
    final db = await getDb();
    if (query.isEmpty) return await getAllDoors();

    final searchTerm = '%$query%';
    
    final results = await db.rawQuery('''
      SELECT DISTINCT d.* 
      FROM doors d
      LEFT JOIN inspection_doors id ON d.id = id.doorId
      LEFT JOIN inspection_door_errors ide ON id.id = ide.inspectionDoorId
      LEFT JOIN error_catalog ec ON ide.errorId = ec.errorId
      WHERE d.doorNumber LIKE ? 
         OR d.doorAlias LIKE ?
         OR ec.code LIKE ? 
         OR ec.description LIKE ?
    ''', [searchTerm, searchTerm, searchTerm, searchTerm]);

    return results.map((m) => Door.fromMap(m)).toList();
  }

  static Future<void> updateDoor(Door door) async {
    final db = await getDb();
    await db.update('doors', door.toMap(), where: 'id = ?', whereArgs: [door.id!]);
  }

  static Future<void> deleteDoor(int id) async {
    await deleteDoors([id]);
  }

  static Future<void> deleteDoors(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await getDb();
    final idList = ids.join(',');
    await db.transaction((txn) async {
      // 1. Delete errors associated with junctions of these doors
      await txn.execute('''
        DELETE FROM inspection_door_errors 
        WHERE inspectionDoorId IN (SELECT id FROM inspection_doors WHERE doorId IN ($idList))
      ''');
      // 2. Delete the junctions linked to these doors
      await txn.delete('inspection_doors', where: 'doorId IN ($idList)');
      // 3. Delete the door records themselves
      await txn.delete('doors', where: 'id IN ($idList)');
    });
  }

  // ─────────────────────────────────────────────────────────────
  // INSPECTIONS
  // ─────────────────────────────────────────────────────────────

  static Future<int> insertInspection(Map<String, dynamic> inspection) async {
    final db = await getDb();
    return await db.insert('inspections', inspection, conflictAlgorithm: ConflictAlgorithm.replace);
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

    final existingRows = await db.query(
      'inspections',
      columns: ['clientName', 'objectAddress'],
      where: 'inspectionId = ?',
      whereArgs: [id],
      limit: 1,
    );

    final String oldClient = existingRows.isNotEmpty ? (existingRows.first['clientName'] as String? ?? '') : '';
    final String oldAddress = existingRows.isNotEmpty ? (existingRows.first['objectAddress'] as String? ?? '') : '';

    await db.update(
      'inspections',
      inspectionData,
      where: 'inspectionId = ?',
      whereArgs: [id],
    );

    final String newClient = inspectionData['clientName']?.toString().trim() ?? oldClient;
    final String newAddress = inspectionData['objectAddress']?.toString().trim() ?? oldAddress;

    if (newClient != oldClient || newAddress != oldAddress) {
      await updateDoorAliasesForInspection(
        inspectionId: (id is int) ? id : int.parse(id.toString()),
        newClientName: newClient,
        newObjectAddress: newAddress,
      );
    }
  }

  static Future<void> updateDoorAliasesForInspection({
    required int inspectionId,
    required String newClientName,
    required String newObjectAddress,
  }) async {
    final db = await getDb();

    final List<Map<String, dynamic>> linkedDoors = await db.rawQuery('''
      SELECT d.* 
      FROM doors d
      INNER JOIN inspection_doors id ON d.id = id.doorId
      WHERE id.inspectionId = ?
    ''', [inspectionId]);

    for (final doorRow in linkedDoors) {
      final int doorId = doorRow['id'] as int;
      final String doorNumber = doorRow['doorNumber'] as String? ?? '';
      final String floor = doorRow['floor'] as String? ?? '';

      final String newAlias = Door.generateAlias(
        newClientName,
        newObjectAddress,
        doorNumber,
        floor: floor,
      );

      if (newAlias.isEmpty) continue;

      final String oldAlias = doorRow['doorAlias'] as String? ?? '';
      if (newAlias == oldAlias) continue;

      final existingWithAlias = await db.query(
        'doors',
        columns: ['id'],
        where: 'doorAlias = ? AND id != ?',
        whereArgs: [newAlias, doorId],
        limit: 1,
      );

      if (existingWithAlias.isNotEmpty) {
        final int targetExistingDoorId = existingWithAlias.first['id'] as int;
        await mergeDuplicateDoors(targetDoorId: targetExistingDoorId, duplicateDoorId: doorId);
      } else {
        await db.update(
          'doors',
          {'doorAlias': newAlias},
          where: 'id = ?',
          whereArgs: [doorId],
        );
      }
    }
  }

  static Future<void> mergeDuplicateDoors({
    required int targetDoorId,
    required int duplicateDoorId,
  }) async {
    if (targetDoorId == duplicateDoorId) return;
    final db = await getDb();

    final duplicateJunctions = await db.query(
      'inspection_doors',
      where: 'doorId = ?',
      whereArgs: [duplicateDoorId],
    );

    for (final j in duplicateJunctions) {
      final jId = j['id'] as int;
      final jInspId = j['inspectionId'] as int;

      final existingJunctionForTarget = await db.query(
        'inspection_doors',
        where: 'doorId = ? AND inspectionId = ?',
        whereArgs: [targetDoorId, jInspId],
        limit: 1,
      );

      if (existingJunctionForTarget.isNotEmpty) {
        final targetJunctionId = existingJunctionForTarget.first['id'] as int;

        await db.rawUpdate('''
          UPDATE inspection_door_errors 
          SET inspectionDoorId = ? 
          WHERE inspectionDoorId = ?
        ''', [targetJunctionId, jId]);

        await db.delete('inspection_doors', where: 'id = ?', whereArgs: [jId]);
      } else {
        await db.update(
          'inspection_doors',
          {'doorId': targetDoorId},
          where: 'id = ?',
          whereArgs: [jId],
        );
      }
    }

    await db.delete('doors', where: 'id = ?', whereArgs: [duplicateDoorId]);
  }

  /// Returns all distinct client names stored in the local working database
  static Future<List<String>> getAllLocalClients() async {
    final db = await getDb();
    final rows = await db.rawQuery('''
      SELECT DISTINCT clientName 
      FROM inspections 
      WHERE clientName IS NOT NULL AND TRIM(clientName) != ''
      ORDER BY clientName ASC
    ''');
    return rows.map((r) => r['clientName'] as String).toList();
  }

  /// Fetches inspections stored in the working database with optional query and clientFilter.
  static Future<List<Map<String, dynamic>>> getAllInspections({String query = '', String clientFilter = ''}) async {
    final db = await getDb();
    final cleanQuery = query.trim();
    final cleanClient = clientFilter.trim();

    String where = '1=1';
    List<dynamic> whereArgs = [];

    if (cleanClient.isNotEmpty && cleanClient != 'Alle') {
      where += ' AND i.clientName = ?';
      whereArgs.add(cleanClient);
    }

    if (cleanQuery.isNotEmpty) {
      final searchTerm = '%$cleanQuery%';
      where += ''' AND (
        i.clientName LIKE ? 
        OR i.jobNumber LIKE ? 
        OR i.date LIKE ? 
        OR i.objectAddress LIKE ? 
        OR d.doorNumber LIKE ?
      )''';
      whereArgs.addAll([searchTerm, searchTerm, searchTerm, searchTerm, searchTerm]);
    }

    return await db.rawQuery('''
      SELECT i.*, COUNT(DISTINCT id.doorId) as doorCount
      FROM inspections i
      LEFT JOIN inspection_doors id ON i.inspectionId = id.inspectionId
      LEFT JOIN doors d ON id.doorId = d.id
      WHERE $where
      GROUP BY i.inspectionId
      ORDER BY i.date DESC
    ''', whereArgs);
  }

  /// Returns all doors associated with a specific inspection ID in the local DB.
  /// Supports optional query to search by door number, room description, room designation, error description/code/notes.
  static Future<List<Door>> getDoorsByInspectionId(int inspectionId, {String query = ''}) async {
    final db = await getDb();
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT d.* 
        FROM doors d
        INNER JOIN inspection_doors id ON d.id = id.doorId
        WHERE id.inspectionId = ?
        ORDER BY d.pos ASC, d.doorNumber ASC
      ''', [inspectionId]);
      return maps.map((map) => Door.fromMap(map)).toList();
    }

    final searchTerm = '%$cleanQuery%';
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT DISTINCT d.* 
      FROM doors d
      INNER JOIN inspection_doors id ON d.id = id.doorId
      LEFT JOIN inspection_door_errors ide ON id.id = ide.inspectionDoorId
      LEFT JOIN error_catalog ec ON (ide.errorId = ec.errorId OR (ide.errorCode IS NOT NULL AND ide.errorCode != '' AND ide.errorCode = ec.code))
      WHERE id.inspectionId = ?
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
      inspectionId,
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

  static Future<Set<String>> _getInspectionDoorErrorsColumns(DatabaseExecutor db) async {
    try {
      final List<Map<String, dynamic>> tableInfo = await db.rawQuery('PRAGMA table_info(inspection_door_errors)');
      return tableInfo.map((row) => row['name'] as String).toSet();
    } catch (e) {
      print('Error getting table info for inspection_door_errors: $e');
      return {};
    }
  }

  static Future<String> _fetchLargeAttachments(DatabaseExecutor db, int errorId) async {
    final StringBuffer sb = StringBuffer();
    int offset = 1; // SQLite SUBSTR is 1-indexed
    const int chunkSize = 1000 * 1024; // 1MB chunks (approx 1,000,000 characters)
    
    while (true) {
      try {
        final chunkQuery = await db.rawQuery('''
          SELECT SUBSTR(attachments, ?, ?) as chunk
          FROM inspection_door_errors
          WHERE id = ?
        ''', [offset, chunkSize, errorId]);
        
        if (chunkQuery.isEmpty) break;
        final String chunk = chunkQuery.first['chunk'] as String? ?? '';
        if (chunk.isEmpty) break;
        
        sb.write(chunk);
        if (chunk.length < chunkSize) {
          break;
        }
        offset += chunk.length;
      } catch (e) {
        print('Error reading chunk for error ID $errorId at offset $offset: $e');
        break;
      }
    }
    return sb.toString();
  }

  // This method was missing its body in the previous diff, restoring it.
  static Future<List<InspectionDoorError>> getErrorsForInspectionDoor(int inspectionDoorId) async {
    final db = await getDb();
    
    final Set<String> existingColumns = await _getInspectionDoorErrorsColumns(db);
    final List<String> selectCols = [];
    final List<String> possibleCols = ['id', 'inspectionDoorId', 'errorId', 'errorCode', 'quantity', 'severity', 'notes', 'resolutionStatus'];
    for (final col in possibleCols) {
      if (existingColumns.contains(col)) {
        selectCols.add(col);
      }
    }

    final maps = await db.query(
      'inspection_door_errors',
      columns: selectCols,
      where: 'inspectionDoorId = ?',
      whereArgs: [inspectionDoorId],
    );
    
    final List<InspectionDoorError> errors = [];
    for (final map in maps) {
      final int? errorId = map['id'] as int?;
      String attachments = '';
      if (errorId != null && existingColumns.contains('attachments')) {
        try {
          final attachmentQuery = await db.query(
            'inspection_door_errors',
            columns: ['attachments'],
            where: 'id = ?',
            whereArgs: [errorId],
          );
          if (attachmentQuery.isNotEmpty) {
            attachments = attachmentQuery.first['attachments'] as String? ?? '';
          }
        } catch (e) {
          print('Error loading attachments for error ID $errorId: $e');
          attachments = await _fetchLargeAttachments(db, errorId);
        }
      }
      
      final Map<String, dynamic> fullMap = Map<String, dynamic>.from(map);
      fullMap['attachments'] = attachments;
      errors.add(InspectionDoorError.fromMap(fullMap));
    }
    return errors;
  }

  static Future<List<Map<String, dynamic>>> getDetailedErrorsForInspectionDoor(int inspectionDoorId) async {
    final db = await getDb();
    
    final Set<String> existingColumns = await _getInspectionDoorErrorsColumns(db);
    final List<String> selectCols = [];
    final List<String> possibleCols = ['id', 'inspectionDoorId', 'errorId', 'errorCode', 'quantity', 'severity', 'notes', 'resolutionStatus'];
    for (final col in possibleCols) {
      if (existingColumns.contains(col)) {
        selectCols.add('ide.$col');
      }
    }
    final String selectString = selectCols.join(', ');

    // FIX 2: Use LEFT JOIN with COALESCE fallbacks (matching Manager DB pattern)
    // so that errors are always visible even if the catalog FK is broken.
    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT $selectString,
             COALESCE(ec.code, ide.errorCode, 'UNKNOWN') AS code,
             COALESCE(ec.description, ide.notes, 'Keine Beschreibung') AS description,
             COALESCE(ec.category, '') AS category
      FROM inspection_door_errors ide
      LEFT JOIN error_catalog ec ON ide.errorId = ec.errorId
      WHERE ide.inspectionDoorId = ?
    ''', [inspectionDoorId]);

    final List<Map<String, dynamic>> finalResults = [];
    for (final row in results) {
      final int? errorId = row['id'] as int?;
      String attachments = '';
      if (errorId != null && existingColumns.contains('attachments')) {
        try {
          final attachmentQuery = await db.query(
            'inspection_door_errors',
            columns: ['attachments'],
            where: 'id = ?',
            whereArgs: [errorId],
          );
          if (attachmentQuery.isNotEmpty) {
            attachments = attachmentQuery.first['attachments'] as String? ?? '';
          }
        } catch (e) {
          print('Error loading attachments for error ID $errorId: $e');
          attachments = await _fetchLargeAttachments(db, errorId);
        }
      }

      final rowWithAttachments = Map<String, dynamic>.from(row);
      rowWithAttachments['attachments'] = attachments;
      finalResults.add(rowWithAttachments);
    }
    return finalResults;
  }
  static Future<void> deleteInspectionDoorError(int id) async {
    final db = await getDb();
    await db.delete('inspection_door_errors', where: 'id = ?', whereArgs: [id]);
  }

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

  /// When an inspector creates an error not in the catalog, this method
  /// creates a 'Pending' catalog entry and links it to the door instance.
  static Future<void> proposeNewError({
    required int inspectionDoorId,
    required String description,
    required String category,
    required String severity,
  }) async {
    final db = await getDb();
    
    await db.transaction((txn) async {
      // 1. Create a provisional catalog entry
      final String provisionalCode = 'REQ-${DateTime.now().millisecondsSinceEpoch}';
      final provisionalId = await txn.insert('error_catalog', {
        'code': provisionalCode,
        'description': description,
        'category': category,
        'status': 'Pending',
        'requestedBy': 'Inspector', // Ideally pass the actual user name
        'requestDate': DateTime.now().toIso8601String(),
        'sourceInspectionDoorId': inspectionDoorId,
      });
      print('LOCAL DB: Proposed new error created in catalog. ID: $provisionalId, Status: Pending');

      // 2. Create the door error instance linked to the provisional ID
      await txn.insert('inspection_door_errors', {
        'inspectionDoorId': inspectionDoorId,
        'errorId': provisionalId,
        'errorCode': provisionalCode,
        'quantity': 1,
        'severity': severity,
        'notes': 'Vorgeschlagener Fehler durch Inspektor',
        'resolutionStatus': 'open',
      });
    });
  }

  /// Specifically refreshes the local error catalog from the main database
  /// without clearing other job-related data (doors, inspections).
  static Future<void> refreshLocalCatalogFromMain() async {
    try {
      print('Refreshing local error catalog from main database...');
      // Fetch current master list from main DB
      final masterCatalog = await DatabaseService.getAllErrorCatalog(status: 'Approved');
      
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
      final data = item.toMap();
      batch.insert('error_catalog', data, conflictAlgorithm: algorithm);
    }
    await batch.commit(noResult: true);
  }

  /// Closes the database connection to allow file-level operations.
  /// Essential for Windows to release file locks.
  static Future<void> closeDb() async {
    if (_db != null) {
      final dbToClose = _db!;
      _db = null;
      if (dbToClose.isOpen) await dbToClose.close();
      print('Database connection closed and reference cleared.');
    }
  }

  /// Exports the internal working.db to a specified external path.
  static Future<void> exportWorkingDb(String destinationPath) async {
    // Ensure all transactions are committed and file handle is released
    await closeDb();
    
    final sourcePath = await _getWorkingDbPath();
    final sourceFile = File(sourcePath);
    
    if (!await sourceFile.exists()) {
      throw Exception('Export fehlgeschlagen: Quelldatenbank existiert nicht.');
    }

    await sourceFile.copy(destinationPath);
    print('Database exported to: $destinationPath');
  }

  /// Imports an external .db file to replace the internal working.db.
  /// Validates file existence, format, and schema compatibility.
  static Future<void> importWorkingDb(String sourcePath) async {
    final sourceFile = File(sourcePath);
    
    // 1. Basic File Validation
    if (!await sourceFile.exists()) {
      throw Exception('Import fehlgeschlagen: Quelldatei nicht gefunden.');
    }

    if (!sourcePath.toLowerCase().endsWith('.db')) {
      throw Exception('Import fehlgeschlagen: Ungültiges Dateiformat. Bitte wählen Sie eine .db Datei.');
    }

    // 2. Schema Compatibility Check
    Database? tempDb;
    try {
      if (Platform.isWindows || Platform.isLinux) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      tempDb = await openDatabase(sourcePath, readOnly: true);
      final tables = await tempDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((t) => t['name'] as String).toSet();
      
      if (!tableNames.contains('doors') || !tableNames.contains('inspections')) {
        throw Exception('Die ausgewählte Datei enthält keine gültigen Prüfungsdaten (Tabellen fehlen).');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Validierungsfehler: $e');
    } finally {
      await tempDb?.close();
    }

    // 3. Execute Import (Replace local working DB)
    await closeDb();
    
    final destinationPath = await _getWorkingDbPath();
    try {
      await sourceFile.copy(destinationPath);
      // Re-initialize to ensure migrations are applied if needed
      await getDb();
      print('Database successfully validated and imported.');
    } catch (e) {
      throw Exception('Fehler beim Dateizugriff während des Imports: $e');
    }
  }

  /// Imports an external inspection package and merges it into the local working DB.
  /// Allows technicians to load multiple inspection packages without losing existing local data.
  static Future<ImportReport> importAndMergePackage(String packagePath) async {
    final localDb = await getDb();
    
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final packageDb = await openDatabase(packagePath, readOnly: true);

    int newDoorsCount = 0;
    int updatedDoorsCount = 0;
    int newInspectionsCount = 0;
    int updatedInspectionsCount = 0;
    int totalErrorsImported = 0;
    int totalAttachmentsImported = 0;
    final List<DoorChangeItem> doorChanges = [];
    final List<String> newCatalogProposals = [];

    final List<DoorConflict> packageDoorConflicts = [];

    try {
      // Validate structure
      final tables = await packageDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((t) => t['name'] as String).toSet();
      if (!tableNames.contains('doors') || !tableNames.contains('inspections')) {
        throw Exception('Die Datei enthält keine gültigen Prüfungsdaten (Tabellen fehlen).');
      }

      await localDb.transaction((txn) async {
        final pInspections = await packageDb.query('inspections');
        final pDoors = await packageDb.query('doors');
        final pJunctions = await packageDb.query('inspection_doors');
        final pErrors = await packageDb.query('inspection_door_errors');
        final pCatalog = await packageDb.query('error_catalog');

        // 1. Merge catalog
        final catalogList = pCatalog.map((m) => ErrorCatalog.fromMap(m)).toList();
        for (var cat in catalogList) {
          final existing = await txn.query('error_catalog', where: 'code = ?', whereArgs: [cat.code], limit: 1);
          if (existing.isEmpty && cat.status == 'Pending') {
            newCatalogProposals.add('${cat.code}: ${cat.description}');
          }
        }
        await _batchInsertCatalog(txn, catalogList, ConflictAlgorithm.replace);

        // 2. Merge inspections
        for (var insp in pInspections) {
          final data = Map<String, dynamic>.from(insp);
          data.remove('doorCount');
          final jobNum = (insp['jobNumber'] ?? insp['auftragsnummer'] ?? '') as String;
          final existing = await txn.query('inspections', where: 'jobNumber = ?', whereArgs: [jobNum], limit: 1);
          if (existing.isNotEmpty) {
            updatedInspectionsCount++;
          } else {
            newInspectionsCount++;
          }
          await txn.insert('inspections', data, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 3. Merge doors
        for (var door in pDoors) {
          final alias = door['doorAlias'] as String? ?? '';
          final existing = await txn.query('doors', where: 'doorAlias = ?', whereArgs: [alias], limit: 1);
          if (existing.isNotEmpty) {
            updatedDoorsCount++;
          } else {
            newDoorsCount++;
          }
          await txn.insert('doors', door, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 4. Merge junctions
        for (var junction in pJunctions) {
          final doorId = junction['doorId'] as int?;
          final doorRow = doorId != null ? pDoors.firstWhere((d) => d['id'] == doorId, orElse: () => {}) : {};
          final alias = doorRow['doorAlias'] as String? ?? '';
          final doorNum = doorRow['doorNumber'] as String? ?? '';
          final roomDesig = doorRow['roomDesignation'] as String? ?? '';
          final status = junction['status'] as String? ?? 'InProgress';
          final junctionId = junction['id'] as int?;

          final existingJunction = await txn.query('inspection_doors',
              where: 'inspectionId = ? AND doorId = ?',
              whereArgs: [junction['inspectionId'], junction['doorId']],
              limit: 1);

          await txn.insert('inspection_doors', junction, conflictAlgorithm: ConflictAlgorithm.replace);

          final errCount = pErrors.where((e) => e['inspectionDoorId'] == junctionId).length;
          doorChanges.add(DoorChangeItem(
            doorAlias: alias,
            doorNumber: doorNum,
            roomDesignation: roomDesig,
            changeType: existingJunction.isEmpty ? 'new' : 'updated',
            status: status,
            errorCount: errCount,
          ));
        }

        // 5. Merge errors
        totalErrorsImported = pErrors.length;
        for (var err in pErrors) {
          final att = err['attachments'] as String? ?? '';
          if (att.isNotEmpty) {
            totalAttachmentsImported++;
          }
          await txn.insert('inspection_door_errors', err, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

      return ImportReport(
        packageName: basename(packagePath),
        importedAt: DateTime.now(),
        newDoorsCount: newDoorsCount,
        updatedDoorsCount: updatedDoorsCount,
        newInspectionsCount: newInspectionsCount,
        updatedInspectionsCount: updatedInspectionsCount,
        totalErrorsImported: totalErrorsImported,
        totalAttachmentsImported: totalAttachmentsImported,
        doorChanges: doorChanges,
        newCatalogProposals: newCatalogProposals,
        doorConflicts: packageDoorConflicts,
      );
    } finally {
      await packageDb.close();
    }
  }
}