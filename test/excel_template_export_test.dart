import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_export_service.dart';
import 'package:wartungstool/models/models.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ExcelExportService Template Format Tests', () {
    test('exportSingleInspection builds correct matrix headers, defects, notes, and totals', () async {
      final db = await DatabaseService.getDb();

      // Insert dummy inspection
      final inspId = await db.insert('inspections', {
        'clientName': 'Test Client Template',
        'objectAddress': 'Test Address 123',
        'inspectorName': 'Max Inspector',
        'jobNumber': '26-14705-AB',
        'projectNumber': 'P-000175',
        'date': '2026-09-15',
        'isLocked': 1,
      });

      final uniqueAlias = 'BC-${DateTime.now().millisecondsSinceEpoch}';
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
        'notes': 'Door close speed needs adjustment',
      });

      // Link door to inspection
      final junctionId = await db.insert('inspection_doors', {
        'inspectionId': inspId,
        'doorId': doorId,
        'status': 'InProgress',
        'notes': 'Door close speed needs adjustment',
      });

      // Insert error catalog item
      final errorId = await db.insert('error_catalog', {
        'code': 'E01',
        'description': 'Schließkraft ungenügend',
        'category': 'Türschließer',
      });

      // Insert defect for door
      await db.insert('inspection_door_errors', {
        'inspectionDoorId': junctionId,
        'errorId': errorId,
        'errorCode': 'E01',
        'quantity': 1,
      });

      final testPath = '${Directory.systemTemp.path}/test_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = await ExcelExportService.exportSingleInspection(inspId, testPath);
      expect(await file.exists(), true);

      final bytes = await file.readAsBytes();
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);
      final sheetName = decoder.tables.keys.first;
      final table = decoder.tables[sheetName]!;

      // Row 0: Metadata
      final metaText = table.rows[0][0]?.toString() ?? '';
      expect(metaText.contains('26-14705-AB'), true);
      expect(metaText.contains('Test Client Template'), true);

      // Row 1: UI Categories
      expect(table.rows[1][0]?.toString(), 'Grundinformationen');
      expect(table.rows[1][6]?.toString(), 'Tür Spezifikationen');
      expect(table.rows[1][11]?.toString(), 'Installation');
      expect(table.rows[1][17]?.toString(), 'Sicherheit & Zugang');
      expect(table.rows[1][27]?.toString(), 'Bewertung');

      // Row 2: Column Headers
      expect(table.rows[2][0]?.toString(), 'Pos.');
      expect(table.rows[2][1]?.toString(), 'Barcode');
      expect(table.rows[2][2]?.toString(), 'Tür Nr.');
      expect(table.rows[2][28]?.toString(), 'E01 Schließkraft ungenügend');
      expect(table.rows[2][29]?.toString(), 'Anmerkung');

      // Row 3: Data Row
      expect(table.rows[3][0]?.toString(), '1');
      expect(table.rows[3][1]?.toString(), uniqueAlias);
      expect(table.rows[3][2]?.toString(), 'T-101');
      expect(table.rows[3][28]?.toString(), '1'); // Defect qty
      expect(table.rows[3][29]?.toString(), 'Door close speed needs adjustment'); // Notes

      // Row 4: Summary Row
      expect(table.rows[4][0]?.toString(), 'Summe für Mängelbeseitigung');
      expect(table.rows[4][28]?.toString(), '1');

      // Cleanup
      await file.delete();
    });
  });
}
