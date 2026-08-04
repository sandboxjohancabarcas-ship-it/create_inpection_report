import 'dart:io';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';

class ExcelImportResult {
  final int sheetsProcessed;
  final int doorsImported;
  final int errorsLinked;
  final List<String> warnings;

  ExcelImportResult({
    required this.sheetsProcessed,
    required this.doorsImported,
    required this.errorsLinked,
    required this.warnings,
  });
}

class ExcelDataImporter {
  /// Main entry point: parses the Excel file and imports its door inspection history
  static Future<ExcelImportResult> importFromFile(File excelFile) async {
    final List<int> bytes = await excelFile.readAsBytes();
    final decoder = SpreadsheetDecoder.decodeBytes(bytes);
    final warnings = <String>[];

    // 1. Process Fehlerübersicht and populate error_catalog
    final fehlerSheet = decoder.tables['Fehlerübersicht'];
    if (fehlerSheet == null) {
      throw Exception('Das Arbeitsblatt "Fehlerübersicht" fehlt in der Excel-Datei.');
    }

    int catalogInserted = 0;
    for (int r = 1; r < fehlerSheet.maxRows; r++) {
      final row = fehlerSheet.rows[r];
      if (row.length > 2) {
        final codeVal = row[1];
        final descVal = row[2];
        if (codeVal != null && descVal != null) {
          final code = codeVal.toString().trim();
          final desc = descVal.toString().trim();
          if (code.isNotEmpty && desc.isNotEmpty) {
            final isNotice = code.startsWith('0.');
            final cat = isNotice ? 'Hinweis' : 'Mangel';
            final sev = isNotice ? 'low' : 'medium';
            
            await DatabaseService.insertErrorCatalog(ErrorCatalog(
              code: code,
              description: desc,
              category: cat,
              severity: sev,
              status: 'Approved',
            ));
            catalogInserted++;
          }
        }
      }
    }

    // Refresh memory catalog list
    final catalog = await DatabaseService.getAllErrorCatalog();

    int sheetsProcessed = 0;
    int totalDoorsImported = 0;
    int totalErrorsLinked = 0;

    // 2. Locate and process Türlisten sheets
    for (var sheetName in decoder.tables.keys) {
      if (!sheetName.toLowerCase().startsWith('türlisten')) continue;
      
      final sheet = decoder.tables[sheetName]!;
      if (sheet.maxRows < 4) {
        warnings.add('Arbeitsblatt "$sheetName" hat nicht genügend Zeilen.');
        continue;
      }

      final row0 = sheet.rows[0];
      if (row0.isEmpty || row0[0] == null) {
        warnings.add('Arbeitsblatt "$sheetName" hat eine leere erste Zeile.');
        continue;
      }

      final metadataText = row0[0].toString();
      final meta = _parseMetadata(metadataText);

      // Create the Inspection record
      final inspectionId = await DatabaseService.insertInspection(meta);
      sheetsProcessed++;

      // Analyze Column headers at Row 2 (3rd row) to build error column mappings
      final headerRow = sheet.rows[2];
      final errorColumns = <int, String>{}; // colIndex -> code
      
      // Scan from column 27 (AB) onwards for error headers
      for (int c = 27; c < headerRow.length; c++) {
        final val = headerRow[c];
        if (val == null) continue;
        final headerStr = val.toString().trim();
        if (headerStr.toLowerCase() == 'anmerkung') {
          break; // Stop at notes column
        }
        
        // Try to parse code (e.g. "0.32 Das Brand-...")
        final match = RegExp(r'^([\d\.]+)\s+(.*)$').firstMatch(headerStr);
        if (match != null) {
          final code = match.group(1)!;
          errorColumns[c] = code;
        } else {
          warnings.add('Konnte Mängelcode aus Spaltenkopf "$headerStr" nicht lesen. Übersprungen.');
        }
      }

      // Process Door data rows (Row 3 onwards)
      for (int r = 3; r < sheet.maxRows; r++) {
        final row = sheet.rows[r];
        if (row.isEmpty || row[0] == null || row[0].toString().trim().isEmpty) continue;

        final pos = _toInt(row[0]);
        final doorNumber = _toStr(row[1]);
        final floor = _toStr(row[2]);
        final roomNumber = _toStr(row[3]);
        final roomDesignation = _toStr(row[4]);
        
        // Normalization check on physical properties
        final doorType = _toStr(row[5]);
        final wingCount = _toInt(row[6], defaultValue: 1);
        final material = _toStr(row[7]);
        final manufacturer = _toStr(row[8]);
        final dinConfig = _toStr(row[9]);
        final closerType = _toStr(row[10]);
        final closingSeq = _toStr(row[11]);
        final lockDim = _toStr(row[12]);
        
        final closerHinge = _toBool(row[13]);
        final closerOpposite = _toBool(row[14]);
        final lintelUnder1m = _toBool(row[15]);
        final escapeDoorControl = _toBool(row[16]);
        final accessControl = _toStr(row[17]);
        final escapeRouteSituation = _toBool(row[18]);
        final escapeRouteSignage = _toBool(row[19]);
        final blindCyl = _toBool(row[20]);
        final pzCyl = _toBool(row[21]);
        final fittingType = _toStr(row[22]);
        final panicFunc = _toStr(row[23]);
        final escapeDirectionRespected = _toBool(row[24]);
        final fullPanicStandWing = _toBool(row[25]);
        final doorFunctionOK = _toBool(row[26]);

        // Handle door alias creation (include floor to distinguish doors with identical numbers across floors)
        final alias = Door.generateAlias(meta['clientName']!, meta['objectAddress']!, doorNumber, floor: floor);

        final door = Door(
          id: null,
          pos: pos,
          doorAlias: alias,
          doorNumber: doorNumber,
          floor: floor,
          roomNumber: roomNumber,
          roomDesignation: roomDesignation,
          doorType: doorType,
          wingCount: wingCount,
          material: material,
          manufacturer: manufacturer,
          dinConfiguration: dinConfig,
          closerType: closerType,
          closingSequenceSystem: closingSeq,
          lockDimensions: lockDim,
          closerOnHingeSide: closerHinge,
          closerOnOppositeSide: closerOpposite,
          lintelHeightUnder1m: lintelUnder1m,
          escapeDoorControl: escapeDoorControl,
          accessControl: accessControl,
          escapeRouteSituation: escapeRouteSituation,
          escapeRouteSignage: escapeRouteSignage,
          blindCylinder: blindCyl,
          pzCylinder: pzCyl,
          fittingType: fittingType,
          panicFunction: panicFunc,
          escapeDirectionRespected: escapeDirectionRespected,
          fullPanicStandWing: fullPanicStandWing,
          doorFunctionOK: doorFunctionOK,
        );

        final doorId = await DatabaseService.insertDoor(door);

        // Notes column is Col 37 (AL)
        String notes = 'Importiert aus Excel';
        if (row.length > 37 && row[37] != null) {
          notes = row[37].toString().trim();
        }

        final junctionId = await DatabaseService.insertInspectionDoor({
          'inspectionId': inspectionId,
          'doorId': doorId,
          'status': doorFunctionOK ? 'Passed' : 'Failed',
          'notes': notes,
        });
        totalDoorsImported++;

        // Process error quantities in error columns
        for (var entry in errorColumns.entries) {
          final cIndex = entry.key;
          final code = entry.value;

          if (cIndex < row.length && row[cIndex] != null) {
            final qty = _toInt(row[cIndex]);
            if (qty > 0) {
              // Find in catalog
              final catalogItem = catalog.firstWhere((e) => e.code == code, orElse: () => ErrorCatalog(code: code, description: 'Excel-Fehler $code', category: 'Allgemein'));
              
              // If it's a fallback item not in catalog, insert it
              int errorId;
              if (catalogItem.errorId == null) {
                await DatabaseService.insertErrorCatalog(catalogItem);
                final newlyInserted = await DatabaseService.searchErrorCatalog(code);
                errorId = newlyInserted.first.errorId!;
              } else {
                errorId = catalogItem.errorId!;
              }

              await DatabaseService.insertInspectionDoorError(InspectionDoorError(
                inspectionDoorId: junctionId,
                errorId: errorId,
                errorCode: catalogItem.code,
                quantity: qty,
                severity: catalogItem.severity,
                notes: 'Excel-Spalte $code',
              ));
              totalErrorsLinked++;
            }
          }
        }
      }
    }

    return ExcelImportResult(
      sheetsProcessed: sheetsProcessed,
      doorsImported: totalDoorsImported,
      errorsLinked: totalErrorsLinked,
      warnings: warnings,
    );
  }

