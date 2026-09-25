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
      await db.delete('error_catalog', where: 'code = ? OR description LIKE ?', whereArgs: ['0.32', '%Dormakaba Fehler SCU-UP%']);
    });

    test('Excel import raises catalog conflicts for unlisted defect headers on the latest inspection sheet', () async {
      final file = File(filePath);
      expect(file.existsSync(), isTrue);

      final result = await ExcelDataImporter.importFromFile(file);

      // Verify that catalog conflicts are raised from the latest sheet (Türlisten 24.03.2026)
      expect(result.catalogConflicts, isNotEmpty);

      // Check specific conflicts for latest inspection Türlisten 24.03.2026
      final dormakabaConflict = result.catalogConflicts.where(
        (c) => c.description.contains('Dormakaba') || c.code.contains('Dormakaba')
      ).firstOrNull;
      expect(dormakabaConflict, isNotNull, reason: 'Dormakaba Fehler SCU-UP must be flagged as conflict on latest sheet');

      final brandschutzConflict = result.catalogConflicts.where(
        (c) => c.description.contains('Brand- und Rauchschutzkonzept') || c.code == '0.32'
      ).firstOrNull;
      expect(brandschutzConflict, isNotNull, reason: '0.32 Brandschutzkonzept must be flagged as conflict on latest sheet');
    });

    test('Applying Manager resolutions assigns errors to latest inspection and assigns older inspection errors automatically', () async {
      final file = File(filePath);
      expect(file.existsSync(), isTrue);

      // 1. Initial run to get conflicts from latest sheet
      final initialResult = await ExcelDataImporter.importFromFile(file);
      expect(initialResult.catalogConflicts, isNotEmpty);

      // 2. Manager resolves the conflicts:
      // - Adds "0.32" as approved catalog entry
      // - Maps "Dormakaba Fehler SCU-UP" to existing catalog code "11.5"
      final resolutions = <ConflictResolution>[];
      for (final c in initialResult.catalogConflicts) {
        if (c.code == '0.32' || c.description.contains('Brand- und Rauchschutzkonzept')) {
          resolutions.add(ConflictResolution(
            conflict: c,
            action: ResolutionAction.addAsNew,
            newCode: '0.32',
          ));
        } else if (c.description.contains('Dormakaba')) {
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

      // 4. Verify in DB that error_catalog was updated with 0.32
      final db = await DatabaseService.getDb();
      final cat32 = await db.query('error_catalog', where: 'code = ?', whereArgs: ['0.32']);
      expect(cat32, isNotEmpty, reason: 'Code 0.32 should be saved in error_catalog');

      // 5. Verify that Door 3 in older inspection Türlisten 31.03.2025 has errors assigned via Alternative 1
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
      expect(linkedCodes, isNotEmpty, reason: 'Older inspection Door 3 must have errors linked under Alternative 1');
    });
  });
}

