import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';

class ExcelExportService {
  /// Wraps text to a maximum line length at word boundaries.
  static String _wrapText(dynamic val, [int maxLineLength = 40]) {
    if (val == null) return '';
    final s = _cleanText(val);
    if (s.isEmpty || maxLineLength <= 0) return s;

    final paragraphs = s.split('\n');
    final resultParagraphs = <String>[];

    for (final para in paragraphs) {
      final trimmedPara = para.trim();
      if (trimmedPara.isEmpty) {
        resultParagraphs.add('');
        continue;
      }
      if (trimmedPara.length <= maxLineLength) {
        resultParagraphs.add(trimmedPara);
        continue;
      }

      final words = trimmedPara.split(RegExp(r'[ \t]+'));
      final lines = <String>[];
      String currentLine = '';

      for (final word in words) {
        if (currentLine.isEmpty) {
          currentLine = word;
        } else if (currentLine.length + 1 + word.length <= maxLineLength) {
          currentLine += ' $word';
        } else {
          lines.add(currentLine);
          currentLine = word;
        }
      }
      if (currentLine.isNotEmpty) {
        lines.add(currentLine);
      }
      resultParagraphs.add(lines.join('\n'));
    }

    return resultParagraphs.join('\n');
  }

  /// Formats multi-line notes cleanly with proper line breaks, wrapped at a maximum of 80 characters.
  static String _cleanNoteText(dynamic val, [int maxLineLength = 80]) {
    if (val == null) return '';
    String s = val.toString();
    s = s.replaceAll('_x000D_', '\n');
    s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    final lines = s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final cleaned = lines.join('\n');
    return _wrapText(cleaned, maxLineLength);
  }

  /// Cleans raw text strings from Excel/database imports, stripping internal artifacts.
  static String _cleanText(dynamic val) {
    if (val == null) return '';
    String s = val.toString();
    s = s.replaceAll('_x000D_', '\n');
    s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.trim();
    if (s == 'null' || s == 'undefined' || s == 'None') return '';
    return s;
  }

  /// Normalizes floor abbreviations (e.g. "1.OG", "2.OG", "EG", "UG", "KG", "DG") keeping them compact without inserted spaces so <=4 char codes fit on one line.
  static String _formatFloor(dynamic val) {
    final s = _cleanText(val);
    if (s.isEmpty) return '';
    return s
        .replaceAllMapped(RegExp(r'^(\d+)\s*\.\s*(OG|UG)', caseSensitive: false), (m) => '${m[1]}.${m[2]?.toUpperCase()}')
        .replaceAllMapped(RegExp(r'^(EG|UG|KG|DG)$', caseSensitive: false), (m) => m[1]!.toUpperCase());
  }

  /// Formats clean checkbox representations ('X' or empty string).
  static String _xStr(dynamic val) {
    if (val == null) return '';
    if (val is bool) return val ? 'X' : '';
    if (val is num) return val == 1 ? 'X' : '';
    if (val is String) {
      final lower = val.trim().toLowerCase();
      return (lower == '1' || lower == 'true' || lower == 'ja' || lower == 'x' || lower == 'j') ? 'X' : '';
    }
    return '';
  }

  /// Formats clean function OK representation ('J' or 'N').
  static String _jnStr(dynamic val) {
    if (val == null) return 'N';
    if (val is bool) return val ? 'J' : 'N';
    if (val is num) return val == 1 ? 'J' : 'N';
    if (val is String) {
      final lower = val.trim().toLowerCase();
      return (lower == '1' || lower == 'true' || lower == 'ja' || lower == 'j' || lower == 'x') ? 'J' : 'N';
    }
    return 'N';
  }

  /// Formats Sturzhöhe values (> 1m), displaying either the custom dimension string or 'X'.
  static String _formatLintelHeight(dynamic isOver1m, dynamic heightValue) {
    final valStr = _cleanText(heightValue);
    final bool isTrue = (isOver1m == true || isOver1m == 1 || isOver1m == '1' || isOver1m == 'true' || isOver1m == 'Ja' || isOver1m == 'ja');
    if (valStr.isNotEmpty) return valStr;
    if (isTrue) return 'X';
    return '';
  }

  /// Formats access control representation ('Ja', 'Nein', or specific system description).
  static String _formatAccessControl(dynamic val) {
    final s = _cleanText(val);
    if (s.isEmpty || s.toLowerCase() == 'nein' || s == '0' || s.toLowerCase() == 'false') return 'Nein';
    if (s.toLowerCase() == 'ja' || s == '1' || s.toLowerCase() == 'true') return 'Ja';
    return _wrapText(s, 40);
  }

  /// Formats escape door control representation ('Nein', 'Ja ?', or specific system description).
  static String _formatEscapeDoorControl(dynamic val) {
    if (val == null) return 'Nein';
    if (val is bool) return val ? 'Ja ?' : 'Nein';
    final s = _cleanText(val);
    if (s.isEmpty || s.toLowerCase() == 'nein' || s == '0' || s.toLowerCase() == 'false') return 'Nein';
    if (s.toLowerCase() == 'ja' || s == '1' || s.toLowerCase() == 'true') return 'Ja ?';
    return _wrapText(s, 40);
  }


  /// Helper to record cell content and compute sharp, snug column widths and row heights.
  static void _setCell(
    Sheet sheet,
    Map<int, double> colWidths,
    Map<int, int> rowLineCounts, {
    required int col,
    required int row,
    required String text,
    required CellStyle style,
    bool trackWidth = true,
  }) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(text);
    cell.cellStyle = style;

    // Minimum column width per column type so multi-digit numbers (like "21", "100", "2.OG") never wrap in Excel UI
    double minColWidth = 1.8;
    if (col == 0) minColWidth = 5.0; // Pos: generous width so numbers like "21", "100", "1000" never wrap in Excel UI
    if (col == 2) minColWidth = 5.5; // Tür Nr: generous width so numbers like "21", "101", "T-01" never wrap
    if (col == 3) minColWidth = 5.0; // Etage: generous width so "2.OG", "1.OG", "EG" never wrap

