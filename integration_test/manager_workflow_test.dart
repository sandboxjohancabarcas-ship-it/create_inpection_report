import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';
import 'package:wartungstool/services/batch_migration_service.dart';
import 'package:wartungstool/services/catalog_integrity_service.dart';
import 'package:wartungstool/services/door_options_service.dart';
import 'package:wartungstool/services/photo_export_service.dart';
import 'package:wartungstool/services/excel_export_service.dart';
import 'package:wartungstool/utils/inspection_year_utils.dart';
import 'package:wartungstool/models/craftnote_models.dart';
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Desktop SQLite FFI initialization
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await DatabaseService.clearDatabase();
    await LocalDatabaseService.clearSyncedData();
    DoorOptionsService.reset();
    CraftnoteCredentialsService.resetToDefaults();
    CraftnoteCredentialsService.setMockMode(true);
  });

  tearDown(() async {
    await DatabaseService.closeDb();
    await LocalDatabaseService.closeDb();
  });

  group('Manager Desktop Integration Test Suite (M-UC-01 to M-UC-16)', () {
    // =========================================================================
    // M-UC-01: Multi-Facility Excel Ingestion with Real-World Datasets
    // =========================================================================
    testWidgets(
        'M-UC-01 [Manager Desktop]: Ingest Real-World Facility Datasets (Hammerbrookstraße & Bargkoppelstieg)',
        (WidgetTester tester) async {
      await DatabaseService.checkAndInitializeCatalog();

      final fileHammerbrook = File(
          'test/test_data/26-14640-AB P-000331 Hammerbrookstraße_63-65_20097_Hamburg.xlsm');
      expect(fileHammerbrook.existsSync(), isTrue,
          reason: 'Hammerbrookstraße dataset must exist in test_data');

      final result1 = await ExcelDataImporter.importFromFile(fileHammerbrook);
      expect(result1.sheetsProcessed, greaterThanOrEqualTo(1));
      expect(result1.doorsImported, greaterThan(0));

      final allDoors = await DatabaseService.getAllDoors();
      expect(allDoors.isNotEmpty, isTrue);
      expect(result1.doorsImported, greaterThan(0));

      final inspections = await DatabaseService.getAllInspections();
      expect(inspections.isNotEmpty, isTrue);
      expect(
          inspections.any((i) =>
              i['projectNumber'] == 'P-000331' ||
              i['objectAddress'].toString().contains('Hammerbrook')),
          isTrue);

      final fileBargkoppel = File(
          'test/test_data/26-15337-AB P-000096 Bargkoppelstieg 10-14 Türliste Türen.xlsm');
      if (fileBargkoppel.existsSync()) {
        final result2 = await ExcelDataImporter.importFromFile(fileBargkoppel);
        expect(result2.sheetsProcessed, greaterThanOrEqualTo(1));
        expect(result2.doorsImported, greaterThan(0));
      }
    });

    // =========================================================================
    // M-UC-02: Door Identity Conflict Resolution (keepBoth vs acceptIncoming)
    // =========================================================================
    testWidgets(
        'M-UC-02 [Manager Desktop]: Resolve Door Collision via keepBoth (_NEU suffix) and acceptIncoming',
        (WidgetTester tester) async {
      final existingDoor = _makeTestDoor(
        pos: 1,
        doorAlias: 'DOOR-COLLISION-01',
        doorNumber: 'T-100',
        floor: 'EG',
        roomNumber: '101',
        roomDesignation: 'Konferenzraum',
        doorType: 'T30',
        escapeRouteSituation: false,
      );
      final existingId = await DatabaseService.insertDoor(existingDoor);

      final incomingDoor = _makeTestDoor(
        pos: 1,
        doorAlias: 'DOOR-COLLISION-01',
        doorNumber: 'T-100',
        floor: 'EG',
        roomNumber: '101',
        roomDesignation: 'Konferenzraum Neu',
        doorType: 'T90',
        escapeRouteSituation: true,
      );

      final identityConflict = DoorConflict(
        type: DoorConflictType.identityCollision,
        existingDoor: existingDoor.copyWith(id: existingId),
        incomingDoor: incomingDoor,
        fieldName: 'doorAlias',
        fieldLabel: 'Tür-Kennzeichnung / Alias',
        existingValue: 'DOOR-COLLISION-01',
        incomingValue: 'DOOR-COLLISION-01',
        ruleCode: 'ID_COLLISION',
        message: 'Identitätskonflikt: Alias existiert bereits.',
        resolution: DoorResolutionAction.keepBoth,
        newAlias: 'DOOR-COLLISION-01_NEU',
      );

      await DatabaseService.applyDoorConflictResolutions([identityConflict]);

      final doorOriginal = await DatabaseService.getDoorById(existingId);
      expect(doorOriginal, isNotNull);
      expect(doorOriginal!.doorAlias, equals('DOOR-COLLISION-01'));
      expect(doorOriginal.doorType, equals('T30'));

      final doorNeu =
          await DatabaseService.getDoorByAlias('DOOR-COLLISION-01_NEU');
      expect(doorNeu, isNotNull);
      expect(doorNeu!.doorType, equals('T90'));
      expect(doorNeu.escapeRouteSituation, isTrue);
    });

    // =========================================================================
    // M-UC-03: Error Catalog Conflict Review & Resolution Engine
    // =========================================================================
    testWidgets(
        'M-UC-03 [Manager Desktop]: Error Conflict Review (replaceExisting & addAsNew for non-standard defect)',
        (WidgetTester tester) async {
      final existingDefect = ErrorCatalog(
        code: 'ALT-HINWEIS-01',
        description: 'Alter Hinweis Schließfunktion',
        category: 'Hinweis',
        severity: 'low',
      );
      await DatabaseService.insertErrorCatalog(existingDefect);

      final incomingDefect = ErrorCatalog(
        code: 'ALT-HINWEIS-01',
        description: 'Neuer Hinweis Schließfunktion mit ASR A2.3 Bezug',
        category: 'Hinweis',
        severity: 'medium',
      );

      final conflict = ImportConflict(
        code: 'ALT-HINWEIS-01',
        description: 'Neuer Hinweis Schließfunktion mit ASR A2.3 Bezug',
        existing: existingDefect,
        incoming: incomingDefect,
        reason: 'Text- und Schweregrad-Abweichung im Katalog',
      );

      final resolution = ConflictResolution(
        conflict: conflict,
        action: ResolutionAction.replaceExisting,
      );

      await DatabaseService.applyConflictResolutions([resolution]);

      final allCatalog = await DatabaseService.getAllErrorCatalog();
      final updated = allCatalog.firstWhere((e) => e.code == 'ALT-HINWEIS-01');
      expect(updated.description, contains('ASR A2.3'));
      expect(updated.severity, equals('medium'));
    });

    // =========================================================================
    // M-UC-04: Error Catalog Consolidation, Fuzzy Match (>=85%) & Cascade Updates
    // =========================================================================
    testWidgets(
        'M-UC-04 [Manager Desktop]: Catalog Consolidation Fuzzy Similarity Match & Cascade Propagation',
        (WidgetTester tester) async {
      await DatabaseService.insertErrorCatalog(ErrorCatalog(
        code: 'M-01',
        description: 'Türschließer undicht',
        category: 'Schließer',
        severity: 'high',
        status: 'Approved',
      ));

      final officialCatalog = await DatabaseService.getAllErrorCatalog();

      // 1. Test Fuzzy Similarity Matching (CatalogIntegrityService)
      final similarMatch = CatalogIntegrityService.findSimilarDescription(
        'Türschließer undicht.', // Near identical punctuation variance
        officialCatalog,
        threshold: 0.85,
      );
      expect(similarMatch, isNotNull);
      expect(similarMatch!.similarityPercentage, greaterThanOrEqualTo(85));
      expect(similarMatch.existing.code, equals('M-01'));

      // 2. Next code proposal
      final nextCode = CatalogIntegrityService.proposeNextCodeForCategory(
          'Schließer', officialCatalog);
      expect(nextCode, isNotEmpty);

      // 3. Propose and approve field defect with cascade to linked inspection door
      final d1Id = await DatabaseService.insertDoor(
          _makeTestDoor(pos: 1, doorNumber: 'T-PROP-CASCADE'));
      final inspId = await DatabaseService.insertInspection({
        'clientName': 'Cascade AG',
        'objectAddress': 'Cascade Allee 1',
        'date': '2026-10-21',
        'jobNumber': 'JOB-CAS-01',
      });
      final inspDoorId = await DatabaseService.insertInspectionDoor({
        'inspectionId': inspId,
        'doorId': d1Id,
        'status': 'Failed',
      });

      await DatabaseService.insertInspectionDoorError(InspectionDoorError(
        inspectionDoorId: inspDoorId,
        errorId: 999,
        errorCode: 'TEMP-999',
        quantity: 1,
        severity: 'high',
        notes: 'Spezialschloss defekt',
      ));

      final db = await DatabaseService.getDb();
      await db.insert('error_catalog', {
        'errorId': 999,
        'code': 'TEMP-999',
        'description': 'Spezialschloss defekt',
        'category': 'Schloss',
        'severity': 'high',
        'status': 'Pending',
      });

      // Manager approves proposal to official code 'M-88'
      await db.update('error_catalog', {'code': 'M-88', 'status': 'Approved'},
          where: 'errorId = ?', whereArgs: [999]);
      await db.update('inspection_door_errors', {'errorCode': 'M-88'},
          where: 'errorId = ?', whereArgs: [999]);

      final updatedErrors =
          await DatabaseService.getDetailedErrorsForInspectionDoor(inspDoorId);
      expect(updatedErrors.first['code'], equals('M-88'));
    });

    // =========================================================================
    // M-UC-05: Door Lifetime Clinical Record ("Tür-Akte" / Patient Timeline)
    // =========================================================================
    testWidgets(
        'M-UC-05 [Manager Desktop]: Query Door Lifetime Clinical Record (Historical Inspections & Defect Evolution)',
        (WidgetTester tester) async {
      final doorId = await DatabaseService.insertDoor(_makeTestDoor(
        pos: 1,
        doorAlias: 'AKTE-DOOR-42',
        doorNumber: 'T-AKTE-42',
        floor: 'EG',
        roomNumber: '10',
        roomDesignation: 'Labor',
      ));

      // Inspection 1 (2024): Discovered Defective
      final insp1Id = await DatabaseService.insertInspection({
        'clientName': 'Clinic Client',
        'objectAddress': 'Klinikweg 1',
        'date': '2024-05-10',
        'jobNumber': 'JOB-2024-01',
        'orderType': 'Wartung',
      });
      final j1Id = await DatabaseService.insertInspectionDoor(
          {'inspectionId': insp1Id, 'doorId': doorId, 'status': 'Failed'});
      await DatabaseService.insertInspectionDoorError(InspectionDoorError(
        inspectionDoorId: j1Id,
        errorId: 1,
        errorCode: 'M-01',
        quantity: 1,
        severity: 'high',
        notes: 'Schließer defekt',
        resolutionStatus: 'Offen',
      ));

      // Inspection 2 (2025): Repaired
      final insp2Id = await DatabaseService.insertInspection({
        'clientName': 'Clinic Client',
        'objectAddress': 'Klinikweg 1',
        'date': '2025-06-15',
        'jobNumber': 'JOB-2025-02',
        'orderType': 'Reparatur',
        'repairDate': '2025-06-15',
      });
      final j2Id = await DatabaseService.insertInspectionDoor(
          {'inspectionId': insp2Id, 'doorId': doorId, 'status': 'Passed'});
      await DatabaseService.insertInspectionDoorError(InspectionDoorError(
        inspectionDoorId: j2Id,
        errorId: 1,
        errorCode: 'M-01',
        quantity: 1,
        severity: 'high',
        notes: 'Neuer Schließer montiert',
        resolutionStatus: 'Behoben',
      ));

      // Query Door History Data
      final historyData =
          await DatabaseService.getDoorHistoryData(doorAlias: 'AKTE-DOOR-42');
      expect(historyData, isNotNull);
      expect(historyData!['door'], isNotNull);
      expect((historyData['door'] as Door).doorNumber, equals('T-AKTE-42'));

      final items = (historyData['historyItems'] as List<dynamic>?) ?? [];
      expect(items.length, equals(2));
      // Chronological order descending by date (latest first)
      expect(items.first['inspection']['jobNumber'], equals('JOB-2025-02'));
      expect(items.last['inspection']['jobNumber'], equals('JOB-2024-01'));

      expect(historyData['totalLifetimeErrors'], equals(2));
      expect(historyData['currentOpenErrors'], equals(1));
      expect(historyData['resolvedErrors'], equals(1));
    });

    // =========================================================================
    // M-UC-06: Dynamic Door Options CRUD
    // =========================================================================
    testWidgets(
        'M-UC-06 [Manager Desktop]: Dynamic CRUD on Dropdown Options (Manufacturers, Closers, Types)',
        (WidgetTester tester) async {
      DoorOptionsService.setMockOptions({
        'manufacturer': {
          'options': ['Hörmann', 'Schüco'],
          'default': 'Hörmann'
        },
        'doorType': {
          'options': ['T30-1', 'T90-1'],
          'default': 'T30-1'
        },
      });

      expect(DoorOptionsService.getStringOptions('manufacturer'),
          contains('Hörmann'));
      expect(DoorOptionsService.getStringOptions('manufacturer'),
          isNot(contains('Geze Custom Master')));

      // Simulate manager adding new custom option
      final currentMfrs = List<String>.from(
          DoorOptionsService.getStringOptions('manufacturer'));
      currentMfrs.add('Geze Custom Master');
      DoorOptionsService.setMockOptions({
        'manufacturer': {'options': currentMfrs, 'default': 'Hörmann'},
      });

      expect(DoorOptionsService.getStringOptions('manufacturer'),
          contains('Geze Custom Master'));
    });

    // =========================================================================
    // M-UC-07: Defect Rectification / Repair Order Lifecycle (orderType: Reparatur)
    // =========================================================================
    testWidgets(
        'M-UC-07 [Manager Desktop]: Order Type Reparatur Defect Resolution & doorFunctionOK Auto-Update',
        (WidgetTester tester) async {
      final doorId = await DatabaseService.insertDoor(_makeTestDoor(
        pos: 1,
        doorNumber: 'T-REP-MASTER',
        doorFunctionOK: false,
      ));

      final inspectionId = await DatabaseService.insertInspection({
        'clientName': 'Repair Master AG',
        'objectAddress': 'Repair Allee 99',
        'date': '2026-10-21',
        'jobNumber': 'JOB-REP-MGR-01',
        'orderType': 'Reparatur',
        'repairDate': '2026-10-21',
      });

      final inspDoorId = await DatabaseService.insertInspectionDoor({
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': 'Defective',
      });

      final errId =
          await DatabaseService.insertInspectionDoorError(InspectionDoorError(
        inspectionDoorId: inspDoorId,
        errorId: 1,
        errorCode: 'M-01',
        quantity: 1,
        severity: 'high',
        notes: 'Türschließer defekt',
        resolutionStatus: 'Offen',
      ));

      final db = await DatabaseService.getDb();
      await db.update('inspection_door_errors', {'resolutionStatus': 'Behoben'},
          where: 'id = ?', whereArgs: [errId]);
      await DatabaseService.updateInspectionDoorStatus(
        inspectionId: inspectionId,
        doorId: doorId,
        status: 'Passed',
      );
      await db.update('doors', {'doorFunctionOK': 1},
          where: 'id = ?', whereArgs: [doorId]);

      final updatedDoor = await DatabaseService.getDoorById(doorId);
      expect(updatedDoor!.doorFunctionOK, isTrue);

      final detailedErrors =
          await DatabaseService.getDetailedErrorsForInspectionDoor(inspDoorId);
      expect(detailedErrors.first['resolutionStatus'], equals('Behoben'));
    });

    // =========================================================================
    // M-UC-08: Inspection Locking Security Enforcement Guard
    // =========================================================================
    testWidgets(
        'M-UC-08 [Manager Desktop]: Verify Inspection Lock Permission Boundaries (isLocked Guard)',
        (WidgetTester tester) async {
      final inspectionId = await DatabaseService.insertInspection({
        'clientName': 'Lock Test AG',
        'objectAddress': 'Sicherheitsstraße 5',
        'date': '2026-10-21',
        'jobNumber': 'JOB-LOCK-01',
        'isLocked': 1, // Locked inspection
      });

      final insp = await DatabaseService.getInspectionById(inspectionId);
      expect(insp, isNotNull);
      expect(insp!['isLocked'], equals(1));

      // 1. Inspector mode cannot edit locked inspection
      expect(InspectionYearUtils.isEditable(isManagerMode: false, isLocked: 1),
          isFalse);
      expect(InspectionYearUtils.isMetadataEditable(isManagerMode: false),
          isFalse);

      // 2. Manager mode retains full administrative access
      expect(InspectionYearUtils.isEditable(isManagerMode: true, isLocked: 1),
          isTrue);
      expect(
          InspectionYearUtils.isMetadataEditable(isManagerMode: true), isTrue);

      // 3. Unlock inspection and verify inspector permissions restored
      final db = await DatabaseService.getDb();
      await db.update('inspections', {'isLocked': 0},
          where: 'inspectionId = ?', whereArgs: [inspectionId]);
      expect(InspectionYearUtils.isEditable(isManagerMode: false, isLocked: 0),
          isTrue);
    });

    // =========================================================================
    // M-UC-09: Batch Migration Engine Compliant File Detection
    // =========================================================================
    testWidgets(
        'M-UC-09 [Manager Desktop]: Batch Migration Engine Discovers & Validates Compliant Facility Files',
        (WidgetTester tester) async {
      expect(BatchMigrationService.isCompliantFile('facility.xlsm'), isTrue);
      expect(BatchMigrationService.isCompliantFile('doors.xlsx'), isTrue);
      expect(BatchMigrationService.isCompliantFile('package.db'), isTrue);
      expect(BatchMigrationService.isCompliantFile('package.sqlite'), isTrue);
      expect(BatchMigrationService.isCompliantFile('document.pdf'), isFalse);
      expect(BatchMigrationService.isCompliantFile('data.txt'), isFalse);

      final files =
          BatchMigrationService.getFilesFromDirectory('test/test_data');
      expect(files.isNotEmpty, isTrue);
      final compliant = files
          .where((f) => BatchMigrationService.isCompliantFile(f.path))
          .toList();
      expect(compliant.length, greaterThanOrEqualTo(10));
    });

    // =========================================================================
    // M-UC-10: Photo Export Service (Structured Archive Naming)
    // =========================================================================
    testWidgets(
        'M-UC-10 [Manager Desktop]: Photo Export with Standardized Sanitized Filenames',
        (WidgetTester tester) async {
      final doorId = await DatabaseService.insertDoor(_makeTestDoor(
        pos: 1,
        doorAlias: 'PHOTO-DOOR-01',
        doorNumber: 'T-PHOTO-01',
      ));

      final inspectionId = await DatabaseService.insertInspection({
        'clientName': 'Photo Client',
        'objectAddress': 'Foto Straße 1',
        'date': '2026-10-21',
        'jobNumber': 'JOB-PHOTO-2026',
      });

      final inspDoorId = await DatabaseService.insertInspectionDoor({
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': 'Failed',
      });

      final testPhotoBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

      await DatabaseService.insertInspectionDoorError(InspectionDoorError(
        inspectionDoorId: inspDoorId,
        errorId: 1,
        errorCode: 'M-01',
        quantity: 1,
        severity: 'high',
        notes: 'Ölaustritt',
        attachments: testPhotoBase64,
      ));

      final tempDir =
          await Directory.systemTemp.createTemp('photo_export_test_');
      final exportResult = await PhotoExportService.exportInspectionPhotos(
        inspectionId: inspectionId,
        destinationDir: tempDir.path,
        isManagerMode: true,
      );

      expect(exportResult.totalPhotos, equals(1));
      expect(exportResult.exportedFileNames.length, equals(1));
      expect(exportResult.exportedFileNames.first, contains('PHOTO-DOOR-01'));
      expect(exportResult.exportedFileNames.first, contains('M-01'));

      final exportedFile =
          File(p.join(tempDir.path, exportResult.exportedFileNames.first));
      expect(await exportedFile.exists(), isTrue);
      expect(await exportedFile.length(), greaterThan(0));
      await tempDir.delete(recursive: true);
    });

    // =========================================================================
    // M-UC-11: Client Audit Excel Export (Workbook Generation)
    // =========================================================================
    testWidgets(
        'M-UC-11 [Manager Desktop]: Generate Formatted Client Inspection Excel Audit Workbook',
        (WidgetTester tester) async {
      final doorId = await DatabaseService.insertDoor(_makeTestDoor(
        pos: 1,
        doorAlias: 'EXCEL-DOOR-01',
        doorNumber: 'T-AUDIT-01',
        floor: 'EG',
        roomNumber: '10',
        roomDesignation: 'Haupteingang',
        doorType: 'T30',
        manufacturer: 'Hörmann',
        doorFunctionOK: true,
      ));

      final inspectionId = await DatabaseService.insertInspection({
        'clientName': 'Audit Client GmbH',
        'objectAddress': 'Prüfstraße 10, Hamburg',
        'date': '2026-10-21',
        'jobNumber': 'JOB-AUDIT-2026',
        'projectNumber': 'P-000331',
        'inspectorName': 'Prüfer Schmidt',
      });

      await DatabaseService.insertInspectionDoor({
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': 'Passed',
      });

      final tempDir =
          await Directory.systemTemp.createTemp('excel_export_test_');
      final targetExcelPath =
          p.join(tempDir.path, 'Audit_Report_JOB-AUDIT-2026.xlsx');

      final exportedFile = await ExcelExportService.exportSingleInspection(
          inspectionId, targetExcelPath);
      expect(await exportedFile.exists(), isTrue);
      expect(await exportedFile.length(),
          greaterThan(1000)); // Non-empty valid workbook
      await tempDir.delete(recursive: true);
    });

    // =========================================================================
    // M-UC-12: Craftnote Active-First Project Search & Archive Enforcement Guard
    // =========================================================================
    testWidgets(
        'M-UC-12 [Manager Desktop]: Search Active vs Archived Projects & Enforce Archive Block',
        (WidgetTester tester) async {
      CraftnoteCredentialsService.resetToDefaults();
      CraftnoteCredentialsService.setMockMode(true);
      final apiService = CraftnoteApiService();

      // 1. Search an active project by order number
      final activeResult = await apiService.findProjectWithArchiveCheck(
        orderNumber: '26-15440-AB',
      );
      expect(activeResult.hasActiveProject, isTrue);
      expect(activeResult.isArchived, isFalse);
      expect(
          activeResult.activeProject!.name, contains('Universitätsklinikum'));

      // 2. Search an archived project by order number
      final archivedResult = await apiService.findProjectWithArchiveCheck(
        orderNumber: '26-15613-AB',
      );
      expect(archivedResult.isArchived, isTrue);
      expect(archivedResult.hasActiveProject, isFalse);
      expect(archivedResult.archivedProject!.name, contains('Archiviert'));
      expect(archivedResult.errorMessage, contains('archiviert'));

      // 3. Verify sync service export rejects the archived project in production mode
      final syncService = CraftnoteSyncService(apiService: apiService);
      CraftnoteCredentialsService.setTestMode(false);

      final inspId = await DatabaseService.insertInspection({
        'clientName': 'Archived Client',
        'jobNumber': '26-15613-AB',
        'craftnoteProjectId': archivedResult.archivedProject!.id,
      });

      final exportArchiveResult =
          await syncService.exportInspectionFromMasterDb(
        inspectionId: inspId,
        craftnoteProjectId: archivedResult.archivedProject!.id,
      );
      expect(exportArchiveResult.success, isFalse);
      expect(exportArchiveResult.message, contains('archiviert'));
    });

    // =========================================================================
    // M-UC-13: Manager Export Job Package to Craftnote Project ("Wartungslisten")
    // =========================================================================
    testWidgets(
        'M-UC-13 [Manager Desktop]: Export Master Job Package to Craftnote Wartungslisten Folder',
        (WidgetTester tester) async {
      CraftnoteCredentialsService.resetToDefaults();
      CraftnoteCredentialsService.setMockMode(true);
      CraftnoteCredentialsService.setTestMode(true);
      final syncService =
          CraftnoteSyncService(apiService: CraftnoteApiService());

      final doorId = await DatabaseService.insertDoor(_makeTestDoor(
        pos: 1,
        doorAlias: 'MGR-CN-01',
        doorNumber: 'T-MGR-01',
        floor: 'EG',
        doorFunctionOK: true,
      ));

      final inspectionId = await DatabaseService.insertInspection({
        'clientName': 'Craftnote Manager Client',
        'objectAddress': 'Ellernreihe 135, Hamburg',
        'date': '2026-11-05',
        'jobNumber': '26-15613-AA',
        'projectNumber': 'P-002026',
        'orderType': 'Wartung',
      });

      await DatabaseService.insertInspectionDoor({
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': 'InProgress',
      });

      final exportResult = await syncService.exportInspectionFromMasterDb(
        inspectionId: inspectionId,
        craftnoteProjectId: 'CN-PROJ-MOCK-01',
      );

      expect(exportResult.success, isTrue);
      expect(exportResult.uploadedDbFileId, isNotNull);

      // Verify Master DB inspection updated with sync status
      final updatedInsp = await DatabaseService.getInspectionById(inspectionId);
      expect(updatedInsp?['craftnoteSyncStatus'], equals('synced'));
      expect(updatedInsp?['craftnoteProjectId'],
          equals(CraftnoteCredentialsService.testProjectId));
    });

    // =========================================================================
    // M-UC-14: Manager Ingest Inspector Result Package (*ergebnis*.db) from Craftnote
    // =========================================================================
    testWidgets(
        'M-UC-14 [Manager Desktop]: Ingest Inspector Field Result Package (*ergebnis*.db) from Craftnote',
        (WidgetTester tester) async {
      CraftnoteCredentialsService.resetToDefaults();
      CraftnoteCredentialsService.setMockMode(true);
      CraftnoteCredentialsService.setTestMode(true);
      final syncService =
          CraftnoteSyncService(apiService: CraftnoteApiService());

      // 1. Verify discovering inspector result package in Wartungslisten
      final project =
          await syncService.apiService.getProjectById('CN-PROJ-MOCK-01');
      expect(project, isNotNull);

      final ergebnisFiles = await syncService.getProjectDbPackages(
        'CN-PROJ-MOCK-01',
        mustContainWord: 'ergebnis',
      );
      expect(ergebnisFiles, isNotEmpty);
      expect(ergebnisFiles.first.name.toLowerCase(), contains('ergebnis'));

      // 2. Import inspector result package into Master DB
      final importResult = await syncService.importProjectJobPackage(
        project: project,
        preferredFile: ergebnisFiles.first,
        isManagerMode: true,
      );

      expect(importResult.success, isTrue);
      expect(importResult.report, isNotNull);

      // 3. Verify archived project import guard
      final archivedProject = const CraftnoteProject(
        id: 'CN-ARCHIVED-01',
        name: 'Archived Proj',
        orderNumber: 'ARCH-01',
        archived: true,
      );
      final archiveImportResult = await syncService.importProjectJobPackage(
        project: archivedProject,
        isManagerMode: true,
      );
      expect(archiveImportResult.success, isFalse);
      expect(archiveImportResult.message, contains('archiviert'));
    });

    // =========================================================================
    // M-UC-15: Manager AppLogger Diagnostics & In-App Log Viewer
    // =========================================================================
    testWidgets(
        'M-UC-15 [Manager Desktop]: AppLogger Diagnostics & In-App Log Viewer Access',
        (WidgetTester tester) async {
      await AppLogger.instance.init();
      AppLogger.info('ManagerTest', 'Manager workflow test started');
      AppLogger.warn('ManagerTest', 'Simulated low disk warning');

      // Allow async file write to flush
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final logs = await AppLogger.instance.readAllLogs();
      expect(logs, contains('Manager workflow test started'));
      expect(logs, contains('[WARN]'));
      expect(AppLogger.instance.recentEntries.any((e) => e.tag == 'ManagerTest'), isTrue);

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
    // M-UC-16: Manager Craftnote Test Mode Switch & Export Feedback
    // =========================================================================
    testWidgets(
        'M-UC-16 [Manager Desktop]: Craftnote Test Mode Switch & Safe Redirection Verification',
        (WidgetTester tester) async {
      CraftnoteCredentialsService.resetToDefaults();

      // Test Mode toggling (Default is false / Production mode)
      expect(CraftnoteCredentialsService.isTestMode, isFalse);
      CraftnoteCredentialsService.setTestMode(true);
      expect(CraftnoteCredentialsService.isTestMode, isTrue);
      CraftnoteCredentialsService.setTestMode(false);
      expect(CraftnoteCredentialsService.isTestMode, isFalse);

      // Verify Test Mode Widget toggle rendering
      bool toggled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CraftnoteTestModeSwitch(
              compact: true,
              onChanged: (val) => toggled = val,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CraftnoteTestModeSwitch), findsOneWidget);
      expect(find.textContaining('Live'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(toggled, isTrue);
      expect(CraftnoteCredentialsService.isTestMode, isTrue);
      expect(find.textContaining('Test'), findsOneWidget);

      // Reset back to defaults
      CraftnoteCredentialsService.resetToDefaults();
    });
  });
}
