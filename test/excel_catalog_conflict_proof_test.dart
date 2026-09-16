import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Proof of Error Catalog Conflict Resolution for Tesdorpfstraße Door 3', () {
    final filePath = r'c:\Users\cabarcas\Projects\WartungsTool\test\test_data\26-14332-AB P-000600 Tesdorpfstraße 8 Türliste final.xlsm';

    setUp(() async {
      final db = await DatabaseService.getDb();
      await db.delete('error_catalog', where: 'code = ? OR description LIKE ?', whereArgs: ['0.40', '%Mehrfachverriegelung%']);
      await db.delete('error_catalog', where: 'description LIKE ?', whereArgs: ['%Kraftbetätigte Tür ohne Fingerschutz%']);
    });

    test('Excel import without resolution raises catalog conflicts for unlisted defect headers', () async {
      final file = File(filePath);
      expect(file.existsSync(), isTrue);

      final result = await ExcelDataImporter.importFromFile(file);

      // Verify that catalog conflicts are raised
      expect(result.catalogConflicts, isNotEmpty);

      // Check specific conflicts for Door 3 in inspection Türlisten 31.03.2025
      final mehrfachConflict = result.catalogConflicts.where(
        (c) => c.description.contains('Mehrfachverriegelung') || c.code.contains('Mehrfachverriegelung')
      ).firstOrNull;
      expect(mehrfachConflict, isNotNull, reason: 'Mehrfachverriegelung defekt must be flagged as conflict');

      final fingerConflict = result.catalogConflicts.where(
        (c) => c.description.contains('Kraftbetätigte Tür') || c.code.contains('Kraftbetätigte Tür')
      ).firstOrNull;
      expect(fingerConflict, isNotNull, reason: 'Kraftbetätigte Tür ohne Fingerschutz must be flagged as conflict');
    });

    test('Applying Manager resolutions assigns errors to Door 3 for Türlisten 31.03.2025', () async {
      final file = File(filePath);
      expect(file.existsSync(), isTrue);

      // 1. Initial run to get conflicts
      final initialResult = await ExcelDataImporter.importFromFile(file);
      expect(initialResult.catalogConflicts, isNotEmpty);

      // 2. Manager resolves the conflicts:
      // - Adds "Mehrfachverriegelung defekt" as new catalog entry with code "0.40"
      // - Maps "Kraftbetätigte Tür ohne Fingerschutz" to existing catalog code "11.5"
      final resolutions = <ConflictResolution>[];
      for (final c in initialResult.catalogConflicts) {
        if (c.description.contains('Mehrfachverriegelung')) {
          resolutions.add(ConflictResolution(
            conflict: c,
            action: ResolutionAction.addAsNew,
            newCode: '0.40',
          ));
        } else if (c.description.contains('Kraftbetätigte Tür')) {
          resolutions.add(ConflictResolution(
            conflict: c,
            action: ResolutionAction.replaceExisting,
            newCode: '11.5',
          ));
        }
      }

      // 3. Apply resolutions during import
      final resolvedResult = await ExcelDataImporter.importFromFile(file, resolutions: resolutions);
      expect(resolvedResult.errorsLinked, greaterThan(0));

      // 4. Verify in DB that error_catalog was updated with 0.40
      final db = await DatabaseService.getDb();
      final cat40 = await db.query('error_catalog', where: 'code = ?', whereArgs: ['0.40']);
      expect(cat40, isNotEmpty, reason: 'Code 0.40 should be saved in error_catalog');

      // 5. Verify that Door 3 in inspection Türlisten 31.03.2025 has both errors linked
      final door3List = await db.query('doors', where: 'doorNumber = ?', whereArgs: ['3']);
      expect(door3List, isNotEmpty, reason: 'Door 3 should exist in database');
      final door3Id = door3List.first['id'];

      final inspectionDoors = await db.rawQuery('''
        SELECT i.date, id.id AS inspectionDoorId, id.notes, ide.errorCode, ide.quantity, ec.description
        FROM inspection_doors id
        JOIN inspections i ON id.inspectionId = i.inspectionId
        LEFT JOIN inspection_door_errors ide ON id.id = ide.inspectionDoorId
        LEFT JOIN error_catalog ec ON ide.errorId = ec.errorId
        WHERE id.doorId = ? AND i.date LIKE '2025-03-31%'
      ''', [door3Id]);

      expect(inspectionDoors, isNotEmpty, reason: 'Inspection for Door 3 on 2025-03-31 should exist');

      final linkedCodes = inspectionDoors.map((r) => r['errorCode']?.toString()).whereType<String>().toList();
      print('Linked error codes for Door 3 on 2025-03-31: $linkedCodes');

      expect(linkedCodes, contains('0.40'), reason: 'Resolved code 0.40 must be assigned to Door 3');
      expect(linkedCodes, contains('11.5'), reason: 'Mapped code 11.5 must be assigned to Door 3');
    });
  });
}
