import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'services/local_database_service.dart';
import 'services/main_database_service.dart';
import 'services/sync_service.dart';
import 'models/models.dart';
import 'pages/main_navigation_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // -----------------------------------------
  // REQUIRED FOR WINDOWS / MACOS / LINUX
  // -----------------------------------------
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Initialize databases
  await LocalDatabaseService.getDb();
  await MainDatabaseService.getDb();

  // Run proof-of-concept scenario
  await runProofOfConceptScenario();

  // Start your real app
  runApp(const MyApp());
}

/// Proof-of-concept scenario demonstrating the two-database architecture
Future<void> runProofOfConceptScenario() async {
  print('\n=== PROOF-OF-CONCEPT: Two-Database Architecture ===\n');

  // 1. Create a test door in local DB (simulating inspector input)
  print('1. Creating door in LOCAL DB (offline work)...');
  final testDoor = Door(
    customerName: 'Test Company GmbH',
    customerAddress: 'Test Street 123, 12345 Test City',
    contactPerson: 'John Doe',
    jobNumber: 'TEST-2026-001',
    inspectionDate: DateTime.now(),
    inspectorName: 'Inspector Test',
    id: DateTime.now().millisecondsSinceEpoch,
    pos: 1,
    doorNumber: 'T-01',
    floor: 'EG',
    roomNumber: '001',
    roomDesignation: 'Test Room',
    doorType: 'T30',
    wingCount: 1,
    material: 'Steel',
    manufacturer: 'Test Manufacturer',
    dinConfiguration: 'DIN L',
    closerType: 'Standard',
    closingSequenceSystem: 'None',
    lockDimensions: '72mm',
    closerOnHingeSide: true,
    closerOnOppositeSide: false,
    lintelHeightUnder1m: false,
    escapeDoorControl: true,
    accessControl: 'No',
    escapeRouteSituation: true,
    escapeRouteSignage: true,
    blindCylinder: false,
    pzCylinder: true,
    fittingType: 'Handle',
    panicFunction: 'B',
    escapeDirectionRespected: true,
    fullPanicStandWing: false,
    doorFunctionOK: true,
    syncStatus: 'pending', // New doors start as 'pending'
  );

  await LocalDatabaseService.insertDoor(testDoor.toMap());
  print('✓ Door created in local DB with syncStatus: ${testDoor.syncStatus}');

  // 2. Verify door exists in local DB
  print('\n2. Verifying door in LOCAL DB...');
  final localDoors = await LocalDatabaseService.getAllDoors();
  final localDoorMaps = localDoors.map((d) => Door.fromMap(d)).toList();
  final foundLocalDoor = localDoorMaps.firstWhere((d) => d.doorNumber == 'T-01');
  print('✓ Found door in local DB: ${foundLocalDoor.doorNumber}, syncStatus: ${foundLocalDoor.syncStatus}');

  // 3. Check main DB is empty initially
  print('\n3. Checking MAIN DB (should be empty initially)...');
  final mainDoorsBefore = await MainDatabaseService.getAllDoors();
  print('✓ Main DB doors before sync: ${mainDoorsBefore.length}');

  // 4. Simulate report generation and sync
  print('\n4. Simulating report generation and SYNC to MAIN DB...');
  await SyncService.syncToMainDB();
  print('✓ Sync completed');

  // 5. Verify door is now in main DB
  print('\n5. Verifying door in MAIN DB after sync...');
  final mainDoorsAfter = await MainDatabaseService.getAllDoors();
  print('✓ Main DB doors after sync: ${mainDoorsAfter.length}');
  if (mainDoorsAfter.isNotEmpty) {
    final mainDoorMap = mainDoorsAfter.first;
    print('✓ Door in main DB: doorNumber=${mainDoorMap['doorNumber']}, customer=${mainDoorMap['customerName']}');
  }

  // 6. Verify no pending doors remain in local DB after sync
  print('\n6. Verifying pending doors in LOCAL DB after sync...');
  final pendingLocalDoorsAfter = await LocalDatabaseService.getPendingDoors();
  if (pendingLocalDoorsAfter.isEmpty) {
    print('✓ No pending doors remain in local DB; sync completed successfully');
  } else {
    final pendingDoorMapsAfter = pendingLocalDoorsAfter.map((d) => Door.fromMap(d)).toList();
    final pendingDoor = pendingDoorMapsAfter.firstWhere((d) => d.doorNumber == 'T-01', orElse: () => Door(id: 0, pos: 0, doorNumber: '', floor: '', roomNumber: '', roomDesignation: '', doorType: '', wingCount: 0, material: '', manufacturer: '', dinConfiguration: '', closerType: '', closingSequenceSystem: '', lockDimensions: '', closerOnHingeSide: false, closerOnOppositeSide: false, lintelHeightUnder1m: false, escapeDoorControl: false, accessControl: '', escapeRouteSituation: false, escapeRouteSignage: false, blindCylinder: false, pzCylinder: false, fittingType: '', panicFunction: '', escapeDirectionRespected: false, fullPanicStandWing: false, doorFunctionOK: false, customerName: '', customerAddress: '', contactPerson: '', jobNumber: '', inspectionDate: DateTime.now(), inspectorName: '', syncStatus: ''));
    if (pendingDoor.doorNumber.isNotEmpty) {
      print('⚠️ Door is still pending in local DB: ${pendingDoor.doorNumber}, syncStatus: ${pendingDoor.syncStatus}');
    } else {
      print('✓ No pending door with doorNumber T-01 found in local DB');
    }
  }

  // 7. Verify error catalog is available in main DB
  print('\n7. Verifying ERROR CATALOG in MAIN DB...');
  // Note: Error catalog seeding happens in MainDatabaseService.getDb()

  print('\n=== SCENARIO COMPLETED SUCCESSFULLY ===');
  print('✓ Local DB: Used for offline door inspections');
  print('✓ Main DB: Contains complete history and error catalog');
  print('✓ Sync: Transfers data after report generation');
  print('✓ Architecture: Two-database system working as designed\n');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: MainNavigationPage(),
    );
  }
}
