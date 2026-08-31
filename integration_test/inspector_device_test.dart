import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';

void main() {
  // 1. Initialize Flutter Integration Test Binding for native Android device execution
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Reset local database tables on the Android device before each test
    await LocalDatabaseService.closeDb();
    final db = await LocalDatabaseService.getDb();
    await db.delete('inspection_door_errors');
    await db.delete('inspection_doors');
    await db.delete('inspections');
    await db.delete('doors');
    await db.delete('error_catalog');
  });

  group('Inspector Android Device Integration Test Suite (I-UC-01 to I-UC-04)', () {

    // =========================================================================
    // I-UC-01: Checkout & Download Job Package on Device
    // =========================================================================
    testWidgets('I-UC-01 [Android Device]: Checkout Assigned Job Package to Local Tablet DB', (WidgetTester tester) async {
      // Seed data into Master DB on device
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
        lintelHeightUnder1m: false,
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
        'clientName': 'Android Field Client',
        'objectAddress': 'Device Road 10',
        'date': '2026-08-31',
        'jobNumber': 'JOB-ANDROID-101',
      });

      await DatabaseService.insertInspectionDoor({'inspectionId': inspectionId, 'doorId': d1, 'status': 'InProgress'});

      // Download package onto local device database
      await LocalDatabaseService.downloadJobPackage(inspectionIds: [inspectionId]);

      // Assert local tablet DB received data
      final localDoors = await LocalDatabaseService.getDoorsByInspectionId(inspectionId);
      expect(localDoors.length, equals(1));
      expect(localDoors.first.doorNumber, equals('T-101'));
    });

    // =========================================================================
    // I-UC-02: Record Defect & Photo Documentation
    // =========================================================================
    testWidgets('I-UC-02 [Android Device]: Record Defect & Photo Attachment During Site Visit', (WidgetTester tester) async {
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
        lintelHeightUnder1m: false,
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

      final mockPhotoBase64 = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

      final defectId = await LocalDatabaseService.insertInspectionDoorError(InspectionDoorError(
        inspectionDoorId: inspDoorId,
        errorId: 1,
        errorCode: 'M-01',
        quantity: 1,
        severity: 'high',
        notes: 'Ölaustritt am Ventilkopf',
        attachments: mockPhotoBase64,
      ));

      expect(defectId, isNotNull);
      final errors = await LocalDatabaseService.getDetailedErrorsForInspectionDoor(inspDoorId);
      expect(errors.length, equals(1));
      expect(errors.first['code'], equals('M-01'));
      expect(errors.first['attachments'], equals(mockPhotoBase64));
    });

    // =========================================================================
    // I-UC-03: Propose Uncatalogued Defect from Device
    // =========================================================================
    testWidgets('I-UC-03 [Android Device]: Propose New Uncatalogued Defect (Pending Proposal)', (WidgetTester tester) async {
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
        lintelHeightUnder1m: false,
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
      final catalogRows = await localDb.query('error_catalog', where: 'description = ?', whereArgs: ['Schlossfalle gebrochen']);
      expect(catalogRows.length, equals(1));
      expect(catalogRows.first['status'], equals('Pending'));
    });

    // =========================================================================
    // I-UC-04: Submit Field Inspection Package
    // =========================================================================
    testWidgets('I-UC-04 [Android Device]: Mark Local Field Records as Completed', (WidgetTester tester) async {
      final doorId = await LocalDatabaseService.insertDoor(Door(
        id: null,
        pos: 1,
        doorAlias: 'SYNC-DOOR-01',
        doorNumber: 'T-SYNC',
        floor: 'EG',
        roomNumber: '05',
        roomDesignation: 'Archiv',
        doorType: 'T30',
        wingCount: 1,
        material: 'Holz',
        manufacturer: 'Prüm',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: '',
        lockDimensions: '',
        closerOnHingeSide: true,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
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

      final inspectionId = await LocalDatabaseService.insertInspection({
        'clientName': 'Sync Client',
        'objectAddress': 'Sync Street 5',
        'date': '2026-08-31',
        'jobNumber': 'JOB-SYNC-04',
      });

      final inspDoorId = await LocalDatabaseService.insertInspectionDoor({
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': 'Passed',
      });

      final localDb = await LocalDatabaseService.getDb();
      await localDb.update(
        'inspection_doors',
        {'status': 'Completed'},
        where: 'id = ?',
        whereArgs: [inspDoorId],
      );

      final rows = await localDb.query(
        'inspection_doors',
        where: 'id = ?',
        whereArgs: [inspDoorId],
      );

      expect(rows.length, equals(1));
      expect(rows.first['status'], equals('Completed'));
    });

  });
}
