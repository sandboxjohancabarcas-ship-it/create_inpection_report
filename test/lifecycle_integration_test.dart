import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/models/models.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  // Initialize SQLite FFI for Desktop environment testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Sync Lifecycle Integration Test', () {
    late String masterPath;
    late String localPath;
    late String exportPath;

    setUp(() async {
      // Determine file paths for Master, Local and Export packages
      final dbPath = await getDatabasesPath();
      masterPath = p.join(dbPath, 'door_inspection.db');
      localPath = p.join(dbPath, 'working.db');
      exportPath = p.join(dbPath, 'result_package.db');

      // Clean up to ensure a deterministic test state
      await DatabaseService.closeDb();
      await LocalDatabaseService.closeDb();

      if (await File(masterPath).exists()) await File(masterPath).delete();
      if (await File(localPath).exists()) await File(localPath).delete();
      if (await File(exportPath).exists()) await File(exportPath).delete();

      // Initialize Master DB
      await DatabaseService.getDb();
    });

    tearDown(() async {
      await DatabaseService.closeDb();
      await LocalDatabaseService.closeDb();
    });

    test('Full Lifecycle: Master Prep -> Export -> Inspector Update -> Pruning -> Merge', () async {
      final masterDb = await DatabaseService.getDb();

      // --- PHASE 1: Master Preparation (Manager Side) ---
      // Create an inspection and a door in the Main Database
      const String jobNum = 'JOB-2024-999';
      const String alias = 'KUNDE-A-EG-T01';

      await DatabaseService.insertInspection({
        'inspectionId': 1,
        'clientName': 'Musterbau AG',
        'objectAddress': 'Hauptstraße 1, Berlin',
        'jobNumber': jobNum,
        'date': '2024-06-01',
        'contactPerson': 'Hr. Meier'
      });

      final initialDoor = Door(
        id: 10,
        pos: 1,
        doorAlias: alias,
        doorNumber: 'T01',
        floor: 'EG',
        roomNumber: '101',
        roomDesignation: 'Technikzentrale',
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
        lintelHeightUnder1m: false,
        escapeDoorControl: false,
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
      await DatabaseService.insertDoor(initialDoor);

      // Create junction in Master
      await DatabaseService.insertInspectionDoor({
        'id': 100,
        'inspectionId': 1,
        'doorId': 10,
        'status': 'open',
        'notes': '',
        'attachments': ''
      });

      // --- PHASE 2: Job Export to Inspector ---
      // Manager prepares the job for the inspector
      await LocalDatabaseService.downloadJobPackage(inspectionIds: [1]);
      
      final localDb = await LocalDatabaseService.getDb();
      final localDoors = await LocalDatabaseService.getAllDoors();
      expect(localDoors.length, 1);
      expect(localDoors.first.doorAlias, alias);

      // --- PHASE 3: Inspector Workflow (Local Working DB) ---
      // Inspector updates the door status and adds a specific error
      await localDb.update(
        'inspection_doors', 
        {'status': 'defective', 'notes': 'Tür schließt zu langsam'},
        where: 'id = ?',
        whereArgs: [100]
      );

      // Inspector records an error (using seed catalog ID 1)
      await LocalDatabaseService.insertInspectionDoorError(InspectionDoorError(
        id: 1,
        inspectionDoorId: 100,
        errorId: 1,
        quantity: 1,
        severity: 'high',
        notes: 'Ölaustritt am Schließer',
        resolutionStatus: 'open',
      ));

      // --- PHASE 4: Pruning & Selective Export ---
      // Inspector sends only the selected doors back to the Manager
      await LocalDatabaseService.exportSelectiveJobPackage([10], exportPath);
      
      // --- PHASE 5: Manager Import & Merge ---
      // Manager imports the inspector's result file back into the Main Database
      await DatabaseService.importAndMergePackage(exportPath);

      // --- VERIFICATION ---
      // Verify status and notes were updated via Merge in Master
      final masterJunctions = await masterDb.query('inspection_doors', where: 'id = 100');
      expect(masterJunctions.first['status'], 'defective');
      expect(masterJunctions.first['notes'], 'Tür schließt zu langsam');

      // Verify the error was correctly mapped and inserted in Master
      final masterErrors = await DatabaseService.getErrorsForInspectionDoorIds([100]);
      expect(masterErrors.length, 1);
      expect(masterErrors.first['notes'], 'Ölaustritt am Schließer');
      
      print('✅ Integration Lifecycle Complete: Master Data successfully updated by Inspector Package.');
    });
  });
}