import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Helper utility to safely save and export files across all platforms (Android, Windows, iOS, macOS, Linux).
/// On Android, this leverages the native Storage Access Framework (SAF) via FilePicker.platform.saveFile.
class FileExportHelper {
  /// Sanitizes a string component for file naming by replacing whitespace,
  /// forbidden filesystem characters, and condensing multiple underscores.
  static String sanitizePathComponent(String? raw, {String fallback = ''}) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    var s = raw.trim();
    // Replace whitespace with underscore
    s = s.replaceAll(RegExp(r'\s+'), '_');
    // Replace forbidden characters (\ / : * ? " < > | , ;) with underscore
    s = s.replaceAll(RegExp(r'[\\/:*?"<>|,;]'), '_');
    // Condense multiple underscores
    s = s.replaceAll(RegExp(r'_+'), '_');
    // Trim leading/trailing underscores or dots
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? fallback : s;
  }

  /// Builds a standard package filename according to the convention:
  /// [Auftrag number]_[Project number]_[Address]_[packageType]_[datetime].db
  ///
  /// Examples:
  /// - To Inspector package:
  ///   25-13610-AB_P-000604_LPS-Museum_inspektion_paket_20260925_101103.db
  /// - To Manager result:
  ///   25-13610-AB_P-000604_LPS-Museum_inspektion_ergebnis_20260925_101103.db
  static String buildPackageFileName({
    String? jobNumber,
    String? projectNumber,
    String? objectAddress,
    required String packageType, // 'inspektion_paket' or 'inspektion_ergebnis'
    DateTime? timestamp,
    String extension = 'db',
  }) {
    final now = timestamp ?? DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);

    final parts = <String>[];

    final safeJob = sanitizePathComponent(jobNumber);
    if (safeJob.isNotEmpty) parts.add(safeJob);

    final safeProj = sanitizePathComponent(projectNumber);
    if (safeProj.isNotEmpty) parts.add(safeProj);

    final safeAddr = sanitizePathComponent(objectAddress);
    if (safeAddr.isNotEmpty) parts.add(safeAddr);

    final safeType = sanitizePathComponent(packageType, fallback: 'inspektion');
    parts.add(safeType);

    parts.add(timeStr);

    final baseName = parts.join('_');
    return extension.isNotEmpty ? '$baseName.$extension' : baseName;
  }
  /// Prompts the user to choose a save destination and saves the file content safely.
  /// 
  /// - [defaultFileName]: Pre-filled file name in the system file picker (e.g. 'inspektion_ergebnis_2026.db').
  /// - [dialogTitle]: Title displayed on the file picker dialog.
  /// - [sourceFile]: Optional local file to read bytes from.
  /// - [fileBytes]: Optional explicit byte data to save.
  /// - [allowedExtensions]: List of allowed extensions (without dot, e.g. ['db', 'xlsx', 'pdf']).
  /// 
  /// Returns the saved destination path or string identifier, or `null` if the user cancelled the dialog.
  static Future<String?> saveFileSafely({
    required String defaultFileName,
    String dialogTitle = 'Datei speichern unter',
    File? sourceFile,
    Uint8List? fileBytes,
    List<String>? allowedExtensions,
  }) async {
    Uint8List? bytes = fileBytes;
    if (bytes == null && sourceFile != null && await sourceFile.exists()) {
      bytes = await sourceFile.readAsBytes();
    }

    final String? selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: defaultFileName,
      type: (allowedExtensions != null && allowedExtensions.isNotEmpty)
          ? FileType.custom
          : FileType.any,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
    );

    if (selectedPath == null) {
      return null; // User dismissed or cancelled the save dialog
    }

    // On desktop platforms (Windows, Linux, macOS) or certain Android targets where saveFile
    // returns a physical filesystem path but doesn't write bytes automatically:
    if (bytes != null && selectedPath.isNotEmpty) {
      try {
        final targetFile = File(selectedPath);
        if (!await targetFile.exists() || (await targetFile.length()) == 0) {
          await targetFile.writeAsBytes(bytes, flush: true);
        }
      } catch (e) {
        debugPrint('FileExportHelper target write notice: $e');
      }
    }

    return selectedPath;
  }

  /// Creates a temporary file path inside the system temporary directory.
  static Future<String> getTempFilePath(String fileName) async {
    final tempDir = await getTemporaryDirectory();
    return p.join(tempDir.path, fileName);
  }

  /// Checks whether all doors in [doors] are marked as processed/inspected.
  /// If any doors are unprocessed, prompts the user with an alert dialog listing the specific doors
  /// and asks if they want to export anyway or continue editing.
  /// Returns `true` if export should proceed, `false` if user cancelled to correct the issue.
  static Future<bool> confirmUnprocessedDoors({
    required BuildContext context,
    required List<dynamic> doors,
    required Map<int, String> statuses,
    String actionName = 'Paket-Export',
  }) async {
    if (doors.isEmpty) return true;

    final List<Map<String, String>> unprocessed = [];
    for (final d in doors) {
      int? doorId;
      String doorNum = '';
      String floor = '';
      String roomDesig = '';
      String alias = '';

      if (d is Map) {
        doorId = d['id'] as int? ?? d['doorId'] as int?;
        doorNum = (d['doorNumber'] ?? d['pos'] ?? '').toString();
        floor = (d['floor'] ?? '').toString();
        roomDesig = (d['roomDesignation'] ?? '').toString();
        alias = (d['doorAlias'] ?? d['provisionalAlias'] ?? '').toString();
      } else {
        doorId = d.id as int?;
        doorNum = d.doorNumber?.toString() ?? d.pos?.toString() ?? '';
        floor = d.floor?.toString() ?? '';
        roomDesig = d.roomDesignation?.toString() ?? '';
        alias = d.doorAlias?.toString() ?? d.provisionalAlias?.toString() ?? '';
      }

      final statusStr = (doorId != null ? statuses[doorId] : null) ?? (d is Map ? d['status']?.toString() : null) ?? '';
      final s = statusStr.trim().toLowerCase();
      final isProcessed = s == 'inspected' ||
          s == 'geprüft' ||
          s == 'completed' ||
          s == 'passed' ||
          s == 'failed' ||
          s == 'done' ||
          s == 'bearbeitet';

      if (!isProcessed) {
        unprocessed.add({
          'doorNumber': doorNum.isNotEmpty ? doorNum : (alias.isNotEmpty ? alias : 'Ohne Nummer'),
          'floor': floor,
          'room': roomDesig,
          'alias': alias,
        });
      }
    }

    if (unprocessed.isEmpty) {
      return true; // All doors are processed
    }

    // Prompt user
    final bool? proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 28),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Unbearbeitete Türen vorhanden',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Text(
                  'In diesem Auftrag wurden noch nicht alle Türen als "Geprüft" markiert (${unprocessed.length} von ${doors.length} Türen offen).',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Folgende Türen sind noch nicht geprüft / offen:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade50,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: unprocessed.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = unprocessed[index];
                    final loc = [if (item['floor']!.isNotEmpty) item['floor']!, if (item['room']!.isNotEmpty) item['room']!].join(' | ');
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.pending_actions, color: Colors.orange, size: 20),
                      title: Text(
                        'Tür ${item['doorNumber']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: Text(
                        [if (loc.isNotEmpty) loc, if (item['alias']!.isNotEmpty) 'Alias: ${item['alias']}'].join(' • '),
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Möchten Sie das Paket trotzdem exportieren oder die Prüfung fortsetzen?',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen / Weiter prüfen'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Trotzdem exportieren'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    return proceed ?? false;
  }
}
