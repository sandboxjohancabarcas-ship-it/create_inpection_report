import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wartungstool/models/error_catalog.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';
import '../widgets/master_portal_home_button.dart';

class ErrorConflictReviewPage extends StatefulWidget {
  final List<ImportConflict> conflicts;
  final List<File>? sourceFiles;

  const ErrorConflictReviewPage({
    super.key,
    required this.conflicts,
    this.sourceFiles,
  });

  @override
  State<ErrorConflictReviewPage> createState() => _ErrorConflictReviewPageState();
}

class _ErrorConflictReviewPageState extends State<ErrorConflictReviewPage> {
  late List<ImportConflict> _uniqueConflicts;
  final Map<String, ResolutionAction> _actions = {};
  final Map<String, TextEditingController> _codeControllers = {};
  final Map<String, TextEditingController> _descriptionControllers = {};
  final Map<String, String> _categorySelections = {};
  final Map<String, String> _severitySelections = {};
  final Map<String, String?> _mappedCodeSelections = {};

  List<ErrorCatalog> _existingCatalog = [];
  bool _isLoading = true;
  bool _isApplying = false;

  final List<String> _categories = ['Mangel', 'Hinweis', 'Wartungsmangel'];
  final List<String> _severities = ['low', 'medium', 'high', 'critical'];

  @override
  void initState() {
    super.initState();
    _initConflicts();
    _loadCatalog();
  }

  void _initConflicts() {
    // Deduplicate conflicts by unique code/description
    final Map<String, ImportConflict> map = {};
    for (final c in widget.conflicts) {
      final key = '${c.code}_${c.description}';
      if (!map.containsKey(key)) {
        map[key] = c;
      }
    }
    _uniqueConflicts = map.values.toList();

    for (final c in _uniqueConflicts) {
      final key = '${c.code}_${c.description}';
      _actions[key] = ResolutionAction.addAsNew;

      final isNotice = c.code.toLowerCase().startsWith('0.') ||
          c.code.toLowerCase().startsWith('hinweis') ||
          c.description.toLowerCase().contains('hinweis');

      // Suggest clean numeric code if it was a free text header
      String suggestedCode = c.code;
      if (!RegExp(r'^\d+\.\d+').hasMatch(suggestedCode)) {
        suggestedCode = isNotice ? '0.40' : '11.1';
      }

      _codeControllers[key] = TextEditingController(text: suggestedCode);
      _descriptionControllers[key] = TextEditingController(
        text: c.description.isNotEmpty ? c.description : c.code,
      );
      _categorySelections[key] = isNotice ? 'Hinweis' : 'Mangel';
      _severitySelections[key] = isNotice ? 'low' : 'medium';
      _mappedCodeSelections[key] = null;
    }
  }

