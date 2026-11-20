import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_export_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Verify Window Excel Export format style matches reference template', () async {
    final db = await DatabaseService.getDb();
    final inspId = await db.insert('inspections', {
      'clientName': 'Fenster Format Test Client',
      'objectAddress': 'Musterstraße 45, 20000 Hamburg',
      'inspectorName': 'Gert Techniker',
      'contactPerson': 'Herr Basau',
      'jobNumber': '25-12115-AB',
      'projectNumber': 'P-003341',
      'date': '2026-11-20',
      'assetType': 'window',
      'isLocked': 1,
    });

    final winId1 = await db.insert('windows', {
      'windowNumber': '01-001',
      'floor': '1.OG',
      'roomNumber': '101',
      'roomDesignation': 'Lagerraum',
      'windowType': 'DKR',
      'material': 'Alu',
      'wingDimensions': '1200x1400',
      'fittings': 'Schüco',
      'windowFunctionOK': 0,
      'hasRaffstore': 1,
      'raffstoreOK': 1,
      'notes': 'Fenster klemmt leicht',
    });

    final winId2 = await db.insert('windows', {
      'windowNumber': '01-002',
      'floor': '1.OG',
      'roomNumber': '102',
      'roomDesignation': 'Büro',
      'windowType': 'DKL',
      'material': 'Kunststoff',
      'wingDimensions': '1000x1200',
      'fittings': 'Roto',
      'windowFunctionOK': 1,
      'hasRaffstore': 0,
      'raffstoreOK': null,
      'notes': '',
    });

    final jId1 = await db.insert('inspection_windows', {
      'inspectionId': inspId,
      'windowId': winId1,
      'status': 'Completed',
      'notes': 'Vor Ort geprüft',
    });

    final jId2 = await db.insert('inspection_windows', {
      'inspectionId': inspId,
      'windowId': winId2,
      'status': 'Completed',
      'notes': '',
    });

    final errId1 = await db.insert('error_catalog', {
      'code': '9.1',
      'description': 'Öffnungssperre für Drehfenster Neumontage',
      'category': 'Fensterbeschläge & Mechanik',
      'assetType': 'window',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final errId2 = await db.insert('error_catalog', {
      'code': '224310',
      'description': 'Anschlagdichtung defekt Art.NR:224310',
      'category': 'Dichtungen',
      'assetType': 'window',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await db.insert('inspection_window_errors', {
      'inspectionWindowId': jId1,
      'errorId': errId1,
      'errorCode': '9.1',
      'quantity': 2,
    });

    await db.insert('inspection_window_errors', {
      'inspectionWindowId': jId1,
      'errorId': errId2,
      'errorCode': '224310',
      'quantity': 1,
    });

    final testPath = '${Directory.systemTemp.path}/test_window_export_${DateTime.now().microsecondsSinceEpoch}.xlsx';
    final file = await ExcelExportService.exportSingleInspection(inspId, testPath);
    expect(await file.exists(), true);

    final bytes = await file.readAsBytes();
    expect(bytes.isNotEmpty, true);

    // 1. Validate Spreadsheet Data & Structure via SpreadsheetDecoder
    final decoder = SpreadsheetDecoder.decodeBytes(bytes);
    expect(decoder.tables.isNotEmpty, true);
    final sheetName = decoder.tables.keys.first;
    expect(sheetName, contains('Fensterliste'));
    final table = decoder.tables[sheetName]!;

    // Row 0 (Metadata & Position numbers)
    expect(table.rows[0][0]?.toString(), contains('Kunde: Fenster Format Test Client'));
    expect(table.rows[0][0]?.toString(), contains('Musterstraße 45'));
    expect(table.rows[0][6]?.toString(), contains('Position:'));
    expect(table.rows[0][10]?.toString(), '1');
    expect(table.rows[0][11]?.toString(), '2');

    // Row 1 (Group Categories)
    expect(table.rows[1][0]?.toString(), 'Grundinformationen');
    expect(table.rows[1][4]?.toString(), 'Fensterspezifikationen');
    expect(table.rows[1][8]?.toString(), 'okay');
    expect(table.rows[1][12]?.toString(), 'Anmerkung');

    // Row 2 (Column Headers)
    expect(table.rows[2][0]?.toString(), 'Fenster Nr.');
    expect(table.rows[2][1]?.toString(), 'Etage');
    expect(table.rows[2][2]?.toString(), 'Raum Nr.');
    expect(table.rows[2][3]?.toString(), 'Sonstiges');
    expect(table.rows[2][8]?.toString(), 'Fenster in Ordnung');
    expect(table.rows[2][9]?.toString(), 'Raffstore in Ordnung');
    expect(table.rows[2][10]?.toString(), contains('224310'));
    expect(table.rows[2][11]?.toString(), contains('9.1'));

    // Row 3 (First window: 01-001)
    expect(table.rows[3][0]?.toString(), '01-001');
    expect(table.rows[3][1]?.toString(), '1.OG');
    expect(table.rows[3][2]?.toString(), '101');
    expect(table.rows[3][3]?.toString(), 'Lagerraum');
    expect(table.rows[3][8]?.toString(), 'N');
    expect(table.rows[3][9]?.toString(), 'Ja');
    expect(table.rows[3][10]?.toString(), '1'); // 224310 defect qty
    expect(table.rows[3][11]?.toString(), '2'); // 9.1 defect qty
    expect(table.rows[3][12]?.toString(), contains('Vor Ort geprüft'));

    // Row 4 (Second window: 01-002)
    expect(table.rows[4][0]?.toString(), '01-002');
    expect(table.rows[4][1]?.toString(), '1.OG');
    expect(table.rows[4][2]?.toString(), '102');
    expect(table.rows[4][3]?.toString(), 'Büro');
    expect(table.rows[4][8]?.toString(), 'J');
    expect(table.rows[4][9]?.toString(), '');

    // Row 5 (Summary Row)
    expect(table.rows[5][6]?.toString(), 'Summe für Mängelbeseitigung');
    expect(table.rows[5][10]?.toString(), '1'); // sum of 224310
    expect(table.rows[5][11]?.toString(), '2'); // sum of 9.1

    // 2. Validate OpenXML Archive Integrity: Fixed Headers, Frozen Panes, Print Titles, Logo
    final archive = ZipDecoder().decodeBytes(bytes);

    // Media image exists
    final mediaFile = archive.findFile('xl/media/image1.png');
    expect(mediaFile != null, true);

    // VML drawing exists
    final vmlFile = archive.findFile('xl/drawings/vmlDrawing1.vml');
    expect(vmlFile != null, true);

    // sheet1.xml validation
    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml');
    expect(sheetFile != null, true);
    final sheetContent = utf8.decode(sheetFile!.content as List<int>);
    expect(sheetContent.contains('Prüfprotokol Fenster'), true);
    expect(sheetContent.contains('<legacyDrawingHF r:id="rId1"/>'), true);
    expect(sheetContent.contains('<pane ySplit="3" topLeftCell="A4" activePane="bottomLeft" state="frozen"/>'), true);
    expect(sheetContent.contains('fitToWidth="1"'), true);
    expect(sheetContent.contains('orientation="landscape"'), true);

    // Print_Titles in xl/workbook.xml
    final workbookFile = archive.findFile('xl/workbook.xml');
    expect(workbookFile != null, true);
    final workbookContent = utf8.decode(workbookFile!.content as List<int>);
    expect(workbookContent.contains('_xlnm.Print_Titles'), true);
    expect(workbookContent.contains(r'!$1:$3'), true);

    await file.delete();
  });
}