    if (text.isNotEmpty) {
      final lines = text.split('\n');
      rowLineCounts[row] = max(rowLineCounts[row] ?? 1, lines.length);

      if (trackWidth) {
        for (final line in lines) {
          final len = line.trim().length.toDouble();
          final needed = max(minColWidth, len + 0.5);
          if (needed > (colWidths[col] ?? 0.0)) {
            colWidths[col] = needed;
          }
        }
      }
    } else {
      rowLineCounts[row] = max(rowLineCounts[row] ?? 1, 1);
      if (trackWidth && !colWidths.containsKey(col)) {
        colWidths[col] = minColWidth;
      }
    }
  }

  /// Applies all dynamically computed column widths and row heights to the sheet.
  static void _applyDimensions(
    Sheet sheet,
    Map<int, double> colWidths,
    Map<int, int> rowLineCounts, {
    double defaultRowHeight = 22.0,
    double headerRowHeight = 150.0,
    int headerRowIndex = 2,
    double lineHeightFactor = 16.0,
  }) {
    for (final entry in colWidths.entries) {
      sheet.setColumnWidth(entry.key, entry.value);
    }
    for (final entry in rowLineCounts.entries) {
      final r = entry.key;
      final lines = entry.value;
      if (r == 0) {
        sheet.setRowHeight(r, 25.0);
      } else if (r == 1) {
        sheet.setRowHeight(r, 28.0);
      } else if (r == headerRowIndex) {
        sheet.setRowHeight(r, max(headerRowHeight, lines * 16.0));
      } else {
        sheet.setRowHeight(r, max(defaultRowHeight, lines * lineHeightFactor));
      }
    }
  }

  /// Calibrated standard column widths matching reference templates
  static const Map<int, double> _templateColWidths = {
    0: 11.44,  // Pos.
    1: 18.00,  // Barcode
    2: 11.44,  // Tür Nr.
    3: 11.44,  // Etage
    4: 11.44,  // Raum Nr.
    5: 20.44,  // Raumbezeichnung
    6: 21.44,  // Türtyp (T30/RS/T90/Panik P/Einbruchschutz WK/usw.)
    7: 14.22,  // Flügelanzahl
    8: 21.44,  // Türmaterial / Türart
    9: 13.22,  // Türhersteller / Türsystem / Profilsystem
    10: 11.44, // DIN L/R / Standflügel/Gangflügel...
    11: 14.22, // Türschließer / Automatikantrieb
    12: 13.22, // GSR / EMF / EMR
    13: 11.44, // Schloßmaße
    14: 6.55,  // Türschließer auf Bandseite
    15: 6.55,  // Türschließer auf Bandgegenseite
    16: 6.55,  // Sturzhöhe unter 1 Meter
    17: 11.44, // Fluchtürsteuerung / Türwächter
    18: 11.44, // Zutrittskontrolle
    19: 6.55,  // Fluchtwegsituation
    20: 6.55,  // Fluchwegbeschilderung vorhanden?
    21: 6.55,  // Blindzylinder
    22: 6.55,  // PZ-Zylinder
    23: 6.55,  // Garnitur D / D - K / D
    24: 6.55,  // Panikfunktion B / E / usw.
    25: 6.55,  // Fluchtrichtung eingehalten
    26: 6.55,  // Vollpanik (Standflügel)
    27: 9.11,  // Tür einschl. Komponenten in ordentlicher Funktion
  };
  static const double _defectColWidth = 5.78;
  static const double _notesColWidth = 52.22;

  /// Exports a single inspection job to a dynamically formatted Excel workbook (.xlsx / .xlsm compatible)
  /// matching the exact layout and visual appearance of the reference master templates.
  static Future<File> exportSingleInspection(int inspectionId, String outputPath) async {
    final data = await DatabaseService.getSingleInspectionExportData(inspectionId);
    if (data.isEmpty) {
      throw Exception('Inspektionsdaten nicht gefunden.');
    }

    final excel = Excel.createExcel();
    final insp = data['inspection'] as Map<String, dynamic>;
    final doors = List<Map<String, dynamic>>.from(data['doors'] as List<Map<String, dynamic>>);

    // Sort doors ascending by Pos. (pos)
    doors.sort((a, b) {
      final posA = (a['pos'] as num?)?.toInt() ?? 999999;
      final posB = (b['pos'] as num?)?.toInt() ?? 999999;
      if (posA != posB) return posA.compareTo(posB);
      final numA = _cleanText(a['doorNumber']);
      final numB = _cleanText(b['doorNumber']);
      return numA.compareTo(numB);
    });

    final String clientName = _cleanText(insp['clientName']);
    final String dateStr = _cleanText(insp['date']);
    final String jobNumber = _cleanText(insp['jobNumber']);
    final String objectAddress = _cleanText(insp['objectAddress']);
    final String projectNumber = _cleanText(insp['projectNumber']);

    final String sheetName = 'Türlisten ${dateStr.replaceAll('-', '.')}';

    final sheet = excel[sheetName];
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Collect all distinct error codes & descriptions across doors in this inspection
    final Map<String, String> defectMap = {}; // Key: errorCode/key -> Value: "[code] [description]"
    for (final d in doors) {
      final errors = d['errors'] as List<Map<String, dynamic>>? ?? [];
      for (final e in errors) {
        final code = _cleanText(e['errorCode'] ?? e['code']);
        final desc = _cleanText(e['errorDesc'] ?? e['description']);
        final key = code.isNotEmpty ? code : desc;
        if (key.isNotEmpty) {
          final label = code.isNotEmpty ? (desc.isNotEmpty ? '$code $desc' : code) : desc;
          defectMap[key] = label;
        }
      }
    }
    final sortedDefectKeys = defectMap.keys.toList()..sort();

    // ── STYLING DEFINITIONS MATCHING TEMPLATES ───────────────────────────
    final borderThin = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('#000000'));
    final borderThick = Border(borderStyle: BorderStyle.Medium, borderColorHex: ExcelColor.fromHexString('#000000'));

    final fontBlack = ExcelColor.fromHexString('#000000');
    final fillWhite = ExcelColor.fromHexString('#FFFFFF');
    final fillSoftBlue = ExcelColor.fromHexString('#DCE6F1');
    final fillMediumBlue = ExcelColor.fromHexString('#8EA9DB');
    final fillYellow = ExcelColor.fromHexString('#FFFF00');

    const int fixedColsCount = 28;
    final int totalCols = fixedColsCount + sortedDefectKeys.length + 1;
    final int notesColIdx = fixedColsCount + sortedDefectKeys.length;

    final groupDefinitions = <({int start, int end, String label})>[
      (start: 0, end: 5, label: 'Grundinformationen'),
      (start: 6, end: 10, label: 'Türbeschreibung'),
      (start: 11, end: 18, label: 'Zubehörbeschreibung'),
      (start: 19, end: 26, label: 'Kontrolle Panikfunktion'),
      (start: 27, end: 27, label: 'okay'),
      if (sortedDefectKeys.isNotEmpty)
        (start: 28, end: 28 + sortedDefectKeys.length - 1, label: ''),
      (start: notesColIdx, end: notesColIdx, label: 'Anmerkung'),
    ];

    // Helper functions to identify perimeter edges of column groups
    // Groups: A-F (0..5), G-K (6..10), L-S (11..18), T-AA (19..26), AB (27), AC-(last error) (28..28+N-1), Anmerkung (notesColIdx)
    bool isLeftEdge(int col) => groupDefinitions.any((g) => g.start == col);
    bool isRightEdge(int col) => groupDefinitions.any((g) => g.end == col);

    // Row 0 Metadata Style
    final metaLeftStyle = CellStyle(
      fontSize: 10,
      fontColorHex: fontBlack,
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Bottom,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final positionBannerLabelStyle = CellStyle(
      fontSize: 10,
      fontColorHex: fontBlack,
      backgroundColorHex: fillYellow,
      horizontalAlign: HorizontalAlign.Right,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final positionNumberStyle = CellStyle(
      fontSize: 10,
      fontColorHex: fontBlack,
      backgroundColorHex: fillYellow,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final blankHeaderStyle = CellStyle(
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    // Row 2 Rotated Column Header Base Style (Centered horizontally with 90° rotation and thick outer borders)
    CellStyle getRotatedHeaderStyle(int col, {ExcelColor? bg}) {
      if (bg != null) {
        return CellStyle(
          fontSize: 12,
          rotation: 90,
          fontColorHex: fontBlack,
          backgroundColorHex: bg,
          horizontalAlign: HorizontalAlign.Center,
          textWrapping: TextWrapping.WrapText,
          topBorder: borderThick,
          bottomBorder: borderThick,
          leftBorder: isLeftEdge(col) ? borderThick : borderThin,
          rightBorder: isRightEdge(col) ? borderThick : borderThin,
        );
      }
      return CellStyle(
        fontSize: 12,
        rotation: 90,
        fontColorHex: fontBlack,
        horizontalAlign: HorizontalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        topBorder: borderThick,
        bottomBorder: borderThick,
        leftBorder: isLeftEdge(col) ? borderThick : borderThin,
        rightBorder: isRightEdge(col) ? borderThick : borderThin,
      );
    }

    final Map<int, double> colWidths = {};
    final Map<int, int> rowLineCounts = {};

    // Apply template column widths
    for (int c = 0; c < fixedColsCount; c++) {
      colWidths[c] = _templateColWidths[c] ?? 11.44;
    }
    for (int i = 0; i < sortedDefectKeys.length; i++) {
      colWidths[fixedColsCount + i] = _defectColWidth;
    }
    colWidths[notesColIdx] = _notesColWidth;

    // ── ROW 0: Header Row 1 (Metadata Line & Yellow Position Banner) ─────
    for (int c = 0; c < totalCols; c++) {
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: c,
        row: 0,
        text: '',
        style: blankHeaderStyle,
        trackWidth: false,
      );
    }

    final metaText = 'Kunde: $clientName | Objekt: $objectAddress | Datum: $dateStr | Auftragsnr.: $jobNumber | Projekt: $projectNumber';
    _setCell(
      sheet,
      colWidths,
      rowLineCounts,
      col: 0,
      row: 0,
      text: metaText,
      style: metaLeftStyle,
      trackWidth: false,
    );

    final int metaMergeEnd = (sortedDefectKeys.isNotEmpty) ? 18 : 26;
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: metaMergeEnd, rowIndex: 0),
    );

    if (sortedDefectKeys.isNotEmpty) {
      final bannerLabel = jobNumber.isNotEmpty ? 'Mängelbeseitigung $jobNumber, Position:' : 'Angebot, Position:';
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: 19,
        row: 0,
        text: bannerLabel,
        style: positionBannerLabelStyle,
        trackWidth: false,
      );
      for (int c = 20; c <= 27; c++) {
        _setCell(
          sheet,
          colWidths,
          rowLineCounts,
          col: c,
          row: 0,
          text: '',
          style: positionBannerLabelStyle,
          trackWidth: false,
        );
      }
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 19, rowIndex: 0),
        CellIndex.indexByColumnRow(columnIndex: 27, rowIndex: 0),
      );

      for (int i = 0; i < sortedDefectKeys.length; i++) {
        final colIdx = fixedColsCount + i;
        _setCell(
          sheet,
          colWidths,
          rowLineCounts,
          col: colIdx,
          row: 0,
          text: '${i + 1}',
          style: positionNumberStyle,
          trackWidth: false,
        );
      }
    }

    // ── ROW 1: Header Row 2 (Group Categories Matching Master Template) ──
    for (final group in groupDefinitions) {
      final style = CellStyle(
        bold: true,
        fontSize: 10,
        fontColorHex: fontBlack,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        topBorder: borderThick,
        bottomBorder: borderThick,
        leftBorder: borderThick,
        rightBorder: borderThick,
      );

      for (int c = group.start; c <= group.end; c++) {
        final isLeft = (c == group.start);
        final text = isLeft ? group.label : ' ';

        _setCell(
          sheet,
          colWidths,
          rowLineCounts,
          col: c,
          row: 1,
          text: text,
          style: style,
          trackWidth: false,
        );
      }

      if (group.end > group.start) {
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: group.start, rowIndex: 1),
          CellIndex.indexByColumnRow(columnIndex: group.end, rowIndex: 1),
          customValue: TextCellValue(group.label),
        );
      }

      for (int c = group.start; c <= group.end; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1)).cellStyle = style;
      }
    }

    // ── ROW 2: Header Row 3 (90° Rotated Vertical Column Headers) ────────
    final fixedHeaders = [
      'Pos.',
      'Barcode',
      'Tür Nr.',
      'Etage',
      'Raum Nr.',
      'Raumbezeichnung',
      'Türtyp (T30/RS/T90/Panik P/Einbruchschutz WK/usw.)',
      'Flügelanzahl',
      'Türmaterial / Türart (Alurohrrahmen RRAL / Stahlrohrrahmen RRST / Holz / Stahlblech / usw.)',
      'Türhersteller \n Türsystem \n Profilsystem',
      'DIN L/R \n Standflügel/Gangflügel \n Standflügelverriegelung',
      'Türschließer \n Automatikantrieb \n Do = Dorma, Ge = Geze, usw.',
      'GSR = Gleitschienen Schließfolgeregelung \n EMF = elektromagnetische Feststellung \n EMR = mit Rauchmelder',
      'Schloßmaße',
      'Türschließer auf Bandseite',
      'Türschließer auf Bandgegenseite',
      'Sturzhöhe unter 1 Meter',
      'Fluchtürsteuerung \n Türwächter',
      'Zutrittskontrolle',
      'Fluchtwegsituation',
      'Fluchwegbeschilderung vorhanden?',
      'Blindzylinder',
      'PZ-Zylinder',
      'Garnitur D / D - K / D',
      'Panikfunktion B / E / usw.',
      'Fluchtrichtung eingehalten',
      'Vollpanik (Standflügel)',
      'Tür einschl. Komponenten in ordendlicher Funktion',
    ];

    for (int col = 0; col < fixedHeaders.length; col++) {
      ExcelColor bg = fillWhite;
      // Light-light blue highlight for alternating columns T (19), V (21), X (23), Z (25), and AB (27).
      // Columns U (20), W (22), Y (24), AA (26) and A..S are white.
      if (col == 19 || col == 21 || col == 23 || col == 25 || col == 27) {
        bg = fillSoftBlue;
      } else {
        bg = fillWhite;
      }

      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: col,
        row: 2,
        text: fixedHeaders[col],
        style: getRotatedHeaderStyle(col, bg: bg),
        trackWidth: false,
      );
    }

    // Rotated Defect Headers (Row 2)
    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final colIdx = fixedColsCount + i;
      final defectLabel = defectMap[sortedDefectKeys[i]]!;
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: colIdx,
        row: 2,
        text: defectLabel,
        style: getRotatedHeaderStyle(colIdx),
        trackWidth: false,
      );
    }

    // Header for Anmerkung column (Row 2 is empty cell under group header)
    _setCell(
      sheet,
      colWidths,
      rowLineCounts,
      col: notesColIdx,
      row: 2,
      text: '',
      style: CellStyle(
        topBorder: borderThick,
        bottomBorder: borderThick,
        leftBorder: borderThick,
        rightBorder: borderThick,
      ),
      trackWidth: false,
    );

    // Accent column indices matching template soft-blue highlight columns
    final accentCols = <int>{14, 16, 19, 21, 23, 25};

    // ── ROW 3+: Data Rows ────────────────────────────────────────────────
    int rowIndex = 3;
    final Map<String, int> defectColumnTotals = {};
    int posCounter = 1;

    for (int r = 0; r < doors.length; r++) {
      final d = doors[r];
      final errors = d['errors'] as List<Map<String, dynamic>>? ?? [];
      final Map<String, int> doorDefectQtyMap = {};
      for (final e in errors) {
        final code = _cleanText(e['errorCode'] ?? e['code']);
        final desc = _cleanText(e['errorDesc'] ?? e['description']);
        final key = code.isNotEmpty ? code : desc;
        final qty = (e['quantity'] as num?)?.toInt() ?? 1;
        if (key.isNotEmpty) {
          doorDefectQtyMap[key] = (doorDefectQtyMap[key] ?? 0) + qty;
        }
      }

      // Compile door notes including extended properties if present
      final List<String> noteParts = [];
      final fsa = _cleanText(d['fsaDriveAcceptanceDate']);
      if (fsa.isNotEmpty && fsa != '?' && fsa != '-') {
        noteParts.add('FSA Abnahme: $fsa');
      }
      final approval = _cleanText(d['approvalNumber']);
      if (approval.isNotEmpty && approval != '?' && approval != '-') {
        noteParts.add('Zulassung: $approval');
      }
      final userNotes = _cleanNoteText(d['notes'] ?? d['junctionNotes'], 80);
      if (userNotes.isNotEmpty) {
        noteParts.add(userNotes);
      }
      final combinedNotes = noteParts.join('; ');

      final barcodeVal = _cleanText(d['doorAlias']).isNotEmpty ? _cleanText(d['doorAlias']) : _cleanText(d['barcode']);
      final doorNumVal = _cleanText(d['doorNumber']).isNotEmpty ? _cleanText(d['doorNumber']) : barcodeVal;

      final doorValues = [
        '${d['pos'] ?? posCounter}',
        barcodeVal,
        doorNumVal,
        _formatFloor(d['floor']),
        _cleanText(d['roomNumber'].toString().isNotEmpty ? d['roomNumber'] : '-'),
        _wrapText(_cleanText(d['roomDesignation']), 40),
        _wrapText(_cleanText(d['doorType']), 30),
        '${d['wingCount'] ?? 1}',
        _wrapText(_cleanText(d['material']), 30),
        _wrapText(_cleanText(d['manufacturer']), 30),
        _cleanText(d['dinConfiguration']),
        _wrapText(_cleanText(d['closerType']), 25),
        _wrapText(_cleanText(d['closingSequenceSystem']), 14), // Col M: snug wrap
        _wrapText(_cleanText(d['lockDimensions']), 12),         // Col N: snug wrap
        _xStr(d['closerOnHingeSide']),
        _xStr(d['closerOnOppositeSide']),
        _formatLintelHeight(d['lintelHeightInsideOver1m'] ?? d['lintelHeightOutsideOver1m'], d['lintelHeightInsideValue'] ?? d['lintelHeightOutsideValue']),
        _formatEscapeDoorControl(d['escapeDoorControl']),
        _formatAccessControl(d['accessControl']),
        _xStr(d['escapeRouteSituation']),
        _xStr(d['escapeRouteSignage']),
        _xStr(d['blindCylinder']),
        _xStr(d['pzCylinder']),
        _wrapText(_cleanText(d['fittingType']), 25),
        _wrapText(_cleanText(d['panicFunction']), 25),
        _xStr(d['escapeDirectionRespected']),
        _xStr(d['fullPanicStandWing']),
        _jnStr(d['doorFunctionOK']),
      ];

      final bool isLastDoorRow = (r == doors.length - 1);

      for (int c = 0; c < doorValues.length; c++) {
        ExcelColor cellBg = fillWhite;
        if (accentCols.contains(c)) {
          cellBg = fillSoftBlue;
        } else if (c == 27) {
          // Okay column: light blue background for 'J', light-light blue for 'N'
          final isOk = (doorValues[c] == 'J');
          cellBg = isOk ? fillMediumBlue : fillSoftBlue;
        }

        final cellStyle = CellStyle(
          fontSize: 10,
          fontColorHex: fontBlack,
          backgroundColorHex: cellBg,
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
          textWrapping: TextWrapping.WrapText,
          topBorder: (r == 0) ? borderThick : borderThin,
          bottomBorder: isLastDoorRow ? borderThick : borderThin,
          leftBorder: isLeftEdge(c) ? borderThick : borderThin,
          rightBorder: isRightEdge(c) ? borderThick : borderThin,
        );

        _setCell(
          sheet,
          colWidths,
          rowLineCounts,
          col: c,
          row: rowIndex,
          text: doorValues[c],
          style: cellStyle,
          trackWidth: false,
        );
      }

      // Defect quantities
      for (int i = 0; i < sortedDefectKeys.length; i++) {
        final key = sortedDefectKeys[i];
        final colIdx = fixedColsCount + i;
        String valText = '';
        if (doorDefectQtyMap.containsKey(key)) {
          final qty = doorDefectQtyMap[key]!;
          valText = '$qty';
          defectColumnTotals[key] = (defectColumnTotals[key] ?? 0) + qty;
        }
        final defectCellStyle = CellStyle(
          fontSize: 10,
          fontColorHex: fontBlack,
          backgroundColorHex: fillWhite,
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
          textWrapping: TextWrapping.WrapText,
          topBorder: (r == 0) ? borderThick : borderThin,
          bottomBorder: isLastDoorRow ? borderThick : borderThin,
          leftBorder: isLeftEdge(colIdx) ? borderThick : borderThin,
          rightBorder: isRightEdge(colIdx) ? borderThick : borderThin,
        );
        _setCell(
          sheet,
          colWidths,
          rowLineCounts,
          col: colIdx,
          row: rowIndex,
          text: valText,
          style: defectCellStyle,
          trackWidth: false,
        );
      }

      // Anmerkung Cell
      final noteCellStyle = CellStyle(
        fontSize: 10,
        fontColorHex: fontBlack,
        backgroundColorHex: fillWhite,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        topBorder: (r == 0) ? borderThick : borderThin,
        bottomBorder: isLastDoorRow ? borderThick : borderThin,
        leftBorder: borderThick,
        rightBorder: borderThick,
      );
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: notesColIdx,
        row: rowIndex,
        text: combinedNotes,
        style: noteCellStyle,
        trackWidth: false,
      );

      rowIndex++;
      posCounter++;
    }

    // ── BOTTOM SUMMARY ROW: Total Sums ───────────────────────────────────
    for (int c = 0; c < totalCols; c++) {
      ExcelColor bg = fillWhite;
      if (c >= 24 && c <= 27) {
        // Columns Y (24), Z (25), AA (26), AB (27) are light-light blue
        bg = fillSoftBlue;
      } else if (c >= fixedColsCount && c < notesColIdx) {
        // Dynamic inserted columns of errors are light-light blue
        bg = fillSoftBlue;
      } else {
        // Columns A..X (0..23) and Anmerkung (notesColIdx) are white
        bg = fillWhite;
      }

      final summaryCellStyle = CellStyle(
        bold: true,
        fontSize: 10,
        fontColorHex: fontBlack,
        backgroundColorHex: bg,
        horizontalAlign: (c >= 24 && c <= 27) ? HorizontalAlign.Center : ((c == 0) ? HorizontalAlign.Right : HorizontalAlign.Center),
        verticalAlign: VerticalAlign.Center,
        topBorder: borderThick,
        bottomBorder: borderThick,
        leftBorder: isLeftEdge(c) ? borderThick : borderThin,
        rightBorder: isRightEdge(c) ? borderThick : borderThin,
      );
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: c,
        row: rowIndex,
        text: '',
        style: summaryCellStyle,
        trackWidth: false,
      );
    }

    // Merge A to X (columns 0 to 23) in white
    final emptySpanStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: fontBlack,
      backgroundColorHex: fillWhite,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThick,
      bottomBorder: borderThick,
      leftBorder: borderThick,
      rightBorder: borderThick,
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
      CellIndex.indexByColumnRow(columnIndex: 23, rowIndex: rowIndex),
      customValue: TextCellValue(''),
    );
    for (int c = 0; c <= 23; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex)).cellStyle = emptySpanStyle;
    }

    // Merge Y to AB (columns 24 to 27) with light-light blue background and label "Summe für Mängelbeseitigung"
    final blueSpanStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: fontBlack,
      backgroundColorHex: fillSoftBlue,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThick,
      bottomBorder: borderThick,
      leftBorder: borderThick,
      rightBorder: borderThick,
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 24, rowIndex: rowIndex),
      CellIndex.indexByColumnRow(columnIndex: 27, rowIndex: rowIndex),
      customValue: TextCellValue('Summe für Mängelbeseitigung'),
    );
    for (int c = 24; c <= 27; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex)).cellStyle = blueSpanStyle;
    }

    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final key = sortedDefectKeys[i];
      final colIdx = fixedColsCount + i;
      final total = defectColumnTotals[key] ?? 0;
      final summaryDefectStyle = CellStyle(
        bold: true,
        fontSize: 10,
        fontColorHex: fontBlack,
        backgroundColorHex: fillSoftBlue,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        topBorder: borderThick,
        bottomBorder: borderThick,
        leftBorder: isLeftEdge(colIdx) ? borderThick : borderThin,
        rightBorder: isRightEdge(colIdx) ? borderThick : borderThin,
      );
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: colIdx,
        row: rowIndex,
        text: '$total',
        style: summaryDefectStyle,
        trackWidth: false,
      );
    }

    // Anmerkung column in summary row (white colored)
    final noteSummaryStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: fontBlack,
      backgroundColorHex: fillWhite,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThick,
      bottomBorder: borderThick,
      leftBorder: borderThick,
      rightBorder: borderThick,
    );
    _setCell(
      sheet,
      colWidths,
      rowLineCounts,
      col: notesColIdx,
      row: rowIndex,
      text: '',
      style: noteSummaryStyle,
      trackWidth: false,
    );

    // Apply exact template dimensions
    for (final entry in colWidths.entries) {
      sheet.setColumnWidth(entry.key, entry.value);
    }

    // Row heights:
    // Row 0: 18.75pt
    // Row 1: 52.5pt
    // Row 2: 201.75pt (Header matrix)
    // Data rows: 33.0pt (or taller for multi-line values, ensuring M, N and notes are fully visible)
    sheet.setRowHeight(0, 18.75);
    sheet.setRowHeight(1, 52.50);
    sheet.setRowHeight(2, 201.75);

    for (int r = 3; r < rowIndex; r++) {
      final lines = rowLineCounts[r] ?? 1;
      sheet.setRowHeight(r, max(33.0, lines * 17.0));
    }
    sheet.setRowHeight(rowIndex, 25.0);

    final file = File(outputPath);
    await file.parent.create(recursive: true);
    final rawBytes = excel.save();
    if (rawBytes != null) {
      final finalBytes = _injectPrintHeaderAndLogo(rawBytes);
      await file.writeAsBytes(finalBytes);
    }
    return file;
  }

  static List<int>? _getLogoBytes() {
    final candidatePaths = [
      r'C:\Users\cabarcas\Projects\WartungsTool\test\test_data\GottsbergLogo.png',
      'test/test_data/GottsbergLogo.png',
    ];
    for (final p in candidatePaths) {
      try {
        final f = File(p);
        if (f.existsSync()) {
          return f.readAsBytesSync();
        }
      } catch (_) {}
    }
    return null;
  }

  static List<int> _injectPrintHeaderAndLogo(List<int> xlsxBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(xlsxBytes);
      final newArchive = Archive();

      final logoBytes = _getLogoBytes();
      final hasLogo = logoBytes != null && logoBytes.isNotEmpty;

      // 1. Process existing files in archive
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final name = file.name;

        // Clean out any unused empty drawings from package:excel
        if (name.startsWith('xl/drawings/drawing')) {
          continue;
        }

        if (name == '[Content_Types].xml') {
          var xmlStr = utf8.decode(file.content as List<int>);
          xmlStr = xmlStr.replaceAll(
            RegExp(r'<Override[^>]*PartName="/xl/drawings/drawing[^"]*"[^>]*/>'),
            '',
          );
          if (hasLogo && !xmlStr.contains('Extension="vml"')) {
            xmlStr = xmlStr.replaceFirst(
              '</Types>',
              '<Default Extension="vml" ContentType="application/vnd.openxmlformats-officedocument.vmlDrawing"/>'
              '<Default Extension="png" ContentType="image/png"/></Types>',
            );
          }
          final bytes = utf8.encode(xmlStr);
          newArchive.addFile(ArchiveFile(name, bytes.length, bytes));
        } else if (name == 'xl/worksheets/sheet1.xml') {
          var xmlStr = utf8.decode(file.content as List<int>);

          // Strip any conflicting elements
          xmlStr = xmlStr.replaceAll(RegExp(r'<drawing[^>]*/>'), '');
          xmlStr = xmlStr.replaceAll(RegExp(r'<pageMargins[^>]*/>'), '');
          xmlStr = xmlStr.replaceAll(RegExp(r'<headerFooter[\s\S]*?</headerFooter>'), '');
          xmlStr = xmlStr.replaceAll(RegExp(r'<legacyDrawingHF[^>]*/>'), '');
          xmlStr = xmlStr.replaceAll(RegExp(r'<pageSetup[^>]*/>'), '');

          final headerText = hasLogo
              ? '&amp;L&amp;14&amp;&quot;-,Fett&quot;Prüfprotokol Türen&amp;R&amp;G'
              : '&amp;L&amp;14&amp;&quot;-,Fett&quot;Prüfprotokol Türen';

          final headerFooterXml =
              '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>'
              '<headerFooter><oddHeader>$headerText</oddHeader><evenHeader>$headerText</evenHeader></headerFooter>'
              '${hasLogo ? '<legacyDrawingHF r:id="rId1"/>' : ''}';

          xmlStr = xmlStr.replaceFirst('</worksheet>', '$headerFooterXml</worksheet>');
          final bytes = utf8.encode(xmlStr);
          newArchive.addFile(ArchiveFile(name, bytes.length, bytes));
        } else if (name == 'xl/worksheets/_rels/sheet1.xml.rels') {
          if (hasLogo) {
            final relsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/vmlDrawing" Target="../drawings/vmlDrawing1.vml"/>'
                '</Relationships>';
            final bytes = utf8.encode(relsXml);
            newArchive.addFile(ArchiveFile(name, bytes.length, bytes));
          }
        } else {
          newArchive.addFile(file);
        }
      }

      // 2. Add missing relationships / drawings / media if needed
      if (hasLogo) {
        if (newArchive.findFile('xl/worksheets/_rels/sheet1.xml.rels') == null) {
          final relsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/vmlDrawing" Target="../drawings/vmlDrawing1.vml"/>'
              '</Relationships>';
          final bytes = utf8.encode(relsXml);
          newArchive.addFile(ArchiveFile('xl/worksheets/_rels/sheet1.xml.rels', bytes.length, bytes));
        }

        newArchive.addFile(ArchiveFile('xl/media/image1.png', logoBytes.length, logoBytes));

        final vmlXml = '<xml xmlns:v="urn:schemas-microsoft-com:vml"\n'
            ' xmlns:o="urn:schemas-microsoft-com:office:office"\n'
            ' xmlns:x="urn:schemas-microsoft-com:office:excel">\n'
            ' <o:shapelayout v:ext="edit">\n'
            '  <o:idmap v:ext="edit" data="1"/>\n'
            ' </o:shapelayout><v:shapetype id="_x0000_t75" coordsize="21600,21600" o:spt="75"\n'
            '  o:preferrelative="t" path="m@4@5l@4@11@9@11@9@5xe" filled="f" stroked="f">\n'
            '  <v:stroke joinstyle="miter"/>\n'
            '  <v:formulas>\n'
            '   <v:f eqn="if lineDrawn pixelLineWidth 0"/>\n'
            '   <v:f eqn="sum @0 1 0"/>\n'
            '   <v:f eqn="sum 0 0 @1"/>\n'
            '   <v:f eqn="prod @2 1 2"/>\n'
            '   <v:f eqn="prod @3 21600 pixelWidth"/>\n'
            '   <v:f eqn="prod @3 21600 pixelHeight"/>\n'
            '   <v:f eqn="sum @0 0 1"/>\n'
            '   <v:f eqn="prod @6 1 2"/>\n'
            '   <v:f eqn="prod @7 21600 pixelWidth"/>\n'
            '   <v:f eqn="sum @8 21600 0"/>\n'
            '   <v:f eqn="prod @7 21600 pixelHeight"/>\n'
            '   <v:f eqn="sum @10 21600 0"/>\n'
            '  </v:formulas>\n'
            '  <v:path o:extrusionok="f" gradientshapeok="t" o:connecttype="rect"/>\n'
            '  <o:lock v:ext="edit" aspectratio="t"/>\n'
            ' </v:shapetype><v:shape id="RH" o:spid="_x0000_s1025" type="#_x0000_t75"\n'
            '  style=\'position:absolute;margin-left:0;margin-top:0;width:148.5pt;height:35.25pt;\n'
            '  z-index:1\'>\n'
            '  <v:imagedata o:relid="rId1" o:title="GottsbergLogo"/>\n'
            '  <o:lock v:ext="edit" rotation="t"/>\n'
            ' </v:shape></xml>';
        final vmlBytes = utf8.encode(vmlXml);
        newArchive.addFile(ArchiveFile('xl/drawings/vmlDrawing1.vml', vmlBytes.length, vmlBytes));

        final vmlRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/>'
            '</Relationships>';
        final vmlRelsBytes = utf8.encode(vmlRelsXml);
        newArchive.addFile(ArchiveFile('xl/drawings/_rels/vmlDrawing1.vml.rels', vmlRelsBytes.length, vmlRelsBytes));
      }

      final encoded = ZipEncoder().encode(newArchive);
      return encoded ?? xlsxBytes;
    } catch (e) {
      print('Warning: Failed to inject print header/logo: $e');
      return xlsxBytes;
    }
  }

  /// Exports complete historical audit data for a client into a multi-tab Excel workbook
  static Future<File> exportClientAudit(String clientName, String outputPath) async {
    final clientData = await DatabaseService.getClientAuditExportData(clientName);
    final inspections = clientData['inspections'] as List<Map<String, dynamic>>? ?? [];

    final excel = Excel.createExcel();

    final borderThin = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('#000000'));
    final borderMedium = Border(borderStyle: BorderStyle.Medium, borderColorHex: ExcelColor.fromHexString('#000000'));

    final headerStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1F497D'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      topBorder: borderMedium,
      bottomBorder: borderMedium,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final headerRotatedStyle = CellStyle(
      bold: true,
      fontSize: 9,
      rotation: 90,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1F497D'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Bottom,
      topBorder: borderMedium,
      bottomBorder: borderMedium,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final titleStyle = CellStyle(
      bold: true,
      fontSize: 12,
      fontColorHex: ExcelColor.fromHexString('#1F497D'),
      verticalAlign: VerticalAlign.Center,
    );

    final metaStyle = CellStyle(
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#333333'),
      verticalAlign: VerticalAlign.Center,
    );

    final dataCenterEven = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final dataCenterOdd = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#F8FAFC'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final dataLeftEven = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final dataLeftOdd = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#F8FAFC'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    // ── Tab 1: Customer Overview ──────────────────────────────────────────
    final overviewSheet = excel['Übersicht & Kundenstamm'];
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final Map<int, double> overviewColWidths = {};
    final Map<int, int> overviewRowLineCounts = {};

    overviewSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
      ..value = TextCellValue('KUNDE: ${_cleanText(clientName)}')
      ..cellStyle = titleStyle;
    overviewSheet.setRowHeight(0, 26.0);

    overviewSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
      ..value = TextCellValue('Gesamtzahl durchgeführter Inspektionen: ${inspections.length}')
      ..cellStyle = metaStyle;

    overviewSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2))
      ..value = TextCellValue('Erstellungsdatum des Berichts: ${DateTime.now().toString().split('.').first}')
      ..cellStyle = metaStyle;

    final overviewHeaders = ['Inspektions-ID', 'Auftragsnummer', 'Datum', 'Objektadresse', 'Projektnummer', 'Anzahl Türen'];
    for (int col = 0; col < overviewHeaders.length; col++) {
      _setCell(
        overviewSheet,
        overviewColWidths,
        overviewRowLineCounts,
        col: col,
        row: 4,
        text: overviewHeaders[col],
        style: headerStyle,
        trackWidth: true,
      );
    }

    int rowIdx = 5;
    for (final inspData in inspections) {
      final insp = inspData['inspection'] as Map<String, dynamic>;
      final doors = inspData['doors'] as List<Map<String, dynamic>>;
      final isEven = (rowIdx % 2 == 0);
      final cStyle = isEven ? dataCenterEven : dataCenterOdd;
      final lStyle = isEven ? dataLeftEven : dataLeftOdd;

      _setCell(overviewSheet, overviewColWidths, overviewRowLineCounts, col: 0, row: rowIdx, text: '${insp['inspectionId']}', style: cStyle);
      _setCell(overviewSheet, overviewColWidths, overviewRowLineCounts, col: 1, row: rowIdx, text: _cleanText(insp['jobNumber']), style: cStyle);
      _setCell(overviewSheet, overviewColWidths, overviewRowLineCounts, col: 2, row: rowIdx, text: _cleanText(insp['date']), style: cStyle);
      _setCell(overviewSheet, overviewColWidths, overviewRowLineCounts, col: 3, row: rowIdx, text: _wrapText(insp['objectAddress'], 40), style: lStyle);
      _setCell(overviewSheet, overviewColWidths, overviewRowLineCounts, col: 4, row: rowIdx, text: _cleanText(insp['projectNumber']), style: cStyle);
      _setCell(overviewSheet, overviewColWidths, overviewRowLineCounts, col: 5, row: rowIdx, text: '${doors.length}', style: cStyle);
      rowIdx++;
    }

    _applyDimensions(overviewSheet, overviewColWidths, overviewRowLineCounts, defaultRowHeight: 22.0, headerRowHeight: 28.0, headerRowIndex: 4);

    // ── Tab 2: Defect History Ledger with All Door Properties ──────────────
    final defectSheet = excel['Mängelhistorie (Revision)'];
    final Map<int, double> defectColWidths = {};
    final Map<int, int> defectRowLineCounts = {};

    final defectHeaders = [
      'Datum', 'Auftrag', 'Barcode', 'Tür-Nr.', 'Geschoss', 'Raumnr.', 'Raum',
      'Türart', 'Zulassung', 'Hersteller', 'Herstellernr', 'DoP-Nr', 'Baujahr', 'Flügel', 'Material', 'DIN',
      'Schließer', 'Schließfolge', 'Schlossmaß', 'Abnahme FSA', 'Bandseite', 'Bandgegenseite',
      'Sturzhöhe innen', 'Sturzhöhe außen', 'Zutrittskontrolle', 'Fluchttürsteu.', 'Fluchtwegsit.', 'Beschilderung', 'Blindzyl.', 'PZ-Zyl.',
      'Garnitur', 'Panikfkt', 'Fluchtricht.OK', 'VollpanikStand', 'FunktionOK',
      'Mängelcode', 'Kategorie', 'Beschreibung', 'Notizen'
    ];

    for (int col = 0; col < defectHeaders.length; col++) {
      final isRotated = (col >= 7 && col <= 34);
      _setCell(
        defectSheet,
        defectColWidths,
        defectRowLineCounts,
        col: col,
        row: 0,
        text: isRotated ? defectHeaders[col] : _wrapText(defectHeaders[col], 40),
        style: isRotated ? headerRotatedStyle : headerStyle,
        trackWidth: !isRotated,
      );
    }

    int defectRowIdx = 1;
    final leftColsDefect = {2, 3, 5, 6, 7, 9, 14, 16, 17, 18, 30, 35, 36, 37, 38};

    for (final inspData in inspections) {
      final insp = inspData['inspection'] as Map<String, dynamic>;
      final doors = inspData['doors'] as List<Map<String, dynamic>>;
      final date = _cleanText(insp['date']);
      final job = _cleanText(insp['jobNumber']);

      for (final d in doors) {
        final alias = _cleanText(d['doorAlias']);
        final doorNum = _cleanText(d['doorNumber']);
        final floor = _formatFloor(d['floor']);
        final roomNum = _cleanText(d['roomNumber']);
        final room = _wrapText(d['roomDesignation'], 40);
        final errors = d['errors'] as List<Map<String, dynamic>>? ?? [];

        for (final e in errors) {
          final isEven = (defectRowIdx % 2 == 0);
          final cStyle = isEven ? dataCenterEven : dataCenterOdd;
          final lStyle = isEven ? dataLeftEven : dataLeftOdd;

          final rowData = [
            date, job, alias, doorNum, floor, roomNum, room,
            _wrapText(d['doorType'], 40), _cleanText(d['approvalNumber'] ?? '?'), _wrapText(d['manufacturer'], 40), _cleanText(d['manufacturerNumber'] ?? '?'), _cleanText(d['dopNumber'] ?? '?'), _cleanText(d['manufactureYear'] ?? '?'),
            '${d['wingCount'] ?? 1}', _wrapText(d['material'], 40), _cleanText(d['dinConfiguration']),
            _wrapText(d['closerType'], 40), _wrapText(d['closingSequenceSystem'], 40), _cleanText(d['lockDimensions']),
            _cleanText(d['fsaDriveAcceptanceDate'] ?? '?'),
            _xStr(d['closerOnHingeSide']), _xStr(d['closerOnOppositeSide']),
            _formatLintelHeight(d['lintelHeightInsideOver1m'], d['lintelHeightInsideValue']),
            _formatLintelHeight(d['lintelHeightOutsideOver1m'], d['lintelHeightOutsideValue']),
            _formatAccessControl(d['accessControl']),
            _formatEscapeDoorControl(d['escapeDoorControl']),
            _xStr(d['escapeRouteSituation']), _xStr(d['escapeRouteSignage']),
            _xStr(d['blindCylinder']), _xStr(d['pzCylinder']),
            _wrapText(d['fittingType'], 40), _wrapText(d['panicFunction'], 40),
            _xStr(d['escapeDirectionRespected']), _xStr(d['fullPanicStandWing']),
            _jnStr(d['doorFunctionOK']),
            _cleanText(e['errorCode'] ?? e['code']),
            _wrapText(e['errorCat'] ?? e['category'], 40),
            _wrapText(e['errorDesc'] ?? e['description'], 40),
            _cleanNoteText(e['notes'] ?? d['notes'], 80),
          ];

          for (int c = 0; c < rowData.length; c++) {
            _setCell(
              defectSheet,
              defectColWidths,
              defectRowLineCounts,
              col: c,
              row: defectRowIdx,
              text: rowData[c],
              style: leftColsDefect.contains(c) ? lStyle : cStyle,
              trackWidth: true,
            );
          }
          defectRowIdx++;
        }
      }
    }

    _applyDimensions(defectSheet, defectColWidths, defectRowLineCounts, defaultRowHeight: 22.0, headerRowHeight: 110.0, headerRowIndex: 0);

    final file = File(outputPath);
    final bytes = excel.save();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }
    return file;
  }

  /// Exports lifetime history of a single door ("Tür-Akte") into an Excel workbook
  static Future<File> exportDoorHistoryReport(Map<String, dynamic> historyData, String outputPath) async {
    final doorObj = historyData['door'];
    final Map<String, dynamic> door = (doorObj is Door)
        ? doorObj.toMap()
        : (doorObj is Map<String, dynamic> ? doorObj : {});

    final historyItems = historyData['historyItems'] as List<dynamic>? ?? historyData['inspections'] as List<dynamic>? ?? [];

    final excel = Excel.createExcel();
    final String rawAlias = _cleanText(door['doorAlias'] ?? 'Tür');
    final String safeSheetAlias = rawAlias.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final String sheetName = 'Tür-Akte ${safeSheetAlias.length > 20 ? safeSheetAlias.substring(0, 20) : safeSheetAlias}';

    final sheet = excel[sheetName];
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final borderThin = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('#000000'));
    final borderMedium = Border(borderStyle: BorderStyle.Medium, borderColorHex: ExcelColor.fromHexString('#000000'));

    final headerStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1F497D'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      topBorder: borderMedium,
      bottomBorder: borderMedium,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final titleStyle = CellStyle(
      bold: true,
      fontSize: 12,
      fontColorHex: ExcelColor.fromHexString('#1F497D'),
      verticalAlign: VerticalAlign.Center,
    );

    final metaKeyStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#1F497D'),
      backgroundColorHex: ExcelColor.fromHexString('#D9E1F2'),
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final metaValStyle = CellStyle(
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final dataCenterEven = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final dataCenterOdd = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#F8FAFC'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final dataLeftEven = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final dataLeftOdd = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#F8FAFC'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final Map<int, double> colWidths = {};
    final Map<int, int> rowLineCounts = {};

    // ── Section 1: Specs (Key-Value Grid for Door Attributes) ─────────────
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
      ..value = TextCellValue('STAMMDATEN TÜR-AKTE')
      ..cellStyle = titleStyle;
    sheet.setRowHeight(0, 26.0);

    final specRows = [
      ['Barcode', _cleanText(door['doorAlias']), 'Türnummer', _cleanText(door['doorNumber']), 'Pos.', '${door['pos'] ?? 0}'],
      ['Geschoss', _formatFloor(door['floor']), 'Raumnummer', _cleanText(door['roomNumber']), 'Raumbezeichnung', _wrapText(door['roomDesignation'], 40)],
      ['Türtyp', _wrapText(door['doorType'], 40), 'Zulassungsnummer', _cleanText(door['approvalNumber'] ?? '?'), 'Hersteller', _wrapText(door['manufacturer'], 40)],
      ['Herstellernummer', _cleanText(door['manufacturerNumber'] ?? '?'), 'DoP-Nummer', _cleanText(door['dopNumber'] ?? '?'), 'Baujahr', _cleanText(door['manufactureYear'] ?? '?')],
      ['Flügelanzahl', '${door['wingCount'] ?? 1}', 'Türmaterial', _wrapText(door['material'], 40), 'DIN-Richtung', _cleanText(door['dinConfiguration'])],
      ['Schließertyp', _wrapText(door['closerType'], 40), 'Schließfolgeregler', _wrapText(door['closingSequenceSystem'], 40), 'Schlossmaße', _cleanText(door['lockDimensions'])],
      ['Abnahme FSA/Antrieb', _cleanText(door['fsaDriveAcceptanceDate'] ?? '?'), 'Sturzhöhe innen > 1m', _formatLintelHeight(door['lintelHeightInsideOver1m'], door['lintelHeightInsideValue']), 'Sturzhöhe außen > 1m', _formatLintelHeight(door['lintelHeightOutsideOver1m'], door['lintelHeightOutsideValue'])],
      ['Türschließer auf Bandseite', _xStr(door['closerOnHingeSide']), 'Türschließer auf Bandgegenseite', _xStr(door['closerOnOppositeSide']), 'Zutrittskontrolle', _formatAccessControl(door['accessControl'])],
      ['Fluchttürsteuerung', _formatEscapeDoorControl(door['escapeDoorControl']), 'Fluchtwegsituation', _xStr(door['escapeRouteSituation']), 'Fluchtwegbeschilderung', _xStr(door['escapeRouteSignage'])],
      ['Blindzylinder', _xStr(door['blindCylinder']), 'PZ-Zylinder', _xStr(door['pzCylinder']), 'Garnitur', _wrapText(door['fittingType'], 40)],
      ['Panikfunktion', _wrapText(door['panicFunction'], 40), 'Fluchtrichtung OK', _xStr(door['escapeDirectionRespected']), 'Vollpanik Standflügel', _xStr(door['fullPanicStandWing'])],
      ['Türfunktion OK', _jnStr(door['doorFunctionOK']), 'Notizen', _cleanNoteText(door['notes'], 80), '', ''],
    ];

    for (int r = 0; r < specRows.length; r++) {
      final row = specRows[r];
      final rIdx = 1 + r;
      for (int c = 0; c < row.length; c++) {
        _setCell(
          sheet,
          colWidths,
          rowLineCounts,
          col: c,
          row: rIdx,
          text: row[c],
          style: (c % 2 == 0) ? metaKeyStyle : metaValStyle,
          trackWidth: true,
        );
      }
    }

    // ── Section 2: Timeline ───────────────────────────────────────────────
    final timelineHeaderRow = 14;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: timelineHeaderRow))
      ..value = TextCellValue('INSPEKTIONSHISTORIE & MÄNGELPROTOKOLL')
      ..cellStyle = titleStyle;
    sheet.setRowHeight(timelineHeaderRow, 26.0);

    final headers = ['Datum', 'Kunde', 'Objektadresse', 'Auftrag', 'Status', 'Erfasste Mängel', 'Notizen'];
    final headerRowIdx = timelineHeaderRow + 1;
    for (int col = 0; col < headers.length; col++) {
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: col,
        row: headerRowIdx,
        text: _wrapText(headers[col], 40),
        style: headerStyle,
        trackWidth: true,
      );
    }

    int rowIdx = headerRowIdx + 1;
    for (final item in historyItems) {
      final insp = item is Map ? (item['inspection'] as Map<String, dynamic>? ?? item) : <String, dynamic>{};
      final errors = item is Map ? (item['errors'] as List<dynamic>? ?? []) : [];
      final errorSummary = errors.map((e) {
        if (e is Map) {
          final code = _cleanText(e['errorCode'] ?? e['code']);
          final desc = _cleanText(e['catalogDescription'] ?? e['description']);
          return code.isNotEmpty ? (desc.isNotEmpty ? '$code: $desc' : code) : desc;
        }
        return '';
      }).where((s) => s.isNotEmpty).join('\n');

      final isEven = (rowIdx % 2 == 0);
      final cStyle = isEven ? dataCenterEven : dataCenterOdd;
      final lStyle = isEven ? dataLeftEven : dataLeftOdd;

      _setCell(sheet, colWidths, rowLineCounts, col: 0, row: rowIdx, text: _cleanText(insp['date']), style: cStyle);
      _setCell(sheet, colWidths, rowLineCounts, col: 1, row: rowIdx, text: _wrapText(insp['clientName'], 40), style: lStyle);
      _setCell(sheet, colWidths, rowLineCounts, col: 2, row: rowIdx, text: _wrapText(insp['objectAddress'], 40), style: lStyle);
      _setCell(sheet, colWidths, rowLineCounts, col: 3, row: rowIdx, text: _cleanText(insp['jobNumber']), style: cStyle);
      _setCell(sheet, colWidths, rowLineCounts, col: 4, row: rowIdx, text: _cleanText(insp['junctionStatus'] ?? insp['status']), style: cStyle);
      _setCell(sheet, colWidths, rowLineCounts, col: 5, row: rowIdx, text: _wrapText(errorSummary, 40), style: lStyle);
      _setCell(sheet, colWidths, rowLineCounts, col: 6, row: rowIdx, text: _cleanNoteText(insp['junctionNotes'] ?? insp['notes'], 80), style: lStyle);
      rowIdx++;
    }

    _applyDimensions(sheet, colWidths, rowLineCounts, defaultRowHeight: 22.0, headerRowHeight: 28.0, headerRowIndex: headerRowIdx);

    final file = File(outputPath);
    final bytes = excel.save();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }
    return file;
  }
}
