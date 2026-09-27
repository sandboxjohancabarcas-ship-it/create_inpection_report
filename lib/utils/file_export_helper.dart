import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Helper utility to safely save and export files across all platforms (Android, Windows, iOS, macOS, Linux).
/// On Android, this leverages the native Storage Access Framework (SAF) via FilePicker.platform.saveFile.
class FileExportHelper {
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
