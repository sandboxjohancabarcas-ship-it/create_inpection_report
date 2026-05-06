import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:create_inpection_report/models/error_catalog.dart';
import 'package:create_inpection_report/services/database_service.dart';
import 'package:create_inpection_report/pages/conflict_review_page.dart';

class BulkErrorImportPage extends StatefulWidget {
  const BulkErrorImportPage({super.key});

  @override
  _BulkErrorImportPageState createState() => _BulkErrorImportPageState();
}

class _BulkErrorImportPageState extends State<BulkErrorImportPage> {
  final TextEditingController _textController = TextEditingController();
  bool _isImporting = false;
  int _importedCount = 0;
  int _skippedCount = 0;
  final List<String> _importLog = [];
  final List<ImportConflict> _importConflicts = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fehlerkatalog - Bulk Import'),
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: _showImportHelp,
            tooltip: 'Import-Hilfe',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
            // Import Options
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Import-Optionen',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _importFromText,
                            icon: Icon(Icons.text_fields),
                            label: Text('Text-Import'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _importFromFile,
                            icon: Icon(Icons.file_upload),
                            label: Text('Datei-Import'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _importFromExcel,
                            icon: Icon(Icons.table_chart),
                            label: Text('Excel/CSV'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _clearCatalog,
                            icon: Icon(Icons.clear_all),
                            label: Text('Katalog leeren'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Text Input Area
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fehler-Daten (Format: Code|Beschreibung|Kategorie|Schwere|Empfehlung|Norm)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    SizedBox(height: 8),
                    SizedBox(
                      height: 260,
                      child: TextField(
                        controller: _textController,
                        maxLines: null,
                        expands: true,
                        decoration: InputDecoration(
                          hintText: 'Beispiel:\n'
                              '1.1|Türbeschlag beschädigt|Türbeschlag|medium|Türbeschlag austauschen|DIN 18095\n'
                              '2.1|Schloss defekt|Schloss|high|Schloss austauschen|DIN 18251\n'
                              '3.1|Dichtung undicht|Bodenbelag|low|Dichtung ersetzen|',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        style: TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Import Actions
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isImporting ? null : _parseAndImport,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _isImporting
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                      SizedBox(width: 8),
                                      Text('Importiere...'),
                                    ],
                                  )
                                : Text('Importieren'),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _clearText,
                            child: Text('Text löschen'),
                          ),
                        ),
                      ],
                    ),
                    
                    if (_importedCount > 0 || _skippedCount > 0) ...[
                      SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatCard('Importiert', _importedCount, Colors.green),
                          _buildStatCard('Übersprungen', _skippedCount, Colors.orange),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            // Import Log
            if (_importLog.isNotEmpty) ...[
              SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Import-Protokoll',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      SizedBox(height: 8),
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ListView.builder(
                          itemCount: _importLog.length,
                          itemBuilder: (context, index) {
                            final log = _importLog[index];
                            final isError = log.startsWith('FEHLER:');
                            return Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              child: Text(
                                log,
                                style: TextStyle(
                                  color: isError ? Colors.red : Colors.green,
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_importConflicts.isNotEmpty) ...[
              SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Konflikte (Manager Review)',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final resolved = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ConflictReviewPage(conflicts: _importConflicts),
                                ),
                              );
                              if (resolved == true) {
                                // Conflicts were resolved, clear the list and refresh
                                setState(() {
                                  _importConflicts.clear();
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Konflikte erfolgreich gelöst'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                            icon: Icon(Icons.edit, size: 16),
                            label: Text('Lösen'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ListView.builder(
                          itemCount: _importConflicts.length,
                          itemBuilder: (context, index) {
                            final conflict = _importConflicts[index];
                            return Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(
                                '${conflict.code}: ${conflict.reason}',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    },
  ),
  ),
  ),
);
  }

  Widget _buildStatCard(String label, int count, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  void _showImportHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Import-Formate'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '1. Text-Import:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Format: Code|Beschreibung|Kategorie|Schwere|Empfehlung|Norm'),
              Text('Trennzeichen: | (Pipe)'),
              SizedBox(height: 16),
              
              Text(
                '2. Datei-Import:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Unterstützte Formate: .txt, .csv'),
              Text('Format: Text mit Pipe-Trennung'),
              SizedBox(height: 16),
              
              Text(
                '3. Schweregrade:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('• low - Niedrig'),
              Text('• medium - Mittel'),
              Text('• high - Hoch'),
              Text('• critical - Kritisch'),
              SizedBox(height: 16),
              
              Text(
                'Beispiel:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Container(
                padding: EdgeInsets.all(8),
                color: Colors.grey.shade100,
                child: Text(
                  '1.1|Türbeschlag beschädigt|Türbeschlag|medium|Türbeschlag austauschen|DIN 18095\n'
                  '2.1|Schloss defekt|Schloss|high|Schloss austauschen|DIN 18251',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Schließen'),
          ),
        ],
      ),
    );
  }

  void _importFromText() {
    // Focus on text input
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _importFromFile() async {
    try {
      // Use native file picker through clipboard for now
      final data = await Clipboard.getData('text/plain');
      if (data != null && data.text != null) {
        _textController.text = data.text!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Text aus Zwischenablage geladen')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kein Text in Zwischenablage gefunden. Bitte kopieren Sie den Text und versuchen Sie es erneut.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Import: $e')),
      );
    }
  }

  void _importFromExcel() async {
    // For now, treat as CSV
    _importFromFile();
  }

  void _clearText() {
    _textController.clear();
    setState(() {
      _importLog.clear();
      _importConflicts.clear();
      _importedCount = 0;
      _skippedCount = 0;
    });
  }

  void _clearCatalog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Katalog leeren'),
        content: Text('Möchten Sie den gesamten Fehlerkatalog wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Löschen'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        await DatabaseService.clearErrorCatalog();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehlerkatalog wurde geleert')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Leeren: $e')),
        );
      }
    }
  }

  void _parseAndImport() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bitte geben Sie Fehler-Daten ein')),
      );
      return;
    }

    setState(() {
      _isImporting = true;
      _importLog.clear();
      _importConflicts.clear();
      _importedCount = 0;
      _skippedCount = 0;
    });

    try {
      final lines = text.split('\n');
      final errors = <ErrorCatalog>[];
      int parseSkippedCount = 0;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        try {
          final parts = line.split('|');
          if (parts.length < 2) {
            _importLog.add('FEHLER Zeile ${i + 1}: Nicht genügend Felder');
            parseSkippedCount++;
            continue;
          }

          final error = ErrorCatalog(
            code: parts[0].trim(),
            description: parts[1].trim(),
            category: parts.length > 2 ? parts[2].trim() : 'Allgemein',
            severity: parts.length > 3 ? _normalizeSeverity(parts[3].trim()) : 'medium',
            recommendation: parts.length > 4 ? parts[4].trim() : '',
            normReference: parts.length > 5 ? parts[5].trim() : '',
          );

          errors.add(error);
          _importLog.add('OK: ${error.code} - ${error.description}');
        } catch (e) {
          _importLog.add('FEHLER Zeile ${i + 1}: $e');
          parseSkippedCount++;
        }
      }

      final result = await DatabaseService.mergeErrorCatalog(errors);
      _importedCount = result.insertedCount;
      _skippedCount = parseSkippedCount + result.duplicateCount + result.conflicts.length;
      _importConflicts.addAll(result.conflicts);

      if (result.duplicateCount > 0) {
        _importLog.add('DUPLICATE: ${result.duplicateCount} identische Einträge übersprungen');
      }
      for (final conflict in result.conflicts) {
        _importLog.add('FEHLER: ${conflict.toString()}');
      }

      final message = result.conflicts.isNotEmpty
          ? 'Import abgeschlossen: ${result.insertedCount} Fehler importiert, ${result.conflicts.length} Konflikte'
          : 'Erfolgreich importiert: ${result.insertedCount} Fehler';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: result.conflicts.isNotEmpty ? Colors.orange : Colors.green,
        ),
      );

      // If there are conflicts, navigate to conflict review
      if (result.conflicts.isNotEmpty) {
        final resolved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => ConflictReviewPage(conflicts: result.conflicts),
          ),
        );

        if (resolved == true) {
          // Conflicts were resolved, show final success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Alle Konflikte erfolgreich gelöst'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      _importLog.add('FEHLER: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import fehlgeschlagen: $e')),
      );
    } finally {
      setState(() {
        _isImporting = false;
      });
    }
  }

  String _normalizeSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'low':
      case 'niedrig':
      case '1':
        return 'low';
      case 'medium':
      case 'mittel':
      case '2':
        return 'medium';
      case 'high':
      case 'hoch':
      case '3':
        return 'high';
      case 'critical':
      case 'kritisch':
      case '4':
        return 'critical';
      default:
        return 'medium';
    }
  }
}
