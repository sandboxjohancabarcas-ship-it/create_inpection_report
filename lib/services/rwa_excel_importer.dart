import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/rwa_options_service.dart';

class RwaImportResult {
  final int sheetsProcessed;
  final int rwaSystemsImported;
  final int inspectionsCreated;
  final int settingsEvaluated;
  final int errorsLinked;
  final List<String> warnings;
  final List<String> logs;
  final List<DoorChangeItem> doorChanges;

  RwaImportResult({
    required this.sheetsProcessed,
    required this.rwaSystemsImported,
    required this.inspectionsCreated,
    required this.settingsEvaluated,
    required this.errorsLinked,
    required this.warnings,
    required this.logs,
    this.doorChanges = const [],
  });
}

class RwaExcelImporter {
  /// Result Normalization
  static String normalizeResult(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'OK'; // default fallback if empty
    final lower = trimmed.toLowerCase();

    // Not present
    if (lower == 'n.v' ||
        lower == 'n.v.' ||
        lower == 'nv' ||
        lower == '---' ||
        lower == '--' ||
        lower == '-' ||
        lower == '/' ||
        lower.contains('nicht vorhanden') ||
        lower == 'n.a.') {
      return 'NOT_PRESENT';
    }

    // Defect
    if (lower == 'x' ||
        lower.contains('mangel') ||
        lower.contains('defekt') ||
        lower.contains('nein') ||
        lower.contains('fehler')) {
      return 'DEFECT';
    }

    // OK
    if (lower == 'i.o.' ||
        lower == 'i.o' ||
        lower == 'io' ||
        lower == 'ok' ||
        lower == 'o.k.' ||
        lower == 'ja' ||
        trimmed == '√' ||
        trimmed == '✓' ||
        lower.contains('keine mängel') ||
        lower.contains('in ordnung')) {
      return 'OK';
    }

    return 'OK';
  }

  /// Detect whether an annotation is a defect or an ordinary remark
  static bool isDefectAnnotation(String text) {
    if (text.trim().isEmpty || text.trim() == '---' || text.trim() == '-') {
      return false;
    }
    final lower = text.toLowerCase();
    final defectKeywords = [
      'störung',
      'defekt',
      'ausfall',
      'auslösen nicht möglich',
      'auslösung nicht möglich',
      'überfällig',
      'abgelaufen',
      'tauschen',
      'austauschen',
      'erneuern',
      'austausch erforderlich',
      'fehlt',
      'fehlend',
      'korrosion',
      'korrodiert',
      'rostig',
      'schwergängig',
      'klemmt',
      'blockiert',
      'schließt nicht',
      'öffnet nicht',
      'undicht',
      'druckabfall',
      'beschädigt',
      'defektes glas',
      'glas defekt',
      'glas gebrochen',
      'scheibe defekt',
      'scheibe gebrochen',
      'glas',
      'abgerissen',
      'ohne funktion',
      'nicht funktionsfähig',
      'mangel',
    ];

    for (final kw in defectKeywords) {
      if (lower.contains(kw)) return true;
    }
    return false;
  }

