import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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
}
