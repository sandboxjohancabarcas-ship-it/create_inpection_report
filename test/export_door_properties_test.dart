import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_export_service.dart';
import 'package:wartungstool/services/pdf_export_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Door history export routines handle extended door properties', () async {
    final door = Door(
      id: 1,
      doorAlias: 'TÜR-001',
      doorNumber: '101',
      pos: 1,
      floor: 'OG 1',
      roomNumber: '1.02',
      roomDesignation: 'Büro',
      doorType: 'Holztür',
      wingCount: 1,
      material: 'Holz',
      manufacturer: 'Hörmann',
      approvalNumber: 'Z-6.55-1234',
      manufacturerNumber: 'H-98765',
      dopNumber: 'DoP-2026-001',
      manufactureYear: '2022',
      dinConfiguration: 'DIN Links',
      closerType: 'Obentürschließer',
      closingSequenceSystem: '-',
      lockDimensions: '55/72/8',
      fittingType: 'Drücker/Drücker',
      panicFunction: 'Funktion E',
      accessControl: 'RFID',
      closerOnHingeSide: true,
      closerOnOppositeSide: false,
      lintelHeightInsideOver1m: false,
      lintelHeightOutsideOver1m: true,
      lintelHeightOutsideValue: '3m',
      escapeDoorControl: true,
      escapeRouteSituation: true,
      escapeRouteSignage: true,
      blindCylinder: false,
      pzCylinder: true,
      escapeDirectionRespected: true,
      fullPanicStandWing: false,
      doorFunctionOK: true,
    );

    final historyData = {
      'door': door,
      'historyItems': [
        {
          'inspection': {
            'date': '2026-09-07',
            'clientName': 'Musterfirma',
            'jobNumber': 'A-123',
            'junctionStatus': 'Completed',
            'junctionNotes': 'Alles OK',
          },
          'errors': [],
        }
      ],
    };

    final tempDir = await Directory.systemTemp.createTemp('export_test_');
    final excelPath = '${tempDir.path}/door_history.xlsx';
    final pdfPath = '${tempDir.path}/door_history.pdf';

    final excelFile = await ExcelExportService.exportDoorHistoryReport(historyData, excelPath);
    expect(await excelFile.exists(), isTrue);

    final pdfFile = await PdfExportService.exportDoorHistoryPdf(historyData, pdfPath);
    expect(await pdfFile.exists(), isTrue);

    await tempDir.delete(recursive: true);
  });

  test('PdfExportService.exportSingleInspectionPdf generates single inspection PDF report', () async {
    final db = await DatabaseService.getDb();

    final inspId = await db.insert('inspections', {
      'clientName': 'PDF Client Test',
      'objectAddress': 'PDF Street 1',
      'inspectorName': 'PDF Inspector',
      'jobNumber': 'PDF-JOB-100',
      'projectNumber': 'P-PDF-100',
      'date': '2026-09-21',
      'isLocked': 0,
    });

    final doorId = await db.insert('doors', {
      'pos': 1,
      'doorAlias': 'P-PDF-100-1-EG-101',
      'doorNumber': '101',
      'floor': 'EG',
      'roomNumber': '0.01',
      'roomDesignation': 'Lager',
      'doorType': 'T30',
      'wingCount': 1,
      'material': 'Stahl',
      'manufacturer': 'Teckentrup',
      'approvalNumber': 'Z-6.55-5555',
      'manufacturerNumber': 'MN-99',
      'dopNumber': 'DoP-PDF',
      'manufactureYear': '2025',
      'fsaDriveAcceptanceDate': '2025-01-10',
      'dinConfiguration': 'DIN L',
      'closerType': 'TS93',
      'closingSequenceSystem': '-',
      'lockDimensions': '55/72/9',
      'closerOnHingeSide': 1,
      'closerOnOppositeSide': 1,
      'lintelHeightInsideOver1m': 1,
      'lintelHeightInsideValue': '4m',
      'lintelHeightOutsideOver1m': 1,
      'lintelHeightOutsideValue': '> 5m',
      'escapeDoorControl': 1,
      'accessControl': 'Nein',
      'escapeRouteSituation': 1,
      'escapeRouteSignage': 1,
      'blindCylinder': 0,
      'pzCylinder': 1,
      'fittingType': 'Drücker',
      'panicFunction': 'Nein',
      'escapeDirectionRespected': 1,
      'fullPanicStandWing': 0,
      'doorFunctionOK': 1,
      'notes': 'PDF Export OK',
    });

    await db.insert('inspection_doors', {
      'inspectionId': inspId,
      'doorId': doorId,
      'status': 'Completed',
      'notes': 'PDF Export OK',
    });

    final tempDir = await Directory.systemTemp.createTemp('pdf_single_test_');
    final pdfPath = '${tempDir.path}/single_inspection.pdf';

    final pdfFile = await PdfExportService.exportSingleInspectionPdf(inspId, pdfPath);
    expect(await pdfFile.exists(), isTrue);
    expect(await pdfFile.length(), greaterThan(0));

    await tempDir.delete(recursive: true);
  });
}