  /// Suggest or match an error catalog code based on setting name and annotation text
  static String matchCatalogCode(String settingName, String text) {
    final sLower = settingName.toLowerCase();
    final tLower = text.toLowerCase();

    if (sLower.contains('feuertaster') || sLower.contains('handauslöser')) {
      if (tLower.contains('korrosion') || tLower.contains('feucht')) return 'RWA-FT-001';
      if (tLower.contains('glas') || tLower.contains('scheibe')) return 'RWA-FT-002';
      return 'RWA-FT-001';
    }
    if (sLower.contains('rauchmelder') || sLower.contains('melder')) {
      if (tLower.contains('verschmutzt') || tLower.contains('staub')) return 'RWA-RM-001';
      if (tLower.contains('überfällig') || tLower.contains('jahr') || tLower.contains('alt')) return 'RWA-RM-002';
      return 'RWA-RM-001';
    }
    if (sLower.contains('notstrom') || sLower.contains('batterie') || sLower.contains('akku')) {
      if (tLower.contains('überfällig') || tLower.contains('tauschen') || tLower.contains('alt') || tLower.contains('jahre')) return 'RWA-AK-001';
      if (tLower.contains('spannung') || tLower.contains('leer') || tLower.contains('tiefentladen')) return 'RWA-AK-002';
      return 'RWA-AK-001';
    }
    if (sLower.contains('co2') || sLower.contains('flasche')) {
      if (tLower.contains('gewicht') || tLower.contains('verlust') || tLower.contains('untergewicht') || tLower.contains('druck')) return 'RWA-CO2-001';
      if (tLower.contains('tüv') || tLower.contains('abgelaufen')) return 'RWA-CO2-002';
      return 'RWA-CO2-001';
    }
    if (sLower.contains('klappe') || sLower.contains('antrieb') || sLower.contains('dämpfer')) {
      if (tLower.contains('schwergängig') || tLower.contains('klemmt') || tLower.contains('schließt')) return 'RWA-KL-001';
      if (tLower.contains('dichtung') || tLower.contains('porös') || tLower.contains('undicht')) return 'RWA-KL-002';
      if (tLower.contains('dämpfer') || tLower.contains('öl')) return 'RWA-DP-001';
      return 'RWA-KL-001';
    }
    if (sLower.contains('zentrale')) {
      if (tLower.contains('störung') || tLower.contains('platine') || tLower.contains('netzteil')) return 'RWA-ZE-001';
      return 'RWA-ZE-001';
    }

    return 'RWA-GEN-001';
  }

