import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_export_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ExcelExportService Properties Verification', () {
    test('exportSingleInspection exports current door properties including Sturzhöhe values and modern fields', () async {
      final db = await DatabaseService.getDb();

      final inspId = await db.insert('inspections', {
        'clientName': 'Client Lintel Test',
        'objectAddress': 'Test St 45',
        'inspectorName': 'Inspector Val',
        'jobNumber': 'JOB-999',
        'projectNumber': 'P-000999',
        'date': '2026-09-21',
        'isLocked': 0,
      });

      final doorId = await db.insert('doors', {
        'pos': 1,
        'doorAlias': 'P-000999-1-EG-T01',
        'doorNumber': 'T01',
        'floor': 'EG',
        'roomNumber': '0.01',
        'roomDesignation': 'Empfang',
        'doorType': 'T90',
        'wingCount': 2,
        'material': 'Aluminium',
        'manufacturer': 'Dorma',
        'approvalNumber': 'Z-6.55-9999',
        'manufacturerNumber': 'MN-123456',
        'dopNumber': 'DoP-999-ABC',
        'manufactureYear': '2024',
        'fsaDriveAcceptanceDate': '2024-05-15',
        'dinConfiguration': 'DIN R',
        'closerType': 'TS93',
        'closingSequenceSystem': 'GSR',
        'lockDimensions': '65/72/9',
        'closerOnHingeSide': 1,
        'closerOnOppositeSide': 0,
        'lintelHeightInsideOver1m': 1,
        'lintelHeightInsideValue': '2m',
        'lintelHeightOutsideOver1m': 1,
        'lintelHeightOutsideValue': '> 5m',
        'escapeDoorControl': 1,
        'accessControl': 'RFID',
        'escapeRouteSituation': 1,
        'escapeRouteSignage': 1,
        'blindCylinder': 0,
        'pzCylinder': 1,
        'fittingType': 'Drücker',
        'panicFunction': 'Funktion B',
        'escapeDirectionRespected': 1,
        'fullPanicStandWing': 1,
        'doorFunctionOK': 1,
        'notes': 'Sturzhöhe geprüft',
      });

      await db.insert('inspection_doors', {
        'inspectionId': inspId,
        'doorId': doorId,
        'status': 'Completed',
        'notes': 'Sturzhöhe geprüft',
      });

      final testPath = '${Directory.systemTemp.path}/test_export_properties_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = await ExcelExportService.exportSingleInspection(inspId, testPath);
      expect(await file.exists(), true);

      final bytes = await file.readAsBytes();
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);
      final sheetName = decoder.tables.keys.first;
      final table = decoder.tables[sheetName]!;

      // Verify Column Headers (Row 2)
      final row2Headers = table.rows[2].map((e) => e?.toString() ?? '').toList();

      // "Sturzhöhe unter 1 Meter" MUST NOT exist in headers
      expect(row2Headers.contains('Sturzhöhe unter 1 Meter'), false);

      // Verify new fields and Sturzhöhe headers
      expect(row2Headers[7], 'Zulassungsnummer');
      expect(row2Headers[9], 'Herstellernummer');
      expect(row2Headers[10], 'DoP-Nummer (Leistungserklärung)');
      expect(row2Headers[11], 'Baujahr');
      expect(row2Headers[18], 'Abnahme FSA / Antrieb');
      expect(row2Headers[21], 'Sturzhöhe innen über 1m');
      expect(row2Headers[22], 'Sturzhöhe außen über 1m');

      // Verify Data Row (Row 3)
      final row3Data = table.rows[3].map((e) => e?.toString() ?? '').toList();
      expect(row3Data[7], 'Z-6.55-9999');
      expect(row3Data[9], 'MN-123456');
      expect(row3Data[10], 'DoP-999-ABC');
      expect(row3Data[11], '2024');
      expect(row3Data[18], '2024-05-15');
      expect(row3Data[21], '2m');
      expect(row3Data[22], '> 5m');

      // Test roundtrip import
      final importResult = await ExcelDataImporter.importFromFile(file);
      expect(importResult.sheetsProcessed, 1);

      await file.delete();
    });
  });
}
