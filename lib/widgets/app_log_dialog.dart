import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_logger.dart';

class AppLogDialog extends StatefulWidget {
  const AppLogDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => const AppLogDialog(),
    );
  }

  @override
  State<AppLogDialog> createState() => _AppLogDialogState();
}

class _AppLogDialogState extends State<AppLogDialog> {
  bool _isLoading = true;
  String _rawLogText = '';
  String? _logFilePath;
  int _logFileSize = 0;
  String _searchQuery = '';
  LogLevel? _selectedLevel;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final text = await AppLogger.instance.readAllLogs();
    final path = await AppLogger.instance.getLogFilePath();
    final size = await AppLogger.instance.getLogFileSize();
    if (mounted) {
      setState(() {
        _rawLogText = text;
        _logFilePath = path;
        _logFileSize = size;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleDownload() async {
    final savedPath = await AppLogger.instance.exportLogsSafely();
    if (savedPath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Protokolldatei erfolgreich gespeichert:\n$savedPath'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _handleDownloadToDownloads() async {
    final savedPath = await AppLogger.instance.exportToDownloadsOrPrompt();
    if (savedPath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ In Downloads abgelegt:\n$savedPath'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _handleClearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Protokoll leeren?'),
        content: const Text('Möchten Sie alle bisherigen Logeinträge unwiderruflich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AppLogger.instance.clearLogs();
      await _loadLogs();
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _rawLogText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log-Inhalt in die Zwischenablage kopiert.')),
    );
  }

  List<String> get _filteredLines {
    if (_rawLogText.isEmpty) return [];
    final lines = _rawLogText.split('\n');
    return lines.where((line) {
      if (line.trim().isEmpty) return false;
      if (_selectedLevel != null) {
        final lvlTag = '[${_selectedLevel.toString().split('.').last.toUpperCase()}]';
        if (!line.contains(lvlTag)) return false;
      }
      if (_searchQuery.isNotEmpty) {
        return line.toLowerCase().contains(_searchQuery.toLowerCase());
      }
      return true;
    }).toList();
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredLines;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.receipt_long, color: theme.colorScheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Anwendungsprotokoll (Log-Datei)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _logFilePath != null
                              ? '${_formatFileSize(_logFileSize)} • ${_logFilePath!}'
                              : 'Lade Protokolldaten...',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Aktualisieren',
                    onPressed: _loadLogs,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Kopieren',
                    onPressed: _copyToClipboard,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 16),

              // Access Notice Banner
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.usb, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        Platform.isAndroid
                            ? 'Einfacher USB-Zugriff am PC: Interner Speicher > Android > data > de.gottsberg.wartungstool > files > logs\nOder unten mit 1-Klick direkt in den Download-Ordner Ihres Tablets kopieren.'
                            : 'Log-Speicherort: ${_logFilePath ?? "WartungsTool/logs"} • Direkt aufrufbar oder unten als Datei exportieren.',
                        style: const TextStyle(fontSize: 11, height: 1.25),
                      ),
                    ),
                  ],
                ),
              ),

              // Filter Controls
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Suchen (z. B. Craftnote, Door, Fehler)...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<LogLevel?>(
                    value: _selectedLevel,
                    hint: const Text('Alle Level'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Alle Level')),
                      DropdownMenuItem(value: LogLevel.info, child: Text('INFO')),
                      DropdownMenuItem(value: LogLevel.warn, child: Text('WARN')),
                      DropdownMenuItem(value: LogLevel.error, child: Text('ERROR')),
                      DropdownMenuItem(value: LogLevel.debug, child: Text('DEBUG')),
                    ],
                    onChanged: (lvl) => setState(() => _selectedLevel = lvl),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Log Viewer Box
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade800),
                  ),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? Center(
                              child: Text(
                                _rawLogText.isEmpty
                                    ? 'Keine Log-Einträge vorhanden.'
                                    : 'Keine Einträge für den aktuellen Filter gefunden.',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              ),
                            )
                          : Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              child: ListView.builder(
                                controller: _scrollController,
                                itemCount: filtered.length,
                                itemBuilder: (ctx, i) {
                                  final line = filtered[i];
                                  Color textColor = Colors.white;
                                  if (line.contains('[INFO]')) {
                                    textColor = Colors.lightGreenAccent.shade100;
                                  } else if (line.contains('[WARN]')) {
                                    textColor = Colors.amberAccent;
                                  } else if (line.contains('[ERROR]')) {
                                    textColor = Colors.redAccent.shade100;
                                  } else if (line.contains('[DEBUG]')) {
                                    textColor = Colors.cyanAccent.shade100;
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                                    child: SelectableText(
                                      line,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11.5,
                                        color: textColor,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                ),
              ),

              const SizedBox(height: 12),

              // Footer Actions
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _handleClearLogs,
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    label: const Text('Protokoll leeren', style: TextStyle(color: Colors.red)),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Tooltip(
                        message: 'Kopiert die Log-Datei mit 1 Klick in den öffentlichen Download-Ordner Ihres Geräts',
                        child: FilledButton.icon(
                          onPressed: _handleDownloadToDownloads,
                          icon: const Icon(Icons.download_for_offline, size: 18),
                          label: const Text('In Downloads ablegen'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: 'Freie Speicherortauswahl über Systemdialog',
                        child: OutlinedButton.icon(
                          onPressed: _handleDownload,
                          icon: const Icon(Icons.save_as, size: 16),
                          label: const Text('Speichern unter...'),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Schließen'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

