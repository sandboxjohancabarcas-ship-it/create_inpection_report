import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/excel_export_service.dart';
import 'package:wartungstool/services/pdf_export_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Export Door Properties Tests (Excel & PDF)', () {
    late String tempDir;

    setUp(() async {
      final systemTemp = Directory.systemTemp.createTempSync('export_test_');
      tempDir = systemTemp.path;
    });

    tearDown(() {
      final dir = Directory(tempDir);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    test('Excel single inspection export runs and generates valid xlsx file', () async {
      final doorMap = {
        'id': 1,
        'pos': 1,
        'doorAlias': 'TEST-ALIAS-01',
        'doorNumber': 'T-101',
        'floor': '1. OG',
        'roomNumber': '101',
        'roomDesignation': 'Büro',
        'doorType': 'T30-1',
        'wingCount': 1,
        'material': 'Stahl',
        'manufacturer': 'Hörmann',
        'dinConfiguration': 'DIN Links',
        'closerType': 'TS 5000',
        'closingSequenceSystem': 'Keines',
        'lockDimensions': '65/72/9',
        'closerOnHingeSide': 1,
        'closerOnOppositeSide': 0,
        'lintelHeightUnder1m': 0,
        'escapeDoorControl': 1,
        'accessControl': 'RFID',
        'escapeRouteSituation': 1,
        'escapeRouteSignage': 1,
        'blindCylinder': 0,
        'pzCylinder': 1,
        'fittingType': 'Drücker/Drücker',
        'panicFunction': 'Funktion E',
        'escapeDirectionRespected': 1,
        'fullPanicStandWing': 0,
        'doorFunctionOK': 1,
      };

      final outputPath = p.join(tempDir, 'single_inspection_test.xlsx');

      final historyData = {
        'door': doorMap,
        'historyItems': [
          {
            'inspection': {
              'date': '2026-01-15',
              'clientName': 'Test Kunden AG',
              'objectAddress': 'Hauptstr. 10',
              'jobNumber': 'JOB-99',
              'junctionStatus': 'Completed',
              'junctionNotes': 'Keine Mängel',
            },
            'errors': []
          }
        ]
      };

      final excelFile = await ExcelExportService.exportDoorHistoryReport(historyData, outputPath);
      expect(excelFile.existsSync(), isTrue);
      expect(excelFile.lengthSync(), greaterThan(0));
    });

    test('PDF door history export runs and generates valid pdf file with door properties', () async {
      final door = Door(
        id: 1,
        pos: 1,
        doorAlias: 'TEST-ALIAS-02',
        doorNumber: 'T-102',
        floor: 'EG',
        roomNumber: '002',
        roomDesignation: 'Empfang',
        doorType: 'T90-2',
        wingCount: 2,
        material: 'Holz',
        manufacturer: 'Dorma',
        dinConfiguration: 'DIN Rechts',
        closerType: 'TS 93',
        closingSequenceSystem: 'GSR',
        lockDimensions: '55/72/8',
        closerOnHingeSide: false,
        closerOnOppositeSide: true,
        lintelHeightUnder1m: true,
        escapeDoorControl: false,
        accessControl: 'Keine',
        escapeRouteSituation: true,
        escapeRouteSignage: true,
        blindCylinder: true,
        pzCylinder: false,
        fittingType: 'Knauf/Drücker',
        panicFunction: 'Funktion D',
        escapeDirectionRespected: true,
        fullPanicStandWing: true,
        doorFunctionOK: true,
      );

      final outputPath = p.join(tempDir, 'door_history_test.pdf');
      final historyData = {
        'door': door,
        'historyItems': [
          {
            'inspection': {
              'date': '2026-02-20',
              'clientName': 'Musterbau GmbH',
              'jobNumber': 'JOB-100',
              'junctionStatus': 'InProgress',
              'junctionNotes': 'Mangel an Dichtung',
            },
            'errors': [
              {'errorCode': 'M-01', 'catalogDescription': 'Beschädigte Dichtung'}
            ]
          }
        ]
      };

      final pdfFile = await PdfExportService.exportDoorHistoryPdf(historyData, outputPath);
      expect(pdfFile.existsSync(), isTrue);
      expect(pdfFile.lengthSync(), greaterThan(0));
    });

    test('PDF single inspection export runs and generates valid pdf file with individual property columns', () async {
      final outputPath = p.join(tempDir, 'single_inspection_test.pdf');
      final pdfFile = await PdfExportService.exportDoorHistoryPdf({
        'door': {
          'id': 1,
          'pos': 1,
          'doorAlias': 'ALIAS-PDF-01',
          'doorNumber': 'T-200',
          'floor': 'EG',
          'roomNumber': '001',
          'roomDesignation': 'Foyer',
          'doorType': 'T30',
          'wingCount': 1,
          'material': 'Stahl',
          'manufacturer': 'Hörmann',
          'dinConfiguration': 'DIN L',
          'closerType': 'TS5000',
          'closingSequenceSystem': 'Keines',
          'lockDimensions': '65/72',
          'closerOnHingeSide': 1,
          'closerOnOppositeSide': 0,
          'lintelHeightUnder1m': 0,
          'escapeDoorControl': 1,
          'accessControl': 'RFID',
          'escapeRouteSituation': 1,
          'escapeRouteSignage': 1,
          'blindCylinder': 0,
          'pzCylinder': 1,
          'fittingType': 'Drücker',
          'panicFunction': 'E',
          'escapeDirectionRespected': 1,
          'fullPanicStandWing': 0,
          'doorFunctionOK': 1,
        },
        'historyItems': []
      }, outputPath);

      expect(pdfFile.existsSync(), isTrue);
      expect(pdfFile.lengthSync(), greaterThan(0));
    });
  });
}
