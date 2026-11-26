// Local Database Service for Inspector Mobile App (Offline Work)
// Handles temporary data for current inspections: doors, errors, requests

import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/models/craftnote_models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class LocalDatabaseService {
  /// Canonical Local Database Schema Version (Single Source of Truth).
  /// Increment this ONLY when modifying schema tables/columns and adding onUpgrade handlers.
  static const int currentDatabaseVersion = 20;

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
      version: currentDatabaseVersion,
      onCreate: (db, version) async {
        // Doors table (local copy for current inspection)
        await db.execute('''
          CREATE TABLE doors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pos INTEGER,
            doorAlias TEXT UNIQUE,
            provisionalAlias TEXT,
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
            lintelHeightInsideOver1m INTEGER DEFAULT 0,
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
            lintelHeightOutsideOver1m INTEGER DEFAULT 0,
            lintelHeightValue TEXT,
            lintelHeightInsideValue TEXT,
            lintelHeightOutsideValue TEXT,
            manufactureYear TEXT DEFAULT '?',
            fsaDriveAcceptanceDate TEXT,
            notes TEXT DEFAULT ''
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
            projectNumber TEXT,
            isLocked INTEGER DEFAULT 0,
            orderType TEXT DEFAULT 'Wartung',
            repairDate TEXT,
            craftnoteProjectId TEXT,
            craftnoteFileId TEXT,
            craftnoteSyncStatus TEXT DEFAULT 'none',
            craftnoteLastSyncTime TEXT,
            assetType TEXT DEFAULT 'door'
          );
        ''');

        // Windows table (local copy)
        await db.execute('''
          CREATE TABLE windows (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            windowAlias TEXT UNIQUE,
            provisionalAlias TEXT,
            windowNumber TEXT,
            floor TEXT,
            roomNumber TEXT,
            roomDesignation TEXT,
            windowType TEXT,
            material TEXT,
            wingDimensions TEXT,
            fittings TEXT,
            windowFunctionOK INTEGER DEFAULT 1,
            hasRaffstore INTEGER DEFAULT 0,
            raffstoreOK INTEGER,
            notes TEXT DEFAULT ''
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

        // InspectionWindows table (local)
        await db.execute('''
          CREATE TABLE inspection_windows (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inspectionId INTEGER,
            windowId INTEGER,
            status TEXT,
            notes TEXT,
            attachments TEXT,
            syncStatus TEXT,
            FOREIGN KEY (inspectionId) REFERENCES inspections (inspectionId),
            FOREIGN KEY (windowId) REFERENCES windows (id)
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

        // InspectionWindowErrors table (local)
        await db.execute('''
          CREATE TABLE inspection_window_errors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inspectionWindowId INTEGER,
            errorId INTEGER,
            errorCode TEXT NOT NULL DEFAULT '',
            quantity INTEGER,
            severity TEXT,
            notes TEXT,
            resolutionStatus TEXT,
            attachments TEXT DEFAULT '',
            FOREIGN KEY (inspectionWindowId) REFERENCES inspection_windows (id)
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
            assetType TEXT DEFAULT 'door',
            requestedBy TEXT,
            requestDate TEXT,
            sourceInspectionDoorId INTEGER,
            sourceInspectionWindowId INTEGER,
            sourceInspectionRwaId INTEGER
          );
        ''');

        // RWA-Systeme tables (local copy)
        await db.execute('''
          CREATE TABLE rwa_systems (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            systemAlias TEXT UNIQUE,
            provisionalAlias TEXT,
            projectNumber TEXT,
            systemType TEXT,
            objectAddress TEXT,
            building TEXT,
            floor TEXT,
            room TEXT,
            centralType TEXT,
            fireButtonSpec TEXT,
            smokeDetectorSpec TEXT,
            actuatorSpec TEXT,
            ventilationButtonSpec TEXT,
            emergencyPowerSpec TEXT,
            co2BottleSpec TEXT,
            thermalBottleSpec TEXT,
            rwaFlapSpec TEXT,
            ventilationFlapSpec TEXT,
            damperSpec TEXT,
            systemFunctionOK INTEGER DEFAULT 1,
            notes TEXT DEFAULT ''
          );
        ''');

        await db.execute('''
          CREATE TABLE inspection_rwa (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inspectionId INTEGER,
            rwaSystemId INTEGER,
            status TEXT,
            notes TEXT,
            attachments TEXT,
            syncStatus TEXT,
            FOREIGN KEY (inspectionId) REFERENCES inspections (inspectionId),
            FOREIGN KEY (rwaSystemId) REFERENCES rwa_systems (id)
          );
        ''');

        await db.execute('''
          CREATE TABLE inspection_rwa_settings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inspectionRwaId INTEGER,
            settingName TEXT,
            result TEXT,
            rawResult TEXT,
            annotation TEXT,
            FOREIGN KEY (inspectionRwaId) REFERENCES inspection_rwa (id)
          );
        ''');

        await db.execute('''
          CREATE TABLE inspection_rwa_errors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inspectionRwaId INTEGER,
            settingName TEXT,
            errorId INTEGER,
            errorCode TEXT NOT NULL DEFAULT '',
            quantity INTEGER,
            severity TEXT,
            notes TEXT,
            resolutionStatus TEXT,
            attachments TEXT DEFAULT '',
            FOREIGN KEY (inspectionRwaId) REFERENCES inspection_rwa (id)
          );
        ''');

        // Craftnote offline upload queue table
        await db.execute('''
          CREATE TABLE IF NOT EXISTS craftnote_upload_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inspectionId INTEGER,
            craftnoteProjectId TEXT NOT NULL,
            packageFilePath TEXT NOT NULL,
            pdfFilePath TEXT,
            queuedAt TEXT NOT NULL,
            attempts INTEGER DEFAULT 0,
            lastError TEXT
          );
        ''');

        // Add indices for optimized searching
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_doors_number ON doors (doorNumber)');
        await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_local_doors_alias ON doors (doorAlias)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_doors_provisional_alias ON doors (provisionalAlias)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_windows_number ON windows (windowNumber)');
        await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_local_windows_alias ON windows (windowAlias)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_windows_provisional_alias ON windows (provisionalAlias)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_insp_win_insp ON inspection_windows (inspectionId)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_insp_win_win ON inspection_windows (windowId)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_insp_win_err_win ON inspection_window_errors (inspectionWindowId)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_rwa_alias ON rwa_systems (systemAlias)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_rwa_provisional_alias ON rwa_systems (provisionalAlias)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_rwa_project ON rwa_systems (projectNumber)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_insp_rwa_insp ON inspection_rwa (inspectionId)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_insp_rwa_sys ON inspection_rwa (rwaSystemId)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_insp_rwa_set_rwa ON inspection_rwa_settings (inspectionRwaId)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_insp_rwa_err_rwa ON inspection_rwa_errors (inspectionRwaId)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_ec_description ON error_catalog (description)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_local_insp_craftnote ON inspections (craftnoteProjectId)');
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
            await db.execute(
                "ALTER TABLE error_catalog ADD COLUMN status TEXT NOT NULL DEFAULT 'Approved'");
            await db.execute(
                "ALTER TABLE error_catalog ADD COLUMN requestedBy TEXT");
            await db.execute(
                "ALTER TABLE error_catalog ADD COLUMN requestDate TEXT");
            await db.execute(
                "ALTER TABLE error_catalog ADD COLUMN sourceInspectionDoorId INTEGER");
          } catch (e) {
            print(
                'Local DB: Consolidation columns might already exist in error_catalog: $e');
          }

          // Remove error_requests table
          await db.execute('DROP TABLE IF EXISTS error_requests');

          print(
              'Local Database upgraded to version $newVersion: Schema aligned with main DB.');
        }
        if (oldVersion < 3) {
          // Add indices for optimized searching in existing databases
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_local_doors_number ON doors (doorNumber)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_local_ec_description ON error_catalog (description)');
          print(
              'Local Database upgraded to version 3: Search indices created.');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE doors ADD COLUMN doorAlias TEXT');
          await db.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_local_doors_alias ON doors (doorAlias)');
          print('Local Database upgraded to version 4: Door Alias added.');
        }
        if (oldVersion < 5) {
          // Data Migration: Normalize values to prevent Dropdown crashes in local DB
          await db.execute(
              "UPDATE doors SET dinConfiguration = 'DIN L' WHERE dinConfiguration = 'L'");
          await db.execute(
              "UPDATE doors SET dinConfiguration = 'DIN R' WHERE dinConfiguration = 'R'");
          await db.execute(
              "UPDATE doors SET closerType = 'TS93' WHERE closerType = 'TS 5000'");
          await db.execute(
              "UPDATE doors SET manufacturer = 'Dorma' WHERE manufacturer = 'HÖRMANN'");
          await db.execute(
              "UPDATE doors SET fittingType = 'Drücker' WHERE fittingType = 'Drücker/Drücker'");
          print('Local Database upgraded to version 5: Values normalized.');
        }
        if (oldVersion < 6) {
          // Comprehensive Normalization for Local DB
          await db.execute(
              "UPDATE doors SET closerType = 'TS93' WHERE closerType = 'TS 5000' OR closerType IS NULL");
          await db.execute(
              "UPDATE doors SET manufacturer = 'Dorma' WHERE manufacturer = 'HÖRMANN' OR manufacturer IS NULL");
          await db.execute(
              "UPDATE doors SET fittingType = 'Drücker' WHERE fittingType = 'Drücker/Drücker' OR fittingType IS NULL");
          await db.execute(
              "UPDATE doors SET dinConfiguration = 'DIN L' WHERE dinConfiguration = 'L' OR dinConfiguration IS NULL");
          await db.execute(
              "UPDATE doors SET dinConfiguration = 'DIN R' WHERE dinConfiguration = 'R'");
          print(
              'Local Database upgraded to version 6: Comprehensive values normalized.');
        }
        if (oldVersion < 7) {
          try {
            await db.execute(
                "ALTER TABLE inspection_door_errors ADD COLUMN attachments TEXT DEFAULT ''");
            print(
                'Local Database upgraded to version 7: attachments column added to inspection_door_errors.');
          } catch (e) {
            print('Local DB migration warning (attachments): \$e');
          }
        }
        if (oldVersion < 8) {
          try {
            await db.execute(
                "ALTER TABLE inspection_door_errors ADD COLUMN errorCode TEXT NOT NULL DEFAULT ''");
            // Backfill errorCode from local error_catalog
            await db.execute('''
              UPDATE inspection_door_errors
              SET errorCode = COALESCE(
                (SELECT code FROM error_catalog WHERE error_catalog.errorId = inspection_door_errors.errorId),
                ''
              )
              WHERE errorCode IS NULL OR errorCode = ''
            ''');
            print(
                'Local Database upgraded to version 8: errorCode column added and backfilled.');
          } catch (e) {
            print('Local DB migration warning (errorCode): \$e');
          }
        }

        if (oldVersion < 9) {
          try {
            await db.execute(
                'ALTER TABLE inspections ADD COLUMN projectNumber TEXT');
            print(
                'Local Database upgraded to version 9: projectNumber column added.');
          } catch (e) {
            print('Local DB migration warning (projectNumber): $e');
          }
        }

        if (oldVersion < 10) {
          try {
            await db.execute(
                "ALTER TABLE doors ADD COLUMN approvalNumber TEXT DEFAULT '?'");
            await db.execute(
                "ALTER TABLE doors ADD COLUMN manufacturerNumber TEXT DEFAULT '?'");
            await db.execute(
                "ALTER TABLE doors ADD COLUMN dopNumber TEXT DEFAULT '?'");
            await db.execute(
                "ALTER TABLE doors ADD COLUMN lintelHeightOver1m INTEGER DEFAULT 0");
            await db.execute(
                "ALTER TABLE doors ADD COLUMN lintelHeightValue INTEGER");
            await db.execute(
                "ALTER TABLE doors ADD COLUMN manufactureYear TEXT DEFAULT '?'");
            print(
                'Local Database upgraded to version 10: new door properties added.');
          } catch (e) {
            print('Local DB migration warning (v10 columns): $e');
          }
        }

        if (oldVersion < 11) {
          try {
            await db.execute(
                "ALTER TABLE doors ADD COLUMN fsaDriveAcceptanceDate TEXT");
            print(
                'Local Database upgraded to version 11: fsaDriveAcceptanceDate column added.');
          } catch (e) {
            print('Local DB migration warning (v11 column): $e');
          }
        }

        if (oldVersion < 12) {
          try {
            await db.execute(
                "ALTER TABLE doors ADD COLUMN lintelHeightInsideOver1m INTEGER DEFAULT 0");
            await db.execute(
                "ALTER TABLE doors ADD COLUMN lintelHeightOutsideOver1m INTEGER DEFAULT 0");
            try {
              await db.execute(
                  "UPDATE doors SET lintelHeightOutsideOver1m = lintelHeightOver1m WHERE lintelHeightOver1m = 1");
            } catch (_) {}
            print(
                'Local Database upgraded to version 12: lintel height properties updated.');
          } catch (e) {
            print('Local DB migration warning (v12 columns): $e');
          }
        }

        if (oldVersion < 13) {
          try {
            await db.execute(
                "ALTER TABLE doors ADD COLUMN lintelHeightInsideValue TEXT");
            await db.execute(
                "ALTER TABLE doors ADD COLUMN lintelHeightOutsideValue TEXT");
            try {
              await db.execute(
                  "UPDATE doors SET lintelHeightInsideValue = lintelHeightValue WHERE lintelHeightInsideOver1m = 1 AND (lintelHeightInsideValue IS NULL OR lintelHeightInsideValue = '')");
              await db.execute(
                  "UPDATE doors SET lintelHeightOutsideValue = lintelHeightValue WHERE lintelHeightOutsideOver1m = 1 AND (lintelHeightOutsideValue IS NULL OR lintelHeightOutsideValue = '')");
            } catch (_) {}
            print(
                'Local Database upgraded to version 13: lintelHeightInsideValue and lintelHeightOutsideValue added.');
          } catch (e) {
            print('Local DB migration warning (v13 columns): $e');
          }
        }

        if (oldVersion < 14) {
          try {
            await db
                .execute("ALTER TABLE doors ADD COLUMN provisionalAlias TEXT");
            await db.execute(
                "UPDATE doors SET provisionalAlias = doorAlias WHERE provisionalAlias IS NULL OR provisionalAlias = ''");
            await db.execute(
                "CREATE INDEX IF NOT EXISTS idx_local_doors_provisional_alias ON doors (provisionalAlias)");
            print(
                'Local Database upgraded to version 14: provisionalAlias column added and backfilled.');
          } catch (e) {
            print('Local DB migration warning (v14 column): $e');
          }
        }

        if (oldVersion < 15) {
          try {
            await db
                .execute("ALTER TABLE doors ADD COLUMN notes TEXT DEFAULT ''");
            print(
                'Local Database upgraded to version 15: notes column added to doors table.');
          } catch (e) {
            print('Local DB migration warning (v15 column): $e');
          }
        }

        if (oldVersion < 16) {
          try {
            await db.execute(
                "ALTER TABLE inspections ADD COLUMN isLocked INTEGER DEFAULT 0");
            print(
                'Local Database upgraded to version 16: isLocked column added to inspections table.');
          } catch (e) {
            print('Local DB migration warning (v16 column): $e');
          }
        }

        if (oldVersion < 17) {
          try {
            await db.execute(
                "ALTER TABLE inspections ADD COLUMN orderType TEXT DEFAULT 'Wartung'");
            await db
                .execute("ALTER TABLE inspections ADD COLUMN repairDate TEXT");
            print(
                'Local Database upgraded to version 17: orderType and repairDate columns added to inspections table.');
          } catch (e) {
            print('Local DB migration warning (v17 columns): $e');
          }
        }

        if (oldVersion < 18) {
          try {
            await db.execute(
                "ALTER TABLE inspections ADD COLUMN craftnoteProjectId TEXT");
            await db.execute(
                "ALTER TABLE inspections ADD COLUMN craftnoteFileId TEXT");
            await db.execute(
                "ALTER TABLE inspections ADD COLUMN craftnoteSyncStatus TEXT DEFAULT 'none'");
            await db.execute(
                "ALTER TABLE inspections ADD COLUMN craftnoteLastSyncTime TEXT");
            await db.execute(
                "CREATE INDEX IF NOT EXISTS idx_local_insp_craftnote ON inspections (craftnoteProjectId)");
            await db.execute('''
              CREATE TABLE IF NOT EXISTS craftnote_upload_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                inspectionId INTEGER,
                craftnoteProjectId TEXT NOT NULL,
                packageFilePath TEXT NOT NULL,
                pdfFilePath TEXT,
                queuedAt TEXT NOT NULL,
                attempts INTEGER DEFAULT 0,
                lastError TEXT
              );
            ''');
            print(
                '[LocalDatabaseService] Local Database upgraded to version 18: Craftnote columns and upload queue added.');
          } catch (e) {
            print('Local DB migration warning (v18 columns): $e');
          }
        }

        if (oldVersion < 19) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS windows (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                windowAlias TEXT UNIQUE,
                provisionalAlias TEXT,
                windowNumber TEXT,
                floor TEXT,
                roomNumber TEXT,
                roomDesignation TEXT,
                windowType TEXT,
                material TEXT,
                wingDimensions TEXT,
                fittings TEXT,
                windowFunctionOK INTEGER DEFAULT 1,
                hasRaffstore INTEGER DEFAULT 0,
                raffstoreOK INTEGER,
                notes TEXT DEFAULT ''
              );
            ''');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_local_windows_number ON windows (windowNumber)');
            await db.execute(
                'CREATE UNIQUE INDEX IF NOT EXISTS idx_local_windows_alias ON windows (windowAlias)');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_local_windows_provisional_alias ON windows (provisionalAlias)');

            await db.execute('''
              CREATE TABLE IF NOT EXISTS inspection_windows (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                inspectionId INTEGER,
                windowId INTEGER,
                status TEXT,
                notes TEXT,
                attachments TEXT,
                syncStatus TEXT,
                FOREIGN KEY (inspectionId) REFERENCES inspections (inspectionId),
                FOREIGN KEY (windowId) REFERENCES windows (id)
              );
            ''');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_local_insp_win_insp ON inspection_windows (inspectionId)');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_local_insp_win_win ON inspection_windows (windowId)');

            await db.execute('''
              CREATE TABLE IF NOT EXISTS inspection_window_errors (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                inspectionWindowId INTEGER,
                errorId INTEGER,
                errorCode TEXT NOT NULL DEFAULT '',
                quantity INTEGER,
                severity TEXT,
                notes TEXT,
                resolutionStatus TEXT,
                attachments TEXT DEFAULT '',
                FOREIGN KEY (inspectionWindowId) REFERENCES inspection_windows (id)
              );
            ''');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_local_insp_win_err_win ON inspection_window_errors (inspectionWindowId)');

            try {
              await db.execute(
                  "ALTER TABLE inspections ADD COLUMN assetType TEXT DEFAULT 'door'");
            } catch (_) {}

            try {
              await db.execute(
                  "ALTER TABLE error_catalog ADD COLUMN assetType TEXT DEFAULT 'door'");
            } catch (_) {}

            try {
              await db.execute(
                  "ALTER TABLE error_catalog ADD COLUMN sourceInspectionWindowId INTEGER");
            } catch (_) {}

            print(
                '[LocalDatabaseService] Local Database upgraded to version 19: Windows, InspectionWindows, and InspectionWindowErrors tables added.');
          } catch (e) {
            print('Local DB migration warning (v19 columns/tables): $e');
          }
        }

        if (oldVersion < 20) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS rwa_systems (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                systemAlias TEXT UNIQUE,
                provisionalAlias TEXT,
                projectNumber TEXT,
                systemType TEXT,
                objectAddress TEXT,
                building TEXT,
                floor TEXT,
                room TEXT,
                centralType TEXT,
                fireButtonSpec TEXT,
                smokeDetectorSpec TEXT,
                actuatorSpec TEXT,
                ventilationButtonSpec TEXT,
                emergencyPowerSpec TEXT,
                co2BottleSpec TEXT,
                thermalBottleSpec TEXT,
                rwaFlapSpec TEXT,
                ventilationFlapSpec TEXT,
                damperSpec TEXT,
                systemFunctionOK INTEGER DEFAULT 1,
                notes TEXT DEFAULT ''
              );
            ''');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_local_rwa_alias ON rwa_systems (systemAlias)');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_local_rwa_provisional_alias ON rwa_systems (provisionalAlias)');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_local_rwa_project ON rwa_systems (projectNumber)');

            await db.execute('''
              CREATE TABLE IF NOT EXISTS inspection_rwa (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                inspectionId INTEGER,
                rwaSystemId INTEGER,
                status TEXT,
                notes TEXT,
                attachments TEXT,
                syncStatus TEXT,
                FOREIGN KEY (inspectionId) REFERENCES inspections (inspectionId),
                FOREIGN KEY (rwaSystemId) REFERENCES rwa_systems (id)
              );
            ''');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_local_insp_rwa_insp ON inspection_rwa (inspectionId)');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_local_insp_rwa_sys ON inspection_rwa (rwaSystemId)');

            await db.execute('''
              CREATE TABLE IF NOT EXISTS inspection_rwa_settings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                inspectionRwaId INTEGER,
                settingName TEXT,
                result TEXT,
                rawResult TEXT,
                annotation TEXT,
                FOREIGN KEY (inspectionRwaId) REFERENCES inspection_rwa (id)
              );
            ''');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_local_insp_rwa_set_rwa ON inspection_rwa_settings (inspectionRwaId)');

            await db.execute('''
              CREATE TABLE IF NOT EXISTS inspection_rwa_errors (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                inspectionRwaId INTEGER,
                settingName TEXT,
                errorId INTEGER,
                errorCode TEXT NOT NULL DEFAULT '',
                quantity INTEGER,
                severity TEXT,
                notes TEXT,
                resolutionStatus TEXT,
                attachments TEXT DEFAULT '',
                FOREIGN KEY (inspectionRwaId) REFERENCES inspection_rwa (id)
              );
            ''');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_local_insp_rwa_err_rwa ON inspection_rwa_errors (inspectionRwaId)');

            try {
              await db.execute(
                  "ALTER TABLE error_catalog ADD COLUMN sourceInspectionRwaId INTEGER");
            } catch (_) {}

            print(
                '[LocalDatabaseService] Local Database upgraded to version 20: RWA-Systeme tables added.');
          } catch (e) {
            print('Local DB migration warning (v20 columns/tables): $e');
          }
        }
      },
    );

    await _populateMissingAliases(_db!);

    return _db!;
  }

  /// Sets or updates the lock status for a given inspection ID in Local DB.
  static Future<void> setInspectionLockStatus(
      int inspectionId, bool isLocked) async {
    final db = await getDb();
    await db.update(
      'inspections',
      {'isLocked': isLocked ? 1 : 0},
      where: 'inspectionId = ?',
      whereArgs: [inspectionId],
    );
  }

  static Future<void> _populateMissingAliases(Database db) async {
    final List<Map<String, dynamic>> rows = await db.rawQuery('''
      SELECT d.id, d.doorNumber, d.floor, d.pos, i.projectNumber
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
      final projectNumber = row['projectNumber'] as String? ?? '';
      final pos = row['pos'] ?? 0;

      String generated = Door.generateAlias(
          projectNumber: projectNumber,
          pos: pos,
          floor: floor,
          doorNumber: doorNumber);
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
        final base = generated.length > maxBaseLen
            ? generated.substring(0, maxBaseLen)
            : generated;
        uniqueAlias = '$base$suffixStr';
        suffix++;
      }

      await db.update(
        'doors',
        {
          'doorAlias': uniqueAlias,
          'provisionalAlias': uniqueAlias,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// Updates the doorAlias for a door ID in local working.db.
  /// Preserves existing alias in provisionalAlias if not already set.
  static Future<int> updateDoorAlias(int doorId, String newAlias) async {
    final db = await getDb();
    final cleanAlias = newAlias.trim();
    final maps =
        await db.query('doors', where: 'id = ?', whereArgs: [doorId], limit: 1);
    if (maps.isNotEmpty) {
      final currentDoor = Door.fromMap(maps.first);
      final provisional = (currentDoor.provisionalAlias != null &&
              currentDoor.provisionalAlias!.isNotEmpty)
          ? currentDoor.provisionalAlias
          : (currentDoor.doorAlias ?? cleanAlias);
      return await db.update(
        'doors',
        {
          'doorAlias': cleanAlias,
          'provisionalAlias': provisional,
        },
        where: 'id = ?',
        whereArgs: [doorId],
      );
    }
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
      print(
          'Downloading Job Package for ${inspectionIds.length} inspections...');

      // 1. Fetch all related records from Master DB using our new batch helpers
      final doorList =
          await DatabaseService.getDoorsByInspectionIds(inspectionIds);

      final List<Map<String, dynamic>> allJunctions = [];
      for (int id in inspectionIds) {
        allJunctions
            .addAll(await DatabaseService.getInspectionDoorsByInspectionId(id));
      }

      final List<int> junctionIds =
          allJunctions.map((j) => j['id'] as int).toList();
      final errorList =
          await DatabaseService.getErrorsForInspectionDoorIds(junctionIds);

      // Fetch related window records from Master DB
      final List<Map<String, dynamic>> allWindowJunctions = [];
      final List<Window> windowList = [];
      for (int id in inspectionIds) {
        allWindowJunctions.addAll(
            await DatabaseService.getInspectionWindowsByInspectionId(id));
        final wins = await DatabaseService.getWindowsByInspectionId(id);
        for (final w in wins) {
          if (!windowList.any((existing) => existing.id == w.id)) {
            windowList.add(w);
          }
        }
      }

      final List<InspectionWindowError> windowErrors = [];
      for (final j in allWindowJunctions) {
        final jId = j['id'] as int;
        final errs = await DatabaseService.getInspectionWindowErrors(jId);
        windowErrors.addAll(errs);
      }

      // Fetch related RWA records from Master DB
      final List<Map<String, dynamic>> allRwaJunctions = [];
      final List<RwaSystem> rwaList = [];
      for (int id in inspectionIds) {
        allRwaJunctions.addAll(
            await DatabaseService.getInspectionRwasByInspectionId(id));
        final rwas = await DatabaseService.getRwaSystemsByInspectionId(id);
        for (final r in rwas) {
          if (!rwaList.any((existing) => existing.id == r.id)) {
            rwaList.add(r);
          }
        }
      }

      final List<RwaInspectionSetting> rwaSettings = [];
      final List<InspectionRwaError> rwaErrors = [];
      for (final j in allRwaJunctions) {
        final jId = j['id'] as int;
        final sets = await DatabaseService.getRwaInspectionSettings(jId);
        rwaSettings.addAll(sets);
        final errs = await DatabaseService.getInspectionRwaErrors(jId);
        rwaErrors.addAll(errs);
      }
      // Resolve full inspection objects for the local DB
      final allMainInspections = await DatabaseService.searchInspections('');
      final selectedInspections = allMainInspections
          .where((i) => inspectionIds.contains(i['inspectionId']))
          .toList();

      // Ensure any inspections not returned in the first 100 search results are fetched directly
      for (int id in inspectionIds) {
        if (!selectedInspections.any((i) => i['inspectionId'] == id)) {
          final directInsp = await DatabaseService.getInspectionById(id);
          if (directInsp != null) {
            selectedInspections.add(directInsp);
          }
        }
      }

      // Fetch the full approved catalog to include in the package
      final masterCatalog =
          await DatabaseService.getAllErrorCatalog(status: 'Approved');

      final db = await getDb();
      await db.transaction((txn) async {
        // Purge old local job data to enforce Isolation Protocol
        await txn.delete('inspection_door_errors');
        await txn.delete('inspection_doors');
        await txn.delete('inspections');
        await txn.delete('doors');
        await txn.delete('inspection_window_errors');
        await txn.delete('inspection_windows');
        await txn.delete('windows');
        await txn.delete('inspection_rwa_errors');
        await txn.delete('inspection_rwa_settings');
        await txn.delete('inspection_rwa');
        await txn.delete('rwa_systems');

        // 3. Populate local Inspections from the downloaded package
        final localInspCols = await _getTableColumns(txn, 'inspections');
        final localDoorCols = await _getTableColumns(txn, 'doors');
        final localJunctionCols =
            await _getTableColumns(txn, 'inspection_doors');
        final localWinCols = await _getTableColumns(txn, 'windows');
        final localWinJuncCols =
            await _getTableColumns(txn, 'inspection_windows');
        final localWinErrCols =
            await _getTableColumns(txn, 'inspection_window_errors');
        final localRwaCols = await _getTableColumns(txn, 'rwa_systems');
        final localRwaJuncCols =
            await _getTableColumns(txn, 'inspection_rwa');
        final localRwaSetCols =
            await _getTableColumns(txn, 'inspection_rwa_settings');
        final localRwaErrCols =
            await _getTableColumns(txn, 'inspection_rwa_errors');

        for (var insp in selectedInspections) {
          final Map<String, dynamic> data = Map<String, dynamic>.from(insp);
          // Ensure legacy packages are mapped to new English keys
          if (data.containsKey('auftragsnummer') &&
              !data.containsKey('jobNumber')) {
            data['jobNumber'] = data['auftragsnummer'];
          }
          data.remove('doorCount');
          data.removeWhere((key, _) => !localInspCols.contains(key));
          await txn.insert('inspections', data,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (var junction in allJunctions) {
          final Map<String, dynamic> jData =
              Map<String, dynamic>.from(junction);
          // New exported packages start in Pending (Offen) state for inspector
          jData['status'] = 'Pending';
          jData.removeWhere((key, _) => !localJunctionCols.contains(key));
          await txn.insert('inspection_doors', jData,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (var door in doorList) {
          final dData = door.toMap();
          dData.removeWhere((key, _) => !localDoorCols.contains(key));
          await txn.insert('doors', dData,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (var win in windowList) {
          final wData = win.toMap();
          wData.removeWhere((key, _) => !localWinCols.contains(key));
          await txn.insert('windows', wData,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (var junction in allWindowJunctions) {
          final Map<String, dynamic> jData =
              Map<String, dynamic>.from(junction);
          jData['status'] = 'Pending';
          jData.removeWhere((key, _) => !localWinJuncCols.contains(key));
          await txn.insert('inspection_windows', jData,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (var err in windowErrors) {
          final eData = err.toMap();
          eData.removeWhere((key, _) => !localWinErrCols.contains(key));
          await txn.insert('inspection_window_errors', eData,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (var rwa in rwaList) {
          final rData = rwa.toMap();
          rData.removeWhere((key, _) => !localRwaCols.contains(key));
          await txn.insert('rwa_systems', rData,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (var junction in allRwaJunctions) {
          final Map<String, dynamic> jData =
              Map<String, dynamic>.from(junction);
          jData['status'] = 'Pending';
          jData.removeWhere((key, _) => !localRwaJuncCols.contains(key));
          await txn.insert('inspection_rwa', jData,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (var setting in rwaSettings) {
          final sData = setting.toMap();
          sData.removeWhere((key, _) => !localRwaSetCols.contains(key));
          await txn.insert('inspection_rwa_settings', sData,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (var err in rwaErrors) {
          final eData = err.toMap();
          eData.removeWhere((key, _) => !localRwaErrCols.contains(key));
          await txn.insert('inspection_rwa_errors', eData,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        // FIX 1: Insert catalog BEFORE errors so we can remap errorId FKs.
        // The Master DB and Local DB have independent AUTOINCREMENT sequences,
        // so we must ensure the local catalog IDs are established first.
        await _batchInsertCatalog(
            txn, masterCatalog, ConflictAlgorithm.replace);

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
          if (errorCode.isNotEmpty &&
              codeToLocalErrorId.containsKey(errorCode)) {
            data['errorId'] = codeToLocalErrorId[errorCode];
          }

          await txn.insert('inspection_door_errors', data,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    } catch (e) {
      print('Critical error during package download: $e');
      rethrow;
    }
  }

  /// Creates a specific result package containing only the selected doors and their inspections.
  /// This implements the "Inspector Export" requirement.
  static Future<void> exportSelectiveJobPackage(
      List<int> doorIds, String destinationPath) async {
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
    await db
        .delete('inspection_door_errors'); // Clear all inspection_door_errors

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
      await txn.execute(
          'DELETE FROM doors WHERE id NOT IN (SELECT DISTINCT doorId FROM inspection_doors)');
    });
  }

  // ─────────────────────────────────────────────────────────────
  // DOORS
  // ─────────────────────────────────────────────────────────────

  static Future<int> insertDoor(Door door) async {
    final db = await getDb();
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
      lintelHeightInsideOver1m: false,
      lintelHeightOutsideOver1m: false,
      escapeDoorControl: 'Nein',
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

  static Future<Door?> getDoorById(int id) async {
    final db = await getDb();
    final maps = await db.query(
      'doors',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return maps.isNotEmpty ? Door.fromMap(maps.first) : null;
  }

  static Future<Door?> getDoorByAlias(String alias) async {
    final db = await getDb();
    final clean = alias.trim();
    final maps = await db.query(
      'doors',
      where: 'doorAlias = ? OR provisionalAlias = ?',
      whereArgs: [clean, clean],
      limit: 1,
    );
    return maps.isNotEmpty ? Door.fromMap(maps.first) : null;
  }

  /// Finds an existing door matching the given barcode (doorAlias or provisionalAlias),
  /// optionally excluding a specific door ID.
  static Future<Door?> findDoorByBarcode(String barcode,
      {int? excludeDoorId}) async {
    final clean = barcode.trim();
    if (clean.isEmpty) return null;
    final db = await getDb();
    final String whereClause = excludeDoorId != null
        ? '(doorAlias = ? OR provisionalAlias = ?) AND id != ?'
        : 'doorAlias = ? OR provisionalAlias = ?';
    final List<dynamic> whereArgs =
        excludeDoorId != null ? [clean, clean, excludeDoorId] : [clean, clean];

    final maps = await db.query(
      'doors',
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1,
    );
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
    await db
        .update('doors', door.toMap(), where: 'id = ?', whereArgs: [door.id!]);
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
  // WINDOWS (LOCAL)
  // ─────────────────────────────────────────────────────────────

  static Future<int> insertWindow(Window window) async {
    final db = await getDb();
    return await db.insert(
      'windows',
      window.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateWindow(Window window) async {
    final db = await getDb();
    if (window.id == null) return;
    await db.update(
      'windows',
      window.toMap(),
      where: 'id = ?',
      whereArgs: [window.id],
    );
  }

  static Future<void> deleteWindow(int id) async {
    await deleteWindows([id]);
  }

  static Future<void> deleteWindows(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await getDb();
    final idList = ids.join(',');
    await db.transaction((txn) async {
      await txn.execute('''
        DELETE FROM inspection_window_errors 
        WHERE inspectionWindowId IN (SELECT id FROM inspection_windows WHERE windowId IN ($idList))
      ''');
      await txn.delete('inspection_windows', where: 'windowId IN ($idList)');
      await txn.delete('windows', where: 'id IN ($idList)');
    });
  }

  static Future<Window?> getWindowById(int id) async {
    final db = await getDb();
    final maps = await db.query(
      'windows',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return maps.isNotEmpty ? Window.fromMap(maps.first) : null;
  }

  static Future<Window?> getWindowByAlias(String alias) async {
    final db = await getDb();
    final clean = alias.trim();
    final maps = await db.query(
      'windows',
      where: 'windowAlias = ? OR provisionalAlias = ?',
      whereArgs: [clean, clean],
      limit: 1,
    );
    return maps.isNotEmpty ? Window.fromMap(maps.first) : null;
  }

  static Future<Window?> findWindowByBarcode(String barcode,
      {int? excludeWindowId}) async {
    final clean = barcode.trim();
    if (clean.isEmpty) return null;
    final db = await getDb();
    final String whereClause = excludeWindowId != null
        ? '(windowAlias = ? OR provisionalAlias = ?) AND id != ?'
        : 'windowAlias = ? OR provisionalAlias = ?';
    final List<dynamic> whereArgs = excludeWindowId != null
        ? [clean, clean, excludeWindowId]
        : [clean, clean];

    final maps = await db.query(
      'windows',
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1,
    );
    return maps.isNotEmpty ? Window.fromMap(maps.first) : null;
  }

  static Future<int> updateWindowAlias(int windowId, String newAlias) async {
    final db = await getDb();
    final cleanAlias = newAlias.trim();
    final maps = await db.query('windows',
        where: 'id = ?', whereArgs: [windowId], limit: 1);
    if (maps.isNotEmpty) {
      final currentWindow = Window.fromMap(maps.first);
      final provisional = (currentWindow.provisionalAlias != null &&
              currentWindow.provisionalAlias!.isNotEmpty)
          ? currentWindow.provisionalAlias
          : (currentWindow.windowAlias ?? cleanAlias);
      return await db.update(
        'windows',
        {
          'windowAlias': cleanAlias,
          'provisionalAlias': provisional,
        },
        where: 'id = ?',
        whereArgs: [windowId],
      );
    }
    return await db.update(
      'windows',
      {'windowAlias': cleanAlias},
      where: 'id = ?',
      whereArgs: [windowId],
    );
  }

  static Future<List<Window>> getAllWindows() async {
    final db = await getDb();
    final maps = await db.query('windows');
    return maps.map((m) => Window.fromMap(m)).toList();
  }

  static Future<List<Window>> getWindowsByInspectionId(int inspectionId) async {
    return getWindowsByInspectionIds([inspectionId]);
  }

  static Future<List<Window>> getWindowsByInspectionIds(List<int> inspectionIds,
      {String query = ''}) async {
    if (inspectionIds.isEmpty) return [];
    final db = await getDb();
    final String idString = inspectionIds.join(',');
    final cleanQuery = query.trim();

    if (cleanQuery.isEmpty) {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT w.*, iw.status as inspectionStatus, iw.notes as inspectionNotes, iw.attachments as inspectionAttachments
        FROM windows w
        INNER JOIN inspection_windows iw ON w.id = iw.windowId
        WHERE iw.inspectionId IN ($idString)
        ORDER BY w.windowNumber ASC
      ''');
      return maps.map((map) => Window.fromMap(map)).toList();
    }

    final searchTerm = '%$cleanQuery%';
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT DISTINCT w.*, iw.status as inspectionStatus, iw.notes as inspectionNotes, iw.attachments as inspectionAttachments
      FROM windows w
      INNER JOIN inspection_windows iw ON w.id = iw.windowId
      LEFT JOIN inspection_window_errors iwe ON iw.id = iwe.inspectionWindowId
      LEFT JOIN error_catalog ec ON (iwe.errorId = ec.errorId OR (iwe.errorCode IS NOT NULL AND iwe.errorCode != '' AND iwe.errorCode = ec.code))
      WHERE iw.inspectionId IN ($idString)
        AND (
          w.windowNumber LIKE ? 
          OR w.roomNumber LIKE ? 
          OR w.roomDesignation LIKE ?
          OR w.windowAlias LIKE ?
          OR w.provisionalAlias LIKE ?
          OR w.floor LIKE ?
          OR iw.notes LIKE ?
          OR iwe.errorCode LIKE ?
          OR iwe.notes LIKE ?
          OR ec.code LIKE ? 
          OR ec.description LIKE ?
          OR ec.category LIKE ?
        )
      ORDER BY w.windowNumber ASC
    ''', [
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm
    ]);
    return maps.map((map) => Window.fromMap(map)).toList();
  }

  static Future<Map<int, DoorErrorSummary>>
      getWindowErrorSummariesForInspection(int inspectionId) async {
    final db = await getDb();
    final List<Map<String, dynamic>> rows = await db.rawQuery('''
      SELECT 
        iw.windowId,
        COUNT(iwe.id) AS total_errors,
        SUM(CASE WHEN iwe.id IS NOT NULL AND LOWER(COALESCE(iwe.resolutionStatus, 'open')) NOT IN ('resolved', 'gelöst', 'geloest', 'beholfen', 'erledigt') THEN 1 ELSE 0 END) AS open_errors,
        SUM(CASE WHEN iwe.id IS NOT NULL AND LOWER(COALESCE(iwe.resolutionStatus, 'open')) IN ('resolved', 'gelöst', 'geloest', 'beholfen', 'erledigt') THEN 1 ELSE 0 END) AS resolved_errors,
        SUM(CASE WHEN iwe.id IS NOT NULL AND (
          LOWER(COALESCE(ec.category, '')) LIKE '%hinweis%'
          OR LOWER(COALESCE(ec.category, '')) LIKE '%anmerkung%'
          OR LOWER(COALESCE(ec.description, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(ec.code, iwe.errorCode, '')) LIKE 'hinweis%'
          OR COALESCE(ec.code, iwe.errorCode, '') LIKE '0.%'
          OR LOWER(COALESCE(ec.code, iwe.errorCode, '')) LIKE 'h-%'
          OR LOWER(COALESCE(iwe.notes, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(iwe.severity, '')) = 'hinweis'
        ) THEN 1 ELSE 0 END) AS notice_count,
        SUM(CASE WHEN iwe.id IS NOT NULL AND (
          LOWER(COALESCE(ec.category, '')) LIKE '%hinweis%'
          OR LOWER(COALESCE(ec.category, '')) LIKE '%anmerkung%'
          OR LOWER(COALESCE(ec.description, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(ec.code, iwe.errorCode, '')) LIKE 'hinweis%'
          OR COALESCE(ec.code, iwe.errorCode, '') LIKE '0.%'
          OR LOWER(COALESCE(ec.code, iwe.errorCode, '')) LIKE 'h-%'
          OR LOWER(COALESCE(iwe.notes, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(iwe.severity, '')) = 'hinweis'
        ) AND LOWER(COALESCE(iwe.resolutionStatus, 'open')) NOT IN ('resolved', 'gelöst', 'geloest', 'beholfen', 'erledigt') THEN 1 ELSE 0 END) AS open_notices,
        SUM(CASE WHEN iwe.id IS NOT NULL AND (
          LOWER(COALESCE(ec.category, '')) LIKE '%hinweis%'
          OR LOWER(COALESCE(ec.category, '')) LIKE '%anmerkung%'
          OR LOWER(COALESCE(ec.description, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(ec.code, iwe.errorCode, '')) LIKE 'hinweis%'
          OR COALESCE(ec.code, iwe.errorCode, '') LIKE '0.%'
          OR LOWER(COALESCE(ec.code, iwe.errorCode, '')) LIKE 'h-%'
          OR LOWER(COALESCE(iwe.notes, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(iwe.severity, '')) = 'hinweis'
        ) AND LOWER(COALESCE(iwe.resolutionStatus, 'open')) IN ('resolved', 'gelöst', 'geloest', 'beholfen', 'erledigt') THEN 1 ELSE 0 END) AS resolved_notices,
        SUM(CASE WHEN iwe.id IS NOT NULL AND NOT (
          LOWER(COALESCE(ec.category, '')) LIKE '%hinweis%'
          OR LOWER(COALESCE(ec.category, '')) LIKE '%anmerkung%'
          OR LOWER(COALESCE(ec.description, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(ec.code, iwe.errorCode, '')) LIKE 'hinweis%'
          OR COALESCE(ec.code, iwe.errorCode, '') LIKE '0.%'
          OR LOWER(COALESCE(ec.code, iwe.errorCode, '')) LIKE 'h-%'
          OR LOWER(COALESCE(iwe.notes, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(iwe.severity, '')) = 'hinweis'
        ) THEN 1 ELSE 0 END) AS defect_count,
        SUM(CASE WHEN iwe.id IS NOT NULL AND NOT (
          LOWER(COALESCE(ec.category, '')) LIKE '%hinweis%'
          OR LOWER(COALESCE(ec.category, '')) LIKE '%anmerkung%'
          OR LOWER(COALESCE(ec.description, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(ec.code, iwe.errorCode, '')) LIKE 'hinweis%'
          OR COALESCE(ec.code, iwe.errorCode, '') LIKE '0.%'
          OR LOWER(COALESCE(ec.code, iwe.errorCode, '')) LIKE 'h-%'
          OR LOWER(COALESCE(iwe.notes, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(iwe.severity, '')) = 'hinweis'
        ) AND LOWER(COALESCE(iwe.resolutionStatus, 'open')) NOT IN ('resolved', 'gelöst', 'geloest', 'beholfen', 'erledigt') THEN 1 ELSE 0 END) AS open_defects,
        SUM(CASE WHEN iwe.id IS NOT NULL AND NOT (
          LOWER(COALESCE(ec.category, '')) LIKE '%hinweis%'
          OR LOWER(COALESCE(ec.category, '')) LIKE '%anmerkung%'
          OR LOWER(COALESCE(ec.description, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(ec.code, iwe.errorCode, '')) LIKE 'hinweis%'
          OR COALESCE(ec.code, iwe.errorCode, '') LIKE '0.%'
          OR LOWER(COALESCE(ec.code, iwe.errorCode, '')) LIKE 'h-%'
          OR LOWER(COALESCE(iwe.notes, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(iwe.severity, '')) = 'hinweis'
        ) AND LOWER(COALESCE(iwe.resolutionStatus, 'open')) IN ('resolved', 'gelöst', 'geloest', 'beholfen', 'erledigt') THEN 1 ELSE 0 END) AS resolved_defects
      FROM inspection_windows iw
      LEFT JOIN inspection_window_errors iwe ON iw.id = iwe.inspectionWindowId
      LEFT JOIN error_catalog ec ON (iwe.errorId = ec.errorId OR (iwe.errorCode IS NOT NULL AND iwe.errorCode != '' AND iwe.errorCode = ec.code))
      WHERE iw.inspectionId = ?
      GROUP BY iw.windowId
    ''', [inspectionId]);

    final Map<int, DoorErrorSummary> summaries = {};
    for (final row in rows) {
      final windowId = row['windowId'] as int;
      summaries[windowId] = DoorErrorSummary(
        totalErrors: (row['total_errors'] as num?)?.toInt() ?? 0,
        openErrors: (row['open_errors'] as num?)?.toInt() ?? 0,
        resolvedErrors: (row['resolved_errors'] as num?)?.toInt() ?? 0,
        defectCount: (row['defect_count'] as num?)?.toInt() ?? 0,
        openDefects: (row['open_defects'] as num?)?.toInt() ?? 0,
        resolvedDefects: (row['resolved_defects'] as num?)?.toInt() ?? 0,
        noticeCount: (row['notice_count'] as num?)?.toInt() ?? 0,
        openNotices: (row['open_notices'] as num?)?.toInt() ?? 0,
        resolvedNotices: (row['resolved_notices'] as num?)?.toInt() ?? 0,
      );
    }
    return summaries;
  }

  static Future<Map<int, String>> getWindowInspectionStatuses(
      int inspectionId) async {
    final db = await getDb();
    final rows = await db.query(
      'inspection_windows',
      columns: ['windowId', 'status'],
      where: 'inspectionId = ?',
      whereArgs: [inspectionId],
    );
    final Map<int, String> map = {};
    for (final r in rows) {
      final windowId = r['windowId'] as int?;
      if (windowId != null) {
        map[windowId] = (r['status'] as String? ?? '').trim();
      }
    }
    return map;
  }

  static Future<void> setWindowInspectionStatus({
    required int inspectionId,
    required int windowId,
    required String status,
    String? notes,
  }) =>
      updateInspectionWindowStatus(
        inspectionId: inspectionId,
        windowId: windowId,
        status: status,
        notes: notes,
      );

  static Future<Map<String, dynamic>?> getWindowHistoryData(
      {int? windowId, String? windowAlias}) async {
    final db = await getDb();

    // 1. Fetch Window
    List<Map<String, dynamic>> windowRows = [];
    if (windowId != null) {
      windowRows = await db.query('windows',
          where: 'id = ?', whereArgs: [windowId], limit: 1);
    } else if (windowAlias != null && windowAlias.isNotEmpty) {
      windowRows = await db.query('windows',
          where: 'windowAlias = ?', whereArgs: [windowAlias], limit: 1);
      if (windowRows.isEmpty) {
        windowRows = await db.query('windows',
            where: 'provisionalAlias = ?', whereArgs: [windowAlias], limit: 1);
      }
    }

    if (windowRows.isEmpty) return null;
    final windowMap = windowRows.first;
    final targetWindowId = windowMap['id'] as int;
    final window = Window.fromMap(windowMap);

    // 2. Fetch all inspection_windows entries linked to this window, joined with inspections
    final List<Map<String, dynamic>> inspectionRows = await db.rawQuery('''
      SELECT 
        iw.id AS junctionId,
        iw.status AS junctionStatus,
        iw.notes AS junctionNotes,
        iw.attachments AS junctionAttachments,
        i.inspectionId,
        i.clientName,
        i.objectAddress,
        i.date,
        i.contactPerson,
        i.inspectorName,
        i.jobNumber,
        i.projectNumber,
        i.orderType,
        i.repairDate
      FROM inspection_windows iw
      INNER JOIN inspections i ON iw.inspectionId = i.inspectionId
      WHERE iw.windowId = ?
      ORDER BY i.date DESC, i.inspectionId DESC
    ''', [targetWindowId]);

    // 3. For each inspection, fetch associated defects
    List<Map<String, dynamic>> historyItems = [];
    int totalLifetimeErrors = 0;
    int currentOpenErrors = 0;
    int resolvedErrors = 0;

    for (var row in inspectionRows) {
      final junctionId = row['junctionId'] as int;
      final errors = await db.rawQuery('''
        SELECT 
          iwe.id AS errorInstanceId,
          iwe.errorCode,
          iwe.quantity,
          iwe.severity,
          iwe.notes,
          iwe.resolutionStatus,
          iwe.attachments,
          ec.description AS catalogDescription,
          ec.category AS catalogCategory,
          ec.recommendation AS catalogRecommendation,
          ec.normReference AS catalogNormReference
        FROM inspection_window_errors iwe
        LEFT JOIN error_catalog ec ON (
          iwe.errorId = ec.errorId OR 
          (iwe.errorCode IS NOT NULL AND iwe.errorCode != '' AND iwe.errorCode = ec.code)
        )
        WHERE iwe.inspectionWindowId = ?
      ''', [junctionId]);

      int rowErrorCount = errors.length;
      totalLifetimeErrors += rowErrorCount;

      for (var e in errors) {
        final status =
            (e['resolutionStatus']?.toString() ?? 'open').toLowerCase();
        if (status == 'resolved' ||
            status == 'behoben' ||
            status == 'beholfen' ||
            status == 'gelöst') {
          resolvedErrors++;
        } else {
          currentOpenErrors++;
        }
      }

      historyItems.add({
        'inspection': row,
        'errors': errors,
        'errorCount': rowErrorCount,
      });
    }

    // 4. Compute Health Status
    String healthStatus = 'green';
    if (currentOpenErrors > 0) {
      bool hasHighSeverity = historyItems.any((item) {
        final errors = item['errors'] as List<Map<String, dynamic>>;
        return errors.any((e) {
          final sev = (e['severity']?.toString() ?? 'medium').toLowerCase();
          final status =
              (e['resolutionStatus']?.toString() ?? 'open').toLowerCase();
          final isResolved = (status == 'resolved' ||
              status == 'behoben' ||
              status == 'beholfen' ||
              status == 'gelöst');
          return (sev == 'high' ||
                  sev == 'critical' ||
                  sev == 'hoch' ||
                  sev == 'kritisch') &&
              !isResolved;
        });
      });
      healthStatus = hasHighSeverity ? 'red' : 'yellow';
    } else if (!window.windowFunctionOK || (window.hasRaffstore && window.raffstoreOK == false)) {
      healthStatus = 'yellow';
    }

    return {
      'window': window,
      'historyItems': historyItems,
      'totalInspections': historyItems.length,
      'totalLifetimeErrors': totalLifetimeErrors,
      'currentOpenErrors': currentOpenErrors,
      'resolvedErrors': resolvedErrors,
      'healthStatus': healthStatus,
    };
  }

  static Future<int> insertInspectionWindow(Map<String, dynamic> data) async {
    final db = await getDb();
    final inspectionId = data['inspectionId'];
    final windowId = data['windowId'];

    if (inspectionId != null && windowId != null) {
      final existing = await db.query(
        'inspection_windows',
        columns: ['id'],
        where: 'inspectionId = ? AND windowId = ?',
        whereArgs: [inspectionId, windowId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final existingId = existing.first['id'] as int;
        final updateData = Map<String, dynamic>.from(data);
        updateData['id'] = existingId;
        await db.update(
          'inspection_windows',
          updateData,
          where: 'id = ?',
          whereArgs: [existingId],
        );
        return existingId;
      }
    }

    return await db.insert(
      'inspection_windows',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getInspectionWindowsByInspectionId(
      int inspectionId) async {
    final db = await getDb();
    return await db.query(
      'inspection_windows',
      where: 'inspectionId = ?',
      whereArgs: [inspectionId],
    );
  }

  static Future<void> updateInspectionWindowStatus({
    required int inspectionId,
    required int windowId,
    required String status,
    String? notes,
    String? attachments,
  }) async {
    final db = await getDb();
    final existing = await db.query(
      'inspection_windows',
      columns: ['id'],
      where: 'inspectionId = ? AND windowId = ?',
      whereArgs: [inspectionId, windowId],
      limit: 1,
    );

    final values = <String, dynamic>{
      'status': status,
      if (notes != null) 'notes': notes,
      if (attachments != null) 'attachments': attachments,
    };

    if (existing.isNotEmpty) {
      await db.update(
        'inspection_windows',
        values,
        where: 'inspectionId = ? AND windowId = ?',
        whereArgs: [inspectionId, windowId],
      );
    } else {
      values['inspectionId'] = inspectionId;
      values['windowId'] = windowId;
      await db.insert('inspection_windows', values);
    }
  }

  static Future<int> insertInspectionWindowError(
      InspectionWindowError error) async {
    final db = await getDb();

    if (error.id != null) {
      final existing = await db.query(
        'inspection_window_errors',
        where: 'id = ?',
        whereArgs: [error.id],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        await db.update(
          'inspection_window_errors',
          error.toMap(),
          where: 'id = ?',
          whereArgs: [error.id],
        );
        return error.id!;
      }
    }

    if (error.inspectionWindowId > 0) {
      List<Map<String, dynamic>> existing = [];
      if (error.errorId != null) {
        existing = await db.query(
          'inspection_window_errors',
          columns: ['id'],
          where: 'inspectionWindowId = ? AND errorId = ?',
          whereArgs: [error.inspectionWindowId, error.errorId],
          limit: 1,
        );
      } else if (error.errorCode.isNotEmpty) {
        existing = await db.query(
          'inspection_window_errors',
          columns: ['id'],
          where: 'inspectionWindowId = ? AND errorCode = ?',
          whereArgs: [error.inspectionWindowId, error.errorCode],
          limit: 1,
        );
      }
      if (existing.isNotEmpty) {
        final existingId = existing.first['id'] as int;
        final updateError = error.copyWith(id: existingId);
        await db.update(
          'inspection_window_errors',
          updateError.toMap(),
          where: 'id = ?',
          whereArgs: [existingId],
        );
        return existingId;
      }
    }

    return await db.insert(
      'inspection_window_errors',
      error.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<InspectionWindowError>> getInspectionWindowErrors(
      int inspectionWindowId) async {
    final db = await getDb();
    final rows = await db.query(
      'inspection_window_errors',
      where: 'inspectionWindowId = ?',
      whereArgs: [inspectionWindowId],
    );
    return rows.map((r) => InspectionWindowError.fromMap(r)).toList();
  }

  static Future<void> deleteInspectionWindowError(int id) async {
    final db = await getDb();
    await db
        .delete('inspection_window_errors', where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> updateInspectionWindowError(
      InspectionWindowError error) async {
    final db = await getDb();
    if (error.id == null) return 0;
    return await db.update(
      'inspection_window_errors',
      error.toMap(),
      where: 'id = ?',
      whereArgs: [error.id],
    );
  }

  static Future<List<Map<String, dynamic>>> getErrorsForInspectionWindowIds(
      List<int> ids) async {
    if (ids.isEmpty) return [];
    final db = await getDb();
    final String idString = ids.join(',');
    return await db.rawQuery('''
      SELECT iwe.*, ec.code, ec.description, ec.category
      FROM inspection_window_errors iwe
      LEFT JOIN error_catalog ec ON (iwe.errorId = ec.errorId OR (iwe.errorCode IS NOT NULL AND iwe.errorCode != '' AND iwe.errorCode = ec.code))
      WHERE iwe.inspectionWindowId IN ($idString)
    ''');
  }

  // ==========================================
  // RWA-Systeme (Local Working DB)
  // ==========================================

  static Future<int> insertRwaSystem(RwaSystem rwa) async {
    final db = await getDb();
    final data = rwa.toMap()..remove('id');
    return await db.insert(
      'rwa_systems',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateRwaSystem(RwaSystem rwa) async {
    final db = await getDb();
    if (rwa.id == null) return;
    await db.update(
      'rwa_systems',
      rwa.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [rwa.id],
    );
  }

  static Future<void> deleteRwaSystem(int id) async {
    final db = await getDb();
    await db.delete(
      'inspection_rwa_errors',
      where:
          'inspectionRwaId IN (SELECT id FROM inspection_rwa WHERE rwaSystemId = ?)',
      whereArgs: [id],
    );
    await db.delete(
      'inspection_rwa_settings',
      where:
          'inspectionRwaId IN (SELECT id FROM inspection_rwa WHERE rwaSystemId = ?)',
      whereArgs: [id],
    );
    await db.delete('inspection_rwa', where: 'rwaSystemId = ?', whereArgs: [id]);
    await db.delete('rwa_systems', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteRwaSystems(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await getDb();
    final idList = ids.join(',');
    await db.transaction((txn) async {
      await txn.delete(
        'inspection_rwa_errors',
        where:
            'inspectionRwaId IN (SELECT id FROM inspection_rwa WHERE rwaSystemId IN ($idList))',
      );
      await txn.delete(
        'inspection_rwa_settings',
        where:
            'inspectionRwaId IN (SELECT id FROM inspection_rwa WHERE rwaSystemId IN ($idList))',
      );
      await txn.delete(
        'inspection_rwa',
        where: 'rwaSystemId IN ($idList)',
      );
      await txn.delete(
        'rwa_systems',
        where: 'id IN ($idList)',
      );
    });
  }

  static Future<RwaSystem?> getRwaSystemById(int id) async {
    final db = await getDb();
    final maps = await db.query(
      'rwa_systems',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return RwaSystem.fromMap(maps.first);
  }

  static Future<RwaSystem?> getRwaSystemByAlias(String alias) async {
    final db = await getDb();
    final clean = alias.trim();
    if (clean.isEmpty) return null;
    final maps = await db.query(
      'rwa_systems',
      where: 'systemAlias = ? OR provisionalAlias = ?',
      whereArgs: [clean, clean],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return RwaSystem.fromMap(maps.first);
  }

  static Future<RwaSystem?> findRwaSystemByBarcode(String barcode,
      {String? projectNumber}) async {
    final db = await getDb();
    final clean = barcode.trim();
    if (clean.isEmpty) return null;

    final exact = await db.query(
      'rwa_systems',
      where: 'systemAlias = ? OR provisionalAlias = ?',
      whereArgs: [clean, clean],
      limit: 1,
    );
    if (exact.isNotEmpty) return RwaSystem.fromMap(exact.first);

    if (projectNumber != null && projectNumber.trim().isNotEmpty) {
      final inProj = await db.query(
        'rwa_systems',
        where:
            'projectNumber = ? AND (systemAlias LIKE ? OR provisionalAlias LIKE ?)',
        whereArgs: [projectNumber.trim(), '%$clean%', '%$clean%'],
        limit: 1,
      );
      if (inProj.isNotEmpty) return RwaSystem.fromMap(inProj.first);
    }
    return null;
  }

  static Future<int> updateRwaSystemAlias(int rwaId, String newAlias) async {
    final db = await getDb();
    final cleanAlias = newAlias.trim();

    if (cleanAlias.isNotEmpty) {
      final conflict = await db.query(
        'rwa_systems',
        columns: ['id'],
        where: 'systemAlias = ? AND id != ?',
        whereArgs: [cleanAlias, rwaId],
        limit: 1,
      );
      if (conflict.isNotEmpty) {
        throw Exception(
            'Alias "$cleanAlias" ist bereits an eine andere RWA-Anlage vergeben.');
      }
    }

    return await db.update(
      'rwa_systems',
      {'systemAlias': cleanAlias.isEmpty ? null : cleanAlias},
      where: 'id = ?',
      whereArgs: [rwaId],
    );
  }

  static Future<List<RwaSystem>> getAllRwaSystems() async {
    final db = await getDb();
    final maps = await db.query('rwa_systems', orderBy: 'id ASC');
    return maps.map((m) => RwaSystem.fromMap(m)).toList();
  }

  static Future<List<RwaSystem>> getRwaSystemsByInspectionId(
      int inspectionId) async {
    final db = await getDb();
    final rows = await db.rawQuery('''
      SELECT r.* 
      FROM rwa_systems r
      INNER JOIN inspection_rwa ir ON r.id = ir.rwaSystemId
      WHERE ir.inspectionId = ?
      ORDER BY r.id ASC
    ''', [inspectionId]);
    return rows.map((r) => RwaSystem.fromMap(r)).toList();
  }

  static Future<int> insertInspectionRwa(Map<String, dynamic> data) async {
    final db = await getDb();
    final inspectionId = data['inspectionId'];
    final rwaSystemId = data['rwaSystemId'];

    if (inspectionId != null && rwaSystemId != null) {
      final existing = await db.query(
        'inspection_rwa',
        columns: ['id'],
        where: 'inspectionId = ? AND rwaSystemId = ?',
        whereArgs: [inspectionId, rwaSystemId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final existingId = existing.first['id'] as int;
        await db.update(
          'inspection_rwa',
          data,
          where: 'id = ?',
          whereArgs: [existingId],
        );
        return existingId;
      }
    }

    return await db.insert(
      'inspection_rwa',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getInspectionRwasByInspectionId(
      int inspectionId) async {
    final db = await getDb();
    return await db.query(
      'inspection_rwa',
      where: 'inspectionId = ?',
      whereArgs: [inspectionId],
    );
  }

  static Future<void> updateInspectionRwaStatus({
    required int inspectionId,
    required int rwaSystemId,
    required String status,
    String? notes,
    String? attachments,
  }) async {
    final db = await getDb();
    final existing = await db.query(
      'inspection_rwa',
      columns: ['id'],
      where: 'inspectionId = ? AND rwaSystemId = ?',
      whereArgs: [inspectionId, rwaSystemId],
      limit: 1,
    );

    final values = <String, dynamic>{
      'status': status,
      if (notes != null) 'notes': notes,
      if (attachments != null) 'attachments': attachments,
    };

    if (existing.isNotEmpty) {
      await db.update(
        'inspection_rwa',
        values,
        where: 'inspectionId = ? AND rwaSystemId = ?',
        whereArgs: [inspectionId, rwaSystemId],
      );
    } else {
      values['inspectionId'] = inspectionId;
      values['rwaSystemId'] = rwaSystemId;
      await db.insert('inspection_rwa', values);
    }
  }

  static Future<int> insertRwaInspectionSetting(
      RwaInspectionSetting setting) async {
    final db = await getDb();
    return await db.insert(
      'inspection_rwa_settings',
      setting.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<RwaInspectionSetting>> getRwaInspectionSettings(
      int inspectionRwaId) async {
    final db = await getDb();
    final rows = await db.query(
      'inspection_rwa_settings',
      where: 'inspectionRwaId = ?',
      whereArgs: [inspectionRwaId],
      orderBy: 'id ASC',
    );
    return rows.map((r) => RwaInspectionSetting.fromMap(r)).toList();
  }

  static Future<void> saveRwaInspectionSettings(
      int inspectionRwaId, List<RwaInspectionSetting> settings) async {
    final db = await getDb();
    await db.transaction((txn) async {
      await txn.delete(
        'inspection_rwa_settings',
        where: 'inspectionRwaId = ?',
        whereArgs: [inspectionRwaId],
      );
      for (final s in settings) {
        await txn.insert(
          'inspection_rwa_settings',
          s.copyWith(inspectionRwaId: inspectionRwaId).toMap()..remove('id'),
        );
      }
    });
  }

  static Future<int> insertInspectionRwaError(InspectionRwaError error) async {
    final db = await getDb();
    if (error.id != null) {
      final existing = await db.query(
        'inspection_rwa_errors',
        where: 'id = ?',
        whereArgs: [error.id],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        await db.update(
          'inspection_rwa_errors',
          error.toMap(),
          where: 'id = ?',
          whereArgs: [error.id],
        );
        return error.id!;
      }
    }

    int? resolvedErrorId = error.errorId;
    if (resolvedErrorId == null && error.errorCode.isNotEmpty) {
      final matches = await db.query(
        'error_catalog',
        columns: ['errorId'],
        where: 'code = ?',
        whereArgs: [error.errorCode],
        limit: 1,
      );
      if (matches.isNotEmpty) {
        resolvedErrorId = matches.first['errorId'] as int;
      }
    }

    final data = error.toMap()..remove('id');
    data['errorId'] = resolvedErrorId;

    return await db.insert(
      'inspection_rwa_errors',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<InspectionRwaError>> getInspectionRwaErrors(
      int inspectionRwaId) async {
    final db = await getDb();
    final rows = await db.query(
      'inspection_rwa_errors',
      where: 'inspectionRwaId = ?',
      whereArgs: [inspectionRwaId],
    );
    return rows.map((r) => InspectionRwaError.fromMap(r)).toList();
  }

  static Future<void> deleteInspectionRwaError(int id) async {
    final db = await getDb();
    await db.delete('inspection_rwa_errors', where: 'id = ?', whereArgs: [id]);
  }

  // ─────────────────────────────────────────────────────────────
  // INSPECTIONS
  // ─────────────────────────────────────────────────────────────

  static String _normalizeDate(dynamic val) {
    if (val == null) return '';
    final str = val.toString().trim();
    if (str.isEmpty) return '';
    if (str.contains('T')) {
      return str.split('T')[0];
    }
    if (str.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(str)) {
      return str.substring(0, 10);
    }
    return str;
  }

  static Future<int> insertInspection(Map<String, dynamic> inspection) async {
    final db = await getDb();
    final data = Map<String, dynamic>.from(inspection);
    data.remove('doorCount');
    if (data.containsKey('date') && data['date'] != null) {
      data['date'] = _normalizeDate(data['date']);
    }
    if (data.containsKey('repairDate') && data['repairDate'] != null) {
      data['repairDate'] = _normalizeDate(data['repairDate']);
    }
    return await db.insert('inspections', data,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>?> getInspectionById(
      int inspectionId) async {
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

  static Future<void> updateInspection(
      Map<String, dynamic> inspectionData) async {
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

    final String oldClient = existingRows.isNotEmpty
        ? (existingRows.first['clientName'] as String? ?? '')
        : '';
    final String oldAddress = existingRows.isNotEmpty
        ? (existingRows.first['objectAddress'] as String? ?? '')
        : '';

    final data = Map<String, dynamic>.from(inspectionData);
    if (data.containsKey('date') && data['date'] != null) {
      data['date'] = _normalizeDate(data['date']);
    }
    if (data.containsKey('repairDate') && data['repairDate'] != null) {
      data['repairDate'] = _normalizeDate(data['repairDate']);
    }

    await db.update(
      'inspections',
      data,
      where: 'inspectionId = ?',
      whereArgs: [id],
    );

    final String newClient =
        inspectionData['clientName']?.toString().trim() ?? oldClient;
    final String newAddress =
        inspectionData['objectAddress']?.toString().trim() ?? oldAddress;

    if (newClient != oldClient || newAddress != oldAddress) {
      await updateDoorAliasesForInspection(
        inspectionId: (id is int) ? id : int.parse(id.toString()),
        newClientName: newClient,
        newObjectAddress: newAddress,
      );
    }
  }

  /// Updates project number and/or building address across all inspections in local DB.
  static Future<int> updateProjectBuildingData({
    required String currentProjectNumber,
    required String newProjectNumber,
    required String newObjectAddress,
  }) async {
    final db = await getDb();
    final cleanCurrentProj = currentProjectNumber.trim();
    final cleanNewProj = newProjectNumber.trim();
    final cleanNewAddress = newObjectAddress.trim();

    if (cleanCurrentProj.isEmpty && cleanNewProj.isEmpty) {
      return 0;
    }

    final String searchProj =
        cleanCurrentProj.isNotEmpty ? cleanCurrentProj : cleanNewProj;
    final targetInspections = await db.query(
      'inspections',
      columns: ['inspectionId', 'clientName'],
      where: 'projectNumber = ?',
      whereArgs: [searchProj],
    );

    int updatedCount = 0;
    for (final insp in targetInspections) {
      final inspId = insp['inspectionId'] as int;
      final clientName = (insp['clientName'] as String? ?? '').trim();
      await db.update(
        'inspections',
        {
          'projectNumber': cleanNewProj,
          'objectAddress': cleanNewAddress,
        },
        where: 'inspectionId = ?',
        whereArgs: [inspId],
      );
      await updateDoorAliasesForInspection(
        inspectionId: inspId,
        newClientName: clientName,
        newObjectAddress: cleanNewAddress,
      );
      updatedCount++;
    }
    return updatedCount;
  }

  static Future<void> updateDoorAliasesForInspection({
    required int inspectionId,
    required String newClientName,
    required String newObjectAddress,
  }) async {
    final db = await getDb();

    final inspRows = await db.query('inspections',
        columns: ['projectNumber'],
        where: 'inspectionId = ?',
        whereArgs: [inspectionId]);
    final projectNumber = inspRows.isNotEmpty
        ? (inspRows.first['projectNumber'] as String? ?? '')
        : '';

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
        projectNumber: projectNumber,
        pos: doorRow['pos'] ?? 0,
        floor: floor,
        doorNumber: doorNumber,
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
        await mergeDuplicateDoors(
            targetDoorId: targetExistingDoorId, duplicateDoorId: doorId);
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
  static Future<List<Map<String, dynamic>>> getAllInspections(
      {String query = '', String clientFilter = ''}) async {
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
      whereArgs
          .addAll([searchTerm, searchTerm, searchTerm, searchTerm, searchTerm]);
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
  static Future<List<Door>> getDoorsByInspectionId(int inspectionId,
      {String query = ''}) async {
    final db = await getDb();
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT d.*, COALESCE(id.notes, '') AS notes 
        FROM doors d
        INNER JOIN inspection_doors id ON d.id = id.doorId
        WHERE id.inspectionId = ?
        ORDER BY d.pos ASC, d.doorNumber ASC
      ''', [inspectionId]);
      return maps.map((map) => Door.fromMap(map)).toList();
    }

    final searchTerm = '%$cleanQuery%';
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT DISTINCT d.*, COALESCE(id.notes, '') AS notes 
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
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm,
      searchTerm
    ]);

    return maps.map((map) => Door.fromMap(map)).toList();
  }

  /// Returns a map of doorId -> DoorErrorSummary for a given inspection ID.
  static Future<Map<int, DoorErrorSummary>> getDoorErrorSummariesForInspection(
      int inspectionId) async {
    final db = await getDb();
    final List<Map<String, dynamic>> rows = await db.rawQuery('''
      SELECT 
        id.doorId,
        COUNT(ide.id) AS total_errors,
        SUM(CASE WHEN ide.id IS NOT NULL AND LOWER(COALESCE(ide.resolutionStatus, 'open')) NOT IN ('resolved', 'gelöst', 'geloest', 'beholfen', 'erledigt') THEN 1 ELSE 0 END) AS open_errors,
        SUM(CASE WHEN ide.id IS NOT NULL AND LOWER(COALESCE(ide.resolutionStatus, 'open')) IN ('resolved', 'gelöst', 'geloest', 'beholfen', 'erledigt') THEN 1 ELSE 0 END) AS resolved_errors,
        SUM(CASE WHEN ide.id IS NOT NULL AND (
          LOWER(COALESCE(ec.category, '')) LIKE '%hinweis%'
          OR LOWER(COALESCE(ec.category, '')) LIKE '%anmerkung%'
          OR LOWER(COALESCE(ec.description, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(ec.code, ide.errorCode, '')) LIKE 'hinweis%'
          OR COALESCE(ec.code, ide.errorCode, '') LIKE '0.%'
          OR LOWER(COALESCE(ec.code, ide.errorCode, '')) LIKE 'h-%'
        ) THEN 1 ELSE 0 END) AS notice_count,
        SUM(CASE WHEN ide.id IS NOT NULL AND (
          LOWER(COALESCE(ec.category, '')) LIKE '%hinweis%'
          OR LOWER(COALESCE(ec.category, '')) LIKE '%anmerkung%'
          OR LOWER(COALESCE(ec.description, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(ec.code, ide.errorCode, '')) LIKE 'hinweis%'
          OR COALESCE(ec.code, ide.errorCode, '') LIKE '0.%'
          OR LOWER(COALESCE(ec.code, ide.errorCode, '')) LIKE 'h-%'
        ) AND LOWER(COALESCE(ide.resolutionStatus, 'open')) NOT IN ('resolved', 'gelöst', 'geloest', 'beholfen', 'erledigt') THEN 1 ELSE 0 END) AS open_notices,
        SUM(CASE WHEN ide.id IS NOT NULL AND (
          LOWER(COALESCE(ec.category, '')) LIKE '%hinweis%'
          OR LOWER(COALESCE(ec.category, '')) LIKE '%anmerkung%'
          OR LOWER(COALESCE(ec.description, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(ec.code, ide.errorCode, '')) LIKE 'hinweis%'
          OR COALESCE(ec.code, ide.errorCode, '') LIKE '0.%'
          OR LOWER(COALESCE(ec.code, ide.errorCode, '')) LIKE 'h-%'
        ) AND LOWER(COALESCE(ide.resolutionStatus, 'open')) IN ('resolved', 'gelöst', 'geloest', 'beholfen', 'erledigt') THEN 1 ELSE 0 END) AS resolved_notices,
        SUM(CASE WHEN ide.id IS NOT NULL AND NOT (
          LOWER(COALESCE(ec.category, '')) LIKE '%hinweis%'
          OR LOWER(COALESCE(ec.category, '')) LIKE '%anmerkung%'
          OR LOWER(COALESCE(ec.description, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(ec.code, ide.errorCode, '')) LIKE 'hinweis%'
          OR COALESCE(ec.code, ide.errorCode, '') LIKE '0.%'
          OR LOWER(COALESCE(ec.code, ide.errorCode, '')) LIKE 'h-%'
        ) THEN 1 ELSE 0 END) AS defect_count,
        SUM(CASE WHEN ide.id IS NOT NULL AND NOT (
          LOWER(COALESCE(ec.category, '')) LIKE '%hinweis%'
          OR LOWER(COALESCE(ec.category, '')) LIKE '%anmerkung%'
          OR LOWER(COALESCE(ec.description, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(ec.code, ide.errorCode, '')) LIKE 'hinweis%'
          OR COALESCE(ec.code, ide.errorCode, '') LIKE '0.%'
          OR LOWER(COALESCE(ec.code, ide.errorCode, '')) LIKE 'h-%'
        ) AND LOWER(COALESCE(ide.resolutionStatus, 'open')) NOT IN ('resolved', 'gelöst', 'geloest', 'beholfen', 'erledigt') THEN 1 ELSE 0 END) AS open_defects,
        SUM(CASE WHEN ide.id IS NOT NULL AND NOT (
          LOWER(COALESCE(ec.category, '')) LIKE '%hinweis%'
          OR LOWER(COALESCE(ec.category, '')) LIKE '%anmerkung%'
          OR LOWER(COALESCE(ec.description, '')) LIKE 'hinweis%'
          OR LOWER(COALESCE(ec.code, ide.errorCode, '')) LIKE 'hinweis%'
          OR COALESCE(ec.code, ide.errorCode, '') LIKE '0.%'
          OR LOWER(COALESCE(ec.code, ide.errorCode, '')) LIKE 'h-%'
        ) AND LOWER(COALESCE(ide.resolutionStatus, 'open')) IN ('resolved', 'gelöst', 'geloest', 'beholfen', 'erledigt') THEN 1 ELSE 0 END) AS resolved_defects
      FROM inspection_doors id
      LEFT JOIN inspection_door_errors ide ON id.id = ide.inspectionDoorId
      LEFT JOIN error_catalog ec ON (ide.errorId IS NOT NULL AND ide.errorId = ec.errorId) OR (ide.errorId IS NULL AND ide.errorCode != '' AND ide.errorCode = ec.code)
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
        final defects = (row['defect_count'] as num?)?.toInt() ?? 0;
        final openDefects = (row['open_defects'] as num?)?.toInt() ?? 0;
        final resolvedDefects = (row['resolved_defects'] as num?)?.toInt() ?? 0;
        final notices = (row['notice_count'] as num?)?.toInt() ?? 0;
        final openNotices = (row['open_notices'] as num?)?.toInt() ?? 0;
        final resolvedNotices = (row['resolved_notices'] as num?)?.toInt() ?? 0;
        map[doorId] = DoorErrorSummary(
          totalErrors: total,
          openErrors: open,
          resolvedErrors: resolved,
          defectCount: defects,
          openDefects: openDefects,
          resolvedDefects: resolvedDefects,
          noticeCount: notices,
          openNotices: openNotices,
          resolvedNotices: resolvedNotices,
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

  static Future<int> insertInspectionDoor(
      Map<String, dynamic> inspectionDoor) async {
    final db = await getDb();
    return await db.insert('inspection_doors', inspectionDoor,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getInspectionDoorsByInspectionId(
      int inspectionId) async {
    final db = await getDb();
    return await db.query(
      'inspection_doors',
      where: 'inspectionId = ?',
      whereArgs: [inspectionId],
    );
  }

  /// Updates or sets the status of a door for a given inspection (e.g. 'Inspected', 'Pending').
  static Future<void> updateInspectionDoorStatus({
    required int inspectionId,
    required int doorId,
    required String status,
    String? notes,
    String? attachments,
  }) async {
    final db = await getDb();
    final existing = await db.query(
      'inspection_doors',
      columns: ['id'],
      where: 'inspectionId = ? AND doorId = ?',
      whereArgs: [inspectionId, doorId],
      limit: 1,
    );

    final Map<String, dynamic> data = {'status': status};
    if (notes != null) data['notes'] = notes;
    if (attachments != null) data['attachments'] = attachments;

    if (existing.isNotEmpty) {
      await db.update(
        'inspection_doors',
        data,
        where: 'inspectionId = ? AND doorId = ?',
        whereArgs: [inspectionId, doorId],
      );
    } else {
      data['inspectionId'] = inspectionId;
      data['doorId'] = doorId;
      await db.insert('inspection_doors', data);
    }
  }

  /// Updates only the attachments for a door in a given inspection.
  static Future<void> updateInspectionDoorAttachments({
    required int inspectionId,
    required int doorId,
    required String? attachments,
  }) async {
    final db = await getDb();
    final existing = await db.query(
      'inspection_doors',
      columns: ['id'],
      where: 'inspectionId = ? AND doorId = ?',
      whereArgs: [inspectionId, doorId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        'inspection_doors',
        {'attachments': attachments},
        where: 'inspectionId = ? AND doorId = ?',
        whereArgs: [inspectionId, doorId],
      );
    }
  }

  /// Sets or updates the inspection status of a door.
  static Future<void> setDoorInspectionStatus({
    required int inspectionId,
    required int doorId,
    required String status,
    String? notes,
  }) =>
      updateInspectionDoorStatus(
        inspectionId: inspectionId,
        doorId: doorId,
        status: status,
        notes: notes,
      );

  /// Returns a map of doorId -> status for all doors in an inspection.
  static Future<Map<int, String>> getDoorInspectionStatuses(
      int inspectionId) async {
    final db = await getDb();
    final rows = await db.query(
      'inspection_doors',
      columns: ['doorId', 'status'],
      where: 'inspectionId = ?',
      whereArgs: [inspectionId],
    );
    final Map<int, String> map = {};
    for (final r in rows) {
      final doorId = r['doorId'] as int?;
      if (doorId != null) {
        map[doorId] = (r['status'] as String? ?? '').trim();
      }
    }
    return map;
  }

  // ─────────────────────────────────────────────────────────────
  // INSPECTION DOOR ERRORS (LOCAL)
  // ─────────────────────────────────────────────────────────────

  static Future<int> insertInspectionDoorError(
      InspectionDoorError error) async {
    final db = await getDb();
    return await db.insert(
      'inspection_door_errors',
      error.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<int> updateInspectionDoorError(
      InspectionDoorError error) async {
    final db = await getDb();
    if (error.id == null) return 0;
    return await db.update(
      'inspection_door_errors',
      error.toMap(),
      where: 'id = ?',
      whereArgs: [error.id],
    );
  }

  static Future<Set<String>> _getInspectionDoorErrorsColumns(
      DatabaseExecutor db) async {
    try {
      final List<Map<String, dynamic>> tableInfo =
          await db.rawQuery('PRAGMA table_info(inspection_door_errors)');
      return tableInfo.map((row) => row['name'] as String).toSet();
    } catch (e) {
      print('Error getting table info for inspection_door_errors: $e');
      return {};
    }
  }

  static Future<String> _fetchLargeAttachments(
      DatabaseExecutor db, int errorId) async {
    final StringBuffer sb = StringBuffer();
    int offset = 1; // SQLite SUBSTR is 1-indexed
    const int chunkSize =
        1000 * 1024; // 1MB chunks (approx 1,000,000 characters)

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
        print(
            'Error reading chunk for error ID $errorId at offset $offset: $e');
        break;
      }
    }
    return sb.toString();
  }

  // This method was missing its body in the previous diff, restoring it.
  static Future<List<InspectionDoorError>> getErrorsForInspectionDoor(
      int inspectionDoorId) async {
    final db = await getDb();

    final Set<String> existingColumns =
        await _getInspectionDoorErrorsColumns(db);
    final List<String> selectCols = [];
    final List<String> possibleCols = [
      'id',
      'inspectionDoorId',
      'errorId',
      'errorCode',
      'quantity',
      'severity',
      'notes',
      'resolutionStatus'
    ];
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

  static Future<List<Map<String, dynamic>>> getDetailedErrorsForInspectionDoor(
      int inspectionDoorId) async {
    final db = await getDb();

    final Set<String> existingColumns =
        await _getInspectionDoorErrorsColumns(db);
    final List<String> selectCols = [];
    final List<String> possibleCols = [
      'id',
      'inspectionDoorId',
      'errorId',
      'errorCode',
      'quantity',
      'severity',
      'notes',
      'resolutionStatus'
    ];
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

  static Future<List<Map<String, String>>> getAllLocalProjects() async {
    final db = await getDb();
    final rows = await db.rawQuery('''
      SELECT DISTINCT 
        COALESCE(projectNumber, '') as projectNumber,
        COALESCE(objectAddress, '') as objectAddress,
        COALESCE(clientName, '') as clientName
      FROM inspections
      WHERE (projectNumber IS NOT NULL AND TRIM(projectNumber) != '')
         OR (objectAddress IS NOT NULL AND TRIM(objectAddress) != '')
      ORDER BY projectNumber ASC, objectAddress ASC
    ''');
    return rows
        .map((r) => {
              'projectNumber': (r['projectNumber'] as String? ?? '').trim(),
              'objectAddress': (r['objectAddress'] as String? ?? '').trim(),
              'clientName': (r['clientName'] as String? ?? '').trim(),
            })
        .toList();
  }

  /// Fetches all errors for a set of inspection door IDs from Local DB
  static Future<List<Map<String, dynamic>>> getErrorsForInspectionDoorIds(
      List<int> ids) async {
    if (ids.isEmpty) return [];
    final db = await getDb();
    final String idString = ids.join(',');

    final Set<String> existingColumns =
        await _getInspectionDoorErrorsColumns(db);
    final List<String> selectCols = [];
    final List<String> possibleCols = [
      'id',
      'inspectionDoorId',
      'errorId',
      'errorCode',
      'quantity',
      'severity',
      'notes',
      'resolutionStatus'
    ];
    for (final col in possibleCols) {
      if (existingColumns.contains(col)) {
        selectCols.add('ide.$col');
      }
    }
    final String selectString = selectCols.join(', ');

    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT $selectString,
             COALESCE(ec.code, ide.errorCode, 'UNKNOWN') AS code,
             COALESCE(ec.description, ide.notes, 'Keine Beschreibung') AS description,
             COALESCE(ec.category, '') AS category
      FROM inspection_door_errors ide
      LEFT JOIN error_catalog ec ON ide.errorId = ec.errorId
      WHERE ide.inspectionDoorId IN ($idString)
    ''');

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
          attachments = await _fetchLargeAttachments(db, errorId);
        }
      }
      final Map<String, dynamic> fullRow = Map<String, dynamic>.from(row);
      fullRow['attachments'] = attachments;
      finalResults.add(fullRow);
    }
    return finalResults;
  }

  /// Creates a new Auftrag ("Wartung" or "Reparatur") in Local DB (technician device).
  /// If a previous event exists and cloneDoors is true:
  /// - Copies all doors and technical properties.
  /// - Inherits open defects with resolutionStatus 'Open'.
  /// - Solved defects ("gelöst", "Resolved", etc.) are omitted and resolved notes cleared.
  /// If no previous event exists, creates a blank event (0 doors, 0 errors).
  static Future<int> createAuftragFromLatestInspection({
    required String projectNumber,
    required String objectAddress,
    required String clientName,
    required String jobNumber,
    required DateTime date,
    String orderType = 'Wartung', // 'Wartung' or 'Reparatur'
    String assetType = 'door', // 'door' or 'window'
    DateTime? repairDate,
    String contactPerson = '',
    String inspectorName = '',
    bool cloneDoors = true,
    int? sourceInspectionId,
  }) async {
    final db = await getDb();
    final cleanProj = projectNumber.trim();
    final cleanAddr = objectAddress.trim();
    final cleanClient = clientName.trim();
    final cleanJob = jobNumber.trim();
    final cleanAssetType = assetType.trim().toLowerCase();

    if (cleanJob.isEmpty) {
      throw ArgumentError('Bitte eine Auftragsnummer eingeben.');
    }

    // 1. Validate Job Number Uniqueness in Local DB
    final existingJobs = await db.query(
      'inspections',
      where: 'jobNumber = ?',
      whereArgs: [cleanJob],
      limit: 1,
    );
    if (existingJobs.isNotEmpty) {
      throw ArgumentError(
          'Ein Auftrag mit der Auftragsnummer "$cleanJob" existiert bereits. Bitte eine neue, eindeutige Nummer vergeben.');
    }

    // 2. Locate base previous inspection/event
    Map<String, dynamic>? baseInspection;
    if (sourceInspectionId != null) {
      final found = await db.query(
        'inspections',
        where: 'inspectionId = ?',
        whereArgs: [sourceInspectionId],
        limit: 1,
      );
      if (found.isNotEmpty) baseInspection = found.first;
    }
    if (baseInspection == null && cleanProj.isNotEmpty) {
      final found = await db.query(
        'inspections',
        where: "projectNumber = ? AND LOWER(COALESCE(assetType, 'door')) = ?",
        whereArgs: [cleanProj, cleanAssetType],
        orderBy: "COALESCE(repairDate, date) DESC, inspectionId DESC",
        limit: 1,
      );
      if (found.isNotEmpty) baseInspection = found.first;
    }
    if (baseInspection == null && cleanAddr.isNotEmpty) {
      final found = await db.query(
        'inspections',
        where: "objectAddress = ? AND LOWER(COALESCE(assetType, 'door')) = ?",
        whereArgs: [cleanAddr, cleanAssetType],
        orderBy: "COALESCE(repairDate, date) DESC, inspectionId DESC",
        limit: 1,
      );
      if (found.isNotEmpty) baseInspection = found.first;
    }
    if (baseInspection == null && cloneDoors) {
      final allLocal = await db.query(
        'inspections',
        where: "LOWER(COALESCE(assetType, 'door')) = ?",
        whereArgs: [cleanAssetType],
        orderBy: "COALESCE(repairDate, date) DESC, inspectionId DESC",
        limit: 1,
      );
      if (allLocal.isNotEmpty) {
        baseInspection = allLocal.first;
      }
    }

    // 3. Validate Date Sequencing (subsequent event cannot be earlier than previous event)
    final DateTime newEffectiveDate =
        (orderType == 'Reparatur' && repairDate != null) ? repairDate : date;
    if (baseInspection != null) {
      final String? prevDateStr =
          baseInspection['repairDate']?.toString().trim().isNotEmpty == true
              ? baseInspection['repairDate']?.toString()
              : baseInspection['date']?.toString();
      if (prevDateStr != null && prevDateStr.isNotEmpty) {
        try {
          final prevDate = DateTime.parse(prevDateStr);
          final newDatePure = DateTime(newEffectiveDate.year,
              newEffectiveDate.month, newEffectiveDate.day);
          final prevDatePure =
              DateTime(prevDate.year, prevDate.month, prevDate.day);
          if (newDatePure.isBefore(prevDatePure)) {
            final fNew = DateFormat('dd.MM.yyyy').format(newEffectiveDate);
            final fPrev = DateFormat('dd.MM.yyyy').format(prevDate);
            throw ArgumentError(
                'Das Datum des Folge-Auftrags ($fNew) darf nicht vor dem Datum des vorherigen Auftrags ($fPrev) liegen.');
          }
        } catch (e) {
          if (e is ArgumentError) rethrow;
        }
      }
    }

    final resolvedProj = cleanProj.isNotEmpty
        ? cleanProj
        : (baseInspection != null
            ? (baseInspection['projectNumber']?.toString() ?? '')
            : '');
    final resolvedAddr = cleanAddr.isNotEmpty
        ? cleanAddr
        : (baseInspection != null
            ? (baseInspection['objectAddress']?.toString() ?? '')
            : '');
    final resolvedClient = cleanClient.isNotEmpty
        ? cleanClient
        : (baseInspection != null
            ? (baseInspection['clientName']?.toString() ?? '')
            : '');

    // 4. Create the new inspection record
    final inspectionData = {
      'projectNumber': resolvedProj,
      'objectAddress': resolvedAddr,
      'clientName': resolvedClient,
      'jobNumber': cleanJob,
      'date': _normalizeDate(date),
      'contactPerson': contactPerson.trim().isNotEmpty
          ? contactPerson.trim()
          : (baseInspection != null
              ? (baseInspection['contactPerson']?.toString() ?? '')
              : ''),
      'inspectorName': inspectorName.trim().isNotEmpty
          ? inspectorName.trim()
          : (baseInspection != null
              ? (baseInspection['inspectorName']?.toString() ?? '')
              : ''),
      'orderType': orderType,
      'assetType': cleanAssetType,
      'repairDate': orderType == 'Reparatur' && repairDate != null
          ? _normalizeDate(repairDate)
          : null,
      'isLocked': 0,
    };

    final newInspectionId = await insertInspection(inspectionData);

    // 5. Clone doors / windows and propagate open errors
    if (cloneDoors && baseInspection != null) {
      final prevInspId = baseInspection['inspectionId'] as int;
      final bool isWindow = cleanAssetType == 'window';

      if (isWindow) {
        final prevJunctions =
            await getInspectionWindowsByInspectionId(prevInspId);

        bool isResolved(dynamic e) {
          final res = (e is InspectionWindowError
                  ? e.resolutionStatus
                  : e['resolutionStatus']?.toString() ?? 'open')
              .trim()
              .toLowerCase();
          return res == 'resolved' ||
              res == 'gelöst' ||
              res == 'geloest' ||
              res == 'beholfen' ||
              res == 'erledigt';
        }

        for (final j in prevJunctions) {
          final windowId = j['windowId'] as int;
          final prevJunctionId = j['id'] as int;
          final winErrors = await getInspectionWindowErrors(prevJunctionId);
          final openErrors = winErrors.where((e) => !isResolved(e)).toList();

          String winNote = '';
          if (openErrors.isNotEmpty) {
            winNote = j['notes']?.toString() ?? '';
          }

          final newJunctionId = await insertInspectionWindow({
            'inspectionId': newInspectionId,
            'windowId': windowId,
            'status': 'Pending',
            'notes': winNote,
            'attachments': null,
          });

          for (final err in openErrors) {
            final errorObj = InspectionWindowError(
              id: null,
              inspectionWindowId: newJunctionId,
              errorId: err.errorId,
              errorCode: err.errorCode,
              quantity: err.quantity,
              severity: err.severity,
              notes: err.notes,
              resolutionStatus: 'Open',
              attachments: err.attachments,
            );
            await insertInspectionWindowError(errorObj);
          }
        }
      } else {
        final prevJunctions =
            await getInspectionDoorsByInspectionId(prevInspId);
        final prevJunctionIds =
            prevJunctions.map((j) => j['id'] as int).toList();
        final prevErrors =
            await getErrorsForInspectionDoorIds(prevJunctionIds);

        bool isResolved(Map<String, dynamic> e) {
          final res = (e['resolutionStatus']?.toString() ?? 'open')
              .trim()
              .toLowerCase();
          return res == 'resolved' ||
              res == 'gelöst' ||
              res == 'geloest' ||
              res == 'beholfen' ||
              res == 'erledigt';
        }

        for (final j in prevJunctions) {
          final doorId = j['doorId'] as int;
          final prevJunctionId = j['id'] as int;
          final doorErrors = prevErrors
              .where((e) => e['inspectionDoorId'] == prevJunctionId)
              .toList();

          final openErrors = doorErrors.where((e) => !isResolved(e)).toList();

          String doorNote = '';
          if (openErrors.isNotEmpty) {
            doorNote = j['notes']?.toString() ?? '';
          }

          final newJunctionId = await insertInspectionDoor({
            'inspectionId': newInspectionId,
            'doorId': doorId,
            'status': 'Pending',
            'notes': doorNote,
            'attachments': null,
          });

          for (final err in openErrors) {
            final errorObj = InspectionDoorError(
              id: null,
              inspectionDoorId: newJunctionId,
              errorId: err['errorId'] as int?,
              errorCode: err['errorCode']?.toString() ?? '',
              quantity: (err['quantity'] as num?)?.toInt() ?? 1,
              severity: err['severity']?.toString() ?? 'medium',
              notes: err['notes']?.toString() ?? '',
              resolutionStatus: 'Open',
              attachments: err['attachments']?.toString() ?? '',
            );
            await insertInspectionDoorError(errorObj);
          }
        }
      }
    }

    return newInspectionId;
  }

  static Future<void> deleteInspectionDoorError(int id) async {
    final db = await getDb();
    await db.delete('inspection_door_errors', where: 'id = ?', whereArgs: [id]);
  }

  static Future<Map<String, dynamic>?> getInspectionDoor(
      int inspectionId, int doorId) async {
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
      final String provisionalCode =
          'REQ-${DateTime.now().millisecondsSinceEpoch}';
      final provisionalId = await txn.insert('error_catalog', {
        'code': provisionalCode,
        'description': description,
        'category': category,
        'status': 'Pending',
        'requestedBy': 'Inspector', // Ideally pass the actual user name
        'requestDate': DateTime.now().toIso8601String(),
        'sourceInspectionDoorId': inspectionDoorId,
      });
      print(
          'LOCAL DB: Proposed new error created in catalog. ID: $provisionalId, Status: Pending');

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
      final masterCatalog =
          await DatabaseService.getAllErrorCatalog(status: 'Approved');

      // Clear local window catalog entries so any deleted/reset window entries do not linger
      final db = await getDb();
      try {
        await db.delete(
          'error_catalog',
          where: "LOWER(COALESCE(assetType, 'door')) = 'window'",
        );
      } catch (_) {}

      // Delegate the insertion to the standard catalog update routine
      await insertErrorCatalogItems(masterCatalog);
      print(
          'Catalog refresh complete. ${masterCatalog.length} items synchronized.');
    } catch (e) {
      print('Error refreshing catalog: $e');
      rethrow;
    }
  }

  /// Resets window error catalog entries in local database.
  static Future<void> resetWindowCatalog() async {
    final db = await getDb();
    try {
      await db.delete(
        'error_catalog',
        where: "LOWER(COALESCE(assetType, 'door')) = 'window'",
      );
    } catch (e) {
      print('[LocalDatabaseService] Error deleting local window entries: $e');
    }
  }

  /// Fetches all error catalog entries from the local database.
  static Future<List<ErrorCatalog>> getAllErrorCatalog(
      {String? status, String? assetType}) async {
    final db = await getDb();
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (status != null && status.isNotEmpty) {
      whereClauses.add('status = ?');
      whereArgs.add(status);
    }
    if (assetType != null &&
        assetType.isNotEmpty &&
        assetType.toLowerCase() != 'all') {
      whereClauses.add("LOWER(COALESCE(assetType, 'door')) = ?");
      whereArgs.add(assetType.toLowerCase());
    }

    final maps = await db.query(
      'error_catalog',
      where: whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'category, code',
    );
    return maps.map((m) => ErrorCatalog.fromMap(m)).toList();
  }

  static Future<List<ErrorCatalog>> searchErrorCatalog(String query,
      {int? limit, String? assetType}) async {
    final db = await getDb();
    if (query.trim().isEmpty) {
      return getAllErrorCatalog(assetType: assetType);
    }

    String where =
        '(LOWER(code) LIKE LOWER(?) OR LOWER(description) LIKE LOWER(?))';
    List<dynamic> args = ['%$query%', '%$query%'];

    if (assetType != null &&
        assetType.isNotEmpty &&
        assetType.toLowerCase() != 'all') {
      where += " AND LOWER(COALESCE(assetType, 'door')) = ?";
      args.add(assetType.toLowerCase());
    }

    final maps = await db.query(
      'error_catalog',
      where: where,
      whereArgs: args,
      orderBy: 'category, code',
      limit: limit,
    );
    return maps.map((m) => ErrorCatalog.fromMap(m)).toList();
  }

  static Future<List<String>> getErrorCatalogCategories(
      {String? assetType}) async {
    final db = await getDb();
    String query = 'SELECT DISTINCT category FROM error_catalog';
    List<dynamic> args = [];
    if (assetType != null &&
        assetType.isNotEmpty &&
        assetType.toLowerCase() != 'all') {
      query += " WHERE LOWER(COALESCE(assetType, 'door')) = ?";
      args.add(assetType.toLowerCase());
    }
    query += ' ORDER BY category ASC';
    final maps = await db.rawQuery(query, args);
    return maps.map((m) => m['category'] as String).toList();
  }

  static Future<List<ErrorCatalog>> getErrorCatalogByCategory(
      String category) async {
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
  static Future<void> _batchInsertCatalog(DatabaseExecutor db,
      List<ErrorCatalog> items, ConflictAlgorithm algorithm) async {
    final batch = db.batch();
    for (final item in items) {
      final data = item.toMap();
      batch.insert('error_catalog', data, conflictAlgorithm: algorithm);
    }
    await batch.commit(noResult: true);
  }

  /// Inserts or replaces a single error catalog entry into local DB.
  static Future<void> insertErrorCatalog(ErrorCatalog item) async {
    final db = await getDb();
    await db.insert('error_catalog', item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
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

  /// Returns the path to the current working database file.
  static Future<String> getWorkingDbPath() async => _getWorkingDbPath();

  /// Checks whether the inspector app currently has any active inspections or doors to save.
  static Future<bool> hasInspectionsToSave() async {
    try {
      final sourcePath = await _getWorkingDbPath();
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists() || (await sourceFile.length()) == 0) {
        return false;
      }
      final db = await getDb();
      final inspResult =
          await db.rawQuery('SELECT count(*) as c FROM inspections');
      final inspCount = (inspResult.first['c'] as int?) ?? 0;
      final doorResult = await db.rawQuery('SELECT count(*) as c FROM doors');
      final doorCount = (doorResult.first['c'] as int?) ?? 0;
      return (inspCount > 0 || doorCount > 0);
    } catch (_) {
      return false;
    }
  }

  /// Creates an automatic safety backup of the working database prior to any import or replace action.
  /// Keeps the most recent [maxBackups] copies in the app's backup directory.
  static Future<File?> createSafetyBackup(
      {String tag = 'pre_import', int maxBackups = 10}) async {
    try {
      final sourcePath = await _getWorkingDbPath();
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists() || (await sourceFile.length()) == 0) {
        return null;
      }

      // Check if DB actually contains any active records before backing up
      try {
        final db = await getDb();
        final countResult =
            await db.rawQuery('SELECT count(*) as c FROM doors');
        final count = (countResult.first['c'] as int?) ?? 0;
        if (count == 0) {
          return null; // No active doors, skip backup
        }
      } catch (_) {}

      // Get backup directory
      Directory backupDir;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        backupDir = Directory(join(appDir.path, 'WartungsTool', 'Backups'));
      } catch (_) {
        final fallbackDir = await getApplicationSupportDirectory();
        backupDir = Directory(join(fallbackDir.path, 'Backups'));
      }

      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final timeStr = DateFormat('ddMMyyyy_HHmmss').format(DateTime.now());
      final backupFileName = 'auto_backup_${tag}_$timeStr.db';
      final backupFilePath = join(backupDir.path, backupFileName);

      // Copy database file
      final backupFile = await sourceFile.copy(backupFilePath);
      print(
          '[LocalDatabaseService] Automatic safety backup created: $backupFilePath');

      // Prune old backups
      try {
        final existingFiles = backupDir
            .listSync()
            .whereType<File>()
            .where((f) =>
                f.path.endsWith('.db') && f.path.contains('auto_backup_'))
            .toList();

        existingFiles.sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

        if (existingFiles.length > maxBackups) {
          for (int i = maxBackups; i < existingFiles.length; i++) {
            await existingFiles[i].delete();
            print(
                '[LocalDatabaseService] Pruned old backup: ${existingFiles[i].path}');
          }
        }
      } catch (e) {
        print('[LocalDatabaseService] Backup pruning notice: $e');
      }

      return backupFile;
    } catch (e) {
      print('[LocalDatabaseService] Failed to create safety backup: $e');
      return null;
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
  static Future<void> importWorkingDb(String sourcePath,
      {bool createAutoBackup = false}) async {
    final sourceFile = File(sourcePath);

    // 1. Basic File Validation
    if (!await sourceFile.exists()) {
      throw Exception('Import fehlgeschlagen: Quelldatei nicht gefunden.');
    }

    if (!sourcePath.toLowerCase().endsWith('.db')) {
      throw Exception(
          'Import fehlgeschlagen: Ungültiges Dateiformat. Bitte wählen Sie eine .db Datei.');
    }

    // 2. Schema Compatibility Check
    Database? tempDb;
    try {
      if (Platform.isWindows || Platform.isLinux) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      tempDb = await openDatabase(sourcePath, readOnly: true);
      final tables = await tempDb
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      if (!tableNames.contains('doors') ||
          !tableNames.contains('inspections')) {
        throw Exception(
            'Die ausgewählte Datei enthält keine gültigen Prüfungsdaten (Tabellen fehlen).');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Validierungsfehler: $e');
    } finally {
      await tempDb?.close();
    }

    // 3. Create Safety Backup of current working database if requested
    if (createAutoBackup) {
      await createSafetyBackup(tag: 'pre_replace');
    }

    // 4. Execute Import (Replace local working DB)
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
  static Future<ImportReport> importAndMergePackage(String packagePath,
      {bool createAutoBackup = false}) async {
    // Create safety backup before merge if requested
    if (createAutoBackup) {
      await createSafetyBackup(tag: 'pre_merge');
    }
    final localDb = await getDb();

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final absolutePackagePath = File(packagePath).absolute.path;
    final packageDb = await openDatabase(absolutePackagePath, readOnly: true);

    int newDoorsCount = 0;
    int updatedDoorsCount = 0;
    int newInspectionsCount = 0;
    int updatedInspectionsCount = 0;
    int totalErrorsImported = 0;
    int totalAttachmentsImported = 0;
    final List<DoorChangeItem> doorChanges = [];
    final List<String> newCatalogProposals = [];
    final List<DoorConflict> packageDoorConflicts = [];
    final List<LegacyMigrationAudit> legacyAudits = [];

    try {
      // Validate structure
      final tables = await packageDb
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((t) => t['name'] as String).toSet();
      if (!tableNames.contains('doors') ||
          !tableNames.contains('inspections')) {
        throw Exception(
            'Die Datei enthält keine gültigen Prüfungsdaten (Tabellen fehlen).');
      }

      int packageVersion = 0;
      try {
        final verResult = await packageDb.rawQuery('PRAGMA user_version');
        if (verResult.isNotEmpty) {
          packageVersion = (verResult.first.values.first as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
      const int targetVersion = currentDatabaseVersion;

      final Set<String> packageDoorCols =
          await _getTableColumns(packageDb, 'doors');
      final Set<String> packageInspCols =
          await _getTableColumns(packageDb, 'inspections');

      final List<String> convertedProperties = [];
      if (packageDoorCols.contains('lintelHeightUnder1m')) {
        convertedProperties.add(
            'Altes Attribut "lintelHeightUnder1m" (unter 1m) automatisch auf Schema-Standard "lintelHeightInsideOver1m" überführt');
      }
      if (packageDoorCols.contains('lintelHeightOver1m')) {
        convertedProperties.add(
            'Altes Attribut "lintelHeightOver1m" (über 1m) automatisch auf Schema-Standard "lintelHeightInsideOver1m" überführt');
      }
      if (packageDoorCols.contains('customerName')) {
        convertedProperties.add(
            'Metadatum "customerName" in Türzeilen erkannt und kompatibel überführt');
      }
      if (!packageInspCols.contains('orderType')) {
        convertedProperties.add(
            'Fehlende Auftragsphase ("orderType") in Prüfungen automatisch mit "Wartung" initialisiert');
      }
      if (!packageInspCols.contains('isLocked')) {
        convertedProperties.add(
            'Sperrstatus ("isLocked") für Altdaten automatisch mit entsperrt (0) initialisiert');
      }

      await localDb.transaction((txn) async {
        final pInspections = await packageDb.query('inspections');
        final pDoors = await packageDb.query('doors');
        final pJunctions = await packageDb.query('inspection_doors');
        final pErrors = await packageDb.query('inspection_door_errors');
        final pCatalog = await packageDb.query('error_catalog');

        if (pCatalog.isNotEmpty) {
          convertedProperties.add(
              'ID-Remapping für ${pCatalog.length} Mängelkatalog-Einträge via Fehlercode durchgeführt');
        }

        // Check for placeholder properties in doors
        int placeholderApprovalCount = 0;
        int placeholderManufacturerNumCount = 0;
        int placeholderDopCount = 0;
        int placeholderYearCount = 0;
        int placeholderFireProtCount = 0;
        int placeholderSmokeProtCount = 0;
        final List<String> placeholderSampleDoors = [];

        for (final row in pDoors) {
          final doorNum =
              (row['doorNumber'] ?? row['doorAlias'] ?? '').toString().trim();
          bool hasPlaceholder = false;

          final appNo = (row['approvalNumber'] ?? '').toString().trim();
          if (appNo == '?' || appNo.isEmpty) {
            placeholderApprovalCount++;
            hasPlaceholder = true;
          }
          final mfgNo = (row['manufacturerNumber'] ?? '').toString().trim();
          if (mfgNo == '?' || mfgNo.isEmpty) {
            placeholderManufacturerNumCount++;
            hasPlaceholder = true;
          }
          final dop = (row['dopNumber'] ?? '').toString().trim();
          if (dop == '?' || dop.isEmpty) {
            placeholderDopCount++;
            hasPlaceholder = true;
          }
          final year = (row['manufactureYear'] ?? '').toString().trim();
          if (year == '?' || year.isEmpty) {
            placeholderYearCount++;
            hasPlaceholder = true;
          }
          final fp = (row['fireProtection'] ?? '').toString().trim();
          if (fp == '?') {
            placeholderFireProtCount++;
            hasPlaceholder = true;
          }
          final sp = (row['smokeProtection'] ?? '').toString().trim();
          if (sp == '?') {
            placeholderSmokeProtCount++;
            hasPlaceholder = true;
          }

          if (hasPlaceholder &&
              placeholderSampleDoors.length < 8 &&
              doorNum.isNotEmpty) {
            if (!placeholderSampleDoors.contains(doorNum)) {
              placeholderSampleDoors.add(doorNum);
            }
          }
        }

        final Map<String, int> placeholderDoorProperties = {};
        if (placeholderApprovalCount > 0) {
          placeholderDoorProperties['Zulassungsnummer (approvalNumber)'] =
              placeholderApprovalCount;
        }
        if (placeholderManufacturerNumCount > 0) {
          placeholderDoorProperties['Herstellernummer (manufacturerNumber)'] =
              placeholderManufacturerNumCount;
        }
        if (placeholderDopCount > 0) {
          placeholderDoorProperties['Leistungserklärung / DoP (dopNumber)'] =
              placeholderDopCount;
        }
        if (placeholderYearCount > 0) {
          placeholderDoorProperties['Baujahr (manufactureYear)'] =
              placeholderYearCount;
        }
        if (placeholderFireProtCount > 0) {
          placeholderDoorProperties['Brandschutzklasse (fireProtection)'] =
              placeholderFireProtCount;
        }
        if (placeholderSmokeProtCount > 0) {
          placeholderDoorProperties['Rauchschutzklasse (smokeProtection)'] =
              placeholderSmokeProtCount;
        }

        final bool isLegacy = packageVersion < targetVersion ||
            convertedProperties.isNotEmpty ||
            placeholderDoorProperties.isNotEmpty;
        if (isLegacy) {
          final firstInsp = pInspections.isNotEmpty
              ? pInspections.first
              : <String, dynamic>{};
          final firstJobNum =
              (firstInsp['jobNumber'] ?? firstInsp['auftragsnummer'] ?? '')
                  .toString();
          final firstClient = (firstInsp['clientName'] ?? '').toString();
          final firstAddress = (firstInsp['objectAddress'] ?? '').toString();
          final firstRepairDate = firstInsp['repairDate']?.toString();

          legacyAudits.add(LegacyMigrationAudit(
            fileName: basename(packagePath),
            packageVersion: packageVersion,
            targetVersion: targetVersion,
            jobNumber: firstJobNum,
            clientName: firstClient,
            objectAddress: firstAddress,
            defaultOrderType: 'Wartung',
            repairDate: firstRepairDate,
            newFeatures: const [
              'Mehrstufige Auftragsphasen (Wartung ➔ Reparatur ➔ Erledigt) mit getrenntem Reparaturdatum',
              'Auftragssperre & Schreibschutz (isLocked) für Revisionssicherheit',
              'Erweiterte Sturzhöhen-Parameter (Innen/Außen getrennt, inkl. Messwerte)',
              'Dynamische Dropdown-Optionen mit Whitelist-Validierung',
            ],
            convertedProperties: convertedProperties,
            placeholderDoorProperties: placeholderDoorProperties,
            placeholderSampleDoors: placeholderSampleDoors,
            managerActionHints: const [
              '1. Überprüfen Sie den importierten Auftrag in der Auftragsübersicht (Standardmäßig als Phase "Wartung" angelegt).',
              '2. Öffnen Sie die Türverwaltung im Master-Portal, um bei Bedarf mit "?" markierte Felder (z.B. Zulassungsnummer, Herstellernummer, Baujahr) manuell nachzupflegen.',
              '3. Falls eine Reparatur durchgeführt wurde oder wird, wechseln Sie die Phase auf "Reparatur" bzw. tragen Sie das Reparaturdatum ein.',
              '4. Nach Abschluss aller Nacharbeiten kann der Auftrag über das Schloss-Symbol gesperrt (isLocked) werden.',
            ],
          ));
        }

        // 1. Merge catalog
        final localCatalogColumns =
            await _getTableColumns(txn, 'error_catalog');
        final catalogList =
            pCatalog.map((m) => ErrorCatalog.fromMap(m)).toList();
        for (var cat in catalogList) {
          final existing = await txn.query('error_catalog',
              where: 'code = ?', whereArgs: [cat.code], limit: 1);
          if (existing.isEmpty && cat.status == 'Pending') {
            newCatalogProposals.add('${cat.code}: ${cat.description}');
          }
        }
        for (final cat in catalogList) {
          final catData = cat.toMap();
          catData.removeWhere((k, _) => !localCatalogColumns.contains(k));
          await txn.insert('error_catalog', catData,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 2. Merge inspections
        final localInspectionColumns =
            await _getTableColumns(txn, 'inspections');
        for (var insp in pInspections) {
          final data = Map<String, dynamic>.from(insp);
          data.remove('doorCount');
          if (data['orderType'] == null ||
              data['orderType'].toString().trim().isEmpty) {
            data['orderType'] = 'Wartung';
          }
          data.removeWhere((k, _) => !localInspectionColumns.contains(k));
          final jobNum =
              (insp['jobNumber'] ?? insp['auftragsnummer'] ?? '') as String;
          final existing = await txn.query('inspections',
              where: 'jobNumber = ?', whereArgs: [jobNum], limit: 1);
          if (existing.isNotEmpty) {
            updatedInspectionsCount++;
          } else {
            newInspectionsCount++;
          }
          await txn.insert('inspections', data,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 3. Merge doors
        final localDoorColumns = await _getTableColumns(txn, 'doors');
        for (var door in pDoors) {
          final incomingDoor = Door.fromMap(door);
          final alias =
              incomingDoor.doorAlias ?? (door['doorAlias'] as String? ?? '');
          final existing = alias.isNotEmpty
              ? await txn.query('doors',
                  where: 'doorAlias = ?', whereArgs: [alias], limit: 1)
              : <Map<String, dynamic>>[];
          if (existing.isNotEmpty) {
            updatedDoorsCount++;
          } else {
            newDoorsCount++;
          }
          final doorMap = incomingDoor.toMap();
          final data = <String, dynamic>{};
          for (final entry in doorMap.entries) {
            if (localDoorColumns.contains(entry.key)) {
              data[entry.key] = entry.value;
            }
          }
          await txn.insert('doors', data,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 4. Merge junctions
        final localJunctionColumns =
            await _getTableColumns(txn, 'inspection_doors');
        for (var junction in pJunctions) {
          final doorId = junction['doorId'] as int?;
          final doorRow = doorId != null
              ? pDoors.firstWhere((d) => d['id'] == doorId, orElse: () => {})
              : {};
          final alias = doorRow['doorAlias'] as String? ?? '';
          final doorNum = doorRow['doorNumber'] as String? ?? '';
          final roomDesig = doorRow['roomDesignation'] as String? ?? '';
          final status = junction['status'] as String? ?? 'InProgress';
          final junctionId = junction['id'] as int?;

          final existingJunction = await txn.query('inspection_doors',
              where: 'inspectionId = ? AND doorId = ?',
              whereArgs: [junction['inspectionId'], junction['doorId']],
              limit: 1);

          final junctionData = Map<String, dynamic>.from(junction);
          junctionData.removeWhere((k, _) => !localJunctionColumns.contains(k));
          await txn.insert('inspection_doors', junctionData,
              conflictAlgorithm: ConflictAlgorithm.replace);

          final errCount =
              pErrors.where((e) => e['inspectionDoorId'] == junctionId).length;
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
        final localErrorColumns =
            await _getTableColumns(txn, 'inspection_door_errors');
        totalErrorsImported = pErrors.length;
        for (var err in pErrors) {
          final att = err['attachments'] as String? ?? '';
          if (att.isNotEmpty) {
            totalAttachmentsImported++;
          }
          final errData = Map<String, dynamic>.from(err);
          errData.removeWhere((k, _) => !localErrorColumns.contains(k));
          await txn.insert('inspection_door_errors', errData,
              conflictAlgorithm: ConflictAlgorithm.replace);
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
        legacyAudits: legacyAudits,
      );
    } finally {
      await packageDb.close();
    }
  }

  static Future<Set<String>> _getTableColumns(
      DatabaseExecutor db, String tableName) async {
    try {
      final rows = await db.rawQuery('PRAGMA table_info($tableName)');
      return rows.map((r) => r['name'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CRAFTNOTE CLOUD INTEGRATION & OFFLINE QUEUE
  // ─────────────────────────────────────────────────────────────

  /// Updates Craftnote linkage and synchronization status for an inspection in Local DB.
  static Future<void> updateInspectionCraftnoteStatus(
    int inspectionId, {
    String? projectId,
    String? fileId,
    String? syncStatus,
    String? lastSyncTime,
  }) async {
    final db = await getDb();
    final values = <String, dynamic>{};
    if (projectId != null) values['craftnoteProjectId'] = projectId;
    if (fileId != null) values['craftnoteFileId'] = fileId;
    if (syncStatus != null) values['craftnoteSyncStatus'] = syncStatus;
    values['craftnoteLastSyncTime'] =
        lastSyncTime ?? DateTime.now().toIso8601String();

    await db.update(
      'inspections',
      values,
      where: 'inspectionId = ?',
      whereArgs: [inspectionId],
    );
  }

  /// Enqueues an upload task into local SQLite for background/retry sync.
  static Future<int> enqueueCraftnoteUpload(
      CraftnoteUploadQueueItem item) async {
    final db = await getDb();
    return await db.insert(
      'craftnote_upload_queue',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves all pending Craftnote uploads ordered by queued timestamp ascending.
  static Future<List<CraftnoteUploadQueueItem>>
      getPendingCraftnoteUploads() async {
    final db = await getDb();
    final rows = await db.query(
      'craftnote_upload_queue',
      orderBy: 'queuedAt ASC',
    );
    return rows.map((r) => CraftnoteUploadQueueItem.fromMap(r)).toList();
  }

  /// Removes an upload queue item once successfully synced.
  static Future<int> deleteCraftnoteUploadQueueItem(int id) async {
    final db = await getDb();
    return await db.delete(
      'craftnote_upload_queue',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Increments retry count and sets last error message for an upload queue item.
  static Future<void> incrementCraftnoteUploadAttempt(int id,
      {String? error}) async {
    final db = await getDb();
    await db.rawUpdate('''
      UPDATE craftnote_upload_queue
      SET attempts = attempts + 1, lastError = ?
      WHERE id = ?
    ''', [error, id]);
  }
}
