import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/models/models.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseService.verifyIntegrity Tests', () {
    test('verifyIntegrity cleans orphaned junctions and repairs missing door aliases', () async {
      final db = await DatabaseService.getDb();
      await db.delete('inspection_door_errors');
      await db.delete('inspection_doors');
      await db.delete('inspections');
      await db.delete('doors');

      // Insert valid door without alias
      final doorId = await db.insert('doors', {
        'pos': 1,
        'doorNumber': '99',
        'floor': 'EG',
        'doorAlias': null,
      });

      // Insert valid inspection
      final inspId = await db.insert('inspections', {
        'clientName': 'Test GmbH',
        'objectAddress': 'Hauptstr 1',
        'date': '2025-01-01',
      });

      // Insert valid junction
      final validJunctionId = await db.insert('inspection_doors', {
        'inspectionId': inspId,
        'doorId': doorId,
      });

      // Insert ORPHANED junction (pointing to non-existent doorId 9999)
      final orphanJunctionId = await db.insert('inspection_doors', {
        'inspectionId': inspId,
        'doorId': 9999,
      });

      // Insert ORPHANED error (pointing to non-existent inspectionDoorId 8888)
      await db.insert('inspection_door_errors', {
        'inspectionDoorId': 8888,
        'errorCode': 'ERR-01',
      });

      // Execute verifyIntegrity
      final report = await DatabaseService.verifyIntegrity();

      expect(report.orphanedJunctionsRemoved, equals(1));
      expect(report.orphanedErrorsRemoved, equals(1));
      expect(report.missingAliasesRepaired, equals(1));

      // Verify that door 99 has its alias generated
      final repairedDoorMap = await db.query('doors', where: 'id = ?', whereArgs: [doorId]);
      final repairedAlias = repairedDoorMap.first['doorAlias'] as String?;
      expect(repairedAlias, isNotNull);
      expect(repairedAlias!.isNotEmpty, isTrue);

      // Verify DB contains 0 orphans
      final orphanJunctionCheck = await db.query('inspection_doors', where: 'id = ?', whereArgs: [orphanJunctionId]);
      expect(orphanJunctionCheck.isEmpty, isTrue);
    });
  });
}
