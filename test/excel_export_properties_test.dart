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

      final uniqueAlias = 'P-000999-1-EG-T01-${DateTime.now().microsecondsSinceEpoch}';
      final doorId = await db.insert('doors', {
        'pos': 1,
        'doorAlias': uniqueAlias,
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

      // Verify Column Headers (Row 2) - Standard 28 Master Template Columns
      final row2Headers = table.rows[2].map((e) => e?.toString() ?? '').toList();

      expect(row2Headers[0], 'Pos.');
      expect(row2Headers[1], 'Barcode');
      expect(row2Headers[2], 'Tür Nr.');
      expect(row2Headers[3], 'Etage');
      expect(row2Headers[4], 'Raum Nr.');
      expect(row2Headers[5], 'Raumbezeichnung');
      expect(row2Headers[6], 'Türtyp (T30/RS/T90/Panik P/Einbruchschutz WK/usw.)');
      expect(row2Headers[7], 'Flügelanzahl');
      expect(row2Headers[8], 'Türmaterial / Türart (Alurohrrahmen RRAL / Stahlrohrrahmen RRST / Holz / Stahlblech / usw.)');
      expect(row2Headers[9], 'Türhersteller \n Türsystem \n Profilsystem');
      expect(row2Headers[10], 'DIN L/R \n Standflügel/Gangflügel \n Standflügelverriegelung');
      expect(row2Headers[11], 'Türschließer \n Automatikantrieb \n Do = Dorma, Ge = Geze, usw.');
      expect(row2Headers[12], 'GSR = Gleitschienen Schließfolgeregelung \n EMF = elektromagnetische Feststellung \n EMR = mit Rauchmelder');
      expect(row2Headers[13], 'Schloßmaße');
      expect(row2Headers[14], 'Türschließer auf Bandseite');
      expect(row2Headers[15], 'Türschließer auf Bandgegenseite');
      expect(row2Headers[16], 'Sturzhöhe unter 1 Meter');
      expect(row2Headers[17], 'Fluchtürsteuerung \n Türwächter');
      expect(row2Headers[18], 'Zutrittskontrolle');
      expect(row2Headers[19], 'Fluchtwegsituation');
      expect(row2Headers[20], 'Fluchwegbeschilderung vorhanden?');
      expect(row2Headers[21], 'Blindzylinder');
      expect(row2Headers[22], 'PZ-Zylinder');
      expect(row2Headers[23], 'Garnitur D / D - K / D');
      expect(row2Headers[24], 'Panikfunktion B / E / usw.');
      expect(row2Headers[25], 'Fluchtrichtung eingehalten');
      expect(row2Headers[26], 'Vollpanik (Standflügel)');
      expect(row2Headers[27], 'Tür einschl. Komponenten in ordendlicher Funktion');

      // Verify Data Row (Row 3)
      final row3Data = table.rows[3].map((e) => e?.toString() ?? '').toList();
      expect(row3Data[0], '1');
      expect(row3Data[1], uniqueAlias);
      expect(row3Data[2], 'T01');
      expect(row3Data[3], 'EG');
      expect(row3Data[4], '0.01');
      expect(row3Data[5], 'Empfang');
      expect(row3Data[6], 'T90');
      expect(row3Data[7], '2');
      expect(row3Data[8], 'Aluminium');
      expect(row3Data[9], 'Dorma');
      expect(row3Data[10], 'DIN R');
      expect(row3Data[11], 'TS93');
      expect(row3Data[12], 'GSR');
      expect(row3Data[13], '65/72/9');
      expect(row3Data[14], 'X');
      expect(row3Data[15], '');
      expect(row3Data[16], '2m');
      expect(row3Data[17], 'Ja ?');
      expect(row3Data[18], 'RFID');
      expect(row3Data[19], 'X');
      expect(row3Data[20], 'X');
      expect(row3Data[21], '');
      expect(row3Data[22], 'X');
      expect(row3Data[23], 'Drücker');
      expect(row3Data[24], 'Funktion B');
      expect(row3Data[25], 'X');
      expect(row3Data[26], 'X');
      expect(row3Data[27], 'J');

      // Test roundtrip import
      final importResult = await ExcelDataImporter.importFromFile(file);
      expect(importResult.sheetsProcessed, 1);

      await file.delete();
    });
  });
}
