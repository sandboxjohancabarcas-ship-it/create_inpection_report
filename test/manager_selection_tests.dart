import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/models/models.dart';
import 'dart:io';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await DatabaseService.closeDb();
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/door_inspection.db';
    if (await File(path).exists()) await File(path).delete();
    await DatabaseService.getDb();
  });

  tearDown(() async {
    await DatabaseService.closeDb();
  });

  /// Helper to create a valid Door object for testing with German UX strings
  Door createTestDoor({required int id, required String alias, required String number, required int pos}) {
    return Door(
      id: id,
      pos: pos,
      doorAlias: alias,
      doorNumber: number,
      floor: 'EG',
      roomNumber: '101',
      roomDesignation: 'Testraum',
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
  }

  group('Manager Selection & Search Tests (Block 3)', () {
    
    // EASY: Verify the new search-by-address capability (UX in German)
    test('Easy: Search inspections by object address', () async {
      await DatabaseService.insertInspection({
        'inspectionId': 1,
        'clientName': 'Kunde A',
        'objectAddress': 'Hauptstrasse 10',
        'auftragsnummer': 'JOB-100',
        'date': '2023-10-01',
        'contactPerson': 'Hr. Mustermann',
        'inspectorName': 'Prüfer 1'
      });

      final results = await DatabaseService.searchInspections('Hauptstrasse');
      expect(results.length, equals(1));
      expect(results.first['clientName'], equals('Kunde A'));
    });

    // MEDIUM: Verify the multi-selection ID logic
    test('Medium: Batch selection set consistency', () {
      // Simulating the UI's _selectedInspectionIds behavior
      final Set<int> selectedIds = {};
      final List<Map<String, dynamic>> searchResults = [
        {'inspectionId': 101},
        {'inspectionId': 102},
        {'inspectionId': 103},
      ];

      // Simulate "Select All Results" logic
      for (var item in searchResults) {
        selectedIds.add(item['inspectionId'] as int);
      }

      expect(selectedIds.length, equals(3));
      expect(selectedIds.contains(101), isTrue);
      
      // Simulate "Deselect All"
      selectedIds.clear();
      expect(selectedIds, isEmpty);
    });

    // HARD: Verify relational data preparation for multiple selected jobs
    test('Hard: Aggregate relational data for multiple inspections', () async {
      
      // 1. Setup two inspections via Service with all required German metadata
      await DatabaseService.insertInspection({
        'inspectionId': 1, 
        'auftragsnummer': 'JOB-1', 
        'clientName': 'Kunde 1', 
        'date': '2024-01-01',
        'objectAddress': 'Teststraße 1',
        'contactPerson': 'Ansprechpartner 1'
      });
      await DatabaseService.insertInspection({
        'inspectionId': 2, 
        'auftragsnummer': 'JOB-2', 
        'clientName': 'Kunde 2', 
        'date': '2024-01-02',
        'objectAddress': 'Teststraße 2',
        'contactPerson': 'Ansprechpartner 2'
      });

      // 2. Setup two doors using the Service to ensure all required fields are set
      await DatabaseService.insertDoor(createTestDoor(id: 10, alias: 'ALIAS-1', number: 'T1', pos: 1));
      await DatabaseService.insertDoor(createTestDoor(id: 20, alias: 'ALIAS-2', number: 'T2', pos: 2));

      // 3. Setup junctions via Service (Linking doors to jobs)
      // This ensures 'status', 'notes', and 'attachments' are handled correctly
      await DatabaseService.insertInspectionDoor({
        'id': 100, 'inspectionId': 1, 'doorId': 10, 'status': 'open', 'notes': '', 'attachments': ''
      });
      await DatabaseService.insertInspectionDoor({
        'id': 200, 'inspectionId': 2, 'doorId': 20, 'status': 'open', 'notes': '', 'attachments': ''
      });

      // 4. Verify batch retrieval logic used for "Paket laden"
      final selectedIds = [1, 2];
      final aggregatedDoors = await DatabaseService.getDoorsByInspectionIds(selectedIds);

      expect(aggregatedDoors.length, equals(2), reason: 'Should fetch doors from all selected jobs');
      final numbers = aggregatedDoors.map((d) => d.doorNumber).toList();
      expect(numbers, containsAll(['T1', 'T2']));
    });
  });
}