  static Map<String, String> _parseMetadata(String text) {
    String extract(String label, List<String> nextLabels) {
      final nextOrEnd = nextLabels.isNotEmpty ? nextLabels.join('|') : '\$';
      final pattern = RegExp('$label:\\s*(.*?)(?=$nextOrEnd|\\s+\\w+:\\s*|\\s*\$)');
      final match = pattern.firstMatch(text);
      return match?.group(1)?.trim() ?? '';
    }

    final client = extract('Kunde', ['Objekt', 'Datum', 'Ansprechpartner', 'Monteur', 'Auftragsnummer']);
    final object = extract('Objekt', ['Kunde', 'Datum', 'Ansprechpartner', 'Monteur', 'Auftragsnummer']);
    final dateStr = extract('Datum', ['Kunde', 'Objekt', 'Ansprechpartner', 'Monteur', 'Auftragsnummer']);
    final contact = extract('Ansprechpartner', ['Kunde', 'Objekt', 'Datum', 'Monteur', 'Auftragsnummer']);
    final inspector = extract('Monteur', ['Kunde', 'Objekt', 'Datum', 'Ansprechpartner', 'Auftragsnummer']);
    final jobNum = extract('Auftragsnummer', ['Kunde', 'Objekt', 'Datum', 'Ansprechpartner', 'Monteur']);

    String formattedDate = '';
    if (dateStr.isNotEmpty) {
      final dateMatch = RegExp(r'(\d{2})\.(\d{2})\.(\d{4})').firstMatch(dateStr);
      if (dateMatch != null) {
        formattedDate = '${dateMatch.group(3)}-${dateMatch.group(2)!.padLeft(2, '0')}-${dateMatch.group(1)!.padLeft(2, '0')}';
      }
    }
    if (formattedDate.isEmpty) {
      formattedDate = DateTime.now().toIso8601String().substring(0, 10);
    }

    return {
      'clientName': client.isNotEmpty ? client : 'Stadt Geesthacht',
      'objectAddress': object.isNotEmpty ? object : 'Fam. Zentrum Regenbogen',
      'date': formattedDate,
      'contactPerson': contact.isNotEmpty ? contact : 'Herr Basau',
      'inspectorName': inspector.isNotEmpty ? inspector : 'Gert',
      'jobNumber': jobNum.isNotEmpty ? jobNum : '25-12115-AB',
    };
  }

  static String _toStr(dynamic val) {
    if (val == null) return '';
    return val.toString().trim();
  }

  static int _toInt(dynamic val, {int defaultValue = 0}) {
    if (val == null) return defaultValue;
    if (val is int) return val;
    if (val is double) return val.toInt();
    final parsed = int.tryParse(val.toString().trim());
    return parsed ?? defaultValue;
  }

  static bool _toBool(dynamic val) {
    if (val == null) return false;
    final str = val.toString().trim().toLowerCase();
    return str == 'x' || str == 'j' || str == 'ja' || str == '1' || str == 'true';
  }
}
