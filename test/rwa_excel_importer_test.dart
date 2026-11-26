import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
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
    tempDir = Directory.systemTemp.createTempSync('rwa_importer_test_');
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

  group('RwaExcelImporter Unit Tests', () {
    test('normalizeResult parses known values correctly', () {
      expect(RwaExcelImporter.normalizeResult('i.O.'), equals('OK'));
      expect(RwaExcelImporter.normalizeResult('I.O'), equals('OK'));
      expect(RwaExcelImporter.normalizeResult('√'), equals('OK'));
      expect(RwaExcelImporter.normalizeResult('✓'), equals('OK'));
      expect(RwaExcelImporter.normalizeResult('Ja'), equals('OK'));
      expect(RwaExcelImporter.normalizeResult('Keine Mängel'), equals('OK'));

      expect(RwaExcelImporter.normalizeResult('X'), equals('DEFECT'));
      expect(RwaExcelImporter.normalizeResult('defekt'), equals('DEFECT'));
      expect(RwaExcelImporter.normalizeResult('Mangel'), equals('DEFECT'));

      expect(RwaExcelImporter.normalizeResult('n.v'), equals('NOT_PRESENT'));
      expect(RwaExcelImporter.normalizeResult('n.v.'), equals('NOT_PRESENT'));
      expect(RwaExcelImporter.normalizeResult('---'), equals('NOT_PRESENT'));
      expect(RwaExcelImporter.normalizeResult('-'), equals('NOT_PRESENT'));
      expect(RwaExcelImporter.normalizeResult('/'), equals('NOT_PRESENT'));
    });

    test('isDefectAnnotation distinguishes defects from ordinary notes', () {
      // Ordinary notes (not defects)
      expect(RwaExcelImporter.isDefectAnnotation('Bj. 12/2019'), isFalse);
      expect(RwaExcelImporter.isDefectAnnotation('Getauscht 01/25'), isFalse);
      expect(RwaExcelImporter.isDefectAnnotation('Kunde schaltet bei Bedarf ab'), isFalse);
      expect(RwaExcelImporter.isDefectAnnotation('Akku neu'), isFalse);
      expect(RwaExcelImporter.isDefectAnnotation('---'), isFalse);

      // Defect annotations
      expect(RwaExcelImporter.isDefectAnnotation('Taster stark korrodiert'), isTrue);
      expect(RwaExcelImporter.isDefectAnnotation('Klappe klemmt'), isTrue);
      expect(RwaExcelImporter.isDefectAnnotation('Akku überfällig, bitte austauschen'), isTrue);
      expect(RwaExcelImporter.isDefectAnnotation('Glas gebrochen'), isTrue);
      expect(RwaExcelImporter.isDefectAnnotation('Störung an Zentrale'), isTrue);
    });

    test('importFromFile processes sample RWA workbook successfully', () async {
      final sampleFile = File(
        'test/test_data/RWA-Anlagen/26-14517-AB P-000893 Checkliste RWA-Anlage-1 Gebäude G.xlsx',
      );

      if (!await sampleFile.exists()) {
        print('Skipping test: sample file not found at ${sampleFile.path}');
        return;
      }

      final result = await RwaExcelImporter.importFromFile(sampleFile);

      expect(result.sheetsProcessed, greaterThanOrEqualTo(5));
      expect(result.rwaSystemsImported, equals(1));
      expect(result.inspectionsCreated, greaterThanOrEqualTo(5));
      expect(result.settingsEvaluated, greaterThanOrEqualTo(50));

      // Verify in Database
      final db = await DatabaseService.getDb();
      final systems = await db.query('rwa_systems');
      expect(systems.length, equals(1));
      final system = systems.first;
      expect(system['projectNumber'], equals('P-000893'));
      expect(system['objectAddress'], contains('Hamburg'));
      expect(system['building'], contains('Gebäude G'));

      final inspections = await db.query('inspections', where: 'assetType = ?', whereArgs: ['rwa']);
      expect(inspections.length, equals(result.inspectionsCreated));

      final settings = await db.query('inspection_rwa_settings');
      expect(settings.length, equals(result.settingsEvaluated));
    });
  });
}
