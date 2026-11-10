import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/services/craftnote_api_service.dart';
import 'package:wartungstool/services/craftnote_credentials_service.dart';
import 'package:wartungstool/services/craftnote_sync_service.dart';
import 'package:wartungstool/services/app_logger.dart';
import 'package:wartungstool/widgets/app_log_dialog.dart';
import 'package:wartungstool/widgets/craftnote_test_mode_switch.dart';

Door _makeTestDoor({
  int? id,
  int pos = 1,
  String? doorAlias,
  String? provisionalAlias,
  String doorNumber = 'T-01',
  String floor = 'EG',
  String roomNumber = '01',
  String roomDesignation = 'Raum',
  String doorType = 'T30',
  int wingCount = 1,
  String material = 'Stahl',
  String manufacturer = 'Hörmann',
  String dinConfiguration = 'DIN L',
  String closerType = 'TS93',
  String closingSequenceSystem = 'Keine',
  String lockDimensions = 'PZ 72/65',
  bool closerOnHingeSide = true,
  bool closerOnOppositeSide = false,
  bool lintelHeightInsideOver1m = false,
  String? lintelHeightInsideValue,
  bool lintelHeightOutsideOver1m = false,
  String? lintelHeightOutsideValue,
  String escapeDoorControl = 'Nein',
  String accessControl = 'Nein',
  bool escapeRouteSituation = false,
  bool escapeRouteSignage = false,
  bool blindCylinder = false,
  bool pzCylinder = true,
  String fittingType = 'Drücker',
  String panicFunction = 'Nein',
  bool escapeDirectionRespected = false,
  bool fullPanicStandWing = false,
  bool doorFunctionOK = true,
  String approvalNumber = '?',
  String manufacturerNumber = '?',
  String dopNumber = '?',
  String manufactureYear = '2020',
  String? fsaDriveAcceptanceDate,
  String notes = '',
}) {
  return Door(
    id: id,
    pos: pos,
    doorAlias: doorAlias,
    provisionalAlias: provisionalAlias,
    doorNumber: doorNumber,
    floor: floor,
    roomNumber: roomNumber,
    roomDesignation: roomDesignation,
    doorType: doorType,
    wingCount: wingCount,
    material: material,
    manufacturer: manufacturer,
    dinConfiguration: dinConfiguration,
    closerType: closerType,
    closingSequenceSystem: closingSequenceSystem,
    lockDimensions: lockDimensions,
    closerOnHingeSide: closerOnHingeSide,
    closerOnOppositeSide: closerOnOppositeSide,
    lintelHeightInsideOver1m: lintelHeightInsideOver1m,
    lintelHeightInsideValue: lintelHeightInsideValue,
    lintelHeightOutsideOver1m: lintelHeightOutsideOver1m,
    lintelHeightOutsideValue: lintelHeightOutsideValue,
    escapeDoorControl: escapeDoorControl,
    accessControl: accessControl,
    escapeRouteSituation: escapeRouteSituation,
    escapeRouteSignage: escapeRouteSignage,
    blindCylinder: blindCylinder,
    pzCylinder: pzCylinder,
    fittingType: fittingType,
    panicFunction: panicFunction,
    escapeDirectionRespected: escapeDirectionRespected,
    fullPanicStandWing: fullPanicStandWing,
    doorFunctionOK: doorFunctionOK,
    approvalNumber: approvalNumber,
    manufacturerNumber: manufacturerNumber,
    dopNumber: dopNumber,
    manufactureYear: manufactureYear,
    fsaDriveAcceptanceDate: fsaDriveAcceptanceDate,
    notes: notes,
  );
}

