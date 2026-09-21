import 'dart:io';
import 'package:excel/excel.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';

class ExcelExportService {
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

  /// Exports a single inspection job to a formatted Excel workbook (.xlsx / .xlsm compatible)
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
      final numA = (a['doorNumber'] as String? ?? '');
      final numB = (b['doorNumber'] as String? ?? '');
      return numA.compareTo(numB);
    });

    final String clientName = insp['clientName'] as String? ?? '';
    final String dateStr = insp['date'] as String? ?? '';
    final String jobNumber = insp['jobNumber'] as String? ?? '';
    final String objectAddress = insp['objectAddress'] as String? ?? '';
    final String contactPerson = insp['contactPerson'] as String? ?? '';
    final String inspectorName = insp['inspectorName'] as String? ?? '';

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

    // ── STYLING DEFINITIONS FOR CUSTOMER PRESENTATION ──────────────
    final borderThin = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('#BFBFBF'));
    final borderMedium = Border(borderStyle: BorderStyle.Medium, borderColorHex: ExcelColor.fromHexString('#000000'));
    final borderDouble = Border(borderStyle: BorderStyle.Double, borderColorHex: ExcelColor.fromHexString('#000000'));

    final metaStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#1F497D'),
      verticalAlign: VerticalAlign.Center,
    );

    final categoryHeaderStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1F497D'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderMedium,
      bottomBorder: borderMedium,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final colHeaderFixedStyle = CellStyle(
      bold: true,
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#D9E1F2'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThin,
      bottomBorder: borderMedium,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final colHeaderDefectStyle = CellStyle(
      bold: true,
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#FCE4D6'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThin,
      bottomBorder: borderMedium,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final colHeaderNotesStyle = CellStyle(
      bold: true,
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#E2EFDA'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThin,
      bottomBorder: borderMedium,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final dataCenterEvenStyle = CellStyle(
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

    final dataCenterOddStyle = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#F2F4F8'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final dataLeftEvenStyle = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderThin,
      bottomBorder: borderThin,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    final dataLeftOddStyle = CellStyle(
      fontSize: 9,
      fontColorHex: ExcelColor.fromHexString('#000000'),
      backgroundColorHex: ExcelColor.fromHexString('#F2F4F8'),
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
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
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: borderMedium,
      bottomBorder: borderDouble,
      leftBorder: borderThin,
      rightBorder: borderThin,
    );

    // ── ROW 0: Metadata Row ───────────────────────────────────
    final metaText = 'Kunde: $clientName | Objekt: $objectAddress | Datum: $dateStr | Ansprechpartner: $contactPerson | Monteur: $inspectorName | Auftragsnummer: $jobNumber';
    final metaCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
    metaCell.value = TextCellValue(metaText);
    metaCell.cellStyle = metaStyle;

    // Dynamic error sequence numbers (1, 2, 3...) above defect columns
    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final colIdx = 34 + i;
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: 0));
      cell.value = TextCellValue('${i + 1}');
      cell.cellStyle = colHeaderDefectStyle;
    }

    // ── ROW 1: Grouped Category Headers (Application UI Categories) ───────
    final categoriesMap = <int, String>{
      0: 'Grundinformationen',
      6: 'Tür Spezifikationen',
      18: 'Installation',
      23: 'Sicherheit & Zugang',
      33: 'Bewertung',
      34: 'Mängelhinweise [$jobNumber]',
      34 + sortedDefectKeys.length: 'Anmerkung',
    };

    final totalCols = 34 + sortedDefectKeys.length + 1;
    for (int c = 0; c < totalCols; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1));
      if (categoriesMap.containsKey(c)) {
        cell.value = TextCellValue(categoriesMap[c]!);
      }
      cell.cellStyle = categoryHeaderStyle;
    }

    // ── ROW 2: Column Headers ──────────────────────────────────
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

    for (int col = 0; col < fixedHeaders.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 2));
      cell.value = TextCellValue(fixedHeaders[col]);
      cell.cellStyle = colHeaderFixedStyle;
    }

    // Dynamic Defect Column Headers (Col 34 to 34 + N - 1)
    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final colIdx = 34 + i;
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: 2));
      cell.value = TextCellValue(defectMap[sortedDefectKeys[i]]!);
      cell.cellStyle = colHeaderDefectStyle;
    }

    // Notes Column Header (Col 34 + N)
    final notesColIdx = 34 + sortedDefectKeys.length;
    final notesHeaderCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: notesColIdx, rowIndex: 2));
    notesHeaderCell.value = TextCellValue('Anmerkung');
    notesHeaderCell.cellStyle = colHeaderNotesStyle;

    // ── ROW 3+: Data Rows ──────────────────────────────────────
    int rowIndex = 3;
    int posCounter = 1;
    final Map<String, int> defectColumnTotals = {};

    for (final d in doors) {
      final isEven = (rowIndex % 2 == 0);
      final centerStyle = isEven ? dataCenterEvenStyle : dataCenterOddStyle;
      final leftStyle = isEven ? dataLeftEvenStyle : dataLeftOddStyle;

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

      final fixedCells = [
        TextCellValue('${d['pos'] ?? posCounter}'),
        TextCellValue(d['doorAlias'] as String? ?? ''),
        TextCellValue(d['doorNumber'] as String? ?? ''),
        TextCellValue(d['floor'] as String? ?? ''),
        TextCellValue(d['roomNumber'] as String? ?? ''),
        TextCellValue(d['roomDesignation'] as String? ?? ''),
        TextCellValue(d['doorType'] as String? ?? ''),
        TextCellValue(d['approvalNumber'] as String? ?? '?'),
        TextCellValue(d['manufacturer'] as String? ?? ''),
        TextCellValue(d['manufacturerNumber'] as String? ?? '?'),
        TextCellValue(d['dopNumber'] as String? ?? '?'),
        TextCellValue(d['manufactureYear'] as String? ?? '?'),
        TextCellValue('${d['wingCount'] ?? 1}'),
        TextCellValue(d['material'] as String? ?? ''),
        TextCellValue(d['dinConfiguration'] as String? ?? ''),
        TextCellValue(d['closerType'] as String? ?? ''),
        TextCellValue(d['closingSequenceSystem'] as String? ?? ''),
        TextCellValue(d['lockDimensions'] as String? ?? ''),
        TextCellValue(d['fsaDriveAcceptanceDate'] as String? ?? '?'),
        TextCellValue(_xStr(d['closerOnHingeSide'])),
        TextCellValue(_xStr(d['closerOnOppositeSide'])),
        TextCellValue(_formatLintelHeight(d['lintelHeightInsideOver1m'], d['lintelHeightInsideValue'])),
        TextCellValue(_formatLintelHeight(d['lintelHeightOutsideOver1m'], d['lintelHeightOutsideValue'])),
        TextCellValue(d['accessControl'] as String? ?? 'Nein'),
        TextCellValue(d['escapeDoorControl'] == true || d['escapeDoorControl'] == 1 ? 'Ja' : 'Nein'),
        TextCellValue(_xStr(d['escapeRouteSituation'])),
        TextCellValue(_xStr(d['escapeRouteSignage'])),
        TextCellValue(_xStr(d['blindCylinder'])),
        TextCellValue(_xStr(d['pzCylinder'])),
        TextCellValue(d['fittingType'] as String? ?? ''),
        TextCellValue(d['panicFunction'] as String? ?? ''),
        TextCellValue(_xStr(d['escapeDirectionRespected'])),
        TextCellValue(_xStr(d['fullPanicStandWing'])),
        TextCellValue(_jnStr(d['doorFunctionOK'])),
      ];

      // Left-aligned text columns: 1, 2, 4, 5, 6, 8, 13, 15, 16, 17, 23, 24, 29, 30
      final leftAlignedCols = {1, 2, 4, 5, 6, 8, 13, 15, 16, 17, 23, 24, 29, 30};

      for (int c = 0; c < fixedCells.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex));
        cell.value = fixedCells[c];
        cell.cellStyle = leftAlignedCols.contains(c) ? leftStyle : centerStyle;
      }

      // Dynamic Defect Cells
      for (int i = 0; i < sortedDefectKeys.length; i++) {
        final key = sortedDefectKeys[i];
        final colIdx = 34 + i;
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIndex));
        if (doorDefectQtyMap.containsKey(key)) {
          final qty = doorDefectQtyMap[key]!;
          cell.value = TextCellValue('$qty');
          defectColumnTotals[key] = (defectColumnTotals[key] ?? 0) + qty;
        } else {
          cell.value = TextCellValue('');
        }
        cell.cellStyle = centerStyle;
      }

      // Anmerkung Cell (Notes property)
      final doorNotes = (d['notes'] ?? d['junctionNotes'] ?? '').toString();
      final notesCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: notesColIdx, rowIndex: rowIndex));
      notesCell.value = TextCellValue(doorNotes);
      notesCell.cellStyle = leftStyle;

      rowIndex++;
      posCounter++;
    }

    // ── BOTTOM SUMMARY ROW: Total Sums ────────────────────────
    for (int c = 0; c < totalCols; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex));
      cell.cellStyle = summaryStyle;
    }
    final sumLabelCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex));
    sumLabelCell.value = TextCellValue('Summe für Mängelbeseitigung');
    sumLabelCell.cellStyle = summaryLabelStyle;

    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final key = sortedDefectKeys[i];
      final colIdx = 34 + i;
      final total = defectColumnTotals[key] ?? 0;
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIndex));
      cell.value = TextCellValue('$total');
      cell.cellStyle = summaryStyle;
    }

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

    // Tab 1: Customer Overview
    final overviewSheet = excel['Übersicht & Kundenstamm'];
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    overviewSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('KUNDE: $clientName');
    overviewSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('Gesamtzahl durchgeführter Inspektionen: ${inspections.length}');
    overviewSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('Erstellungsdatum des Berichts: ${DateTime.now().toString().split('.').first}');

    final overviewHeaders = ['Inspektions-ID', 'Auftragsnummer', 'Datum', 'Objektadresse', 'Projektnummer', 'Anzahl Türen'];
    for (int col = 0; col < overviewHeaders.length; col++) {
      overviewSheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 4)).value = TextCellValue(overviewHeaders[col]);
    }

    int rowIdx = 5;
    for (final inspData in inspections) {
      final insp = inspData['inspection'] as Map<String, dynamic>;
      final doors = inspData['doors'] as List<Map<String, dynamic>>;
      overviewSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).value = TextCellValue('${insp['inspectionId']}');
      overviewSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx)).value = TextCellValue(insp['jobNumber'] as String? ?? '');
      overviewSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx)).value = TextCellValue(insp['date'] as String? ?? '');
      overviewSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx)).value = TextCellValue(insp['objectAddress'] as String? ?? '');
      overviewSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx)).value = TextCellValue(insp['projectNumber'] as String? ?? '');
      overviewSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx)).value = TextCellValue('${doors.length}');
      rowIdx++;
    }

    // Tab 2: Defect History Ledger with All Door Properties
    final defectSheet = excel['Mängelhistorie (Revision)'];
    final defectHeaders = [
      'Datum', 'Auftrag', 'Barcode', 'Tür-Nr.', 'Geschoss', 'Raumnr.', 'Raum',
      'Türart', 'Zulassung', 'Hersteller', 'Herstellernr', 'DoP-Nr', 'Baujahr', 'Flügel', 'Material', 'DIN',
      'Schließer', 'Schließfolge', 'Schlossmaß', 'Abnahme FSA', 'Bandseite', 'Bandgegenseite',
      'Sturzhöhe innen', 'Sturzhöhe außen', 'Zutrittskontrolle', 'Fluchttürsteu.', 'Fluchtwegsit.', 'Beschilderung', 'Blindzyl.', 'PZ-Zyl.',
      'Garnitur', 'Panikfkt', 'Fluchtricht.OK', 'VollpanikStand', 'FunktionOK',
      'Mängelcode', 'Kategorie', 'Beschreibung', 'Notizen'
    ];
    for (int col = 0; col < defectHeaders.length; col++) {
      defectSheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).value = TextCellValue(defectHeaders[col]);
    }

    int defectRowIdx = 1;
    for (final inspData in inspections) {
      final insp = inspData['inspection'] as Map<String, dynamic>;
      final doors = inspData['doors'] as List<Map<String, dynamic>>;
      final date = insp['date'] as String? ?? '';
      final job = insp['jobNumber'] as String? ?? '';

      for (final d in doors) {
        final alias = d['doorAlias'] as String? ?? '';
        final doorNum = d['doorNumber'] as String? ?? '';
        final floor = d['floor'] as String? ?? '';
        final roomNum = d['roomNumber'] as String? ?? '';
        final room = d['roomDesignation'] as String? ?? '';
        final errors = d['errors'] as List<Map<String, dynamic>>? ?? [];

        for (final e in errors) {
          final rowData = [
            date, job, alias, doorNum, floor, roomNum, room,
            d['doorType'] ?? '', d['approvalNumber'] ?? '?', d['manufacturer'] ?? '', d['manufacturerNumber'] ?? '?', d['dopNumber'] ?? '?', d['manufactureYear'] ?? '?',
            '${d['wingCount'] ?? 1}', d['material'] ?? '', d['dinConfiguration'] ?? '',
            d['closerType'] ?? '', d['closingSequenceSystem'] ?? '', d['lockDimensions'] ?? '',
            d['fsaDriveAcceptanceDate'] ?? '?',
            _xStr(d['closerOnHingeSide']), _xStr(d['closerOnOppositeSide']),
            _formatLintelHeight(d['lintelHeightInsideOver1m'], d['lintelHeightInsideValue']),
            _formatLintelHeight(d['lintelHeightOutsideOver1m'], d['lintelHeightOutsideValue']),
            d['accessControl'] ?? '',
            _xStr(d['escapeDoorControl']),
            _xStr(d['escapeRouteSituation']), _xStr(d['escapeRouteSignage']),
            _xStr(d['blindCylinder']), _xStr(d['pzCylinder']),
            d['fittingType'] ?? '', d['panicFunction'] ?? '',
            _xStr(d['escapeDirectionRespected']), _xStr(d['fullPanicStandWing']),
            _jnStr(d['doorFunctionOK']),
            e['errorCode'] as String? ?? e['code'] as String? ?? '',
            e['errorCat'] as String? ?? e['category'] as String? ?? '',
            e['errorDesc'] as String? ?? e['description'] as String? ?? '',
            e['notes'] as String? ?? d['notes'] as String? ?? '',
          ];

          for (int c = 0; c < rowData.length; c++) {
            defectSheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: defectRowIdx)).value = TextCellValue(rowData[c]);
          }
          defectRowIdx++;
        }
      }
    }

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
    final String rawAlias = (door['doorAlias'] ?? 'Tür').toString();
    final String safeSheetAlias = rawAlias.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final String sheetName = 'Tür-Akte ${safeSheetAlias.length > 20 ? safeSheetAlias.substring(0, 20) : safeSheetAlias}';

    final sheet = excel[sheetName];
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Section 1: Specs (All door properties)
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('STAMMDATEN TÜR-AKTE');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('Barcode: ${door['doorAlias'] ?? ''}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('Türnummer: ${door['doorNumber'] ?? ''} | Pos: ${door['pos'] ?? 0}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3)).value = TextCellValue('Geschoss: ${door['floor'] ?? ''} | Raumnr: ${door['roomNumber'] ?? ''} | Raum: ${door['roomDesignation'] ?? ''}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4)).value = TextCellValue('Türart: ${door['doorType'] ?? ''} | Zulassung: ${door['approvalNumber'] ?? '?'} | Hersteller: ${door['manufacturer'] ?? ''} | Herstellernr: ${door['manufacturerNumber'] ?? '?'}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 5)).value = TextCellValue('DoP-Nr: ${door['dopNumber'] ?? '?'} | Baujahr: ${door['manufactureYear'] ?? '?'} | Flügelanzahl: ${door['wingCount'] ?? 1} | Material: ${door['material'] ?? ''}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 6)).value = TextCellValue('DIN-Richtung: ${door['dinConfiguration'] ?? ''} | Schließertyp: ${door['closerType'] ?? ''} | Schließfolgeregler: ${door['closingSequenceSystem'] ?? ''} | Schlossmaße: ${door['lockDimensions'] ?? ''}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 7)).value = TextCellValue('Abnahme FSA/Antrieb: ${door['fsaDriveAcceptanceDate'] ?? '?'} | Sturzhöhe Bandseite: ${_xStr(door['closerOnHingeSide'])} | Sturzhöhe Gegenseite: ${_xStr(door['closerOnOppositeSide'])}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 8)).value = TextCellValue('Sturzhöhe innen > 1m: ${_formatLintelHeight(door['lintelHeightInsideOver1m'], door['lintelHeightInsideValue'])} | Sturzhöhe außen > 1m: ${_formatLintelHeight(door['lintelHeightOutsideOver1m'], door['lintelHeightOutsideValue'])} | Beschlagart: ${door['fittingType'] ?? ''} | Panikfunktion: ${door['panicFunction'] ?? ''} | Zutrittskontrolle: ${door['accessControl'] ?? ''}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 9)).value = TextCellValue('Fluchttürsteuerung: ${_xStr(door['escapeDoorControl'])} | Fluchtwegsituation: ${_xStr(door['escapeRouteSituation'])} | Fluchtwegbeschilderung: ${_xStr(door['escapeRouteSignage'])}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 10)).value = TextCellValue('Blindzylinder: ${_xStr(door['blindCylinder'])} | PZ-Zylinder: ${_xStr(door['pzCylinder'])} | Fluchtrichtung beachtet: ${_xStr(door['escapeDirectionRespected'])} | Vollpanik Standflügel: ${_xStr(door['fullPanicStandWing'])} | Türfunktion OK: ${_jnStr(door['doorFunctionOK'])}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 11)).value = TextCellValue('Notizen: ${door['notes'] ?? ''}');

    // Section 2: Timeline
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 13)).value = TextCellValue('INSPEKTIONSHISTORIE & MÄNGELPROTOKOLL');
    final headers = ['Datum', 'Kunde', 'Objektadresse', 'Auftrag', 'Status', 'Erfasste Mängel', 'Notizen'];
    for (int col = 0; col < headers.length; col++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 14)).value = TextCellValue(headers[col]);
    }

    int rowIdx = 15;
    for (final item in historyItems) {
      final insp = item is Map ? (item['inspection'] as Map<String, dynamic>? ?? item) : <String, dynamic>{};
      final errors = item is Map ? (item['errors'] as List<dynamic>? ?? []) : [];
      final errorSummary = errors.map((e) {
        if (e is Map) {
          final code = e['errorCode'] ?? e['code'] ?? '';
          final desc = e['catalogDescription'] ?? e['description'] ?? '';
          return '$code: $desc';
        }
        return '';
      }).where((s) => s.isNotEmpty).join(' | ');

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).value = TextCellValue((insp['date'] ?? '').toString());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx)).value = TextCellValue((insp['clientName'] ?? '').toString());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx)).value = TextCellValue((insp['objectAddress'] ?? '').toString());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx)).value = TextCellValue((insp['jobNumber'] ?? '').toString());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx)).value = TextCellValue((insp['junctionStatus'] ?? insp['status'] ?? '').toString());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx)).value = TextCellValue(errorSummary);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx)).value = TextCellValue((insp['junctionNotes'] ?? insp['notes'] ?? '').toString());
      rowIdx++;
    }

    final file = File(outputPath);
    final bytes = excel.save();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }
    return file;
  }
}
