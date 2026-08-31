import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseService.closeDb();

    final dbPath = await getDatabasesPath();
    final masterPath = p.join(dbPath, 'door_inspection.db');

    try {
      if (await File(masterPath).exists()) await File(masterPath).delete();
    } catch (_) {}
  });

  tearDown(() async {
    await DatabaseService.closeDb();
  });

  group('Duplicate Migration Re-Import Protection Tests', () {

    test('Re-importing the same Excel workbook twice produces ZERO duplicate inspections or doors', () async {
      final testFile = File('test/test_data/25-12343-AB P-003926 Ebner-Eschenbach-Weg 43, 21035 Hamburg Türen final.xlsx');
      if (!await testFile.exists()) {
        print('Test file not found, skipping test');
        return;
      }

      // FIRST IMPORT
      final result1 = await ExcelDataImporter.importFromFile(testFile);
      expect(result1.doorsImported, greaterThan(0));

      final initialInspections = await DatabaseService.getAllInspections();
      final initialDoors = await DatabaseService.getAllDoors();

      final initialInspCount = initialInspections.length;
      final initialDoorCount = initialDoors.length;

      // SECOND IMPORT OF EXACT SAME FILE
      final result2 = await ExcelDataImporter.importFromFile(testFile);

      final secondInspections = await DatabaseService.getAllInspections();
      final secondDoors = await DatabaseService.getAllDoors();

      // VERIFY ZERO DUPLICATION
      expect(secondInspections.length, equals(initialInspCount), reason: 'Inspections count must remain identical');
      expect(secondDoors.length, equals(initialDoorCount), reason: 'Doors count must remain identical');
      expect(result2.logs.any((l) => l.contains('WARNUNG:') || l.contains('bereits im Stammdatenbestand')), isTrue, reason: 'Warning must be logged on re-import');
    });

  });
}
