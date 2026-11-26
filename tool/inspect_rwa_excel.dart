import 'dart:convert';
import 'dart:io';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:path/path.dart' as p;

void main() {
  final dir = Directory('test/test_data/RWA-Anlagen');
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.xlsx')).toList();

  // 1. Property values: Map<PropertyName, Set<Value>>
  final systemProperties = <String, Set<String>>{};

  // 2. Einrichtung settings: Map<EinrichtungName, Map<Ergebnis, int>>
  final einrichtungen = <String, Set<String>>{};
  final ergebnisValues = <String, int>{};

  // 3. Anmerkungen: List of {file, sheet, einrichtung, ergebnis, anmerkung}
  final anmerkungenList = <Map<String, String>>[];

  // 4. Object addresses and headers
  final objectAddresses = <String>{};
  final monteurList = <String>{};

  final sheetNamesAll = <String, List<String>>{};

  for (final file in files) {
    final fileName = p.basename(file.path);
    final bytes = file.readAsBytesSync();
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);
    sheetNamesAll[fileName] = decoder.tables.keys.toList();

    for (final entry in decoder.tables.entries) {
      final sheetName = entry.key;
      final table = entry.value;

      // Filter out empty or template sheets if they don't have RWA data
      if (table.maxRows < 10) continue;

      // Check if row 0 has Objekt:
      final firstRowFirstCell = table.rows[0].isNotEmpty ? table.rows[0][0]?.toString().trim() : '';
      if (firstRowFirstCell != 'Objekt:' && !sheetName.contains(RegExp(r'\d{4}'))) {
        // Not a standard RWA sheet
        continue;
      }

      int einrichtungHeaderRow = -1;
      for (int r = 0; r < table.maxRows; r++) {
        final rCells = table.rows[r];
        if (rCells.isNotEmpty && rCells[0]?.toString().trim() == 'Einrichtung') {
          einrichtungHeaderRow = r;
          break;
        }
      }

      if (einrichtungHeaderRow == -1) continue;

      // Parse System Properties (rows 0 to einrichtungHeaderRow - 1)
      String currentPropName = '';
      for (int r = 0; r < einrichtungHeaderRow; r++) {
        final rCells = table.rows[r];
        final col0 = rCells.isNotEmpty ? rCells[0]?.toString().trim() ?? '' : '';
        final col1 = rCells.length > 1 ? rCells[1]?.toString().trim() ?? '' : '';

        if (col0.isNotEmpty && col0 != 'Objekt:') {
          currentPropName = col0;
          systemProperties.putIfAbsent(currentPropName, () => <String>{});
          if (col1.isNotEmpty) {
            systemProperties[currentPropName]!.add(col1);
          }
        } else if (col0.isEmpty && col1.isNotEmpty && currentPropName.isNotEmpty) {
          // Additional line for previous property (e.g. multiple CO2-Flaschen entries!)
          systemProperties[currentPropName]!.add(col1);
        } else if (col0 == 'Objekt:' && col1.isNotEmpty) {
          objectAddresses.add(col1);
        }
      }

      // Parse Einrichtung & Anmerkungen (from einrichtungHeaderRow + 1 onwards)
      for (int r = einrichtungHeaderRow + 1; r < table.maxRows; r++) {
        final rCells = table.rows[r];
        final col0 = rCells.isNotEmpty ? rCells[0]?.toString().trim() ?? '' : '';
        final col1 = rCells.length > 1 ? rCells[1]?.toString().trim() ?? '' : '';
        final col2 = rCells.length > 2 ? rCells[2]?.toString().trim() ?? '' : '';

        if (col0 == 'Prüfdatum:' || col0 == 'Prüfdatum' || col0.startsWith('Prüf')) {
          // Bottom metadata reached
          if (col1 == 'Monteur:' || col1 == 'Monteur') {
            if (r + 1 < table.maxRows) {
              final nextR = table.rows[r + 1];
              final m = nextR.length > 1 ? nextR[1]?.toString().trim() ?? '' : '';
              if (m.isNotEmpty) monteurList.add(m);
            }
          }
          break;
        }

        if (col0.isNotEmpty) {
          einrichtungen.putIfAbsent(col0, () => <String>{});
          if (col1.isNotEmpty) {
            einrichtungen[col0]!.add(col1);
            ergebnisValues[col1] = (ergebnisValues[col1] ?? 0) + 1;
          }
          if (col2.isNotEmpty && col2 != '---' && col2 != '-') {
            anmerkungenList.add({
              'file': fileName,
              'sheet': sheetName,
              'einrichtung': col0,
              'ergebnis': col1,
              'anmerkung': col2,
            });
          }
        }
      }
    }
  }

  final report = StringBuffer();
  report.writeln('================================================================');
  report.writeln('  RWA-SYSTEM EXCEL ANALYSIS REPORT');
  report.writeln('================================================================\n');

  report.writeln('1. SHEETS SUMMARY BY FILE:');
  for (final e in sheetNamesAll.entries) {
    report.writeln('  * ${e.key}: ${e.value.join(", ")}');
  }

  report.writeln('\n2. OBJECT ADDRESSES FOUND (${objectAddresses.length}):');
  for (final addr in objectAddresses) {
    report.writeln('  - $addr');
  }

  report.writeln('\n3. RWA SYSTEM PROPERTIES & UNIQUE VALUES:');
  for (final prop in systemProperties.entries) {
    report.writeln('  Property: "${prop.key}" (Count: ${prop.value.length})');
    for (final val in prop.value) {
      report.writeln('    - $val');
    }
  }

  report.writeln('\n4. EINRICHTUNG (INSTALLATION SETTINGS) & OBSERVED RESULTS:');
  for (final einr in einrichtungen.entries) {
    report.writeln('  Setting: "${einr.key}" -> Results: ${einr.value.toList()}');
  }

  report.writeln('\n5. ALL DISTINCT "ERGEBNIS" VALUES & FREQUENCIES:');
  for (final erg in ergebnisValues.entries) {
    report.writeln('  - "${erg.key}": ${erg.value} occurrences');
  }

  report.writeln('\n6. ALL "ANMERKUNGEN" COLLECTED (${anmerkungenList.length}):');
  for (int i = 0; i < anmerkungenList.length; i++) {
    final item = anmerkungenList[i];
    report.writeln('  [${i + 1}] Einrichtung: "${item['einrichtung']}" | Ergebnis: "${item['ergebnis']}"');
    report.writeln('      Text: "${item['anmerkung']}"');
    report.writeln('      Source: ${item['file']} (${item['sheet']})\n');
  }

  File('test/rwa_analysis_full_report.txt').writeAsStringSync(report.toString());
  print('Analysis complete! Report written to test/rwa_analysis_full_report.txt');
}
