import 'package:flutter/material.dart';
import 'package:create_inpection_report/models/error_catalog.dart';
import 'package:create_inpection_report/services/database_service.dart';

class ConflictReviewPage extends StatefulWidget {
  final List<ImportConflict> conflicts;

  const ConflictReviewPage({
    super.key,
    required this.conflicts,
  });

  @override
  _ConflictReviewPageState createState() => _ConflictReviewPageState();
}

class _ConflictReviewPageState extends State<ConflictReviewPage> {
  final Map<int, ConflictResolution> _resolutions = {};
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    // Initialize all conflicts with default action (keep existing)
    for (int i = 0; i < widget.conflicts.length; i++) {
      _resolutions[i] = ConflictResolution(
        conflict: widget.conflicts[i],
        action: ResolutionAction.keepExisting,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Konflikte lösen (${widget.conflicts.length})'),
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: _showHelp,
            tooltip: 'Hilfe',
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary header
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.orange.shade50,
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${widget.conflicts.length} Konflikte gefunden. Bitte wählen Sie für jeden Konflikt eine Lösung.',
                    style: TextStyle(color: Colors.orange.shade800),
                  ),
                ),
              ],
            ),
          ),

          // Conflict list
          Expanded(
            child: ListView.builder(
              itemCount: widget.conflicts.length,
              itemBuilder: (context, index) {
                final conflict = widget.conflicts[index];
                final resolution = _resolutions[index]!;

                return Card(
                  margin: EdgeInsets.all(8),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Conflict header
                        Row(
                          children: [
                            Icon(Icons.error, color: Colors.red),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Konflikt ${index + 1}: ${conflict.code}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          conflict.reason,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 14,
                          ),
                        ),

                        SizedBox(height: 16),

                        // Existing vs Incoming comparison
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Existing
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Aktuell in Katalog',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  _buildErrorCard(conflict.existing!, Colors.blue.shade50),
                                ],
                              ),
                            ),

                            SizedBox(width: 16),

                            // Incoming
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Neu importiert',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  _buildErrorCard(conflict.incoming, Colors.green.shade50),
                                ],
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 16),

                        // Resolution options
                        Text(
                          'Lösung wählen:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),

                        // Radio buttons for resolution
                        Column(
                          children: [
                            RadioListTile<ResolutionAction>(
                              title: Text('Bestehenden Eintrag behalten'),
                              subtitle: Text('Importierten Eintrag überspringen'),
                              value: ResolutionAction.keepExisting,
                              groupValue: resolution.action,
                              onChanged: (value) => _updateResolution(index, value!),
                            ),
                            RadioListTile<ResolutionAction>(
                              title: Text('Bestehenden Eintrag ersetzen'),
                              subtitle: Text('Mit importierten Daten überschreiben'),
                              value: ResolutionAction.replaceExisting,
                              groupValue: resolution.action,
                              onChanged: (value) => _updateResolution(index, value!),
                            ),
                            RadioListTile<ResolutionAction>(
                              title: Text('Als neuen Eintrag hinzufügen'),
                              subtitle: Text('Unter neuem Code speichern'),
                              value: ResolutionAction.addAsNew,
                              groupValue: resolution.action,
                              onChanged: (value) => _updateResolution(index, value!),
                            ),
                            RadioListTile<ResolutionAction>(
                              title: Text('Importierten Eintrag überspringen'),
                              subtitle: Text('Beide Einträge unverändert lassen'),
                              value: ResolutionAction.skip,
                              groupValue: resolution.action,
                              onChanged: (value) => _updateResolution(index, value!),
                            ),
                          ],
                        ),

                        // New code input for addAsNew
                        if (resolution.action == ResolutionAction.addAsNew) ...[
                          SizedBox(height: 16),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'Neuer Code',
                              hintText: 'z.B. ${conflict.code}_neu',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _resolutions[index] = ConflictResolution(
                                  conflict: conflict,
                                  action: ResolutionAction.addAsNew,
                                  newCode: value.isEmpty ? null : value,
                                );
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Apply button
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isApplying ? null : _applyResolutions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isApplying
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('Wende Lösungen an...'),
                            ],
                          )
                        : Text('Lösungen anwenden'),
                  ),
                ),
                SizedBox(width: 16),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Abbrechen'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ErrorCatalog error, Color backgroundColor) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Code: ${error.code}', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('Beschreibung: ${error.description}'),
          Text('Kategorie: ${error.category}'),
          Text('Schwere: ${error.severity}'),
          if (error.recommendation.isNotEmpty)
            Text('Empfehlung: ${error.recommendation}'),
          if (error.normReference.isNotEmpty)
            Text('Norm: ${error.normReference}'),
        ],
      ),
    );
  }

  void _updateResolution(int index, ResolutionAction action) {
    setState(() {
      _resolutions[index] = ConflictResolution(
        conflict: widget.conflicts[index],
        action: action,
        newCode: action == ResolutionAction.addAsNew ? _resolutions[index]?.newCode : null,
      );
    });
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Konfliktlösung Hilfe'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Konflikte treten auf, wenn:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Gleicher Code mit unterschiedlichen Daten'),
              Text('• Gleiche Beschreibung mit unterschiedlichem Code'),
              SizedBox(height: 16),

              Text(
                'Lösungsoptionen:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Behalten: Bestehenden Eintrag unverändert lassen'),
              Text('• Ersetzen: Bestehenden Eintrag mit neuen Daten überschreiben'),
              Text('• Neu hinzufügen: Importierten Eintrag unter neuem Code speichern'),
              Text('• Überspringen: Beide Einträge unverändert lassen'),
              SizedBox(height: 16),

              Text(
                'Empfehlung:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Prüfen Sie jeden Konflikt sorgfältig. Bei Unsicherheit "Behalten" wählen.'),
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

  void _applyResolutions() async {
    // Validate new codes for addAsNew actions
    final invalidResolutions = _resolutions.values.where((r) =>
      r.action == ResolutionAction.addAsNew &&
      (r.newCode == null || r.newCode!.trim().isEmpty)
    ).toList();

    if (invalidResolutions.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bitte geben Sie einen neuen Code für alle "Neu hinzufügen" Einträge ein'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isApplying = true;
    });

    try {
      final resolutions = _resolutions.values.toList();
      await DatabaseService.applyConflictResolutions(resolutions);

      final appliedCount = resolutions.where((r) => r.action != ResolutionAction.keepExisting && r.action != ResolutionAction.skip).length;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$appliedCount Konflikte erfolgreich gelöst'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true); // Return success
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Anwenden der Lösungen: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isApplying = false;
      });
    }
  }
}