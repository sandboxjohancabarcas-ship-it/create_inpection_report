import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/customer_normalizer.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/services/window_options_service.dart';

class ExcelImportResult {
  final int sheetsProcessed;
  final int doorsImported;
  final int windowsImported;
  final int errorsLinked;
  final String assetType;
  final List<String> warnings;
  final List<String> logs;

  /// Doors that had conflicts and were NOT written to DB yet.
  /// Route the Manager to DoorConflictReviewPage when this is non-empty.
  final List<DoorConflict> doorConflicts;

  /// Catalog conflicts found during Fehlerübersicht processing.
  final List<ImportConflict> catalogConflicts;

  /// List of individual item changes (doors or windows) imported.
  final List<DoorChangeItem> doorChanges;

  /// Catalog proposals added or discovered during import.
  final List<String> newCatalogProposals;

  /// Metadata extracted during inspection migration
  final String clientName;
  final String objectAddress;
  final String jobNumber;
  final String inspectionDate;

  ExcelImportResult({
    required this.sheetsProcessed,
    this.doorsImported = 0,
    this.windowsImported = 0,
    required this.errorsLinked,
    this.assetType = 'door',
    required this.warnings,
    this.logs = const [],
    this.doorConflicts = const [],
    this.catalogConflicts = const [],
    this.doorChanges = const [],
    this.newCatalogProposals = const [],
    this.clientName = '',
    this.objectAddress = '',
    this.jobNumber = '',
    this.inspectionDate = '',
  });

  bool get hasDoorConflicts => doorConflicts.isNotEmpty;
  bool get hasCatalogConflicts => catalogConflicts.isNotEmpty;
  int get totalItemsImported =>
      assetType == 'window' ? windowsImported : doorsImported;
}

