import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/models/models.dart';


void main() {
  // Initialize sqflite for local environment testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('LocalDatabaseService (working.db) Verification Tests', () {
    setUp(() async {
      // Clear local tables before each test to ensure a clean slate
      final db = await LocalDatabaseService.getDb();
      await db.delete('doors');
      await db.delete('inspections');
      await db.delete('inspection_doors');
      await db.delete('inspection_door_errors');
    });

    test('Verification: Saving Door and Errors to working.db (Offline Flow)', () async {
      // 1. Simulate creating a door as done in new_door_page.dart
      final testDoor = Door(
        id: 555,
        pos: 1,
        doorAlias: 'LOC-TEST-01',
        doorNumber: 'LOCAL-TEST-01',
        floor: '1.OG',
        roomNumber: '101',
        roomDesignation: 'Server Room',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Dorma',
        dinConfiguration: 'DIN R',
        closerType: 'Standard',
        closingSequenceSystem: 'Keine',
        lockDimensions: '92mm',
        closerOnHingeSide: true,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: true,
        accessControl: 'Nein',
        escapeRouteSituation: true,
        escapeRouteSignage: true,
        blindCylinder: false,
        pzCylinder: true,
        fittingType: 'Drückergarnitur',
        panicFunction: 'E',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: false,
        syncStatus: 'pending',
      );

      // Save the door locally
      await LocalDatabaseService.insertDoor(testDoor);

      // 2. Simulate adding an error as done in ErrorManagementPage.dart
      // In your UI, widget.doorId (555) is passed as the inspectionDoorId
      final testError = InspectionDoorError(
        inspectionDoorId: testDoor.id!,
        errorId: 10,
        quantity: 1,
        severity: 'high',
        notes: 'Dichtung im unteren Bereich beschädigt',
        resolutionStatus: 'Open',
      );

      await LocalDatabaseService.insertInspectionDoorError(testError);

      // 3. PROOF: Retrieve data directly from working.db
      final localDoors = await LocalDatabaseService.getAllDoors();
      final doorExists = localDoors.any((d) => d.doorNumber == 'LOCAL-TEST-01');
      
      expect(doorExists, isTrue, reason: 'Door was not found in working.db');
      
      final storedErrors = await LocalDatabaseService.getErrorsForInspectionDoor(testDoor.id!);
      
      expect(storedErrors.length, 1, reason: 'Error record missing in working.db');
      expect(storedErrors.first.notes, 'Dichtung im unteren Bereich beschädigt');
      expect(testDoor.syncStatus, 'pending', reason: 'New data must be marked as pending');
    });

    test('Requirement 2: Isolation Verification (Clean Slate)', () async {
      // 1. Setup: Create a "leftover" door from a previous job in working.db
      await LocalDatabaseService.insertDoor(Door(
        id: 111,
        pos: 1,
        doorAlias: 'OldCustomer-SiteX-001',
        doorNumber: 'OLD-1',
        floor: '', roomNumber: '', roomDesignation: '', doorType: '', wingCount: 1, material: '', manufacturer: '', dinConfiguration: '', closerType: '', closingSequenceSystem: '', lockDimensions: '', closerOnHingeSide: false, closerOnOppositeSide: false, lintelHeightUnder1m: false, escapeDoorControl: false, accessControl: '', escapeRouteSituation: false, escapeRouteSignage: false, blindCylinder: false, pzCylinder: false, fittingType: '', panicFunction: '', escapeDirectionRespected: false, fullPanicStandWing: false, doorFunctionOK: true,
      ));

      // Verify it exists before clearing
      var currentDoors = await LocalDatabaseService.getAllDoors();
      expect(currentDoors.length, 1);

      // 2. Trigger isolation logic
      await LocalDatabaseService.clearSyncedData();

      // 3. Verify working.db is now empty
      currentDoors = await LocalDatabaseService.getAllDoors();
      expect(currentDoors.isEmpty, isTrue, reason: 'Isolation protocol failed: old doors were not purged.');
    });

    test('Requirement 3: Local Search via Alias', () async {
      await LocalDatabaseService.insertDoor(Door(
        id: 222,
        pos: 1,
        doorAlias: 'ActiveCustomer-MainSite-001',
        doorNumber: 'D1',
        floor: '', roomNumber: '', roomDesignation: '', doorType: '', wingCount: 1, material: '', manufacturer: '', dinConfiguration: '', closerType: '', closingSequenceSystem: '', lockDimensions: '', closerOnHingeSide: false, closerOnOppositeSide: false, lintelHeightUnder1m: false, escapeDoorControl: false, accessControl: '', escapeRouteSituation: false, escapeRouteSignage: false, blindCylinder: false, pzCylinder: false, fittingType: '', panicFunction: '', escapeDirectionRespected: false, fullPanicStandWing: false, doorFunctionOK: true,
      ));

      // Search by partial alias string
      final results = await LocalDatabaseService.searchDoors('Active');
      expect(results.length, 1);
      expect(results.first.doorAlias, 'ActiveCustomer-MainSite-001');
    });

    test('Requirement 2: Wide Spectrum Download (History & Isolation)', () async {
      // 1. SETUP MASTER DB (Simulation)
      final mainDb = await DatabaseService.getDb();
      await mainDb.delete('doors');
      await mainDb.delete('inspections');
      await mainDb.delete('inspection_doors');
      await mainDb.delete('inspection_door_errors');

      // Create 2 historical inspections for the same object
      final inspId1 = await DatabaseService.insertInspection({
        'inspectionId': 1001,
        'clientName': 'SpectrumCorp',
        'objectAddress': 'Main St 1',
        'date': '2023-01-01',
      });
      final inspId2 = await DatabaseService.insertInspection({
        'inspectionId': 1002,
        'clientName': 'SpectrumCorp',
        'objectAddress': 'Main St 1',
        'date': '2024-01-01',
      });

      final doorId = 55;
      await DatabaseService.insertDoor(Door(
        id: doorId, pos: 1, doorAlias: 'SC-M1-D1', doorNumber: 'D1', doorFunctionOK: true,
        floor: '', roomNumber: '', roomDesignation: '', doorType: '', wingCount: 1, material: '', manufacturer: '', dinConfiguration: '', closerType: '', closingSequenceSystem: '', lockDimensions: '', closerOnHingeSide: false, closerOnOppositeSide: false, lintelHeightUnder1m: false, escapeDoorControl: false, accessControl: '', escapeRouteSituation: false, escapeRouteSignage: false, blindCylinder: false, pzCylinder: false, fittingType: '', panicFunction: '', escapeDirectionRespected: false, fullPanicStandWing: false,
      ));
      
      // Link door to both inspections (History)
      await DatabaseService.insertInspectionDoor({'id': 2001, 'inspectionId': inspId1, 'doorId': doorId, 'status': 'Passed'});
      await DatabaseService.insertInspectionDoor({'id': 2002, 'inspectionId': inspId2, 'doorId': doorId, 'status': 'Failed'});

      // Add an error to the second (most recent) inspection
      await DatabaseService.insertInspectionDoorError(InspectionDoorError(
        id: 3001, inspectionDoorId: 2002, errorId: 1, notes: 'History Error', quantity: 1, severity: 'medium',
      ));

      // 2. SETUP LOCAL DB DIRTY STATE (Simulate a previous job for a different customer)
      await LocalDatabaseService.insertDoor(Door(
        id: 999, pos: 9, doorAlias: 'OLD-CUST-ADDR-001', doorNumber: 'X', doorFunctionOK: true,
        floor: '', roomNumber: '', roomDesignation: '', doorType: '', wingCount: 1, material: '', manufacturer: '', dinConfiguration: '', closerType: '', closingSequenceSystem: '', lockDimensions: '', closerOnHingeSide: false, closerOnOppositeSide: false, lintelHeightUnder1m: false, escapeDoorControl: false, accessControl: '', escapeRouteSituation: false, escapeRouteSignage: false, blindCylinder: false, pzCylinder: false, fittingType: '', panicFunction: '', escapeDirectionRespected: false, fullPanicStandWing: false,
      ));

      // 3. EXECUTE DOWNLOAD (Wide Spectrum)
      final idsToDownload = await DatabaseService.getInspectionIdsByCriteria(
        clientName: 'SpectrumCorp', objectAddress: 'Main St 1'
      );
      expect(idsToDownload.length, 2, reason: 'Should have found 2 historical inspections');

      await LocalDatabaseService.downloadJobPackage(inspectionIds: idsToDownload);

      // 4. VERIFY RESULTS
      final localDb = await LocalDatabaseService.getDb();
      final inspCount = Sqflite.firstIntValue(await localDb.rawQuery('SELECT COUNT(*) FROM inspections')) ?? 0;
      expect(inspCount, 2, reason: 'Both historical inspections should be present in working.db');

      final localDoors = await LocalDatabaseService.getAllDoors();
      expect(localDoors.length, 1);
      expect(localDoors.first.doorAlias, 'SC-M1-D1');
      expect(localDoors.any((d) => d.id == 999), isFalse, reason: 'Isolation failed: Old customer data was not purged');
    });
  });
}