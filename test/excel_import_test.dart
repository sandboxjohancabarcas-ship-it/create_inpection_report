import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ExcelDataImporter Service Tests', () {
    setUp(() async {
      final db = await DatabaseService.getDb();
      await db.delete('inspections');
      await db.delete('doors');
      await db.delete('inspection_doors');
      await db.delete('inspection_door_errors');
      await db.delete('error_catalog');
    });

    test('importFromFile should parse doors and inspections correctly', () async {
      final file = File(r'GAEB\25-12115-AB P-003341 Fam. Zentrum Regenbogen, Neuer Krug 31 Türen KINCHI TEST.xlsx');
      expect(file.existsSync(), isTrue, reason: 'Excel file must exist');

      final result = await ExcelDataImporter.importFromFile(file);

      expect(result.sheetsProcessed, equals(1));
      expect(result.doorsImported, equals(38));
      expect(result.errorsLinked, equals(34));
      expect(result.warnings.isEmpty, isTrue);

      final db = await DatabaseService.getDb();
      
      final inspectionsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inspections')) ?? 0;
      final doorsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM doors')) ?? 0;
      final junctionsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inspection_doors')) ?? 0;
      final errorsLinkedCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inspection_door_errors')) ?? 0;

      expect(inspectionsCount, equals(1));
      expect(doorsCount, equals(38));
      expect(junctionsCount, equals(38));
      expect(errorsLinkedCount, equals(34));
    });
  });
}
