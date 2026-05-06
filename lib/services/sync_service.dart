// Sync Service: Transfers data from Local DB to Main DB after report generation

import 'local_database_service.dart';
import 'main_database_service.dart';

class SyncService {
  // Sync all pending data from local to main DB
  static Future<void> syncToMainDB() async {
    try {
      // Sync doors
      final localDoors = await LocalDatabaseService.getPendingDoors();
      for (final door in localDoors) {
        await MainDatabaseService.insertDoor(door);
        await LocalDatabaseService.markAsSynced('doors', door['id']);
      }

      // Sync inspections
      final localInspections = await LocalDatabaseService.getPendingInspections();
      for (final inspection in localInspections) {
        await MainDatabaseService.insertInspection(inspection);
        await LocalDatabaseService.markAsSynced('inspections', inspection['inspectionId']);
      }

      // Sync inspection doors
      final localInspectionDoors = await LocalDatabaseService.getPendingInspectionDoors();
      for (final inspectionDoor in localInspectionDoors) {
        await MainDatabaseService.insertInspectionDoor(inspectionDoor);
        await LocalDatabaseService.markAsSynced('inspection_doors', inspectionDoor['id']);
      }

      // Optionally clear synced data from local
      await LocalDatabaseService.clearSyncedData();

      print('Sync completed successfully');
    } catch (e) {
      print('Error during sync: $e');
      rethrow;
    }
  }
}