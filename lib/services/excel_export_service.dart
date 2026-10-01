import 'dart:io';
import 'dart:math';
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

  /// Computes the statistical mode of character lengths for values in a column.
  /// Used to determine the optimal character allowance for dynamic line wrapping.
  static int _computeColumnModeAllowance(
    List<String> rawValues, {
    int defaultAllowance = 40,
    int minAllowance = 3,
    int maxAllowance = 40,
    bool isFloorCol = false,
    bool isShortDigitCol = false,
  }) {
    final validLengths = rawValues
        .map((s) => _cleanText(s))
        .where((s) => s.isNotEmpty)
        .map((s) => s.length)
        .toList();

    if (validLengths.isEmpty) {
      if (isFloorCol) return 4;
      if (isShortDigitCol) return 3;
      return defaultAllowance;
    }

    final Map<int, int> freq = {};
    for (final l in validLengths) {
      freq[l] = (freq[l] ?? 0) + 1;
    }

    int mode = defaultAllowance;
    int maxCount = 0;
    final sortedLengths = freq.keys.toList()..sort();
    for (final l in sortedLengths) {
      if (freq[l]! > maxCount) {
        maxCount = freq[l]!;
        mode = l;
      } else if (freq[l]! == maxCount && l > mode) {
        mode = l;
      }
    }

    int effectiveMin = minAllowance;
    if (isFloorCol) effectiveMin = max(minAllowance, 4);
    if (isShortDigitCol) effectiveMin = max(minAllowance, 3);
    return min(max(mode, effectiveMin), maxAllowance);
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

  /// Exports a single inspection job to a dynamically formatted Excel workbook (.xlsx / .xlsm compatible)
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
    final String contactPerson = _cleanText(insp['contactPerson']);
    final String inspectorName = _cleanText(insp['inspectorName']);

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

    // ── STYLING DEFINITIONS FOR PROFESSIONAL CUSTOMER PRESENTATION ──────────────
    final borderThin = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('#D9D9D9'));
    final borderMedium = Border(borderStyle: BorderStyle.Medium, borderColorHex: ExcelColor.fromHexString('#000000'));
    final borderDouble = Border(borderStyle: BorderStyle.Double, borderColorHex: ExcelColor.fromHexString('#000000'));

    final metaStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#1F497D'),
      verticalAlign: VerticalAlign.Center,
      horizontalAlign: HorizontalAlign.Left,
    );

    final categoryHeaderStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1F497D'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.Clip,
      topBorder: borderMedium,
      bottomBorder: borderMedium,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    // 90-degree rotated category header style for single-column category headers (e.g. Bewertung, Anmerkung)
    final categoryHeaderRotatedStyle = CellStyle(
      bold: true,
      fontSize: 9,
      rotation: 90,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1F497D'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderMedium,
      bottomBorder: borderMedium,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    // 90-degree rotated column header style for compact width
    final colHeaderFixedStyle = CellStyle(
      bold: true,
      fontSize: 9,
      rotation: 90,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#D9E1F2'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Bottom,
      topBorder: borderThin,
      bottomBorder: borderMedium,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    // 90-degree rotated defect column header style for compact width
    final colHeaderDefectStyle = CellStyle(
      bold: true,
      fontSize: 9,
      rotation: 90,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#FCE4D6'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Bottom,
      textWrapping: TextWrapping.WrapText,
      topBorder: borderThin,
      bottomBorder: borderMedium,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    // 90-degree rotated header style for Anmerkung column
    final colHeaderNotesStyle = CellStyle(
      bold: true,
      fontSize: 9,
      rotation: 90,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#E2EFDA'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Bottom,
      topBorder: borderThin,
      bottomBorder: borderMedium,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final dataLeftEvenStyle = CellStyle(
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

    final dataLeftOddStyle = CellStyle(
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

    final dataCenterEvenStyle = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final dataCenterOddStyle = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#F8FAFC'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    // No-wrap centered style for short numeric/code columns (Pos, Tür Nr., Etage)
    final dataCenterNoWrapEvenStyle = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.Clip,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final dataCenterNoWrapOddStyle = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#F8FAFC'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.Clip,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    // Special cell style for Anmerkung notes
    final notesEvenStyle = CellStyle(
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

    final notesOddStyle = CellStyle(
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

    final summaryLabelStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#E2EFDA'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderMedium,
      bottomBorder: borderDouble,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final summaryStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#E2EFDA'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderMedium,
      bottomBorder: borderDouble,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final summaryCenterStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#E2EFDA'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderMedium,
      bottomBorder: borderDouble,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final Map<int, double> colWidths = {};
    final Map<int, int> rowLineCounts = {};

    // ── ROW 0: Metadata Row ───────────────────────────────────
    final metaText = 'Kunde: $clientName | Objekt: $objectAddress | Datum: $dateStr | Ansprechpartner: $contactPerson | Monteur: $inspectorName | Auftragsnummer: $jobNumber';
    _setCell(
      sheet,
      colWidths,
      rowLineCounts,
      col: 0,
      row: 0,
      text: metaText,
      style: metaStyle,
      trackWidth: false, // Don't let wide meta banner distort Col 0
    );

    // Dynamic error sequence numbers (1, 2, 3...) above defect columns
    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final colIdx = 34 + i;
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: colIdx,
        row: 0,
        text: '${i + 1}',
        style: dataLeftEvenStyle,
        trackWidth: false,
      );
    }

    // ── ROW 1: Grouped Category Headers (Application UI Categories) ───────
    final totalCols = 34 + sortedDefectKeys.length + 1;
    for (int c = 0; c < totalCols; c++) {
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: c,
        row: 1,
        text: '',
        style: categoryHeaderStyle,
        trackWidth: false,
      );
    }

    final categoryDefinitions = <({int start, int end, String label, bool isRotated})>[
      (start: 0, end: 5, label: 'Grundinformationen', isRotated: false),
      (start: 6, end: 17, label: 'Tür Spezifikationen', isRotated: false),
      (start: 18, end: 22, label: 'Installation', isRotated: false),
      (start: 23, end: 32, label: 'Sicherheit & Zugang', isRotated: false),
      (start: 33, end: 33, label: 'Okay', isRotated: true),
    ];

    if (sortedDefectKeys.isNotEmpty) {
      categoryDefinitions.add((
        start: 34,
        end: 34 + sortedDefectKeys.length - 1,
        label: 'Mängelhinweise [$jobNumber]',
        isRotated: false,
      ));
    }

    categoryDefinitions.add((
      start: 34 + sortedDefectKeys.length,
      end: 34 + sortedDefectKeys.length,
      label: 'Anmerkung',
      isRotated: true,
    ));

    for (final cat in categoryDefinitions) {
      final style = cat.isRotated ? categoryHeaderRotatedStyle : categoryHeaderStyle;
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: cat.start,
        row: 1,
        text: cat.label,
        style: style,
        trackWidth: false,
      );

      // Merge contiguous cells so complete category names display clearly across the section
      if (cat.end > cat.start) {
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: cat.start, rowIndex: 1),
          CellIndex.indexByColumnRow(columnIndex: cat.end, rowIndex: 1),
        );
      }
    }

    // ── ROW 2: Column Headers (90° Rotated for Compact Width) ─────────────
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

    for (int col = 0; col < fixedHeaders.length; col++) {
      final headerText = fixedHeaders[col];
      if (headerText.length > maxHeaderChars) {
        maxHeaderChars = headerText.length;
      }
      // Set 90-degree rotated header without letting horizontal text stretch column width
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: col,
        row: 2,
        text: headerText,
        style: colHeaderFixedStyle,
        trackWidth: false, // 90° rotated headers do not define column width
      );
    }

    // Calculate mode allowance for defect column headers so long error descriptions wrap dynamically
    final defectHeaderAllowance = _computeColumnModeAllowance(
      defectMap.values.toList(),
      defaultAllowance: 25,
      minAllowance: 15,
      maxAllowance: 32,
    );

    // Dynamic Defect Column Headers (Col 34 to 34 + N - 1, 90-degree rotated)
    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final colIdx = 34 + i;
      final rawDefectLabel = defectMap[sortedDefectKeys[i]]!;
      final wrappedDefectLabel = (rawDefectLabel.length > defectHeaderAllowance)
          ? _wrapText(rawDefectLabel, defectHeaderAllowance)
          : rawDefectLabel;

      final labelLines = wrappedDefectLabel.split('\n');
      for (final line in labelLines) {
        if (line.trim().length > maxHeaderChars) {
          maxHeaderChars = line.trim().length;
        }
      }

      // Proportional column width for multi-line rotated defect header
      final neededWidth = max(2.5, labelLines.length * 2.2);
      if (neededWidth > (colWidths[colIdx] ?? 0.0)) {
        colWidths[colIdx] = neededWidth;
      }

      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: colIdx,
        row: 2,
        text: wrappedDefectLabel,
        style: colHeaderDefectStyle,
        trackWidth: false, // 90° rotated headers width tracked via labelLines count
      );
    }

    // 90-degree rotated Anmerkung Column Header (Col 34 + N)
    final notesColIdx = 34 + sortedDefectKeys.length;
    _setCell(
      sheet,
      colWidths,
      rowLineCounts,
      col: notesColIdx,
      row: 2,
      text: 'Anmerkung',
      style: colHeaderNotesStyle,
      trackWidth: false, // 90° rotated headers do not define horizontal column width
    );

    // ── Pre-pass: Gather door data & compute column mode allowances ────────
    final List<List<String>> doorFixedRows = [];
    final List<Map<String, int>> doorDefectMaps = [];
    final List<String> doorNoteRows = [];

    int posCounter = 1;
    for (final d in doors) {
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
      doorDefectMaps.add(doorDefectQtyMap);

      final rawFixed = [
        '${d['pos'] ?? posCounter}',
        _cleanText(d['doorAlias']),
        _cleanText(d['doorNumber']),
        _formatFloor(d['floor']),
        _cleanText(d['roomNumber']),
        _cleanText(d['roomDesignation']),
        _cleanText(d['doorType']),
        _cleanText(d['approvalNumber'] ?? '?'),
        _cleanText(d['manufacturer']),
        _cleanText(d['manufacturerNumber'] ?? '?'),
        _cleanText(d['dopNumber'] ?? '?'),
        _cleanText(d['manufactureYear'] ?? '?'),
        '${d['wingCount'] ?? 1}',
        _cleanText(d['material']),
        _cleanText(d['dinConfiguration']),
        _cleanText(d['closerType']),
        _cleanText(d['closingSequenceSystem']),
        _cleanText(d['lockDimensions']),
        _cleanText(d['fsaDriveAcceptanceDate'] ?? '?'),
        _xStr(d['closerOnHingeSide']),
        _xStr(d['closerOnOppositeSide']),
        _formatLintelHeight(d['lintelHeightInsideOver1m'], d['lintelHeightInsideValue']),
        _formatLintelHeight(d['lintelHeightOutsideOver1m'], d['lintelHeightOutsideValue']),
        _formatAccessControl(d['accessControl']),
        _formatEscapeDoorControl(d['escapeDoorControl']),
        _xStr(d['escapeRouteSituation']),
        _xStr(d['escapeRouteSignage']),
        _xStr(d['blindCylinder']),
        _xStr(d['pzCylinder']),
        _cleanText(d['fittingType']),
        _cleanText(d['panicFunction']),
        _xStr(d['escapeDirectionRespected']),
        _xStr(d['fullPanicStandWing']),
        _jnStr(d['doorFunctionOK']),
      ];
      doorFixedRows.add(rawFixed);

      final doorNotes = _cleanNoteText(d['notes'] ?? d['junctionNotes'], 80);
      doorNoteRows.add(doorNotes);

      posCounter++;
    }

    // Compute column mode allowances for fixed columns (0..33)
    final Map<int, int> fixedColModeAllowances = {};
    for (int c = 0; c < 34; c++) {
      final colValues = doorFixedRows.map((r) => r[c]).toList();
      fixedColModeAllowances[c] = _computeColumnModeAllowance(
        colValues,
        defaultAllowance: 40,
        minAllowance: 2,
        isFloorCol: (c == 3),
        isShortDigitCol: (c == 0 || c == 2),
      );
    }

    // ── ROW 3+: Data Rows (Mode-wrapped, snug fit) ────────────────────────
    int rowIndex = 3;
    final Map<String, int> defectColumnTotals = {};

    for (int r = 0; r < doors.length; r++) {
      final isEven = (rowIndex % 2 == 0);
      final leftStyle = isEven ? dataLeftEvenStyle : dataLeftOddStyle;
      final centerStyle = isEven ? dataCenterEvenStyle : dataCenterOddStyle;
      final centerNoWrapStyle = isEven ? dataCenterNoWrapEvenStyle : dataCenterNoWrapOddStyle;
      final noteStyle = isEven ? notesEvenStyle : notesOddStyle;

      final rawFixed = doorFixedRows[r];
      final doorDefectQtyMap = doorDefectMaps[r];

      for (int c = 0; c < rawFixed.length; c++) {
        final rawVal = rawFixed[c];
        String wrappedText;
        if (c == 0) {
          // Pos: NEVER wrap or insert break line into position numbers
          wrappedText = rawVal;
        } else if (c == 2) {
          // Tür Nr: NEVER wrap or insert break line into door numbers
          wrappedText = rawVal;
        } else if (c == 3) {
          // Etage: never wrap standard floor codes (<= 8 chars)
          wrappedText = (rawVal.length <= 8) ? rawVal : _wrapText(rawVal, 8);
        } else {
          final modeAllowance = fixedColModeAllowances[c] ?? 40;
          wrappedText = (rawVal.length > modeAllowance) ? _wrapText(rawVal, modeAllowance) : rawVal;
        }

        final isNoWrap = (c == 0 || c == 2 || c == 3);
        final isCenter = (c == 0 || c == 2 || c == 3 || c == 12 || c == 14 || c == 19 || c == 20 || c == 21 || c == 22 || c == 25 || c == 26 || c == 27 || c == 28 || c == 31 || c == 32 || c == 33);
        
        CellStyle cellStyle;
        if (isNoWrap) {
          cellStyle = centerNoWrapStyle;
        } else if (isCenter) {
          cellStyle = centerStyle;
        } else {
          cellStyle = leftStyle;
        }

        _setCell(
          sheet,
          colWidths,
          rowLineCounts,
          col: c,
          row: rowIndex,
          text: wrappedText,
          style: cellStyle,
          trackWidth: true,
        );
      }

      // Dynamic Defect Cells (Single quantities: tight width, center-aligned)
      for (int i = 0; i < sortedDefectKeys.length; i++) {
        final key = sortedDefectKeys[i];
        final colIdx = 34 + i;
        String valText = '';
        if (doorDefectQtyMap.containsKey(key)) {
          final qty = doorDefectQtyMap[key]!;
          valText = '$qty';
          defectColumnTotals[key] = (defectColumnTotals[key] ?? 0) + qty;
        }
        _setCell(
          sheet,
          colWidths,
          rowLineCounts,
          col: colIdx,
          row: rowIndex,
          text: valText,
          style: centerStyle,
          trackWidth: true,
        );
      }

      // Special Anmerkung Cell (Wrapped at max 80 chars, left-aligned)
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: notesColIdx,
        row: rowIndex,
        text: doorNoteRows[r],
        style: noteStyle,
        trackWidth: true,
      );

      rowIndex++;
      posCounter++;
    }

    // ── BOTTOM SUMMARY ROW: Total Sums ────────────────────────
    for (int c = 0; c < totalCols; c++) {
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: c,
        row: rowIndex,
        text: '',
        style: summaryStyle,
        trackWidth: false,
      );
    }
    _setCell(
      sheet,
      colWidths,
      rowLineCounts,
      col: 0,
      row: rowIndex,
      text: 'Summe für Mängelbeseitigung',
      style: summaryLabelStyle,
      trackWidth: false,
    );

    // Merge columns 0..33 only for this special summary row so "Summe für Mängelbeseitigung" displays completely on one line without breaking
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
      CellIndex.indexByColumnRow(columnIndex: 33, rowIndex: rowIndex),
    );

    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final key = sortedDefectKeys[i];
      final colIdx = 34 + i;
      final total = defectColumnTotals[key] ?? 0;
      _setCell(
        sheet,
        colWidths,
        rowLineCounts,
        col: colIdx,
        row: rowIndex,
        text: '$total',
        style: summaryCenterStyle,
        trackWidth: true,
      );
    }

    // Calculate vertical height needed for 90-degree rotated headers
    final dynamicHeaderHeight = max(130.0, min(240.0, maxHeaderChars * 3.5));

    // Apply all dynamically computed column widths and row heights
    _applyDimensions(
      sheet,
      colWidths,
      rowLineCounts,
      defaultRowHeight: 22.0,
      headerRowHeight: dynamicHeaderHeight,
      headerRowIndex: 2,
    );

    final file = File(outputPath);
    final bytes = excel.save();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }
    return file;
  }

  /// Exports complete historical audit data for a client into a multi-tab Excel workbook
  static Future<File> exportClientAudit(String clientName, String outputPath) async {
    final clientData = await DatabaseService.getClientAuditExportData(clientName);
    final inspections = clientData['inspections'] as List<Map<String, dynamic>>? ?? [];

    final excel = Excel.createExcel();

    final borderThin = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('#D9D9D9'));
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

    final borderThin = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('#D9D9D9'));
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
