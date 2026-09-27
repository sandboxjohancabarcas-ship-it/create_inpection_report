import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'file_export_helper.dart';

/// Result of checking SQLite package compatibility before import.
class CompatibilityCheckResult {
  final bool hasVersionMismatch;
  final int? packageVersion;
  final int? targetVersion;
  final List<String> legacyColumns;
  final List<String> missingColumns;
  final String details;

  const CompatibilityCheckResult({
    required this.hasVersionMismatch,
    this.packageVersion,
    this.targetVersion,
    this.legacyColumns = const [],
    this.missingColumns = const [],
    this.details = '',
  });
}

/// Utility for diagnosing, warning about version mismatches, and exporting
/// comprehensive error diagnostic text files to hand out to developers.
class ErrorLogExportHelper {
  /// Analyzes an incoming .db package for version and schema differences.
  static Future<CompatibilityCheckResult> checkPackageCompatibility(
    String packagePath, {
    int targetVersion = 16,
  }) async {
    if (!packagePath.toLowerCase().endsWith('.db') &&
        !packagePath.toLowerCase().endsWith('.sqlite') &&
        !packagePath.toLowerCase().endsWith('.wartung')) {
      return const CompatibilityCheckResult(hasVersionMismatch: false);
    }

    final file = File(packagePath);
    if (!await file.exists()) {
      return const CompatibilityCheckResult(hasVersionMismatch: false);
    }

    Database? packageDb;
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      packageDb = await openDatabase(packagePath, readOnly: true);

      final versionResult = await packageDb.rawQuery('PRAGMA user_version');
      final int packageVersion = versionResult.isNotEmpty
          ? (versionResult.first.values.first as int? ?? 0)
          : 0;

      final tables = await packageDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      final List<String> legacyCols = [];
      final List<String> missingCols = [];

      if (tableNames.contains('doors')) {
        final doorColsRaw = await packageDb.rawQuery('PRAGMA table_info(doors)');
        final doorCols = doorColsRaw.map((c) => c['name'] as String).toSet();

        if (doorCols.contains('lintelHeightUnder1m')) legacyCols.add('doors.lintelHeightUnder1m (veraltet)');
        if (doorCols.contains('lintelHeightOver1m')) legacyCols.add('doors.lintelHeightOver1m (veraltet)');
        if (doorCols.contains('customerName')) legacyCols.add('doors.customerName (Metadaten in Tür veraltet)');

        if (!doorCols.contains('lintelHeightInsideOver1m')) missingCols.add('doors.lintelHeightInsideOver1m');
        if (!doorCols.contains('lintelHeightOutsideOver1m')) missingCols.add('doors.lintelHeightOutsideOver1m');
        if (!doorCols.contains('lintelHeightInsideValue')) missingCols.add('doors.lintelHeightInsideValue');
      }

      if (tableNames.contains('inspections')) {
        final inspColsRaw = await packageDb.rawQuery('PRAGMA table_info(inspections)');
        final inspCols = inspColsRaw.map((c) => c['name'] as String).toSet();
        if (!inspCols.contains('isLocked')) missingCols.add('inspections.isLocked');
      }

      // Modern schema packages from inspector (v16+) or master (v26+) with no legacy columns are compatible
      final bool isModernSchema = packageVersion >= 16 && legacyCols.isEmpty;
      final bool hasMismatch = legacyCols.isNotEmpty ||
          (!isModernSchema && packageVersion > 0 && packageVersion < targetVersion);

      return CompatibilityCheckResult(
        hasVersionMismatch: hasMismatch,
        packageVersion: packageVersion,
        targetVersion: targetVersion,
        legacyColumns: legacyCols,
        missingColumns: missingCols,
        details: 'Paket-Version: v$packageVersion | Ziel-Version: v$targetVersion',
      );
    } catch (e) {
      debugPrint('[ErrorLogExportHelper] Compatibility check warning: $e');
      return const CompatibilityCheckResult(hasVersionMismatch: false);
    } finally {
      await packageDb?.close();
    }
  }

  /// Shows a pre-import warning dialog if a version incompatibility is detected.
  /// Returns `true` if the user wants to continue the import, `false` otherwise.
  static Future<bool> showVersionWarningDialog(
    BuildContext context, {
    required CompatibilityCheckResult compatibility,
    required String fileName,
  }) async {
    if (!compatibility.hasVersionMismatch) return true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Versionsinkompatibilität erkannt',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Die Datei "$fileName" stammt von einer abweichenden oder älteren App-Version.',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Details zur Abweichung:',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                    ),
                    const SizedBox(height: 4),
                    if (compatibility.legacyColumns.isNotEmpty) ...[
                      Text('• Veraltete Felder: ${compatibility.legacyColumns.join(', ')}'),
                    ],
                    if (compatibility.packageVersion != null && compatibility.packageVersion! > 0) ...[
                      Text('• Paket-Schema: v${compatibility.packageVersion} (Aktuell: v${compatibility.targetVersion})'),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'Empfehlung: Bitte gleichen Sie die App-Versionen zwischen Prüfer (Tablet) und Manager (Desktop) ab (Update durchführen).',
                      style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Das System wird versuchen, die Daten kompatibel zu konvertieren. Manche veraltete Felder können jedoch nicht direkt übernommen werden.\n\nMöchten Sie den Import trotzdem fortsetzen?',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Trotzdem importieren'),
          ),
        ],
      ),
    );

    return result == true;
  }

  /// Builds a comprehensive text error report for developers.
  static Future<String> generateErrorReport({
    required dynamic error,
    required StackTrace stackTrace,
    String? packagePath,
    String operation = 'Import/Merge Vorgang',
  }) async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final buffer = StringBuffer();

    buffer.writeln('================================================================================');
    buffer.writeln('WARTUNGSTOOL - DIAGNOSE & FEHLERBERICHT FÜR ENTWICKLER');
    buffer.writeln('================================================================================');
    buffer.writeln('Erstellungszeitpunkt : $dateStr');
    buffer.writeln('Betriebssystem       : ${Platform.operatingSystem} (${Platform.operatingSystemVersion})');
    buffer.writeln('Vorgang              : $operation');
    buffer.writeln('');

    buffer.writeln('--------------------------------------------------------------------------------');
    buffer.writeln('1. FEHLERBESCHREIBUNG');
    buffer.writeln('--------------------------------------------------------------------------------');
    buffer.writeln('Fehlertyp   : ${error.runtimeType}');
    buffer.writeln('Fehlertext  : $error');
    buffer.writeln('');

    buffer.writeln('--------------------------------------------------------------------------------');
    buffer.writeln('2. URSACHEN-ANALYSE & SCHNELLDIAGNOSE');
    buffer.writeln('--------------------------------------------------------------------------------');
    final errStr = error.toString();
    if (errStr.contains('no such column')) {
      buffer.writeln('HINWEIS: Schema-Inkompatibilität festgestellt.');
      buffer.writeln('Ein SQL-Befehl referenzierte eine Spalte, die in der Zieltabelle nicht existiert.');
      buffer.writeln('Dies tritt typischerweise auf, wenn ein Prüfer-Tablet ein altes/neues Schema exportiert');
      buffer.writeln('und der Manager versucht, Daten mit abweichenden Spalten direkt einzuspielen.');
    } else if (errStr.contains('no such table')) {
      buffer.writeln('HINWEIS: Fehlende Tabelle im SQLite Paket.');
    } else if (errStr.contains('UNIQUE constraint failed')) {
      buffer.writeln('HINWEIS: Eindeutigkeits-Konflikt bei Schlüsselwerten (z. B. Tür-Alias oder Fehler-Code).');
    } else {
      buffer.writeln('HINWEIS: Unerwarteter Laufzeitfehler während der Ausführung.');
    }
    buffer.writeln('');

    if (packagePath != null && packagePath.isNotEmpty) {
      buffer.writeln('--------------------------------------------------------------------------------');
      buffer.writeln('3. PAKET-DATEI INFORMATIONEN');
      buffer.writeln('--------------------------------------------------------------------------------');
      buffer.writeln('Dateipfad: $packagePath');
      try {
        final file = File(packagePath);
        if (await file.exists()) {
          final size = await file.length();
          final modified = await file.lastModified();
          buffer.writeln('Dateigröße  : $size Bytes');
          buffer.writeln('Geändert am : $modified');

          // Try inspecting SQLite structure
          if (packagePath.toLowerCase().endsWith('.db') ||
              packagePath.toLowerCase().endsWith('.sqlite') ||
              packagePath.toLowerCase().endsWith('.wartung')) {
            Database? pkgDb;
            try {
              pkgDb = await openDatabase(packagePath, readOnly: true);
              final verResult = await pkgDb.rawQuery('PRAGMA user_version');
              buffer.writeln('Paket user_version: ${verResult.isNotEmpty ? verResult.first.values.first : "N/A"}');

              final tables = await pkgDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
              buffer.writeln('Vorhandene Tabellen: ${tables.map((t) => t['name']).join(', ')}');

              for (final t in ['doors', 'inspections', 'inspection_door_errors']) {
                if (tables.any((tbl) => tbl['name'] == t)) {
                  final cols = await pkgDb.rawQuery('PRAGMA table_info($t)');
                  final colNames = cols.map((c) => c['name']).toList();
                  buffer.writeln('Spalten in "$t": ${colNames.join(', ')}');
                }
              }
            } catch (inspectError) {
              buffer.writeln('Paket-Inspektions-Hinweis: $inspectError');
            } finally {
              await pkgDb?.close();
            }
          }
        } else {
          buffer.writeln('Datei existiert nicht auf dem Dateisystem.');
        }
      } catch (fileErr) {
        buffer.writeln('Konnte Dateidetails nicht lesen: $fileErr');
      }
      buffer.writeln('');
    }

    buffer.writeln('--------------------------------------------------------------------------------');
    buffer.writeln('4. STACK TRACE');
    buffer.writeln('--------------------------------------------------------------------------------');
    buffer.writeln(stackTrace.toString());
    buffer.writeln('');
    buffer.writeln('================================================================================');
    buffer.writeln('ENDE DES FEHLERBERICHTS');
    buffer.writeln('================================================================================');

    return buffer.toString();
  }

  /// Catches an exception, shows an alert dialog to the user with options to save
  /// the detailed error exception file via FilePicker.
  static Future<void> handleExceptionWithDialog(
    BuildContext context, {
    required dynamic error,
    required StackTrace stackTrace,
    String? packagePath,
    String operation = 'Import Vorgang',
  }) async {
    final reportText = await generateErrorReport(
      error: error,
      stackTrace: stackTrace,
      packagePath: packagePath,
      operation: operation,
    );

    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Import-Fehler aufgetreten',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Beim Verarbeiten der Datei ist ein Fehler aufgetreten:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  error.toString(),
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ein detaillierter Diagnosebericht für Entwickler wurde erstellt. '
                'Sie können diesen Bericht jetzt als Textdatei exportieren und zur Fehleranalyse weiterleiten.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Schließen'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.file_download),
            label: const Text('Fehlerbericht speichern (.txt)'),
            onPressed: () async {
              final timestamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
              final defaultFileName = 'wartungstool-fehlerbericht-$timestamp.txt';
              
              final savedPath = await FileExportHelper.saveFileSafely(
                defaultFileName: defaultFileName,
                dialogTitle: 'Fehlerbericht für Entwickler speichern',
                fileBytes: Uint8List.fromList(utf8.encode(reportText)),
                allowedExtensions: ['txt', 'log'],
              );

              if (dialogCtx.mounted) {
                Navigator.pop(dialogCtx);
                if (savedPath != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Fehlerbericht gespeichert: $savedPath'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
