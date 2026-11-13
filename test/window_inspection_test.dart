import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';
import 'package:wartungstool/services/excel_export_service.dart';
import 'package:wartungstool/services/window_options_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Window Inspection Tests', () {
    setUp(() async {
      final db = await DatabaseService.getDb();
      await db.delete('inspections');
      await db.delete('windows');
      await db.delete('inspection_windows');
      await db.delete('inspection_window_errors');
      await db.delete('error_catalog');
    });

    test('Window.generateAlias conforms to agreed formula F-[Project]-[Window]', () {
      final alias1 = Window.generateAlias(
        projectNumber: '24-00000-AB P-000000',
        windowNumber: '03-044',
      );
      expect(alias1, equals('F-000000-03-044'));

      final alias2 = Window.generateAlias(
        projectNumber: 'P-12345',
        windowNumber: '00-001',
      );
      expect(alias2, equals('F-12345-00-001'));
    });

    test('Window CRUD operations work in DatabaseService', () async {
      final window = Window(
        windowNumber: '01-010',
        floor: '1.OG',
        roomNumber: '101',
        roomDesignation: 'Büro',
        windowType: 'DKR',
        material: 'Alu',
        wingDimensions: '1300x1550',
        fittings: 'Schüco',
        windowFunctionOK: true,
        hasRaffstore: true,
        raffstoreOK: true,
        windowAlias: 'F-99999-01-010',
      );

      final id = await DatabaseService.insertWindow(window);
      expect(id, isPositive);

      final fetched = await DatabaseService.getWindowById(id);
      expect(fetched, isNotNull);
      expect(fetched!.windowNumber, equals('01-010'));
      expect(fetched.material, equals('Alu'));
      expect(fetched.hasRaffstore, isTrue);
      expect(fetched.windowAlias, equals('F-99999-01-010'));

      final byAlias = await DatabaseService.getWindowByAlias('F-99999-01-010');
      expect(byAlias, isNotNull);
      expect(byAlias!.id, equals(id));
    });

    test('WindowOptionsService manages dynamic options', () async {
      await WindowOptionsService.ensureLoaded();

      final windowTypes = WindowOptionsService.getStringOptions('windowType');
      expect(windowTypes, contains('DKR'));

      final materials = WindowOptionsService.getStringOptions('material');
      expect(materials, contains('Alu'));
      expect(materials, contains('Holz'));

      WindowOptionsService.addOption('material', 'Holz-Alu');
      final updatedMaterials = WindowOptionsService.getStringOptions('material');
      expect(updatedMaterials, contains('Holz-Alu'));

      WindowOptionsService.removeOption('material', 'Holz-Alu');
      final afterRemove = WindowOptionsService.getStringOptions('material');
      expect(afterRemove.contains('Holz-Alu'), isFalse);
    });

    test('ExcelDataImporter imports template file and exports back to Excel', () async {
      final templateFile = File(
          'test/test_data/test_template/24-00000-AB P-000000 Fensterliste Aktuell 20.08.2024.xlsx');
      expect(templateFile.existsSync(), isTrue,
          reason: 'Test template file must exist');

      final result = await ExcelDataImporter.importFromFile(templateFile);

      expect(result.assetType, equals('window'));
      expect(result.windowsImported, greaterThan(200));

      final inspections = await DatabaseService.getAllInspections();
      expect(inspections.length, equals(1));
      final insp = inspections.first;
      expect(insp['assetType'], equals('window'));
      expect(insp['clientName'], contains('Sprinkenhof'));

      final windows = await DatabaseService.getWindowsByInspectionId(insp['inspectionId'] as int);
      expect(windows.length, equals(result.windowsImported));

      // Test export to Excel
      final tempExportDir = Directory.systemTemp.createTempSync('export_test_');
      final exportPath = '${tempExportDir.path}/test_fenster_export.xlsx';

      final exportedFile = await ExcelExportService.exportSingleInspection(
        insp['inspectionId'] as int,
        exportPath,
      );

      expect(exportedFile.existsSync(), isTrue);
      expect(exportedFile.lengthSync(), greaterThan(1000));

      try {
        tempExportDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('InspectionWindow junction and error linking flow', () async {
      final inspId = await DatabaseService.insertInspection({
        'clientName': 'Test Fenster Kunde',
        'objectAddress': 'Musterstraße 1, 20000 Hamburg',
        'date': '2026-11-12',
        'jobNumber': '26-12345',
        'projectNumber': 'P-999999',
        'assetType': 'window',
      });

      final win = Window(
        windowNumber: '02-005',
        floor: '2.OG',
        roomNumber: '205',
        roomDesignation: 'Chefzimmer',
        windowType: 'DKR',
        material: 'Alu',
        wingDimensions: '1200x1400',
        fittings: 'Schüco',
        windowFunctionOK: false,
        hasRaffstore: true,
        raffstoreOK: false,
        windowAlias: 'F-999999-02-005',
      );
      final winId = await DatabaseService.insertWindow(win);

      final junctionId = await DatabaseService.insertInspectionWindow({
        'inspectionId': inspId,
        'windowId': winId,
        'status': 'Mängel',
        'notes': 'Dichtung defekt',
      });
      expect(junctionId, isPositive);

      final err = InspectionWindowError(
        inspectionWindowId: junctionId,
        errorCode: '9.1',
        quantity: 2,
        severity: 'high',
        notes: 'Dichtung porös und gerissen',
      );
      final errId = await DatabaseService.insertInspectionWindowError(err);
      expect(errId, isPositive);

      final errList = await DatabaseService.getInspectionWindowErrors(junctionId);
      expect(errList.length, equals(1));
      expect(errList.first.errorCode, equals('9.1'));
      expect(errList.first.quantity, equals(2));

      final exportData = await DatabaseService.getSingleInspectionExportData(inspId);
      expect(exportData['windows'], isNotEmpty);
      final exportedWin = (exportData['windows'] as List).first;
      expect(exportedWin['windowNumber'], equals('02-005'));
      expect((exportedWin['errors'] as List).length, equals(1));
    });
  });
}
