import 'dart:io';
import 'package:excel/excel.dart';
import 'package:wartungstool/services/database_service.dart';

class ExcelExportService {
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

    // Row 2: Headers
    final headers = [
      'Pos',
      'Tür-Nr.',
      'Geschoss',
      'Raumnr.',
      'Raumbezeichnung',
      'Hersteller',
      'Breite',
      'Höhe',
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
        TextCellValue('$posCounter'),
        TextCellValue(d['doorNumber'] as String? ?? ''),
        TextCellValue(d['floor'] as String? ?? ''),
        TextCellValue(d['roomNumber'] as String? ?? ''),
        TextCellValue(d['roomDesignation'] as String? ?? ''),
        TextCellValue(d['manufacturer'] as String? ?? ''),
        TextCellValue(d['width'] != null ? '${d['width']}' : ''),
        TextCellValue(d['height'] != null ? '${d['height']}' : ''),
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

    // Tab 2: Defect History Ledger
    final defectSheet = excel['Mängelhistorie (Revision)'];
    final defectHeaders = ['Datum', 'Auftrag', 'Tür-Alias', 'Tür-Nr.', 'Geschoss', 'Raum', 'Mängelcode', 'Kategorie', 'Beschreibung', 'Notizen'];
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
        final room = d['roomDesignation'] as String? ?? '';
        final errors = d['errors'] as List<Map<String, dynamic>>? ?? [];

        for (final e in errors) {
          defectSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: defectRowIdx)).value = TextCellValue(date);
          defectSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: defectRowIdx)).value = TextCellValue(job);
          defectSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: defectRowIdx)).value = TextCellValue(alias);
          defectSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: defectRowIdx)).value = TextCellValue(doorNum);
          defectSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: defectRowIdx)).value = TextCellValue(floor);
          defectSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: defectRowIdx)).value = TextCellValue(room);
          defectSheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: defectRowIdx)).value = TextCellValue(e['errorCode'] as String? ?? e['code'] as String? ?? '');
          defectSheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: defectRowIdx)).value = TextCellValue(e['errorCat'] as String? ?? e['category'] as String? ?? '');
          defectSheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: defectRowIdx)).value = TextCellValue(e['errorDesc'] as String? ?? e['description'] as String? ?? '');
          defectSheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: defectRowIdx)).value = TextCellValue(e['notes'] as String? ?? '');
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
    final door = historyData['door'] as Map<String, dynamic>? ?? {};
    final inspections = historyData['inspections'] as List<Map<String, dynamic>>? ?? [];

    final excel = Excel.createExcel();
    final sheet = excel['Tür-Akte ${door['doorAlias']}'];
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Section 1: Specs
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('STAMMDATEN TÜR-AKTE');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('Tür-Alias (QR/Patienten-ID): ${door['doorAlias']}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('Türnummer: ${door['doorNumber']}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3)).value = TextCellValue('Geschoss: ${door['floor']} | Raumnr: ${door['roomNumber']} | Raum: ${door['roomDesignation']}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4)).value = TextCellValue('Hersteller: ${door['manufacturer']} | Funktion: ${door['doorFunction']} | Brandschutz: ${door['fireProtection']}');

    // Section 2: Timeline
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 6)).value = TextCellValue('INSPEKTIONSHISTORIE & MÄNGELPROTOKOLL');
    final headers = ['Datum', 'Kunde', 'Objektadresse', 'Auftrag', 'Status', 'Erfasste Mängel', 'Notizen'];
    for (int col = 0; col < headers.length; col++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 7)).value = TextCellValue(headers[col]);
    }

    int rowIdx = 8;
    for (final insp in inspections) {
      final errors = insp['errors'] as List<Map<String, dynamic>>? ?? [];
      final errorSummary = errors.map((e) => '${e['errorCode'] ?? e['code']}: ${e['errorDesc'] ?? e['description']}').join(' | ');

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).value = TextCellValue(insp['date'] as String? ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx)).value = TextCellValue(insp['clientName'] as String? ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx)).value = TextCellValue(insp['objectAddress'] as String? ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx)).value = TextCellValue(insp['jobNumber'] as String? ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx)).value = TextCellValue(insp['status'] as String? ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx)).value = TextCellValue(errorSummary);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx)).value = TextCellValue(insp['notes'] as String? ?? '');
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
