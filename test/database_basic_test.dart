import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:create_inpection_report/services/database_service.dart';
import 'package:create_inpection_report/models/models.dart';

void main() {
  // Initialize sqflite for local unit testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseService Core Functionality Tests', () {
    setUp(() async {
      // Clear tables before each test to ensure isolation
      final db = await DatabaseService.getDb();
      await db.delete('doors');
      await db.delete('inspections');
      await db.delete('inspection_doors');
      await db.delete('inspection_door_errors');
      await db.delete('error_catalog');
    });

    test('Door CRUD - Should insert and retrieve a door', () async {
      final door = Door(
        id: 101,
        pos: 1,
        doorNumber: 'T01',
        floor: 'EG',
        roomNumber: '0.01',
        roomDesignation: 'Entrance',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Test',
        dinConfiguration: 'DIN L',
        closerType: 'Standard',
        closingSequenceSystem: 'Keine',
        lockDimensions: '72mm',
        closerOnHingeSide: false,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: false,
        accessControl: 'Nein',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: false,
        fittingType: 'Drückergarnitur',
        panicFunction: 'Nein',
        escapeDirectionRespected: false,
        fullPanicStandWing: false,
        doorFunctionOK: true,
        syncStatus: 'pending',
      );

      await DatabaseService.insertDoor(door);
      final allDoors = await DatabaseService.getAllDoors();

      expect(allDoors.any((d) => d.doorNumber == 'T01'), isTrue);
    });

    test('Inspection Linkage - Should create an inspection and link a door', () async {
      // Create an inspection record
      final inspectionId = await DatabaseService.insertInspection({
        'clientName': 'Global Corp',
        'auftragsnummer': '2023-XYZ',
        'date': '2023-11-01',
        'inspectorName': 'Test Inspector',
      });

      // Create a door
      final doorId = 202;
      await DatabaseService.insertDoor(Door(
        id: doorId,
        pos: 2,
        doorNumber: 'D-202',
        floor: '',
        roomNumber: '',
        roomDesignation: '',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: '',
        dinConfiguration: 'DIN L',
        closerType: 'Standard',
        closingSequenceSystem: 'Keine',
        lockDimensions: '',
        closerOnHingeSide: false,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: false,
        accessControl: 'Nein',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: false,
        fittingType: 'Drückergarnitur',
        panicFunction: 'Nein',
        escapeDirectionRespected: false,
        fullPanicStandWing: false,
        doorFunctionOK: true,
        syncStatus: 'pending',
      ));

      // Link door to inspection (mimics the workflow in DoorInspectionForm)
      await DatabaseService.insertInspectionDoor({
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': 'InProgress',
      });

      // Verify retrieval by criteria
      final doors = await DatabaseService.getDoorsByInspectionCriteria(
        clientName: 'Global Corp',
        jobNumber: '2023-XYZ',
        date: '2023-11-01',
      );

      expect(doors.length, 1);
      expect(doors.first.doorNumber, 'D-202');
    });

    test('Error Management - Should record and retrieve errors for a door', () async {
      final inspDoorId = 1;
      
      final error = InspectionDoorError(
        inspectionDoorId: inspDoorId,
        errorId: 5,
        severity: 'high',
        notes: 'Broken hinge',
        quantity: 1,
      );

      await DatabaseService.insertInspectionDoorError(error);
      
      final errors = await DatabaseService.getErrorsForInspectionDoor(inspDoorId);
      
      expect(errors.length, 1);
      expect(errors.first.notes, 'Broken hinge');
      expect(errors.first.severity, 'high');
    });

    test('Catalog Search - Should search error catalog by description', () async {
      // Seed an error manually
      final error = ErrorCatalog(
        code: 'CAT-001',
        description: 'Defective Closer',
        category: 'Hardware',
        severity: 'medium',
      );
      await DatabaseService.insertErrorCatalog(error);

      // Search for "closer"
      final results = await DatabaseService.searchErrorCatalog('closer');
      
      expect(results.length, 1);
      expect(results.first.code, 'CAT-001');
      expect(results.first.description, 'Defective Closer');
    });

    test('Integration: Create door, assign errors, and verify storage in main DB', () async {
      // 1. Prepare Door object with technical specifications
      final testDoor = Door(
        id: 999,
        pos: 1,
        doorNumber: 'WORK-001',
        floor: 'EG',
        roomNumber: '0.01',
        roomDesignation: 'Main Entrance',
        doorType: 'T30',
        wingCount: 1,
        material: 'Steel',
        manufacturer: 'Manufacturer A',
        dinConfiguration: 'DIN L',
        closerType: 'Overhead',
        closingSequenceSystem: 'None',
        lockDimensions: '72mm',
        closerOnHingeSide: true,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: true,
        accessControl: 'Yes',
        escapeRouteSituation: true,
        escapeRouteSignage: true,
        blindCylinder: false,
        pzCylinder: true,
        fittingType: 'Lever',
        panicFunction: 'B',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: false, // Set to false as it has errors
        syncStatus: 'pending',
      );

      // 2. Save Inspection Metadata (Parent record)
      final inspectionId = await DatabaseService.insertInspection({
        'clientName': 'Verification Corp',
        'auftragsnummer': 'VC-2024-01',
        'date': '2024-06-01',
        'inspectorName': 'Test Auditor',
      });

      // 3. Save Door and Link to Inspection (Junction record)
      final doorId = await DatabaseService.insertDoor(testDoor);
      final inspectionDoorId = await DatabaseService.insertInspectionDoor({
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': 'Failed',
        'notes': 'Door has critical issues',
      });

      // 4. Assign Errors (Related records)
      final error = InspectionDoorError(
        inspectionDoorId: inspectionDoorId,
        errorId: 101,
        severity: 'high',
        notes: 'Hinge is loose and needs immediate repair',
        quantity: 1,
      );
      await DatabaseService.insertInspectionDoorError(error);

      // 5. PROOF: Verify data is stored correctly in the main database
      final allDoors = await DatabaseService.getAllDoors();
      final storedDoor = allDoors.firstWhere((d) => d.doorNumber == 'WORK-001');
      
      expect(storedDoor, isNotNull, reason: 'Door should be found in the database');
      expect(storedDoor.manufacturer, 'Manufacturer A');
      expect(storedDoor.doorFunctionOK, isFalse);

      // Verify the associated error is also stored
      final storedErrors = await DatabaseService.getErrorsForInspectionDoor(inspectionDoorId);
      expect(storedErrors.length, 1);
      expect(storedErrors.first.notes, 'Hinge is loose and needs immediate repair');
    });
  });
}