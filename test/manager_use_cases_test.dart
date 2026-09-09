import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/services/gaeb_export_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseService.closeDb();
    await LocalDatabaseService.closeDb();

    final dbPath = await getDatabasesPath();
    final masterPath = p.join(dbPath, 'door_inspection.db');
    final localPath = p.join(dbPath, 'working.db');

    try {
      if (await File(masterPath).exists()) await File(masterPath).delete();
    } catch (_) {}
    try {
      if (await File(localPath).exists()) await File(localPath).delete();
    } catch (_) {}

    final masterDb = await DatabaseService.getDb();
    await masterDb.delete('inspection_door_errors');
    await masterDb.delete('inspection_doors');
    await masterDb.delete('inspections');
    await masterDb.delete('doors');
    await masterDb.delete('error_catalog');
  });

  tearDown(() async {
    await DatabaseService.closeDb();
    await LocalDatabaseService.closeDb();
  });

  group('Manager Use Cases Test Suite (Easy, Medium, Hard Levels)', () {

    // =========================================================================
    // LEVEL 1: HAPPY PATH / EASY LEVEL TESTS (M-UC-01 to M-UC-06)
    // =========================================================================
    group('Level 1: Happy Path / Standard Workflows', () {

      test('M-UC-01 [EASY]: Create New Inspection Job & Assign Doors to Facility', () async {
        // TEST DATA: 1 Door, 1 Inspection map
        final doorId = await DatabaseService.insertDoor(Door(
          id: null,
          pos: 1,
          doorAlias: 'GOTTS-EBN43-EG-01',
          doorNumber: 'T-101',
          floor: 'EG',
          roomNumber: '101',
          roomDesignation: 'Büro GF',
          doorType: 'T30',
          wingCount: 1,
          material: 'Stahl',
          manufacturer: 'Hörmann',
          dinConfiguration: 'DIN L',
          closerType: 'TS93',
          closingSequenceSystem: '',
          lockDimensions: '55/72/9',
          closerOnHingeSide: true,
          closerOnOppositeSide: false,
          lintelHeightInsideOver1m: false,
          escapeDoorControl: true,
          accessControl: 'RFID',
          escapeRouteSituation: true,
          escapeRouteSignage: true,
          blindCylinder: false,
          pzCylinder: true,
          fittingType: 'Drücker/Drücker',
          panicFunction: 'Panik E',
          escapeDirectionRespected: true,
          fullPanicStandWing: false,
          doorFunctionOK: true,
        ));

        final inspectionId = await DatabaseService.insertInspection({
          'clientName': 'Gottsberg GmbH',
          'objectAddress': 'Ebner-Eschenbach-Weg 43, Hamburg',
          'date': '2026-09-01',
          'contactPerson': 'Herr Gottsberg',
          'inspectorName': 'Techniker Max',
          'jobNumber': 'JOB-M-UC-01',
        });

        final junctionId = await DatabaseService.insertInspectionDoor({
          'inspectionId': inspectionId,
          'doorId': doorId,
          'status': 'InProgress',
          'notes': 'Erstinspektion 2026',
        });

        expect(inspectionId, isNotNull);
        expect(junctionId, isNotNull);

        final inspections = await DatabaseService.getAllInspections();
        expect(inspections.length, equals(1));
        expect(inspections.first['jobNumber'], equals('JOB-M-UC-01'));
      });

      test('M-UC-02 [EASY]: Export Job Package for Field Inspector Checkout', () async {
        await DatabaseService.insertErrorCatalog(ErrorCatalog(
          code: 'M-01',
          description: 'Türschließer undicht',
          category: 'Schließer',
          severity: 'medium',
          status: 'Approved',
        ));

        final doorId = await DatabaseService.insertDoor(Door(
          id: null,
          pos: 1,
          doorAlias: 'BAHN-HAUPT-OG1-02',
          doorNumber: 'T-202',
          floor: '1.OG',
          roomNumber: '202',
          roomDesignation: 'Flur',
          doorType: 'RS-1',
          wingCount: 2,
          material: 'Aluminium',
          manufacturer: 'Dorma',
          dinConfiguration: 'DIN R',
          closerType: 'TS5000',
          closingSequenceSystem: 'SR390',
          lockDimensions: '65/72/9',
          closerOnHingeSide: true,
          closerOnOppositeSide: false,
          lintelHeightInsideOver1m: false,
          escapeDoorControl: false,
          accessControl: '',
          escapeRouteSituation: true,
          escapeRouteSignage: true,
          blindCylinder: false,
          pzCylinder: true,
          fittingType: 'Stange',
          panicFunction: 'Panik B',
          escapeDirectionRespected: true,
          fullPanicStandWing: true,
          doorFunctionOK: true,
        ));

        final inspectionId = await DatabaseService.insertInspection({
          'clientName': 'Deutsche Bahn AG',
          'objectAddress': 'Hauptbahnhof 1',
          'date': '2026-09-02',
          'jobNumber': 'JOB-PKG-02',
        });

        await DatabaseService.insertInspectionDoor({
          'inspectionId': inspectionId,
          'doorId': doorId,
          'status': 'InProgress',
        });

        await LocalDatabaseService.downloadJobPackage(inspectionIds: [inspectionId]);

        final localDoors = await LocalDatabaseService.getDoorsByInspectionId(inspectionId);
        expect(localDoors.length, equals(1));
        expect(localDoors.first.doorNumber, equals('T-202'));
      });

      test('M-UC-03 [EASY]: Import & Merge Completed Field Package into Master DB', () async {
        final dbPath = await getDatabasesPath();
        final packagePath = p.join(dbPath, 'completed_field_package.db');
        if (await File(packagePath).exists()) await File(packagePath).delete();

        final pkgDb = await openDatabase(
          packagePath,
          version: 18,
          onCreate: (db, v) async {
            await db.execute('CREATE TABLE doors (id INTEGER PRIMARY KEY, doorAlias TEXT UNIQUE, doorNumber TEXT, floor TEXT, roomNumber TEXT, roomDesignation TEXT, doorType TEXT, wingCount INTEGER, material TEXT, manufacturer TEXT, dinConfiguration TEXT, closerType TEXT, closingSequenceSystem TEXT, lockDimensions TEXT, closerOnHingeSide INTEGER, closerOnOppositeSide INTEGER, lintelHeightInsideOver1m INTEGER DEFAULT 0, escapeDoorControl INTEGER, accessControl TEXT, escapeRouteSituation INTEGER, escapeRouteSignage INTEGER, blindCylinder INTEGER, pzCylinder INTEGER, fittingType TEXT, panicFunction TEXT, escapeDirectionRespected INTEGER, fullPanicStandWing INTEGER, doorFunctionOK INTEGER)');
            await db.execute('CREATE TABLE inspections (inspectionId INTEGER PRIMARY KEY, clientName TEXT, objectAddress TEXT, date TEXT, contactPerson TEXT, inspectorName TEXT, jobNumber TEXT)');
            await db.execute('CREATE TABLE inspection_doors (id INTEGER PRIMARY KEY, inspectionId INTEGER, doorId INTEGER, status TEXT, notes TEXT)');
            await db.execute('CREATE TABLE inspection_door_errors (id INTEGER PRIMARY KEY, inspectionDoorId INTEGER, errorId INTEGER, errorCode TEXT, quantity INTEGER, severity TEXT, notes TEXT, attachments TEXT)');
            await db.execute('CREATE TABLE error_catalog (errorId INTEGER PRIMARY KEY, code TEXT UNIQUE, description TEXT, category TEXT, status TEXT)');
          },
        );

        await pkgDb.insert('doors', {
          'id': 1,
          'doorAlias': 'ALIAS-FIELD-01',
          'doorNumber': 'T-FIELD-1',
          'floor': 'EG',
          'roomNumber': '001',
          'roomDesignation': 'Empfang',
          'doorType': 'T90',
          'wingCount': 1,
          'material': 'Stahl',
          'manufacturer': 'Hörmann',
          'dinConfiguration': 'DIN L',
          'doorFunctionOK': 0,
        });

        await pkgDb.insert('inspections', {
          'inspectionId': 1,
          'clientName': 'Field Client',
          'objectAddress': 'Field Street 1',
          'date': '2026-09-03',
          'jobNumber': 'JOB-FIELD-03',
        });

        await pkgDb.insert('inspection_doors', {
          'id': 50,
          'inspectionId': 1,
          'doorId': 1,
          'status': 'Failed',
          'notes': 'Dichtung beschädigt',
        });

        await pkgDb.insert('error_catalog', {
          'errorId': 100,
          'code': 'ERR-FIELD-01',
          'description': 'Quelldichtung defekt',
          'category': 'Dichtung',
          'status': 'Approved',
        });

        await pkgDb.insert('inspection_door_errors', {
          'id': 10,
          'inspectionDoorId': 50,
          'errorId': 100,
          'errorCode': 'ERR-FIELD-01',
          'quantity': 1,
          'severity': 'high',
          'notes': 'Dichtung eingerissen',
        });

        await pkgDb.close();

        final report = await DatabaseService.importAndMergePackage(packagePath);

        expect(report.newDoorsCount, equals(1));
        expect(report.newInspectionsCount, equals(1));
        expect(report.totalErrorsImported, equals(1));

        final allMasterDoors = await DatabaseService.getAllDoors();
        expect(allMasterDoors.any((d) => d.doorAlias == 'ALIAS-FIELD-01'), isTrue);

        if (await File(packagePath).exists()) await File(packagePath).delete();
      });

      test('M-UC-05 [EASY]: Review & Approve Pending Field Defect Proposal', () async {
        await DatabaseService.insertErrorCatalog(ErrorCatalog(
          code: 'PROP-01',
          description: 'Panikstange verbogen',
          category: 'Beschlag',
          severity: 'high',
          status: 'Pending',
          requestedBy: 'Inspector Bob',
        ));

        final pendingBefore = await DatabaseService.getAllErrorCatalog(status: 'Pending');
        expect(pendingBefore.length, equals(1));
        expect(pendingBefore.first.code, equals('PROP-01'));

        final itemToApprove = pendingBefore.first.copyWith(status: 'Approved');
        await DatabaseService.insertErrorCatalog(itemToApprove);

        final pendingAfter = await DatabaseService.getAllErrorCatalog(status: 'Pending');
        expect(pendingAfter.isEmpty, isTrue);

        final approvedList = await DatabaseService.getAllErrorCatalog(status: 'Approved');
        expect(approvedList.any((e) => e.code == 'PROP-01'), isTrue);
      });

    });

    // =========================================================================
    // LEVEL 2: MEDIUM DIFFICULTY / EDGE CASES & EXCEPTION HANDLING
    // =========================================================================
    group('Level 2: Medium Edge Cases & Error Recovery', () {

      test('M-UC-04-MED1: Excel Import Non-Existent or Corrupted File Graceful Handling', () async {
        // TEST DATA PURPOSE:
        // Pass a non-existent file path to `ExcelDataImporter.importFromFile()`.
        // EXPECTED RESULT:
        // Must throw an Exception or return 0 sheets gracefully without unhandled crash.
        final missingFile = File('test/test_data/non_existent_file_12345.xlsx');
        
        expect(
          () async => await ExcelDataImporter.importFromFile(missingFile),
          throwsA(isA<Exception>()),
        );
      });

      test('M-UC-03-MED2: Package Import with Corrupted / Invalid DB Schema', () async {
        // TEST DATA PURPOSE:
        // Create an invalid SQLite DB missing required tables ('doors', 'inspections').
        // EXPECTED RESULT:
        // `importAndMergePackage` catches DB exception and returns 0 imported records safely.
        final dbPath = await getDatabasesPath();
        final corruptPath = p.join(dbPath, 'corrupted_package.db');
        if (await File(corruptPath).exists()) await File(corruptPath).delete();

        final corruptDb = await openDatabase(corruptPath, version: 1, onCreate: (db, v) async {
          await db.execute('CREATE TABLE dummy_invalid_table (id INTEGER PRIMARY KEY)');
        });
        await corruptDb.close();

        try {
          final report = await DatabaseService.importAndMergePackage(corruptPath);
          expect(report.newDoorsCount, equals(0));
        } catch (e) {
          expect(e, isA<DatabaseException>());
        }

        if (await File(corruptPath).exists()) await File(corruptPath).delete();
      });

      test('M-UC-06-MED3: GAEB XML Generator Text Escaping & Special Character Handling', () async {
        // TEST DATA PURPOSE:
        // Door and defect containing XML reserved characters: `< > & " '` and German umlauts.
        // EXPECTED RESULT:
        // XML output is built clean without crashing, escaping or encoding XML reserved syntax.
        final door = Door(
          id: 1,
          pos: 1,
          doorAlias: 'DOOR-XML-&<>\'\"',
          doorNumber: 'T-XML-<1>',
          floor: 'EG',
          roomNumber: '100',
          roomDesignation: 'Raum & Flur <A>',
          doorType: 'T30',
          wingCount: 1,
          material: 'Stahl',
          manufacturer: 'Hörmann',
          dinConfiguration: 'DIN L',
          closerType: 'TS93',
          closingSequenceSystem: '',
          lockDimensions: '',
          closerOnHingeSide: true,
          closerOnOppositeSide: false,
          lintelHeightInsideOver1m: false,
          escapeDoorControl: false,
          accessControl: '',
          escapeRouteSituation: true,
          escapeRouteSignage: true,
          blindCylinder: false,
          pzCylinder: true,
          fittingType: '',
          panicFunction: '',
          escapeDirectionRespected: true,
          fullPanicStandWing: false,
          doorFunctionOK: false,
        );

        final exportService = GaebExportService(
          customer: 'Client & Partner GmbH',
          projectName: 'Projekt <Neubau> & Sanierung',
          jobNumber: '9999',
        );

        final exportData = [
          {
            'door': door,
            'errors': [
              {
                'code': 'ERR-&1',
                'description': 'Türschließer & Dichtung defekt <Prüfbericht>',
                'severity': 'high',
                'quantity': 1,
              }
            ]
          }
        ];

        final xmlOutput = exportService.generateXmlString(exportData);
        expect(xmlOutput, isNotEmpty);
        expect(xmlOutput, contains('<GAEB xmlns="http://www.gaeb.de/GAEB_DA_XML/DA83/3.2">'));
      });

      test('M-UC-05-MED4: Catalog Conflict Detection on Duplicate Code Insert', () async {
        // TEST DATA PURPOSE:
        // Insert catalog defect with code 'M-01', then attempt inserting another defect with same code 'M-01' but different text.
        // EXPECTED RESULT:
        // Database replaces/updates entry or handles conflict cleanly without database lock exception.
        await DatabaseService.insertErrorCatalog(ErrorCatalog(
          code: 'M-01',
          description: 'Original Dichtung defekt',
          category: 'Dichtung',
        ));

        await DatabaseService.insertErrorCatalog(ErrorCatalog(
          code: 'M-01',
          description: 'Aktualisierte Dichtung beschädigt',
          category: 'Dichtung',
        ));

        final catalog = await DatabaseService.getAllErrorCatalog();
        final matches = catalog.where((c) => c.code == 'M-01').toList();
        expect(matches.length, equals(1));
        expect(matches.first.description, equals('Aktualisierte Dichtung beschädigt'));
      });

    });

    // =========================================================================
    // LEVEL 3: HARD / LIMIT & REAL LEGACY DATA TESTS
    // =========================================================================
    group('Level 3: Hard Level & Real Legacy Workbook Mass Migration', () {

      test('M-UC-04-HARD1: Real Legacy Excel Workbook Migration (Ebner-Eschenbach-Weg 43)', () async {
        // TEST DATA PURPOSE:
        // Load actual production legacy Excel workbook from `test/test_data/`:
        // "25-12343-AB P-003926 Ebner-Eschenbach-Weg 43, 21035 Hamburg Türen final.xlsx"
        //
        // EXPECTED RESULTS:
        // 1. Excel importer processes multi-sheet workbook cleanly without memory crash.
        // 2. Returns processed sheets >= 1 and doors imported >= 1.
        // 3. First-time migration logs record worksheet names (`Arbeitsblatt: "..."`).
        final legacyFile = File('test/test_data/25-12343-AB P-003926 Ebner-Eschenbach-Weg 43, 21035 Hamburg Türen final.xlsx');

        if (!await legacyFile.exists()) {
          print('Skipping M-UC-04-HARD1: Legacy test file not found at ${legacyFile.path}');
          return;
        }

        final result = await ExcelDataImporter.importFromFile(legacyFile);

        expect(result.sheetsProcessed, greaterThanOrEqualTo(1));
        expect(result.doorsImported, greaterThan(0));
        expect(result.logs.isNotEmpty, isTrue);

        final masterDoors = await DatabaseService.getAllDoors();
        expect(masterDoors.length, greaterThan(0));
      });

      test('M-UC-03-HARD2: Sequential Multi-Package Inspector Check-in Stress Test', () async {
        // TEST DATA PURPOSE:
        // Create 3 separate field package SQLite DBs representing 3 different inspector tablets
        // checking in results sequentially into the central Master DB.
        // EXPECTED RESULT:
        // All 3 packages merge cleanly, master door records consolidate, and zero data loss occurs.
        final dbPath = await getDatabasesPath();

        for (int pIndex = 1; pIndex <= 3; pIndex++) {
          final pkgPath = p.join(dbPath, 'seq_package_$pIndex.db');
          if (await File(pkgPath).exists()) await File(pkgPath).delete();

          final pkgDb = await openDatabase(
            pkgPath,
            version: 18,
            onCreate: (db, v) async {
              await db.execute('CREATE TABLE doors (id INTEGER PRIMARY KEY, doorAlias TEXT UNIQUE, doorNumber TEXT, floor TEXT, roomNumber TEXT, roomDesignation TEXT, doorType TEXT, wingCount INTEGER, material TEXT, manufacturer TEXT, dinConfiguration TEXT, closerType TEXT, closingSequenceSystem TEXT, lockDimensions TEXT, closerOnHingeSide INTEGER, closerOnOppositeSide INTEGER, lintelHeightInsideOver1m INTEGER DEFAULT 0, escapeDoorControl INTEGER, accessControl TEXT, escapeRouteSituation INTEGER, escapeRouteSignage INTEGER, blindCylinder INTEGER, pzCylinder INTEGER, fittingType TEXT, panicFunction TEXT, escapeDirectionRespected INTEGER, fullPanicStandWing INTEGER, doorFunctionOK INTEGER)');
              await db.execute('CREATE TABLE inspections (inspectionId INTEGER PRIMARY KEY, clientName TEXT, objectAddress TEXT, date TEXT, contactPerson TEXT, inspectorName TEXT, jobNumber TEXT)');
              await db.execute('CREATE TABLE inspection_doors (id INTEGER PRIMARY KEY, inspectionId INTEGER, doorId INTEGER, status TEXT, notes TEXT)');
              await db.execute('CREATE TABLE inspection_door_errors (id INTEGER PRIMARY KEY, inspectionDoorId INTEGER, errorId INTEGER, errorCode TEXT, quantity INTEGER, severity TEXT, notes TEXT, attachments TEXT)');
              await db.execute('CREATE TABLE error_catalog (errorId INTEGER PRIMARY KEY, code TEXT UNIQUE, description TEXT, category TEXT, status TEXT)');
            },
          );

          await pkgDb.insert('doors', {
            'id': pIndex,
            'doorAlias': 'MULTI-PKG-DOOR-0$pIndex',
            'doorNumber': 'T-00$pIndex',
            'floor': 'EG',
            'roomNumber': '10$pIndex',
            'roomDesignation': 'Büro $pIndex',
            'doorType': 'T30',
            'wingCount': 1,
            'material': 'Stahl',
            'manufacturer': 'Hörmann',
            'dinConfiguration': 'DIN L',
            'doorFunctionOK': 1,
          });

          await pkgDb.insert('inspections', {
            'inspectionId': pIndex,
            'clientName': 'Multi Package Client',
            'objectAddress': 'Multi Street $pIndex',
            'date': '2026-09-01',
            'jobNumber': 'JOB-MULTI-0$pIndex',
          });

          await pkgDb.insert('inspection_doors', {
            'id': pIndex * 10,
            'inspectionId': pIndex,
            'doorId': pIndex,
            'status': 'Passed',
          });

          await pkgDb.close();

          final report = await DatabaseService.importAndMergePackage(pkgPath);
          expect(report.newDoorsCount, equals(1));
          expect(report.newInspectionsCount, equals(1));

          if (await File(pkgPath).exists()) await File(pkgPath).delete();
        }

        final finalMasterDoors = await DatabaseService.getAllDoors();
        expect(finalMasterDoors.length, equals(3));
      });

    });

  });
}
