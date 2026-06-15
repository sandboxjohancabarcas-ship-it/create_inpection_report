import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/models/door.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await LocalDatabaseService.closeDb();
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'working.db');
    if (await File(path).exists()) await File(path).delete();
  });

  group('LocalDatabaseService Tests', () {
    test('createNewDoorInField should generate TEMP- alias', () async {
      const String testDoorNumber = '101-NEW';
      final int id = await LocalDatabaseService.createNewDoorInField(testDoorNumber);
      
      final doors = await LocalDatabaseService.getAllDoors();
      final newDoor = doors.firstWhere((d) => d.id == id);
      
      expect(newDoor.doorNumber, equals(testDoorNumber));
      expect(newDoor.doorAlias, startsWith('TEMP-'));
      expect(newDoor.doorAlias, contains(testDoorNumber));
    });

    test('purgeExportedData should only remove specified inspections', () async {
      // 1. Setup: Create two inspections
      await LocalDatabaseService.insertInspection({
        'inspectionId': 1,
        'jobNumber': 'JOB-001',
      });
      await LocalDatabaseService.insertInspection({
        'inspectionId': 2,
        'jobNumber': 'JOB-002',
      });

      // Link a door to inspection 1
      final doorId = await LocalDatabaseService.insertDoor(Door(
        id: null, // Pass null for auto-incrementing ID
        pos: 1,
        doorNumber: 'D1',
        doorAlias: 'A1',
        floor: 'EG',
        roomNumber: '101',
        roomDesignation: 'Büro',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Dorma',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: 'Standard',
        lockDimensions: 'PZ 92',
        closerOnHingeSide: true,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: true,
        accessControl: 'RFID',
        escapeRouteSituation: true,
        escapeRouteSignage: true,
        blindCylinder: false,
        pzCylinder: true,
        fittingType: 'Drücker',
        panicFunction: 'E',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
      ));
      await LocalDatabaseService.insertInspectionDoor({
        'inspectionId': 1,
        'doorId': doorId,
        'status': 'Done'
      });

      // 2. Purge only inspection 1
      await LocalDatabaseService.purgeExportedData([1]);

      // 3. Verify
      final db = await LocalDatabaseService.getDb();
      final inspections = await db.query('inspections');
      final remainingDoors = await LocalDatabaseService.getAllDoors();

      expect(inspections.length, equals(1), reason: 'Job 2 should remain');
      expect(inspections.first['inspectionId'], equals(2));
      expect(remainingDoors, isEmpty, reason: 'Door D1 should be purged as it is no longer linked to any inspection');
    });
  });
}
