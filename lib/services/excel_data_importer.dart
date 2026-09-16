import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/models/door_conflict.dart';
import 'package:wartungstool/services/customer_normalizer.dart';
import 'package:wartungstool/services/database_service.dart';

class ExcelImportResult {
  final int sheetsProcessed;
  final int doorsImported;
  final int errorsLinked;
  final List<String> warnings;
  final List<String> logs;
  /// Doors that had conflicts and were NOT written to DB yet.
  /// Route the Manager to DoorConflictReviewPage when this is non-empty.
  final List<DoorConflict> doorConflicts;
  /// Catalog conflicts found during Fehlerübersicht processing.
  final List<ImportConflict> catalogConflicts;

  ExcelImportResult({
    required this.sheetsProcessed,
    required this.doorsImported,
    required this.errorsLinked,
    required this.warnings,
    this.logs = const [],
    this.doorConflicts = const [],
    this.catalogConflicts = const [],
  });

  bool get hasDoorConflicts => doorConflicts.isNotEmpty;
  bool get hasCatalogConflicts => catalogConflicts.isNotEmpty;
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
    final String projectNumber = projMatch != null ? projMatch.group(1)!.toUpperCase() : '';

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
        logs.add('Makro-Datei ($ext) in temporäre .xlsx umgewandelt: $tempPath');
      } catch (e) {
        logs.add('Hinweis: Konvertierung von $ext in .xlsx übersprungen ($e)');
      }
    }

    final List<int> bytes = await fileToRead.readAsBytes();
    final decoder = SpreadsheetDecoder.decodeBytes(bytes);

    final allSheets = decoder.tables.keys.toList();
    logs.add('Gefundene Arbeitsblätter (${allSheets.length}): ${allSheets.join(', ')}');

    // 1. Process Fehlerübersicht / Fehlercode and populate error_catalog
    final fehlerSheetKey = decoder.tables.keys.where((k) {
      final l = k.trim().toLowerCase();
      return l == 'fehlerübersicht' ||
             l == 'fehleruebersicht' ||
             l == 'fehler-übersicht' ||
             l == 'fehlercode' ||
             l == 'fehlerkatalog' ||
             l.startsWith('fehler');
    }).firstOrNull;

    final fehlerSheet = fehlerSheetKey != null ? decoder.tables[fehlerSheetKey] : null;
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
          await DatabaseService.insertErrorCatalog(res.conflict.incoming.copyWith(
            code: newCode,
            status: 'Approved',
          ));
        } else if (res.action == ResolutionAction.replaceExisting || res.action == ResolutionAction.keepExisting) {
          if (res.newCode != null && res.newCode!.isNotEmpty) {
            resolvedCodes[res.conflict.code] = res.newCode!;
            resolvedCodes[res.conflict.description] = res.newCode!;
            resolvedCodes[res.conflict.incoming.description] = res.newCode!;
          }
        }
      }
    }

    if (fehlerSheet == null) {
      final msg = 'Kein Arbeitsblatt "Fehlerübersicht" / "Fehlercode" in der Excel-Datei gefunden. Verwende bestehenden Fehlerkatalog.';
      warnings.add(msg);
      logs.add('WARNUNG: $msg');
    } else {
      final List<ErrorCatalog> parsedCatalogErrors = [];
      for (int r = 1; r < fehlerSheet.maxRows; r++) {
        final row = fehlerSheet.rows[r];
        if (row.isEmpty) continue;

        String? code;
        String? desc;

        // Format 1: Column 1 = Code, Column 2 = Description (Fehlerübersicht)
        if (row.length > 2 && row[1] != null && row[2] != null) {
          final c = row[1].toString().trim();
          final d = row[2].toString().trim();
          if (c.isNotEmpty && d.isNotEmpty && RegExp(r'^\d+(\.\d+)?').hasMatch(c)) {
            code = c;
            desc = d;
          }
        }

        // Format 2: Column 1 = "Code Description" (Fehlercode)
        if (code == null && row.length > 1 && row[1] != null) {
          final text = row[1].toString().trim();
          final m = RegExp(r'^([\d\.]+)\s+(.*)$').firstMatch(text);
          if (m != null) {
            code = m.group(1)!;
            desc = m.group(2)!;
          }
        }

        // Format 3: Column 0 = Code, Column 1 = Description
        if (code == null && row.length > 1 && row[0] != null && row[1] != null) {
          final c = row[0].toString().trim();
          final d = row[1].toString().trim();
          if (RegExp(r'^\d+(\.\d+)?$').hasMatch(c) && d.isNotEmpty) {
            code = c;
            desc = d;
          }
        }

        if (code != null && desc != null && code.isNotEmpty && desc.isNotEmpty) {
          final isNotice = code.startsWith('0.') ||
              desc.toLowerCase().startsWith('hinweis') ||
              desc.toLowerCase().contains('hinweis');
          final cat = isNotice ? 'Hinweis' : 'Mangel';
          final sev = isNotice ? 'low' : 'medium';

          parsedCatalogErrors.add(ErrorCatalog(
            code: code,
            description: desc,
            category: cat,
            severity: sev,
            status: 'Approved',
          ));
        }
      }

      logs.add('Arbeitsblatt "$fehlerSheetKey" erkannt: ${parsedCatalogErrors.length} Fehlerdefinitionen extrahiert.');

      // Merge error catalog
      if (resolutions == null) {
        final mergeResult = await DatabaseService.mergeErrorCatalog(parsedCatalogErrors, autoResolve: false);
        if (mergeResult.conflicts.isNotEmpty) {
          allCatalogConflicts.addAll(mergeResult.conflicts);
          logs.add('KATALOGKONFLIKTE GEFUNDEN: ${mergeResult.conflicts.length} echte Konflikte in $fehlerSheetKey.');
        } else {
          logs.add('Fehlerkatalog verarbeitet: ${mergeResult.insertedCount} neue Einträge automatisch hinzugefügt, ${mergeResult.duplicateCount} identische Einträge übersprungen.');
        }
      } else {
        logs.add('Konfliktlösungen angewendet: ${resolvedCodes.length} Codes überschrieben, ${skippedCodes.length} übersprungen.');
      }
    }

    // Refresh memory catalog list
    final catalog = await DatabaseService.getAllErrorCatalog();
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
        logs.add('Arbeitsblatt "$sheetName" übersprungen (kein "Türlisten"-Präfix).');
        continue;
      }

      final sheet = decoder.tables[sheetName]!;
      if (sheet.maxRows < 2) {
        final warn = 'Arbeitsblatt "$sheetName" hat nicht genügend Zeilen (${sheet.maxRows} < 2).';
        warnings.add(warn);
        logs.add('WARNUNG: $warn');
        continue;
      }

      String metadataText = '';
      for (int r = 0; r < sheet.maxRows && r < 3; r++) {
        final row = sheet.rows[r];
        if (row.isNotEmpty && row[0] != null && row[0].toString().trim().isNotEmpty) {
          metadataText = row[0].toString();
          break;
        }
      }

      final meta = _parseMetadata(metadataText);

      // Extract date from sheet name if present (e.g. "Türlisten 04.09.2025")
      final sheetDateMatch = RegExp(r'(\d{2})[\.\-_](\d{2})[\.\-_](\d{4}|\d{2})').firstMatch(sheetName) ??
                             RegExp(r'(\d{4})[\.\-_](\d{2})[\.\-_](\d{2})').firstMatch(sheetName);
      if (sheetDateMatch != null) {
        if (sheetDateMatch.group(1)!.length == 4) {
          meta['date'] = '${sheetDateMatch.group(1)}-${sheetDateMatch.group(2)!.padLeft(2, '0')}-${sheetDateMatch.group(3)!.padLeft(2, '0')}';
        } else {
          final day = sheetDateMatch.group(1)!.padLeft(2, '0');
          final month = sheetDateMatch.group(2)!.padLeft(2, '0');
          var year = sheetDateMatch.group(3)!;
          if (year.length == 2) year = '20$year';
          meta['date'] = '$year-$month-$day';
        }
      }

      final String dateStr = meta['date'] ?? '';
      final DateTime sheetDate = DateTime.tryParse(dateStr) ?? DateTime.fromMillisecondsSinceEpoch(0);

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

    logs.add('Reihenfolge der verarbeiteten Blätter (neueste zuerst): ' + 
      doorSheetsToProcess.map((ds) => '${ds['sheetName']} (${ds['meta']['date']})').join(', '));

    for (final dsInfo in doorSheetsToProcess) {
      final String sheetName = dsInfo['sheetName'] as String;
      final sheet = dsInfo['sheet'];
      final Map<String, String> meta = Map<String, String>.from(dsInfo['meta'] as Map);
      meta['projectNumber'] = projectNumber;
      if (meta['clientName'] != null && meta['clientName']!.isNotEmpty) {
        meta['clientName'] = CustomerNormalizer.getCanonicalName(meta['clientName']!);
      }

      logs.add('Verarbeite Türlisten-Blatt: "$sheetName" (${sheet.maxRows} Zeilen)...');
      logs.add('Metadaten für "$sheetName": Kunde="${meta['clientName']}", Objekt="${meta['objectAddress']}", Datum="${meta['date']}", Auftrag="${meta['jobNumber']}", Projektnummer="${meta['projectNumber']}"');

      // Check for existing inspection to warn user on duplicate re-import
      final existingInspId = await DatabaseService.findExistingInspectionId(meta);
      if (existingInspId != null) {
        logs.add('WARNUNG: Das Inspektionsdokument für Auftrag "${meta['jobNumber']}" (Kunde: "${meta['clientName']}", Objekt: "${meta['objectAddress']}", Datum: "${meta['date']}") existiert bereits im Stammdatenbestand.');
      }

      // Fetch existing inspection or create new inspection record to prevent duplication on re-import
      final inspectionId = await DatabaseService.getOrInsertInspection(meta);
      sheetsProcessed++;
      logs.add('Inspektion ID $inspectionId für "$sheetName" (Auftrag: ${meta['jobNumber']}) verarbeitet.');

      // Analyze Column headers to build error column mappings
      int headerRowIndex = 2;
      for (int r = 0; r < sheet.maxRows && r < 10; r++) {
        final rRow = sheet.rows[r];
        if (rRow.isNotEmpty) {
          bool foundHeader = false;
          for (int c = 0; c < rRow.length && c < 5; c++) {
            if (rRow[c] != null) {
              final cellVal = rRow[c].toString().trim().toLowerCase();
              if (cellVal == 'pos' || cellVal == 'pos.' || cellVal == 'lfd' || cellVal == 'nr' || cellVal == 'tür-nr' || cellVal == 'türnummer' || cellVal == 'tür nr') {
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
      if (notesColumnIndex == -1) {
        final textCountPerCol = <int, int>{};
        for (int r = headerRowIndex + 1; r < sheet.maxRows; r++) {
          final row = sheet.rows[r];
          for (int c = 27; c < row.length; c++) {
            final cell = row[c];
            if (cell != null) {
              final str = cell.toString().trim();
              if (str.isNotEmpty && str != '1' && str != '0' && double.tryParse(str) == null && str.length > 2) {
                textCountPerCol[c] = (textCountPerCol[c] ?? 0) + 1;
              }
            }
          }
        }

        if (textCountPerCol.isNotEmpty) {
          final sorted = textCountPerCol.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          notesColumnIndex = sorted.first.key;
        }
      }
      
      // 3. Scan from column 27 (AB) onwards for error headers
      for (int c = 27; c < headerRow.length; c++) {
        if (c == notesColumnIndex) continue;
        final val = _cell(headerRow, c);
        if (val == null) continue;
        final headerStr = val.toString().trim();
        if (headerStr.isEmpty) continue;
        if (headerStr.toLowerCase() == 'anmerkung' || headerStr.toLowerCase().startsWith('anmerkung')) {
          break; // Stop at notes column
        }
        
        // Try to parse code (e.g. "0.32 Das Brand-...")
        final match = RegExp(r'^([\d\.]+)\s+(.*)$').firstMatch(headerStr);
        String code;
        if (match != null) {
          code = match.group(1)!;
        } else {
          // Check if header matches an existing catalog item by description
          final exactCatalogMatch = catalog.where((e) =>
            e.description.trim().toLowerCase() == headerStr.toLowerCase() ||
            e.description.trim().toLowerCase() == headerStr.replaceFirst(RegExp(r'^Hinweis:\s*', caseSensitive: false), '').trim().toLowerCase()
          ).firstOrNull;

          if (exactCatalogMatch != null) {
            code = exactCatalogMatch.code;
            logs.add('Spaltenkopf "$headerStr" in "$sheetName" zu bestehendem Katalogcode "${exactCatalogMatch.code}" zugeordnet.');
          } else {
            code = headerStr;
          }
        }

        // Check if code exists in catalog or was resolved by Manager
        final existsInCatalog = catalog.any((e) => e.code.toLowerCase() == code.toLowerCase() || e.description.trim().toLowerCase() == code.toLowerCase());
        final isResolved = resolvedCodes.containsKey(code) || skippedCodes.contains(code);

        if (!existsInCatalog && !isResolved) {
          // Raise catalog conflict for Manager review
          final alreadyConflict = allCatalogConflicts.any((cf) => cf.code.toLowerCase() == code.toLowerCase() || cf.description.toLowerCase() == code.toLowerCase());
          if (!alreadyConflict) {
            final isNotice = code.toLowerCase().startsWith('0.') || code.toLowerCase().startsWith('hinweis') || code.toLowerCase().contains('hinweis');
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
              ),
              reason: 'Unbekannter Mangel-/Hinweis-Spaltenkopf in "$sheetName" (weder im Fehlerkatalog noch in Fehlerübersicht vorhanden).',
            ));

            final msg = '[KATALOG-KONFLIKT] Unbekannter Mangel/Hinweis "$headerStr" in Blatt "$sheetName" erfordert Überprüfung durch den Manager.';
            warnings.add(msg);
            logs.add(msg);
          }
        }

        errorColumns[c] = code;
      }

      logs.add('Mängelspalten für "$sheetName": ${errorColumns.length} Mängelcodes erkannt. (Anmerkung: ${notesColumnIndex >= 0 ? "Spalte $notesColumnIndex" : "Standard"})');

      int sheetDoorsCount = 0;
      int sheetErrorsCount = 0;

      // ── Collect all doors from this sheet first, then batch-merge ────────
      final sheetDoors = <Door>[];
      final sheetDoorRows = <int, List<dynamic>>{}; // doorIndex -> raw row for error linking

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
        
        // Normalization check on physical properties
        final doorType = _toStr(_cell(row, 5));
        final wingCount = _toInt(_cell(row, 6), defaultValue: 1);
        final material = _toStr(_cell(row, 7));
        final manufacturer = _toStr(_cell(row, 8));
        final dinConfig = _toStr(_cell(row, 9));
        final closerType = _toStr(_cell(row, 10));
        final closingSeq = _toStr(_cell(row, 11));
        final lockDim = _toStr(_cell(row, 12));
        
        final closerHinge = _toBool(_cell(row, 13));
        final closerOpposite = _toBool(_cell(row, 14));
        final lintelInsideOver1m = _toBool(_cell(row, 15));
        final escapeDoorControl = _toBool(_cell(row, 16));
        final accessControl = _toStr(_cell(row, 17));
        final escapeRouteSituation = _toBool(_cell(row, 18));
        final escapeRouteSignage = _toBool(_cell(row, 19));
        final blindCyl = _toBool(_cell(row, 20));
        final pzCyl = _toBool(_cell(row, 21));
        final fittingType = _toStr(_cell(row, 22));
        final panicFunc = _toStr(_cell(row, 23));
        final escapeDirectionRespected = _toBool(_cell(row, 24));
        final fullPanicStandWing = _toBool(_cell(row, 25));
        final doorFunctionOK = _toBool(_cell(row, 26));

        // Read & format notes from "Anmerkung" column for Door properties
        String rawNotes = '';
        if (notesColumnIndex >= 0 && notesColumnIndex < row.length) {
          rawNotes = _toStr(_cell(row, notesColumnIndex));
        } else if (row.length > 37) {
          rawNotes = _toStr(_cell(row, 37));
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
          wingCount: wingCount,
          material: material,
          manufacturer: manufacturer,
          dinConfiguration: dinConfig,
          closerType: closerType,
          closingSequenceSystem: closingSeq,
          lockDimensions: lockDim,
          closerOnHingeSide: closerHinge,
          closerOnOppositeSide: closerOpposite,
          lintelHeightInsideOver1m: lintelInsideOver1m,
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
      final mergeResult = await DatabaseService.mergeDoors(
        sheetDoors,
        jobNumber: meta['jobNumber'] ?? '',
        clientName: meta['clientName'] ?? '',
        objectAddress: meta['objectAddress'] ?? '',
        sourceContext: 'Arbeitsblatt: "$sheetName"',
        currentInspectionDate: meta['date'] ?? '',
      );

      if (mergeResult.hasConflicts) {
        allDoorConflicts.addAll(mergeResult.conflicts);
        logs.add('KONFLIKTE: ${mergeResult.conflicts.length} Türkonflikte in "$sheetName" '
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
        if (doorId == null) {
          doorId = await DatabaseService.insertDoor(door);
        }

        final doorFunctionOK = door.doorFunctionOK;
        final row = sheetDoorRows[di] ?? [];
        final doorNote = door.notes.isNotEmpty ? door.notes : 'Importiert aus Excel';

        final junctionId = await DatabaseService.insertInspectionDoor({
          'inspectionId': inspectionId,
          'doorId': doorId,
          'status': doorFunctionOK ? 'Passed' : 'Failed',
          'notes': doorNote,
        });
        totalDoorsImported++;
        sheetDoorsCount++;

        // Process error quantities in error columns
        for (var entry in errorColumns.entries) {
          final cIndex = entry.key;
          final code = entry.value;

          // If code was skipped in catalog resolution, ignore it
          if (skippedCodes.contains(code)) continue;

          // Map code based on catalog resolution
          final targetCode = resolvedCodes[code] ?? code;

          if (cIndex < row.length && row[cIndex] != null) {
            final qty = _toErrorQty(row[cIndex]);
            if (qty > 0) {
              // Find in catalog using the mapped targetCode or description
              final catalogItem = catalog.where(
                (e) => e.code.toLowerCase() == targetCode.toLowerCase() ||
                       e.description.trim().toLowerCase() == targetCode.toLowerCase(),
              ).firstOrNull;

              int? errorId = catalogItem?.errorId;
              if (errorId == null) {
                final dbItem = await DatabaseService.searchErrorCatalog(targetCode);
                if (dbItem.isNotEmpty && dbItem.first.errorId != null) {
                  errorId = dbItem.first.errorId;
                }
              }

              if (errorId != null) {
                await DatabaseService.insertInspectionDoorError(InspectionDoorError(
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
                logs.add('Mangel "$targetCode" für Tür ${door.doorNumber} in "$sheetName" nicht verknüpft (wartet auf Konfliktlösung durch Manager).');
              }
            }
          }
        }
      }

      logs.add('Blatt "$sheetName" abgeschlossen: $sheetDoorsCount Türen importiert, $sheetErrorsCount Mängel verknüpft.');
    }

    logs.add('Import abgeschlossen: Total $sheetsProcessed von ${allSheets.length} Arbeitsblättern verarbeitet. $totalDoorsImported Türen, $totalErrorsLinked Mängel verknüpft, ${warnings.length} Warnungen, ${allDoorConflicts.length} Türkonflikte, ${allCatalogConflicts.length} Katalogkonflikte zur Überprüfung.');

    // Write full logs to migration_protocol.log in project root
    try {
      final logFile = File('migration_protocol.log');
      final StringBuffer sb = StringBuffer();
      sb.writeln('======================================================================');
      sb.writeln('MIGRATION PROTOCOL - IMPORT FROM: ${excelFile.path}');
      sb.writeln('Date of Migration: ${DateTime.now()}');
      sb.writeln('======================================================================');
      sb.writeln('SUMMARY:');
      sb.writeln('  - Sheets Processed: $sheetsProcessed');
      sb.writeln('  - Doors Imported: $totalDoorsImported');
      sb.writeln('  - Errors Linked: $totalErrorsLinked');
      sb.writeln('  - Warnings: ${warnings.length}');
      sb.writeln('  - Door Conflicts: ${allDoorConflicts.length}');
      sb.writeln('  - Catalog Conflicts: ${allCatalogConflicts.length}');
      sb.writeln('----------------------------------------------------------------------');
      sb.writeln('MIGRATION LOGS:');
      for (final logLine in logs) {
        sb.writeln('  $logLine');
      }
      sb.writeln('======================================================================\n');
      
      await logFile.writeAsString(sb.toString(), mode: FileMode.append, flush: true);
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
      warnings: warnings,
      logs: logs,
      doorConflicts: allDoorConflicts,
      catalogConflicts: allCatalogConflicts,
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

    final cleanClient = CustomerNormalizer.getCanonicalName(client);

    return {
      'clientName': cleanClient.isNotEmpty ? cleanClient : 'Stadt Geesthacht',
      'objectAddress': object.isNotEmpty ? object : 'Fam. Zentrum Regenbogen',
      'date': formattedDate,
      'contactPerson': contact.isNotEmpty ? contact : 'Herr Basau',
      'inspectorName': inspector.isNotEmpty ? inspector : 'Gert',
      'jobNumber': jobNum.isNotEmpty ? jobNum : '25-12115-AB',
    };
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
      return strVal.endsWith('.0') ? strVal.substring(0, strVal.length - 2) : strVal;
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

  /// Sanitizes door numbers by stripping unknown noise characters (commas, question marks, isolated dashes).
  /// Preserves valid alphanumeric formats like "21.A", "2202.5", "EG.01", "T-01".
  @visibleForTesting
  static String sanitizeDoorNumberForTest(String raw) => _sanitizeDoorNumber(raw);

  static String _sanitizeDoorNumber(String raw, {int pos = 0, int rowIndex = 0}) {
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
    String text = raw.replaceAll(RegExp(r'_x000[dD]_?'), '\n')
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
}
