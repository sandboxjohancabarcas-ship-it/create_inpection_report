import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
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

    test('Window.generateAlias conforms to agreed formula F-[Project]-[Window]',
        () {
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
      final updatedMaterials =
          WindowOptionsService.getStringOptions('material');
      expect(updatedMaterials, contains('Holz-Alu'));

      WindowOptionsService.removeOption('material', 'Holz-Alu');
      final afterRemove = WindowOptionsService.getStringOptions('material');
      expect(afterRemove.contains('Holz-Alu'), isFalse);
    });

    test('ExcelDataImporter imports template file and exports back to Excel',
        () async {
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

      final windows = await DatabaseService.getWindowsByInspectionId(
          insp['inspectionId'] as int);
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

      final errList =
          await DatabaseService.getInspectionWindowErrors(junctionId);
      expect(errList.length, equals(1));
      expect(errList.first.errorCode, equals('9.1'));
      expect(errList.first.quantity, equals(2));

      final exportData =
          await DatabaseService.getSingleInspectionExportData(inspId);
      expect(exportData['windows'], isNotEmpty);
      final exportedWin = (exportData['windows'] as List).first;
      expect(exportedWin['windowNumber'], equals('02-005'));
      expect((exportedWin['errors'] as List).length, equals(1));
    });

    test(
        'ExcelDataImporter imports multi-year sheets and Fehlerliste Codes sheet',
        () async {
      final excel = Excel.createExcel();
      excel.rename('Sheet1', '2024');

      // Sheet "Fehlerliste Codes"
      final codesSheet = excel['Fehlerliste Codes'];
      codesSheet
          .appendRow([TextCellValue('9.99-Sonderfensterschere austauschen')]);
      codesSheet.appendRow([TextCellValue('Holzfenster')]);
      codesSheet.appendRow(
          [TextCellValue('20.99-Hinweis: Spezieller Holzfäulebefall')]);

      // Sheet "2024"
      final sheet2024 = excel['2024'];
      sheet2024.appendRow([
        TextCellValue('Kunde: Testkunde MultiYear'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('Objekt: Mustergebäude 24'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('Auftrag 24-99999-AB'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('Anmerkung')
      ]);
      sheet2024.appendRow([
        TextCellValue('Fenster Nr.'),
        TextCellValue('Etage'),
        TextCellValue('Raum Nr.'),
        TextCellValue('Sonstiges'),
        TextCellValue('Fenstertyp'),
        TextCellValue('Material'),
        TextCellValue('Flügelabmaße'),
        TextCellValue('Beschläge'),
        TextCellValue('Fenster in Ordnung'),
        TextCellValue('Raffstore in Ordnung'),
        TextCellValue('Anschlagdichtung defekt Art.NR:224310'),
        TextCellValue('Anmerkung'),
      ]);
      sheet2024.appendRow([
        TextCellValue('01-001'),
        TextCellValue('1.OG'),
        TextCellValue('101'),
        TextCellValue('Büro'),
        TextCellValue('DKR'),
        TextCellValue('Alu'),
        TextCellValue('1200x1400'),
        TextCellValue('Schüco'),
        TextCellValue('N'),
        TextCellValue('J'),
        IntCellValue(1),
        TextCellValue('Dichtung porös'),
      ]);

      // Sheet "2023"
      final sheet2023 = excel['2023'];
      sheet2023.appendRow([
        TextCellValue('Kunde: Testkunde MultiYear'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('Objekt: Mustergebäude 24'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('Auftrag 23-88888-AB'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('Anmerkung')
      ]);
      sheet2023.appendRow([
        TextCellValue('Fenster Nr.'),
        TextCellValue('Etage'),
        TextCellValue('Raum Nr.'),
        TextCellValue('Sonstiges'),
        TextCellValue('Fenstertyp'),
        TextCellValue('Material'),
        TextCellValue('Flügelabmaße'),
        TextCellValue('Beschläge'),
        TextCellValue('Fenster in Ordnung'),
        TextCellValue('Jalousie in Ordnung'),
        TextCellValue('Anschlagdichtung defekt Art.NR:224310'),
        TextCellValue('Anmerkung'),
      ]);
      sheet2023.appendRow([
        TextCellValue('01-001'),
        TextCellValue('1.OG'),
        TextCellValue('101'),
        TextCellValue('Büro'),
        TextCellValue('DKR'),
        TextCellValue('Alu'),
        TextCellValue('1200x1400'),
        TextCellValue('Schüco'),
        TextCellValue('J'),
        TextCellValue('J'),
        IntCellValue(0),
        TextCellValue(''),
      ]);

      final tempDir = Directory.systemTemp.createTempSync('multi_year_test_');
      final tempFile = File('${tempDir.path}/test_multi_year_windows.xlsx');
      final bytes = excel.save()!;
      await tempFile.writeAsBytes(bytes);

      final result = await ExcelDataImporter.importFromFile(tempFile);

      expect(result.assetType, equals('window'));
      expect(result.sheetsProcessed, equals(2));
      expect(result.windowsImported, equals(1));
      expect(result.errorsLinked, equals(1));

      // Verify Inspections created for both 2024 and 2023
      final allInspections = await DatabaseService.getAllInspections();
      final windowInspections =
          allInspections.where((i) => i['assetType'] == 'window').toList();
      expect(windowInspections.length, greaterThanOrEqualTo(2));

      // Verify new catalog error from "Fehlerliste Codes" was imported
      final windowCatalog =
          await DatabaseService.getAllErrorCatalog(assetType: 'window');
      expect(windowCatalog.any((c) => c.code == '9.99'), isTrue);
      expect(
          windowCatalog
              .any((c) => c.code == '20.99' && c.category == 'Holzfenster'),
          isTrue);

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
        'ExcelDataImporter extracts address from filename or row 1 (cols E, F, G) into metadata',
        () async {
      // 1. File with address in Row 1 Columns F & G (not full in filename)
      final file1 = File(
          'test/test_data/Fenster/23-08561-AB Tesdorpfstraße 8 Fensterliste Final.xlsx');
      if (file1.existsSync()) {
        final res1 = await ExcelDataImporter.importFromFile(file1);
        print('=== TESDORPFSTRASSE IMPORT RESULT ===');
        print('Sheets processed: ${res1.sheetsProcessed}');
        print('Windows imported: ${res1.windowsImported}');
        print('Errors linked: ${res1.errorsLinked}');
        print('New catalog proposals: ${res1.newCatalogProposals}');
        for (final log in res1.logs) {
          if (log.contains('Mängel') || log.contains('2023') || log.contains('Katalogfehler') || log.contains('Fehler') || log.contains('Arbeitsblatt')) {
            print(log);
          }
        }
        expect(res1.objectAddress, contains('Tesdorpfstraße 8'));
        expect(res1.objectAddress, contains('20148 Hamburg'));

        final inspections1 = await DatabaseService.getAllInspections();
        final match1 = inspections1.firstWhere(
          (i) => i['objectAddress'].toString().contains('Tesdorpfstraße 8'),
        );
        expect(match1['objectAddress'], contains('20148 Hamburg'));
      }

      // 2. File with address in filename (Row 1 has empty address cell)
      final file2 = File(
          'test/test_data/Fenster/26-14892-AB P-000362 Am Überwinterungshafen 1, 21079 Hamburg Fenster final.xlsx');
      if (file2.existsSync()) {
        final res2 = await ExcelDataImporter.importFromFile(file2);
        expect(res2.objectAddress, contains('Am Überwinterungshafen 1'));
        expect(res2.objectAddress, contains('21079 Hamburg'));

        final inspections2 = await DatabaseService.getAllInspections();
        final match2 = inspections2.firstWhere(
          (i) => i['objectAddress'].toString().contains('Überwinterungshafen'),
        );
        expect(match2['objectAddress'], contains('21079 Hamburg'));
      }

      // 3. File with address in Row 1 Column E
      final file3 = File(
          'test/test_data/Fenster/26-15318-AB P-003732 Willinghusener Weg 5, 22113 Oststeinbek Mieter GOTTWALD Fensterliste final.xlsx');
      if (file3.existsSync()) {
        final res3 = await ExcelDataImporter.importFromFile(file3);
        expect(res3.objectAddress, contains('Willinghusener Weg 5'));
        expect(res3.objectAddress, contains('22113'));

        final inspections3 = await DatabaseService.getAllInspections();
        final match3 = inspections3.firstWhere(
          (i) => i['objectAddress'].toString().contains('Willinghusener Weg 5'),
        );
        expect(match3['objectAddress'], contains('22113'));
      }

      // 4. File with address in both filename and Row 1
      final file4 = File(
          'test/test_data/Fenster/26-15614-AB P-000748 Rotenhäuser Str. 73, 21107 Hamburg Fenster Altbau final.xlsx');
      if (file4.existsSync()) {
        final res4 = await ExcelDataImporter.importFromFile(file4);
        expect(res4.objectAddress, contains('Rotenhäuser Str. 73'));
        expect(res4.objectAddress, contains('21107 Hamburg'));
      }
    });

    test('Window inspection status, search and defect summaries work correctly', () async {
      final db = await DatabaseService.getDb();
      final inspId = await db.insert('inspections', {
        'assetType': 'window',
        'jobNumber': '26-99999-AB',
        'projectNumber': 'P-009999',
        'clientName': 'Testkunde',
        'date': '2026-11-17',
        'isLocked': 0,
      });

      final win1Id = await DatabaseService.insertWindow(Window(
        windowNumber: 'W-01',
        floor: 'EG',
        roomNumber: 'R101',
        roomDesignation: 'Besprechungsraum',
        windowType: 'DKR',
        material: 'Alu',
        windowAlias: 'F-009999-W-01',
      ));
      final win2Id = await DatabaseService.insertWindow(Window(
        windowNumber: 'W-02',
        floor: '1.OG',
        roomNumber: 'R201',
        roomDesignation: 'Büro Chef',
        windowType: 'DKR',
        material: 'Alu',
        windowAlias: 'F-009999-W-02',
      ));

      final j1Id = await db.insert('inspection_windows', {
        'inspectionId': inspId,
        'windowId': win1Id,
        'status': 'Pending',
      });
      final j2Id = await db.insert('inspection_windows', {
        'inspectionId': inspId,
        'windowId': win2Id,
        'status': 'Inspected',
      });

      // Insert catalog errors
      await db.insert('error_catalog', {
        'code': 'F-1.1',
        'description': 'Griff defekt',
        'category': 'Beschlag',
        'assetType': 'window',
      });
      await db.insert('error_catalog', {
        'code': 'H-01',
        'description': 'Hinweis Dichtung reinigen',
        'category': 'Hinweis',
        'assetType': 'window',
      });

      // Insert window error for win1
      await db.insert('inspection_window_errors', {
        'inspectionWindowId': j1Id,
        'errorCode': 'F-1.1',
        'resolutionStatus': 'open',
      });
      // Insert notice for win2
      await db.insert('inspection_window_errors', {
        'inspectionWindowId': j2Id,
        'errorCode': 'H-01',
        'resolutionStatus': 'resolved',
      });

      // 1. Test getWindowInspectionStatuses
      final statuses = await DatabaseService.getWindowInspectionStatuses(inspId);
      expect(statuses[win1Id], equals('Pending'));
      expect(statuses[win2Id], equals('Inspected'));

      // 2. Test setWindowInspectionStatus
      await DatabaseService.setWindowInspectionStatus(
        inspectionId: inspId,
        windowId: win1Id,
        status: 'Inspected',
      );
      final updatedStatuses = await DatabaseService.getWindowInspectionStatuses(inspId);
      expect(updatedStatuses[win1Id], equals('Inspected'));

      // 3. Test getWindowErrorSummariesForInspection
      final summaries = await DatabaseService.getWindowErrorSummariesForInspection(inspId);
      final s1 = summaries[win1Id]!;
      expect(s1.defectCount, equals(1));
      expect(s1.openDefects, equals(1));
      expect(s1.resolvedDefects, equals(0));

      final s2 = summaries[win2Id]!;
      expect(s2.noticeCount, equals(1));
      expect(s2.resolvedNotices, equals(1));
      expect(s2.defectCount, equals(0));

      // 4. Test getWindowsByInspectionIds with queries
      final searchRoom = await DatabaseService.getWindowsByInspectionIds([inspId], query: 'Besprechung');
      expect(searchRoom.length, equals(1));
      expect(searchRoom.first.windowNumber, equals('W-01'));

      final searchErrorCode = await DatabaseService.getWindowsByInspectionIds([inspId], query: 'Griff defekt');
      expect(searchErrorCode.length, equals(1));
      expect(searchErrorCode.first.windowNumber, equals('W-01'));

      final searchNotice = await DatabaseService.getWindowsByInspectionIds([inspId], query: 'Dichtung');
      expect(searchNotice.length, equals(1));
      expect(searchNotice.first.windowNumber, equals('W-02'));

      // 5. Test inspection lock status
      await DatabaseService.setInspectionLockStatus(inspId, true);
      final inspLocked = await DatabaseService.getInspectionById(inspId);
      expect(inspLocked?['isLocked'], equals(1));

      // 6. Test Fenster-Akte (getWindowHistoryData)
      final history1 = await DatabaseService.getWindowHistoryData(windowId: win1Id);
      expect(history1, isNotNull);
      expect(history1!['totalInspections'], equals(1));
      expect(history1['totalLifetimeErrors'], equals(1));
      expect(history1['currentOpenErrors'], equals(1));
      expect(history1['resolvedErrors'], equals(0));
      expect(history1['window'], isA<Window>());
      expect((history1['window'] as Window).windowNumber, equals('W-01'));
      final historyItems = history1['historyItems'] as List<Map<String, dynamic>>;
      expect(historyItems.length, equals(1));
      expect(historyItems.first['errors'], isNotEmpty);
      expect(historyItems.first['errors'][0]['errorCode'], equals('F-1.1'));

      // Test alias lookup
      final historyByAlias = await DatabaseService.getWindowHistoryData(windowAlias: 'F-009999-W-02');
      expect(historyByAlias, isNotNull);
      expect((historyByAlias!['window'] as Window).windowNumber, equals('W-02'));
      expect(historyByAlias['resolvedErrors'], equals(1));
      expect(historyByAlias['healthStatus'], equals('green'));
    });

    test('ExcelDataImporter imports Tesdorpfstrasse file with 15 errors from sheet 2023', () async {
      final file = File('test/test_data/Fenster/23-08561-AB Tesdorpfstraße 8 Fensterliste Final.xlsx');
      expect(file.existsSync(), isTrue);

      final result = await ExcelDataImporter.importFromFile(file);

      expect(result.windowsImported, equals(732));
      expect(result.sheetsProcessed, equals(4)); // 2023, 2022, 2021, 2019
      expect(result.errorsLinked, greaterThan(0));

      // Verify all 15 error codes are registered in error_catalog for window
      final catalog = await DatabaseService.getAllErrorCatalog(assetType: 'window');
      final catalogCodes = catalog.map((e) => e.code).toSet();

      for (int i = 1; i <= 15; i++) {
        expect(catalogCodes.contains('$i'), isTrue,
            reason: 'Error code $i should be in window error catalog');
      }

      // Check specific defect descriptions
      final err1 = catalog.firstWhere((e) => e.code == '1');
      expect(err1.description, equals('Entwässerung nach aussen wurde verschlossen'));
      expect(err1.category, equals('Fenster Mängelerfassung'));

      final err2 = catalog.firstWhere((e) => e.code == '2');
      expect(err2.description, equals('Ecklager unten gebrochen'));
      expect(err2.category, equals('Fensterbeschläge & Mechanik'));

      final err3 = catalog.firstWhere((e) => e.code == '3');
      expect(err3.description, equals('Mitteldichtung Blendrahmen fehlt'));
      expect(err3.category, equals('Dichtungen'));

      final err4 = catalog.firstWhere((e) => e.code == '4');
      expect(err4.description, equals('RC2 Schließblech fehlt'));
      expect(err4.category, equals('Schließbleche'));

      final err5 = catalog.firstWhere((e) => e.code == '5');
      expect(err5.description, equals('Scließblech fehlt Art.NR:525099'));
      expect(err5.category, equals('Schließbleche'));

      final err6 = catalog.firstWhere((e) => e.code == '6');
      expect(err6.description, equals('Raffstore fährt nicht(kein Strom)'));
      expect(err6.category, equals('Sonnenschutz & Raffstore'));

      final err7 = catalog.firstWhere((e) => e.code == '7');
      expect(err7.description, equals('Schere defekt'));
      expect(err7.category, equals('Fensterbeschläge & Mechanik'));

      final err8 = catalog.firstWhere((e) => e.code == '8');
      expect(err8.description, equals('Leiterkordel defekt'));
      expect(err8.category, equals('Sonnenschutz & Raffstore'));

      final err9 = catalog.firstWhere((e) => e.code == '9');
      expect(err9.description, equals('Schnapper fehlt'));
      expect(err9.category, equals('Fensterbeschläge & Mechanik'));

      final err10 = catalog.firstWhere((e) => e.code == '10');
      expect(err10.description, equals('Öffnungsbegrenzer defekt'));
      expect(err10.category, equals('Fensterbeschläge & Mechanik'));

      final err11 = catalog.firstWhere((e) => e.code == '11');
      expect(err11.description, equals('nicht prüfbar zugestellt'));
      expect(err11.category, equals('Fenster Mängelerfassung'));

      final err12 = catalog.firstWhere((e) => e.code == '12');
      expect(err12.description, equals('Kipp Schließblech fehlt'));
      expect(err12.category, equals('Schließbleche'));

      final err13 = catalog.firstWhere((e) => e.code == '13');
      expect(err13.description, equals('Texband gerissen'));
      expect(err13.category, equals('Sonnenschutz & Raffstore'));

      final err14 = catalog.firstWhere((e) => e.code == '14');
      expect(err14.description, equals('Scheibe gerissen'));
      expect(err14.category, equals('Verglasung'));

      final err15 = catalog.firstWhere((e) => e.code == '15');
      expect(err15.description, equals('Mitteldichtung Flügel'));
      expect(err15.category, equals('Dichtungen'));

      // Verify all 4 inspections are created in database
      final db = await DatabaseService.getDb();
      final inspections = await db.query('inspections');
      final windowInspections = inspections.where((i) => i['assetType'] == 'window').toList();
      expect(windowInspections.length, equals(4));

      // Verify window 1 has errors in 2023
      final win1 = await DatabaseService.getWindowByAlias('F-000000-EG-1');
      expect(win1, isNotNull);
      final history1 = await DatabaseService.getWindowHistoryData(windowId: win1!.id!);
      expect(history1, isNotNull);
      expect(history1!['totalLifetimeErrors'], greaterThan(0));
    });
  });
}