class ExcelDataImporter {
  /// Main entry point: parses the Excel file and imports its door inspection history
  static Future<ExcelImportResult> importFromFile(
    File excelFile, {
    List<ConflictResolution>? resolutions,
  }) async {
    final logs = <String>[];
    final warnings = <String>[];
    final allDoorConflicts = <DoorConflict>[];
    final allCatalogConflicts = <ImportConflict>[];

    logs.add('Starte Excel-Import für Datei: ${excelFile.path}');

    final String fileName = p.basename(excelFile.path);
    final RegExp projRegExp = RegExp(r'(P-\d+)', caseSensitive: false);
    final RegExpMatch? projMatch = projRegExp.firstMatch(fileName);
    final String projectNumber =
        projMatch != null ? projMatch.group(1)!.toUpperCase() : '';

    // Strictly extract job number (Auftragsnummer) from the file name
    final jobMatch = RegExp(r'\b(\d{2}-\d{4,5}(?:-[A-Za-z0-9]+)?)\b').firstMatch(fileName);
    final String fileNameJobNumber = jobMatch != null ? jobMatch.group(1)! : '';

    File fileToRead = excelFile;
    File? tempXlsx;

    final ext = p.extension(excelFile.path).toLowerCase();
    if (ext == '.xlsm' || ext == '.xlms') {
      try {
        final tempPath = p.join(
          Directory.systemTemp.path,
          '${p.basenameWithoutExtension(excelFile.path)}_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        );
        tempXlsx = await excelFile.copy(tempPath);
        fileToRead = tempXlsx;
        logs.add(
            'Makro-Datei ($ext) in temporäre .xlsx umgewandelt: $tempPath');
      } catch (e) {
        logs.add('Hinweis: Konvertierung von $ext in .xlsx übersprungen ($e)');
      }
    }

    final List<int> bytes = await fileToRead.readAsBytes();
    final decoder = SpreadsheetDecoder.decodeBytes(bytes);

    final allSheets = decoder.tables.keys.toList();
    logs.add(
        'Gefundene Arbeitsblätter (${allSheets.length}): ${allSheets.join(', ')}');

    // Auto-detect asset type: Windows vs Doors
    bool isWindowFile = fileName.toLowerCase().contains('fenster');
    if (!isWindowFile) {
      for (final sName in decoder.tables.keys) {
        if (sName.toLowerCase().contains('fenster')) {
          isWindowFile = true;
          break;
        }
        final table = decoder.tables[sName]!;
        for (int r = 0; r < table.maxRows && r < 5; r++) {
          final row = table.rows[r];
          for (final cell in row) {
            final str = cell?.toString().trim().toLowerCase() ?? '';
            if (str == 'fenster nr.' ||
                str == 'fenster nr' ||
                str == 'fensternummer' ||
                str == 'fenstertyp' ||
                str == 'raffstore in ordnung') {
              isWindowFile = true;
              break;
            }
          }
          if (isWindowFile) break;
        }
        if (isWindowFile) break;
      }
    }

    if (isWindowFile) {
      logs.add('Erkanntes Prüfobjekt: FENSTER (assetType: window)');
      return await _importWindowsFromFile(
        decoder: decoder,
        fileName: fileName,
        projectNumber: projectNumber,
        logs: logs,
        warnings: warnings,
      );
    }

    // 1. Ensure master error catalog is initialized from asset/db and apply any resolutions
    await DatabaseService.checkAndInitializeCatalog();
    final Map<String, String> resolvedCodes = {};
    final Set<String> skippedCodes = {};

    // Process Manager conflict resolutions if provided
    if (resolutions != null) {
      for (final res in resolutions) {
        if (res.action == ResolutionAction.skip) {
          skippedCodes.add(res.conflict.code);
          skippedCodes.add(res.conflict.description);
          skippedCodes.add(res.conflict.incoming.description);
        } else if (res.action == ResolutionAction.addAsNew) {
          final newCode = res.newCode ?? res.conflict.code;
          resolvedCodes[res.conflict.code] = newCode;
          resolvedCodes[res.conflict.description] = newCode;
          resolvedCodes[res.conflict.incoming.description] = newCode;
          final approvedIncoming = res.conflict.incoming.copyWith(
            code: newCode,
            status: 'Approved',
            assetType: 'door',
          );
          await DatabaseService.insertErrorCatalog(approvedIncoming);
          try {
            await LocalDatabaseService.insertErrorCatalog(approvedIncoming);
          } catch (_) {}
        } else if (res.action == ResolutionAction.replaceExisting ||
            res.action == ResolutionAction.keepExisting) {
          if (res.newCode != null && res.newCode!.isNotEmpty) {
            resolvedCodes[res.conflict.code] = res.newCode!;
            resolvedCodes[res.conflict.description] = res.newCode!;
            resolvedCodes[res.conflict.incoming.description] = res.newCode!;
          }
        }
      }
      logs.add(
          'Konfliktlösungen angewendet: ${resolvedCodes.length} Codes überschrieben, ${skippedCodes.length} übersprungen.');
    }

    // Refresh memory catalog list (doors only)
    final catalog = await DatabaseService.getAllErrorCatalog(assetType: 'door');
    final officialCatalog = catalog
        .where((e) =>
            e.status == 'Approved' &&
            e.category != 'Altdaten' &&
            !e.code.toUpperCase().startsWith('ALT-') &&
            e.assetType.toLowerCase() != 'window')
        .toList();
    int sheetsProcessed = 0;
    int totalDoorsImported = 0;
    int totalErrorsLinked = 0;

    // 2. Locate and pre-parse dates of Türlisten inspection sheets, then sort them newest-first
    final List<Map<String, dynamic>> doorSheetsToProcess = [];
    for (var sheetName in decoder.tables.keys) {
      final lowerName = sheetName.trim().toLowerCase();
      // Inspection sheets MUST have prefix "türlisten", "türliste", "türen", or "doors"
      final isTuerlistenSheet = lowerName.startsWith('türlisten') ||
          lowerName.startsWith('türliste') ||
          lowerName.startsWith('türen') ||
          lowerName.startsWith('doors');

      if (!isTuerlistenSheet) {
        logs.add(
            'Arbeitsblatt "$sheetName" übersprungen (kein "Türlisten"-Präfix).');
        continue;
      }

      final sheet = decoder.tables[sheetName]!;
      if (sheet.maxRows < 2) {
        final warn =
            'Arbeitsblatt "$sheetName" hat nicht genügend Zeilen (${sheet.maxRows} < 2).';
        warnings.add(warn);
        logs.add('WARNUNG: $warn');
        continue;
      }

      String metadataText = '';
      for (int r = 0; r < sheet.maxRows && r < 3; r++) {
        final row = sheet.rows[r];
        if (row.isNotEmpty &&
            row[0] != null &&
            row[0].toString().trim().isNotEmpty) {
          metadataText = row[0].toString();
          break;
        }
      }

      final meta = _parseMetadata(metadataText);
      // Strictly set job number from file name, not from inside the Excel file
      meta['jobNumber'] = fileNameJobNumber;

      // Extract date from sheet name if present (e.g. "Türlisten 04.09.2025")
      final sheetDateMatch =
          RegExp(r'(\d{2})[\.\-_](\d{2})[\.\-_](\d{4}|\d{2})')
                  .firstMatch(sheetName) ??
              RegExp(r'(\d{4})[\.\-_](\d{2})[\.\-_](\d{2})')
                  .firstMatch(sheetName);
      if (sheetDateMatch != null) {
        if (sheetDateMatch.group(1)!.length == 4) {
          meta['date'] =
              '${sheetDateMatch.group(1)}-${sheetDateMatch.group(2)!.padLeft(2, '0')}-${sheetDateMatch.group(3)!.padLeft(2, '0')}';
        } else {
          final day = sheetDateMatch.group(1)!.padLeft(2, '0');
          final month = sheetDateMatch.group(2)!.padLeft(2, '0');
          var year = sheetDateMatch.group(3)!;
          if (year.length == 2) year = '20$year';
          meta['date'] = '$year-$month-$day';
        }
      }

      final String dateStr = meta['date'] ?? '';
      final DateTime sheetDate =
          DateTime.tryParse(dateStr) ?? DateTime.fromMillisecondsSinceEpoch(0);

      doorSheetsToProcess.add({
        'sheetName': sheetName,
        'sheet': sheet,
        'meta': meta,
        'date': sheetDate,
      });
    }

    // Sort sheets chronologically: newest-first (descending order of date)
    doorSheetsToProcess.sort((a, b) {
      final DateTime dateA = a['date'] as DateTime;
      final DateTime dateB = b['date'] as DateTime;
      return dateB.compareTo(dateA);
    });

    logs.add(
        'Reihenfolge der verarbeiteten Blätter (neueste zuerst): ${doorSheetsToProcess.map((ds) => '${ds['sheetName']} (${ds['meta']['date']})').join(', ')}');

    // ── Evaluate Error Catalog Conflicts on the Latest Inspection Sheet ──
    final latestSheetInfo = doorSheetsToProcess.firstOrNull;
    if (latestSheetInfo != null && resolutions == null) {
      final latestSheet = latestSheetInfo['sheet'] as dynamic;
      final String latestSheetName = latestSheetInfo['sheetName'] as String;

      int lHeaderRowIndex = 2;
      for (int r = 0; r < latestSheet.maxRows && r < 10; r++) {
        final rRow = latestSheet.rows[r];
        if (rRow.isNotEmpty) {
          bool foundHeader = false;
          for (int c = 0; c < rRow.length && c < 5; c++) {
            if (rRow[c] != null) {
              final cellVal = rRow[c].toString().trim().toLowerCase();
              if (cellVal == 'pos' ||
                  cellVal == 'pos.' ||
                  cellVal == 'lfd' ||
                  cellVal == 'nr' ||
                  cellVal == 'tür-nr' ||
                  cellVal == 'türnummer' ||
                  cellVal == 'tür nr') {
                lHeaderRowIndex = r;
                foundHeader = true;
                break;
              }
            }
          }
          if (foundHeader) break;
        }
      }
      if (lHeaderRowIndex >= latestSheet.rows.length) lHeaderRowIndex = 0;
      final lHeaderRow =
          latestSheet.rows.isNotEmpty ? latestSheet.rows[lHeaderRowIndex] : [];

      int lNotesCol = -1;
      if (latestSheet.maxRows > 1) {
        final row2 = latestSheet.rows[1];
        for (int c = 0; c < row2.length; c++) {
          final val = _cell(row2, c);
          if (val != null &&
              val.toString().trim().toLowerCase().startsWith('anmerkung')) {
            lNotesCol = c;
            break;
          }
        }
      }

      int lFixedColCount = 28;
      if (lHeaderRow.length >= 34) {
        final col7 = _toStr(_cell(lHeaderRow, 7)).toLowerCase();
        final col21 = _toStr(_cell(lHeaderRow, 21)).toLowerCase();
        if (col7.contains('zulassung') || col21.contains('sturzhöhe innen')) {
          lFixedColCount = 34;
        }
      }

      for (int c = lFixedColCount; c < lHeaderRow.length; c++) {
        if (c == lNotesCol) continue;
        final val = _cell(lHeaderRow, c);
        if (val == null) continue;
        final headerStr = val.toString().trim();
        if (headerStr.isEmpty ||
            headerStr.toLowerCase().startsWith('anmerkung')) {
          break;
        }

        final match = RegExp(r'^([\d\.]+)\s+(.*)$').firstMatch(headerStr);
        String code;
        String desc;
        if (match != null) {
          code = match.group(1)!;
          desc = match.group(2)!;
        } else {
          final exactCatalogMatch = officialCatalog
              .where((e) =>
                  e.description.trim().toLowerCase() ==
                      headerStr.toLowerCase() ||
                  e.description.trim().toLowerCase() ==
                      headerStr
                          .replaceFirst(
                              RegExp(r'^Hinweis:\s*', caseSensitive: false), '')
                          .trim()
                          .toLowerCase())
              .firstOrNull;
          code = exactCatalogMatch?.code ?? headerStr;
          desc = exactCatalogMatch?.description ?? headerStr;
        }

        final existingForCode = officialCatalog
            .where((e) => e.code.toLowerCase() == code.toLowerCase())
            .firstOrNull;
        final existingForDesc = officialCatalog
            .where((e) =>
                _cleanCatalogDesc(e.description) == _cleanCatalogDesc(desc))
            .firstOrNull;

        final isResolved = resolvedCodes.containsKey(code) ||
            resolvedCodes.containsKey(desc) ||
            resolvedCodes.containsKey(headerStr) ||
            skippedCodes.contains(code) ||
            skippedCodes.contains(desc) ||
            skippedCodes.contains(headerStr);

        if (!isResolved) {
          bool isConflict = false;
          String reason = '';
          ErrorCatalog? existingMatch;

          if (existingForCode == null && existingForDesc == null) {
            isConflict = true;
            reason =
                'Unbekannter Mangel-/Hinweis-Spaltenkopf in neuester Inspektion "$latestSheetName".';
          } else if (existingForCode != null &&
              existingForDesc != null &&
              existingForCode.code.toLowerCase() !=
                  existingForDesc.code.toLowerCase()) {
            isConflict = true;
            existingMatch = existingForCode;
            reason =
                'Mangel "$headerStr" hat Code "$code", aber die Beschreibung entspricht bestehendem Code "${existingForDesc.code}".';
          } else if (existingForCode != null &&
              _cleanCatalogDesc(existingForCode.description) !=
                  _cleanCatalogDesc(desc) &&
              desc.length > 5 &&
              !desc.toLowerCase().startsWith('fehler')) {
            isConflict = true;
            existingMatch = existingForCode;
            reason =
                'Bestehender Eintrag mit Code "$code" hat andere Beschreibung ("${existingForCode.description}").';
          } else if (existingForDesc != null &&
              existingForDesc.code.toLowerCase() != code.toLowerCase() &&
              RegExp(r'^\d+(\.\d+)?$').hasMatch(code)) {
            isConflict = true;
            existingMatch = existingForDesc;
            reason =
                'Bestehender Eintrag mit identischer Beschreibung hat anderen Code (${existingForDesc.code}).';
          }

          if (isConflict) {
            final alreadyInConflict = allCatalogConflicts.any((cf) =>
                cf.code.toLowerCase() == code.toLowerCase() ||
                cf.description.toLowerCase() == headerStr.toLowerCase());

            if (!alreadyInConflict) {
              final isNotice = code.toLowerCase().startsWith('0.') ||
                  code.toLowerCase().startsWith('hinweis') ||
                  headerStr.toLowerCase().contains('hinweis');
              final cat = isNotice ? 'Hinweis' : 'Mangel';
              final sev = isNotice ? 'low' : 'medium';

              allCatalogConflicts.add(ImportConflict(
                code: code,
                description: headerStr,
                incoming: ErrorCatalog(
                  code: code,
                  description: headerStr,
                  category: cat,
                  severity: sev,
                  status: 'Proposed',
                  assetType: 'door',
                ),
                existing: existingMatch ?? existingForCode ?? existingForDesc,
                reason: reason,
              ));

              final msg =
                  '[KATALOG-KONFLIKT] Unbekannter/abweichender Mangel "$headerStr" in neuester Inspektion "$latestSheetName" erfordert Überprüfung durch den Manager.';
              warnings.add(msg);
              logs.add(msg);
            }
          }
        }
      }
      logs.add(
          'Neueste Inspektion "$latestSheetName": ${allCatalogConflicts.length} Mängelkatalog-Konflikte erkannt.');
    }

    // ── Resolve Canonical Object Address for this Project/File ──────────
    final String fileNameAddress = _extractAddressFromFileName(fileName);
    String canonicalObjectAddress = '';

    // Check if filename contains a valid street address
    if (_hasStreetOrNumber(fileNameAddress)) {
      canonicalObjectAddress = fileNameAddress;
    }

    // Check sheets (newest sheet first)
    for (final ds in doorSheetsToProcess) {
      final sheetMeta = ds['meta'] as Map<String, dynamic>;
      final rawAddr = (sheetMeta['objectAddress'] ?? '').toString().trim();
      if (_hasStreetOrNumber(rawAddr)) {
        if (canonicalObjectAddress.isEmpty ||
            rawAddr.length > canonicalObjectAddress.length) {
          canonicalObjectAddress = rawAddr;
        }
      }
    }

    // If still empty, use newest sheet's objectAddress if non-empty, otherwise fileNameAddress
    if (canonicalObjectAddress.isEmpty) {
      final newestAddr =
          (doorSheetsToProcess.firstOrNull?['meta']?['objectAddress'] ?? '')
              .toString()
              .trim();
      canonicalObjectAddress =
          newestAddr.isNotEmpty ? newestAddr : fileNameAddress;
    }

    if (canonicalObjectAddress.isNotEmpty && projectNumber.isNotEmpty) {
      logs.add(
          'Projekt-Anker $projectNumber: Kanonische Liegenschaftsadresse festgelegt als: "$canonicalObjectAddress"');
    }

    for (final dsInfo in doorSheetsToProcess) {
      final String sheetName = dsInfo['sheetName'] as String;
      final sheet = dsInfo['sheet'];
      final Map<String, String> meta =
          Map<String, String>.from(dsInfo['meta'] as Map);
      meta['projectNumber'] = projectNumber;
      if (meta['clientName'] != null && meta['clientName']!.isNotEmpty) {
        meta['clientName'] =
            CustomerNormalizer.getCanonicalName(meta['clientName']!);
      }

      // If sheet has a short/incomplete address or differs from canonical address for this project, unify it
      final String rawSheetAddr = (meta['objectAddress'] ?? '').trim();
      if (canonicalObjectAddress.isNotEmpty) {
        if (rawSheetAddr.isEmpty ||
            !_hasStreetOrNumber(rawSheetAddr) ||
            projectNumber.isNotEmpty) {
          meta['objectAddress'] = canonicalObjectAddress;
        }
      }

      logs.add(
          'Verarbeite Türlisten-Blatt: "$sheetName" (${sheet.maxRows} Zeilen)...');
      logs.add(
          'Metadaten für "$sheetName": Kunde="${meta['clientName']}", Objekt="${meta['objectAddress']}", Datum="${meta['date']}", Auftrag="${meta['jobNumber']}", Projektnummer="${meta['projectNumber']}"');

      // Check for existing inspection to warn user on duplicate re-import
      final existingInspId =
          await DatabaseService.findExistingInspectionId(meta);
      if (existingInspId != null) {
        logs.add(
            'WARNUNG: Das Inspektionsdokument für Auftrag "${meta['jobNumber']}" (Kunde: "${meta['clientName']}", Objekt: "${meta['objectAddress']}", Datum: "${meta['date']}") existiert bereits im Stammdatenbestand.');
      }

      // Fetch existing inspection or create new inspection record to prevent duplication on re-import
      final inspectionId = await DatabaseService.getOrInsertInspection(meta);
      sheetsProcessed++;
      logs.add(
          'Inspektion ID $inspectionId für "$sheetName" (Auftrag: ${meta['jobNumber']}) verarbeitet.');

      // Analyze Column headers to build error column mappings
      int headerRowIndex = 2;
      for (int r = 0; r < sheet.maxRows && r < 10; r++) {
        final rRow = sheet.rows[r];
        if (rRow.isNotEmpty) {
          bool foundHeader = false;
          for (int c = 0; c < rRow.length && c < 5; c++) {
            if (rRow[c] != null) {
              final cellVal = rRow[c].toString().trim().toLowerCase();
              if (cellVal == 'pos' ||
                  cellVal == 'pos.' ||
                  cellVal == 'lfd' ||
                  cellVal == 'nr' ||
                  cellVal == 'tür-nr' ||
                  cellVal == 'türnummer' ||
                  cellVal == 'tür nr') {
                headerRowIndex = r;
                foundHeader = true;
                break;
              }
            }
          }
          if (foundHeader) break;
        }
      }

      if (headerRowIndex >= sheet.rows.length) {
        headerRowIndex = 0;
      }
      final headerRow = sheet.rows.isNotEmpty ? sheet.rows[headerRowIndex] : [];
      final errorColumns = <int, String>{}; // colIndex -> code
      int notesColumnIndex = -1;

      // 1. Scan Row 2 of Excel (Dart index 1) for explicit "Anmerkung" header column
      if (sheet.maxRows > 1) {
        final row2 = sheet.rows[1];
        for (int c = 0; c < row2.length; c++) {
          final val = _cell(row2, c);
          if (val == null) continue;
          final headerStr = val.toString().trim().toLowerCase();
          if (headerStr == 'anmerkung' || headerStr.startsWith('anmerkung')) {
            notesColumnIndex = c;
            break;
          }
        }
      }

      // Fallback: If not found in Row 2, check Row 1 (Dart index 0)
      if (notesColumnIndex == -1 && sheet.maxRows > 0) {
        final row1 = sheet.rows[0];
        for (int c = 0; c < row1.length; c++) {
          final val = _cell(row1, c);
          if (val == null) continue;
          final headerStr = val.toString().trim().toLowerCase();
          if (headerStr == 'anmerkung' || headerStr.startsWith('anmerkung')) {
            notesColumnIndex = c;
            break;
          }
        }
      }

      // 2. Fallback: If header cell is unnamed or blank, scan data rows for column >= 27 containing text notes
      // Determine fixed column count for door specs (34 for new standard, 28 for legacy)
      int fixedColumnCount = 28;
      if (headerRow.length >= 34) {
        final col7 = _toStr(_cell(headerRow, 7)).toLowerCase();
        final col21 = _toStr(_cell(headerRow, 21)).toLowerCase();
        if (col7.contains('zulassung') || col21.contains('sturzhöhe innen')) {
          fixedColumnCount = 34;
        }
      }

      if (notesColumnIndex == -1) {
        final textCountPerCol = <int, int>{};
        for (int r = headerRowIndex + 1; r < sheet.maxRows; r++) {
          final row = sheet.rows[r];
          for (int c = fixedColumnCount; c < row.length; c++) {
            final cell = row[c];
            if (cell != null) {
              final str = cell.toString().trim();
              if (str.isNotEmpty &&
                  str != '1' &&
                  str != '0' &&
                  double.tryParse(str) == null &&
                  str.length > 2) {
                textCountPerCol[c] = (textCountPerCol[c] ?? 0) + 1;
              }
            }
          }
        }

        if (textCountPerCol.isNotEmpty) {
          final sorted = textCountPerCol.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          notesColumnIndex = sorted.first.key;
        }
      }

      // 3. Scan from fixedColumnCount onwards for error headers
      for (int c = fixedColumnCount; c < headerRow.length; c++) {
        if (c == notesColumnIndex) continue;
        final val = _cell(headerRow, c);
        if (val == null) continue;
        final headerStr = val.toString().trim();
        if (headerStr.isEmpty) continue;
        if (headerStr.toLowerCase() == 'anmerkung' ||
            headerStr.toLowerCase().startsWith('anmerkung')) {
          break; // Stop at notes column
        }

        // Try to parse code (e.g. "0.32 Das Brand-...")
        final match = RegExp(r'^([\d\.]+)\s+(.*)$').firstMatch(headerStr);
        String code;
        if (match != null) {
          code = match.group(1)!;
        } else {
          // Check if header matches an existing catalog item by description
          final exactCatalogMatch = catalog
              .where((e) =>
                  e.description.trim().toLowerCase() ==
                      headerStr.toLowerCase() ||
                  e.description.trim().toLowerCase() ==
                      headerStr
                          .replaceFirst(
                              RegExp(r'^Hinweis:\s*', caseSensitive: false), '')
                          .trim()
                          .toLowerCase())
              .firstOrNull;

          if (exactCatalogMatch != null) {
            code = exactCatalogMatch.code;
            logs.add(
                'Spaltenkopf "$headerStr" in "$sheetName" zu bestehendem Katalogcode "${exactCatalogMatch.code}" zugeordnet.');
          } else {
            code = headerStr;
          }
        }

        errorColumns[c] = code;
      }

      logs.add(
          'Mängelspalten für "$sheetName": ${errorColumns.length} Mängelcodes erkannt. (Anmerkung: ${notesColumnIndex >= 0 ? "Spalte $notesColumnIndex" : "Standard"})');

      int sheetDoorsCount = 0;
      int sheetErrorsCount = 0;

      // ── Collect all doors from this sheet first, then batch-merge ────────
      final sheetDoors = <Door>[];
      final sheetDoorRows =
          <int, List<dynamic>>{}; // doorIndex -> raw row for error linking

      // Process Door data rows (Row after header onwards)
      for (int r = headerRowIndex + 1; r < sheet.maxRows; r++) {
        final row = sheet.rows[r];
        if (row.isEmpty) continue;

        final posVal = _toStr(_cell(row, 0));
        final doorNumVal = _toStr(_cell(row, 1));

        // Skip row if both pos and doorNumber are blank or if row contains summary/footer text
        if ((posVal.isEmpty && doorNumVal.isEmpty) ||
            _isSummaryOrFooterText(posVal) ||
            _isSummaryOrFooterText(doorNumVal)) {
          continue;
        }

        final pos = _toInt(_cell(row, 0));
        final rawDoorNumberCell = _cell(row, 1);
        final rawStr = _toStr(rawDoorNumberCell);
        final doorNumber = _sanitizeDoorNumber(rawStr, pos: pos, rowIndex: r);

        final floor = _toStr(_cell(row, 2));
        final roomNumber = _toStr(_cell(row, 3));
        final roomDesignation = _toStr(_cell(row, 4));

        String doorType = '';
        String approvalNumber = '?';
        String manufacturer = '';
        String manufacturerNumber = '?';
        String dopNumber = '?';
        String manufactureYear = '?';
        int wingCount = 1;
        String material = '';
        String dinConfig = '';
        String closerType = '';
        String closingSeq = '';
        String lockDim = '';
        String? fsaDriveAcceptanceDate;
        bool closerHinge = false;
        bool closerOpposite = false;
        bool lintelInsideOver1m = false;
        String? lintelInsideValue;
        bool lintelOutsideOver1m = false;
        String? lintelOutsideValue;
        String accessControl = '';
        String escapeDoorControl = 'Nein';
        bool escapeRouteSituation = false;
        bool escapeRouteSignage = false;
        bool blindCyl = false;
        bool pzCyl = false;
        String fittingType = '';
        String panicFunc = '';
        bool escapeDirectionRespected = false;
        bool fullPanicStandWing = false;
        bool doorFunctionOK = false;

        if (fixedColumnCount == 34) {
          // New standard 34-column layout
          doorType = _toStr(_cell(row, 6));
          final appStr = _toStr(_cell(row, 7));
          approvalNumber = appStr.isNotEmpty ? appStr : '?';
          manufacturer = _toStr(_cell(row, 8));
          final mfgNumStr = _toStr(_cell(row, 9));
          manufacturerNumber = mfgNumStr.isNotEmpty ? mfgNumStr : '?';
          final dopStr = _toStr(_cell(row, 10));
          dopNumber = dopStr.isNotEmpty ? dopStr : '?';
          final yrStr = _toStr(_cell(row, 11));
          manufactureYear = yrStr.isNotEmpty ? yrStr : '?';
          wingCount = _toInt(_cell(row, 12), defaultValue: 1);
          material = _toStr(_cell(row, 13));
          dinConfig = _toStr(_cell(row, 14));
          closerType = _toStr(_cell(row, 15));
          closingSeq = _toStr(_cell(row, 16));
          lockDim = _toStr(_cell(row, 17));
          final fsaStr = _toStr(_cell(row, 18));
          if (fsaStr.isNotEmpty && fsaStr != '?') {
            fsaDriveAcceptanceDate = fsaStr;
          }
          closerHinge = _toBool(_cell(row, 19));
          closerOpposite = _toBool(_cell(row, 20));

          final insideRaw = _toStr(_cell(row, 21));
          if (insideRaw.isNotEmpty) {
            lintelInsideOver1m = _toBool(insideRaw) ||
                insideRaw.contains('m') ||
                insideRaw == 'X' ||
                insideRaw == 'Ja' ||
                insideRaw == 'J';
            if (insideRaw.contains('m') || RegExp(r'\d').hasMatch(insideRaw)) {
              lintelInsideValue = insideRaw;
            }
          }

          final outsideRaw = _toStr(_cell(row, 22));
          if (outsideRaw.isNotEmpty) {
            lintelOutsideOver1m = _toBool(outsideRaw) ||
                outsideRaw.contains('m') ||
                outsideRaw == 'X' ||
                outsideRaw == 'Ja' ||
                outsideRaw == 'J';
            if (outsideRaw.contains('m') ||
                RegExp(r'\d').hasMatch(outsideRaw)) {
              lintelOutsideValue = outsideRaw;
            }
          }

          accessControl = _toStr(_cell(row, 23));
          escapeDoorControl = _toEscapeDoorControl(_cell(row, 24));
          escapeRouteSituation = _toBool(_cell(row, 25));
          escapeRouteSignage = _toBool(_cell(row, 26));
          blindCyl = _toBool(_cell(row, 27));
          pzCyl = _toBool(_cell(row, 28));
          fittingType = _toStr(_cell(row, 29));
          panicFunc = _toStr(_cell(row, 30));
          escapeDirectionRespected = _toBool(_cell(row, 31));
          fullPanicStandWing = _toBool(_cell(row, 32));
          doorFunctionOK = _toBool(_cell(row, 33));
        } else {
          // Legacy 28-column layout
          doorType = _toStr(_cell(row, 5));
          wingCount = _toInt(_cell(row, 6), defaultValue: 1);
          material = _toStr(_cell(row, 7));
          manufacturer = _toStr(_cell(row, 8));
          dinConfig = _toStr(_cell(row, 9));
          closerType = _toStr(_cell(row, 10));
          closingSeq = _toStr(_cell(row, 11));
          lockDim = _toStr(_cell(row, 12));
          closerHinge = _toBool(_cell(row, 13));
          closerOpposite = _toBool(_cell(row, 14));

          final insideRaw = _toStr(_cell(row, 15));
          if (insideRaw.isNotEmpty) {
            lintelInsideOver1m = _toBool(insideRaw) ||
                insideRaw.contains('m') ||
                insideRaw == 'X' ||
                insideRaw == 'Ja' ||
                insideRaw == 'J';
            if (insideRaw.contains('m') || RegExp(r'\d').hasMatch(insideRaw)) {
              lintelInsideValue = insideRaw;
            }
          }

          escapeDoorControl = _toEscapeDoorControl(_cell(row, 16));
          accessControl = _toStr(_cell(row, 17));
          escapeRouteSituation = _toBool(_cell(row, 18));
          escapeRouteSignage = _toBool(_cell(row, 19));
          blindCyl = _toBool(_cell(row, 20));
          pzCyl = _toBool(_cell(row, 21));
          fittingType = _toStr(_cell(row, 22));
          panicFunc = _toStr(_cell(row, 23));
          escapeDirectionRespected = _toBool(_cell(row, 24));
          fullPanicStandWing = _toBool(_cell(row, 25));
          doorFunctionOK = _toBool(_cell(row, 26));
        }

        // Read & format notes from "Anmerkung" column for Door properties
        String rawNotes = '';
        if (notesColumnIndex >= 0 && notesColumnIndex < row.length) {
          rawNotes = _toStr(_cell(row, notesColumnIndex));
        } else if (row.length > fixedColumnCount + 9) {
          rawNotes = _toStr(_cell(row, fixedColumnCount + 9));
        }
        final notes = _formatNotes(rawNotes);

        // Handle door alias creation (format: [Projektnummer (without P-)]-[Pos]-[Floor]-[DoorNumber])
        final alias = Door.generateAlias(
          projectNumber: meta['projectNumber'] ?? '',
          pos: pos,
          floor: floor,
          doorNumber: doorNumber,
        );

        final door = Door(
          id: null,
          pos: pos,
          doorAlias: alias,
          provisionalAlias: alias,
          doorNumber: doorNumber,
          floor: floor,
          roomNumber: roomNumber,
          roomDesignation: roomDesignation,
          doorType: doorType,
          approvalNumber: approvalNumber.isNotEmpty ? approvalNumber : '?',
          manufacturer: manufacturer,
          manufacturerNumber:
              manufacturerNumber.isNotEmpty ? manufacturerNumber : '?',
          dopNumber: dopNumber.isNotEmpty ? dopNumber : '?',
          manufactureYear: manufactureYear.isNotEmpty ? manufactureYear : '?',
          wingCount: wingCount,
          material: material,
          dinConfiguration: dinConfig,
          closerType: closerType,
          closingSequenceSystem: closingSeq,
          lockDimensions: lockDim,
          fsaDriveAcceptanceDate: fsaDriveAcceptanceDate,
          closerOnHingeSide: closerHinge,
          closerOnOppositeSide: closerOpposite,
          lintelHeightInsideOver1m: lintelInsideOver1m,
          lintelHeightInsideValue: lintelInsideValue,
          lintelHeightOutsideOver1m: lintelOutsideOver1m,
          lintelHeightOutsideValue: lintelOutsideValue,
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
          notes: notes,
        );

        sheetDoors.add(door);
        sheetDoorRows[sheetDoors.length - 1] = row;
      }

      // ── Run conflict-aware merge for all doors in this sheet ─────────────
      final String clientStr = (meta['clientName'] ?? '').trim();
      final String jobStr = (meta['jobNumber'] ?? '').trim();
      final String dateStr = (meta['date'] ?? '').trim();
      final String sheetSourceContext =
          'Datei: "$fileName" (Blatt: "$sheetName")'
          '${clientStr.isNotEmpty ? " | Kunde: $clientStr" : ""}'
          '${jobStr.isNotEmpty ? " | Auftragsnr.: $jobStr" : ""}'
          '${dateStr.isNotEmpty ? " | Datum: $dateStr" : ""}';

      final mergeResult = await DatabaseService.mergeDoors(
        sheetDoors,
        jobNumber: meta['jobNumber'] ?? '',
        clientName: meta['clientName'] ?? '',
        objectAddress: meta['objectAddress'] ?? '',
        sourceContext: sheetSourceContext,
        currentInspectionDate: meta['date'] ?? '',
      );

      if (mergeResult.hasConflicts) {
        allDoorConflicts.addAll(mergeResult.conflicts);
        logs.add(
            'KONFLIKTE: ${mergeResult.conflicts.length} Türkonflikte in "$sheetName" '
            '(${mergeResult.identityCount} Identität, ${mergeResult.safetyCount} Sicherheit, '
            '${mergeResult.technicalCount} Technisch, ${mergeResult.logicalCount} Logisch) '
            '— diese Türen wurden NICHT importiert und warten auf Freigabe.');
      }

      // ── Link errors and inspection records for all doors in sheet ──────────────
      for (int di = 0; di < sheetDoors.length; di++) {
        final door = sheetDoors[di];
        final alias = door.doorAlias?.trim() ?? '';

        // Resolve the actual DB id for this door
        Door? inserted = mergeResult.cleanDoors
            .where((d) => (d.doorAlias?.trim() ?? '') == alias)
            .firstOrNull;

        int? doorId = inserted?.id;
        if (doorId == null && alias.isNotEmpty) {
          final existing = await DatabaseService.getDoorByAlias(alias);
          doorId = existing?.id;
        }
        doorId ??= await DatabaseService.insertDoor(door);

        final doorFunctionOK = door.doorFunctionOK;
        final row = sheetDoorRows[di] ?? [];
        final doorNote = door.notes.trim();

        final junctionId = await DatabaseService.insertInspectionDoor({
          'inspectionId': inspectionId,
          'doorId': doorId,
          'status': doorFunctionOK ? 'Passed' : 'Failed',
          'notes': doorNote,
        });
        totalDoorsImported++;
        sheetDoorsCount++;

        // Process error quantities in error columns
        final bool isLatestSheet = (dsInfo == doorSheetsToProcess.first);
        for (var entry in errorColumns.entries) {
          final cIndex = entry.key;
          final code = entry.value;

          // If code was skipped in catalog resolution, ignore it
          if (skippedCodes.contains(code)) continue;

          // Map code based on catalog resolution
          final targetCode = resolvedCodes[code] ?? code;
          final rawHeader = _toStr(_cell(headerRow, cIndex));

          if (cIndex < row.length && row[cIndex] != null) {
            final qty = _toErrorQty(row[cIndex]);
            if (qty > 0) {
              if (isLatestSheet) {
                // Find in catalog using the mapped targetCode or description
                final catalogItem = catalog
                    .where(
                      (e) =>
                          e.code.toLowerCase() == targetCode.toLowerCase() ||
                          e.description.trim().toLowerCase() ==
                              targetCode.toLowerCase(),
                    )
                    .firstOrNull;

                int? errorId = catalogItem?.errorId;
                if (errorId == null) {
                  final dbItem =
                      await DatabaseService.searchErrorCatalog(targetCode);
                  if (dbItem.isNotEmpty && dbItem.first.errorId != null) {
                    errorId = dbItem.first.errorId;
                  }
                }

                if (errorId != null) {
                  await DatabaseService.insertInspectionDoorError(
                      InspectionDoorError(
                    inspectionDoorId: junctionId,
                    errorId: errorId,
                    errorCode: catalogItem?.code ?? targetCode,
                    quantity: qty,
                    severity: catalogItem?.severity ?? 'medium',
                    notes: 'Keine Notizen für Fehler',
                  ));
                  totalErrorsLinked++;
                  sheetErrorsCount++;
                } else {
                  // No auto-registration: unapproved errors are skipped until Manager resolves conflict
                  logs.add(
                      'Mangel "$targetCode" für Tür ${door.doorNumber} in "$sheetName" nicht verknüpft (wartet auf Konfliktlösung durch Manager).');
                }
              } else {
                // Older inspection sheet (Alternative 1: Best-match without raising conflicts)
                final catalogItemByCode = officialCatalog
                    .where(
                      (e) => e.code.toLowerCase() == targetCode.toLowerCase(),
                    )
                    .firstOrNull;

                final catalogItemByDesc = catalogItemByCode == null
                    ? officialCatalog
                        .where((e) =>
                            _cleanCatalogDesc(e.description) ==
                            _cleanCatalogDesc(rawHeader))
                        .firstOrNull
                    : null;

                final catalogItem = catalogItemByCode ?? catalogItemByDesc;

                if (catalogItem != null && catalogItem.errorId != null) {
                  String errorNote = 'Keine Notizen für Fehler';
                  if (rawHeader.isNotEmpty &&
                      _cleanCatalogDesc(catalogItem.description) !=
                          _cleanCatalogDesc(rawHeader)) {
                    errorNote = 'Historische Bezeichnung: $rawHeader';
                  }

                  await DatabaseService.insertInspectionDoorError(
                      InspectionDoorError(
                    inspectionDoorId: junctionId,
                    errorId: catalogItem.errorId!,
                    errorCode: catalogItem.code,
                    quantity: qty,
                    severity: catalogItem.severity,
                    notes: errorNote,
                  ));
                  totalErrorsLinked++;
                  sheetErrorsCount++;
                } else {
                  // Fallback to continuous legacy error entry under category "Altdaten" (e.g. ALT-001, ALT-002, ...)
                  final legacyItem =
                      await DatabaseService.getOrCreateLegacyError(rawHeader);

                  await DatabaseService.insertInspectionDoorError(
                      InspectionDoorError(
                    inspectionDoorId: junctionId,
                    errorId: legacyItem.errorId!,
                    errorCode: legacyItem.code,
                    quantity: qty,
                    severity: legacyItem.severity,
                    notes: 'Historischer Mangel: $rawHeader',
                  ));
                  totalErrorsLinked++;
                  sheetErrorsCount++;
                }
              }
            }
          }
        }
      }

      if (meta['orderType'] == 'Reparatur' || meta['orderType'] == 'Erledigt') {
        final jobNum = meta['jobNumber'] ?? '';
        if (jobNum.isNotEmpty) {
          await DatabaseService.consolidateJobToErledigt(
            jobNumber: jobNum,
            projectNumber: meta['projectNumber'],
          );
        }
      }

      logs.add(
          'Blatt "$sheetName" abgeschlossen: $sheetDoorsCount Türen importiert, $sheetErrorsCount Mängel verknüpft.');
    }

    logs.add(
        'Import abgeschlossen: Total $sheetsProcessed von ${allSheets.length} Arbeitsblättern verarbeitet. $totalDoorsImported Türen, $totalErrorsLinked Mängel verknüpft, ${warnings.length} Warnungen, ${allDoorConflicts.length} Türkonflikte, ${allCatalogConflicts.length} Katalogkonflikte zur Überprüfung.');

    // Write full logs to migration_protocol.log in project root
    try {
      final logFile = File('migration_protocol.log');
      final StringBuffer sb = StringBuffer();
      sb.writeln(
          '======================================================================');
      sb.writeln('MIGRATION PROTOCOL - IMPORT FROM: ${excelFile.path}');
      sb.writeln('Date of Migration: ${DateTime.now()}');
      sb.writeln(
          '======================================================================');
      sb.writeln('SUMMARY:');
      sb.writeln('  - Sheets Processed: $sheetsProcessed');
      sb.writeln('  - Doors Imported: $totalDoorsImported');
      sb.writeln('  - Errors Linked: $totalErrorsLinked');
      sb.writeln('  - Warnings: ${warnings.length}');
      sb.writeln('  - Door Conflicts: ${allDoorConflicts.length}');
      sb.writeln('  - Catalog Conflicts: ${allCatalogConflicts.length}');
      sb.writeln(
          '----------------------------------------------------------------------');
      sb.writeln('MIGRATION LOGS:');
      for (final logLine in logs) {
        sb.writeln('  $logLine');
      }
      sb.writeln(
          '======================================================================\n');

      await logFile.writeAsString(sb.toString(),
          mode: FileMode.append, flush: true);
      print('Migration protocol written to: ${logFile.absolute.path}');
    } catch (e) {
      print('Failed to write migration protocol log file: $e');
    } finally {
      if (tempXlsx != null && tempXlsx.existsSync()) {
        try {
          tempXlsx.deleteSync();
        } catch (_) {}
      }
    }

    return ExcelImportResult(
      sheetsProcessed: sheetsProcessed,
      doorsImported: totalDoorsImported,
      errorsLinked: totalErrorsLinked,
      assetType: 'door',
      warnings: warnings,
      logs: logs,
      doorConflicts: allDoorConflicts,
      catalogConflicts: allCatalogConflicts,
      clientName: doorSheetsToProcess.firstOrNull?['meta']?['clientName'] ?? '',
      objectAddress: canonicalObjectAddress,
      jobNumber: doorSheetsToProcess.firstOrNull?['meta']?['jobNumber'] ?? '',
      inspectionDate: doorSheetsToProcess.firstOrNull?['meta']?['date'] ?? '',
    );
  }

  static Map<String, String> _parseMetadata(String text) {
    String extract(String label, List<String> nextLabels) {
      final nextOrEnd = nextLabels.isNotEmpty ? nextLabels.join('|') : '\$';
      final pattern =
          RegExp('$label:\\s*(.*?)(?=$nextOrEnd|\\s+\\w+:\\s*|\\s*\$)');
      final match = pattern.firstMatch(text);
      return match?.group(1)?.trim() ?? '';
    }

    final client = extract('Kunde', [
      'Objekt',
      'Datum',
      'Ansprechpartner',
      'Kontakt Person vor Ort',
      'Monteur',
      'Service Techniker',
      'Auftragsnummer',
      'Auftragsnr.',
      'Projekt'
    ]);
    final object = extract('Objekt', [
      'Kunde',
      'Datum',
      'Ansprechpartner',
      'Kontakt Person vor Ort',
      'Monteur',
      'Service Techniker',
      'Auftragsnummer',
      'Auftragsnr.',
      'Projekt'
    ]);
    final dateStr = extract('Datum', [
      'Kunde',
      'Objekt',
      'Ansprechpartner',
      'Kontakt Person vor Ort',
      'Monteur',
      'Service Techniker',
      'Auftragsnummer',
      'Auftragsnr.',
      'Projekt'
    ]);
    final contact = extract('(?:Ansprechpartner|Kontakt Person vor Ort)', [
      'Kunde',
      'Objekt',
      'Datum',
      'Monteur',
      'Service Techniker',
      'Auftragsnummer',
      'Auftragsnr.',
      'Projekt'
    ]);
    final inspector = extract('(?:Monteur|Service Techniker)', [
      'Kunde',
      'Objekt',
      'Datum',
      'Ansprechpartner',
      'Kontakt Person vor Ort',
      'Auftragsnummer',
      'Auftragsnr.',
      'Projekt'
    ]);
    String formattedDate = '';
    if (dateStr.isNotEmpty) {
      final dateMatch =
          RegExp(r'(\d{2})\.(\d{2})\.(\d{4})').firstMatch(dateStr);
      if (dateMatch != null) {
        formattedDate =
            '${dateMatch.group(3)}-${dateMatch.group(2)!.padLeft(2, '0')}-${dateMatch.group(1)!.padLeft(2, '0')}';
      }
    }
    if (formattedDate.isEmpty) {
      formattedDate = DateTime.now().toIso8601String().substring(0, 10);
    }

    final cleanClient = CustomerNormalizer.getCanonicalName(client);

    return {
      'clientName': cleanClient.isNotEmpty ? cleanClient : 'Stadt Geesthacht',
      'objectAddress': object.isNotEmpty ? object : 'Fam. Zentrum Regenbogen',
      'date': formattedDate,
      'contactPerson': contact.isNotEmpty ? contact : 'Herr Basau',
      'inspectorName': inspector.isNotEmpty ? inspector : 'Gert',
      'jobNumber': '',
    };
  }

  static String _extractAddressFromFileName(String fileName) {
    String clean = p.basenameWithoutExtension(fileName);
    // Remove job number pattern e.g. 25-13966-AB, 26-14332-AB, 23-08561-AB
    clean = clean.replaceAll(RegExp(r'\b\d{2}-\d{5}(?:-[A-Za-z0-9]+)?\b'), ' ');
    // Remove project number pattern e.g. P-000604, P-003341, P-000362
    clean = clean.replaceAll(RegExp(r'\bP-\d+\b', caseSensitive: false), ' ');
    // Remove suffixes like Türen, Türliste, final, Monteur, Wartung, KINCHI, TEST, Kopie, template, Fenster, Fensterliste, Mängelbeseitigung, Altbau, Neubau
    clean = clean.replaceAll(
        RegExp(
            r'\b(Fensterliste|Fensterprüfung|Fenster|Türen|Türliste|final|Monteur|Wartung|KINCHI|TEST|Kopie|template|1 Monteur|Mängelbeseitigung|Altbau|Neubau)\b',
            caseSensitive: false),
        ' ');
    // Remove trailing "Mieter ..." if present in filename
    clean = clean.replaceAll(RegExp(r'\bMieter\b.*$', caseSensitive: false), ' ');
    // Remove underscores and isolated hyphens (preserving hyphenated German street names like Carl-Cohn-Straße)
    clean = clean.replaceAll('_', ' ');
    clean = clean.replaceAll(RegExp(r'\s+-\s+'), ' ');
    clean = clean.replaceAll(RegExp(r'^[-_,\s]+|[-_,\s]+$'), '');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean;
  }

  static bool _hasStreetOrNumber(String address) {
    if (address.isEmpty) return false;
    final lower = address.toLowerCase();
    final hasPostalCode = RegExp(r'\b\d{5}\b').hasMatch(address);
    final hasStreetKeyword = lower.contains('straße') ||
        lower.contains('strasse') ||
        lower.contains('str.') ||
        lower.contains('str ') ||
        lower.contains('weg') ||
        lower.contains('platz') ||
        lower.contains('allee') ||
        lower.contains('ring') ||
        lower.contains('damm') ||
        lower.contains('ufer') ||
        lower.contains('chaussee') ||
        lower.contains('gasse') ||
        lower.contains('krug') ||
        lower.contains('bogen') ||
        lower.contains('hafen') ||
        lower.contains('kai') ||
        lower.contains('fleet') ||
        lower.contains('deich') ||
        lower.contains('wall') ||
        lower.contains('stieg') ||
        lower.contains('twiete') ||
        lower.contains('kamp') ||
        lower.contains('berg') ||
        lower.contains('brücke') ||
        lower.contains('markt');
    final hasNumber = RegExp(r'\d+').hasMatch(address);
    return (hasStreetKeyword || hasPostalCode) && hasNumber;
  }

  /// Extracts the property address from row 0/1 (Columns E, F, G or cells labeled "Objekt:" / "Objeckt:").
  static String _extractObjectAddressFromWindowSheet(SpreadsheetTable table) {
    if (table.maxRows == 0) return '';

    for (int r = 0; r < table.maxRows && r < 2; r++) {
      final row = table.rows[r];

      // 1. Scan for cell matching "objekt:" or "objeckt:"
      for (int i = 0; i < row.length; i++) {
        final cellStr = _toStr(_cell(row, i)).trim();
        if (cellStr.isEmpty) continue;

        final match = RegExp(r'^objec?kt:?\s*(.*)$', caseSensitive: false)
            .firstMatch(cellStr);
        if (match != null) {
          final inlineAddr = match.group(1)!.trim();
          if (inlineAddr.isNotEmpty) {
            return inlineAddr;
          }
          // "Objekt:" is alone in cell i. Check adjacent cells (e.g., Col F, G)
          for (int nextIdx = i + 1;
              nextIdx < row.length && nextIdx <= i + 3;
              nextIdx++) {
            final nextVal = _toStr(_cell(row, nextIdx)).trim();
            if (nextVal.isNotEmpty &&
                !nextVal.toLowerCase().startsWith('angebot') &&
                !nextVal.toLowerCase().startsWith('auftrag') &&
                !nextVal.toLowerCase().startsWith('kunde')) {
              return nextVal;
            }
          }
        }
      }

      // 2. Also check specifically Columns E (idx 4), F (idx 5), G (idx 6) in row r
      for (final cIdx in [4, 5, 6]) {
        if (cIdx < row.length) {
          final cellStr = _toStr(_cell(row, cIdx)).trim();
          if (cellStr.isNotEmpty) {
            final lower = cellStr.toLowerCase();
            if (lower.startsWith('objekt:') || lower.startsWith('objeckt:')) {
              final addr = cellStr
                  .replaceFirst(
                      RegExp(r'^objec?kt:?\s*', caseSensitive: false), '')
                  .trim();
              if (addr.isNotEmpty) return addr;
            } else if (_hasStreetOrNumber(cellStr)) {
              return cellStr;
            }
          }
        }
      }
    }

    return '';
  }

  static bool _isSummaryOrFooterText(String str) {
    final lower = str.trim().toLowerCase();
    if (lower.isEmpty) return false;
    return lower.startsWith('gesamtzahl') ||
        lower.startsWith('summe') ||
        lower.startsWith('unterschrift') ||
        lower.startsWith('kunde') ||
        lower.startsWith('objekt') ||
        lower.startsWith('monteur') ||
        lower.startsWith('datum') ||
        lower.startsWith('bemerkung') ||
        lower.startsWith('anzahl') ||
        lower.startsWith('gesamt') ||
        lower.startsWith('geprüft') ||
        lower.startsWith('prüfer');
  }

  static dynamic _cell(List<dynamic>? row, int index) {
    if (row == null || index < 0 || index >= row.length) {
      return null;
    }
    return row[index];
  }

  static String _toStr(dynamic val) {
    if (val == null) return '';

    if (val is double) {
      if (val % 1 == 0) {
        return val.toInt().toString();
      }
      final strVal = val.toString().trim();
      return strVal.endsWith('.0')
          ? strVal.substring(0, strVal.length - 2)
          : strVal;
    }

    if (val is int) {
      return val.toString();
    }

    if (val is DateTime) {
      if (val.year == 1899 || val.year == 1900) {
        if (val.minute == 0 && val.second == 0) {
          return val.hour.toString();
        }
        return '0';
      }
      return '${val.day.toString().padLeft(2, '0')}.${val.month.toString().padLeft(2, '0')}.${val.year}';
    }

    final rawStr = val.toString().trim();
    if (rawStr.isEmpty) return '';

    // Handle Excel time formatting quirks (e.g. 00:00:00 -> "0", 01:00:00 -> "1")
    final timeMatch = RegExp(r'^0*(\d{1,3}):00:00$').firstMatch(rawStr);
    if (timeMatch != null) {
      final hourStr = timeMatch.group(1)!;
      return hourStr.isEmpty ? '0' : hourStr;
    }
    if (rawStr == '00:00' || rawStr == '00:00:00') {
      return '0';
    }

    // Strip trailing decimal zeroes from numeric strings (e.g. "1.0" -> "1")
    if (RegExp(r'^\d+\.0+$').hasMatch(rawStr)) {
      return rawStr.split('.').first;
    }

    return rawStr;
  }

  static int _toInt(dynamic val, {int defaultValue = 0}) {
    if (val == null) return defaultValue;
    if (val is int) return val;
    if (val is double) return val.toInt();
    final parsed = int.tryParse(val.toString().trim());
    return parsed ?? defaultValue;
  }

  static int _toErrorQty(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    final str = val.toString().trim().toLowerCase();
    if (str == 'x' || str == 'j' || str == 'ja' || str == 'true') return 1;
    final parsed = int.tryParse(str);
    return parsed ?? 0;
  }

  static bool _toBool(dynamic val) {
    if (val == null) return false;
    if (val is bool) return val;
    final str = val.toString().trim().toLowerCase();
    if (str.isEmpty) return false;
    if (str == 'x' || str == 'j' || str == 'ja' || str == 'true') return true;
    final numVal = double.tryParse(str);
    if (numVal != null) {
      return numVal > 0;
    }
    return false;
  }

  static String _toEscapeDoorControl(dynamic val) {
    if (val == null) return 'Nein';
    final str = _toStr(val).trim();
    if (str.isEmpty ||
        str == '0' ||
        str.toLowerCase() == 'false' ||
        str.toLowerCase() == 'nein') {
      return 'Nein';
    }
    if (str == '1' ||
        str.toLowerCase() == 'true' ||
        str.toLowerCase() == 'ja' ||
        str == 'X' ||
        str == 'x') {
      return 'Ja ?';
    }
    return str;
  }

  /// Sanitizes door numbers by stripping unknown noise characters (commas, question marks, isolated dashes).
  /// Preserves valid alphanumeric formats like "21.A", "2202.5", "EG.01", "T-01".
  @visibleForTesting
  static String sanitizeDoorNumberForTest(String raw) =>
      _sanitizeDoorNumber(raw);

  static String _sanitizeDoorNumber(String raw,
      {int pos = 0, int rowIndex = 0}) {
    if (raw.isEmpty || _isSummaryOrFooterText(raw)) {
      return pos > 0 ? pos.toString() : 'TÜR-$rowIndex';
    }

    String cleaned = raw.trim();

    // Convert decimal commas to dots (e.g. "2202,5" -> "2202.5")
    cleaned = cleaned.replaceAll(',', '.');

    // Remove unwanted special characters, keeping alphanumeric, German umlauts, dots, and hyphens
    cleaned = cleaned.replaceAll(RegExp(r'[^\w\.\-äöüÄÖÜß]'), '');

    // Strip leading or trailing isolated dots or hyphens (e.g. "21-" -> "21", ".21" -> "21")
    cleaned = cleaned.replaceAll(RegExp(r'^[\.\-]+|[\.\-]+$'), '');

    if (cleaned.isEmpty || cleaned == '?') {
      return pos > 0 ? pos.toString() : 'TÜR-$rowIndex';
    }

    return cleaned;
  }

  /// Formats raw notes from Excel for clean readability.
  /// Normalizes line endings (\r\n -> \n), trims line whitespace, cleans redundant internal spaces,
  /// and removes duplicate empty lines.
  @visibleForTesting
  static String formatNotesForTest(String raw) => _formatNotes(raw);

  static String _formatNotes(String raw) {
    if (raw.trim().isEmpty) return '';
    String text = raw
        .replaceAll(RegExp(r'_x000[dD]_?'), '\n')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = text.split('\n');
    final cleaned = <String>[];
    bool previousEmpty = false;

    for (var line in lines) {
      final trimmedLine = line.trim().replaceAll(RegExp(r'[ \t]+'), ' ');
      if (trimmedLine.isEmpty) {
        if (!previousEmpty && cleaned.isNotEmpty) {
          cleaned.add('');
          previousEmpty = true;
        }
      } else {
        cleaned.add(trimmedLine);
        previousEmpty = false;
      }
    }

    while (cleaned.isNotEmpty && cleaned.last.isEmpty) {
      cleaned.removeLast();
    }

    return cleaned.join('\n');
  }

  static String _cleanCatalogDesc(String text) {
    return text
        .replaceFirst(
            RegExp(r'^(Hinweis|Mangel):\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^[xX]\s+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  static String _determineWindowDefectCategory(String description) {
    final d = description.toLowerCase();
    if (d.contains('dichtung')) return 'Dichtungen';
    if (d.contains('schließblech') || d.contains('scließblech')) {
      return 'Schließbleche';
    }
    if (d.contains('raffstore') ||
        d.contains('jalousie') ||
        d.contains('leiterkordel') ||
        d.contains('texband')) {
      return 'Sonnenschutz & Raffstore';
    }
    if (d.contains('scheibe') || d.contains('glas') || d.contains('verglasung')) {
      return 'Verglasung';
    }
    if (d.contains('griff') || d.contains('oliven')) {
      return 'Fenstergriffe & Bedienung';
    }
    if (d.contains('lager') ||
        d.contains('schere') ||
        d.contains('schnapper') ||
        d.contains('begrenzer') ||
        d.contains('beschlag')) {
      return 'Fensterbeschläge & Mechanik';
    }
    if (d.contains('hinweis') || d.contains('anmerkung')) {
      return 'Hinweise und Anmerkungen';
    }
    return 'Fenster Mängelerfassung';
  }

  static List<ErrorCatalog> _extractErrorsFromNotes(
      String notes, List<ErrorCatalog> catalogList) {
    if (notes.trim().isEmpty) return [];
    final List<ErrorCatalog> matchedErrors = [];
    final lowerNotes = notes.toLowerCase();

    for (final cat in catalogList) {
      if (cat.assetType.toLowerCase() != 'window') continue;
      final desc = cat.description.toLowerCase().trim();
      if (desc.isEmpty) continue;

      bool isMatch = false;
      if (lowerNotes.contains(desc)) {
        isMatch = true;
      } else if (desc.contains('entwässerung') && lowerNotes.contains('entwässerung')) {
        isMatch = true;
      } else if (desc.contains('525099') && lowerNotes.contains('525099')) {
        isMatch = true;
      } else if (desc.contains('mitteldichtung') && desc.contains('blendrahmen') &&
          lowerNotes.contains('mitteldichtung') && lowerNotes.contains('blendrahmen')) {
        isMatch = true;
      } else if (desc.contains('mitteldichtung') && desc.contains('flügel') &&
          lowerNotes.contains('mitteldichtung') && lowerNotes.contains('flügel')) {
        isMatch = true;
      } else if (desc.contains('ecklager') && lowerNotes.contains('ecklager')) {
        isMatch = true;
      } else if (desc.contains('schere') && lowerNotes.contains('schere')) {
        isMatch = true;
      } else if (desc.contains('schnapper') && lowerNotes.contains('schnapper')) {
        isMatch = true;
      } else if (desc.contains('öffnungsbegrenzer') && lowerNotes.contains('öffnungsbegrenzer')) {
        isMatch = true;
      } else if (desc.contains('kipp') && desc.contains('schließblech') &&
          lowerNotes.contains('kipp') && lowerNotes.contains('schließblech')) {
        isMatch = true;
      } else if (desc.contains('rc2') && lowerNotes.contains('rc2')) {
        isMatch = true;
      } else if (desc.contains('texband') && lowerNotes.contains('texband')) {
        isMatch = true;
      } else if (desc.contains('scheibe') && lowerNotes.contains('scheibe') && lowerNotes.contains('gerissen')) {
        isMatch = true;
      } else if (desc.contains('leiterkordel') && lowerNotes.contains('leiterkordel')) {
        isMatch = true;
      } else if ((desc.contains('raffstore fährt nicht') || desc.contains('jalousie defekt')) &&
          (lowerNotes.contains('raffstore fährt nicht') || lowerNotes.contains('jalousie defekt'))) {
        isMatch = true;
      }

      if (isMatch) {
        if (!matchedErrors.any((m) => m.errorId == cat.errorId || m.code == cat.code)) {
          matchedErrors.add(cat);
        }
      }
    }
    return matchedErrors;
  }

  static Future<ExcelImportResult> _importWindowsFromFile({
    required SpreadsheetDecoder decoder,
    required String fileName,
    required String projectNumber,
    required List<String> logs,
    required List<String> warnings,
  }) async {
    await WindowOptionsService.ensureLoaded();
    await DatabaseService.checkAndInitializeCatalog();
    await DatabaseService.checkAndInitializeWindowCatalog();

    // Strictly extract job number (Auftragsnummer) from file name
    final jobMatch = RegExp(r'\b(\d{2}-\d{4,5}(?:-[A-Za-z0-9]+)?)\b').firstMatch(fileName);
    final String fileNameJobNumber = jobMatch != null ? jobMatch.group(1)! : '';

    final List<String> newCatalogProposals = [];

    // ── STEP 1: Process "Fehlerliste Codes" sheet if present ──
    for (final sName in decoder.tables.keys) {
      final sLower = sName.trim().toLowerCase();
      if (sLower.contains('fehlerliste') ||
          sLower.contains('fehler code') ||
          sLower == 'codes') {
        logs.add('Lese Fehlerkatalog-Arbeitsblatt "$sName"...');
        final cSheet = decoder.tables[sName]!;
        String currentCategory = 'Fenster Mängelerfassung';

        final existingWindowCatalog =
            await DatabaseService.getAllErrorCatalog(assetType: 'window');
        final existingCodes = existingWindowCatalog
            .map((e) => e.code.trim().toLowerCase())
            .toSet();
        final existingDescriptions = existingWindowCatalog
            .map((e) => e.description.trim().toLowerCase())
            .toSet();

        for (int r = 0; r < cSheet.maxRows; r++) {
          final row = cSheet.rows[r];
          if (row.isEmpty) continue;
          final cellText = _toStr(_cell(row, 0)).trim();
          if (cellText.isEmpty) continue;

          // Header switch for Wood windows: e.g. "Holzfenster"
          if (cellText.toLowerCase() == 'holzfenster' ||
              cellText.toLowerCase().startsWith('holzfenster')) {
            currentCategory = 'Holzfenster';
            continue;
          }

          // Parse line: e.g. "9.1-Öffnungssperre...", "9.3-x Drehkippschere...", "20.1-Hinweis:..."
          String code = '';
          String desc = cellText;

          final codeMatch = RegExp(r'^(\d+\.\d+)(?:-x|-|\s+)?\s*(.*)$')
              .firstMatch(cellText);
          if (codeMatch != null) {
            code = codeMatch.group(1)!.trim();
            desc = codeMatch.group(2)!.trim();
          } else if (cellText.contains('-')) {
            final parts = cellText.split('-');
            code = parts.first.trim();
            desc = parts.sublist(1).join('-').trim();
            if (desc.toLowerCase().startsWith('x ')) {
              desc = desc.substring(2).trim();
            }
          }

          if (desc.isEmpty) desc = cellText;
          if (code.isEmpty) code = 'WIN_FL_${r + 1}';

          final isAlreadyPresent = existingCodes.contains(code.toLowerCase()) ||
              existingDescriptions.contains(desc.toLowerCase());

          if (!isAlreadyPresent) {
            final newError = ErrorCatalog(
              code: code,
              description: desc,
              category: currentCategory,
              severity: 'medium',
              recommendation: 'Prüfen / Instandsetzen',
              assetType: 'window',
              status: 'Approved',
            );
            await DatabaseService.insertErrorCatalog(newError);
            try {
              await LocalDatabaseService.insertErrorCatalog(newError);
            } catch (_) {}
            existingCodes.add(code.toLowerCase());
            existingDescriptions.add(desc.toLowerCase());
            newCatalogProposals.add('$code: $desc ($currentCategory)');
            logs.add(
                'Neuer Fenster-Fehlercode aus "$sName" hinzugefügt: $code - $desc');
          }
        }
      }
    }

    // ── STEP 2: Find all Window Inspection sheets (Multi-year, "YYYY" or "Tabelle...") ──
    final List<Map<String, dynamic>> windowSheetsToProcess = [];

    for (final sName in decoder.tables.keys) {
      final sLower = sName.trim().toLowerCase();
      // Skip catalog / empty / irrelevant sheets
      if (sLower.contains('fehler') ||
          sLower.contains('code') ||
          sLower == 'tabelle3') {
        continue;
      }

      final table = decoder.tables[sName]!;
      if (table.maxRows < 2) continue;

      int foundHeaderRow = -1;
      for (int r = 0; r < table.maxRows && r < 5; r++) {
        final row = table.rows[r];
        for (final cell in row) {
          final str = cell?.toString().trim().toLowerCase() ?? '';
          if (str == 'fenster nr.' ||
              str == 'fenster nr' ||
              str == 'fensternummer' ||
              str == 'flügelabmaße' ||
              str == 'fenstertyp' ||
              str == 'beschläge') {
            foundHeaderRow = r;
            break;
          }
        }
        if (foundHeaderRow >= 0) break;
      }

      final isYearSheet = RegExp(r'^(19|20)\d{2}$').hasMatch(sName.trim());
      final isTableSheet =
          sLower.startsWith('tabelle') || sLower.startsWith('fenster');

      if (foundHeaderRow == -1 && (isYearSheet || isTableSheet) && table.maxRows >= 2) {
        if (table.rows.length > 1 &&
            table.rows[1]
                    .where((c) => c != null && c.toString().trim().isNotEmpty)
                    .length >=
                4) {
          foundHeaderRow = 1;
        }
      }

      if (foundHeaderRow == -1) {
        logs.add(
            'Arbeitsblatt "$sName" übersprungen (keine Fenster-Spalten gefunden).');
        continue;
      }

      // Parse metadata from header area / row 0 (and row 1)
      String sClient = '';
      String sObject = _extractObjectAddressFromWindowSheet(table);
      String sJobNum = fileNameJobNumber; // Strictly from file name, not within the Excel file
      String sDateStr = '';

      if (table.maxRows > 0) {
        final r0 = table.rows[0];
        for (int i = 0; i < r0.length; i++) {
          final cellStr = _toStr(_cell(r0, i)).trim();
          if (cellStr.isEmpty) continue;
          final cellLower = cellStr.toLowerCase();

          if (cellLower.startsWith('kunde:')) {
            final rem = cellStr.substring(6).trim();
            if (rem.isNotEmpty) {
              sClient = rem;
            } else if (i + 1 < r0.length &&
                _toStr(_cell(r0, i + 1)).trim().isNotEmpty) {
              sClient = _toStr(_cell(r0, i + 1)).trim();
            } else if (i + 2 < r0.length &&
                _toStr(_cell(r0, i + 2)).trim().isNotEmpty) {
              sClient = _toStr(_cell(r0, i + 2)).trim();
            }
          } else if (sObject.isEmpty &&
              (cellLower.startsWith('objekt:') ||
                  cellLower.startsWith('objeckt:'))) {
            final rem = cellStr
                .replaceFirst(
                    RegExp(r'^objec?kt:?\s*', caseSensitive: false), '')
                .trim();
            if (rem.isNotEmpty) {
              sObject = rem;
            } else if (i + 1 < r0.length &&
                _toStr(_cell(r0, i + 1)).trim().isNotEmpty) {
              sObject = _toStr(_cell(r0, i + 1)).trim();
            } else if (i + 2 < r0.length &&
                _toStr(_cell(r0, i + 2)).trim().isNotEmpty) {
              sObject = _toStr(_cell(r0, i + 2)).trim();
            }
          } else if (cellLower.startsWith('datum:')) {
            sDateStr = cellStr.substring(6).trim();
          }
        }
      }

      // Determine year and date
      DateTime sheetDate;
      int? sheetYear;

      final yearMatch = RegExp(r'(19|20)\d{2}').firstMatch(sName);
      if (yearMatch != null) {
        sheetYear = int.tryParse(yearMatch.group(0)!);
      }

      if (sDateStr.isNotEmpty) {
        final dMatch =
            RegExp(r'(\d{2})\.(\d{2})\.(\d{4})').firstMatch(sDateStr);
        if (dMatch != null) {
          final y = int.parse(dMatch.group(3)!);
          final m = int.parse(dMatch.group(2)!);
          final d = int.parse(dMatch.group(1)!);
          sheetDate = DateTime(sheetYear ?? y, m, d);
          sDateStr =
              '${sheetDate.year}-${sheetDate.month.toString().padLeft(2, '0')}-${sheetDate.day.toString().padLeft(2, '0')}';
        } else {
          sheetDate = DateTime.tryParse(sDateStr) ??
              DateTime(sheetYear ?? 2024, 1, 1);
        }
      } else if (sheetYear != null) {
        final fileDateMatch =
            RegExp(r'(\d{2})\.(\d{2})\.(\d{4})').firstMatch(fileName);
        if (fileDateMatch != null) {
          final m = int.parse(fileDateMatch.group(2)!);
          final d = int.parse(fileDateMatch.group(1)!);
          sheetDate = DateTime(sheetYear, m, d);
        } else {
          sheetDate = DateTime(sheetYear, 1, 1);
        }
        sDateStr =
            '${sheetDate.year}-${sheetDate.month.toString().padLeft(2, '0')}-${sheetDate.day.toString().padLeft(2, '0')}';
      } else {
        sheetDate = DateTime.now();
        sDateStr = sheetDate.toIso8601String().substring(0, 10);
      }

      windowSheetsToProcess.add({
        'sheetName': sName,
        'sheet': table,
        'headerRowIndex': foundHeaderRow,
        'date': sheetDate,
        'dateStr': sDateStr,
        'clientName': sClient,
        'objectAddress': sObject,
        'jobNumber': sJobNum,
      });
    }

    if (windowSheetsToProcess.isEmpty) {
      final warn =
          'Keine gültigen Fenster-Arbeitsblätter in "$fileName" gefunden.';
      warnings.add(warn);
      logs.add('WARNUNG: $warn');
      return ExcelImportResult(
        sheetsProcessed: 0,
        doorsImported: 0,
        windowsImported: 0,
        errorsLinked: 0,
        assetType: 'window',
        warnings: warnings,
        logs: logs,
        newCatalogProposals: newCatalogProposals,
      );
    }

    // Sort sheets newest-first
    windowSheetsToProcess.sort((a, b) {
      final DateTime dateA = a['date'] as DateTime;
      final DateTime dateB = b['date'] as DateTime;
      return dateB.compareTo(dateA);
    });

    logs.add(
        'Gefundene Fenster-Arbeitsblätter (${windowSheetsToProcess.length}): '
        '${windowSheetsToProcess.map((s) => "${s['sheetName']} (${s['dateStr']})").join(", ")}');

    String effectiveProj = projectNumber;
    if (effectiveProj.isEmpty) {
      final projMatch =
          RegExp(r'(P-\d+)', caseSensitive: false).firstMatch(fileName);
      if (projMatch != null) {
        effectiveProj = projMatch.group(1)!.toUpperCase();
      }
    }
    if (effectiveProj.isEmpty) effectiveProj = 'P-000000';

    int totalErrorsLinked = 0;
    final Set<String> distinctWindowAliases = {};
    final List<DoorChangeItem> allWindowChanges = [];

    // Fallbacks from filename if not in row 0
    String fallbackClient = '';
    String fallbackJobNum = fileNameJobNumber;

    // ── Resolve Canonical Object Address for this Project/File ──────────
    final String fileNameAddress = _extractAddressFromFileName(fileName);
    String canonicalObjectAddress = '';

    // Check if filename contains a valid street address
    if (_hasStreetOrNumber(fileNameAddress)) {
      canonicalObjectAddress = fileNameAddress;
    }

    // Check sheets (newest sheet first)
    for (final ws in windowSheetsToProcess) {
      final rawAddr = (ws['objectAddress'] ?? '').toString().trim();
      if (_hasStreetOrNumber(rawAddr)) {
        if (canonicalObjectAddress.isEmpty ||
            rawAddr.length > canonicalObjectAddress.length) {
          canonicalObjectAddress = rawAddr;
        }
      }
    }

    // If still empty, use sheet's objectAddress if non-empty, otherwise fileNameAddress
    if (canonicalObjectAddress.isEmpty) {
      for (final ws in windowSheetsToProcess) {
        final rawAddr = (ws['objectAddress'] ?? '').toString().trim();
        if (rawAddr.isNotEmpty) {
          canonicalObjectAddress = rawAddr;
          break;
        }
      }
      if (canonicalObjectAddress.isEmpty) {
        canonicalObjectAddress = fileNameAddress;
      }
    }

    if (canonicalObjectAddress.isNotEmpty) {
      logs.add(
          'Liegenschaftsadresse für ${projectNumber.isNotEmpty ? "Projekt $projectNumber" : fileName} festgelegt als: "$canonicalObjectAddress"');
    } else {
      final warn =
          'WARNUNG: Keine Objektadresse in Dateiname oder Kopfzeile (Zeile 1, Spalten E/F/G) für "$fileName" gefunden.';
      warnings.add(warn);
      logs.add(warn);
    }

    for (int sheetIndex = 0;
        sheetIndex < windowSheetsToProcess.length;
        sheetIndex++) {
      final sInfo = windowSheetsToProcess[sheetIndex];
      final String sName = sInfo['sheetName'] as String;
      final table = sInfo['sheet'] as SpreadsheetTable;
      final int headerRowIndex = sInfo['headerRowIndex'] as int;
      final String dateStr = sInfo['dateStr'] as String;

      String clientName = sInfo['clientName'] as String;
      String objectAddress = sInfo['objectAddress'] as String;
      if (canonicalObjectAddress.isNotEmpty) {
        if (objectAddress.isEmpty || !_hasStreetOrNumber(objectAddress)) {
          objectAddress = canonicalObjectAddress;
        }
      }
      String jobNumber = sInfo['jobNumber'] as String;

      if (jobNumber.isEmpty) jobNumber = fallbackJobNum;
      if (clientName.isEmpty && fallbackClient.isNotEmpty) {
        clientName = fallbackClient;
      }
      final normalizedClient = CustomerNormalizer.getCanonicalName(clientName);
      final effectiveClient = normalizedClient.isNotEmpty
          ? normalizedClient
          : (clientName.isNotEmpty ? clientName : 'Sprinkenhof');

      if (sheetIndex == 0) {
        fallbackClient = effectiveClient;
        if (jobNumber.isNotEmpty) fallbackJobNum = jobNumber;
      }

      logs.add(
          'Verarbeite Fenster-Arbeitsblatt "$sName" (Jahr/Datum: $dateStr, Kopfzeile: Index $headerRowIndex): '
          'Kunde="$effectiveClient", Objekt="$objectAddress", Auftrag="$jobNumber"');

      // Create Inspection for this year/sheet
      final inspectionData = {
        'clientName': effectiveClient,
        'objectAddress': objectAddress,
        'date': dateStr,
        'jobNumber': jobNumber,
        'projectNumber': effectiveProj,
        'orderType': 'Wartung',
        'assetType': 'window',
      };

      final inspectionId =
          await DatabaseService.insertInspection(inspectionData);
      logs.add(
          'Inspektion angelegt mit ID: $inspectionId für Blatt "$sName" ($dateStr)');

      // 3. Map Header Row Columns
      final headerRow = table.rows[headerRowIndex];
      int colWinNum = 0;
      int colFloor = 1;
      int colRoomNum = 2;
      int colRoomDesig = 3;
      int colWinType = 4;
      int colMat = 5;
      int colDimensions = 6;
      int colFittings = 7;
      int colWinOK = -1;
      int colWinNotOK = -1;
      int colRaffstore = -1;
      int colJalousie = -1;
      int colNotes = -1;

      bool isDefectText(String text) {
        final t = text.toLowerCase();
        return t.contains('defekt') ||
            t.contains('fährt') ||
            t.contains('strom') ||
            t.contains('fehlt') ||
            t.contains('schaden') ||
            t.contains('beschädigt') ||
            t.contains('kaputt') ||
            t.contains('gerissen') ||
            t.contains('gebrochen') ||
            t.contains('schere') ||
            t.contains('schnapper') ||
            t.contains('kordel') ||
            t.contains('dichtung') ||
            t.contains('schließblech') ||
            t.contains('scließblech');
      }

      for (int c = 0; c < headerRow.length; c++) {
        final h = _toStr(_cell(headerRow, c)).trim().toLowerCase();
        if (h.contains('fenster nr') || h.contains('fensternummer')) {
          colWinNum = c;
        }
        if (h.contains('etage')) colFloor = c;
        if (h.contains('raum nr')) colRoomNum = c;
        if (h.contains('sonstiges')) colRoomDesig = c;
        if (h.contains('fenstertyp')) colWinType = c;
        if (h.contains('material')) colMat = c;
        if (h.contains('flügelabmaße') || h.contains('abmaße')) {
          colDimensions = c;
        }
        if (h.contains('beschläge')) colFittings = c;
        if (h.contains('fenster in ordnung') ||
            h == 'fenster i.o.' ||
            h == 'fenster ok') {
          colWinOK = c;
        }
        if (h.contains('fenster nicht in ordnung')) colWinNotOK = c;
        if ((h.contains('raffstore in ordnung') ||
                h.contains('raffstore i.o.') ||
                h.contains('raffstore ok') ||
                h == 'raffstore') &&
            !isDefectText(h)) {
          colRaffstore = c;
        }
        if ((h.contains('jalousie in ordnung') ||
                h.contains('jalousie i.o.') ||
                h.contains('jalousie ok') ||
                h == 'jalousie') &&
            !isDefectText(h)) {
          colJalousie = c;
        }
        if (h.contains('anmerkung') ||
            h.contains('beschreibung der mängel') ||
            h.contains('beschreibung') ||
            h.contains('bemerkung') ||
            h.contains('notiz')) {
          colNotes = c;
        }
      }

      // Check row above header (e.g. row 0) for "anmerkung" if colNotes not found in headerRow
      if (colNotes == -1 && headerRowIndex > 0) {
        final rAbove = table.rows[headerRowIndex - 1];
        for (int c = 0; c < rAbove.length; c++) {
          final cellAbove = _toStr(_cell(rAbove, c)).trim().toLowerCase();
          if (cellAbove.contains('anmerkung') ||
              cellAbove.contains('beschreibung') ||
              cellAbove.contains('bemerkung') ||
              cellAbove.contains('notiz')) {
            colNotes = c;
            break;
          }
        }
      }
      if (colNotes == -1) {
        colNotes = headerRow.length;
      }

      // Determine where defect columns start:
      // After the condition / shading columns ("Fenster in Ordnung", "Fenster nicht in Ordnung", "Raffstore in Ordnung", "Jalousie in Ordnung")
      int colDefectsStart = [colWinOK, colWinNotOK, colRaffstore, colJalousie]
          .where((c) => c >= 0)
          .fold<int>(-1, (prev, elem) => elem > prev ? elem : prev);

      if (colDefectsStart == -1) {
        colDefectsStart = [
          colWinNum,
          colFloor,
          colRoomNum,
          colRoomDesig,
          colWinType,
          colMat,
          colDimensions,
          colFittings
        ].where((c) => c >= 0).fold<int>(-1, (prev, elem) => elem > prev ? elem : prev);
      }
      colDefectsStart += 1;

      // Map defect columns: between colDefectsStart and colNotes
      final Map<int, ErrorCatalog> defectColumnMap = {};
      final catalogList =
          await DatabaseService.getAllErrorCatalog(assetType: 'window');

      for (int c = colDefectsStart; c < colNotes && c < headerRow.length; c++) {
        String headerText = _toStr(_cell(headerRow, c)).trim();
        if (headerText.isEmpty && headerRowIndex > 0) {
          headerText = _toStr(_cell(table.rows[headerRowIndex - 1], c)).trim();
        }
        if (headerText.isEmpty) continue;

        // Check if row above contains a designated error code (e.g. 1, 2, ..., 15)
        String colCode = '';
        if (headerRowIndex > 0 && c < table.rows[headerRowIndex - 1].length) {
          final rawCode =
              _toStr(_cell(table.rows[headerRowIndex - 1], c)).trim();
          if (rawCode.isNotEmpty &&
              !rawCode.toLowerCase().contains('anmerkung') &&
              !rawCode.toLowerCase().contains('beschreibung')) {
            colCode = rawCode;
          }
        }

        ErrorCatalog? match;
        // 1. Try matching by exact or clean description first
        for (final cat in catalogList) {
          if (cat.description.trim().toLowerCase() ==
              headerText.toLowerCase()) {
            match = cat;
            break;
          }
        }

        // 2. Only if NOT matched by description, check if colCode is a structured error code (e.g. "9.1", "WIN_...", NOT a plain integer like "1", "2")
        if (match == null &&
            colCode.isNotEmpty &&
            !RegExp(r'^\d+$').hasMatch(colCode)) {
          for (final cat in catalogList) {
            if (cat.code.trim().toLowerCase() == colCode.toLowerCase() &&
                cat.assetType.toLowerCase() == 'window') {
              match = cat;
              break;
            }
          }
        }

        if (match == null) {
          String codeToUse = '';
          if (colCode.isNotEmpty && !RegExp(r'^\d+$').hasMatch(colCode)) {
            codeToUse = colCode;
          }

          if (codeToUse.isEmpty) {
            // Check if plain integer colCode can be used without collision
            if (colCode.isNotEmpty && RegExp(r'^\d+$').hasMatch(colCode)) {
              final exists = catalogList.any((cat) =>
                  cat.code.trim().toLowerCase() == colCode.toLowerCase());
              if (!exists) {
                codeToUse = colCode;
              }
            }
            if (codeToUse.isEmpty) {
              codeToUse = 'WIN_COL_$c';
              int suffix = 1;
              while (catalogList.any((cat) =>
                  cat.code.trim().toLowerCase() == codeToUse.toLowerCase())) {
                codeToUse = 'WIN_COL_${c}_$suffix';
                suffix++;
              }
            }
          } else {
            final codeCollision = catalogList.any((cat) =>
                cat.code.trim().toLowerCase() == codeToUse.toLowerCase());
            if (codeCollision) {
              codeToUse = 'W-$codeToUse';
            }
          }

          final category = _determineWindowDefectCategory(headerText);
          final newEntry = ErrorCatalog(
            code: codeToUse,
            description: headerText,
            category: category,
            severity: 'medium',
            recommendation: 'Prüfen / Instandsetzen',
            assetType: 'window',
            status: 'Approved',
          );
          final insertedId =
              await DatabaseService.insertErrorCatalog(newEntry);
          try {
            await LocalDatabaseService.insertErrorCatalog(newEntry);
          } catch (_) {}
          match =
              newEntry.copyWith(errorId: insertedId > 0 ? insertedId : null);
          catalogList.add(match);
          newCatalogProposals.add('$codeToUse: $headerText ($category)');
          logs.add(
              'Neuer Fenster-Katalogfehler aus Spalte $c angelegt: $codeToUse - $headerText ($category)');
        }

        defectColumnMap[c] = match;
      }

      logs.add(
          'Blatt "$sName": ${defectColumnMap.length} Mängelspalten erkannt (Spalten $colDefectsStart bis ${colNotes - 1}).');

      // 4. Parse Window Rows for this sheet
      int sheetWindowsCount = 0;
      int sheetErrorsCount = 0;

      for (int r = headerRowIndex + 1; r < table.maxRows; r++) {
        final row = table.rows[r];
        if (row.isEmpty) continue;

        final winNum = _toStr(_cell(row, colWinNum)).trim();
        if (winNum.isEmpty) continue;

        final fittingsVal = (colFittings >= 0 && colFittings < row.length
                ? _toStr(_cell(row, colFittings))
                : '')
            .trim();
        if (winNum.toLowerCase().startsWith('summe') ||
            fittingsVal.toLowerCase().startsWith('summe')) {
          logs.add(
              'Blatt "$sName": Summenzeile bei Zeile ${r + 1} erreicht. Beende Zeilen-Import.');
          break;
        }

        final floor = (colFloor >= 0 && colFloor < row.length
                ? _toStr(_cell(row, colFloor))
                : '')
            .trim();
        final roomNum = (colRoomNum >= 0 && colRoomNum < row.length
                ? _toStr(_cell(row, colRoomNum))
                : '')
            .trim();
        final roomDesig = (colRoomDesig >= 0 && colRoomDesig < row.length
                ? _toStr(_cell(row, colRoomDesig))
                : '')
            .trim();
        final winType = (colWinType >= 0 && colWinType < row.length
                ? _toStr(_cell(row, colWinType))
                : '')
            .trim();
        final material = (colMat >= 0 && colMat < row.length
                ? _toStr(_cell(row, colMat))
                : '')
            .trim();
        final dimensions = (colDimensions >= 0 && colDimensions < row.length
                ? _toStr(_cell(row, colDimensions))
                : '')
            .trim();
        final fittings = (colFittings >= 0 && colFittings < row.length
                ? _toStr(_cell(row, colFittings))
                : '')
            .trim();

        // Evaluate window function OK
        bool windowFunctionOK = true;
        if (colWinOK >= 0 && colWinOK < row.length) {
          final winOKStr = _toStr(_cell(row, colWinOK)).trim().toLowerCase();
          if (winOKStr == 'n' ||
              winOKStr == 'nein' ||
              winOKStr == '0' ||
              winOKStr == 'false') {
            windowFunctionOK = false;
          }
        }
        if (colWinNotOK >= 0 && colWinNotOK < row.length) {
          final winNotOKStr =
              _toStr(_cell(row, colWinNotOK)).trim().toLowerCase();
          if (winNotOKStr == 'j' ||
              winNotOKStr == 'ja' ||
              winNotOKStr == '1' ||
              winNotOKStr == 'x' ||
              winNotOKStr == 'true') {
            windowFunctionOK = false;
          }
        }

        // Evaluate Raffstore / Jalousie
        bool hasRaffstore = false;
        bool? raffstoreOK;

        String raffStr = '';
        if (colRaffstore >= 0 && colRaffstore < row.length) {
          raffStr = _toStr(_cell(row, colRaffstore)).trim().toLowerCase();
        } else if (colJalousie >= 0 && colJalousie < row.length) {
          raffStr = _toStr(_cell(row, colJalousie)).trim().toLowerCase();
        }

        if (raffStr.isNotEmpty &&
            raffStr != '-' &&
            raffStr != '/' &&
            raffStr != 'nein' &&
            raffStr != 'nicht vorhanden' &&
            raffStr != 'kein raffstore' &&
            raffStr != 'keine' &&
            raffStr != 'kein') {
          if (raffStr == 'x' ||
              raffStr == 'j' ||
              raffStr == 'ja' ||
              raffStr == '1' ||
              raffStr == 'ok' ||
              raffStr == 'i.o.' ||
              raffStr == '√' ||
              raffStr == 'true' ||
              raffStr == 'in ordnung') {
            hasRaffstore = true;
            raffstoreOK = true;
          } else if (raffStr == 'n' ||
              raffStr == '0' ||
              raffStr == 'false' ||
              raffStr == 'defekt' ||
              raffStr == 'nicht in ordnung' ||
              raffStr == 'schaden') {
            hasRaffstore = true;
            raffstoreOK = false;
          } else {
            hasRaffstore = true;
            raffstoreOK = true;
          }
        } else {
          // If there is no value in this parameter (or explicitly 'nein'/'nicht vorhanden'), set as "nicht vorhanden"
          hasRaffstore = false;
          raffstoreOK = null;
        }

        final notes = (colNotes >= 0 && colNotes < row.length
                ? _toStr(_cell(row, colNotes))
                : '')
            .trim();

        // Check defect marks
        bool hasDefect = false;
        int rowErrorCount = 0;
        final List<MapEntry<ErrorCatalog, int>> rowErrors = [];

        for (final colIdx in defectColumnMap.keys) {
          if (colIdx < row.length) {
            final val = _toStr(_cell(row, colIdx)).trim();
            final qty = int.tryParse(val) ??
                ((val.toLowerCase() == 'x' ||
                        val == '1' ||
                        val == '√' ||
                        val.toLowerCase() == 'ja')
                    ? 1
                    : 0);
            if (qty > 0) {
              hasDefect = true;
              rowErrorCount += qty;
              rowErrors.add(MapEntry(defectColumnMap[colIdx]!, qty));
              if (defectColumnMap[colIdx]!
                      .description
                      .toLowerCase()
                      .contains('raffstore') ||
                  defectColumnMap[colIdx]!
                      .category
                      .toLowerCase()
                      .contains('raffstore')) {
                hasRaffstore = true;
                raffstoreOK = false;
              }
            }
          }
        }

        // If sheet has no separate defect columns (e.g. 2022, 2021, 2019), check notes for recorded defects
        if (defectColumnMap.isEmpty && notes.isNotEmpty) {
          final noteErrors = _extractErrorsFromNotes(notes, catalogList);
          for (final ne in noteErrors) {
            hasDefect = true;
            rowErrorCount += 1;
            rowErrors.add(MapEntry(ne, 1));
            if (ne.description.toLowerCase().contains('raffstore') ||
                ne.category.toLowerCase().contains('raffstore')) {
              hasRaffstore = true;
              raffstoreOK = false;
            }
          }
        }

        if (notes.toLowerCase().contains('kein raffstore')) {
          hasRaffstore = false;
          raffstoreOK = null;
        }

        final effectiveWinNum = (floor.isNotEmpty &&
                !winNum.contains('-') &&
                !winNum.contains('.'))
            ? '${floor.replaceAll(' ', '')}-$winNum'
            : winNum;

        final alias = Window.generateAlias(
          projectNumber: effectiveProj,
          windowNumber: effectiveWinNum,
        );

        if (floor.isNotEmpty) WindowOptionsService.addOption('floor', floor);
        if (roomNum.isNotEmpty) {
          WindowOptionsService.addOption('roomNumber', roomNum);
        }
        if (roomDesig.isNotEmpty) {
          WindowOptionsService.addOption('roomDesignation', roomDesig);
        }
        if (winType.isNotEmpty) {
          WindowOptionsService.addOption('windowType', winType);
        }
        if (material.isNotEmpty) {
          WindowOptionsService.addOption('material', material);
        }
        if (dimensions.isNotEmpty) {
          WindowOptionsService.addOption('wingDimensions', dimensions);
        }
        if (fittings.isNotEmpty) {
          WindowOptionsService.addOption('fittings', fittings);
        }

        final existingWindow = await DatabaseService.findWindowByBarcode(alias);
        int windowId;
        if (existingWindow != null && existingWindow.id != null) {
          windowId = existingWindow.id!;
          // If this is the newest sheet, update latest master properties
          if (sheetIndex == 0) {
            final updated = existingWindow.copyWith(
              floor: floor.isNotEmpty ? floor : existingWindow.floor,
              roomNumber:
                  roomNum.isNotEmpty ? roomNum : existingWindow.roomNumber,
              roomDesignation: roomDesig.isNotEmpty
                  ? roomDesig
                  : existingWindow.roomDesignation,
              windowType:
                  winType.isNotEmpty ? winType : existingWindow.windowType,
              material:
                  material.isNotEmpty ? material : existingWindow.material,
              wingDimensions: dimensions.isNotEmpty
                  ? dimensions
                  : existingWindow.wingDimensions,
              fittings:
                  fittings.isNotEmpty ? fittings : existingWindow.fittings,
              windowFunctionOK: windowFunctionOK,
              hasRaffstore: hasRaffstore,
              raffstoreOK: raffstoreOK,
              notes: notes.isNotEmpty ? notes : existingWindow.notes,
            );
            await DatabaseService.updateWindow(updated);
          }
        } else {
          final newWin = Window(
            id: null,
            windowAlias: alias,
            provisionalAlias: alias,
            windowNumber: effectiveWinNum,
            floor: floor,
            roomNumber: roomNum,
            roomDesignation: roomDesig,
            windowType: winType,
            material: material,
            wingDimensions: dimensions,
            fittings: fittings,
            windowFunctionOK: windowFunctionOK,
            hasRaffstore: hasRaffstore,
            raffstoreOK: raffstoreOK,
            notes: notes,
          );
          windowId = await DatabaseService.insertWindow(newWin);
        }

        distinctWindowAliases.add(alias);

        final status =
            (!windowFunctionOK || hasDefect) ? 'HasErrors' : 'Inspected';
        final inspWinId = await DatabaseService.insertInspectionWindow({
          'inspectionId': inspectionId,
          'windowId': windowId,
          'status': status,
          'notes': notes,
        });

        for (final errEntry in rowErrors) {
          final catError = errEntry.key;
          final qty = errEntry.value;
          final winError = InspectionWindowError(
            inspectionWindowId: inspWinId,
            errorId: catError.errorId,
            errorCode: catError.code,
            quantity: qty,
            severity: catError.severity,
            notes: '',
            resolutionStatus: 'Open',
          );
          await DatabaseService.insertInspectionWindowError(winError);
          sheetErrorsCount++;
          totalErrorsLinked++;
        }

        sheetWindowsCount++;

        // Add to allWindowChanges for the primary report (from latest sheet)
        if (sheetIndex == 0) {
          allWindowChanges.add(DoorChangeItem(
            doorAlias: alias,
            doorNumber: effectiveWinNum,
            roomDesignation: roomDesig.isNotEmpty
                ? roomDesig
                : (roomNum.isNotEmpty ? 'Raum $roomNum' : ''),
            floor: floor,
            changeType: existingWindow != null ? 'updated' : 'new',
            status: (!windowFunctionOK || hasDefect) ? 'HasErrors' : 'geprüft',
            errorCount: rowErrorCount,
            assetType: 'window',
          ));
        }
      }

      logs.add(
          'Blatt "$sName" abgeschlossen: $sheetWindowsCount Fenster erfasst, $sheetErrorsCount Mängel verknüpft.');
    }

    await WindowOptionsService.save();
    try {
      await LocalDatabaseService.refreshLocalCatalogFromMain();
    } catch (_) {}
    logs.add(
        'Fenster-Import vollständig: ${windowSheetsToProcess.length} Blätter verarbeitet, '
        '${distinctWindowAliases.length} eindeutige Fenster, $totalErrorsLinked Mängel verknüpft.');

    return ExcelImportResult(
      sheetsProcessed: windowSheetsToProcess.length,
      doorsImported: 0,
      windowsImported: distinctWindowAliases.length,
      errorsLinked: totalErrorsLinked,
      assetType: 'window',
      warnings: warnings,
      logs: logs,
      doorChanges: allWindowChanges,
      newCatalogProposals: newCatalogProposals,
      clientName: fallbackClient,
      objectAddress: canonicalObjectAddress,
      jobNumber: fallbackJobNum,
      inspectionDate: windowSheetsToProcess.firstOrNull?['dateStr'] ?? '',
    );
  }
}
