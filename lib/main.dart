import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
//import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';   // <-- REQUIRED
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'services/database_service.dart';
import 'models/models.dart';
import 'pages/new_door_page.dart';
import 'pages/DoorListPage.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // -----------------------------------------
  // REQUIRED FOR WINDOWS / MACOS / LINUX
  // -----------------------------------------
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // -------------------------------
  // CRUD TEST FOR DOORS (runs once)
  // -------------------------------

final door = Door(
  id: 1,
  pos: 101,
  doorNumber: 'D-12',
  floor: '1',
  roomNumber: '101',
  roomDesignation: 'Office',
  doorType: 'T30',
  wingCount: 1,
  material: 'Steel',
  manufacturer: 'Hörmann',
  dinConfiguration: 'DIN L',
  closerType: 'Standard',
  closingSequenceSystem: 'None',
  lockDimensions: '72mm',
  closerOnHingeSide: true,
  closerOnOppositeSide: false,
  lintelHeightUnder1m: false,
  escapeDoorControl: true,
  accessControl: 'None',
  escapeRouteSituation: true,
  escapeRouteSignage: true,
  blindCylinder: false,
  pzCylinder: true,
  fittingType: 'Drückergarnitur',
  panicFunction: 'B',
  escapeDirectionRespected: true,
  fullPanicStandWing: false,
  doorFunctionOK: true,
);


  print('--- INSERT TEST ---');
  await DatabaseService.insertDoor(door);

  print('--- QUERY TEST ---');
  final doors = await DatabaseService.getAllDoors();
  print('Doors in DB: ${doors.length}');
  print('First door: ${doors.first.doorNumber}');

  print('--- UPDATE TEST ---');
  final updatedDoor = door.copyWith(roomDesignation: 'Conference Room');
  await DatabaseService.updateDoor(updatedDoor);

  final updatedDoors = await DatabaseService.getAllDoors();
  print('Updated room: ${updatedDoors.first.roomDesignation}');

  print('--- DELETE TEST ---');
  await DatabaseService.deleteDoor(1);

  final afterDelete = await DatabaseService.getAllDoors();
  print('Doors after delete: ${afterDelete.length}');

  // -------------------------------
  // START YOUR REAL APP
  // -------------------------------
  runApp(const MyApp());
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
      home: DoorListPage(),
    );
  }
}
