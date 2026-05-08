// Sync Service: Transfers data from Local DB to Main DB after report generation

import 'local_database_service.dart';
import 'database_service.dart';
import '../models/models.dart';

class SyncService {
  // Sync all pending data from local to main DB
  static Future<void> syncToMainDB() async {
    try {
      // Sync doors
      final localDoors = await LocalDatabaseService.getPendingDoors();
      for (final door in localDoors) {
        await DatabaseService.insertDoor(Door.fromMap(door));
        await LocalDatabaseService.markAsSynced('doors', door['id']);
      }

      // Sync inspections
      final localInspections = await LocalDatabaseService.getPendingInspections();
      for (final inspection in localInspections) {
        await DatabaseService.insertInspection(inspection);
        await LocalDatabaseService.markAsSynced(
          'inspections', 
          inspection['inspectionId'], 
          idColumn: 'inspectionId'
        );
      }

      // Sync inspection doors
      final localInspectionDoors = await LocalDatabaseService.getPendingInspectionDoors();
      for (final inspectionDoor in localInspectionDoors) {
        await DatabaseService.insertInspectionDoor(inspectionDoor);
        await LocalDatabaseService.markAsSynced('inspection_doors', inspectionDoor['id']);
      }

      // Sync inspection door errors
      final localErrors = await LocalDatabaseService.getPendingInspectionDoorErrors();
      for (final errorMap in localErrors) {
        await DatabaseService.insertInspectionDoorError(InspectionDoorError.fromMap(errorMap));
        await LocalDatabaseService.markAsSynced('inspection_door_errors', errorMap['id']);
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