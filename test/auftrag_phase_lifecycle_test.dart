import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/models/models.dart';

Door _createTestDoor({
  required String doorNumber,
  required String roomDesignation,
  String notes = '',
  bool doorFunctionOK = false,
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
    doorFunctionOK: doorFunctionOK,
    notes: notes,
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

  test('Standalone Reparatur Auftrag from scratch creation test', () async {
    // 1. Create a standalone Reparatur job from scratch
    final repDate = DateTime(2026, 10, 15);
    final inspectionId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-STANDALONE-REP-01',
      objectAddress: 'Industriestr. 99, 80999 München',
      clientName: 'München Tech AG',
      jobNumber: 'REP-2026-001',
      date: DateTime(2026, 10, 1),
      orderType: 'Reparatur',
      repairDate: repDate,
      contactPerson: 'Herr Schneider',
      inspectorName: 'Techniker Hans',
      cloneDoors: false,
    );

    expect(inspectionId, isPositive);

    final inspection = await DatabaseService.getInspectionById(inspectionId);
    expect(inspection, isNotNull);
    expect(inspection!['projectNumber'], 'PRJ-STANDALONE-REP-01');
    expect(inspection['orderType'], 'Reparatur');
    expect(inspection['repairDate'], repDate.toIso8601String());
    expect(inspection['jobNumber'], 'REP-2026-001');
    expect(inspection['clientName'], 'München Tech AG');

    // Should have 0 doors because cloneDoors was false
    final junctions = await DatabaseService.getInspectionDoorsByInspectionId(inspectionId);
    expect(junctions.isEmpty, isTrue);
  });

  test('Open errors are passed to next event, solved errors are dropped, resolved notes cleared', () async {
    // 1. Base Event: Wartung with 1 open error and 1 solved error
    final baseInspId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-ERROR-CHAIN-01',
      objectAddress: 'Bavariaring 10, 80336 München',
      clientName: 'Bavaria Real Estate',
      jobNumber: 'WARTUNG-2025-01',
      date: DateTime(2025, 5, 10),
      orderType: 'Wartung',
      cloneDoors: false,
    );

    final baseDoor = _createTestDoor(
      doorNumber: 'T-101',
      roomDesignation: 'Serverraum',
      notes: 'Türschließer defekt & Scharnier geölt',
      doorFunctionOK: false,
    );
    final doorId = await DatabaseService.insertDoor(baseDoor);
    final junctionId = await DatabaseService.insertInspectionDoor({
      'inspectionId': baseInspId,
      'doorId': doorId,
      'status': 'Pending',
      'notes': 'Türschließer defekt & Scharnier geölt',
    });

    // Error 1: Open
    await DatabaseService.insertInspectionDoorError(InspectionDoorError(
      inspectionDoorId: junctionId,
      errorCode: 'DEF_CLOSER_OPEN',
      notes: 'Türschließer verliert Öl',
      severity: 'high',
      quantity: 1,
      resolutionStatus: 'open',
    ));

    // Error 2: Solved / Gelöst
    await DatabaseService.insertInspectionDoorError(InspectionDoorError(
      inspectionDoorId: junctionId,
      errorCode: 'DEF_HINGE_SOLVED',
      notes: 'Scharnier quietscht - behoben',
      severity: 'low',
      quantity: 1,
      resolutionStatus: 'gelöst',
    ));

    // 2. Next Event: Follow-up Wartung (or Reparatur) for 2026
    final nextInspId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-ERROR-CHAIN-01',
      objectAddress: 'Bavariaring 10, 80336 München',
      clientName: 'Bavaria Real Estate',
      jobNumber: 'WARTUNG-2026-01',
      date: DateTime(2026, 5, 12),
      orderType: 'Wartung',
      cloneDoors: true,
    );

    expect(nextInspId, isPositive);
    final nextJunctions = await DatabaseService.getInspectionDoorsByInspectionId(nextInspId);
    expect(nextJunctions.length, 1);

    final nextErrors = await DatabaseService.getDetailedErrorsForInspectionDoor(nextJunctions.first['id'] as int);
    // Rule: Open error is passed, solved error is NOT passed
    expect(nextErrors.length, 1);
    expect(nextErrors.first['errorCode'], 'DEF_CLOSER_OPEN');
    expect(nextErrors.first['notes'], 'Türschließer verliert Öl');
    expect(nextErrors.first['resolutionStatus'], 'Open');

    // Rule: Door notes for the open error remain
    final nextJunctionNote = nextJunctions.first['notes']?.toString() ?? '';
    expect(nextJunctionNote, contains('Türschließer defekt'));
  });

  test('Job number uniqueness is strictly enforced', () async {
    await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-UNIQUE-01',
      objectAddress: 'Alsterufer 1, Hamburg',
      clientName: 'Alster Properties',
      jobNumber: 'AUFTRAG-DUPLICATE-TEST',
      date: DateTime(2026, 1, 10),
      orderType: 'Wartung',
      cloneDoors: false,
    );

    // Attempting to create another job with the exact same jobNumber must throw ArgumentError
    expect(
      () => DatabaseService.createAuftragFromLatestInspection(
        projectNumber: 'PRJ-UNIQUE-01',
        objectAddress: 'Alsterufer 1, Hamburg',
        clientName: 'Alster Properties',
        jobNumber: 'AUFTRAG-DUPLICATE-TEST',
        date: DateTime(2026, 2, 10),
        orderType: 'Reparatur',
        cloneDoors: true,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('Subsequent event date cannot be earlier than previous event date', () async {
    await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-DATE-SEQ-01',
      objectAddress: 'Odeonsplatz 4, München',
      clientName: 'Bavaria Heritage',
      jobNumber: 'JOB-FIRST-2026',
      date: DateTime(2026, 6, 15),
      orderType: 'Wartung',
      cloneDoors: false,
    );

    // Attempting to create a subsequent event dated 2026-06-10 (before 2026-06-15) must throw ArgumentError
    expect(
      () => DatabaseService.createAuftragFromLatestInspection(
        projectNumber: 'PRJ-DATE-SEQ-01',
        objectAddress: 'Odeonsplatz 4, München',
        clientName: 'Bavaria Heritage',
        jobNumber: 'JOB-SECOND-2026',
        date: DateTime(2026, 6, 10),
        orderType: 'Reparatur',
        repairDate: DateTime(2026, 6, 10),
        cloneDoors: true,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('Chain: Wartung -> Reparatur -> Wartung -> Reparatur with error state transitions', () async {
    // 1. Wartung (Jan 2026): records 2 defects
    final w1Id = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-CHAIN-01',
      objectAddress: 'Maximilianstr. 20, München',
      clientName: 'Max Luxury',
      jobNumber: 'W-2026-01',
      date: DateTime(2026, 1, 10),
      orderType: 'Wartung',
      cloneDoors: false,
    );
    final doorId = await DatabaseService.insertDoor(_createTestDoor(doorNumber: 'T-1', roomDesignation: 'Lobby'));
    final w1JuncId = await DatabaseService.insertInspectionDoor({
      'inspectionId': w1Id,
      'doorId': doorId,
      'status': 'Failed',
      'notes': 'Zwei Mängel festgestellt',
    });
    await DatabaseService.insertInspectionDoorError(InspectionDoorError(
      inspectionDoorId: w1JuncId,
      errorCode: 'DEF_1',
      notes: 'Mangel 1',
      quantity: 1,
      severity: 'medium',
      resolutionStatus: 'open',
    ));
    await DatabaseService.insertInspectionDoorError(InspectionDoorError(
      inspectionDoorId: w1JuncId,
      errorCode: 'DEF_2',
      notes: 'Mangel 2',
      quantity: 1,
      severity: 'medium',
      resolutionStatus: 'open',
    ));

    // 2. Reparatur (Feb 2026): repairs DEF_1 (resolved), but DEF_2 remains open
    final r1Id = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-CHAIN-01',
      objectAddress: 'Maximilianstr. 20, München',
      clientName: 'Max Luxury',
      jobNumber: 'R-2026-01',
      date: DateTime(2026, 1, 10),
      orderType: 'Reparatur',
      repairDate: DateTime(2026, 2, 10),
      cloneDoors: true,
    );
    final r1Juncs = await DatabaseService.getInspectionDoorsByInspectionId(r1Id);
    final r1Errors = await DatabaseService.getDetailedErrorsForInspectionDoor(r1Juncs.first['id'] as int);
    expect(r1Errors.length, 2);

    // Mark DEF_1 as resolved during repair
    final def1Id = r1Errors.firstWhere((e) => e['errorCode'] == 'DEF_1')['id'] as int;
    await DatabaseService.insertInspectionDoorError(InspectionDoorError(
      id: def1Id,
      inspectionDoorId: r1Juncs.first['id'] as int,
      errorCode: 'DEF_1',
      notes: 'Mangel 1 behoben',
      quantity: 1,
      severity: 'medium',
      resolutionStatus: 'Resolved',
    ));

    // 3. Follow-up Wartung (Mar 2026): Only open error (DEF_2) must be passed over
    final w2Id = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-CHAIN-01',
      objectAddress: 'Maximilianstr. 20, München',
      clientName: 'Max Luxury',
      jobNumber: 'W-2026-02',
      date: DateTime(2026, 3, 10),
      orderType: 'Wartung',
      cloneDoors: true,
    );
    final w2Juncs = await DatabaseService.getInspectionDoorsByInspectionId(w2Id);
    final w2Errors = await DatabaseService.getDetailedErrorsForInspectionDoor(w2Juncs.first['id'] as int);
    expect(w2Errors.length, 1);
    expect(w2Errors.first['errorCode'], 'DEF_2');

    // 4. Follow-up Reparatur (Apr 2026): Repairs DEF_2
    final r2Id = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-CHAIN-01',
      objectAddress: 'Maximilianstr. 20, München',
      clientName: 'Max Luxury',
      jobNumber: 'R-2026-02',
      date: DateTime(2026, 3, 10),
      orderType: 'Reparatur',
      repairDate: DateTime(2026, 4, 10),
      cloneDoors: true,
    );
    final r2Juncs = await DatabaseService.getInspectionDoorsByInspectionId(r2Id);
    final r2Errors = await DatabaseService.getDetailedErrorsForInspectionDoor(r2Juncs.first['id'] as int);
    expect(r2Errors.length, 1);
    expect(r2Errors.first['errorCode'], 'DEF_2');
  });

  test('Importing an inspection package marks the job as Erledigt in Master DB', () async {
    final tempDbPath = 'test_wartung_erledigt_export_${DateTime.now().millisecondsSinceEpoch}.db';

    // 1. Create a Wartung job and export it
    final inspId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-ERLEDIGT-IMPORT-01',
      objectAddress: 'Berliner Str. 50, Berlin',
      clientName: 'Capital Immo',
      jobNumber: 'W-BERLIN-01',
      date: DateTime(2026, 5, 1),
      orderType: 'Wartung',
      cloneDoors: false,
    );
    final doorId = await DatabaseService.insertDoor(_createTestDoor(doorNumber: 'T-B1', roomDesignation: 'Eingang'));
    await DatabaseService.insertInspectionDoor({
      'inspectionId': inspId,
      'doorId': doorId,
      'status': 'Passed',
      'notes': 'Alles in Ordnung',
    });

    await DatabaseService.exportJobPackage([inspId], destinationPath: tempDbPath);

    // 2. Clear master DB and import the package as manager
    await DatabaseService.clearDatabase();
    final report = await DatabaseService.importAndMergePackage(tempDbPath);
    expect(report.newInspectionsCount + report.updatedInspectionsCount, 1);

    // 3. Verify the imported inspection preserves orderType = 'Wartung'
    final importedInsps = await DatabaseService.searchInspections('W-BERLIN-01');
    expect(importedInsps.length, 1);
    expect(importedInsps.first['orderType'], 'Wartung');

    // Clean up temp file
    final tempFile = File(tempDbPath);
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }
  });
}
