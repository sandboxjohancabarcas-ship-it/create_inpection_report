import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rwa_db_test_');
  });

  tearDown(() async {
    await DatabaseService.closeDb();
    await LocalDatabaseService.closeDb();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('DatabaseService RWA Tests', () {
    test('RWA tables and schema version 30 exist in DatabaseService', () async {
      final db = await DatabaseService.getDb();
      expect(DatabaseService.currentDatabaseVersion, equals(30));

      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      expect(tableNames.contains('rwa_systems'), isTrue);
      expect(tableNames.contains('inspection_rwa'), isTrue);
      expect(tableNames.contains('inspection_rwa_settings'), isTrue);
      expect(tableNames.contains('inspection_rwa_errors'), isTrue);

      // Verify sourceInspectionRwaId column in error_catalog
      final catalogCols = await db.rawQuery("PRAGMA table_info(error_catalog)");
      final colNames = catalogCols.map((c) => c['name'] as String).toSet();
      expect(colNames.contains('sourceInspectionRwaId'), isTrue);
    });

    test('RWA System CRUD and alias search operations', () async {
      final rwa = RwaSystem(
        systemAlias: 'Anlage 1 - M-PIC-Ost',
        provisionalAlias: 'RWA-26-14517-AB-01',
        projectNumber: '26-14517-AB',
        systemType: 'elektromotorisch / CO2',
        objectAddress: 'Hohe-Schar-Str. 36, 21107 Hamburg',
        building: 'Gebäude G',
        centralType: 'JET - FIREJET 165J',
        actuatorSpec: '2 Stück CO2 Zylinder',
        fireButtonSpec: '2 Auslöseeinheiten CO2',
        systemFunctionOK: true,
      );

      final id = await DatabaseService.insertRwaSystem(rwa);
      expect(id, greaterThan(0));

      final fetched = await DatabaseService.getRwaSystemById(id);
      expect(fetched, isNotNull);
      expect(fetched!.systemAlias, 'Anlage 1 - M-PIC-Ost');
      expect(fetched.systemType, 'elektromotorisch / CO2');

      // Search by alias
      final byAlias = await DatabaseService.getRwaSystemByAlias('Anlage 1 - M-PIC-Ost');
      expect(byAlias?.id, id);

      // Search by barcode / alias
      final byBarcode = await DatabaseService.findRwaSystemByBarcode('Anlage 1 - M-PIC-Ost');
      expect(byBarcode?.id, id);

      // Update alias
      await DatabaseService.updateRwaSystemAlias(id, 'RWA-PAE-01');
      final updated = await DatabaseService.getRwaSystemById(id);
      expect(updated?.systemAlias, 'RWA-PAE-01');

      // Update system
      await DatabaseService.updateRwaSystem(updated!.copyWith(systemFunctionOK: false, notes: 'Defekt'));
      final refreshed = await DatabaseService.getRwaSystemById(id);
      expect(refreshed?.systemFunctionOK, isFalse);
      expect(refreshed?.notes, 'Defekt');

      // Delete
      await DatabaseService.deleteRwaSystem(id);
      final deleted = await DatabaseService.getRwaSystemById(id);
      expect(deleted, isNull);
    });

    test('RWA Inspection Session, Checklist Settings & Errors', () async {
      final rwa = RwaSystem(
        systemAlias: 'RWA-TEST-02',
        projectNumber: '26-15443-AB',
        systemType: 'CO2',
        objectAddress: 'Deichstraße 21',
      );
      final rwaId = await DatabaseService.insertRwaSystem(rwa);

      // Create an inspection
      final db = await DatabaseService.getDb();
      final inspId = await db.insert('inspections', {
        'clientName': 'HafenCity Test',
        'objectAddress': 'Deichstraße 21',
        'date': '2026-11-26',
        'projectNumber': '26-15443-AB',
        'assetType': 'rwa',
      });

      // Link inspection with RWA system
      final junctionId = await DatabaseService.insertInspectionRwa({
        'inspectionId': inspId,
        'rwaSystemId': rwaId,
        'status': 'InProgress',
        'notes': 'Jahresprüfung 2026',
      });
      expect(junctionId, greaterThan(0));

      final linkedRwas = await DatabaseService.getRwaSystemsByInspectionId(inspId);
      expect(linkedRwas.length, 1);
      expect(linkedRwas.first.id, rwaId);

      // Save checklist settings (12 items)
      final settings = [
        RwaInspectionSetting(
          inspectionRwaId: junctionId,
          settingName: 'Feuertaster',
          result: 'DEFECT',
          rawResult: 'X',
          annotation: 'Korrosion',
        ),
        RwaInspectionSetting(
          inspectionRwaId: junctionId,
          settingName: 'Notstrombatterie',
          result: 'OK',
          rawResult: 'I.O',
          annotation: 'Getauscht 01/25',
        ),
      ];
      await DatabaseService.saveRwaInspectionSettings(junctionId, settings);

      final loadedSettings = await DatabaseService.getRwaInspectionSettings(junctionId);
      expect(loadedSettings.length, 2);
      expect(loadedSettings.first.settingName, 'Feuertaster');
      expect(loadedSettings.first.isDefect, isTrue);

      // Add defect error linked to Feuertaster
      final error = InspectionRwaError(
        inspectionRwaId: junctionId,
        settingName: 'Feuertaster',
        errorCode: 'RWA-FT-001',
        quantity: 1,
        severity: 'high',
        notes: 'Auslösekasten stark korrodiert',
      );
      final errId = await DatabaseService.insertInspectionRwaError(error);
      expect(errId, greaterThan(0));

      final loadedErrors = await DatabaseService.getInspectionRwaErrors(junctionId);
      expect(loadedErrors.length, 1);
      expect(loadedErrors.first.errorCode, 'RWA-FT-001');

      // Verify searchMasterRwaDetailed
      final searchResults = await DatabaseService.searchMasterRwaDetailed(query: 'RWA-TEST-02');
      expect(searchResults.length, 1);
      expect(searchResults.first['openErrorCount'], 1);

      // Export payload check
      final exportData = await DatabaseService.getSingleInspectionExportData(inspId);
      expect(exportData['rwaSystems'], isNotNull);
      final exportedRwas = exportData['rwaSystems'] as List;
      expect(exportedRwas.length, 1);
      expect(exportedRwas.first['settings'], isNotNull);
      expect(exportedRwas.first['errors'], isNotNull);
    });

    test('checkAndInitializeRwaCatalog seeds error catalog', () async {
      await DatabaseService.checkAndInitializeRwaCatalog(force: true);

      final db = await DatabaseService.getDb();
      final rows = await db.query(
        'error_catalog',
        where: "LOWER(COALESCE(assetType, 'door')) = 'rwa'",
      );
      expect(rows.length, greaterThanOrEqualTo(10));

      final sample = rows.firstWhere((r) => r['code'] == 'RWA-FT-001');
      expect(sample['description'], contains('korrodiert'));
      expect(sample['category'], 'Feuertaster');
    });
  });

  group('LocalDatabaseService RWA Tests', () {
    test('LocalDatabaseService initializes v20 with RWA tables and CRUD', () async {
      final db = await LocalDatabaseService.getDb();
      expect(LocalDatabaseService.currentDatabaseVersion, equals(20));

      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      expect(tableNames.contains('rwa_systems'), isTrue);
      expect(tableNames.contains('inspection_rwa'), isTrue);
      expect(tableNames.contains('inspection_rwa_settings'), isTrue);
      expect(tableNames.contains('inspection_rwa_errors'), isTrue);

      final localRwa = RwaSystem(
        systemAlias: 'Local-RWA-01',
        projectNumber: '26-LOCAL-01',
        systemType: 'elektromotorisch',
        objectAddress: 'Musterweg 10',
      );
      final id = await LocalDatabaseService.insertRwaSystem(localRwa);
      expect(id, greaterThan(0));

      final fetched = await LocalDatabaseService.getRwaSystemById(id);
      expect(fetched?.systemAlias, 'Local-RWA-01');

      final all = await LocalDatabaseService.getAllRwaSystems();
      expect(all.length, 1);
    });
  });
}
