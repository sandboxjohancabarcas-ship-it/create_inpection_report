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

  static String _xStr(dynamic val) {
    if (val == null) return '';
    if (val is bool) return val ? 'X' : '';
    if (val is num) return val == 1 ? 'X' : '';
    if (val is String) {
      final lower = val.trim().toLowerCase();
      return (lower == '1' || lower == 'true' || lower == 'ja' || lower == 'x') ? 'X' : '';
    }
    return '';
  }

  static String _jnStr(dynamic val) {
    if (val == null) return 'N';
    if (val is bool) return val ? 'J' : 'N';
    if (val is num) return val == 1 ? 'J' : 'N';
    if (val is String) {
      final lower = val.trim().toLowerCase();
      return (lower == '1' || lower == 'true' || lower == 'ja' || lower == 'j') ? 'J' : 'N';
    }
    return 'N';
  }

  /// Exports a single inspection report to a formatted PDF document
  static Future<File> exportSingleInspectionPdf(int inspectionId, String outputPath) async {
    final data = await DatabaseService.getSingleInspectionExportData(inspectionId);
    if (data.isEmpty) {
      throw Exception('Inspektionsdaten nicht gefunden.');
    }

    final insp = data['inspection'] as Map<String, dynamic>;
    final doors = data['doors'] as List<Map<String, dynamic>>;

    // Collect all distinct error codes & descriptions across doors in this inspection
    final Map<String, String> defectMap = {};
    for (final d in doors) {
      final errors = d['errors'] as List<Map<String, dynamic>>? ?? [];
      for (final e in errors) {
        final code = (e['errorCode'] ?? e['code'] ?? '') as String;
        final desc = (e['errorDesc'] ?? e['description'] ?? '') as String;
        final key = code.isNotEmpty ? code : desc;
        if (key.isNotEmpty) {
          final label = code.isNotEmpty ? (desc.isNotEmpty ? '$code $desc' : code) : desc;
          defectMap[key] = label;
        }
      }
    }
    final sortedDefectKeys = defectMap.keys.toList()..sort();

    final document = PdfDocument();
    document.pageSettings.orientation = PdfPageOrientation.landscape;
    final page = document.pages.add();

    final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);
    final PdfFont headerFont = PdfStandardFont(PdfFontFamily.helvetica, 4.5, style: PdfFontStyle.bold);
    final PdfFont bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 4.5);

    // Title
    page.graphics.drawString(
      'INSPEKTIONSBERICHT',
      titleFont,
      brush: PdfSolidBrush(PdfColor(13, 71, 161)),
      bounds: Rect.fromLTWH(0, 0, page.getClientSize().width, 16),
    );

    // Metadata Block
    final metaText = 'Kunde: ${insp['clientName'] ?? ''} | Objekt: ${insp['objectAddress'] ?? ''} | Datum: ${insp['date'] ?? ''} | Auftragsnr.: ${insp['jobNumber'] ?? ''} | Projekt: ${insp['projectNumber'] ?? ''} | Prüfer: ${insp['inspectorName'] ?? ''}';

    page.graphics.drawString(
      metaText,
      PdfStandardFont(PdfFontFamily.helvetica, 7),
      bounds: Rect.fromLTWH(0, 18, page.getClientSize().width, 18),
    );

    // Table Column Headers
    final fixedHeaders = [
      'Pos',
      'Barcode',
      'Tür Nr.',
      'Etage',
      'Raum Nr.',
      'Raumbezeichnung',
      'Türtyp',
      'Flügel',
      'Material',
      'Hersteller',
      'DIN',
      'Schließer',
      'Schließfolge',
      'Schlossmaß',
      'Bandseite',
      'Bandgegenseite',
      'Sturz >1m',
      'Fluchttürst.',
      'Zutritt',
      'Fluchtwegsit.',
      'Beschilderung',
      'Blindzyl.',
      'PZ-Zyl.',
      'Beschlag',
      'Panikfkt',
      'Fluchtricht.OK',
      'Vollpanik',
      'Funktion OK',
    ];

    final totalCols = fixedHeaders.length + sortedDefectKeys.length + 1; // +1 for Anmerkung
    final PdfGrid grid = PdfGrid();
    grid.columns.add(count: totalCols);
    grid.headers.add(1);

    final PdfGridRow headerRow = grid.headers[0];
    for (int col = 0; col < fixedHeaders.length; col++) {
      headerRow.cells[col].value = fixedHeaders[col];
      headerRow.cells[col].style.font = headerFont;
      headerRow.cells[col].style.backgroundBrush = PdfSolidBrush(PdfColor(220, 230, 242));
    }

    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final colIdx = fixedHeaders.length + i;
      headerRow.cells[colIdx].value = defectMap[sortedDefectKeys[i]]!;
      headerRow.cells[colIdx].style.font = headerFont;
      headerRow.cells[colIdx].style.backgroundBrush = PdfSolidBrush(PdfColor(255, 235, 238));
    }

    final notesColIdx = fixedHeaders.length + sortedDefectKeys.length;
    headerRow.cells[notesColIdx].value = 'Anmerkung';
    headerRow.cells[notesColIdx].style.font = headerFont;
    headerRow.cells[notesColIdx].style.backgroundBrush = PdfSolidBrush(PdfColor(240, 240, 240));

    int posCounter = 1;
    final Map<String, int> defectTotals = {};

    for (final d in doors) {
      final PdfGridRow row = grid.rows.add();
      final errors = d['errors'] as List<Map<String, dynamic>>? ?? [];
      final Map<String, int> doorDefectQtyMap = {};
      for (final e in errors) {
        final code = (e['errorCode'] ?? e['code'] ?? '') as String;
        final desc = (e['errorDesc'] ?? e['description'] ?? '') as String;
        final key = code.isNotEmpty ? code : desc;
        final qty = (e['quantity'] as num?)?.toInt() ?? 1;
        if (key.isNotEmpty) {
          doorDefectQtyMap[key] = (doorDefectQtyMap[key] ?? 0) + qty;
        }
      }

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
        d['dinConfiguration'] as String? ?? '',
        d['closerType'] as String? ?? '',
        d['closingSequenceSystem'] as String? ?? '',
        d['lockDimensions'] as String? ?? '',
        _xStr(d['closerOnHingeSide']),
        _xStr(d['closerOnOppositeSide']),
        _xStr(d['lintelHeightInsideOver1m'] ?? d['lintelHeightOutsideOver1m']),
        d['escapeDoorControl'] == true ? 'Ja' : 'Nein',
        d['accessControl'] as String? ?? 'Nein',
        _xStr(d['escapeRouteSituation']),
        _xStr(d['escapeRouteSignage']),
        _xStr(d['blindCylinder']),
        _xStr(d['pzCylinder']),
        d['fittingType'] as String? ?? '',
        d['panicFunction'] as String? ?? '',
        _xStr(d['escapeDirectionRespected']),
        _xStr(d['fullPanicStandWing']),
        _jnStr(d['doorFunctionOK']),
      ];

      for (int c = 0; c < rowValues.length; c++) {
        row.cells[c].value = rowValues[c];
        row.cells[c].style.font = bodyFont;
      }

      for (int i = 0; i < sortedDefectKeys.length; i++) {
        final key = sortedDefectKeys[i];
        final colIdx = fixedHeaders.length + i;
        if (doorDefectQtyMap.containsKey(key)) {
          final qty = doorDefectQtyMap[key]!;
          row.cells[colIdx].value = '$qty';
          row.cells[colIdx].style.font = bodyFont;
          defectTotals[key] = (defectTotals[key] ?? 0) + qty;
        } else {
          row.cells[colIdx].value = '';
          row.cells[colIdx].style.font = bodyFont;
        }
      }

      final doorNotes = (d['notes'] ?? d['junctionNotes'] ?? '').toString();
      row.cells[notesColIdx].value = doorNotes;
      row.cells[notesColIdx].style.font = bodyFont;

      posCounter++;
    }

    // Bottom total sum row
    final PdfGridRow summaryRow = grid.rows.add();
    summaryRow.cells[0].value = 'Summe für Mängelbeseitigung';
    summaryRow.cells[0].style.font = headerFont;

    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final key = sortedDefectKeys[i];
      final colIdx = fixedHeaders.length + i;
      final total = defectTotals[key] ?? 0;
      summaryRow.cells[colIdx].value = '$total';
      summaryRow.cells[colIdx].style.font = headerFont;
    }

    grid.draw(
      page: page,
      bounds: Rect.fromLTWH(0, 40, page.getClientSize().width, page.getClientSize().height - 45),
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
    final String provAlias = (door['provisionalAlias'] ?? alias).toString();
    final String doorNum = (door['doorNumber'] ?? '').toString();

    // Door Info Card with All Door Properties
    final doorSpecsText = 'Barcode: $alias  |  Alias: $provAlias  |  Türnummer: $doorNum  |  Pos: ${door['pos'] ?? 0}\n'
        'Geschoss: ${door['floor'] ?? ''}  |  Raumnr.: ${door['roomNumber'] ?? ''}  |  Raum: ${door['roomDesignation'] ?? ''}\n'
        'Türart: ${door['doorType'] ?? ''}  |  Flügelanzahl: ${door['wingCount'] ?? 1}  |  Material: ${door['material'] ?? ''}  |  Hersteller: ${door['manufacturer'] ?? ''}\n'
        'Zulassungs-Nr.: ${door['approvalNumber'] ?? ''}  |  Hersteller-Nr.: ${door['manufacturerNumber'] ?? ''}  |  DoP-Nr.: ${door['dopNumber'] ?? ''}  |  Baujahr: ${door['manufactureYear'] ?? ''}\n'
        'DIN-Richtung: ${door['dinConfiguration'] ?? ''}  |  Schließertyp: ${door['closerType'] ?? ''}  |  Schließfolgeregler: ${door['closingSequenceSystem'] ?? ''}\n'
        'Schlossmaße: ${door['lockDimensions'] ?? ''}  |  Beschlagart: ${door['fittingType'] ?? ''}  |  Panikfunktion: ${door['panicFunction'] ?? ''}  |  Zutrittskontrolle: ${door['accessControl'] ?? ''}\n'
        'Sturzhöhe auf Bandseite: ${_boolToStr(door['closerOnHingeSide'])}  |  Sturzhöhe auf Gegenseite: ${_boolToStr(door['closerOnOppositeSide'])}  |  Sturzhöhe innen > 1m: ${_boolToStr(door['lintelHeightInsideOver1m'])} (${door['lintelHeightInsideValue'] ?? ''})  |  Sturzhöhe außen > 1m: ${_boolToStr(door['lintelHeightOutsideOver1m'])} (${door['lintelHeightOutsideValue'] ?? ''})\n'
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