void main() {
  // 1. Initialize Flutter Integration Test Binding for native Android device execution
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    CraftnoteCredentialsService.resetToDefaults();
    CraftnoteCredentialsService.setMockMode(true);

    // Reset local database tables on the Android device before each test
    await LocalDatabaseService.closeDb();
    final db = await LocalDatabaseService.getDb();
    await db.delete('inspection_door_errors');
    await db.delete('inspection_doors');
    await db.delete('inspections');
    await db.delete('doors');
    await db.delete('error_catalog');
    await db.delete('craftnote_upload_queue');
  });

  group('Inspector Android Device Integration Test Suite (I-UC-01 to I-UC-12)',
      () {
    // =========================================================================
    // I-UC-01: Checkout & Ingest Job Package with Auto Safety Backup
    // =========================================================================
    testWidgets(
        'I-UC-01 [Android Device]: Checkout Assigned Job Package to Local Tablet DB & Verify Safety Backup',
        (WidgetTester tester) async {
      await DatabaseService.insertErrorCatalog(ErrorCatalog(
        code: 'M-01',
        description: 'Türschließer defekt',
        category: 'Schließer',
        severity: 'high',
        status: 'Approved',
      ));

      final d1 = await DatabaseService.insertDoor(_makeTestDoor(
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
        escapeDoorControl: 'Ja',
        accessControl: 'Nein',
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
        'clientName': 'Android Field Client',
        'objectAddress': 'Device Road 10',
        'date': '2026-08-31',
        'jobNumber': 'JOB-ANDROID-101',
        'orderType': 'Wartung',
      });

      await DatabaseService.insertInspectionDoor(
          {'inspectionId': inspectionId, 'doorId': d1, 'status': 'InProgress'});

      // Download package onto local device database
      await LocalDatabaseService.downloadJobPackage(
          inspectionIds: [inspectionId]);

      // Assert local tablet DB received data
      final localDoors =
          await LocalDatabaseService.getDoorsByInspectionId(inspectionId);
      expect(localDoors.length, equals(1));
      expect(localDoors.first.doorNumber, equals('T-101'));

      // Verify Safety Backup creation
      final backup =
          await LocalDatabaseService.createSafetyBackup(tag: 'test_safety');
      expect(backup, isNotNull);
      expect(await backup!.exists(), isTrue);
    });

    // =========================================================================
    // I-UC-02: Barcode / QR Door Identification & Duplicate Barcode Guard
    // =========================================================================
    testWidgets(
        'I-UC-02 [Android Device]: Barcode Lookup & Duplicate Barcode Detection Guard',
        (WidgetTester tester) async {
      final door1Id = await LocalDatabaseService.insertDoor(_makeTestDoor(
        pos: 1,
        doorAlias: 'BARCODE-DOOR-A',
        doorNumber: 'T-101',
        floor: 'EG',
        roomNumber: '01',
        roomDesignation: 'Eingang',
        doorType: 'T30',
        wingCount: 1,
        material: 'Aluminium',
        manufacturer: 'Schüco',
        dinConfiguration: 'DIN L',
        closerType: 'TS5000',
        doorFunctionOK: true,
      ));

      final door2Id = await LocalDatabaseService.insertDoor(_makeTestDoor(
        pos: 2,
        doorAlias: 'BARCODE-DOOR-B',
        doorNumber: 'T-102',
        floor: 'EG',
        roomNumber: '02',
        roomDesignation: 'Flur',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Hörmann',
        dinConfiguration: 'DIN R',
        closerType: 'TS93',
        doorFunctionOK: true,
      ));

      // 1. Verify resolving door by barcode / alias
      final foundDoor =
          await LocalDatabaseService.findDoorByBarcode('BARCODE-DOOR-A');
      expect(foundDoor, isNotNull);
      expect(foundDoor!.id, equals(door1Id));
      expect(foundDoor.doorNumber, equals('T-101'));

      // 2. Guard: Attempting to assign existing barcode 'BARCODE-DOOR-A' to door 2 must detect duplicate
      final collision = await LocalDatabaseService.findDoorByBarcode(
          'BARCODE-DOOR-A',
          excludeDoorId: door2Id);
      expect(collision, isNotNull);
      expect(collision!.id, equals(door1Id));
      expect(collision.id, isNot(equals(door2Id)));
    });

    // =========================================================================
    // I-UC-03: Door Technical Specifications Audit in Field
    // =========================================================================
    testWidgets(
        'I-UC-03 [Android Device]: Inspect Technical Attributes, Lintel Height & Closer Location',
        (WidgetTester tester) async {
      final doorId = await LocalDatabaseService.insertDoor(_makeTestDoor(
        pos: 1,
        doorAlias: 'SPEC-DOOR-01',
        doorNumber: 'T-SPEC-01',
        floor: '1.OG',
        roomNumber: '110',
        roomDesignation: 'Serverraum',
        doorType: 'T90',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Teckentrup',
        dinConfiguration: 'DIN R',
        closerType: 'TS93',
        closingSequenceSystem: '',
        lockDimensions: '65/72/9',
        closerOnHingeSide: false,
        closerOnOppositeSide: true,
        lintelHeightInsideOver1m: true,
        lintelHeightInsideValue: '125cm',
        escapeDoorControl: 'Nein',
        accessControl: 'Zutrittskontrolle RFID',
        panicFunction: 'Panikfunktion E',
        escapeRouteSituation: true,
        escapeRouteSignage: true,
        doorFunctionOK: true,
      ));

      final fetchedDoor = await LocalDatabaseService.getDoorById(doorId);
      expect(fetchedDoor, isNotNull);
      expect(fetchedDoor!.closerOnOppositeSide, isTrue);
      expect(fetchedDoor.closerOnHingeSide, isFalse);
      expect(fetchedDoor.lintelHeightInsideOver1m, isTrue);
      expect(fetchedDoor.lintelHeightInsideValue, equals('125cm'));
      expect(fetchedDoor.panicFunction, equals('Panikfunktion E'));
    });

    // =========================================================================
    // I-UC-04: Record Defect & Photo Documentation
    // =========================================================================
    testWidgets(
        'I-UC-04 [Android Device]: Record Defect & Photo Attachment During Site Visit',
        (WidgetTester tester) async {
      final localDb = await LocalDatabaseService.getDb();
      await localDb.insert('error_catalog', {
        'errorId': 1,
        'code': 'M-01',
        'description': 'Türschließer undicht',
        'category': 'Schließer',
        'severity': 'high',
        'status': 'Approved',
      });

      final doorId = await LocalDatabaseService.insertDoor(_makeTestDoor(
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
        escapeDoorControl: 'Nein',
        accessControl: 'Nein',
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
        'clientName': 'Device Client',
        'objectAddress': 'Site Address 1',
        'date': '2026-08-31',
        'jobNumber': 'JOB-ANDROID-102',
      });

      final inspDoorId = await LocalDatabaseService.insertInspectionDoor({
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': 'Failed',
        'notes': 'Recorded on physical Android device',
      });

      final mockPhotoBase64 =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

      final defectId = await LocalDatabaseService.insertInspectionDoorError(
          InspectionDoorError(
        inspectionDoorId: inspDoorId,
        errorId: 1,
        errorCode: 'M-01',
        quantity: 1,
        severity: 'high',
        notes: 'Ölaustritt am Ventilkopf',
        attachments: mockPhotoBase64,
      ));

      expect(defectId, isNotNull);
      final errors =
          await LocalDatabaseService.getDetailedErrorsForInspectionDoor(
              inspDoorId);
      expect(errors.length, equals(1));
      expect(errors.first['code'], equals('M-01'));
      expect(errors.first['attachments'], equals(mockPhotoBase64));
    });

    // =========================================================================
    // I-UC-05: Propose Uncatalogued Defect from Device
    // =========================================================================
    testWidgets(
        'I-UC-05 [Android Device]: Propose New Uncatalogued Defect (Pending Proposal)',
        (WidgetTester tester) async {
      final doorId = await LocalDatabaseService.insertDoor(_makeTestDoor(
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
        escapeDoorControl: 'Nein',
        accessControl: 'Nein',
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
        'date': '2026-08-31',
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
      final catalogRows = await localDb.query('error_catalog',
          where: 'description = ?', whereArgs: ['Schlossfalle gebrochen']);
      expect(catalogRows.length, equals(1));
      expect(catalogRows.first['status'], equals('Pending'));
    });

    // =========================================================================
    // I-UC-06: Defect Rectification / Repair Visit Lifecycle (orderType: Reparatur)
    // =========================================================================
    testWidgets(
        'I-UC-06 [Android Device]: Rectify Defect during Repair Visit (orderType: Reparatur)',
        (WidgetTester tester) async {
      final doorId = await LocalDatabaseService.insertDoor(_makeTestDoor(
        pos: 1,
        doorAlias: 'REPAIR-DOOR-01',
        doorNumber: 'T-REP-01',
        floor: 'EG',
        roomNumber: '02',
        roomDesignation: 'Werkstatt',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Hörmann',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        doorFunctionOK: false, // Initially defective
      ));

      final inspectionId = await LocalDatabaseService.insertInspection({
        'clientName': 'Repair Client AG',
        'objectAddress': 'Industrieweg 4',
        'date': '2026-09-02',
        'jobNumber': 'JOB-REP-2026',
        'orderType': 'Reparatur',
        'repairDate': '2026-09-02',
      });

      final inspDoorId = await LocalDatabaseService.insertInspectionDoor({
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': 'Defective',
      });

      final errorId = await LocalDatabaseService.insertInspectionDoorError(
          InspectionDoorError(
        inspectionDoorId: inspDoorId,
        errorId: 1,
        errorCode: 'M-01',
        quantity: 1,
        severity: 'high',
        notes: 'Schließer defekt',
        resolutionStatus: 'Offen',
      ));

      // Technician fixes the closer on site: mark resolutionStatus = 'Behoben'
      final localDb = await LocalDatabaseService.getDb();
      await localDb.update(
        'inspection_door_errors',
        {
          'resolutionStatus': 'Behoben',
          'notes': 'Schließer ausgetauscht und neu justiert.'
        },
        where: 'id = ?',
        whereArgs: [errorId],
      );

      // Update door status to Passed
      await LocalDatabaseService.updateInspectionDoorStatus(
        inspectionId: inspectionId,
        doorId: doorId,
        status: 'Passed',
      );
      await localDb.update('doors', {'doorFunctionOK': 1},
          where: 'id = ?', whereArgs: [doorId]);

      // Verify
      final updatedDoor = await LocalDatabaseService.getDoorById(doorId);
      expect(updatedDoor!.doorFunctionOK, isTrue);

      final updatedErrors =
          await LocalDatabaseService.getDetailedErrorsForInspectionDoor(
              inspDoorId);
      expect(updatedErrors.first['resolutionStatus'], equals('Behoben'));
    });

    // =========================================================================
    // I-UC-07: Unprocessed Doors Warning Guard & Selective Export
    // =========================================================================
    testWidgets(
        'I-UC-07 [Android Device]: Validate Incomplete Doors Guard & Selective Package Export',
        (WidgetTester tester) async {
      final door1 = _makeTestDoor(
        pos: 1,
        doorAlias: 'EXPORT-T1',
        doorNumber: 'T-EXP-01',
        floor: 'EG',
        roomNumber: '01',
        roomDesignation: 'Büro 1',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Hörmann',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        doorFunctionOK: true,
      );
      final door2 = _makeTestDoor(
        pos: 2,
        doorAlias: 'EXPORT-T2',
        doorNumber: 'T-EXP-02',
        floor: 'EG',
        roomNumber: '02',
        roomDesignation: 'Büro 2',
        doorType: 'T30',
        wingCount: 1,
        material: 'Holz',
        manufacturer: 'Prüm',
        dinConfiguration: 'DIN R',
        closerType: 'TS93',
        doorFunctionOK: false,
      );

      final d1Id = await LocalDatabaseService.insertDoor(door1);
      final d2Id = await LocalDatabaseService.insertDoor(door2);

      final inspectionId = await LocalDatabaseService.insertInspection({
        'clientName': 'Export Guard Client',
        'objectAddress': 'Guard Road 9',
        'date': '2026-09-03',
        'jobNumber': 'JOB-GUARD-07',
      });

      await LocalDatabaseService.insertInspectionDoor(
          {'inspectionId': inspectionId, 'doorId': d1Id, 'status': 'Passed'});
      await LocalDatabaseService.insertInspectionDoor({
        'inspectionId': inspectionId,
        'doorId': d2Id,
        'status': null
      }); // Uninspected

      // 1. Verify detection of unprocessed doors
      final doors = [door1.copyWith(id: d1Id), door2.copyWith(id: d2Id)];
      final statuses = {d1Id: 'Passed'}; // d2Id has no status

      final unprocessed = doors.where((d) {
        final s = statuses[d.id];
        return s == null || s.trim().isEmpty || s == 'Offen';
      }).toList();

      expect(unprocessed.length, equals(1));
      expect(unprocessed.first.doorNumber, equals('T-EXP-02'));

      // 2. Perform selective export of door 1
      final tempDir = await getDatabasesPath();
      final targetExportPath =
          p.join(tempDir, 'inspektion_ergebnis_guard_test.db');

      await LocalDatabaseService.exportSelectiveJobPackage(
          [d1Id], targetExportPath);

      final exportedFile = File(targetExportPath);
      expect(await exportedFile.exists(), isTrue);

      // Verify exported DB contains only door 1
      final exportedDb = await openDatabase(targetExportPath, readOnly: true);
      final exportedDoors = await exportedDb.query('doors');
      expect(exportedDoors.length, equals(1));
      expect(exportedDoors.first['doorNumber'], equals('T-EXP-01'));
      await exportedDb.close();
      await exportedFile.delete();
    });

    // =========================================================================
    // I-UC-08: Inspector Targeted Order Search & Archive Guard
    // =========================================================================
    testWidgets(
        'I-UC-08 [Android Device]: Targeted Order Search (Auftragsnummer) & Archive Guard Enforcement',
        (WidgetTester tester) async {
      CraftnoteCredentialsService.resetToDefaults();
      CraftnoteCredentialsService.setMockMode(true);
      final apiService = CraftnoteApiService();

      // 1. Search an active project by orderNumber: returns active project
      final activeResult = await apiService.findProjectWithArchiveCheck(
        orderNumber: '26-15440-AB',
      );
      expect(activeResult.hasActiveProject, isTrue);
      expect(activeResult.isArchived, isFalse);
      expect(
          activeResult.activeProject!.name, contains('Universitätsklinikum'));

      // 2. Search an archived project: returns archived alert and blocks acquisition
      final archivedResult = await apiService.findProjectWithArchiveCheck(
        orderNumber: '26-15613-AB',
      );
      expect(archivedResult.isArchived, isTrue);
      expect(archivedResult.hasActiveProject, isFalse);
      expect(archivedResult.archivedProject!.name, contains('Archiviert'));
      expect(archivedResult.errorMessage, contains('archiviert'));

      // 3. Verify sync service upload blocks export if project is archived
      final syncService = CraftnoteSyncService(apiService: apiService);
      CraftnoteCredentialsService.setTestMode(false);

      final doorId = await LocalDatabaseService.insertDoor(_makeTestDoor(
        pos: 1,
        doorAlias: 'ARCHIVE-CHECK-DOOR',
        doorNumber: 'T-ARCH-01',
        doorFunctionOK: true,
      ));
      final inspId = await LocalDatabaseService.insertInspection({
        'clientName': 'Archived Client',
        'jobNumber': '26-15613-AB',
        'craftnoteProjectId': archivedResult.archivedProject!.id,
      });
      await LocalDatabaseService.insertInspectionDoor({
        'inspectionId': inspId,
        'doorId': doorId,
        'status': 'Passed',
      });

      final uploadResult = await syncService.completeAndUploadFromLocalDb(
        inspectionId: inspId,
      );
      expect(uploadResult.success, isFalse);
      expect(uploadResult.message, contains('archiviert'));
    });

    // =========================================================================
    // I-UC-09: Inspector Inspection Completion & Direct Cloud Export
    // =========================================================================
    testWidgets(
        'I-UC-09 [Android Device]: Complete Inspection & Upload Result DB (*ergebnis*.db) and Photos',
        (WidgetTester tester) async {
      CraftnoteCredentialsService.resetToDefaults();
      CraftnoteCredentialsService.setMockMode(true);
      CraftnoteCredentialsService.setTestMode(true);
      final syncService =
          CraftnoteSyncService(apiService: CraftnoteApiService());

      final localDb = await LocalDatabaseService.getDb();
      await localDb.insert('error_catalog', {
        'errorId': 1,
        'code': 'M-01',
        'description': 'Türschließer undicht',
        'category': 'Schließer',
        'severity': 'high',
        'status': 'Approved',
      });

      final doorId = await LocalDatabaseService.insertDoor(_makeTestDoor(
        pos: 1,
        doorAlias: 'CLOUD-DOOR-01',
        doorNumber: 'T-01',
        floor: 'EG',
        roomDesignation: 'Eingang',
        doorType: 'T30',
        doorFunctionOK: false,
      ));

      final inspectionId = await LocalDatabaseService.insertInspection({
        'clientName': 'Craftnote Cloud Field Client',
        'objectAddress': 'Ellernreihe 135, Hamburg',
        'date': '2026-11-05',
        'jobNumber': '26-15440-AB',
        'craftnoteProjectId': 'CN-PROJ-MOCK-01',
        'craftnoteSyncStatus': 'downloaded',
      });

      final inspDoorId = await LocalDatabaseService.insertInspectionDoor({
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': 'Defective',
      });

      // Attach defect photo
      const mockPhotoBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      await LocalDatabaseService.insertInspectionDoorError(InspectionDoorError(
        inspectionDoorId: inspDoorId,
        errorId: 1,
        errorCode: 'M-01',
        quantity: 1,
        severity: 'high',
        notes: 'Ölaustritt vor Ort fotografiert',
        attachments: mockPhotoBase64,
      ));

      // Execute complete and upload from local device DB
      final uploadResult = await syncService.completeAndUploadFromLocalDb(
        inspectionId: inspectionId,
      );

      expect(uploadResult.success, isTrue);
      expect(uploadResult.isQueuedOffline, isFalse);
      expect(uploadResult.uploadedDbFileId, isNotNull);
      expect(uploadResult.uploadedPhotos, greaterThanOrEqualTo(1));

      // Verify local inspection record updated to synced
      final updatedInsp =
          await LocalDatabaseService.getInspectionById(inspectionId);
      expect(updatedInsp?['craftnoteSyncStatus'], equals('synced'));
    });

    // =========================================================================
    // I-UC-10: Inspector Offline Queue Enqueueing & Reconnection Retry
    // =========================================================================
    testWidgets(
        'I-UC-10 [Android Device]: Offline Queue Fallback & Automatic Retry on Reconnection',
        (WidgetTester tester) async {
      CraftnoteCredentialsService.resetToDefaults();
      CraftnoteCredentialsService.setMockMode(true);
      CraftnoteCredentialsService.setTestMode(true);
      final syncService =
          CraftnoteSyncService(apiService: CraftnoteApiService());

      final doorId = await LocalDatabaseService.insertDoor(_makeTestDoor(
        pos: 1,
        doorAlias: 'OFFLINE-QUEUE-DOOR',
        doorNumber: 'T-OFF-01',
        floor: 'UG',
        roomDesignation: 'Keller',
        doorFunctionOK: true,
      ));

      final inspectionId = await LocalDatabaseService.insertInspection({
        'clientName': 'Offline Underground Client',
        'objectAddress': 'Kellerweg 1, Hamburg',
        'date': '2026-11-05',
        'jobNumber': '26-15440-AB',
        'craftnoteProjectId': 'CN-PROJ-MOCK-01',
        'craftnoteSyncStatus': 'downloaded',
      });

      await LocalDatabaseService.insertInspectionDoor({
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': 'Passed',
      });

      // 1. Device is offline (no signal in basement)
      syncService.overrideOnlineStatus = false;

      final offlineResult = await syncService.completeAndUploadFromLocalDb(
        inspectionId: inspectionId,
      );

      expect(offlineResult.success, isTrue);
      expect(offlineResult.isQueuedOffline, isTrue);
      expect(offlineResult.queueId, isNotNull);

      // Verify inspection status marked as 'queued'
      final queuedInsp =
          await LocalDatabaseService.getInspectionById(inspectionId);
      expect(queuedInsp?['craftnoteSyncStatus'], equals('queued'));

      // Verify item in craftnote_upload_queue
      final pendingQueue =
          await LocalDatabaseService.getPendingCraftnoteUploads();
      expect(pendingQueue.length, equals(1));
      expect(pendingQueue.first.inspectionId, equals(inspectionId));

      // 2. Device reconnects to network (emerges from basement)
      syncService.overrideOnlineStatus = true;
      final queueReport = await syncService.processPendingUploadQueue();

      expect(queueReport.processed, equals(1));
      expect(queueReport.succeeded, equals(1));
      expect(queueReport.failed, equals(0));

      // Verify queue is now empty and inspection marked as 'synced'
      final emptyQueue =
          await LocalDatabaseService.getPendingCraftnoteUploads();
      expect(emptyQueue, isEmpty);

      final syncedInsp =
          await LocalDatabaseService.getInspectionById(inspectionId);
      expect(syncedInsp?['craftnoteSyncStatus'], equals('synced'));
    });

    // =========================================================================
    // I-UC-11: Inspector AppLogger Diagnostics & In-App Log Viewer
    // =========================================================================
    testWidgets(
        'I-UC-11 [Android Device]: AppLogger Diagnostics & 1-Click Export to Downloads',
        (WidgetTester tester) async {
      await AppLogger.instance.init();
      AppLogger.info('InspectorTest', 'Inspector workflow started on Android device');
      AppLogger.warn('InspectorTest', 'Simulated door inspection warning note');

      // Allow async file write to flush
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final logs = await AppLogger.instance.readAllLogs();
      expect(logs, contains('Inspector workflow started on Android device'));
      expect(logs, contains('[WARN]'));
      expect(AppLogger.instance.recentEntries.any((e) => e.tag == 'InspectorTest'), isTrue);

      // Render In-App Log Viewer dialog in test harness
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppLogDialog(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Anwendungsprotokoll (Log-Datei)'), findsOneWidget);
      expect(find.text('In Downloads ablegen'), findsOneWidget);
      expect(find.text('Speichern unter...'), findsOneWidget);
      expect(find.text('Protokoll leeren'), findsOneWidget);
    });

    // =========================================================================
    // I-UC-12: Inspector Craftnote Test Mode Switch & Redirection Protection
    // =========================================================================
    testWidgets(
        'I-UC-12 [Android Device]: Craftnote Test Mode Switch & Safe Sandbox Guard',
        (WidgetTester tester) async {
      CraftnoteCredentialsService.resetToDefaults();
      expect(CraftnoteCredentialsService.isTestMode, isTrue);

      bool switchTriggered = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CraftnoteTestModeSwitch(
              compact: true,
              onChanged: (val) => switchTriggered = val,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CraftnoteTestModeSwitch), findsOneWidget);
      expect(find.textContaining('Test'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(switchTriggered, isFalse);
      expect(CraftnoteCredentialsService.isTestMode, isFalse);
      expect(find.textContaining('Live'), findsOneWidget);

      // Return to safe Test Mode
      CraftnoteCredentialsService.setTestMode(true);
    });
  });
}
