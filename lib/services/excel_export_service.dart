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

  /// Exports a single inspection job to a formatted Excel workbook (.xlsx / .xlsm compatible)
  static Future<File> exportSingleInspection(int inspectionId, String outputPath) async {
    final data = await DatabaseService.getSingleInspectionExportData(inspectionId);
    if (data.isEmpty) {
      throw Exception('Inspektionsdaten nicht gefunden.');
    }

    final excel = Excel.createExcel();
    final insp = data['inspection'] as Map<String, dynamic>;
    final doors = data['doors'] as List<Map<String, dynamic>>;

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

    // ── ROW 0: Metadata Row ───────────────────────────────────
    final metaText = 'Kunde: $clientName Objekt: $objectAddress Datum: $dateStr Ansprechpartner: $contactPerson Monteur: $inspectorName Auftragsnummer: $jobNumber';
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue(metaText);

    // Dynamic error sequence numbers (1, 2, 3...) above defect columns
    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final colIdx = 28 + i;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: 0)).value = TextCellValue('${i + 1}');
    }

    // ── ROW 1: Grouped Category Headers (Application UI Categories) ───────
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('Grundinformationen');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 1)).value = TextCellValue('Tür Spezifikationen');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: 1)).value = TextCellValue('Installation');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 17, rowIndex: 1)).value = TextCellValue('Sicherheit & Zugang');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 27, rowIndex: 1)).value = TextCellValue('Bewertung');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 28, rowIndex: 1)).value = TextCellValue('Mängelhinweise [$jobNumber]');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 28 + sortedDefectKeys.length, rowIndex: 1)).value = TextCellValue('Anmerkung');

    // ── ROW 2: Column Headers ──────────────────────────────────
    final fixedHeaders = [
      'Pos.',
      'Barcode',
      'Tür Nr.',
      'Etage',
      'Raum Nr.',
      'Raumbezeichnung',
      'Türtyp (T30/RS/T90/Panik P/WK/usw.)',
      'Flügelanzahl',
      'Türmaterial / Türart',
      'Türhersteller / Türsystem',
      'DIN L/R',
      'Türschließer / Automatikantrieb',
      'GSR / EMF / EMR',
      'Schloßmaße',
      'Türschließer auf Bandseite',
      'Türschließer auf Bandgegenseite',
      'Sturzhöhe unter 1 Meter',
      'Fluchtürsteuerung / Türwächter',
      'Zutrittskontrolle',
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
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 2)).value = TextCellValue(fixedHeaders[col]);
    }

    // Dynamic Defect Column Headers (Col 28 to 28 + N - 1)
    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final colIdx = 28 + i;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: 2)).value = TextCellValue(defectMap[sortedDefectKeys[i]]!);
    }

    // Notes Column Header (Col 28 + N)
    final notesColIdx = 28 + sortedDefectKeys.length;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: notesColIdx, rowIndex: 2)).value = TextCellValue('Anmerkung');

    // ── ROW 3+: Data Rows ──────────────────────────────────────
    int rowIndex = 3;
    int posCounter = 1;
    final Map<String, int> defectColumnTotals = {};

    for (final d in doors) {
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
        TextCellValue('${d['wingCount'] ?? 1}'),
        TextCellValue(d['material'] as String? ?? ''),
        TextCellValue(d['manufacturer'] as String? ?? ''),
        TextCellValue(d['dinConfiguration'] as String? ?? ''),
        TextCellValue(d['closerType'] as String? ?? ''),
        TextCellValue(d['closingSequenceSystem'] as String? ?? ''),
        TextCellValue(d['lockDimensions'] as String? ?? ''),
        TextCellValue(_xStr(d['closerOnHingeSide'])),
        TextCellValue(_xStr(d['closerOnOppositeSide'])),
        TextCellValue(_xStr(d['lintelHeightInsideOver1m'] ?? d['lintelHeightOutsideOver1m'])),
        TextCellValue(d['escapeDoorControl'] == true ? 'Ja' : 'Nein'),
        TextCellValue(d['accessControl'] as String? ?? 'Nein'),
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

      for (int c = 0; c < fixedCells.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex)).value = fixedCells[c];
      }

      // Dynamic Defect Cells
      for (int i = 0; i < sortedDefectKeys.length; i++) {
        final key = sortedDefectKeys[i];
        final colIdx = 28 + i;
        if (doorDefectQtyMap.containsKey(key)) {
          final qty = doorDefectQtyMap[key]!;
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIndex)).value = TextCellValue('$qty');
          defectColumnTotals[key] = (defectColumnTotals[key] ?? 0) + qty;
        } else {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIndex)).value = TextCellValue('');
        }
      }

      // Anmerkung Cell (Notes property)
      final doorNotes = (d['notes'] ?? d['junctionNotes'] ?? '').toString();
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: notesColIdx, rowIndex: rowIndex)).value = TextCellValue(doorNotes);

      rowIndex++;
      posCounter++;
    }

    // ── BOTTOM SUMMARY ROW: Total Sums ────────────────────────
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value = TextCellValue('Summe für Mängelbeseitigung');
    for (int i = 0; i < sortedDefectKeys.length; i++) {
      final key = sortedDefectKeys[i];
      final colIdx = 28 + i;
      final total = defectColumnTotals[key] ?? 0;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIndex)).value = TextCellValue('$total');
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
      'Türart', 'Flügel', 'Material', 'Hersteller', 'DIN', 'Schließer', 'Schließfolge', 'Schlossmaß', 'Garnitur', 'Panikfkt', 'Zutrittskontrolle', 'Bandseite', 'Bandgegenseite',
      'Sturzhöhe', 'Fluchttürsteu.', 'Fluchtwegsit.', 'Beschilderung', 'Blindzyl.', 'PZ-Zyl.',
      'Fluchtricht.OK', 'VollpanikStand', 'FunktionOK',
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
            d['doorType'] ?? '', '${d['wingCount'] ?? 1}', d['material'] ?? '', d['manufacturer'] ?? '',
            d['dinConfiguration'] ?? '', d['closerType'] ?? '', d['closingSequenceSystem'] ?? '',
            d['lockDimensions'] ?? '', d['fittingType'] ?? '', d['panicFunction'] ?? '', d['accessControl'] ?? '',
            _xStr(d['closerOnHingeSide']), _xStr(d['closerOnOppositeSide']),
            _xStr(d['lintelHeightInsideOver1m'] ?? d['lintelHeightOutsideOver1m']),
            _xStr(d['escapeDoorControl']),
            _xStr(d['escapeRouteSituation']), _xStr(d['escapeRouteSignage']),
            _xStr(d['blindCylinder']), _xStr(d['pzCylinder']),
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
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4)).value = TextCellValue('Türart: ${door['doorType'] ?? ''} | Flügelanzahl: ${door['wingCount'] ?? 1} | Material: ${door['material'] ?? ''} | Hersteller: ${door['manufacturer'] ?? ''}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 5)).value = TextCellValue('DIN-Richtung: ${door['dinConfiguration'] ?? ''} | Schließertyp: ${door['closerType'] ?? ''} | Schließfolgeregler: ${door['closingSequenceSystem'] ?? ''}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 6)).value = TextCellValue('Schlossmaße: ${door['lockDimensions'] ?? ''} | Beschlagart: ${door['fittingType'] ?? ''} | Panikfunktion: ${door['panicFunction'] ?? ''} | Zutrittskontrolle: ${door['accessControl'] ?? ''}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 7)).value = TextCellValue('Sturzhöhe Bandseite: ${_xStr(door['closerOnHingeSide'])} | Sturzhöhe Gegenseite: ${_xStr(door['closerOnOppositeSide'])} | Sturzhöhe > 1m: ${_xStr(door['lintelHeightInsideOver1m'] ?? door['lintelHeightOutsideOver1m'])}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 8)).value = TextCellValue('Fluchttürsteuerung: ${_xStr(door['escapeDoorControl'])} | Fluchtwegsituation: ${_xStr(door['escapeRouteSituation'])} | Fluchtwegbeschilderung: ${_xStr(door['escapeRouteSignage'])}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 9)).value = TextCellValue('Blindzylinder: ${_xStr(door['blindCylinder'])} | PZ-Zylinder: ${_xStr(door['pzCylinder'])} | Fluchtrichtung beachtet: ${_xStr(door['escapeDirectionRespected'])} | Vollpanik Standflügel: ${_xStr(door['fullPanicStandWing'])} | Türfunktion OK: ${_jnStr(door['doorFunctionOK'])}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 10)).value = TextCellValue('Notizen: ${door['notes'] ?? ''}');

    // Section 2: Timeline
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 12)).value = TextCellValue('INSPEKTIONSHISTORIE & MÄNGELPROTOKOLL');
    final headers = ['Datum', 'Kunde', 'Objektadresse', 'Auftrag', 'Status', 'Erfasste Mängel', 'Notizen'];
    for (int col = 0; col < headers.length; col++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 13)).value = TextCellValue(headers[col]);
    }

    int rowIdx = 14;
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
