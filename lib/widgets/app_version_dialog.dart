import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/app_version_service.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../utils/file_export_helper.dart';

class AppVersionDialog extends StatefulWidget {
  final bool isManager;

  const AppVersionDialog({
    super.key,
    this.isManager = false,
  });

  static Future<void> show(BuildContext context, {bool isManager = false}) {
    return showDialog(
      context: context,
      builder: (context) => AppVersionDialog(isManager: isManager),
    );
  }

  @override
  State<AppVersionDialog> createState() => _AppVersionDialogState();
}

class _AppVersionDialogState extends State<AppVersionDialog> {
  bool _isLoading = false;
  String? _statusMessage;

  Future<void> _handleBackup() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Datenbank wird gesichert...';
    });

    String? tempExportPath;
    try {
      final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final roleName = widget.isManager ? 'Manager' : 'Inspector';
      final defaultFileName = 'Backup_WartungsTool_${roleName}_$nowStr.db';

      tempExportPath = await FileExportHelper.getTempFilePath(defaultFileName);

      if (widget.isManager) {
        await DatabaseService.exportMasterDb(tempExportPath);
      } else {
        await LocalDatabaseService.exportWorkingDb(tempExportPath);
      }

      final tempFile = File(tempExportPath);
      final savedPath = await FileExportHelper.saveFileSafely(
        defaultFileName: defaultFileName,
        dialogTitle: 'Datenbank-Backup speichern unter',
        sourceFile: tempFile,
        allowedExtensions: ['db'],
      );

      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Datenbank-Backup erfolgreich gespeichert:\n$savedPath'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup fehlgeschlagen: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (tempExportPath != null) {
        try {
          final tf = File(tempExportPath);
          if (await tf.exists()) await tf.delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
      }
    }
  }

  Future<void> _handleRestore() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Datenbank-Sicherung (.db) auswählen',
        type: FileType.custom,
        allowedExtensions: ['db'],
      );

      if (result == null || result.files.isEmpty) return;
      final selectedPath = result.files.single.path;
      if (selectedPath == null || selectedPath.isEmpty) return;

      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('Datenbank wiederherstellen?'),
            ],
          ),
          content: Text(
            'Achtung: Die aktuelle ${widget.isManager ? "Manager-Datenbank" : "Prüfer-Datenbank"} wird vollständig durch die ausgewählte Sicherungsdatei ersetzt.\n\n'
            'Datei: ${File(selectedPath).uri.pathSegments.last}\n\n'
            'Möchten Sie den Wiederherstellungsvorgang fortsetzen?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Wiederherstellen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() {
        _isLoading = true;
        _statusMessage = 'Datenbank wird wiederhergestellt...';
      });

      if (widget.isManager) {
        await DatabaseService.importMasterDb(selectedPath);
      } else {
        await LocalDatabaseService.importWorkingDb(selectedPath);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Datenbank erfolgreich wiederhergestellt! Bitte Ansicht aktualisieren.'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pop(context); // Close dialog upon successful restore
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wiederherstellung fehlgeschlagen: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final platformName = AppVersionService.getPlatformName(isManager: widget.isManager);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            widget.isManager ? Icons.desktop_windows : Icons.phone_android,
            color: Theme.of(context).colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 12),
          const Text('App-Informationen'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WartungsTool - Türinspektion',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(
                      'Anwendung:',
                      widget.isManager ? 'Manager-Portal ($platformName)' : 'Techniker-App ($platformName)',
                    ),
                    const Divider(height: 16),
                    _buildInfoRow('Plattform-Build:', '$platformName Version'),
                    const SizedBox(height: 6),
                    _buildInfoRow('Version:', 'v${AppVersionService.fullVersion}'),
                    const SizedBox(height: 6),
                    _buildInfoRow('Build-Datum:', AppVersionService.buildDate),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Datenbank-Verwaltung',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Sichern Sie die vollständige lokale Datenbank als .db Datei oder stellen Sie einen früheren Sicherungsstand wieder her.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),
              if (_isLoading) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statusMessage ?? 'Bitte warten...',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _handleBackup,
                        icon: const Icon(Icons.backup_outlined, size: 18),
                        label: const Text('Backup erstellen'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _handleRestore,
                        icon: const Icon(Icons.restore_page_outlined, size: 18),
                        label: const Text('Wiederherstellen'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 13),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
