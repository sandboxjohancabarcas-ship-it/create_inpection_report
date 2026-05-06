// Provides CRUD operations for the "inspections" table.
// This service isolates all database logic from the UI,
// keeping your architecture clean and maintainable.

import '../models/inspection.dart';
import 'database_service.dart';

class InspectionService {

  // Inserts a new inspection into the database.
  // Returns the generated ID.
  static Future<int> insertInspection(Inspection inspection) async {
    final db = await DatabaseService.getDb();
    return await db.insert('inspections', inspection.toMap());
  }

  // Loads all inspections for a specific door.
  // Ordered by date (newest first).
  static Future<List<Inspection>> getInspectionsForDoor(int doorId) async {
    final db = await DatabaseService.getDb();
    final result = await db.query(
      'inspections',
      where: 'doorId = ?',
      whereArgs: [doorId],
      orderBy: 'date DESC',
    );
    return result.map((e) => Inspection.fromMap(e)).toList();
  }

  // Updates an existing inspection.
// Updates an existing inspection.
// Requires that inspection.id is not null.
  static Future<int> updateInspection(Inspection inspection) async {
    final db = await DatabaseService.getDb();
    return await db.update(
      'inspections',
      inspection.toMap(),
      where: 'id = ?',
      whereArgs: [inspection.inspectionId!], // '!' because we know it must exist here
    );
  }

  // Deletes an inspection by ID.
  static Future<int> deleteInspection(int id) async {
    final db = await DatabaseService.getDb();
    return await db.delete(
      'inspections',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

}
