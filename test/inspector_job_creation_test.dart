import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/models/models.dart';

Door _createTestDoor({
  required String doorNumber,
  required String roomDesignation,
  String notes = '',
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
    notes: notes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await LocalDatabaseService.clearSyncedData();
  });

  tearDown(() async {
    await LocalDatabaseService.closeDb();
  });

  test('Inspector creates new job with NO existing event -> creates blank event (0 doors, 0 errors)', () async {
    // 1. Verify working.db is empty
    final initialInspections = await LocalDatabaseService.getAllInspections();
    expect(initialInspections, isEmpty);

    // 2. Create blank event
    final inspId = await LocalDatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-BLANK-01',
      objectAddress: 'Hauptstraße 10, 10115 Berlin',
      clientName: 'Berlin Real Estate',
      jobNumber: 'JOB-BER-2026-01',
      date: DateTime(2026, 10, 1),
      orderType: 'Wartung',
      contactPerson: 'Fr. Meier',
      inspectorName: 'Inspektor Alex',
      cloneDoors: false,
    );

    expect(inspId, isPositive);

    final inspection = await LocalDatabaseService.getInspectionById(inspId);
    expect(inspection, isNotNull);
    expect(inspection!['projectNumber'], 'PRJ-BLANK-01');
    expect(inspection['objectAddress'], 'Hauptstraße 10, 10115 Berlin');
    expect(inspection['clientName'], 'Berlin Real Estate');
    expect(inspection['jobNumber'], 'JOB-BER-2026-01');
    expect(inspection['orderType'], 'Wartung');
    expect(inspection['contactPerson'], 'Fr. Meier');
    expect(inspection['inspectorName'], 'Inspektor Alex');

    // Verify 0 doors and 0 errors
    final doors = await LocalDatabaseService.getDoorsByInspectionId(inspId);
    expect(doors, isEmpty);
  });

  test('Inspector creates new follow-up job with EXISTING event -> inherits metadata & doors, preserves open errors, clears solved errors', () async {
    // 1. Setup Base Event with 2 doors:
    // Door 1: Open error
    // Door 2: Gelöst (resolved) error
    final baseDate = DateTime(2026, 5, 1);
    final baseInspId = await LocalDatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-OFFICE-01',
      objectAddress: 'Campus Allee 1, 80807 München',
      clientName: 'Tech Campus München',
      jobNumber: 'WARTUNG-2026-001',
      date: baseDate,
      orderType: 'Wartung',
      contactPerson: 'Herr Schulz',
      inspectorName: 'Prüfer Tom',
      cloneDoors: false,
    );

    final door1Id = await LocalDatabaseService.insertDoor(_createTestDoor(
      doorNumber: 'T-01',
      roomDesignation: 'Server Room',
      notes: 'Türschließer verliert Öl',
    ));
    final door2Id = await LocalDatabaseService.insertDoor(_createTestDoor(
      doorNumber: 'T-02',
      roomDesignation: 'Meeting Room',
      notes: 'Scharnier geölt [Gelöst]',
    ));

    final junction1Id = await LocalDatabaseService.insertInspectionDoor({
      'inspectionId': baseInspId,
      'doorId': door1Id,
      'status': 'Inspected',
      'notes': 'Türschließer verliert Öl',
    });
    final junction2Id = await LocalDatabaseService.insertInspectionDoor({
      'inspectionId': baseInspId,
      'doorId': door2Id,
      'status': 'Inspected',
      'notes': 'Scharnier geölt [Gelöst]',
    });

    // Error 1 on Door 1: Open
    await LocalDatabaseService.insertInspectionDoorError(InspectionDoorError(
      inspectionDoorId: junction1Id,
      errorCode: 'DEF_OPEN_01',
      notes: 'Schließer defekt',
      severity: 'high',
      quantity: 1,
      resolutionStatus: 'open',
    ));

    // Error 2 on Door 2: Gelöst (Resolved)
    await LocalDatabaseService.insertInspectionDoorError(InspectionDoorError(
      inspectionDoorId: junction2Id,
      errorCode: 'DEF_SOLVED_01',
      notes: 'Scharnier geölt',
      severity: 'low',
      quantity: 1,
      resolutionStatus: 'gelöst',
    ));

    // 2. Inspector triggers new follow-up Reparatur job
    final repDate = DateTime(2026, 5, 15);
    final followUpInspId = await LocalDatabaseService.createAuftragFromLatestInspection(
      projectNumber: '', // will be inherited from base inspection
      objectAddress: '', // will be inherited from base inspection
      clientName: '',    // will be inherited from base inspection
      jobNumber: 'REP-2026-002',
      date: DateTime(2026, 5, 15),
      orderType: 'Reparatur',
      repairDate: repDate,
      contactPerson: 'Herr Schneider',
      inspectorName: 'Techniker Lisa',
      cloneDoors: true,
      sourceInspectionId: baseInspId,
    );

    expect(followUpInspId, isPositive);

    final followUpInsp = await LocalDatabaseService.getInspectionById(followUpInspId);
    expect(followUpInsp, isNotNull);
    // Metadata inherited
    expect(followUpInsp!['projectNumber'], 'PRJ-OFFICE-01');
    expect(followUpInsp['objectAddress'], 'Campus Allee 1, 80807 München');
    expect(followUpInsp['clientName'], 'Tech Campus München');
    // New editable fields
    expect(followUpInsp['jobNumber'], 'REP-2026-002');
    expect(followUpInsp['orderType'], 'Reparatur');
    expect(followUpInsp['repairDate'], repDate.toIso8601String());
    expect(followUpInsp['contactPerson'], 'Herr Schneider');
    expect(followUpInsp['inspectorName'], 'Techniker Lisa');

    // Verify 2 doors cloned
    final clonedDoors = await LocalDatabaseService.getDoorsByInspectionId(followUpInspId);
    expect(clonedDoors.length, 2);

    // Verify error propagation
    final summaries = await LocalDatabaseService.getDoorErrorSummariesForInspection(followUpInspId);

    // Door 1 should have 1 open error
    expect(summaries[door1Id]?.totalErrors, 1);
    expect(summaries[door1Id]?.openErrors, 1);
    expect(summaries[door1Id]?.resolvedErrors, 0);

    // Door 2 should have 0 errors (solved error was dropped)
    expect(summaries[door2Id]?.totalErrors, 0);
    expect(summaries[door2Id]?.openErrors, 0);
    expect(summaries[door2Id]?.resolvedErrors, 0);

    // Verify door notes for solved error were cleared on Door 2
    final followUpJunctions = await LocalDatabaseService.getInspectionDoorsByInspectionId(followUpInspId);
    final j1 = followUpJunctions.firstWhere((j) => j['doorId'] == door1Id);
    final j2 = followUpJunctions.firstWhere((j) => j['doorId'] == door2Id);

    expect(j1['notes'], 'Türschließer verliert Öl');
    expect(j2['notes'], isEmpty);
  });
}
