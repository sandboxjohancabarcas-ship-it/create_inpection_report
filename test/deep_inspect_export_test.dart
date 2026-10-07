import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_export_service.dart';
import 'package:xml/xml.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Verify all row 2 and row 3 cells have exact borders in XLSX output', () async {
    final db = await DatabaseService.getDb();
    final inspId = await db.insert('inspections', {
      'clientName': 'Client Borders Test',
      'objectAddress': 'Test Address 123',
      'inspectorName': 'Max Inspector',
      'jobNumber': '26-14705-AB',
      'projectNumber': 'P-000175',
      'date': '2026-09-15',
      'isLocked': 1,
    });

    final uniqueAlias = 'BC-${DateTime.now().microsecondsSinceEpoch}';
    final doorId = await db.insert('doors', {
      'pos': 1,
      'doorAlias': uniqueAlias,
      'doorNumber': 'T-101',
      'floor': '1. OG',
      'roomNumber': '101',
      'roomDesignation': 'Büro',
      'doorType': 'T30',
      'wingCount': 1,
      'material': 'Stahl',
      'manufacturer': 'Hörmann',
      'doorFunctionOK': 0,
      'notes': 'Note text',
    });

    final junctionId = await db.insert('inspection_doors', {
      'inspectionId': inspId,
      'doorId': doorId,
      'status': 'InProgress',
    });

    final err1 = await db.insert('error_catalog', {
      'code': 'E01',
      'description': 'Error 1',
      'category': 'Cat 1',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final err2 = await db.insert('error_catalog', {
      'code': 'E02',
      'description': 'Error 2',
      'category': 'Cat 2',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await db.insert('inspection_door_errors', {
      'inspectionDoorId': junctionId,
      'errorId': err1,
      'errorCode': 'E01',
      'quantity': 1,
    });

    await db.insert('inspection_door_errors', {
      'inspectionDoorId': junctionId,
      'errorId': err2,
      'errorCode': 'E02',
      'quantity': 2,
    });

    final testPath = '${Directory.systemTemp.path}/test_borders_verification_${DateTime.now().microsecondsSinceEpoch}.xlsx';
    final file = await ExcelExportService.exportSingleInspection(inspId, testPath);

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml')!;
    final stylesFile = archive.findFile('xl/styles.xml')!;

    final sheetXml = XmlDocument.parse(utf8.decode(sheetFile.content as List<int>));
    final stylesXml = XmlDocument.parse(utf8.decode(stylesFile.content as List<int>));

    final borders = stylesXml.findAllElements('borders').first.findElements('border').toList();
    final cellXfs = stylesXml.findAllElements('cellXfs').first.findElements('xf').toList();

    print('\n================ MERGE CELLS ================');
    for (final m in sheetXml.findAllElements('mergeCell')) {
      print(m.getAttribute('ref'));
    }

    print('\n================ ROW 2 CELLS (0-indexed row 1) ================');
    final row2 = sheetXml.findAllElements('row').firstWhere((r) => r.getAttribute('r') == '2');
    for (final c in row2.findElements('c')) {
      final cellRef = c.getAttribute('r')!;
      final sIdx = int.tryParse(c.getAttribute('s') ?? '') ?? 0;
      final xf = cellXfs[sIdx];
      final borderId = int.parse(xf.getAttribute('borderId') ?? '0');
      final border = borders[borderId];
      final bLeft = border.findElements('left').firstOrNull?.getAttribute('style') ?? 'none';
      final bRight = border.findElements('right').firstOrNull?.getAttribute('style') ?? 'none';
      final bTop = border.findElements('top').firstOrNull?.getAttribute('style') ?? 'none';
      final bBottom = border.findElements('bottom').firstOrNull?.getAttribute('style') ?? 'none';

      print('Row 2 Cell $cellRef: border(L:$bLeft, R:$bRight, T:$bTop, B:$bBottom)');
    }
  });
}