  /// Parse an Excel file and import all RWA history and assets into DatabaseService
  static Future<RwaImportResult> importFromFile(File excelFile) async {
    final logs = <String>[];
    final warnings = <String>[];
    int sheetsProcessed = 0;
    int rwaSystemsImported = 0;
    int inspectionsCreated = 0;
    int settingsEvaluated = 0;
    int errorsLinked = 0;

    final fileName = p.basename(excelFile.path);
    logs.add('Starte RWA-Excel-Import für Datei: $fileName');

    // Extract project number from file name (e.g. "P-0442 ...")
    final RegExp projRegExp = RegExp(r'(P-\d+)', caseSensitive: false);
    final RegExpMatch? projMatch = projRegExp.firstMatch(fileName);
    String projectNumber = projMatch != null ? projMatch.group(1)!.toUpperCase() : '';

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
      } catch (e) {
        logs.add('Hinweis: Konvertierung von $ext in .xlsx übersprungen ($e)');
      }
    }

    final bytes = await fileToRead.readAsBytes();
    final decoder = SpreadsheetDecoder.decodeBytes(bytes);

    // Initialize RWA error catalog in database if not done
    await DatabaseService.checkAndInitializeRwaCatalog();

    // Identify year sheets (e.g. "2019", "2020", "2026", "2025 (2)")
    final yearRegex = RegExp(r'\b(20\d{2})\b');
    final validSheets = <String, int>{};

    for (final sName in decoder.tables.keys) {
      final match = yearRegex.firstMatch(sName);
      if (match != null) {
        validSheets[sName] = int.parse(match.group(1)!);
      }
    }

    // Sort sheets chronologically (oldest to newest)
    final sortedSheetEntries = validSheets.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    if (sortedSheetEntries.isEmpty) {
      warnings.add('Keine Jahres-Arbeitsblätter in $fileName gefunden.');
      return RwaImportResult(
        sheetsProcessed: 0,
        rwaSystemsImported: 0,
        inspectionsCreated: 0,
        settingsEvaluated: 0,
        errorsLinked: 0,
        warnings: warnings,
        logs: logs,
      );
    }

    RwaSystem? currentRwa;
    int? rwaSystemId;

    for (final entry in sortedSheetEntries) {
      final sheetName = entry.key;
      final year = entry.value;
      final table = decoder.tables[sheetName]!;

      if (table.maxRows < 10) continue;

      int einrichtungHeaderRow = -1;
      for (int r = 0; r < table.maxRows; r++) {
        final rCells = table.rows[r];
        if (rCells.isNotEmpty && rCells[0]?.toString().trim() == 'Einrichtung') {
          einrichtungHeaderRow = r;
          break;
        }
      }

      if (einrichtungHeaderRow == -1) {
        warnings.add('Blatt "$sheetName": Keine "Einrichtung"-Tabelle gefunden.');
        continue;
      }

      // 1. Parse Object Address & System Properties (rows 0 to einrichtungHeaderRow - 1)
      String objectAddress = '';
      final propMap = <String, List<String>>{};
      String currentKey = '';

      for (int r = 0; r < einrichtungHeaderRow; r++) {
        final rCells = table.rows[r];
        final col0 = rCells.isNotEmpty ? rCells[0]?.toString().trim() ?? '' : '';
        final col1 = rCells.length > 1 ? rCells[1]?.toString().trim() ?? '' : '';

        if (col0 == 'Objekt:' || col0 == 'Objekt') {
          if (col1.isNotEmpty) objectAddress = col1;
        } else if (col0.isNotEmpty) {
          currentKey = col0;
          propMap.putIfAbsent(currentKey, () => []);
          if (col1.isNotEmpty) propMap[currentKey]!.add(col1);
        } else if (col0.isEmpty && col1.isNotEmpty && currentKey.isNotEmpty) {
          // Multiline value for current property (e.g. CO2 bottle specifications)
          propMap[currentKey]!.add(col1);
        }
      }

      // If projectNumber wasn't in filename, check if address has it or generate default
      if (projectNumber.isEmpty) {
        final match = projRegExp.firstMatch(objectAddress);
        if (match != null) {
          projectNumber = match.group(1)!.toUpperCase();
        } else {
          projectNumber = 'P-RWA';
        }
      }

      // Parse specific fields
      String systemType = _getJoinedProp(propMap, 'RWA-System:');
      if (systemType.isEmpty) systemType = _getJoinedProp(propMap, 'RWA-System');
      if (systemType.isEmpty) systemType = 'elektromotorisch';

      String building = _getJoinedProp(propMap, 'Gebäude:');
      if (building.isEmpty) building = _getJoinedProp(propMap, 'Gebäude');
      // If building is in objectAddress (e.g. 'PAE-Labor, Gebäude "G" - Anlage 1 - M-PIC-Ost\nHohe-Schar-Str. 36, 21107 Hamburg')
      if (building.isEmpty) {
        final bMatch = RegExp(r'Gebäude\s+["\x27]?([A-Za-z0-9]+)["\x27]?', caseSensitive: false).firstMatch(objectAddress);
        if (bMatch != null) {
          building = 'Gebäude ${bMatch.group(1)}';
        } else {
          final fMatch = RegExp(r'Gebäude\s+([A-Za-z0-9]+)', caseSensitive: false).firstMatch(fileName);
          if (fMatch != null) building = 'Gebäude ${fMatch.group(1)}';
        }
      }

      String floor = _getJoinedProp(propMap, 'Geschoss:');
      if (floor.isEmpty) floor = _getJoinedProp(propMap, 'Geschoss');
      String room = _getJoinedProp(propMap, 'Raum:');
      if (room.isEmpty) room = _getJoinedProp(propMap, 'Raum');
      if (room.isEmpty) {
        final rMatch = RegExp(r'Anlage\s+\d+?\s*-\s*([^\n\r]+)', caseSensitive: false).firstMatch(objectAddress);
        if (rMatch != null) room = rMatch.group(1)!.trim();
      }

      String centralType = _getJoinedProp(propMap, 'Zentrale Fabrikat / Typ');
      if (centralType.isEmpty) centralType = _getJoinedProp(propMap, 'Zentrale Typ');
      if (centralType.isEmpty) centralType = _getJoinedProp(propMap, 'Zentrale:');
      if (centralType.isEmpty) centralType = _getJoinedProp(propMap, 'Zentrale');

      String fireButtonSpec = _getJoinedProp(propMap, 'Feuertaster');
      if (fireButtonSpec.isEmpty) fireButtonSpec = _getJoinedProp(propMap, 'Feuertaster:');

      String smokeDetectorSpec = _getJoinedProp(propMap, 'Rauch/Wärmemelder');
      if (smokeDetectorSpec.isEmpty) smokeDetectorSpec = _getJoinedProp(propMap, 'Rauchmelder');
      if (smokeDetectorSpec.isEmpty) smokeDetectorSpec = _getJoinedProp(propMap, 'Rauch-/Wärmemelder:');

      String actuatorSpec = _getJoinedProp(propMap, 'Antriebe');
      if (actuatorSpec.isEmpty) actuatorSpec = _getJoinedProp(propMap, 'Antriebe:');

      String ventilationButtonSpec = _getJoinedProp(propMap, 'Lüftungstaster');
      if (ventilationButtonSpec.isEmpty) ventilationButtonSpec = _getJoinedProp(propMap, 'Lüftungstaster:');

      String emergencyPowerSpec = _getJoinedProp(propMap, 'Notstrombatterie');
      if (emergencyPowerSpec.isEmpty) emergencyPowerSpec = _getJoinedProp(propMap, 'Notstrombatterie:');

      String co2BottleSpec = _getJoinedProp(propMap, 'CO2- Flaschen');
      if (co2BottleSpec.isEmpty) co2BottleSpec = _getJoinedProp(propMap, 'CO2-Flaschen');
      if (co2BottleSpec.isEmpty) co2BottleSpec = _getJoinedProp(propMap, 'CO2- Flaschen:');
      if (co2BottleSpec.isEmpty) co2BottleSpec = _getJoinedProp(propMap, 'CO2-Flaschen:');

      String thermalBottleSpec = _getJoinedProp(propMap, 'Thermoflasche');
      if (thermalBottleSpec.isEmpty) thermalBottleSpec = _getJoinedProp(propMap, 'Thermoflasche:');

      String rwaFlapSpec = _getJoinedProp(propMap, 'RWA-Klappen');
      if (rwaFlapSpec.isEmpty) rwaFlapSpec = _getJoinedProp(propMap, 'RWA-Klappen:');

      String ventilationFlapSpec = _getJoinedProp(propMap, 'Lüftungsklappen');
      if (ventilationFlapSpec.isEmpty) ventilationFlapSpec = _getJoinedProp(propMap, 'Lüftungsklappen:');

      String damperSpec = _getJoinedProp(propMap, 'Dämpfer');
      if (damperSpec.isEmpty) damperSpec = _getJoinedProp(propMap, 'Dämpfer:');

      // Learn options into RwaOptionsService
      await _registerOptions(
        systemType: systemType,
        centralType: centralType,
        fireButtonSpec: fireButtonSpec,
        smokeDetectorSpec: smokeDetectorSpec,
        actuatorSpec: actuatorSpec,
        ventilationButtonSpec: ventilationButtonSpec,
        emergencyPowerSpec: emergencyPowerSpec,
        co2BottleSpec: co2BottleSpec,
        thermalBottleSpec: thermalBottleSpec,
        rwaFlapSpec: rwaFlapSpec,
        ventilationFlapSpec: ventilationFlapSpec,
        damperSpec: damperSpec,
      );

      // Create or update Master RWA Asset on the first sheet (or update with latest specs)
      if (rwaSystemId == null) {
        // Derive system alias from filename or room/building
        String alias = p.basenameWithoutExtension(fileName)
            .replaceAll(RegExp(r'\.xlsx|\.xlsm', caseSensitive: false), '')
            .replaceAll('Wartungsprotokoll RWA', '')
            .replaceAll('Wartungsprotokoll', '')
            .replaceAll(projectNumber, '')
            .replaceAll(RegExp(r'[_-]+'), ' ')
            .trim();
        if (alias.isEmpty) {
          alias = room.isNotEmpty ? room : 'RWA-$projectNumber-01';
        }

        final initialRwa = RwaSystem(
          projectNumber: projectNumber,
          systemAlias: alias,
          systemType: systemType,
          objectAddress: objectAddress,
          building: building,
          floor: floor,
          room: room,
          centralType: centralType,
          fireButtonSpec: fireButtonSpec,
          smokeDetectorSpec: smokeDetectorSpec,
          actuatorSpec: actuatorSpec,
          ventilationButtonSpec: ventilationButtonSpec,
          emergencyPowerSpec: emergencyPowerSpec,
          co2BottleSpec: co2BottleSpec,
          thermalBottleSpec: thermalBottleSpec,
          rwaFlapSpec: rwaFlapSpec,
          ventilationFlapSpec: ventilationFlapSpec,
          damperSpec: damperSpec,
          systemFunctionOK: true,
        );

        rwaSystemId = await DatabaseService.insertRwaSystem(initialRwa);
        currentRwa = initialRwa.copyWith(id: rwaSystemId);
        rwaSystemsImported++;
        logs.add('RWA-Anlage angelegt (ID: $rwaSystemId, Alias: "$alias", Projekt: $projectNumber)');
      } else {
        // Update specs from subsequent sheets if they have more detailed information
        currentRwa = currentRwa!.copyWith(
          building: building.isNotEmpty ? building : currentRwa.building,
          floor: floor.isNotEmpty ? floor : currentRwa.floor,
          room: room.isNotEmpty ? room : currentRwa.room,
          centralType: centralType.isNotEmpty ? centralType : currentRwa.centralType,
          fireButtonSpec: fireButtonSpec.isNotEmpty ? fireButtonSpec : currentRwa.fireButtonSpec,
          smokeDetectorSpec: smokeDetectorSpec.isNotEmpty ? smokeDetectorSpec : currentRwa.smokeDetectorSpec,
          actuatorSpec: actuatorSpec.isNotEmpty ? actuatorSpec : currentRwa.actuatorSpec,
          ventilationButtonSpec: ventilationButtonSpec.isNotEmpty ? ventilationButtonSpec : currentRwa.ventilationButtonSpec,
          emergencyPowerSpec: emergencyPowerSpec.isNotEmpty ? emergencyPowerSpec : currentRwa.emergencyPowerSpec,
          co2BottleSpec: co2BottleSpec.isNotEmpty ? co2BottleSpec : currentRwa.co2BottleSpec,
          thermalBottleSpec: thermalBottleSpec.isNotEmpty ? thermalBottleSpec : currentRwa.thermalBottleSpec,
          rwaFlapSpec: rwaFlapSpec.isNotEmpty ? rwaFlapSpec : currentRwa.rwaFlapSpec,
          ventilationFlapSpec: ventilationFlapSpec.isNotEmpty ? ventilationFlapSpec : currentRwa.ventilationFlapSpec,
          damperSpec: damperSpec.isNotEmpty ? damperSpec : currentRwa.damperSpec,
        );
        await DatabaseService.updateRwaSystem(currentRwa);
      }

      // 2. Parse Bottom Metadata: Prüfdatum & Monteur
      DateTime inspectionDate = DateTime(year, 1, 1);
      String technician = 'Unbekannt';

      for (int r = einrichtungHeaderRow + 1; r < table.maxRows; r++) {
        final rCells = table.rows[r];
        final col0 = rCells.isNotEmpty ? rCells[0]?.toString().trim() ?? '' : '';

        if (col0.toLowerCase().startsWith('prüfdatum')) {
          if (r + 1 < table.maxRows) {
            final nextR = table.rows[r + 1];
            final dStr = nextR.isNotEmpty ? nextR[0]?.toString().trim() ?? '' : '';
            final parsedD = _parseDate(dStr, year);
            if (parsedD != null) inspectionDate = parsedD;

            final mStr = nextR.length > 1 ? nextR[1]?.toString().trim() ?? '' : '';
            if (mStr.isNotEmpty) technician = mStr;
          }
          break;
        }
      }

      // 3. Create Inspection Header record
      final dateStr = '${inspectionDate.year.toString().padLeft(4, '0')}-${inspectionDate.month.toString().padLeft(2, '0')}-${inspectionDate.day.toString().padLeft(2, '0')}';
      final inspectionData = {
        'projectNumber': projectNumber,
        'clientName': technician,
        'objectAddress': objectAddress,
        'date': dateStr,
        'orderType': 'Wartung',
        'assetType': 'rwa',
      };
      final inspectionId = await DatabaseService.insertInspection(inspectionData);
      inspectionsCreated++;

      // 4. Create InspectionRwa junction record
      final inspectionRwa = InspectionRwa(
        inspectionId: inspectionId,
        rwaSystemId: rwaSystemId,
        status: 'Completed',
        notes: 'Importiert aus Arbeitsblatt "$sheetName"',
      );
      final inspectionRwaId = await DatabaseService.insertInspectionRwa(inspectionRwa.toMap());

      // 5. Parse 12 Einrichtung settings & Anmerkungen
      bool anyDefectFound = false;

      for (int r = einrichtungHeaderRow + 1; r < table.maxRows; r++) {
        final rCells = table.rows[r];
        final col0 = rCells.isNotEmpty ? rCells[0]?.toString().trim() ?? '' : '';
        final col1 = rCells.length > 1 ? rCells[1]?.toString().trim() ?? '' : '';
        final col2 = rCells.length > 2 ? rCells[2]?.toString().trim() ?? '' : '';

        if (col0.toLowerCase().startsWith('prüfdatum')) break;
        if (col0.isEmpty) continue;

        final rawResult = col1;
        final normalized = normalizeResult(rawResult);
        final annotation = (col2 == '---' || col2 == '-') ? '' : col2;

        final setting = RwaInspectionSetting(
          inspectionRwaId: inspectionRwaId,
          settingName: col0,
          result: normalized,
          rawResult: rawResult,
          annotation: annotation,
        );
        await DatabaseService.insertRwaInspectionSetting(setting);
        settingsEvaluated++;

        // Check if this is a defect either via result == 'DEFECT' or defect keywords in annotation
        final isDefectByResult = normalized == 'DEFECT';
        final isDefectByText = isDefectAnnotation(annotation);

        if (isDefectByResult || isDefectByText) {
          anyDefectFound = true;
          final defectText = annotation.isNotEmpty
              ? annotation
              : 'Mangel bei Überprüfung von "$col0" festgestellt.';
          final errorCode = matchCatalogCode(col0, defectText);

          final rwaError = InspectionRwaError(
            inspectionRwaId: inspectionRwaId,
            settingName: col0,
            errorCode: errorCode,
            quantity: 1,
            severity: 'Major',
            notes: defectText,
            resolutionStatus: 'Open',
          );
          await DatabaseService.insertInspectionRwaError(rwaError);
          errorsLinked++;
        }
      }

      if (anyDefectFound && currentRwa != null) {
        currentRwa = currentRwa.copyWith(systemFunctionOK: false);
        await DatabaseService.updateRwaSystem(currentRwa);
      }

      sheetsProcessed++;
      logs.add('Blatt "$sheetName" verarbeitet: Datum $dateStr, Monteur "$technician".');
    }

    if (tempXlsx != null && await tempXlsx.exists()) {
      try {
        await tempXlsx.delete();
      } catch (_) {}
    }

    final List<DoorChangeItem> doorChanges = [];
    if (currentRwa != null) {
      final locationParts = [
        if (currentRwa.building.isNotEmpty) currentRwa.building,
        if (currentRwa.floor.isNotEmpty) currentRwa.floor,
        if (currentRwa.room.isNotEmpty) currentRwa.room,
      ];
      final locationStr = locationParts.join(' / ');
      doorChanges.add(DoorChangeItem(
        doorAlias: currentRwa.displayAlias,
        doorNumber: currentRwa.displayAlias,
        roomDesignation: locationStr.isNotEmpty ? locationStr : 'RWA-Anlage ($projectNumber)',
        floor: currentRwa.floor,
        changeType: rwaSystemsImported > 0 ? 'new' : 'updated',
        status: currentRwa.systemFunctionOK ? 'Geprüft' : 'Mängel',
        errorCount: errorsLinked,
        assetType: 'rwa',
      ));
    }

    logs.add('Import abgeschlossen: $sheetsProcessed Blätter, $rwaSystemsImported Anlage(n), $inspectionsCreated Prüfungen, $settingsEvaluated Einstellungen, $errorsLinked Mängel.');

    return RwaImportResult(
      sheetsProcessed: sheetsProcessed,
      rwaSystemsImported: rwaSystemsImported,
      inspectionsCreated: inspectionsCreated,
      settingsEvaluated: settingsEvaluated,
      errorsLinked: errorsLinked,
      warnings: warnings,
      logs: logs,
      doorChanges: doorChanges,
    );
  }

  /// Batch import all RWA excel files in a directory
  static Future<List<RwaImportResult>> importDirectory(Directory dir) async {
    final results = <RwaImportResult>[];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final ext = p.extension(f.path).toLowerCase();
          return ext == '.xlsx' || ext == '.xlsm';
        })
        .toList();

    for (final file in files) {
      final res = await importFromFile(file);
      results.add(res);
    }
    return results;
  }

  static String _getJoinedProp(Map<String, List<String>> map, String key) {
    if (!map.containsKey(key) || map[key]!.isEmpty) return '';
    return map[key]!.join(', ');
  }

  static DateTime? _parseDate(String raw, int fallbackYear) {
    if (raw.isEmpty) return DateTime(fallbackYear, 1, 1);
    // Patterns like DD.MM.YYYY or DD.MM.YY
    final dotPattern = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{2,4})');
    final match = dotPattern.firstMatch(raw);
    if (match != null) {
      final day = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      var yr = int.parse(match.group(3)!);
      if (yr < 100) yr += 2000;
      return DateTime(yr, month, day);
    }
    return DateTime(fallbackYear, 1, 1);
  }

  static Future<void> _registerOptions({
    required String systemType,
    required String centralType,
    required String fireButtonSpec,
    required String smokeDetectorSpec,
    required String actuatorSpec,
    required String ventilationButtonSpec,
    required String emergencyPowerSpec,
    required String co2BottleSpec,
    required String thermalBottleSpec,
    required String rwaFlapSpec,
    required String ventilationFlapSpec,
    required String damperSpec,
  }) async {
    if (systemType.isNotEmpty) await RwaOptionsService.addCustomOption('systemType', systemType);
    if (centralType.isNotEmpty) await RwaOptionsService.addCustomOption('centralType', centralType);
    if (fireButtonSpec.isNotEmpty) await RwaOptionsService.addCustomOption('fireButton', fireButtonSpec);
    if (smokeDetectorSpec.isNotEmpty) await RwaOptionsService.addCustomOption('smokeDetector', smokeDetectorSpec);
    if (actuatorSpec.isNotEmpty) await RwaOptionsService.addCustomOption('actuator', actuatorSpec);
    if (ventilationButtonSpec.isNotEmpty) await RwaOptionsService.addCustomOption('ventilationButton', ventilationButtonSpec);
    if (emergencyPowerSpec.isNotEmpty) await RwaOptionsService.addCustomOption('emergencyPower', emergencyPowerSpec);
    if (co2BottleSpec.isNotEmpty) await RwaOptionsService.addCustomOption('co2Bottles', co2BottleSpec);
    if (thermalBottleSpec.isNotEmpty) await RwaOptionsService.addCustomOption('thermalBottle', thermalBottleSpec);
    if (rwaFlapSpec.isNotEmpty) await RwaOptionsService.addCustomOption('rwaFlaps', rwaFlapSpec);
    if (ventilationFlapSpec.isNotEmpty) await RwaOptionsService.addCustomOption('ventilationFlaps', ventilationFlapSpec);
    if (damperSpec.isNotEmpty) await RwaOptionsService.addCustomOption('dampers', damperSpec);
  }
}
