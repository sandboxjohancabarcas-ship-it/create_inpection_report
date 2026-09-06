import 'dart:io';
import 'package:excel/excel.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';

class ExcelExportService {
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

  /// Exports a single inspection job to a formatted Excel workbook (.xlsx)
  static Future<File> exportSingleInspection(int inspectionId, String outputPath) async {
    final data = await DatabaseService.getSingleInspectionExportData(inspectionId);
    if (data.isEmpty) {
      throw Exception('Inspektionsdaten nicht gefunden.');
    }

    final excel = Excel.createExcel();
    final insp = data['inspection'] as Map<String, dynamic>;
    final doors = data['doors'] as List<Map<String, dynamic>>;

    final String clientName = insp['clientName'] as String? ?? 'Kunde';
    final String dateStr = insp['date'] as String? ?? '';
    final String sheetName = 'Türlisten ${dateStr.replaceAll('-', '.')}';

    // Rename default sheet or create
    final sheet = excel[sheetName];
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Row 0: Metadata Header
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue(
      'Kunde: $clientName | Objekt: ${insp['objectAddress'] ?? ''} | Datum: $dateStr | Auftrag: ${insp['jobNumber'] ?? ''} | Projekt: ${insp['projectNumber'] ?? ''}',
    );

    // Collect all distinct error codes across doors in this inspection
    final Set<String> defectCodes = {};
    for (final d in doors) {
      final errors = d['errors'] as List<Map<String, dynamic>>? ?? [];
      for (final e in errors) {
        final code = (e['errorCode'] ?? e['code'] ?? '') as String;
        if (code.isNotEmpty) defectCodes.add(code);
      }
    }
    final sortedDefectCodes = defectCodes.toList()..sort();

    // Row 2: Headers (All 28 door properties + Status, Notes & Defect codes)
    final headers = [
      'Pos',
      'Tür-Alias',
      'Tür-Nr.',
      'Geschoss',
      'Raumnr.',
      'Raumbezeichnung',
      'Türart',
      'Flügelanzahl',
      'Material',
      'Hersteller',
      'DIN-Richtung',
      'Schließertyp',
      'Schließfolgeregler',
      'Schlossmaße',
      'Beschlagart',
      'Panikfunktion',
      'Zutrittskontrolle',
      'Schließer Bandseite',
      'Schließer Bandgegenseite',
      'Sturzhöhe < 1m',
      'Fluchttürsteuerung',
      'Fluchtwegsituation',
      'Fluchtwegbeschilderung',
      'Blindzylinder',
      'PZ-Zylinder',
      'Fluchtrichtung beachtet',
      'Vollpanik Standflügel',
      'Türfunktion OK',
      'Status',
      'Bemerkung',
      ...sortedDefectCodes.map((c) => 'Mangel $c'),
    ];

    for (int col = 0; col < headers.length; col++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 2)).value = TextCellValue(headers[col]);
    }

    // Row 3+: Door rows
    int rowIndex = 3;
    int posCounter = 1;

    for (final d in doors) {
      final errors = d['errors'] as List<Map<String, dynamic>>? ?? [];
      final doorErrorCodes = errors.map((e) => (e['errorCode'] ?? e['code'] ?? '') as String).toSet();

      final rowCells = [
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
        TextCellValue(d['fittingType'] as String? ?? ''),
        TextCellValue(d['panicFunction'] as String? ?? ''),
        TextCellValue(d['accessControl'] as String? ?? ''),
        TextCellValue(_boolToStr(d['closerOnHingeSide'])),
        TextCellValue(_boolToStr(d['closerOnOppositeSide'])),
        TextCellValue(_boolToStr(d['lintelHeightUnder1m'])),
        TextCellValue(_boolToStr(d['escapeDoorControl'])),
        TextCellValue(_boolToStr(d['escapeRouteSituation'])),
        TextCellValue(_boolToStr(d['escapeRouteSignage'])),
        TextCellValue(_boolToStr(d['blindCylinder'])),
        TextCellValue(_boolToStr(d['pzCylinder'])),
        TextCellValue(_boolToStr(d['escapeDirectionRespected'])),
        TextCellValue(_boolToStr(d['fullPanicStandWing'])),
        TextCellValue(_boolToStr(d['doorFunctionOK'])),
        TextCellValue(d['junctionStatus'] as String? ?? 'InProgress'),
        TextCellValue(d['junctionNotes'] as String? ?? ''),
        ...sortedDefectCodes.map((code) => TextCellValue(doorErrorCodes.contains(code) ? 'X' : '')),
      ];

      for (int col = 0; col < rowCells.length; col++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex)).value = rowCells[col];
      }
      rowIndex++;
      posCounter++;
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
      'Datum', 'Auftrag', 'Tür-Alias', 'Tür-Nr.', 'Geschoss', 'Raumnr.', 'Raum',
      'Türart', 'Flügel', 'Material', 'Hersteller', 'DIN', 'Schließer', 'Schließfolge',
      'Schlossmaß', 'Beschlag', 'Panikfkt', 'Zutrittskontrolle', 'Bandseite', 'Bandgegenseite',
      'Sturzhöhe<1m', 'Fluchttürsteu.', 'Fluchtwegsit.', 'Beschilderung', 'Blindzyl.', 'PZ-Zyl.',
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
            _boolToStr(d['closerOnHingeSide']), _boolToStr(d['closerOnOppositeSide']),
            _boolToStr(d['lintelHeightUnder1m']), _boolToStr(d['escapeDoorControl']),
            _boolToStr(d['escapeRouteSituation']), _boolToStr(d['escapeRouteSignage']),
            _boolToStr(d['blindCylinder']), _boolToStr(d['pzCylinder']),
            _boolToStr(d['escapeDirectionRespected']), _boolToStr(d['fullPanicStandWing']),
            _boolToStr(d['doorFunctionOK']),
            e['errorCode'] as String? ?? e['code'] as String? ?? '',
            e['errorCat'] as String? ?? e['category'] as String? ?? '',
            e['errorDesc'] as String? ?? e['description'] as String? ?? '',
            e['notes'] as String? ?? '',
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

    // Section 1: Specs (All 28 door properties)
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('STAMMDATEN TÜR-AKTE (ALLE TÜR-EIGENSCHAFTEN)');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('Tür-Alias (QR/Patienten-ID): ${door['doorAlias'] ?? ''}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('Türnummer: ${door['doorNumber'] ?? ''} | Pos: ${door['pos'] ?? 0}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3)).value = TextCellValue('Geschoss: ${door['floor'] ?? ''} | Raumnr: ${door['roomNumber'] ?? ''} | Raum: ${door['roomDesignation'] ?? ''}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4)).value = TextCellValue('Türart: ${door['doorType'] ?? ''} | Flügelanzahl: ${door['wingCount'] ?? 1} | Material: ${door['material'] ?? ''} | Hersteller: ${door['manufacturer'] ?? ''}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 5)).value = TextCellValue('DIN-Richtung: ${door['dinConfiguration'] ?? ''} | Schließertyp: ${door['closerType'] ?? ''} | Schließfolgeregler: ${door['closingSequenceSystem'] ?? ''}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 6)).value = TextCellValue('Schlossmaße: ${door['lockDimensions'] ?? ''} | Beschlagart: ${door['fittingType'] ?? ''} | Panikfunktion: ${door['panicFunction'] ?? ''} | Zutrittskontrolle: ${door['accessControl'] ?? ''}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 7)).value = TextCellValue('Schließer Bandseite: ${_boolToStr(door['closerOnHingeSide'])} | Schließer Bandgegenseite: ${_boolToStr(door['closerOnOppositeSide'])} | Sturzhöhe < 1m: ${_boolToStr(door['lintelHeightUnder1m'])}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 8)).value = TextCellValue('Fluchttürsteuerung: ${_boolToStr(door['escapeDoorControl'])} | Fluchtwegsituation: ${_boolToStr(door['escapeRouteSituation'])} | Fluchtwegbeschilderung: ${_boolToStr(door['escapeRouteSignage'])}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 9)).value = TextCellValue('Blindzylinder: ${_boolToStr(door['blindCylinder'])} | PZ-Zylinder: ${_boolToStr(door['pzCylinder'])} | Fluchtrichtung beachtet: ${_boolToStr(door['escapeDirectionRespected'])} | Vollpanik Standflügel: ${_boolToStr(door['fullPanicStandWing'])} | Türfunktion OK: ${_boolToStr(door['doorFunctionOK'])}');

    // Section 2: Timeline
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 11)).value = TextCellValue('INSPEKTIONSHISTORIE & MÄNGELPROTOKOLL');
    final headers = ['Datum', 'Kunde', 'Objektadresse', 'Auftrag', 'Status', 'Erfasste Mängel', 'Notizen'];
    for (int col = 0; col < headers.length; col++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 12)).value = TextCellValue(headers[col]);
    }

    int rowIdx = 13;
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

