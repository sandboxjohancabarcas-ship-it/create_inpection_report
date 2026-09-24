import 'dart:io';
import 'dart:math';
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

  static String _formatLintelHeight(dynamic isOver1m, dynamic heightValue) {
    final valStr = heightValue?.toString().trim() ?? '';
    final bool isTrue = (isOver1m == true || isOver1m == 1 || isOver1m == '1' || isOver1m == 'true' || isOver1m == 'Ja' || isOver1m == 'ja');
    if (valStr.isNotEmpty) return valStr;
    if (isTrue) return 'X';
    return '';
  }

  static String _formatFloor(dynamic val) {
    if (val == null) return '';
    final s = val.toString().trim();
    if (s.isEmpty || s == 'null') return '';
    return s
        .replaceAllMapped(RegExp(r'^(\d+)\s*\.\s*(OG|UG)', caseSensitive: false), (m) => '${m[1]}.${m[2]?.toUpperCase()}')
        .replaceAllMapped(RegExp(r'^(EG|UG|KG|DG)$', caseSensitive: false), (m) => m[1]!.toUpperCase());
  }

  /// Exports a single inspection report to a formatted PDF document
  static Future<File> exportSingleInspectionPdf(int inspectionId, String outputPath) async {
    final data = await DatabaseService.getSingleInspectionExportData(inspectionId);
    if (data.isEmpty) {
      throw Exception('Inspektionsdaten nicht gefunden.');
    }

    final insp = data['inspection'] as Map<String, dynamic>;
    final doors = List<Map<String, dynamic>>.from(data['doors'] as List<Map<String, dynamic>>);

    // Sort doors ascending by Pos. (pos)
    doors.sort((a, b) {
      final posA = (a['pos'] as num?)?.toInt() ?? 999999;
      final posB = (b['pos'] as num?)?.toInt() ?? 999999;
      if (posA != posB) return posA.compareTo(posB);
      final numA = (a['doorNumber'] as String? ?? '');
      final numB = (b['doorNumber'] as String? ?? '');
      return numA.compareTo(numB);
    });

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
    document.pageSettings.margins.all = 12; // Snug margins maximizing usable landscape printable width
    final page = document.pages.add();
    final pageWidth = page.getClientSize().width;

    final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);
    final PdfFont headerFont = PdfStandardFont(PdfFontFamily.helvetica, 5.5, style: PdfFontStyle.bold);
    final PdfFont bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 5);

    final centerFormat = PdfStringFormat(
      alignment: PdfTextAlignment.center,
      lineAlignment: PdfVerticalAlignment.middle,
    );
    final leftFormat = PdfStringFormat(
      alignment: PdfTextAlignment.left,
      lineAlignment: PdfVerticalAlignment.middle,
    );
    final noWrapCenterFormat = PdfStringFormat(
      alignment: PdfTextAlignment.center,
      lineAlignment: PdfVerticalAlignment.middle,
      wordWrap: PdfWordWrapType.none,
    );

    // Title
    page.graphics.drawString(
      'INSPEKTIONSBERICHT',
      titleFont,
      brush: PdfSolidBrush(PdfColor(13, 71, 161)),
      bounds: Rect.fromLTWH(0, 0, pageWidth, 16),
    );

    // Metadata Block
    final metaText = 'Kunde: ${insp['clientName'] ?? ''} | Objekt: ${insp['objectAddress'] ?? ''} | Datum: ${insp['date'] ?? ''} | Auftragsnr.: ${insp['jobNumber'] ?? ''} | Projekt: ${insp['projectNumber'] ?? ''} | Prüfer: ${insp['inspectorName'] ?? ''}';

    page.graphics.drawString(
      metaText,
      PdfStandardFont(PdfFontFamily.helvetica, 7),
      bounds: Rect.fromLTWH(0, 18, pageWidth, 18),
    );

    final totalCols = 34 + sortedDefectKeys.length + 1; // 34 fixed + defects + 1 for Anmerkung
    final notesColIdx = 34 + sortedDefectKeys.length;

    final PdfGrid grid = PdfGrid();
    grid.style.cellPadding = PdfPaddings(left: 0.6, right: 0.6, top: 1.2, bottom: 1.2);

    grid.columns.add(count: totalCols);

    // Fixed Headers matching Excel export (0..33)
    final fixedHeaders = [
      'Pos.',
      'Barcode',
      'Tür Nr.',
      'Etage',
      'Raum Nr.',
      'Raumbezeichnung',
      'Türtyp (T30/RS/T90/Panik P/WK/usw.)',
      'Zulassungsnummer',
      'Türhersteller / Türsystem',
      'Herstellernummer',
      'DoP-Nummer (Leistungserklärung)',
      'Baujahr',
      'Flügelanzahl',
      'Türmaterial / Türart',
      'DIN L/R',
      'Türschließer / Automatikantrieb',
      'GSR / EMF / EMR',
      'Schloßmaße',
      'Abnahme FSA / Antrieb',
      'Türschließer auf Bandseite',
      'Türschließer auf Bandgegenseite',
      'Sturzhöhe innen über 1m',
      'Sturzhöhe außen über 1m',
      'Zutrittskontrolle',
      'Fluchtürsteuerung / Türwächter',
      'Fluchtwegsituation',
      'Fluchwegbeschilderung',
      'Blindzylinder',
      'PZ-Zylinder',
      'Garnitur',
      'Panikfunktion',
      'Fluchtrichtung eingehalten',
      'Vollpanik (Standflügel)',
      'Tür einschl. Komponenten in ordentlicher Funktion',
    ];

    int maxHeaderChars = 20;
    for (final h in fixedHeaders) {
      if (h.length > maxHeaderChars) maxHeaderChars = h.length;
    }
    for (final k in sortedDefectKeys) {
      final label = defectMap[k]!;
      if (label.length > maxHeaderChars) maxHeaderChars = label.length;
    }

    // Base proportional weights for snug column sizing (matching Excel dynamic widths)
    final Map<int, double> baseColWidths = {
      0: 16.0,  // Pos.
      1: 22.0,  // Barcode
      2: 22.0,  // Tür Nr.
      3: 18.0,  // Etage
      4: 16.0,  // Raum Nr.
      5: 38.0,  // Raumbezeichnung
      6: 24.0,  // Türtyp
      7: 22.0,  // Zulassung
      8: 24.0,  // Hersteller
      9: 18.0,  // Herstellernr
      10: 18.0, // DoP-Nr
      11: 16.0, // Baujahr
      12: 12.0, // Flügel
      13: 20.0, // Material
      14: 12.0, // DIN
      15: 22.0, // Schließer
      16: 20.0, // Schließfolge
      17: 18.0, // Schlossmaß
      18: 20.0, // Abnahme FSA
      19: 12.0, // Bandseite
      20: 12.0, // Bandgegenseite
      21: 14.0, // Sturz in >1m
      22: 14.0, // Sturz aus >1m
      23: 18.0, // Zutritt
      24: 18.0, // Fluchttürst.
      25: 12.0, // Fluchtwegsit.
      26: 12.0, // Beschilderung
      27: 12.0, // Blindzyl.
      28: 12.0, // PZ-Zyl.
      29: 18.0, // Beschlag
      30: 18.0, // Panikfkt
      31: 12.0, // Fluchtricht.OK
      32: 12.0, // Vollpanik
      33: 12.0, // Okay
    };

    for (int i = 0; i < sortedDefectKeys.length; i++) {
      baseColWidths[34 + i] = 12.0; // Defect columns (compact)
    }
    baseColWidths[notesColIdx] = 36.0; // Anmerkung

    double totalBaseWidth = 0.0;
    for (int c = 0; c < totalCols; c++) {
      totalBaseWidth += (baseColWidths[c] ?? 16.0);
    }
    final scale = pageWidth / totalBaseWidth;
    for (int c = 0; c < totalCols; c++) {
      grid.columns[c].width = (baseColWidths[c] ?? 16.0) * scale;
    }

    // ── 2 HEADER ROWS (Matching Excel Structure) ───────────────────────────
    grid.headers.add(2);

    final PdfGridRow categoryRow = grid.headers[0];
    final PdfGridRow colHeaderRow = grid.headers[1];

    final catBg = PdfSolidBrush(PdfColor(31, 73, 125)); // #1F497D Dark Blue
    final catFont = PdfStandardFont(PdfFontFamily.helvetica, 5.5, style: PdfFontStyle.bold);
    final catBorderPen = PdfPen(PdfColor(31, 73, 125), width: 0.5);
    final whiteCenterFormat = PdfStringFormat(
      alignment: PdfTextAlignment.center,
      lineAlignment: PdfVerticalAlignment.middle,
    );

    categoryRow.height = 16.0;
    for (int c = 0; c < totalCols; c++) {
      categoryRow.cells[c].style.backgroundBrush = catBg;
      categoryRow.cells[c].style.borders.all = catBorderPen;
      categoryRow.cells[c].style.font = catFont;
      categoryRow.cells[c].style.textBrush = PdfSolidBrush(PdfColor(255, 255, 255));
      categoryRow.cells[c].style.stringFormat = whiteCenterFormat;
      categoryRow.cells[c].value = '';
    }

    // Row 1 Grouped Categories (Merged Spans)
    categoryRow.cells[0].columnSpan = 6;
    categoryRow.cells[0].value = 'Grundinformationen';

    categoryRow.cells[6].columnSpan = 12;
    categoryRow.cells[6].value = 'Tür Spezifikationen';

    categoryRow.cells[18].columnSpan = 5;
    categoryRow.cells[18].value = 'Installation';

    categoryRow.cells[23].columnSpan = 10;
    categoryRow.cells[23].value = 'Sicherheit & Zugang';

    // Col 33: Okay (single cell, drawn rotated in beginCellLayout)
    categoryRow.cells[33].columnSpan = 1;
    categoryRow.cells[33].value = '';

    if (sortedDefectKeys.isNotEmpty) {
      categoryRow.cells[34].columnSpan = sortedDefectKeys.length;
      categoryRow.cells[34].value = 'Mängelhinweise [${insp['jobNumber'] ?? ''}]';
    }

    // Notes Col: Anmerkung (single cell, drawn rotated in beginCellLayout)
    categoryRow.cells[notesColIdx].columnSpan = 1;
    categoryRow.cells[notesColIdx].value = '';

    // Row 2 Rotated Column Headers Setup
    final dynamicHeaderHeight = (max(75.0, min(140.0, maxHeaderChars * 2.9)));
    colHeaderRow.height = dynamicHeaderHeight;

    final headerBorderPen = PdfPen(PdfColor(0, 0, 0), width: 0.6);
    final fixedHeaderBg = PdfSolidBrush(PdfColor(217, 225, 242)); // #D9E1F2
    final defectHeaderBg = PdfSolidBrush(PdfColor(252, 228, 214)); // #FCE4D6
    final notesHeaderBg = PdfSolidBrush(PdfColor(226, 239, 218)); // #E2EFDA

    final allColumnHeaders = <String>[
      ...fixedHeaders,
      ...sortedDefectKeys.map((k) => defectMap[k]!),
      'Anmerkung',
    ];

    for (int c = 0; c < totalCols; c++) {
      colHeaderRow.cells[c].value = ''; // Clean so default layout does not draw horizontal text
      colHeaderRow.cells[c].style.borders.all = headerBorderPen;
      if (c < 34) {
        colHeaderRow.cells[c].style.backgroundBrush = fixedHeaderBg;
      } else if (c < notesColIdx) {
        colHeaderRow.cells[c].style.backgroundBrush = defectHeaderBg;
      } else {
        colHeaderRow.cells[c].style.backgroundBrush = notesHeaderBg;
      }
    }

    // Register custom drawing for 90-degree rotated headers on endCellLayout (drawn on top of cell backgrounds)
    grid.endCellLayout = (Object sender, PdfGridEndCellLayoutArgs args) {
      final bounds = args.bounds;
      final cellIdx = args.cellIndex;

      // Category Header Row 0 (Y from ~36.0 to ~52.0)
      if (bounds.top >= 36.0 && bounds.top < 52.0) {
        if (cellIdx == 33) {
          final g = args.graphics;
          g.save();
          g.translateTransform(bounds.left + (bounds.width / 2) + 1.8, bounds.bottom - 2.5);
          g.rotateTransform(-90);
          g.drawString(
            'Okay',
            PdfStandardFont(PdfFontFamily.helvetica, 5.0, style: PdfFontStyle.bold),
            brush: PdfSolidBrush(PdfColor(255, 255, 255)),
          );
          g.restore();
        } else if (cellIdx == notesColIdx) {
          final g = args.graphics;
          g.save();
          g.translateTransform(bounds.left + (bounds.width / 2) + 1.8, bounds.bottom - 2.5);
          g.rotateTransform(-90);
          g.drawString(
            'Anmerkung',
            PdfStandardFont(PdfFontFamily.helvetica, 5.0, style: PdfFontStyle.bold),
            brush: PdfSolidBrush(PdfColor(255, 255, 255)),
          );
          g.restore();
        }
      }
      // Column Header Row 1 (Y from ~52.0 to ~52.0 + dynamicHeaderHeight)
      else if (bounds.top >= 52.0 && bounds.top < (54.0 + dynamicHeaderHeight / 2)) {
        if (cellIdx < allColumnHeaders.length) {
          final text = allColumnHeaders[cellIdx];
          final g = args.graphics;
          g.save();
          g.translateTransform(bounds.left + (bounds.width / 2) + 1.8, bounds.bottom - 3.0);
          g.rotateTransform(-90);
          g.drawString(
            text,
            PdfStandardFont(PdfFontFamily.helvetica, 4.6, style: PdfFontStyle.bold),
            brush: PdfSolidBrush(PdfColor(0, 0, 0)),
          );
          g.restore();
        }
      }
    };

    // ── DATA ROWS ──────────────────────────────────────────────────────────
    int posCounter = 1;
    final Map<String, int> defectTotals = {};
    final centerCols = {0, 2, 3, 12, 14, 19, 20, 21, 22, 25, 26, 27, 28, 31, 32, 33};

    final rowBorderPen = PdfPen(PdfColor(217, 217, 217), width: 0.5); // #D9D9D9 thin border
    final evenRowBg = PdfSolidBrush(PdfColor(255, 255, 255)); // #FFFFFF
    final oddRowBg = PdfSolidBrush(PdfColor(248, 250, 252)); // #F8FAFC

    for (int r = 0; r < doors.length; r++) {
      final d = doors[r];
      final PdfGridRow row = grid.rows.add();
      final isEven = (r % 2 == 0);
      final currentBg = isEven ? evenRowBg : oddRowBg;

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

      final floorVal = _formatFloor(d['floor']);

      final rowValues = [
        '${d['pos'] ?? posCounter}',
        d['doorAlias'] as String? ?? '',
        d['doorNumber'] as String? ?? '',
        floorVal,
        d['roomNumber'] as String? ?? '',
        d['roomDesignation'] as String? ?? '',
        d['doorType'] as String? ?? '',
        d['approvalNumber'] as String? ?? '?',
        d['manufacturer'] as String? ?? '',
        d['manufacturerNumber'] as String? ?? '?',
        d['dopNumber'] as String? ?? '?',
        d['manufactureYear'] as String? ?? '?',
        '${d['wingCount'] ?? 1}',
        d['material'] as String? ?? '',
        d['dinConfiguration'] as String? ?? '',
        d['closerType'] as String? ?? '',
        d['closingSequenceSystem'] as String? ?? '',
        d['lockDimensions'] as String? ?? '',
        d['fsaDriveAcceptanceDate'] as String? ?? '?',
        _xStr(d['closerOnHingeSide']),
        _xStr(d['closerOnOppositeSide']),
        _formatLintelHeight(d['lintelHeightInsideOver1m'], d['lintelHeightInsideValue']),
        _formatLintelHeight(d['lintelHeightOutsideOver1m'], d['lintelHeightOutsideValue']),
        d['accessControl'] as String? ?? 'Nein',
        d['escapeDoorControl'] == true ? 'Ja' : 'Nein',
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
        row.cells[c].style.backgroundBrush = currentBg;
        row.cells[c].style.borders.all = rowBorderPen;

        if (c == 0 || c == 2 || c == 3) {
          row.cells[c].style.stringFormat = noWrapCenterFormat;
        } else {
          row.cells[c].style.stringFormat = centerCols.contains(c) ? centerFormat : leftFormat;
        }
      }

      for (int i = 0; i < sortedDefectKeys.length; i++) {
        final key = sortedDefectKeys[i];
        final colIdx = 34 + i;
        if (doorDefectQtyMap.containsKey(key)) {
          final qty = doorDefectQtyMap[key]!;
          row.cells[colIdx].value = '$qty';
          defectTotals[key] = (defectTotals[key] ?? 0) + qty;
        } else {
          row.cells[colIdx].value = '';
        }
        row.cells[colIdx].style.font = bodyFont;
        row.cells[colIdx].style.stringFormat = centerFormat;
        row.cells[colIdx].style.backgroundBrush = currentBg;
        row.cells[colIdx].style.borders.all = rowBorderPen;
      }

      final doorNotes = (d['notes'] ?? d['junctionNotes'] ?? '').toString();
      row.cells[notesColIdx].value = doorNotes;
      row.cells[notesColIdx].style.font = bodyFont;
      row.cells[notesColIdx].style.stringFormat = leftFormat;
      row.cells[notesColIdx].style.backgroundBrush = currentBg;
      row.cells[notesColIdx].style.borders.all = rowBorderPen;

      posCounter++;
    }

    // ── SUMMARY ROW (Totals) ───────────────────────────────────────────────
    final PdfGridRow summaryRow = grid.rows.add();
    final summaryBorderPen = PdfPen(PdfColor(0, 0, 0), width: 1.0);
    final summaryBg = PdfSolidBrush(PdfColor(226, 239, 218)); // #E2EFDA

    for (int c = 0; c < totalCols; c++) {
      summaryRow.cells[c].style.backgroundBrush = summaryBg;
      summaryRow.cells[c].style.borders.top = summaryBorderPen;
      summaryRow.cells[c].style.borders.bottom = summaryBorderPen;
      summaryRow.cells[c].style.borders.left = rowBorderPen;
      summaryRow.cells[c].style.borders.right = rowBorderPen;
    }

    // Merge columns 0 to 33 for the summary label on this special row
    summaryRow.cells[0].columnSpan = 34;
    summaryRow.cells[0].value = 'Summe für Mängelbeseitigung';
    summaryRow.cells[0].style.font = headerFont;
    summaryRow.cells[0].style.stringFormat = leftFormat;

    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final key = sortedDefectKeys[i];
      final colIdx = 34 + i;
      final total = defectTotals[key] ?? 0;
      summaryRow.cells[colIdx].value = '$total';
      summaryRow.cells[colIdx].style.font = headerFont;
      summaryRow.cells[colIdx].style.stringFormat = centerFormat;
    }

    grid.draw(
      page: page,
      bounds: Rect.fromLTWH(0, 38, pageWidth, page.getClientSize().height - 42),
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
        'Geschoss: ${_formatFloor(door['floor'])}  |  Raumnr.: ${door['roomNumber'] ?? ''}  |  Raum: ${door['roomDesignation'] ?? ''}\n'
        'Türart: ${door['doorType'] ?? ''}  |  Flügelanzahl: ${door['wingCount'] ?? 1}  |  Material: ${door['material'] ?? ''}  |  Hersteller: ${door['manufacturer'] ?? ''}\n'
        'Zulassungs-Nr.: ${door['approvalNumber'] ?? ''}  |  Hersteller-Nr.: ${door['manufacturerNumber'] ?? ''}  |  DoP-Nr.: ${door['dopNumber'] ?? ''}  |  Baujahr: ${door['manufactureYear'] ?? ''}\n'
        'DIN-Richtung: ${door['dinConfiguration'] ?? ''}  |  Schließertyp: ${door['closerType'] ?? ''}  |  Schließfolgeregler: ${door['closingSequenceSystem'] ?? ''}\n'
        'Schlossmaße: ${door['lockDimensions'] ?? ''}  |  Beschlagart: ${door['fittingType'] ?? ''}  |  Panikfunktion: ${door['panicFunction'] ?? ''}  |  Zutrittskontrolle: ${door['accessControl'] ?? ''}\n'
        'Sturzhöhe auf Bandseite: ${_boolToStr(door['closerOnHingeSide'])}  |  Sturzhöhe auf Gegenseite: ${_boolToStr(door['closerOnOppositeSide'])}  |  Sturzhöhe innen > 1m: ${_formatLintelHeight(door['lintelHeightInsideOver1m'], door['lintelHeightInsideValue'])}  |  Sturzhöhe außen > 1m: ${_formatLintelHeight(door['lintelHeightOutsideOver1m'], door['lintelHeightOutsideValue'])}\n'
        'Abnahme FSA / Antrieb: ${door['fsaDriveAcceptanceDate'] ?? '?'}  |  Fluchttürsteuerung: ${_boolToStr(door['escapeDoorControl'])}  |  Fluchtwegsituation: ${_boolToStr(door['escapeRouteSituation'])}  |  Beschilderung: ${_boolToStr(door['escapeRouteSignage'])}\n'
        'Blindzylinder: ${_boolToStr(door['blindCylinder'])}  |  PZ-Zylinder: ${_boolToStr(door['pzCylinder'])}  |  Fluchtrichtung beachtet: ${_boolToStr(door['escapeDirectionRespected'])}\n'
        'Vollpanik Standflügel: ${_boolToStr(door['fullPanicStandWing'])}  |  Türfunktion OK: ${_boolToStr(door['doorFunctionOK'])}';

    page.graphics.drawString(
      doorSpecsText,
      bodyFont,
      bounds: Rect.fromLTWH(0, 30, page.getClientSize().width, 125),
    );

    page.graphics.drawString(
      'INSPEKTIONSHISTORIE & VERLAUF',
      subTitleFont,
      brush: PdfSolidBrush(PdfColor(27, 94, 32)),
      bounds: Rect.fromLTWH(0, 160, page.getClientSize().width, 20),
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
      bounds: Rect.fromLTWH(0, 185, page.getClientSize().width, page.getClientSize().height - 195),
    );

    final file = File(outputPath);
    final List<int> bytes = await document.save();
    document.dispose();
    await file.writeAsBytes(bytes);
    return file;
  }
}

