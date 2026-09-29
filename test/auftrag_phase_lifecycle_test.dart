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

  test('Wartung Auftrag cloned from latest inspection resets notes and errors', () async {
    // 1. Prepare an initial inspection with a door and an error
    final baseInspId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-WARTUNG-CYCLE-01',
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
      notes: 'Schloss klemmt stark - 2025 Notiz',
      doorFunctionOK: false,
    );
    final doorId = await DatabaseService.insertDoor(baseDoor);
    final junctionId = await DatabaseService.insertInspectionDoor({
      'inspectionId': baseInspId,
      'doorId': doorId,
      'status': 'Pending',
      'notes': 'Schloss klemmt stark - 2025 Notiz',
    });

    final error = InspectionDoorError(
      inspectionDoorId: junctionId,
      errorCode: 'DEF_LOCK_01',
      notes: 'Schloss defekt',
      severity: 'high',
      quantity: 1,
      resolutionStatus: 'open',
    );
    await DatabaseService.insertInspectionDoorError(error);

    // 2. Prepare new Wartung Auftrag for 2026 cloning from latest inspection
    final newInspId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-WARTUNG-CYCLE-01',
      objectAddress: 'Bavariaring 10, 80336 München',
      clientName: 'Bavaria Real Estate',
      jobNumber: 'WARTUNG-2026-01',
      date: DateTime(2026, 5, 12),
      orderType: 'Wartung',
      cloneDoors: true,
    );

    expect(newInspId, isPositive);
    expect(newInspId, isNot(baseInspId));

    final newInsp = await DatabaseService.getInspectionById(newInspId);
    expect(newInsp!['orderType'], 'Wartung');
    expect(newInsp['repairDate'], isNull);

    final newJunctions = await DatabaseService.getInspectionDoorsByInspectionId(newInspId);
    expect(newJunctions.length, 1);
    final clonedDoorId = newJunctions.first['doorId'] as int;
    final db = await DatabaseService.getDb();
    final doorMaps = await db.query('doors', where: 'id = ?', whereArgs: [clonedDoorId]);
    expect(doorMaps.isNotEmpty, isTrue);
    final clonedDoor = Door.fromMap(doorMaps.first);

    expect(clonedDoor.doorNumber, 'T-101');
    expect(clonedDoor.roomDesignation, 'Serverraum');
    // Wartung rule: Notes in junction must start empty for the new inspection cycle
    final junctionNote = (newJunctions.first['notes']?.toString() ?? '');
    expect(junctionNote.isEmpty, isTrue);

    // Wartung rule: Errors must start empty for the new inspection cycle
    final errors = await DatabaseService.getDetailedErrorsForInspectionDoor(newJunctions.first['id'] as int);
    expect(errors.isEmpty, isTrue);
  });

  test('Reparatur Auftrag cloned from latest inspection preserves notes and errors as guide', () async {
    // 1. Prepare initial inspection with open defect
    final baseInspId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-REP-CYCLE-01',
      objectAddress: 'Sonnenstr. 5, 80331 München',
      clientName: 'City Center GmbH',
      jobNumber: 'WARTUNG-2026-BASE',
      date: DateTime(2026, 3, 1),
      orderType: 'Wartung',
      cloneDoors: false,
    );

    final door = _createTestDoor(
      doorNumber: 'T-202',
      roomDesignation: 'Fluchtweg EG',
      notes: 'Türschließer verliert Öl',
      doorFunctionOK: false,
    );
    final doorId = await DatabaseService.insertDoor(door);
    final junctionId = await DatabaseService.insertInspectionDoor({
      'inspectionId': baseInspId,
      'doorId': doorId,
      'status': 'Pending',
      'notes': 'Türschließer verliert Öl',
    });

    final error = InspectionDoorError(
      inspectionDoorId: junctionId,
      errorCode: 'CLOSER_LEAK_01',
      notes: 'Hydrauliköl läuft aus',
      severity: 'critical',
      quantity: 1,
      resolutionStatus: 'open',
    );
    await DatabaseService.insertInspectionDoorError(error);

    // 2. Manager creates Reparatur Auftrag based on this project
    final repDate = DateTime(2026, 3, 15);
    final repInspId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: 'PRJ-REP-CYCLE-01',
      objectAddress: 'Sonnenstr. 5, 80331 München',
      clientName: 'City Center GmbH',
      jobNumber: 'REP-2026-02',
      date: DateTime(2026, 3, 1),
      orderType: 'Reparatur',
      repairDate: repDate,
      cloneDoors: true,
    );

    expect(repInspId, isPositive);
    final repInsp = await DatabaseService.getInspectionById(repInspId);
    expect(repInsp!['orderType'], 'Reparatur');
    expect(repInsp['repairDate'], repDate.toIso8601String());

    final repJunctions = await DatabaseService.getInspectionDoorsByInspectionId(repInspId);
    expect(repJunctions.length, 1);
    final repDoorId = repJunctions.first['doorId'] as int;
    final db = await DatabaseService.getDb();
    final repDoorMaps = await db.query('doors', where: 'id = ?', whereArgs: [repDoorId]);
    expect(repDoorMaps.isNotEmpty, isTrue);
    final repDoor = Door.fromMap(repDoorMaps.first);

    expect(repDoor.doorNumber, 'T-202');
    // Reparatur rule: Notes and errors preserved as guide for repair technician
    final repJunctionNote = (repJunctions.first['notes']?.toString() ?? '');
    expect(repJunctionNote, 'Türschließer verliert Öl');

    final repErrors = await DatabaseService.getDetailedErrorsForInspectionDoor(repJunctions.first['id'] as int);
    expect(repErrors.length, 1);
    expect(repErrors.first['errorCode'], 'CLOSER_LEAK_01');
    expect(repErrors.first['notes'], 'Hydrauliköl läuft aus');
  });

  test('Consolidate parallel Wartung & Reparatur cards into a single Erledigt card', () async {
    final jobNumber = 'JOB-CONSOLIDATE-2026';
    final projectNumber = 'PRJ-CONSOLIDATE-01';

    // 1. Create Wartung job
    final wartungId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: projectNumber,
      objectAddress: 'Hauptstr. 100, Hamburg',
      clientName: 'Hanseatic Living GmbH',
      jobNumber: jobNumber,
      date: DateTime(2026, 4, 1),
      orderType: 'Wartung',
      cloneDoors: false,
    );

    final door = _createTestDoor(
      doorNumber: 'T-303',
      roomDesignation: 'Haupteingang',
      notes: 'Scharnier locker',
      doorFunctionOK: false,
    );
    final doorId = await DatabaseService.insertDoor(door);
    await DatabaseService.insertInspectionDoor({
      'inspectionId': wartungId,
      'doorId': doorId,
      'status': 'Pending',
      'notes': 'Scharnier locker',
    });

    // 2. Create parallel Reparatur job for the same jobNumber
    final repDate = DateTime(2026, 4, 15);
    final reparaturId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: projectNumber,
      objectAddress: 'Hauptstr. 100, Hamburg',
      clientName: 'Hanseatic Living GmbH',
      jobNumber: jobNumber,
      date: DateTime(2026, 4, 1),
      orderType: 'Reparatur',
      repairDate: repDate,
      cloneDoors: true,
    );

    // Before consolidation: 2 separate jobs exist for this jobNumber
    final beforeJobs = await DatabaseService.searchInspections(jobNumber);
    expect(beforeJobs.length, 2);

    // 3. Manager consolidates when Reparatur report is imported / marked as completed
    final consolidatedId = await DatabaseService.consolidateJobToErledigt(
      jobNumber: jobNumber,
      projectNumber: projectNumber,
    );

    expect(consolidatedId, isNotNull);

    // After consolidation: Exactly 1 card exists for this jobNumber with orderType = 'Erledigt'
    final afterJobs = await DatabaseService.searchInspections(jobNumber);
    expect(afterJobs.length, 1);
    final finalJob = afterJobs.first;
    expect(finalJob['orderType'], 'Erledigt');
    expect(finalJob['jobNumber'], jobNumber);
    expect(finalJob['repairDate'], isNotNull);
    expect(finalJob['repairDate'], contains('2026-04-15'));
    expect(finalJob['date'], contains('2026-04-01'));

    // Verify door junctions are preserved
    final finalJunctions = await DatabaseService.getInspectionDoorsByInspectionId(finalJob['inspectionId'] as int);
    expect(finalJunctions.length, 1);
    expect(finalJunctions.first['doorId'], doorId);

    // 4. Verify Door History ("Tür-Inventar" Audit Trail) has the complete history
    final historyData = await DatabaseService.getDoorHistoryData(doorId: doorId);
    expect(historyData, isNotNull);
    final historyItems = historyData!['historyItems'] as List;
    expect(historyItems.isNotEmpty, isTrue);
    final firstHist = historyItems.first as Map<String, dynamic>;
    final inspData = firstHist['inspection'] as Map<String, dynamic>;
    expect(inspData['jobNumber'], jobNumber);
    expect(inspData['orderType'], 'Erledigt');
    expect(inspData['repairDate'], isNotNull);
  });

  test('Inspector processes Reparatur and exports package; Manager imports it and card auto-consolidates into single Erledigt card', () async {
    final jobNumber = 'JOB-EXPORT-IMPORT-2026';
    final projectNumber = 'PRJ-AUTO-CONSOLIDATE-02';

    // 1. Master DB: Manager prepares Wartung and parallel Reparatur Aufträge
    final wartungId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: projectNumber,
      objectAddress: 'Leopoldstr. 200, München',
      clientName: 'Alpha Real Estate',
      jobNumber: jobNumber,
      date: DateTime(2026, 6, 1),
      orderType: 'Wartung',
      cloneDoors: false,
    );

    final door = _createTestDoor(
      doorNumber: 'T-999',
      roomDesignation: 'Technikzentrale',
      notes: 'Türschloss defekt',
      doorFunctionOK: false,
    );
    final doorId = await DatabaseService.insertDoor(door);
    final wartungJuncId = await DatabaseService.insertInspectionDoor({
      'inspectionId': wartungId,
      'doorId': doorId,
      'status': 'Failed',
      'notes': 'Türschloss defekt',
    });

    await DatabaseService.insertInspectionDoorError(InspectionDoorError(
      inspectionDoorId: wartungJuncId,
      errorCode: 'DEF_LOCK_DEFECT',
      notes: 'Schloss schnappt nicht ein',
      severity: 'high',
      quantity: 1,
      resolutionStatus: 'open',
    ));

    // Parallel Reparatur order created by Manager
    final reparaturId = await DatabaseService.createAuftragFromLatestInspection(
      projectNumber: projectNumber,
      objectAddress: 'Leopoldstr. 200, München',
      clientName: 'Alpha Real Estate',
      jobNumber: jobNumber,
      date: DateTime(2026, 6, 1),
      orderType: 'Reparatur',
      repairDate: DateTime(2026, 6, 10),
      cloneDoors: true,
    );

    // Inspector marks the defect as resolved during repair
    final repJunctions = await DatabaseService.getInspectionDoorsByInspectionId(reparaturId);
    final repErrors = await DatabaseService.getDetailedErrorsForInspectionDoor(repJunctions.first['id'] as int);
    expect(repErrors.length, 1);
    final repErrorId = repErrors.first['id'] as int;
    await DatabaseService.insertInspectionDoorError(InspectionDoorError(
      id: repErrorId,
      inspectionDoorId: repJunctions.first['id'] as int,
      errorCode: 'DEF_LOCK_DEFECT',
      notes: 'Schloss repariert & gefettet',
      severity: 'high',
      quantity: 1,
      resolutionStatus: 'Resolved',
    ));

    // Verify 2 parallel cards in Master DB before inspector syncs
    final beforeImport = await DatabaseService.searchInspections(jobNumber);
    expect(beforeImport.length, 2);

    // 2. Export package containing the Reparatur job (simulate inspector export)
    final tempDbPath = 'test_reparatur_export_${DateTime.now().millisecondsSinceEpoch}.db';
    await DatabaseService.exportJobPackage([reparaturId], destinationPath: tempDbPath);

    // 3. Manager imports the exported package via importAndMergePackage
    final report = await DatabaseService.importAndMergePackage(tempDbPath);
    expect(report.packageName, isNotEmpty);

    // 4. Assert: Exactly 1 card remains for this jobNumber in Master DB with orderType = 'Erledigt'
    final afterImport = await DatabaseService.searchInspections(jobNumber);
    expect(afterImport.length, 1, reason: 'Parallel Wartung and Reparatur should auto-consolidate into 1 card upon Manager import');

    final consolidatedJob = afterImport.first;
    expect(consolidatedJob['orderType'], 'Erledigt');
    expect(consolidatedJob['jobNumber'], jobNumber);
    expect(consolidatedJob['repairDate'], isNotNull);
    expect(consolidatedJob['repairDate'], contains('2026-06-10'));
    expect(consolidatedJob['date'], contains('2026-06-01'));

    // 5. Assert: The door on the consolidated card has EXACTLY 1 error entry with status Resolved (NO DUPLICATE open error)
    final consolidatedJunctions = await DatabaseService.getInspectionDoorsByInspectionId(consolidatedJob['inspectionId'] as int);
    expect(consolidatedJunctions.length, 1);
    final consolidatedErrors = await DatabaseService.getDetailedErrorsForInspectionDoor(consolidatedJunctions.first['id'] as int);
    expect(consolidatedErrors.length, 1, reason: 'Should only have 1 defect record with latest state, not duplicate open and resolved copies');
    expect(consolidatedErrors.first['errorCode'], 'DEF_LOCK_DEFECT');
    expect(consolidatedErrors.first['resolutionStatus'], 'Resolved');
    expect(consolidatedErrors.first['notes'], 'Schloss repariert & gefettet');

    // 6. Door History audit trail check
    final historyData = await DatabaseService.getDoorHistoryData(doorId: doorId);
    expect(historyData, isNotNull);
    final historyItems = historyData!['historyItems'] as List;
    expect(historyItems.isNotEmpty, isTrue);

    // Clean up temporary exported db file
    final tempFile = File(tempDbPath);
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }
  });
}
