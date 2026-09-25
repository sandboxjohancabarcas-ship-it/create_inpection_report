import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/pdf_export_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('PdfExportService multi-page inspection export generates clean subsequent pages without repeating headers', () async {
    final db = await DatabaseService.getDb();

    final inspId = await db.insert('inspections', {
      'clientName': 'MultiPage Client Test',
      'objectAddress': 'Teststraße 99, Berlin',
      'inspectorName': 'Prüfer Mustermann',
      'jobNumber': '26-14332-AB',
      'projectNumber': 'P-2026-MULTI',
      'date': '2026-09-24',
      'isLocked': 0,
    });

    for (int i = 1; i <= 30; i++) {
      final doorId = await db.insert('doors', {
        'pos': i,
        'doorAlias': 'P-2026-MULTI-$i-EG-0$i',
        'doorNumber': 'T-0$i',
        'floor': 'EG',
        'roomNumber': '0.0$i',
        'roomDesignation': 'Büro $i',
        'doorType': 'T30',
        'wingCount': 1,
        'material': 'Stahl',
        'manufacturer': 'Hörmann',
        'approvalNumber': 'Z-6.20-10$i',
        'manufacturerNumber': 'H-10$i',
        'dopNumber': 'DoP-$i',
        'manufactureYear': '2024',
        'fsaDriveAcceptanceDate': '2024-05-10',
        'dinConfiguration': 'DIN L',
        'closerType': 'TS93',
        'closingSequenceSystem': '-',
        'lockDimensions': '55/72/9',
        'closerOnHingeSide': 1,
        'closerOnOppositeSide': 0,
        'lintelHeightInsideOver1m': 1,
        'lintelHeightInsideValue': '2.5m',
        'lintelHeightOutsideOver1m': 0,
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
        'notes': 'Door $i OK',
      });

      await db.insert('inspection_doors', {
        'inspectionId': inspId,
        'doorId': doorId,
        'status': 'Completed',
        'notes': 'Door $i OK',
      });
    }

    final outDir = Directory('test/test_data');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final pdfPath = '${outDir.path}/Inspektion_26-14332-AB_multipage_verified.pdf';

    final file = await PdfExportService.exportSingleInspectionPdf(inspId, pdfPath);
    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(0));

    final doc = PdfDocument(inputBytes: file.readAsBytesSync());
    print('Generated multi-page PDF has ${doc.pages.count} pages');
    expect(doc.pages.count, greaterThan(1), reason: '30 doors should span multiple pages');
    doc.dispose();
  });
}
