import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/models/models.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  // Initialize FFI for terminal execution (Windows/Linux/macOS)
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Master Database Seeding Routine', () {
    test('Populate 10 complex inspections for Multi-selection testing', () async {
      final db = await DatabaseService.getDb();
      
      print('--- Starting Master Data Seed ---');
      
      // Clean slate for testing environment (Master DB)
      await db.delete('inspection_door_errors');
      await db.delete('inspection_doors');
      await db.delete('inspections');
      await db.delete('doors');
      // Note: We keep the existing Approved error_catalog but will add 'Pending' ones

      for (int i = 1; i <= 10; i++) {
        final String clientSuffix = i.toString().padLeft(2, '0');
        
        // 1. Insert Inspection
        final inspectionId = await DatabaseService.insertInspection({
          'inspectionId': i,
          'clientName': 'Kunde Alpha $clientSuffix',
          'objectAddress': 'Teststraße $i, 12345 Berlin',
          'jobNumber': 'AUFTRAG-2024-$clientSuffix',
          'date': '2024-06-$clientSuffix',
          'inspectorName': 'Techniker ${i % 2 == 0 ? "A" : "B"}',
        });

        // 2. Create a Door object
        final door = Door(
          id: i,
          pos: 1,
          doorAlias: 'DOOR-ALIAS-$clientSuffix',
          doorNumber: 'T-00$i',
          floor: 'Etage ${i % 3}',
          roomNumber: 'R.$i.01',
          roomDesignation: 'Technikraum',
          doorType: 'T30',
          wingCount: 1,
          material: 'Stahl',
          manufacturer: 'Standard Hersteller',
          dinConfiguration: 'DIN L',
          closerType: 'Standard',
          closingSequenceSystem: 'Keine',
          lockDimensions: '72mm',
          closerOnHingeSide: true,
          closerOnOppositeSide: false,
          lintelHeightInsideOver1m: false,
          escapeDoorControl: false,
          accessControl: 'Nein',
          escapeRouteSituation: true,
          escapeRouteSignage: true,
          blindCylinder: false,
          pzCylinder: true,
          fittingType: 'Drückergarnitur',
          panicFunction: 'E',
          escapeDirectionRespected: true,
          fullPanicStandWing: false,
          doorFunctionOK: i % 3 != 0, // Some doors fail for visual variety
        );

        // 3. Insert Door into Master DB
        await DatabaseService.insertDoor(door);

        // 4. Create the Junction record (InspectionDoor)
        final junctionId = await DatabaseService.insertInspectionDoor({
          'inspectionId': inspectionId,
          'doorId': door.id,
          'status': door.doorFunctionOK ? 'OK' : 'Mangelhaft',
          'notes': 'Seed data for multi-selection test.',
        });

        // 5. Link a Standard "Approved" Error (Error ID 1 usually exists from seed)
        await DatabaseService.insertInspectionDoorError(InspectionDoorError(
          inspectionDoorId: junctionId,
          errorId: 1,
          errorCode: 'STD-001',
          quantity: 1,
          severity: 'medium',
          notes: 'Standardwartung durchgeführt.',
          resolutionStatus: 'closed',
        ));

        // 6. Simulate a "New Error Request" (Pending entry in catalog)
        // This mimics the 'proposeNewError' logic
        final pendingErrorId = await db.insert('error_catalog', {
          'code': 'REQ-2024-$clientSuffix',
          'description': 'Spezifischer Sonderfehler an Tür $clientSuffix',
          'category': 'Sonderprüfung',
          'status': 'Pending',
          'requestedBy': 'Seed Script',
          'requestDate': DateTime.now().toIso8601String(),
          'sourceInspectionDoorId': junctionId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        // 7. Link the pending error to the door instance
        await DatabaseService.insertInspectionDoorError(InspectionDoorError(
          inspectionDoorId: junctionId,
          errorId: pendingErrorId,
          errorCode: 'REQ-2024-$clientSuffix',
          quantity: 1,
          severity: 'high',
          notes: 'Dringende Ersatzteilbestellung erforderlich.',
          resolutionStatus: 'open',
        ));

        print('Created Job $i: Kunde Alpha $clientSuffix (1 Door, 2 Errors)');
      }

      // Final verification
      final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inspections')) ?? 0;
      expect(count, 10);
      print('--- Seed Complete: $count Inspections created in Master DB ---');
    });
  });
}
