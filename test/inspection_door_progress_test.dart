import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Inspection Door Progress & Status Tracking Tests', () {
    test('LocalDatabaseService tracks door inspection status and notes', () async {
      final db = await LocalDatabaseService.getDb();
      
      // Clean test data
      await db.delete('inspection_doors');
      await db.delete('doors');
      await db.delete('inspections');

      // 1. Insert Inspection
      final inspectionId = await db.insert('inspections', {
        'jobNumber': 'INSP-PROG-001',
        'clientName': 'Test Progress GmbH',
        'objectAddress': 'Teststraße 1',
        'date': '2026-09-27',
      });

      // 2. Insert 2 Doors
      final door1Id = await db.insert('doors', {
        'doorNumber': 'T-01',
        'floor': 'EG',
        'roomDesignation': 'Flur',
      });
      final door2Id = await db.insert('doors', {
        'doorNumber': 'T-02',
        'floor': 'EG',
        'roomDesignation': 'Büro',
      });

      // 3. Link Doors to Inspection
      await db.insert('inspection_doors', {
        'inspectionId': inspectionId,
        'doorId': door1Id,
        'status': 'Pending',
      });
      await db.insert('inspection_doors', {
        'inspectionId': inspectionId,
        'doorId': door2Id,
        'status': 'Pending',
      });

      // Initial statuses check
      var statuses = await LocalDatabaseService.getDoorInspectionStatuses(inspectionId);
      expect(statuses[door1Id], 'Pending');
      expect(statuses[door2Id], 'Pending');

      // Process door 1 (Inspector finishes inspection and saves)
      await LocalDatabaseService.updateInspectionDoorStatus(
        inspectionId: inspectionId,
        doorId: door1Id,
        status: 'Inspected',
        notes: 'Door inspection completed without issues',
      );

      // Verify statuses after processing door 1
      statuses = await LocalDatabaseService.getDoorInspectionStatuses(inspectionId);
      expect(statuses[door1Id], 'Inspected');
      expect(statuses[door2Id], 'Pending');

      // Verify inspection_door row notes updated
      final rows = await db.query(
        'inspection_doors',
        where: 'inspectionId = ? AND doorId = ?',
        whereArgs: [inspectionId, door1Id],
      );
      expect(rows.first['status'], 'Inspected');
      expect(rows.first['notes'], 'Door inspection completed without issues');
    });

    test('DatabaseService (Manager DB) tracks door inspection status', () async {
      final db = await DatabaseService.getDb();
      
      // Clean test data
      await db.delete('inspection_doors');
      await db.delete('doors');
      await db.delete('inspections');

      // 1. Insert Inspection
      final inspectionId = await db.insert('inspections', {
        'jobNumber': 'MGR-PROG-001',
        'clientName': 'Manager Test AG',
        'objectAddress': 'Musterweg 10',
        'date': '2026-09-27',
      });

      // 2. Insert Door
      final doorId = await db.insert('doors', {
        'doorNumber': 'M-01',
        'floor': '1.OG',
        'roomDesignation': 'Lager',
      });

      // 3. Link Door
      await db.insert('inspection_doors', {
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': '',
      });

      // Initial check
      var statuses = await DatabaseService.getDoorInspectionStatuses(inspectionId);
      expect(statuses[doorId], '');

      // Mark inspected
      await DatabaseService.updateInspectionDoorStatus(
        inspectionId: inspectionId,
        doorId: doorId,
        status: 'Inspected',
      );

      statuses = await DatabaseService.getDoorInspectionStatuses(inspectionId);
      expect(statuses[doorId], 'Inspected');
    });
  });
}
