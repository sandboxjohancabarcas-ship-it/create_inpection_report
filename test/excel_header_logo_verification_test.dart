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

  test('Verify Excel Export integrity, data completeness, and print header logo', () async {
    final db = await DatabaseService.getDb();
    final inspId = await db.insert('inspections', {
      'clientName': 'Header Integrity Client',
      'objectAddress': 'Teststrasse 123',
      'inspectorName': 'Max Mustermann',
      'jobNumber': '26-99999-AB',
      'projectNumber': 'P-999999',
      'date': '2026-10-07',
      'isLocked': 1,
    });

    final uniqueAlias = 'BC-${DateTime.now().microsecondsSinceEpoch}';
    final doorId = await db.insert('doors', {
      'pos': 1,
      'doorAlias': uniqueAlias,
      'doorNumber': 'T-01',
      'floor': 'EG',
      'roomNumber': '101',
      'roomDesignation': 'Haupteingang',
      'doorType': 'T30',
      'wingCount': 2,
      'material': 'Alurohrrahmen RRAL',
      'manufacturer': 'Schüco',
      'dinConfiguration': 'DIN L',
      'closerType': 'TS 5000',
      'closingSequenceSystem': 'GSR-EMF 2-flg.',
      'lockDimensions': 'PZ 72/55/24',
      'closerOnHingeSide': 1,
      'closerOnOppositeSide': 0,
      'doorFunctionOK': 1,
      'notes': 'Tür funktioniert einwandfrei',
    });

    final junctionId = await db.insert('inspection_doors', {
      'inspectionId': inspId,
      'doorId': doorId,
      'status': 'Completed',
    });

    final errorId = await db.insert('error_catalog', {
      'code': 'E10',
      'description': 'Schließkraft ungenügend',
      'category': 'Türschließer',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await db.insert('inspection_door_errors', {
      'inspectionDoorId': junctionId,
      'errorId': errorId,
      'errorCode': 'E10',
      'quantity': 1,
    });

    final testPath = '${Directory.systemTemp.path}/test_header_logo_integrity_${DateTime.now().microsecondsSinceEpoch}.xlsx';
    final file = await ExcelExportService.exportSingleInspection(inspId, testPath);
    expect(await file.exists(), true);

    final bytes = await file.readAsBytes();
    expect(bytes.isNotEmpty, true);

    // 1. Validate Spreadsheet Data Readability & Completeness via SpreadsheetDecoder
    final decoder = SpreadsheetDecoder.decodeBytes(bytes);
    expect(decoder.tables.isNotEmpty, true);
    final sheetName = decoder.tables.keys.first;
    final table = decoder.tables[sheetName]!;

    // Verify row 3 (data row)
    expect(table.rows[3][0]?.toString(), '1');
    expect(table.rows[3][1]?.toString(), uniqueAlias);
    expect(table.rows[3][2]?.toString(), 'T-01');
    expect(table.rows[3][3]?.toString(), 'EG');
    expect(table.rows[3][4]?.toString(), '101');
    expect(table.rows[3][5]?.toString(), 'Haupteingang');
    expect(table.rows[3][7]?.toString(), '2');
    expect(table.rows[3][12]?.toString(), 'GSR-EMF 2-flg.');
    expect(table.rows[3][13]?.toString(), 'PZ 72/55/24');
    expect(table.rows[3][27]?.toString(), 'J');
    expect(table.rows[3][28]?.toString(), '1');

    // Verify summary row
    final lastRowIdx = table.rows.length - 1;
    expect(table.rows[lastRowIdx][24]?.toString(), 'Summe für Mängelbeseitigung');
    expect(table.rows[lastRowIdx][28]?.toString(), '1');

    // 2. Validate OpenXML Archive Integrity
    final archive = ZipDecoder().decodeBytes(bytes);

    // Validate media image exists
    final mediaFile = archive.findFile('xl/media/image1.png');
    expect(mediaFile != null, true);
    expect((mediaFile!.content as List<int>).isNotEmpty, true);

    // Validate VML drawing exists
    final vmlFile = archive.findFile('xl/drawings/vmlDrawing1.vml');
    expect(vmlFile != null, true);
    final vmlContent = utf8.decode(vmlFile!.content as List<int>);
    expect(vmlContent.contains('id="RH"'), true);
    expect(vmlContent.contains('o:title="GottsbergLogo"'), true);

    // Validate VML rels
    final vmlRelsFile = archive.findFile('xl/drawings/_rels/vmlDrawing1.vml.rels');
    expect(vmlRelsFile != null, true);
    final vmlRelsContent = utf8.decode(vmlRelsFile!.content as List<int>);
    expect(vmlRelsContent.contains('image1.png'), true);

    // Validate sheet1.xml
    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml');
    expect(sheetFile != null, true);
    final sheetContent = utf8.decode(sheetFile!.content as List<int>);
    expect(sheetContent.contains('Prüfprotokol Türen'), true);
    expect(sheetContent.contains('&amp;R&amp;G') || sheetContent.contains('&R&G'), true);
    expect(sheetContent.contains('<legacyDrawingHF r:id="rId1"/>'), true);

    // Validate sheet1 rels
    final sheetRelsFile = archive.findFile('xl/worksheets/_rels/sheet1.xml.rels');
    expect(sheetRelsFile != null, true);
    final sheetRelsContent = utf8.decode(sheetRelsFile!.content as List<int>);
    expect(sheetRelsContent.contains('rId1'), true);
    expect(sheetRelsContent.contains('vmlDrawing1.vml'), true);

    // Validate [Content_Types].xml
    final typesFile = archive.findFile('[Content_Types].xml');
    expect(typesFile != null, true);
    final typesContent = utf8.decode(typesFile!.content as List<int>);
    expect(typesContent.contains('Extension="vml"'), true);
    expect(typesContent.contains('Extension="png"'), true);

    // 3. Test opening via Excel COM if on Windows
    if (Platform.isWindows) {
      final res = await Process.run('powershell', [
        '-ExecutionPolicy', 'Bypass',
        '-File', r'C:\Users\cabarcas\.gemini\antigravity-ide\brain\c5009d21-246a-4fa7-bac0-a79807aae09d\scratch\test_excel_open.ps1',
        '-FilePath', file.path,
      ]);
      expect(res.exitCode, 0, reason: 'Excel failed to open exported file: ${res.stdout}\n${res.stderr}');
    }

    await file.delete();
  });
}
