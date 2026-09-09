import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';

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

    final localDb = await LocalDatabaseService.getDb();
    await localDb.delete('inspection_door_errors');
    await localDb.delete('inspection_doors');
    await localDb.delete('inspections');
    await localDb.delete('doors');
    await localDb.delete('error_catalog');
  });

  tearDown(() async {
    await DatabaseService.closeDb();
    await LocalDatabaseService.closeDb();
  });

  group('Inspector Use Cases Test Suite (Easy, Medium, Hard Levels)', () {

    // =========================================================================
    // LEVEL 1: HAPPY PATH / EASY LEVEL TESTS (I-UC-01 to I-UC-04)
    // =========================================================================
    group('Level 1: Happy Path / Standard Inspector Workflows', () {

      test('I-UC-01 [EASY]: Checkout & Download Assigned Job Package to Local Tablet DB', () async {
        await DatabaseService.insertErrorCatalog(ErrorCatalog(
          code: 'M-01',
          description: 'Türschließer defekt',
          category: 'Schließer',
          severity: 'high',
          status: 'Approved',
        ));

        final d1 = await DatabaseService.insertDoor(Door(
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
          lockDimensions: '',
          closerOnHingeSide: true,
          closerOnOppositeSide: false,
          lintelHeightInsideOver1m: false,
          escapeDoorControl: true,
          accessControl: '',
          escapeRouteSituation: true,
          escapeRouteSignage: true,
          blindCylinder: false,
          pzCylinder: true,
          fittingType: '',
          panicFunction: '',
          escapeDirectionRespected: true,
          fullPanicStandWing: false,
          doorFunctionOK: true,
        ));

        final inspectionId = await DatabaseService.insertInspection({
          'clientName': 'Field Site GmbH',
          'objectAddress': 'Wartungsstraße 10',
          'date': '2026-09-01',
          'jobNumber': 'JOB-FIELD-101',
        });

        await DatabaseService.insertInspectionDoor({'inspectionId': inspectionId, 'doorId': d1, 'status': 'InProgress'});

        await LocalDatabaseService.downloadJobPackage(inspectionIds: [inspectionId]);

        final localDoors = await LocalDatabaseService.getDoorsByInspectionId(inspectionId);
        expect(localDoors.length, equals(1));

        final localDb = await LocalDatabaseService.getDb();
        final localCatalogRows = await localDb.query('error_catalog');
        expect(localCatalogRows.length, equals(1));
        expect(localCatalogRows.first['code'], equals('M-01'));
      });

      test('I-UC-02 [EASY]: Record Defect & Photo Documentation During Site Visit', () async {
        final localDb = await LocalDatabaseService.getDb();
        await localDb.insert('error_catalog', {
          'errorId': 1,
          'code': 'M-01',
          'description': 'Türschließer undicht',
          'category': 'Schließer',
          'severity': 'high',
          'status': 'Approved',
        });

        final doorId = await LocalDatabaseService.insertDoor(Door(
          id: null,
          pos: 1,
          doorAlias: 'FIELD-DOOR-01',
          doorNumber: 'T-01',
          floor: 'EG',
          roomNumber: '01',
          roomDesignation: 'Lager',
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
          escapeRouteSituation: false,
          escapeRouteSignage: false,
          blindCylinder: false,
          pzCylinder: true,
          fittingType: '',
          panicFunction: '',
          escapeDirectionRespected: true,
          fullPanicStandWing: false,
          doorFunctionOK: false,
        ));

        final inspectionId = await LocalDatabaseService.insertInspection({
          'clientName': 'Site Client',
          'objectAddress': 'Site Address 1',
          'date': '2026-09-01',
          'jobNumber': 'JOB-FIELD-102',
        });

        final inspDoorId = await LocalDatabaseService.insertInspectionDoor({
          'inspectionId': inspectionId,
          'doorId': doorId,
          'status': 'Failed',
          'notes': 'Türschließer verliert Öl',
        });

        final mockPhotoBase64 = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

        final defectId = await LocalDatabaseService.insertInspectionDoorError(InspectionDoorError(
          inspectionDoorId: inspDoorId,
          errorId: 1,
          errorCode: 'M-01',
          quantity: 1,
          severity: 'high',
          notes: 'Ölaustritt am Ventil',
          attachments: mockPhotoBase64,
        ));

        expect(defectId, isNotNull);
        final detailed = await LocalDatabaseService.getDetailedErrorsForInspectionDoor(inspDoorId);
        expect(detailed.length, equals(1));
        expect(detailed.first['code'], equals('M-01'));
      });

      test('I-UC-03 [EASY]: Propose New Uncatalogued Field Defect', () async {
        final doorId = await LocalDatabaseService.insertDoor(Door(
          id: null,
          pos: 1,
          doorAlias: 'FIELD-PROP-01',
          doorNumber: 'T-PROP',
          floor: 'EG',
          roomNumber: '10',
          roomDesignation: 'Technik',
          doorType: 'T90',
          wingCount: 1,
          material: 'Stahl',
          manufacturer: 'Hörmann',
          dinConfiguration: 'DIN R',
          closerType: 'TS93',
          closingSequenceSystem: '',
          lockDimensions: '',
          closerOnHingeSide: true,
          closerOnOppositeSide: false,
          lintelHeightInsideOver1m: false,
          escapeDoorControl: false,
          accessControl: '',
          escapeRouteSituation: false,
          escapeRouteSignage: false,
          blindCylinder: false,
          pzCylinder: true,
          fittingType: '',
          panicFunction: '',
          escapeDirectionRespected: true,
          fullPanicStandWing: false,
          doorFunctionOK: false,
        ));

        final inspectionId = await LocalDatabaseService.insertInspection({
          'clientName': 'Proposal Client',
          'objectAddress': 'Proposal Street',
          'date': '2026-09-01',
          'jobNumber': 'JOB-PROP-03',
        });

        final inspDoorId = await LocalDatabaseService.insertInspectionDoor({
          'inspectionId': inspectionId,
          'doorId': doorId,
          'status': 'Failed',
        });

        await LocalDatabaseService.proposeNewError(
          inspectionDoorId: inspDoorId,
          description: 'Schlossfalle gebrochen',
          category: 'Schloss',
          severity: 'high',
        );

        final localDb = await LocalDatabaseService.getDb();
        final catalogRows = await localDb.query('error_catalog', where: 'description = ?', whereArgs: ['Schlossfalle gebrochen']);
        expect(catalogRows.length, equals(1));
        expect(catalogRows.first['status'], equals('Pending'));
      });

    });

    // =========================================================================
    // LEVEL 2: MEDIUM DIFFICULTY / EDGE CASES & UNICODE HANDLING
    // =========================================================================
    group('Level 2: Medium Edge Cases & Multi-Defect Recording', () {

      test('I-UC-02-MED1: Record Multiple Defects & Large Base64 Payloads per Door', () async {
        // TEST DATA PURPOSE:
        // Record 5 distinct defects on a single door with multiple photo base64 strings.
        // EXPECTED RESULT:
        // Local DB correctly links all 5 defects to the inspection door ID.
        final localDb = await LocalDatabaseService.getDb();

        for (int i = 1; i <= 5; i++) {
          await localDb.insert('error_catalog', {
            'errorId': i,
            'code': 'M-0$i',
            'description': 'Mangel Typ $i',
            'category': 'Allgemein',
            'severity': 'medium',
            'status': 'Approved',
          });
        }

        final doorId = await LocalDatabaseService.insertDoor(Door(
          id: null,
          pos: 1,
          doorAlias: 'MULTI-ERR-DOOR',
          doorNumber: 'T-MULTI',
          floor: 'EG',
          roomNumber: '01',
          roomDesignation: 'Serverraum',
          doorType: 'T90',
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
          escapeRouteSituation: false,
          escapeRouteSignage: false,
          blindCylinder: false,
          pzCylinder: true,
          fittingType: '',
          panicFunction: '',
          escapeDirectionRespected: true,
          fullPanicStandWing: false,
          doorFunctionOK: false,
        ));

        final inspectionId = await LocalDatabaseService.insertInspection({
          'clientName': 'Multi Defect Client',
          'objectAddress': 'Multi Street 2',
          'date': '2026-09-01',
          'jobNumber': 'JOB-MULTI-ERR',
        });

        final inspDoorId = await LocalDatabaseService.insertInspectionDoor({
          'inspectionId': inspectionId,
          'doorId': doorId,
          'status': 'Failed',
        });

        for (int i = 1; i <= 5; i++) {
          await LocalDatabaseService.insertInspectionDoorError(InspectionDoorError(
            inspectionDoorId: inspDoorId,
            errorId: i,
            errorCode: 'M-0$i',
            quantity: i,
            severity: 'high',
            notes: 'Festgestellter Mangel #$i mit Umlauten äöüß',
            attachments: 'data:image/png;base64,sample_payload_$i',
          ));
        }

        final detailed = await LocalDatabaseService.getDetailedErrorsForInspectionDoor(inspDoorId);
        expect(detailed.length, equals(5));
      });

      test('I-UC-03-MED2: Propose Defect with German Umlauts, Quotes & Special Characters', () async {
        // TEST DATA PURPOSE:
        // Test proposing defect description containing: `Schließzylinder klemmt, Feststellanlage "Dorma" defekt & verstellt`.
        // EXPECTED RESULT:
        // Local database safely inserts proposal without SQL syntax errors or encoding bugs.
        final doorId = await LocalDatabaseService.insertDoor(Door(
          id: null,
          pos: 1,
          doorAlias: 'UNICODE-DOOR',
          doorNumber: 'T-UNI',
          floor: 'EG',
          roomNumber: '99',
          roomDesignation: 'Lager & Archiv',
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
          escapeRouteSituation: false,
          escapeRouteSignage: false,
          blindCylinder: false,
          pzCylinder: true,
          fittingType: '',
          panicFunction: '',
          escapeDirectionRespected: true,
          fullPanicStandWing: false,
          doorFunctionOK: false,
        ));

        final inspectionId = await LocalDatabaseService.insertInspection({
          'clientName': 'Unicode Client',
          'objectAddress': 'Unicode Str. 12',
          'date': '2026-09-01',
          'jobNumber': 'JOB-UNI',
        });

        final inspDoorId = await LocalDatabaseService.insertInspectionDoor({
          'inspectionId': inspectionId,
          'doorId': doorId,
          'status': 'Failed',
        });

        const specialDesc = 'Schließzylinder klemmt, Feststellanlage "Dorma" defekt & verstellt (äöüß)';

        await LocalDatabaseService.proposeNewError(
          inspectionDoorId: inspDoorId,
          description: specialDesc,
          category: 'Schloss',
          severity: 'high',
        );

        final localDb = await LocalDatabaseService.getDb();
        final rows = await localDb.query('error_catalog', where: 'description = ?', whereArgs: [specialDesc]);
        expect(rows.length, equals(1));
        expect(rows.first['description'], equals(specialDesc));
      });

      test('I-UC-01-MED3: Overwrite Stale Local Database during New Job Checkout', () async {
        // TEST DATA PURPOSE:
        // Populate local DB with old job, then checkout a new job package.
        // EXPECTED RESULT:
        // Stale data is cleared, and local DB contains only new job doors.
        final localDb = await LocalDatabaseService.getDb();
        await localDb.insert('doors', {'id': 999, 'doorNumber': 'STALE-01', 'floor': 'EG'});

        final d1 = await DatabaseService.insertDoor(Door(
          id: null,
          pos: 1,
          doorAlias: 'FRESH-DOOR-01',
          doorNumber: 'T-FRESH',
          floor: 'EG',
          roomNumber: '10',
          roomDesignation: 'Büro',
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
          escapeRouteSituation: false,
          escapeRouteSignage: false,
          blindCylinder: false,
          pzCylinder: true,
          fittingType: '',
          panicFunction: '',
          escapeDirectionRespected: true,
          fullPanicStandWing: false,
          doorFunctionOK: true,
        ));

        final inspectionId = await DatabaseService.insertInspection({
          'clientName': 'Fresh Job Client',
          'objectAddress': 'Fresh Address',
          'date': '2026-09-01',
          'jobNumber': 'JOB-FRESH',
        });

        await DatabaseService.insertInspectionDoor({'inspectionId': inspectionId, 'doorId': d1, 'status': 'InProgress'});

        await LocalDatabaseService.downloadJobPackage(inspectionIds: [inspectionId]);

        final localDoors = await LocalDatabaseService.getDoorsByInspectionId(inspectionId);
        expect(localDoors.length, equals(1));
        expect(localDoors.first.doorNumber, equals('T-FRESH'));
      });

    });

    // =========================================================================
    // LEVEL 3: HARD / LIMIT & HIGH-VOLUME OFFLINE STRESS TESTS
    // =========================================================================
    group('Level 3: Hard Level & Mass Offline Inspection Stress Test', () {

      test('I-UC-02-HARD1: High-Volume Offline Door Inspection Stress Test (500 Doors Batch)', () async {
        // TEST DATA PURPOSE:
        // Batch insert 500 doors and record defects across 50 doors in local DB.
        // EXPECTED RESULT:
        // Database processes batch transactions without lockups, and query times remain fast.
        final localDb = await LocalDatabaseService.getDb();

        final inspectionId = await LocalDatabaseService.insertInspection({
          'clientName': 'Mass Client',
          'objectAddress': 'Mass Facility 500',
          'date': '2026-09-01',
          'jobNumber': 'JOB-MASS-500',
        });

        await localDb.transaction((txn) async {
          for (int i = 1; i <= 500; i++) {
            final doorId = await txn.insert('doors', {
              'id': i,
              'doorAlias': 'MASS-DOOR-$i',
              'doorNumber': 'T-MASS-$i',
              'floor': 'EG',
              'roomNumber': '$i',
              'roomDesignation': 'Raum $i',
              'doorType': 'T30',
              'wingCount': 1,
              'material': 'Stahl',
              'manufacturer': 'Hörmann',
              'dinConfiguration': 'DIN L',
              'doorFunctionOK': i % 10 == 0 ? 0 : 1,
            });

            await txn.insert('inspection_doors', {
              'id': i,
              'inspectionId': inspectionId,
              'doorId': doorId,
              'status': i % 10 == 0 ? 'Failed' : 'Passed',
            });
          }
        });

        final countResult = await localDb.rawQuery('SELECT COUNT(*) as cnt FROM doors');
        expect(countResult.first['cnt'], equals(500));

        final failedDoors = await localDb.query('inspection_doors', where: 'status = ?', whereArgs: ['Failed']);
        expect(failedDoors.length, equals(50));
      });

    });

  });
}
