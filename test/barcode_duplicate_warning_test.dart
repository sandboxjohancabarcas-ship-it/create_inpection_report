import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/services/database_service.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

Door createTestDoor({int? id, required String alias, required String number, required int pos, String floor = 'EG', String room = 'Haupteingang'}) {
  return Door(
    id: id,
    pos: pos,
    doorAlias: alias,
    doorNumber: number,
    floor: floor,
    roomNumber: '101',
    roomDesignation: room,
    doorType: 'T30',
    wingCount: 1,
    material: 'Stahl',
    manufacturer: 'Dorma',
    dinConfiguration: 'DIN L',
    closerType: 'TS93',
    closingSequenceSystem: 'None',
    lockDimensions: '72/8',
    closerOnHingeSide: true,
    closerOnOppositeSide: false,
    lintelHeightInsideOver1m: false,
    escapeDoorControl: 'Nein',
    accessControl: 'None',
    escapeRouteSituation: true,
    escapeRouteSignage: true,
    blindCylinder: false,
    pzCylinder: true,
    fittingType: 'Drücker',
    panicFunction: 'E',
    escapeDirectionRespected: true,
    fullPanicStandWing: false,
    doorFunctionOK: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final localDb = await LocalDatabaseService.getDb();
    await localDb.delete('inspection_door_errors');
    await localDb.delete('inspection_doors');
    await localDb.delete('inspections');
    await localDb.delete('doors');

    final masterDb = await DatabaseService.getDb();
    await masterDb.delete('inspection_door_errors');
    await masterDb.delete('inspection_doors');
    await masterDb.delete('inspections');
    await masterDb.delete('doors');
  });

  group('Barcode Duplicate Detection & Warning Tests', () {
    test('LocalDatabaseService findDoorByBarcode accurately finds existing door by barcode/alias', () async {
      final door1 = createTestDoor(
        id: null,
        number: 'T-101',
        alias: 'BARCODE-XYZ-1',
        floor: 'EG',
        room: 'Haupteingang',
        pos: 1,
      );

      final door1Id = await LocalDatabaseService.insertDoor(door1);

      // 1. Searching for same barcode finds door 1
      final found = await LocalDatabaseService.findDoorByBarcode('BARCODE-XYZ-1');
      expect(found, isNotNull);
      expect(found!.id, equals(door1Id));
      expect(found.doorNumber, equals('T-101'));
      expect(found.roomDesignation, equals('Haupteingang'));

      // 2. Searching with excludeDoorId of door1 returns null (allowing same door to keep its own barcode)
      final selfCheck = await LocalDatabaseService.findDoorByBarcode('BARCODE-XYZ-1', excludeDoorId: door1Id);
      expect(selfCheck, isNull);

      // 3. Searching for barcode when editing a second door detects collision with door 1
      final collisionForNewDoor = await LocalDatabaseService.findDoorByBarcode('BARCODE-XYZ-1', excludeDoorId: 9999);
      expect(collisionForNewDoor, isNotNull);
      expect(collisionForNewDoor!.doorNumber, equals('T-101'));
    });

    test('DatabaseService findDoorByBarcode accurately finds existing door by barcode in Master DB', () async {
      final doorMaster = createTestDoor(
        id: null,
        number: 'T-202',
        alias: 'BC-MASTER-99',
        floor: '1.OG',
        room: 'Serverraum',
        pos: 2,
      );

      final masterId = await DatabaseService.insertDoor(doorMaster);

      final match = await DatabaseService.findDoorByBarcode('BC-MASTER-99');
      expect(match, isNotNull);
      expect(match!.id, equals(masterId));
      expect(match.doorNumber, equals('T-202'));
      expect(match.floor, equals('1.OG'));
      expect(match.roomDesignation, equals('Serverraum'));

      // Self-update is allowed
      final selfMatch = await DatabaseService.findDoorByBarcode('BC-MASTER-99', excludeDoorId: masterId);
      expect(selfMatch, isNull);
    });
  });
}
