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
    print('\n================ ALL FILLS ================');
    final allFills = stylesXml.findAllElements('fills').first.findElements('fill').toList();
    for (int i = 0; i < allFills.length; i++) {
      print('Fill $i: ${allFills[i].toXmlString()}');
    }

    print('\n================ ALL BORDERS ================');
    for (int i = 0; i < borders.length; i++) {
      print('Border $i: ${borders[i].toXmlString()}');
    }

    print('\n================ ALL CELL XFS ================');
    for (int i = 0; i < cellXfs.length; i++) {
      print('XF $i: ${cellXfs[i].toXmlString()}');
    }
    /*
    print('\n================ ROW 2 CELLS (0-indexed row 1) ================');
    final row2 = sheetXml.findAllElements('row').firstWhere((r) => r.getAttribute('r') == '2');
    ...
    */
  });

  test('Inspect sheet1.xml print settings', () async {
    final dir = Directory('test/test_data/test_template');
    final templateFile = dir.listSync().whereType<File>().firstWhere((f) => f.path.contains('template_26-15337'));
    final bytes = await templateFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml')!;
    final stylesFile = archive.findFile('xl/styles.xml')!;
    final sheetXml = XmlDocument.parse(utf8.decode(sheetFile.content as List<int>));
    final stylesXml = XmlDocument.parse(utf8.decode(stylesFile.content as List<int>));
    final borders = stylesXml.findAllElements('borders').first.findElements('border').toList();
    final cellXfs = stylesXml.findAllElements('cellXfs').first.findElements('xf').toList();

    final sstFile = archive.findFile('xl/sharedStrings.xml')!;
    final sstXml = XmlDocument.parse(utf8.decode(sstFile.content as List<int>));
    final siList = sstXml.findAllElements('si').map((si) => si.findAllElements('t').map((t) => t.innerText).join()).toList();

    print('\n================ TEMPLATE 26-15337 ROW 2 (MERGES) ================');
    for (final m in sheetXml.findAllElements('mergeCell')) {
      print(m.getAttribute('ref'));
    }

    print('\n================ TEMPLATE 26-15337 ROW 3 CELLS ================');
    final row3 = sheetXml.findAllElements('row').firstWhere((r) => r.getAttribute('r') == '3');
    for (final c in row3.findElements('c')) {
      final cellRef = c.getAttribute('r')!;
      final sIdx = int.tryParse(c.getAttribute('s') ?? '') ?? 0;
      final xf = cellXfs[sIdx];
      final borderId = int.parse(xf.getAttribute('borderId') ?? '0');
      final applyBorder = xf.getAttribute('applyBorder');
      final border = borders[borderId];
      final bLeft = border.findElements('left').firstOrNull?.getAttribute('style') ?? 'none';
      final bRight = border.findElements('right').firstOrNull?.getAttribute('style') ?? 'none';
      final bTop = border.findElements('top').firstOrNull?.getAttribute('style') ?? 'none';
      final bBottom = border.findElements('bottom').firstOrNull?.getAttribute('style') ?? 'none';
      final vRaw = c.findElements('v').firstOrNull?.innerText ?? '';
      final sstText = (c.getAttribute('t') == 's' && vRaw.isNotEmpty) ? siList[int.parse(vRaw)] : vRaw;
      print('$cellRef: s=$sIdx applyBorder=$applyBorder (L:$bLeft, R:$bRight, T:$bTop, B:$bBottom) text="${sstText.replaceAll('\n', ' ')}"');
    }
  });

  test('Inspect user exported file 26-15547', () async {
    final path = r'C:\Users\cabarcas\Downloads\WartungsTool_Exports\Inspektion_26-15547-AB_2026-10-15_10-59-12.xlsx';
    final file = File(path);
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml')!;
    final stylesFile = archive.findFile('xl/styles.xml')!;
    final sheetXml = XmlDocument.parse(utf8.decode(sheetFile.content as List<int>));
    final stylesXml = XmlDocument.parse(utf8.decode(stylesFile.content as List<int>));

    final borders = stylesXml.findAllElements('borders').first.findElements('border').toList();
    final cellXfs = stylesXml.findAllElements('cellXfs').first.findElements('xf').toList();

    print('\n================ USER FILE ROW 3 CELLS ================');
    final row3 = sheetXml.findAllElements('row').firstWhere((r) => r.getAttribute('r') == '3');
    for (final c in row3.findElements('c')) {
      final cellRef = c.getAttribute('r')!;
      final sIdx = int.tryParse(c.getAttribute('s') ?? '') ?? 0;
      final xf = cellXfs[sIdx];
      final borderId = int.parse(xf.getAttribute('borderId') ?? '0');
      final fillId = int.parse(xf.getAttribute('fillId') ?? '0');
      final applyBorder = xf.getAttribute('applyBorder');
      final border = borders[borderId];
      final bLeft = border.findElements('left').firstOrNull?.getAttribute('style') ?? 'none';
      final bRight = border.findElements('right').firstOrNull?.getAttribute('style') ?? 'none';
      final bTop = border.findElements('top').firstOrNull?.getAttribute('style') ?? 'none';
      final bBottom = border.findElements('bottom').firstOrNull?.getAttribute('style') ?? 'none';
      print('$cellRef: s=$sIdx applyBorder=$applyBorder borderId=$borderId(L:$bLeft, R:$bRight, T:$bTop, B:$bBottom) fillId=$fillId');
    }

    final sstFile = archive.findFile('xl/sharedStrings.xml')!;
    final sstXml = XmlDocument.parse(utf8.decode(sstFile.content as List<int>));
    final siList = sstXml.findAllElements('si').map((si) => si.findAllElements('t').map((t) => t.innerText).join()).toList();

    print('\n================ USER FILE ROW 4 CELLS ================');
    final row4 = sheetXml.findAllElements('row').firstWhere((r) => r.getAttribute('r') == '4');
    for (final c in row4.findElements('c')) {
      final cellRef = c.getAttribute('r')!;
      final sIdx = int.tryParse(c.getAttribute('s') ?? '') ?? 0;
      final xf = cellXfs[sIdx];
      final borderId = int.parse(xf.getAttribute('borderId') ?? '0');
      final fillId = int.parse(xf.getAttribute('fillId') ?? '0');
      final applyBorder = xf.getAttribute('applyBorder');
      final border = borders[borderId];
      final bLeft = border.findElements('left').firstOrNull?.getAttribute('style') ?? 'none';
      final bRight = border.findElements('right').firstOrNull?.getAttribute('style') ?? 'none';
      final bTop = border.findElements('top').firstOrNull?.getAttribute('style') ?? 'none';
      final bBottom = border.findElements('bottom').firstOrNull?.getAttribute('style') ?? 'none';
      final vRaw = c.findElements('v').firstOrNull?.innerText ?? '';
      final sstText = (c.getAttribute('t') == 's' && vRaw.isNotEmpty) ? siList[int.parse(vRaw)] : vRaw;
      print('$cellRef: text="$sstText" s=$sIdx applyBorder=$applyBorder borderId=$borderId(L:$bLeft, R:$bRight, T:$bTop, B:$bBottom) fillId=$fillId');
    }
  });

  test('Inspect exported file Inspektion_26-15337', () async {
    final file = File('test/test_data/test_template/Inspektion_26-15337-AB_2026-10-07_10-58-32.xlsx');
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml')!;
    final stylesFile = archive.findFile('xl/styles.xml')!;
    final sheetXml = XmlDocument.parse(utf8.decode(sheetFile.content as List<int>));
    final stylesXml = XmlDocument.parse(utf8.decode(stylesFile.content as List<int>));

    final borders = stylesXml.findAllElements('borders').first.findElements('border').toList();
    final cellXfs = stylesXml.findAllElements('cellXfs').first.findElements('xf').toList();

    print('\n================ INSPEKTION 26-15337 ROW 3 CELLS ================');
    final row3 = sheetXml.findAllElements('row').firstWhere((r) => r.getAttribute('r') == '3');
    for (final c in row3.findElements('c')) {
      final cellRef = c.getAttribute('r')!;
      final sIdx = int.tryParse(c.getAttribute('s') ?? '') ?? 0;
      final xf = cellXfs[sIdx];
      final borderId = int.parse(xf.getAttribute('borderId') ?? '0');
      final fillId = int.parse(xf.getAttribute('fillId') ?? '0');
      final applyBorder = xf.getAttribute('applyBorder');
      final border = borders[borderId];
      final bLeft = border.findElements('left').firstOrNull?.getAttribute('style') ?? 'none';
      final bRight = border.findElements('right').firstOrNull?.getAttribute('style') ?? 'none';
      final bTop = border.findElements('top').firstOrNull?.getAttribute('style') ?? 'none';
      final bBottom = border.findElements('bottom').firstOrNull?.getAttribute('style') ?? 'none';
      print('$cellRef: s=$sIdx applyBorder=$applyBorder borderId=$borderId(L:$bLeft, R:$bRight, T:$bTop, B:$bBottom) fillId=$fillId');
    }

    print('\n================ INSPEKTION 26-15337 ROW 4 CELLS ================');
    final row4 = sheetXml.findAllElements('row').firstWhere((r) => r.getAttribute('r') == '4');
    for (final c in row4.findElements('c')) {
      final cellRef = c.getAttribute('r')!;
      final sIdx = int.tryParse(c.getAttribute('s') ?? '') ?? 0;
      final xf = cellXfs[sIdx];
      final borderId = int.parse(xf.getAttribute('borderId') ?? '0');
      final fillId = int.parse(xf.getAttribute('fillId') ?? '0');
      final applyBorder = xf.getAttribute('applyBorder');
      final border = borders[borderId];
      final bLeft = border.findElements('left').firstOrNull?.getAttribute('style') ?? 'none';
      final bRight = border.findElements('right').firstOrNull?.getAttribute('style') ?? 'none';
      final bTop = border.findElements('top').firstOrNull?.getAttribute('style') ?? 'none';
      final bBottom = border.findElements('bottom').firstOrNull?.getAttribute('style') ?? 'none';
      final val = c.findElements('v').firstOrNull?.innerText ?? '';
      print('$cellRef: s=$sIdx applyBorder=$applyBorder borderId=$borderId(L:$bLeft, R:$bRight, T:$bTop, B:$bBottom) fillId=$fillId v=$val');
    }
  });

  test('Inspect master template row 3 and row 4', () async {
    final dir = Directory('test/test_data/test_template');
    final templateFile = dir.listSync().whereType<File>().firstWhere(
      (f) => f.path.contains('template_25-13966'),
    );
    final bytes = await templateFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml')!;
    final stylesFile = archive.findFile('xl/styles.xml')!;
    final sheetXml = XmlDocument.parse(utf8.decode(sheetFile.content as List<int>));
    final stylesXml = XmlDocument.parse(utf8.decode(stylesFile.content as List<int>));

    final borders = stylesXml.findAllElements('borders').first.findElements('border').toList();
    final cellXfs = stylesXml.findAllElements('cellXfs').first.findElements('xf').toList();

    final sstFile = archive.findFile('xl/sharedStrings.xml')!;
    final sstXml = XmlDocument.parse(utf8.decode(sstFile.content as List<int>));
    final siList = sstXml.findAllElements('si').map((si) => si.findAllElements('t').map((t) => t.innerText).join()).toList();

    print('\n================ TEMPLATE ROW 3 CELLS WITH TEXT ================');
    final row3 = sheetXml.findAllElements('row').firstWhere((r) => r.getAttribute('r') == '3');
    for (final c in row3.findElements('c')) {
      final cellRef = c.getAttribute('r')!;
      final sIdx = int.tryParse(c.getAttribute('s') ?? '') ?? 0;
      final xf = cellXfs[sIdx];
      final borderId = int.parse(xf.getAttribute('borderId') ?? '0');
      final applyBorder = xf.getAttribute('applyBorder');
      final border = borders[borderId];
      final bLeft = border.findElements('left').firstOrNull?.getAttribute('style') ?? 'none';
      final bRight = border.findElements('right').firstOrNull?.getAttribute('style') ?? 'none';
      final bTop = border.findElements('top').firstOrNull?.getAttribute('style') ?? 'none';
      final bBottom = border.findElements('bottom').firstOrNull?.getAttribute('style') ?? 'none';
      final vRaw = c.findElements('v').firstOrNull?.innerText ?? '';
      final sstText = (c.getAttribute('t') == 's' && vRaw.isNotEmpty) ? siList[int.parse(vRaw)] : vRaw;
      print('Template $cellRef: text="${sstText.replaceAll('\n', ' ')}" (L:$bLeft, R:$bRight, T:$bTop, B:$bBottom)');
    }

    print('\n================ TEMPLATE ROW 4 CELLS ================');
    final row4 = sheetXml.findAllElements('row').firstWhere((r) => r.getAttribute('r') == '4');
    for (final c in row4.findElements('c')) {
      final cellRef = c.getAttribute('r')!;
      final sIdx = int.tryParse(c.getAttribute('s') ?? '') ?? 0;
      final xf = cellXfs[sIdx];
      final borderId = int.parse(xf.getAttribute('borderId') ?? '0');
      final applyBorder = xf.getAttribute('applyBorder');
      final border = borders[borderId];
      final bLeft = border.findElements('left').firstOrNull?.getAttribute('style') ?? 'none';
      final bRight = border.findElements('right').firstOrNull?.getAttribute('style') ?? 'none';
      final bTop = border.findElements('top').firstOrNull?.getAttribute('style') ?? 'none';
      final bBottom = border.findElements('bottom').firstOrNull?.getAttribute('style') ?? 'none';
      print('Template $cellRef: s=$sIdx applyBorder=$applyBorder borderId=$borderId(L:$bLeft, R:$bRight, T:$bTop, B:$bBottom)');
    }
  });
}
