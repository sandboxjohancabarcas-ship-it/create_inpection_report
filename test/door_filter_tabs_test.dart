import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/pages/inspection_doors_page.dart';

Door _createTestDoor({
  required String doorNumber,
  required String roomDesignation,
}) {
  return Door(
    id: null,
    pos: 1,
    doorNumber: doorNumber,
    floor: 'EG',
    roomNumber: '101',
    roomDesignation: roomDesignation,
    doorType: 'T30',
    wingCount: 1,
    material: 'Stahl',
    manufacturer: 'Hörmann',
    dinConfiguration: 'DIN L',
    closerType: 'TS93',
    closingSequenceSystem: 'None',
    lockDimensions: '65/72/9',
    closerOnHingeSide: true,
    closerOnOppositeSide: false,
    accessControl: 'Nein',
    escapeRouteSituation: false,
    escapeRouteSignage: false,
    blindCylinder: false,
    pzCylinder: true,
    fittingType: 'Drücker',
    panicFunction: 'Nein',
    escapeDirectionRespected: true,
    fullPanicStandWing: false,
    doorFunctionOK: true,
    notes: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await DatabaseService.clearDatabase();
    await LocalDatabaseService.clearSyncedData();
  });

  tearDown(() async {
    await DatabaseService.closeDb();
    await LocalDatabaseService.closeDb();
  });

  test('3 doors (2 no errors, 1 gelöst error) error summary and filter counts', () async {
    // 1. Create base inspection
    final inspectionId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-FILTERS-01',
      objectAddress: 'Musterstraße 1, Hamburg',
      clientName: 'Muster AG',
      jobNumber: 'JOB-FLT-001',
      date: DateTime(2026, 9, 30),
      orderType: 'Wartung',
      cloneDoors: false,
    );

    // 2. Insert 3 doors
    final doorId1 = await DatabaseService.insertDoor(_createTestDoor(
      doorNumber: 'T-01',
      roomDesignation: 'Office 1',
    ));
    final doorId2 = await DatabaseService.insertDoor(_createTestDoor(
      doorNumber: 'T-02',
      roomDesignation: 'Office 2',
    ));
    final doorId3 = await DatabaseService.insertDoor(_createTestDoor(
      doorNumber: 'T-03',
      roomDesignation: 'Office 3',
    ));

    // Link all 3 doors to the inspection as 'Inspected'
    final inspDoorId1 = await DatabaseService.insertInspectionDoor({
      'inspectionId': inspectionId,
      'doorId': doorId1,
      'status': 'Inspected',
      'notes': '',
    });
    final inspDoorId2 = await DatabaseService.insertInspectionDoor({
      'inspectionId': inspectionId,
      'doorId': doorId2,
      'status': 'Inspected',
      'notes': '',
    });
    final inspDoorId3 = await DatabaseService.insertInspectionDoor({
      'inspectionId': inspectionId,
      'doorId': doorId3,
      'status': 'Inspected',
      'notes': '',
    });

    // Door 1 and Door 2 have 0 error records
    // Door 3 has 1 error record with resolutionStatus = 'gelöst'
    await DatabaseService.insertInspectionDoorError(InspectionDoorError(
      inspectionDoorId: inspDoorId3,
      errorCode: 'DEF-01',
      notes: 'Türschließer defekt - repariert',
      severity: 'low',
      quantity: 1,
      resolutionStatus: 'gelöst',
    ));

    // 3. Query error summaries
    final summaries = await DatabaseService.getDoorErrorSummariesForInspection(inspectionId);

    expect(summaries[doorId1]?.totalErrors ?? 0, equals(0));
    expect(summaries[doorId1]?.openErrors ?? 0, equals(0));
    expect(summaries[doorId1]?.resolvedErrors ?? 0, equals(0));

    expect(summaries[doorId2]?.totalErrors ?? 0, equals(0));
    expect(summaries[doorId2]?.openErrors ?? 0, equals(0));
    expect(summaries[doorId2]?.resolvedErrors ?? 0, equals(0));

    expect(summaries[doorId3]?.totalErrors ?? 0, equals(1));
    expect(summaries[doorId3]?.openErrors ?? 0, equals(0));
    expect(summaries[doorId3]?.resolvedErrors ?? 0, equals(1));

    // 4. Test filter count calculation as done in InspectionDoorsPage
    final doors = await DatabaseService.getDoorsByInspectionIds([inspectionId]);
    expect(doors.length, equals(3));

    final statuses = await DatabaseService.getDoorInspectionStatuses(inspectionId);

    bool isDoorInspected(Door d) {
      if (d.id == null) return false;
      final status = (statuses[d.id] ?? '').trim().toLowerCase();
      return status == 'inspected' ||
          status == 'geprüft' ||
          status == 'completed' ||
          status == 'passed' ||
          status == 'failed' ||
          status == 'done' ||
          status == 'bearbeitet';
    }

    final totalCount = doors.length;
    final inspectedCount = doors.where((d) => isDoorInspected(d)).length;
    final pendingCount = totalCount - inspectedCount;
    final doorsWithErrorsCount = doors.where((d) => (summaries[d.id]?.openErrors ?? 0) > 0).length;
    final doorsResolvedCount = doors.where((d) => (summaries[d.id]?.resolvedErrors ?? 0) > 0).length;
    final doorsErrorFreeCount = doors.where((d) => isDoorInspected(d) && (summaries[d.id]?.totalErrors ?? 0) == 0).length;

    expect(totalCount, equals(3));
    expect(inspectedCount, equals(3));
    expect(pendingCount, equals(0));
    expect(doorsWithErrorsCount, equals(0), reason: 'No door has open defects');
    expect(doorsResolvedCount, equals(1), reason: 'Door 3 has a resolved defect');
    expect(doorsErrorFreeCount, equals(2), reason: 'Door 1 and Door 2 have 0 defects');

    // 5. Test filtering predicate results for each tab
    List<Door> filterDoors(InspectionDoorFilter filter) {
      return doors.where((door) {
        if (filter == InspectionDoorFilter.inspected && !isDoorInspected(door)) return false;
        if (filter == InspectionDoorFilter.pending && isDoorInspected(door)) return false;
        if (filter == InspectionDoorFilter.withErrors) {
          final summary = summaries[door.id];
          if (summary == null || summary.openErrors == 0) return false;
        }
        if (filter == InspectionDoorFilter.resolved) {
          final summary = summaries[door.id];
          if (summary == null || summary.resolvedErrors == 0) return false;
        }
        if (filter == InspectionDoorFilter.errorFree) {
          final summary = summaries[door.id];
          if (summary != null && summary.totalErrors > 0) return false;
          if (!isDoorInspected(door)) return false;
        }
        return true;
      }).toList();
    }

    expect(filterDoors(InspectionDoorFilter.all).map((d) => d.doorNumber).toList(), ['T-01', 'T-02', 'T-03']);
    expect(filterDoors(InspectionDoorFilter.inspected).map((d) => d.doorNumber).toList(), ['T-01', 'T-02', 'T-03']);
    expect(filterDoors(InspectionDoorFilter.pending), isEmpty);
    expect(filterDoors(InspectionDoorFilter.withErrors), isEmpty);
    expect(filterDoors(InspectionDoorFilter.resolved).map((d) => d.doorNumber).toList(), ['T-03']);
    expect(filterDoors(InspectionDoorFilter.errorFree).map((d) => d.doorNumber).toList(), ['T-01', 'T-02']);
  });

  test('Inspection with open errors, resolved errors, and error-free doors', () async {
    final inspectionId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-FILTERS-02',
      objectAddress: 'Musterstraße 2, Hamburg',
      clientName: 'Muster AG',
      jobNumber: 'JOB-FLT-002',
      date: DateTime(2026, 9, 30),
      orderType: 'Wartung',
      cloneDoors: false,
    );

    // Door 1: Uninspected (Pending), 0 errors
    // Door 2: Inspected, 0 errors (Mängelfrei)
    // Door 3: Inspected, 1 open error (Mit Mängeln)
    // Door 4: Inspected, 1 resolved error (Gelöst)
    final doorId1 = await DatabaseService.insertDoor(_createTestDoor(doorNumber: 'D-01', roomDesignation: 'Room 1'));
    final doorId2 = await DatabaseService.insertDoor(_createTestDoor(doorNumber: 'D-02', roomDesignation: 'Room 2'));
    final doorId3 = await DatabaseService.insertDoor(_createTestDoor(doorNumber: 'D-03', roomDesignation: 'Room 3'));
    final doorId4 = await DatabaseService.insertDoor(_createTestDoor(doorNumber: 'D-04', roomDesignation: 'Room 4'));

    await DatabaseService.insertInspectionDoor({'inspectionId': inspectionId, 'doorId': doorId1, 'status': 'Pending', 'notes': ''});
    await DatabaseService.insertInspectionDoor({'inspectionId': inspectionId, 'doorId': doorId2, 'status': 'Inspected', 'notes': ''});
    final inspDoorId3 = await DatabaseService.insertInspectionDoor({'inspectionId': inspectionId, 'doorId': doorId3, 'status': 'Inspected', 'notes': ''});
    final inspDoorId4 = await DatabaseService.insertInspectionDoor({'inspectionId': inspectionId, 'doorId': doorId4, 'status': 'Inspected', 'notes': ''});

    await DatabaseService.insertInspectionDoorError(InspectionDoorError(
      inspectionDoorId: inspDoorId3,
      errorCode: 'DEF-OPEN',
      notes: 'Schloss defekt',
      severity: 'high',
      quantity: 1,
      resolutionStatus: 'open',
    ));

    await DatabaseService.insertInspectionDoorError(InspectionDoorError(
      inspectionDoorId: inspDoorId4,
      errorCode: 'DEF-RESOLVED',
      notes: 'Schloss getauscht',
      severity: 'high',
      quantity: 1,
      resolutionStatus: 'Resolved',
    ));

    final summaries = await DatabaseService.getDoorErrorSummariesForInspection(inspectionId);
    final doors = await DatabaseService.getDoorsByInspectionIds([inspectionId]);
    final statuses = await DatabaseService.getDoorInspectionStatuses(inspectionId);

    bool isDoorInspected(Door d) {
      if (d.id == null) return false;
      final status = (statuses[d.id] ?? '').trim().toLowerCase();
      return status == 'inspected' || status == 'geprüft' || status == 'completed';
    }

    final totalCount = doors.length;
    final inspectedCount = doors.where((d) => isDoorInspected(d)).length;
    final pendingCount = totalCount - inspectedCount;
    final doorsWithErrorsCount = doors.where((d) => (summaries[d.id]?.openErrors ?? 0) > 0).length;
    final doorsResolvedCount = doors.where((d) => (summaries[d.id]?.resolvedErrors ?? 0) > 0).length;
    final doorsErrorFreeCount = doors.where((d) => isDoorInspected(d) && (summaries[d.id]?.totalErrors ?? 0) == 0).length;

    expect(totalCount, equals(4));
    expect(inspectedCount, equals(3));
    expect(pendingCount, equals(1));
    expect(doorsWithErrorsCount, equals(1));
    expect(doorsResolvedCount, equals(1));
    expect(doorsErrorFreeCount, equals(1));
  });
}
