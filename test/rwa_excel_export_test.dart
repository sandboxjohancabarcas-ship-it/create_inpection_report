import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_export_service.dart';
import 'package:wartungstool/services/rwa_excel_importer.dart';
import 'package:wartungstool/services/rwa_options_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    RwaOptionsService.setTestMode(true);
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rwa_export_test_');
    final db = await DatabaseService.getDb();
    await db.delete('inspection_rwa_errors');
    await db.delete('inspection_rwa_settings');
    await db.delete('inspection_rwa');
    await db.delete('rwa_systems');
    await db.delete('inspections');
  });

  tearDown(() async {
    await DatabaseService.closeDb();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test('RWA Excel Export produces valid Excel matching customer format', () async {
    // 1. Import a sample file to populate DB
    final sampleFile = File(
      'test/test_data/RWA-Anlagen/26-14517-AB P-000893 Checkliste RWA-Anlage-1 Gebäude G.xlsx',
    );
    final importResult = await RwaExcelImporter.importFromFile(sampleFile);
    expect(importResult.inspectionsCreated, greaterThan(0));

    // 2. Fetch one inspectionId
    final db = await DatabaseService.getDb();
    final inspections = await db.query('inspections', where: 'assetType = ?', whereArgs: ['rwa']);
    expect(inspections.isNotEmpty, isTrue);
    final inspectionId = inspections.first['inspectionId'] as int;

    // 3. Export to Excel
    final exportPath = '${tempDir.path}/rwa_test_export.xlsx';
    final exportedFile = await ExcelExportService.exportSingleInspection(inspectionId, exportPath);

    expect(await exportedFile.exists(), isTrue);
    expect(await exportedFile.length(), greaterThan(1000));

    // 4. Verify contents with SpreadsheetDecoder
    final bytes = await exportedFile.readAsBytes();
    final decoder = SpreadsheetDecoder.decodeBytes(bytes);
    expect(decoder.tables.isNotEmpty, isTrue);

    final sheet = decoder.tables.values.first;
    expect(sheet.maxRows, greaterThanOrEqualTo(20));

    // Verify cell content
    final cell0_0 = sheet.rows[0][0]?.toString() ?? '';
    expect(cell0_0, equals('Objekt:'));

    // Verify Einrichtung header row exists
    bool foundEinrichtung = false;
    for (final row in sheet.rows) {
      if (row.isNotEmpty && row[0]?.toString() == 'Einrichtung') {
        foundEinrichtung = true;
        expect(row.length, greaterThanOrEqualTo(3));
        expect(row[1]?.toString(), equals('Ergebnis'));
        expect(row[2]?.toString(), equals('Anmerkungen'));
        break;
      }
    }
    expect(foundEinrichtung, isTrue);
  });
}
