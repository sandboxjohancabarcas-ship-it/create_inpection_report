import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:wartungstool/pages/door_conflict_review_page.dart';
import 'package:wartungstool/services/batch_migration_service.dart';
import 'package:wartungstool/widgets/import_report_dialog.dart';

class BatchMigrationDialog extends StatefulWidget {
  final VoidCallback? onMigrationCompleted;

  const BatchMigrationDialog({super.key, this.onMigrationCompleted});

  static Future<void> show(BuildContext context, {VoidCallback? onMigrationCompleted}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BatchMigrationDialog(onMigrationCompleted: onMigrationCompleted),
    );
  }

  @override
  State<BatchMigrationDialog> createState() => _BatchMigrationDialogState();
}

class _BatchMigrationDialogState extends State<BatchMigrationDialog> {
  bool _isProcessing = false;
  int _currentFileIndex = 0;
  int _totalFilesCount = 0;
  String _currentFileName = '';

  Future<void> _handlePickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['db', 'db3', 'wartung', 'sqlite', 'xlsx', 'xls', 'xlsm', 'xlms', 'csv', 'pdf'],
      );

      if (result != null && result.files.isNotEmpty) {
        final selectedFiles = result.files
            .where((f) => f.path != null)
            .map((f) => File(f.path!))
            .toList();

        await _startMigration(selectedFiles);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler bei der Dateiauswahl: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handlePickFolder() async {
    try {
      final String? folderPath = await FilePicker.platform.getDirectoryPath();

      if (folderPath != null && folderPath.isNotEmpty) {
        final folderFiles = BatchMigrationService.getFilesFromDirectory(folderPath);

        if (folderFiles.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Der ausgewählte Ordner enthält keine Dateien.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        await _startMigration(folderFiles);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler bei der Ordnerauswahl: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _startMigration(List<File> files) async {
    setState(() {
      _isProcessing = true;
      _totalFilesCount = files.length;
      _currentFileIndex = 0;
      _currentFileName = 'Vorbereitung...';
    });

    final result = await BatchMigrationService.migrateFiles(
      files,
      onProgress: (current, total, filename) {
        if (mounted) {
          setState(() {
            _currentFileIndex = current;
            _totalFilesCount = total;
            _currentFileName = filename;
          });
        }
      },
    );

    if (!mounted) return;

    Navigator.pop(context); // Close migration dialog

    widget.onMigrationCompleted?.call();

    // Route door conflicts (property/datatype mismatch) to review page first if present
    if (result.doorConflicts.isNotEmpty && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => DoorConflictReviewPage(
            conflicts: result.doorConflicts,
          ),
        ),
      );
    }

    // Show Import Report Dialog with itemized per-file results
    if (mounted) {
      await ImportReportDialog.show(context, result.aggregatedReport);
    }

    if (result.skippedFilesCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.compliantFilesProcessed} Datei(en) migriert. '
            '${result.skippedFilesCount} nicht-konforme/ungültige Datei(en) übersprungen.',
          ),
          backgroundColor: Colors.blueGrey,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.unarchive, color: Colors.blue),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Daten-Migration & Import',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: _isProcessing
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Migration läuft: Datei $_currentFileIndex von $_totalFilesCount',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentFileName,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _totalFilesCount > 0 ? _currentFileIndex / _totalFilesCount : 0.0,
                    backgroundColor: Colors.grey.shade200,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Es werden alle konformen Dateien (.db, .xlsx, .csv, .pdf) automatisch erkannt und in die Haupt-DB integriert.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Wählen Sie eine der folgenden Optionen. Alle konformen Dateiformate (.db, .xlsx, .csv, .pdf) werden automatisch migriert:',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 20),
                  InkWell(
                    onTap: _handlePickFiles,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blue.shade200),
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.blue.shade50.withValues(alpha: 0.4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.file_present, color: Colors.blue, size: 28),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Dateien auswählen',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Einzelne oder mehrere Dateien wählen (Strg + Klick)',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _handlePickFolder,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.teal.shade200),
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.teal.shade50.withValues(alpha: 0.4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_copy, color: Colors.teal, size: 28),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Ganzen Ordner auswählen',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Alle Unterordner nach konformen Dateien durchsuchen',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (!_isProcessing)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
      ],
    );
  }
}
