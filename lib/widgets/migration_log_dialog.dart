import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/integrity_report.dart';
import '../services/database_service.dart';

class MigrationLogDialog extends StatefulWidget {
  const MigrationLogDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const MigrationLogDialog(),
    );
  }

  @override
  State<MigrationLogDialog> createState() => _MigrationLogDialogState();
}

class _MigrationLogDialogState extends State<MigrationLogDialog> {
  final TextEditingController _filterController = TextEditingController();
  String _logContent = 'Lade Migration-Protokoll...';
  List<String> _logLines = [];
  bool _isLoading = true;
  bool _isRepairing = false;
  IntegrityReport? _integrityReport;

  @override
  void initState() {
    super.initState();
    _loadLogFile();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _loadLogFile() async {
    setState(() => _isLoading = true);
    try {
      final file = File('migration_protocol.log');
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = content.split('\n');
        setState(() {
          _logContent = content;
          _logLines = lines;
          _isLoading = false;
        });
      } else {
        setState(() {
          _logContent = 'Kein Migrations-Protokoll (migration_protocol.log) in dieser Sitzung erstellt.';
          _logLines = [_logContent];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _logContent = 'Fehler beim Lesen des Protokolls: $e';
        _logLines = [_logContent];
        _isLoading = false;
      });
    }
  }

  Future<void> _runIntegrityCheck() async {
    setState(() => _isRepairing = true);
    try {
      final report = await DatabaseService.verifyIntegrity();
      if (mounted) {
        setState(() {
          _integrityReport = report;
          _isRepairing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(report.isHealthy
                ? 'Datenbank ist zu 100% konsistent und gesund.'
                : 'Reparatur abgeschlossen: ${report.repairLogs.join(" • ")}'),
            backgroundColor: report.isHealthy ? Colors.green : Colors.amber.shade900,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRepairing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler bei Integritätsprüfung: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _copyLogsToClipboard() {
    Clipboard.setData(ClipboardData(text: _logContent));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Protokoll in Zwischenablage kopiert.'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String query = _filterController.text.toLowerCase().trim();
    final List<String> filteredLines = query.isEmpty
        ? _logLines
        : _logLines.where((l) => l.toLowerCase().contains(query)).toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.published_with_changes, color: Colors.deepPurple, size: 28),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Migrations-Audit & Integrität', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Protokollinspektor & Selbstreparatur-Tool', style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            tooltip: 'Protokoll kopieren',
            onPressed: _copyLogsToClipboard,
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: 520,
        child: Column(
          children: [
            // Integrity Quick Banner
            if (_integrityReport != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _integrityReport!.isHealthy ? Colors.green.shade50 : Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _integrityReport!.isHealthy ? Colors.green : Colors.amber,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _integrityReport!.isHealthy ? Icons.check_circle : Icons.healing,
                      color: _integrityReport!.isHealthy ? Colors.green : Colors.amber.shade900,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _integrityReport!.isHealthy ? 'Datenbank-Status: KONSISTENT & GESUND' : 'Datenbank-Reparatur durchgeführt',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _integrityReport!.isHealthy ? Colors.green.shade900 : Colors.amber.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_integrityReport!.totalInspections} Aufträge • ${_integrityReport!.totalDoors} Türen • ${_integrityReport!.totalJunctions} Verknüpfungen • ${_integrityReport!.totalErrors} Mängel',
                            style: const TextStyle(fontSize: 11),
                          ),
                          if (_integrityReport!.repairLogs.isNotEmpty)
                            Text(
                              _integrityReport!.repairLogs.join('\n'),
                              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Action Toolbar
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _filterController,
                    decoration: const InputDecoration(
                      hintText: 'Protokoll durchsuchen (z.B. Kunde, Tür, Mangel)...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _isRepairing ? null : _runIntegrityCheck,
                  icon: _isRepairing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.health_and_safety),
                  label: Text(_isRepairing ? 'Prüfe...' : 'Integrität prüfen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Log Console View
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                    : ListView.builder(
                        itemCount: filteredLines.length,
                        itemBuilder: (context, index) {
                          final line = filteredLines[index];
                          Color textColor = Colors.greenAccent;
                          if (line.contains('WARNUNG') || line.contains('HINWEIS') || line.contains('Repariert')) {
                            textColor = Colors.amberAccent;
                          } else if (line.contains('FEHLER') || line.contains('ERROR')) {
                            textColor = Colors.redAccent;
                          }

                          return SelectableText(
                            line,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: textColor,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}
