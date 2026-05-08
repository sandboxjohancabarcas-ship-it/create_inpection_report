import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:create_inpection_report/services/local_database_service.dart';
import 'package:create_inpection_report/models/models.dart';

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
        inspectionDoorId: testDoor.id, 
        errorId: 10,
        quantity: 1,
        severity: 'high',
        notes: 'Dichtung im unteren Bereich beschädigt',
        resolutionStatus: 'Open',
      );

      await LocalDatabaseService.insertInspectionDoorError(testError);

      // 3. PROOF: Retrieve data directly from working.db
      final localDoors = await LocalDatabaseService.getAllDoors();
      final doorExists = localDoors.any((d) => d['doorNumber'] == 'LOCAL-TEST-01');
      
      expect(doorExists, isTrue, reason: 'Door was not found in working.db');
      
      final storedErrors = await LocalDatabaseService.getErrorsForInspectionDoor(testDoor.id);
      
      expect(storedErrors.length, 1, reason: 'Error record missing in working.db');
      expect(storedErrors.first.notes, 'Dichtung im unteren Bereich beschädigt');
      expect(testDoor.syncStatus, 'pending', reason: 'New data must be marked as pending');
    });
  });
}