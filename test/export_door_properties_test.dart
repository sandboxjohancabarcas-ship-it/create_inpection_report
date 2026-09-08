import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/excel_export_service.dart';
import 'package:wartungstool/services/pdf_export_service.dart';

void main() {
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
      lintelHeightUnder1m: false,
      lintelHeightOver1m: true,
      lintelHeightValue: 3,
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
}
