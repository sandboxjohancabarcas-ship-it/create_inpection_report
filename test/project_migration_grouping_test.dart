import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';
import 'package:wartungstool/services/local_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Project Number Hierarchy & Grouping Tests', () {
    setUp(() async {
      final db = await DatabaseService.getDb();
      await db.delete('inspections');
      await db.delete('doors');
      await db.delete('inspection_doors');
      await db.delete('inspection_door_errors');
      await db.delete('error_catalog');

      try {
        final localDb = await LocalDatabaseService.getDb();
        await localDb.delete('inspections');
        await localDb.delete('doors');
        await localDb.delete('inspection_doors');
        await localDb.delete('inspection_door_errors');
        await localDb.delete('error_catalog');
      } catch (_) {}
    });

    test('Migration file with multiple years & differing sheet addresses unifies under canonical project address', () async {
      final file = File('test/test_data/25-13966-AB P-000604 LPS Polizeimuseum Carl-Cohn-Straße 39 Türen.xlsm');
      expect(file.existsSync(), isTrue, reason: 'Migration test file must exist');

      final result = await ExcelDataImporter.importFromFile(file);
      expect(result.sheetsProcessed > 0, isTrue);

      final db = await DatabaseService.getDb();
      final inspections = await db.query('inspections');
      expect(inspections.isNotEmpty, isTrue);

      // Verify that all inspections share the same project number P-000604
      for (final insp in inspections) {
        expect(insp['projectNumber'], equals('P-000604'));
        // Verify canonical address Carl-Cohn-Straße 39 was assigned to all sheets
        final addr = insp['objectAddress'] as String;
        expect(addr.contains('Carl-Cohn-Straße'), isTrue, reason: 'Address should be unified canonical street address');
      }

      // Verify getAllMasterProjects returns exactly ONE group for P-000604
      final masterProjects = await DatabaseService.getAllMasterProjects();
      expect(masterProjects.length, equals(1));
      expect(masterProjects.first['projectNumber'], equals('P-000604'));
      expect(masterProjects.first['objectAddress'], contains('Carl-Cohn-Straße'));

      // Verify project filter in searchInspections
      final filteredInspections = await DatabaseService.searchInspections('', projectFilter: 'P-000604');
      expect(filteredInspections.length, equals(inspections.length));

      // Verify project filter in searchMasterDoorsDetailed
      final filteredDoors = await DatabaseService.searchMasterDoorsDetailed(projectFilter: 'P-000604');
      expect(filteredDoors.isNotEmpty, isTrue);
      for (final door in filteredDoors) {
        expect(door['projectNumber'], equals('P-000604'));
      }
    });
  });
}
