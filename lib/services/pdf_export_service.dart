import 'dart:io';
import 'dart:ui' show Rect;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';

class PdfExportService {
  static String _boolToStr(dynamic val) {
    if (val == null) return 'Nein';
    if (val is bool) return val ? 'Ja' : 'Nein';
    if (val is num) return val == 1 ? 'Ja' : 'Nein';
    if (val is String) {
      final lower = val.trim().toLowerCase();
      return (lower == '1' || lower == 'true' || lower == 'ja') ? 'Ja' : 'Nein';
    }
    return 'Nein';
  }

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

    final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 14, style: PdfFontStyle.bold);
    final PdfFont headerFont = PdfStandardFont(PdfFontFamily.helvetica, 5.5, style: PdfFontStyle.bold);
    final PdfFont bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 5);

    // Title
    page.graphics.drawString(
      'INSPEKTIONSBERICHT',
      titleFont,
      brush: PdfSolidBrush(PdfColor(13, 71, 161)),
      bounds: Rect.fromLTWH(0, 0, page.getClientSize().width, 20),
    );

    // Metadata Block
    final metaText = 'Kunde: ${insp['clientName'] ?? ''}  |  Objektadresse: ${insp['objectAddress'] ?? ''}\n'
        'Datum: ${insp['date'] ?? ''}  |  Auftragsnr.: ${insp['jobNumber'] ?? ''}  |  Projekt: ${insp['projectNumber'] ?? ''}';

    page.graphics.drawString(
      metaText,
      PdfStandardFont(PdfFontFamily.helvetica, 8),
      bounds: Rect.fromLTWH(0, 22, page.getClientSize().width, 25),
    );

    // Table with individual column headers for each door property
    final headers = [
      'Pos',
      'Tür-Alias',
      'Tür-Nr.',
      'Geschoss',
      'Raumnr.',
      'Raumbezeichnung',
      'Türart',
      'Flügel',
      'Material',
      'Hersteller',
      'Zulassungs-Nr.',
      'Hersteller-Nr.',
      'DoP-Nr.',
      'Baujahr',
      'DIN',
      'Schließer',
      'Schließfolge',
      'Schlossmaß',
      'Bandseite',
      'Bandgegenseite',
      'Abnahme FSA/Antrieb',
      'Sturz in >1m',
      'Sturz in (m)',
      'Sturz aus >1m',
      'Sturz aus (m)',
      'Fluchttürst.',
      'Zutritt',
      'Fluchtwegsit.',
      'Beschilderung',
      'Blindzyl.',
      'PZ-Zyl.',
      'Beschlag',
      'Panikfkt',
      'Fluchtricht.OK',
      'VollpanikStand',
      'FunktionOK',
      'Status',
      'Notizen',
      'Erfasste Mängel',
    ];

    final PdfGrid grid = PdfGrid();
    grid.columns.add(count: headers.length);
    grid.headers.add(1);

    final PdfGridRow headerRow = grid.headers[0];
    for (int col = 0; col < headers.length; col++) {
      headerRow.cells[col].value = headers[col];
      headerRow.cells[col].style.font = headerFont;
      headerRow.cells[col].style.backgroundBrush = PdfSolidBrush(PdfColor(220, 230, 242));
    }

    int posCounter = 1;
    for (final d in doors) {
      final PdfGridRow row = grid.rows.add();
      final errors = d['errors'] as List<Map<String, dynamic>>? ?? [];
      final errorSummary = errors.map((e) => '${e['errorCode'] ?? e['code']}').join(', ');

      final rowValues = [
        '${d['pos'] ?? posCounter}',
        d['doorAlias'] as String? ?? '',
        d['doorNumber'] as String? ?? '',
        d['floor'] as String? ?? '',
        d['roomNumber'] as String? ?? '',
        d['roomDesignation'] as String? ?? '',
        d['doorType'] as String? ?? '',
        '${d['wingCount'] ?? 1}',
        d['material'] as String? ?? '',
        d['manufacturer'] as String? ?? '',
        d['approvalNumber'] as String? ?? '',
        d['manufacturerNumber'] as String? ?? '',
        d['dopNumber'] as String? ?? '',
        d['manufactureYear'] as String? ?? '',
        d['dinConfiguration'] as String? ?? '',
        d['closerType'] as String? ?? '',
        d['closingSequenceSystem'] as String? ?? '',
        d['lockDimensions'] as String? ?? '',
        _boolToStr(d['closerOnHingeSide']),
        _boolToStr(d['closerOnOppositeSide']),
        d['fsaDriveAcceptanceDate'] as String? ?? '',
        _boolToStr(d['lintelHeightInsideOver1m']),
        d['lintelHeightInsideValue'] as String? ?? '',
        _boolToStr(d['lintelHeightOutsideOver1m']),
        d['lintelHeightOutsideValue'] as String? ?? '',
        _boolToStr(d['escapeDoorControl']),
        d['accessControl'] as String? ?? '',
        _boolToStr(d['escapeRouteSituation']),
        _boolToStr(d['escapeRouteSignage']),
        _boolToStr(d['blindCylinder']),
        _boolToStr(d['pzCylinder']),
        d['fittingType'] as String? ?? '',
        d['panicFunction'] as String? ?? '',
        _boolToStr(d['escapeDirectionRespected']),
        _boolToStr(d['fullPanicStandWing']),
        _boolToStr(d['doorFunctionOK']),
        d['junctionStatus'] as String? ?? 'InProgress',
        d['junctionNotes'] as String? ?? '',
        errorSummary.isEmpty ? 'Mängelfrei' : errorSummary,
      ];

      for (int c = 0; c < rowValues.length; c++) {
        row.cells[c].value = rowValues[c];
        row.cells[c].style.font = bodyFont;
      }
      posCounter++;
    }

    grid.draw(
      page: page,
      bounds: Rect.fromLTWH(0, 50, page.getClientSize().width, page.getClientSize().height - 55),
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
    final PdfFont bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 8);

    // Title
    page.graphics.drawString(
      'TÜR-AKTE (PATIENTEN-DOKUMENTATION)',
      titleFont,
      brush: PdfSolidBrush(PdfColor(13, 71, 161)),
      bounds: Rect.fromLTWH(0, 0, page.getClientSize().width, 25),
    );

    final String alias = (door['doorAlias'] ?? '').toString();
    final String doorNum = (door['doorNumber'] ?? '').toString();

    // Door Info Card with All Door Properties
    final doorSpecsText = 'Tür-Alias (QR-Code): $alias  |  Türnummer: $doorNum  |  Pos: ${door['pos'] ?? 0}\n'
        'Geschoss: ${door['floor'] ?? ''}  |  Raumnr.: ${door['roomNumber'] ?? ''}  |  Raum: ${door['roomDesignation'] ?? ''}\n'
        'Türart: ${door['doorType'] ?? ''}  |  Flügelanzahl: ${door['wingCount'] ?? 1}  |  Material: ${door['material'] ?? ''}  |  Hersteller: ${door['manufacturer'] ?? ''}\n'
        'Zulassungs-Nr.: ${door['approvalNumber'] ?? ''}  |  Hersteller-Nr.: ${door['manufacturerNumber'] ?? ''}  |  DoP-Nr.: ${door['dopNumber'] ?? ''}  |  Baujahr: ${door['manufactureYear'] ?? ''}\n'
        'DIN-Richtung: ${door['dinConfiguration'] ?? ''}  |  Schließertyp: ${door['closerType'] ?? ''}  |  Schließfolgeregler: ${door['closingSequenceSystem'] ?? ''}\n'
        'Schlossmaße: ${door['lockDimensions'] ?? ''}  |  Beschlagart: ${door['fittingType'] ?? ''}  |  Panikfunktion: ${door['panicFunction'] ?? ''}  |  Zutrittskontrolle: ${door['accessControl'] ?? ''}\n'
        'Schließer Bandseite: ${_boolToStr(door['closerOnHingeSide'])}  |  Bandgegenseite: ${_boolToStr(door['closerOnOppositeSide'])}  |  Sturzhöhe innen > 1m: ${_boolToStr(door['lintelHeightInsideOver1m'])} (${door['lintelHeightInsideValue'] ?? ''})  |  Sturzhöhe außen > 1m: ${_boolToStr(door['lintelHeightOutsideOver1m'])} (${door['lintelHeightOutsideValue'] ?? ''})\n'
        'Fluchttürsteuerung: ${_boolToStr(door['escapeDoorControl'])}  |  Fluchtwegsituation: ${_boolToStr(door['escapeRouteSituation'])}  |  Beschilderung: ${_boolToStr(door['escapeRouteSignage'])}\n'
        'Blindzylinder: ${_boolToStr(door['blindCylinder'])}  |  PZ-Zylinder: ${_boolToStr(door['pzCylinder'])}  |  Fluchtrichtung beachtet: ${_boolToStr(door['escapeDirectionRespected'])}\n'
        'Vollpanik Standflügel: ${_boolToStr(door['fullPanicStandWing'])}  |  Türfunktion OK: ${_boolToStr(door['doorFunctionOK'])}';

    page.graphics.drawString(
      doorSpecsText,
      bodyFont,
      bounds: Rect.fromLTWH(0, 30, page.getClientSize().width, 115),
    );

    page.graphics.drawString(
      'INSPEKTIONSHISTORIE & VERLAUF',
      subTitleFont,
      brush: PdfSolidBrush(PdfColor(27, 94, 32)),
      bounds: Rect.fromLTWH(0, 150, page.getClientSize().width, 20),
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
      bounds: Rect.fromLTWH(0, 175, page.getClientSize().width, page.getClientSize().height - 185),
    );

    final file = File(outputPath);
    final List<int> bytes = await document.save();
    document.dispose();
    await file.writeAsBytes(bytes);
    return file;
  }
}

