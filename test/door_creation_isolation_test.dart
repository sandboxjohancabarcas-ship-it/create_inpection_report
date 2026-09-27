import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.current.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.current.path;
  }
}

Door _makeDoor({
  int? id,
  required int pos,
  required String doorNumber,
  required String floor,
  required String roomNumber,
  required String roomDesignation,
  required String doorType,
  required int wingCount,
  required String material,
  required String manufacturer,
  required bool doorFunctionOK,
  required String notes,
}) {
  final alias = Door.generateAlias(
    projectNumber: 'P-002098',
    pos: pos,
    floor: floor,
    doorNumber: doorNumber,
  );
  return Door(
    id: id,
    pos: pos,
    doorAlias: alias,
    provisionalAlias: alias,
    doorNumber: doorNumber,
    floor: floor,
    roomNumber: roomNumber,
    roomDesignation: roomDesignation,
    doorType: doorType,
    wingCount: wingCount,
    material: material,
    manufacturer: manufacturer,
    dinConfiguration: 'DIN L',
    closerType: 'TS93',
    closingSequenceSystem: 'None',
    lockDimensions: 'PZ 72/65',
    closerOnHingeSide: false,
    closerOnOppositeSide: true,
    lintelHeightInsideOver1m: false,
    lintelHeightOutsideOver1m: false,
    escapeDoorControl: 'Nein',
    accessControl: 'Nein',
    escapeRouteSituation: false,
    escapeRouteSignage: false,
    blindCylinder: false,
    pzCylinder: false,
    fittingType: 'Drücker',
    panicFunction: 'Nein',
    escapeDirectionRespected: false,
    fullPanicStandWing: false,
    doorFunctionOK: doorFunctionOK,
    approvalNumber: '?',
    manufacturerNumber: '?',
    manufactureYear: '?',
    notes: notes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  PathProviderPlatform.instance = MockPathProviderPlatform();

  setUp(() async {
    await LocalDatabaseService.closeDb();
    await DatabaseService.closeDb();
    final dbFile = File('working.db');
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  });

  tearDown(() async {
    await LocalDatabaseService.closeDb();
    await DatabaseService.closeDb();
    final dbFile = File('working.db');
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  });

  test('Creating second door does not overwrite first door properties and defects', () async {
    // 1. Create an inspection with 0 doors (e.g. from migrated empty doors file)
    final inspectionId = await LocalDatabaseService.insertInspection({
      'clientName': 'An der Alster 45, Hamburg',
      'objectAddress': 'An der Alster 45, 20099 Hamburg',
      'date': '2026-09-27T10:00:00.000',
      'contactPerson': 'Herr Schmidt',
      'inspectorName': 'Inspektor Test',
      'jobNumber': '26-15493-AB',
      'projectNumber': 'P-002098',
    });

    expect(inspectionId, isNotNull);

    // Verify initial door count is 0
    final initialDoors = await LocalDatabaseService.getDoorsByInspectionId(inspectionId);
    expect(initialDoors.length, 0);

    // 2. Create Door 1 (error-free, properFunction = true)
    final door1 = _makeDoor(
      id: null,
      pos: 1,
      doorNumber: 'Tür 1',
      floor: 'EG',
      roomNumber: '101',
      roomDesignation: 'Empfang',
      doorType: 'T30',
      wingCount: 1,
      material: 'Stahl',
      manufacturer: 'Hörmann',
      doorFunctionOK: true,
      notes: 'Tür 1 ist voll funktionsfähig',
    );

    final door1Id = await LocalDatabaseService.insertDoor(door1);
    expect(door1Id, isNotNull);

    final junction1Id = await LocalDatabaseService.insertInspectionDoor({
      'inspectionId': inspectionId,
      'doorId': door1Id,
      'status': 'Inspected',
      'notes': door1.notes,
    });
    expect(junction1Id, isNotNull);

    // 3. Create Door 2 (with 2 defects, properFunction = false)
    final door2 = _makeDoor(
      id: null,
      pos: 2,
      doorNumber: 'Tür 2',
      floor: '1.OG',
      roomNumber: '201',
      roomDesignation: 'Büro',
      doorType: 'T90',
      wingCount: 2,
      material: 'Holz',
      manufacturer: 'Domoferm',
      doorFunctionOK: false,
      notes: 'Tür 2 Mängel festgestellt',
    );

    final door2Id = await LocalDatabaseService.insertDoor(door2);
    expect(door2Id, isNotNull);
    expect(door2Id, isNot(equals(door1Id)), reason: 'Door 2 must have a distinct ID from Door 1');

    final junction2Id = await LocalDatabaseService.insertInspectionDoor({
      'inspectionId': inspectionId,
      'doorId': door2Id,
      'status': 'Inspected',
      'notes': door2.notes,
    });
    expect(junction2Id, isNotNull);
    expect(junction2Id, isNot(equals(junction1Id)), reason: 'Door 2 junction must be distinct from Door 1 junction');

    // Add 2 defects to Door 2
    await LocalDatabaseService.insertInspectionDoorError(InspectionDoorError(
      inspectionDoorId: junction2Id,
      errorCode: 'M-01',
      notes: 'Tür schließt nicht selbsttätig',
      quantity: 1,
      severity: 'Hoch',
    ));
    await LocalDatabaseService.insertInspectionDoorError(InspectionDoorError(
      inspectionDoorId: junction2Id,
      errorCode: 'M-04',
      notes: 'Dichtung beschädigt',
      quantity: 1,
      severity: 'Mittel',
    ));

    // 4. Verification: Query all doors and their error summaries
    final doors = await LocalDatabaseService.getDoorsByInspectionId(inspectionId);
    expect(doors.length, 2, reason: 'Both Door 1 and Door 2 must exist independently');

    final fetchedDoor1 = doors.firstWhere((d) => d.id == door1Id);
    final fetchedDoor2 = doors.firstWhere((d) => d.id == door2Id);

    // Verify Door 1 properties were NOT overwritten
    expect(fetchedDoor1.doorNumber, 'Tür 1');
    expect(fetchedDoor1.floor, 'EG');
    expect(fetchedDoor1.roomNumber, '101');
    expect(fetchedDoor1.roomDesignation, 'Empfang');
    expect(fetchedDoor1.doorType, 'T30');
    expect(fetchedDoor1.wingCount, 1);
    expect(fetchedDoor1.material, 'Stahl');
    expect(fetchedDoor1.manufacturer, 'Hörmann');
    expect(fetchedDoor1.doorFunctionOK, isTrue);
    expect(fetchedDoor1.notes, 'Tür 1 ist voll funktionsfähig');

    // Verify Door 2 properties are distinct
    expect(fetchedDoor2.doorNumber, 'Tür 2');
    expect(fetchedDoor2.floor, '1.OG');
    expect(fetchedDoor2.roomNumber, '201');
    expect(fetchedDoor2.roomDesignation, 'Büro');
    expect(fetchedDoor2.doorType, 'T90');
    expect(fetchedDoor2.wingCount, 2);
    expect(fetchedDoor2.material, 'Holz');
    expect(fetchedDoor2.manufacturer, 'Domoferm');
    expect(fetchedDoor2.doorFunctionOK, isFalse);
    expect(fetchedDoor2.notes, 'Tür 2 Mängel festgestellt');

    // Verify Error Summaries: Door 1 has 0 errors, Door 2 has 2 errors
    final errorSummaries = await LocalDatabaseService.getDoorErrorSummariesForInspection(inspectionId);
    expect(errorSummaries[door1Id]?.totalErrors ?? 0, 0);
    expect(errorSummaries[door2Id]?.totalErrors, 2);
    expect(errorSummaries[door2Id]?.openErrors, 2);
  });
}
