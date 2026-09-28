import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/catalog_integrity_service.dart';
import '../widgets/master_portal_home_button.dart';

class ErrorConsolidationPage extends StatefulWidget {
  const ErrorConsolidationPage({super.key});

  @override
  State<ErrorConsolidationPage> createState() => _ErrorConsolidationPageState();
}

class _ErrorConsolidationPageState extends State<ErrorConsolidationPage> {
  late Future<List<ErrorCatalog>> _pendingErrorsFuture;
  List<ErrorCatalog> _officialCatalog = [];
  List<String> _categories = [];
  bool _isLoadingCatalog = true;

  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  void _refreshList() {
    setState(() {
      _pendingErrorsFuture = DatabaseService.getAllErrorCatalog(status: 'Pending');
    });
    _loadCatalogAndCategories();
  }

  Future<void> _loadCatalogAndCategories() async {
    setState(() => _isLoadingCatalog = true);
    try {
      final allCatalog = await DatabaseService.getAllErrorCatalog();
      final official = allCatalog.where((e) => e.status != 'Pending' && e.category != 'Altdaten').toList();
      final cats = await DatabaseService.getErrorCatalogCategories();
      final cleanCats = cats.where((c) => c != 'Altdaten' && c.trim().isNotEmpty).toList();

      if (mounted) {
        setState(() {
          _officialCatalog = official;
          _categories = cleanCats;
          _isLoadingCatalog = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCatalog = false);
      }
    }
  }

  Future<void> _processApproval(ErrorCatalog error, bool approved, {String? oldCode, int? oldErrorId}) async {
    if (!approved) {
      try {
        final rejectedError = error.copyWith(status: 'Rejected');
        await DatabaseService.insertErrorCatalog(rejectedError);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fehler-Anfrage abgelehnt und archiviert.')),
          );
          _refreshList();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler bei der Verarbeitung: $e')),
          );
        }
      }
      return;
    }

    // Check for collisions before direct approval
    final collision = CatalogIntegrityService.findCodeCollision(
      error.code,
      _officialCatalog,
      ignoreErrorId: error.errorId,
    );
    final similar = CatalogIntegrityService.findSimilarDescription(
      error.description,
      _officialCatalog,
      threshold: 0.85,
      ignoreErrorId: error.errorId,
    );

    if (collision != null || similar != null) {
      // Prompt manager to resolve conflict
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('Konflikt erkannt'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (collision != null) ...[
                  Text(
                    'Der Code "${error.code}" ist bereits vergeben an:',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('• ${collision.code} - ${collision.description} (${collision.category})'),
                  const SizedBox(height: 12),
                ],
                if (similar != null) ...[
                  Text(
                    'Ähnlicher Fehler existiert bereits (${similar.similarityPercentage}% Übereinstimmung):',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('• ${similar.existing.code} - ${similar.existing.description}'),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Ein direktes Genehmigen würde den bestehenden Katalog überschreiben oder duplizieren. Bitte prüfen und anpassen.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Abbrechen'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showEditDialog(error);
                },
                icon: const Icon(Icons.edit),
                label: const Text('Jetzt prüfen & anpassen'),
              ),
            ],
          ),
        );
      }
      return;
    }

    try {
      await DatabaseService.approveAndRemapPendingError(
        error,
        oldCode: oldCode ?? error.code,
        oldErrorId: oldErrorId ?? error.errorId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler "${error.code} - ${error.description}" erfolgreich genehmigt!'),
            backgroundColor: Colors.green,
          ),
        );
        _refreshList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler bei der Genehmigung: $e')),
        );
      }
    }
  }

  Future<void> _mergeWithExisting(ErrorCatalog pendingError, ErrorCatalog targetCatalogItem) async {
    try {
      await DatabaseService.mergePendingErrorIntoExisting(
        pendingError: pendingError,
        targetError: targetCatalogItem,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Anfrage erfolgreich mit [${targetCatalogItem.code}] verknüpft!'),
            backgroundColor: Colors.teal,
          ),
        );
        _refreshList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Verknüpfen: $e')),
        );
      }
    }
  }

  void _showMergeDialog(ErrorCatalog pendingError) {
    String searchQuery = '';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final query = searchQuery.trim().toLowerCase();
          final filtered = _officialCatalog.where((e) {
            if (query.isEmpty) return true;
            return e.code.toLowerCase().contains(query) ||
                e.description.toLowerCase().contains(query) ||
                e.category.toLowerCase().contains(query);
          }).toList();

          return AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.merge_type, color: Colors.teal),
                SizedBox(width: 8),
                Text('Mit bestehendem Fehler verknüpfen'),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: 450,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wählen Sie den offiziellen Katalogeintrag, dem alle Mängel dieser Anfrage ("${pendingError.code} - ${pendingError.description}") zugewiesen werden sollen:',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Katalog durchsuchen...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => setDialogState(() => searchQuery = val),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('Keine passenden Katalogeinträge gefunden.'))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              return ListTile(
                                dense: true,
                                title: Text('${item.code} - ${item.description}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Kategorie: ${item.category} | Schweregrad: ${item.severity}'),
                                trailing: ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _mergeWithExisting(pendingError, item);
                                  },
                                  child: const Text('Verknüpfen'),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Abbrechen'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fehler-Katalog Konsolidierung & Freigabe'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            onPressed: _refreshList,
            icon: const Icon(Icons.refresh),
          ),
          const MasterPortalHomeButton(),
        ],
      ),
      body: FutureBuilder<List<ErrorCatalog>>(
        future: _pendingErrorsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _isLoadingCatalog) {
            return const Center(child: CircularProgressIndicator());
          }

          final pending = snapshot.data ?? [];
          if (pending.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.task_alt, size: 64, color: Colors.green.shade400),
                  const SizedBox(height: 16),
                  const Text(
                    'Keine offenen Fehler-Anfragen vorhanden.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Alle provisorischen Prüfungsfehler wurden genehmigt oder konsolidiert.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: pending.length,
            itemBuilder: (context, index) {
              final item = pending[index];
              final collision = CatalogIntegrityService.findCodeCollision(
                item.code,
                _officialCatalog,
                ignoreErrorId: item.errorId,
              );
              final similar = CatalogIntegrityService.findSimilarDescription(
                item.description,
                _officialCatalog,
                threshold: 0.65,
                ignoreErrorId: item.errorId,
              );

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: collision != null
                        ? Colors.red.shade300
                        : (similar != null ? Colors.orange.shade300 : Colors.grey.shade300),
                    width: (collision != null || similar != null) ? 1.5 : 1,
                  ),
                ),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: collision != null
                        ? Colors.red.shade100
                        : (similar != null ? Colors.orange.shade100 : Colors.blue.shade100),
                    child: Icon(
                      collision != null
                          ? Icons.warning_amber_rounded
                          : (similar != null ? Icons.compare_arrows : Icons.pending_actions),
                      color: collision != null
                          ? Colors.red.shade800
                          : (similar != null ? Colors.orange.shade800 : Colors.blue.shade800),
                    ),
                  ),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.code,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.description,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Text('Kategorie: ${item.category}', style: const TextStyle(fontSize: 12)),
                        if (item.requestedBy != null && item.requestedBy!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text('• Von: ${item.requestedBy}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      ],
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Conflict Warnings Display
                          if (collision != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.red.shade300),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.error, size: 20, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '⚠️ Code-Kollision mit bestehendem Eintrag:',
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900),
                                        ),
                                        Text(
                                          '${collision.code} - ${collision.description} (${collision.category})',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          if (similar != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.orange.shade300),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.lightbulb, size: 20, color: Colors.orange),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '🔍 Ähnlicher Fehler im offiziellen Katalog gefunden (${similar.similarityPercentage}%):',
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                                        ),
                                        Text(
                                          '${similar.existing.code} - ${similar.existing.description}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _mergeWithExisting(item, similar.existing),
                                    icon: const Icon(Icons.merge_type, size: 16),
                                    label: const Text('Verknüpfen', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          if (collision == null && similar == null) ...[
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
                                  SizedBox(width: 6),
                                  Text(
                                    'Keine Kollisionen oder Duplikate im Katalog gefunden.',
                                    style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          // Defect details
                          Row(
                            children: [
                              Expanded(child: Text('Vorgeschlagener Code: ${item.code}', style: const TextStyle(fontWeight: FontWeight.bold))),
                              Expanded(child: Text('Schweregrad: ${item.severity}')),
                            ],
                          ),
                          if (item.recommendation.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Empfehlung: ${item.recommendation}'),
                          ],
                          if (item.normReference.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Normreferenz: ${item.normReference}'),
                          ],

                          const Divider(height: 24),

                          // Actions
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: () => _processApproval(item, false),
                                icon: const Icon(Icons.archive, color: Colors.grey),
                                label: const Text('Ablehnen', style: TextStyle(color: Colors.grey)),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _showMergeDialog(item),
                                icon: const Icon(Icons.merge_type, color: Colors.teal),
                                label: const Text('Mit Katalog verknüpfen', style: TextStyle(color: Colors.teal)),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _showEditDialog(item),
                                icon: const Icon(Icons.edit),
                                label: const Text('Prüfen & Bearbeiten'),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: collision != null ? Colors.orange : Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _processApproval(item, true),
                                icon: Icon(collision != null ? Icons.warning : Icons.check_circle),
                                label: const Text('Direkt Genehmigen'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showEditDialog(ErrorCatalog error) {
    final codeController = TextEditingController(text: error.code);
    final descController = TextEditingController(text: error.description);
    final catController = TextEditingController(text: error.category);
    final severityController = TextEditingController(text: error.severity);
    final recommendationController = TextEditingController(text: error.recommendation);
    final normReferenceController = TextEditingController(text: error.normReference);

    bool isCustomCategory = !_categories.contains(error.category) && error.category.isNotEmpty;
    final customCatController = TextEditingController(text: isCustomCategory ? error.category : '');
    String selectedCategory = _categories.contains(error.category)
        ? error.category
        : (_categories.isNotEmpty ? _categories.first : 'Sonstiges');

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, dialogSetState) {
          final currentCode = codeController.text.trim();
          final currentDesc = descController.text.trim();
          final collision = CatalogIntegrityService.findCodeCollision(
            currentCode,
            _officialCatalog,
            ignoreErrorId: error.errorId,
          );
          final similar = CatalogIntegrityService.findSimilarDescription(
            currentDesc,
            _officialCatalog,
            threshold: 0.65,
            ignoreErrorId: error.errorId,
          );

          return AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.edit_note, color: Colors.blue),
                SizedBox(width: 8),
                Text('Fehler-Anfrage bearbeiten & genehmigen'),
              ],
            ),
            content: SizedBox(
              width: 650,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Passen Sie Code, Kategorie und Beschreibung an, um Integrität und Duplikatfreiheit im Katalog zu sichern.',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),

                    // Dynamic Category Selector
                    Card(
                      elevation: 0,
                      color: Colors.blue.shade50.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.blue.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.category, size: 18, color: Colors.blue),
                                const SizedBox(width: 6),
                                const Text(
                                  'Kategorie:',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                if (isCustomCategory && _categories.isNotEmpty) ...[
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () {
                                      dialogSetState(() {
                                        isCustomCategory = false;
                                        selectedCategory = _categories.first;
                                        catController.text = _categories.first;
                                      });
                                    },
                                    icon: const Icon(Icons.list, size: 14),
                                    label: const Text('Aus Katalogliste wählen', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (!isCustomCategory && _categories.isNotEmpty) ...[
                              DropdownButtonFormField<String>(
                                value: _categories.contains(selectedCategory) ? selectedCategory : _categories.first,
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                items: [
                                  ..._categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                                  const DropdownMenuItem(
                                    value: '__NEW_CATEGORY__',
                                    child: Row(
                                      children: [
                                        Icon(Icons.add_circle_outline, size: 16, color: Colors.blue),
                                        SizedBox(width: 6),
                                        Text(
                                          '+ Neue Kategorie erstellen...',
                                          style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val == '__NEW_CATEGORY__') {
                                    dialogSetState(() {
                                      isCustomCategory = true;
                                      catController.clear();
                                    });
                                  } else if (val != null) {
                                    dialogSetState(() {
                                      selectedCategory = val;
                                      catController.text = val;
                                    });
                                  }
                                },
                              ),
                            ] else ...[
                              TextField(
                                controller: customCatController,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  labelText: 'Neue Kategorie Bezeichnung *',
                                  border: const OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Colors.white,
                                  suffixIcon: _categories.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: () {
                                            dialogSetState(() {
                                              isCustomCategory = false;
                                              selectedCategory = _categories.first;
                                              catController.text = _categories.first;
                                            });
                                          },
                                        )
                                      : null,
                                ),
                                onChanged: (val) {
                                  catController.text = val.trim();
                                  dialogSetState(() {});
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Code with auto-generator
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: codeController,
                            decoration: InputDecoration(
                              labelText: 'Offizieller Fehlercode *',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: 'Nächsten freien Code berechnen',
                                icon: const Icon(Icons.auto_awesome, color: Colors.blue),
                                onPressed: () {
                                  final cat = catController.text.trim().isNotEmpty
                                      ? catController.text.trim()
                                      : selectedCategory;
                                  final nextCode = CatalogIntegrityService.proposeNextCodeForCategory(cat, _officialCatalog);
                                  codeController.text = nextCode;
                                  dialogSetState(() {});
                                },
                              ),
                            ),
                            onChanged: (_) => dialogSetState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                          ),
                          onPressed: () {
                            final cat = catController.text.trim().isNotEmpty
                                ? catController.text.trim()
                                : selectedCategory;
                            final nextCode = CatalogIntegrityService.proposeNextCodeForCategory(cat, _officialCatalog);
                            codeController.text = nextCode;
                            dialogSetState(() {});
                          },
                          icon: const Icon(Icons.tag, size: 16),
                          label: const Text('Code vorschlagen', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),

                    // Code Collision Live Box
                    if (collision != null) ...[
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, size: 18, color: Colors.red),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Achtung: Code "$currentCode" ist bereits vergeben für "${collision.description}"!',
                                style: TextStyle(color: Colors.red.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                final cat = catController.text.trim().isNotEmpty
                                    ? catController.text.trim()
                                    : selectedCategory;
                                codeController.text = CatalogIntegrityService.proposeNextCodeForCategory(cat, _officialCatalog);
                                dialogSetState(() {});
                              },
                              child: const Text('Freien Code wählen', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Description
                    TextField(
                      controller: descController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Beschreibung *', border: OutlineInputBorder()),
                      onChanged: (_) => dialogSetState(() {}),
                    ),

                    // Similar Description Warning
                    if (similar != null) ...[
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_outline, size: 18, color: Colors.orange),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Ähnlicher Fehler im Katalog: [${similar.existing.code}] ${similar.existing.description} (${similar.similarityPercentage}%)',
                                style: TextStyle(color: Colors.orange.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(dialogCtx);
                                _mergeWithExisting(error, similar.existing);
                              },
                              icon: const Icon(Icons.merge_type, size: 14),
                              label: const Text('Zusammenführen', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Severity
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Schweregrad', border: OutlineInputBorder()),
                      value: const ['low', 'medium', 'high', 'critical'].contains(severityController.text.toLowerCase())
                          ? severityController.text.toLowerCase()
                          : 'medium',
                      items: const ['low', 'medium', 'high', 'critical'].map((s) {
                        return DropdownMenuItem(value: s, child: Text(s.toUpperCase()));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) severityController.text = val;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Recommendation
                    TextField(
                      controller: recommendationController,
                      decoration: const InputDecoration(labelText: 'Empfehlung', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),

                    // Norm Reference
                    TextField(
                      controller: normReferenceController,
                      decoration: const InputDecoration(labelText: 'Normreferenz', border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Abbrechen'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _showMergeDialog(error);
                },
                icon: const Icon(Icons.merge_type, color: Colors.teal),
                label: const Text('Mit Katalog verknüpfen', style: TextStyle(color: Colors.teal)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: collision != null ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (codeController.text.trim().isEmpty || descController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code und Beschreibung dürfen nicht leer sein.')),
                    );
                    return;
                  }

                  if (collision != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Code "${codeController.text.trim()}" ist bereits vergeben. Bitte Code ändern.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  final updated = error.copyWith(
                    code: codeController.text.trim(),
                    description: descController.text.trim(),
                    category: catController.text.trim().isNotEmpty ? catController.text.trim() : 'Sonstiges',
                    severity: severityController.text.trim(),
                    recommendation: recommendationController.text.trim(),
                    normReference: normReferenceController.text.trim(),
                    status: 'Approved',
                  );

                  Navigator.pop(dialogCtx);
                  _processApproval(
                    updated,
                    true,
                    oldCode: error.code,
                    oldErrorId: error.errorId,
                  );
                },
                icon: const Icon(Icons.check),
                label: const Text('Speichern & Genehmigen'),
              ),
            ],
          );
        },
      ),
    );
  }
}