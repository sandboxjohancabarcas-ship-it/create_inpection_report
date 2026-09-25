import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wartungstool/models/error_catalog.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';
import 'package:wartungstool/services/catalog_integrity_service.dart';
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

  List<String> _categories = ['Hinweise und Anmerkungen', 'Türblatt/Zarge', 'Feststellanlagen (FSA)', 'Mangel'];
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

      String initialCategory = c.incoming.category.isNotEmpty
          ? c.incoming.category
          : (isNotice ? 'Hinweise und Anmerkungen' : 'Mangel');

      final codeCtrl = TextEditingController(text: c.code);
      final descCtrl = TextEditingController(
        text: c.description.isNotEmpty ? c.description : c.code,
      );

      // Re-render live warnings when user types
      codeCtrl.addListener(() {
        if (mounted) setState(() {});
      });
      descCtrl.addListener(() {
        if (mounted) setState(() {});
      });

      _codeControllers[key] = codeCtrl;
      _descriptionControllers[key] = descCtrl;
      _categorySelections[key] = initialCategory;
      _severitySelections[key] = isNotice ? 'low' : 'medium';
      _mappedCodeSelections[key] = null;
    }
  }

  Future<void> _loadCatalog() async {
    try {
      final catalog = await DatabaseService.getAllErrorCatalog();
      final officialCats = await DatabaseService.getErrorCatalogCategories();
      final filteredCats = officialCats.where((c) => c != 'Altdaten' && c.trim().isNotEmpty).toList();

      if (filteredCats.isEmpty) {
        final derived = catalog
            .where((e) => e.category != 'Altdaten' && e.category.trim().isNotEmpty)
            .map((e) => e.category)
            .toSet()
            .toList();
        derived.sort();
        filteredCats.addAll(derived);
      }

      if (filteredCats.isNotEmpty) {
        _categories = filteredCats;
      }

      // Propose category-fitting codes for conflicts if they don't have a clean numeric code
      for (final c in _uniqueConflicts) {
        final key = '${c.code}_${c.description}';
        final currentCat = _categorySelections[key] ?? _categories.first;
        final proposed = CatalogIntegrityService.proposeNextCodeForCategory(
          currentCat,
          catalog,
          incomingCode: c.code,
        );
        _codeControllers[key]?.text = proposed;
      }

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

  void _onCategoryChanged(String key, String newCategory) {
    setState(() {
      _categorySelections[key] = newCategory;
      final proposed = CatalogIntegrityService.proposeNextCodeForCategory(
        newCategory,
        _existingCatalog,
        incomingCode: _codeControllers[key]?.text,
      );
      _codeControllers[key]?.text = proposed;
    });
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
    // ── Integrity Protection Validation ──
    final collisions = <String>[];
    final duplicateNewCodes = <String, List<String>>{};
    final similarWarnings = <Map<String, dynamic>>[];

    for (final c in _uniqueConflicts) {
      final key = '${c.code}_${c.description}';
      final action = _actions[key] ?? ResolutionAction.addAsNew;

      if (action == ResolutionAction.addAsNew) {
        final newCode = _codeControllers[key]?.text.trim() ?? '';
        final newDesc = _descriptionControllers[key]?.text.trim() ?? '';

        if (newCode.isEmpty || newDesc.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bitte geben Sie für alle neuen Einträge einen Code und eine Beschreibung ein.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        // 1. Identical code collision against existing official catalog
        final collision = CatalogIntegrityService.findCodeCollision(newCode, _existingCatalog);
        if (collision != null) {
          collisions.add('Code "$newCode" (Bereits im Katalog für: "${collision.description}" [${collision.category}])');
        }

        duplicateNewCodes.putIfAbsent(newCode, () => []).add(newDesc);

        // 2. High similarity check with existing catalog description
        final similar = CatalogIntegrityService.findSimilarDescription(newDesc, _existingCatalog, threshold: 0.78);
        if (similar != null) {
          similarWarnings.add({
            'newCode': newCode,
            'newDesc': newDesc,
            'existingCode': similar.existing.code,
            'existingDesc': similar.existing.description,
            'similarity': similar.similarityPercentage,
          });
        }
      }
    }

    // Check duplicate codes among the new items being created in this resolution batch
    for (final entry in duplicateNewCodes.entries) {
      if (entry.value.length > 1) {
        collisions.add('Code "${entry.key}" wird mehrfach gleichzeitig für verschiedene neue Mängel vergeben.');
      }
    }

    // Block saving if there are identical code collisions
    if (collisions.isNotEmpty) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade700, size: 28),
              const SizedBox(width: 8),
              const Text('Katalog-Integritätsprüfung fehlgeschlagen'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Folgende Fehlercodes kollidieren mit bestehenden Katalogeinträgen oder wurden mehrfach vergeben:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ...collisions.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    Expanded(child: Text(c, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              )),
              const SizedBox(height: 12),
              const Text('Bitte korrigieren Sie die Fehlercodes vor dem Speichern, um die Integrität des Mängelkatalogs zu schützen.'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.shade800, foregroundColor: Colors.white),
              child: const Text('Eingaben anpassen'),
            ),
          ],
        ),
      );
      return;
    }

    // Prompt warning confirmation if very similar descriptions already exist
    if (similarWarnings.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 28),
              const SizedBox(width: 8),
              const Text('Ähnliche Mängel im Katalog gefunden'),
            ],
          ),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Für folgende neue Einträge existieren bereits sehr ähnliche Mängel im Katalog:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ...similarWarnings.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Neuer Mangel: ${w['newCode']} - "${w['newDesc']}"', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('Bestehend: ${w['existingCode']} - "${w['existingDesc']}" (${w['similarity']}% Ähnlichkeit)', style: TextStyle(color: Colors.grey.shade800, fontSize: 12)),
                      ],
                    ),
                  ),
                )),
                const SizedBox(height: 10),
                const Text('Möchten Sie diese Einträge trotzdem als neue Katalogeinträge anlegen oder zurückgehen und die bestehenden Mängel zuordnen?'),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Zurück zum Anpassen'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Trotzdem als Neu anlegen'),
            ),
          ],
        ),
      );

      if (proceed != true) {
        return;
      }
    }

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
                              'Folgende Fehler/Hinweise wurden in den Türlisten gefunden, existieren aber nicht im zentralen Mängelkatalog. '
                              'Legen Sie fest, ob diese als neuer Mangel mit passendem Kategorie-Code angelegt, einem bestehenden Eintrag zugeordnet oder ignoriert werden sollen.',
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
    final currentCode = _codeControllers[key]?.text.trim() ?? '';
    final currentDesc = _descriptionControllers[key]?.text.trim() ?? '';

    // Real-time catalog integrity checks for this card
    final codeCollision = action == ResolutionAction.addAsNew
        ? CatalogIntegrityService.findCodeCollision(currentCode, _existingCatalog)
        : null;

    final similarMatch = action == ResolutionAction.addAsNew
        ? CatalogIntegrityService.findSimilarDescription(currentDesc, _existingCatalog, threshold: 0.75)
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: codeCollision != null
              ? Colors.red.shade400
              : (similarMatch != null ? Colors.amber.shade400 : Colors.orange.shade200),
          width: 1.5,
        ),
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
                    width: 140,
                    child: TextField(
                      controller: _codeControllers[key],
                      decoration: InputDecoration(
                        labelText: 'Code (Vorschlag)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        errorText: codeCollision != null ? 'Kollidiert!' : null,
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
                      value: _categories.contains(_categorySelections[key])
                          ? _categorySelections[key]
                          : _categories.firstOrNull,
                      decoration: const InputDecoration(
                        labelText: 'Kategorie (Code passt sich an)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          _onCategoryChanged(key, val);
                        }
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

              // ── Live Code Collision Warning Box ──
              if (codeCollision != null)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade800, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Achtung Code-Kollision: Der Code "$currentCode" existiert bereits für "${codeCollision.description}" (Kategorie: ${codeCollision.category}). Bitte vergeben Sie einen eindeutigen Code.',
                          style: TextStyle(color: Colors.red.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Live Similar Description Warning Box ──
              if (similarMatch != null)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ähnlicher Mangel im Katalog gefunden (${similarMatch.similarityPercentage}% Ähnlichkeit):\n"${similarMatch.existing.code}: ${similarMatch.existing.description}" (${similarMatch.existing.category})',
                              style: TextStyle(color: Colors.amber.shade900, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.amber.shade900,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            setState(() {
                              _actions[key] = ResolutionAction.replaceExisting;
                              _mappedCodeSelections[key] = similarMatch.existing.code;
                            });
                          },
                          icon: const Icon(Icons.swap_horiz, size: 16),
                          label: Text('Diesen Code stattdessen zuordnen (${similarMatch.existing.code})'),
                        ),
                      ),
                    ],
                  ),
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
                items: _existingCatalog
                    .where((e) => e.category != 'Altdaten' && !e.code.toUpperCase().startsWith('ALT-'))
                    .map((item) {
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