  Future<void> _loadCatalog() async {
    try {
      final catalog = await DatabaseService.getAllErrorCatalog();
      setState(() {
        _existingCatalog = catalog;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _codeControllers.values) {
      controller.dispose();
    }
    for (final controller in _descriptionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setAllActions(ResolutionAction action) {
    setState(() {
      for (final c in _uniqueConflicts) {
        final key = '${c.code}_${c.description}';
        _actions[key] = action;
      }
    });
  }

  Future<void> _applyResolutions() async {
    setState(() => _isApplying = true);

    final resolutions = <ConflictResolution>[];

    for (final c in _uniqueConflicts) {
      final key = '${c.code}_${c.description}';
      final action = _actions[key] ?? ResolutionAction.addAsNew;

      if (action == ResolutionAction.addAsNew) {
        final newCode = _codeControllers[key]?.text.trim() ?? c.code;
        final newDesc = _descriptionControllers[key]?.text.trim() ?? c.description;
        final cat = _categorySelections[key] ?? 'Mangel';
        final sev = _severitySelections[key] ?? 'medium';

        final updatedError = c.incoming.copyWith(
          code: newCode,
          description: newDesc,
          category: cat,
          severity: sev,
          status: 'Approved',
        );

        resolutions.add(ConflictResolution(
          conflict: ImportConflict(
            code: c.code,
            description: c.description,
            incoming: updatedError,
            existing: c.existing,
            reason: c.reason,
          ),
          action: ResolutionAction.addAsNew,
          newCode: newCode,
        ));
      } else if (action == ResolutionAction.replaceExisting) {
        final mappedCode = _mappedCodeSelections[key];
        resolutions.add(ConflictResolution(
          conflict: c,
          action: ResolutionAction.replaceExisting,
          newCode: mappedCode,
        ));
      } else if (action == ResolutionAction.skip) {
        resolutions.add(ConflictResolution(
          conflict: c,
          action: ResolutionAction.skip,
        ));
      }
    }

    try {
      // 1. Persist resolutions to catalog DB
      await DatabaseService.applyConflictResolutions(resolutions);

      // 2. If source Excel files are present, re-run import with resolved codes to link doors
      if (widget.sourceFiles != null && widget.sourceFiles!.isNotEmpty) {
        for (final file in widget.sourceFiles!) {
          final ext = file.path.split('.').last.toLowerCase();
          if (['xlsx', 'xls', 'xlsm', 'xlms', 'csv'].contains(ext)) {
            await ExcelDataImporter.importFromFile(file, resolutions: resolutions);
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehlerkatalog-Konflikte erfolgreich gelöst und übernommen.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, resolutions);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Übernehmen der Konfliktlösungen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isApplying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fehlerkatalog-Konflikte lösen (${_uniqueConflicts.length})'),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: const [
          MasterPortalHomeButton(color: Colors.white),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.orange.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.report_problem_outlined, color: Colors.orange.shade900, size: 28),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Unbekannte Mängel/Hinweise in Importdatei festgestellt',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Folgende Fehler/Hinweise wurden in den Türlisten gefunden, existieren aber weder im zentralen Katalog noch in der Fehlerübersicht. '
                              'Legen Sie fest, ob diese neu angelegt, einem bestehenden Code zugeordnet oder ignoriert werden sollen.',
                              style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bulk actions
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _setAllActions(ResolutionAction.addAsNew),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Alle: Als Neu anlegen'),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: () => _setAllActions(ResolutionAction.skip),
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('Alle: Überspringen'),
                      ),
                    ],
                  ),
                ),

                // Conflict Cards
                Expanded(
                  child: ListView.builder(
                    itemCount: _uniqueConflicts.length,
                    itemBuilder: (context, index) {
                      final conflict = _uniqueConflicts[index];
                      final key = '${conflict.code}_${conflict.description}';
                      return _buildConflictCard(key, conflict);
                    },
                  ),
                ),

                // Bottom Action Bar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isApplying ? null : _applyResolutions,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isApplying
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Wende Entscheidungen an...'),
                                  ],
                                )
                              : const Text('Entscheidungen anwenden'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                        ),
                        child: const Text('Abbrechen'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildConflictCard(String key, ImportConflict conflict) {
    final action = _actions[key] ?? ResolutionAction.addAsNew;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade200, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.rule_folder_outlined, color: Colors.orange.shade800),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conflict.description.isNotEmpty ? conflict.description : conflict.code,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (conflict.reason.isNotEmpty)
                        Text(
                          conflict.reason,
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action Selection
            SegmentedButton<ResolutionAction>(
              segments: const [
                ButtonSegment(
                  value: ResolutionAction.addAsNew,
                  label: Text('Als Neu anlegen'),
                  icon: Icon(Icons.add_circle_outline, size: 18),
                ),
                ButtonSegment(
                  value: ResolutionAction.replaceExisting,
                  label: Text('Zuordnen'),
                  icon: Icon(Icons.swap_horiz, size: 18),
                ),
                ButtonSegment(
                  value: ResolutionAction.skip,
                  label: Text('Überspringen'),
                  icon: Icon(Icons.block, size: 18),
                ),
              ],
              selected: {action},
              onSelectionChanged: (set) {
                setState(() {
                  _actions[key] = set.first;
                });
              },
            ),
            const SizedBox(height: 16),

            // Conditional Inputs depending on chosen Action
            if (action == ResolutionAction.addAsNew) ...[
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _codeControllers[key],
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _descriptionControllers[key],
                      decoration: const InputDecoration(
                        labelText: 'Bezeichnung',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _categorySelections[key],
                      decoration: const InputDecoration(
                        labelText: 'Kategorie',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _categorySelections[key] = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _severitySelections[key],
                      decoration: const InputDecoration(
                        labelText: 'Schweregrad',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _severities.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _severitySelections[key] = val);
                      },
                    ),
                  ),
                ],
              ),
            ] else if (action == ResolutionAction.replaceExisting) ...[
              DropdownButtonFormField<String>(
                value: _mappedCodeSelections[key],
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Bestehenden Katalog-Fehler auswählen',
                  border: OutlineInputBorder(),
                  isDense: true,
                  helperText: 'Dieser Mangel wird für die importierten Türen verwendet.',
                ),
                hint: const Text('Bitte Katalog-Eintrag wählen...'),
                items: _existingCatalog.map((item) {
                  return DropdownMenuItem<String>(
                    value: item.code,
                    child: Text('${item.code} - ${item.category}: ${item.description}', overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _mappedCodeSelections[key] = val);
                },
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dieser Mangel wird ignoriert: Er wird nicht in den Katalog aufgenommen und nicht für betroffene Türen hinterlegt.',
                        style: TextStyle(fontSize: 13, color: Colors.blueGrey),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
