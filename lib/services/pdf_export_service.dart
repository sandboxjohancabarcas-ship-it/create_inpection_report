import 'dart:io';
import 'dart:ui' show Rect;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';

class PdfExportService {
  /// Exports a single inspection report to a formatted PDF document
  static Future<File> exportSingleInspectionPdf(int inspectionId, String outputPath) async {
    final data = await DatabaseService.getSingleInspectionExportData(inspectionId);
    if (data.isEmpty) {
      throw Exception('Inspektionsdaten nicht gefunden.');
    }

    final insp = data['inspection'] as Map<String, dynamic>;
    final doors = data['doors'] as List<Map<String, dynamic>>;

    final document = PdfDocument();
    document.pageSettings.orientation = PdfPageOrientation.landscape;
    final page = document.pages.add();

    final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold);
    final PdfFont headerFont = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);
    final PdfFont bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 9);

    // Title
    page.graphics.drawString(
      'INSPEKTIONSBERICHT',
      titleFont,
      brush: PdfSolidBrush(PdfColor(13, 71, 161)),
      bounds: Rect.fromLTWH(0, 0, page.getClientSize().width, 25),
    );

    // Metadata Block
    final metaText = 'Kunde: ${insp['clientName'] ?? ''}\n'
        'Objektadresse: ${insp['objectAddress'] ?? ''}\n'
        'Datum: ${insp['date'] ?? ''}  |  Auftragsnr.: ${insp['jobNumber'] ?? ''}  |  Projekt: ${insp['projectNumber'] ?? ''}';

    page.graphics.drawString(
      metaText,
      bodyFont,
      bounds: Rect.fromLTWH(0, 30, page.getClientSize().width, 45),
    );

    // Table
    final PdfGrid grid = PdfGrid();
    grid.columns.add(count: 8);
    grid.headers.add(1);

    final PdfGridRow headerRow = grid.headers[0];
    headerRow.cells[0].value = 'Pos';
    headerRow.cells[1].value = 'Tür-Nr.';
    headerRow.cells[2].value = 'Geschoss';
    headerRow.cells[3].value = 'Raum';
    headerRow.cells[4].value = 'Hersteller';
    headerRow.cells[5].value = 'Status';
    headerRow.cells[6].value = 'Erfasste Mängel';
    headerRow.cells[7].value = 'Notizen';

    for (int i = 0; i < headerRow.cells.count; i++) {
      headerRow.cells[i].style.font = headerFont;
      headerRow.cells[i].style.backgroundBrush = PdfSolidBrush(PdfColor(220, 230, 242));
    }

    int posCounter = 1;
    for (final d in doors) {
      final PdfGridRow row = grid.rows.add();
      final errors = d['errors'] as List<Map<String, dynamic>>? ?? [];
      final errorSummary = errors.map((e) => '${e['errorCode'] ?? e['code']}').join(', ');

      row.cells[0].value = '$posCounter';
      row.cells[1].value = d['doorNumber'] as String? ?? '';
      row.cells[2].value = d['floor'] as String? ?? '';
      row.cells[3].value = d['roomDesignation'] as String? ?? '';
      row.cells[4].value = d['manufacturer'] as String? ?? '';
      row.cells[5].value = d['junctionStatus'] as String? ?? 'InProgress';
      row.cells[6].value = errorSummary.isEmpty ? 'Mängelfrei' : errorSummary;
      row.cells[7].value = d['junctionNotes'] as String? ?? '';

      for (int i = 0; i < row.cells.count; i++) {
        row.cells[i].style.font = bodyFont;
      }
      posCounter++;
    }

    grid.draw(
      page: page,
      bounds: Rect.fromLTWH(0, 80, page.getClientSize().width, page.getClientSize().height - 90),
    );

    final file = File(outputPath);
    final List<int> bytes = await document.save();
    document.dispose();
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Exports lifetime history of a single door ("Tür-Akte") into a PDF dossier
  static Future<File> exportDoorHistoryPdf(Map<String, dynamic> historyData, String outputPath) async {
    final doorObj = historyData['door'];
    final Map<String, dynamic> door = (doorObj is Door)
        ? doorObj.toMap()
        : (doorObj is Map<String, dynamic> ? doorObj : {});

    final historyItems = historyData['historyItems'] as List<dynamic>? ?? historyData['inspections'] as List<dynamic>? ?? [];

    final document = PdfDocument();
    final page = document.pages.add();

    final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold);
    final PdfFont subTitleFont = PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);
    final PdfFont headerFont = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);
    final PdfFont bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 9);

    // Title
    page.graphics.drawString(
      'TÜR-AKTE (PATIENTEN-DOKUMENTATION)',
      titleFont,
      brush: PdfSolidBrush(PdfColor(13, 71, 161)),
      bounds: Rect.fromLTWH(0, 0, page.getClientSize().width, 25),
    );

    final String alias = (door['doorAlias'] ?? '').toString();
    final String doorNum = (door['doorNumber'] ?? '').toString();

    // Door Info Card
    final doorSpecsText = 'Tür-Alias (QR-Code): $alias\n'
        'Türnummer: $doorNum  |  Geschoss: ${door['floor'] ?? ''}  |  Raum: ${door['roomDesignation'] ?? ''}\n'
        'Hersteller: ${door['manufacturer'] ?? ''}  |  Funktion: ${door['doorFunction'] ?? ''}  |  Brandschutz: ${door['fireProtection'] ?? ''}\n'
        'Breite: ${door['width'] ?? ''} mm  |  Höhe: ${door['height'] ?? ''} mm  |  Baujahr: ${door['constructionYear'] ?? ''}';

    page.graphics.drawString(
      doorSpecsText,
      bodyFont,
      bounds: Rect.fromLTWH(0, 30, page.getClientSize().width, 60),
    );

    page.graphics.drawString(
      'INSPEKTIONSHISTORIE & VERLAUF',
      subTitleFont,
      brush: PdfSolidBrush(PdfColor(27, 94, 32)),
      bounds: Rect.fromLTWH(0, 100, page.getClientSize().width, 20),
    );

    final PdfGrid grid = PdfGrid();
    grid.columns.add(count: 6);
    grid.headers.add(1);

    final PdfGridRow headerRow = grid.headers[0];
    headerRow.cells[0].value = 'Datum';
    headerRow.cells[1].value = 'Kunde';
    headerRow.cells[2].value = 'Auftrag';
    headerRow.cells[3].value = 'Status';
    headerRow.cells[4].value = 'Erfasste Mängel';
    headerRow.cells[5].value = 'Notizen';

    for (int i = 0; i < headerRow.cells.count; i++) {
      headerRow.cells[i].style.font = headerFont;
      headerRow.cells[i].style.backgroundBrush = PdfSolidBrush(PdfColor(230, 245, 233));
    }

    for (final item in historyItems) {
      final PdfGridRow row = grid.rows.add();
      final insp = item is Map ? (item['inspection'] as Map<String, dynamic>? ?? item) : <String, dynamic>{};
      final errors = item is Map ? (item['errors'] as List<dynamic>? ?? []) : [];
      final errorSummary = errors.map((e) {
        if (e is Map) {
          final code = e['errorCode'] ?? e['code'] ?? '';
          final desc = e['catalogDescription'] ?? e['description'] ?? '';
          return '$code: $desc';
        }
        return '';
      }).where((s) => s.isNotEmpty).join('\n');

      row.cells[0].value = (insp['date'] ?? '').toString();
      row.cells[1].value = (insp['clientName'] ?? '').toString();
      row.cells[2].value = (insp['jobNumber'] ?? '').toString();
      row.cells[3].value = (insp['junctionStatus'] ?? insp['status'] ?? '').toString();
      row.cells[4].value = errorSummary.isEmpty ? 'Mängelfrei (Grün)' : errorSummary;
      row.cells[5].value = (insp['junctionNotes'] ?? insp['notes'] ?? '').toString();

      for (int i = 0; i < row.cells.count; i++) {
        row.cells[i].style.font = bodyFont;
      }
    }

    grid.draw(
      page: page,
      bounds: Rect.fromLTWH(0, 125, page.getClientSize().width, page.getClientSize().height - 135),
    );

    final file = File(outputPath);
    final List<int> bytes = await document.save();
    document.dispose();
    await file.writeAsBytes(bytes);
    return file;
  }
}
