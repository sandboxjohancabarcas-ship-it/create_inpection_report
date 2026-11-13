import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';

class WindowErrorManagementPage extends StatefulWidget {
  final int windowId;
  final String windowNumber;
  final int inspectionId;
  final bool isManagerMode;
  final bool isReadOnly;

  const WindowErrorManagementPage({
    super.key,
    required this.windowId,
    required this.windowNumber,
    required this.inspectionId,
    this.isManagerMode = false,
    this.isReadOnly = false,
  });

  @override
  State<WindowErrorManagementPage> createState() => _WindowErrorManagementPageState();
}

class _WindowErrorManagementPageState extends State<WindowErrorManagementPage> {
  int? _inspectionWindowId;
  List<InspectionWindowError> _errors = [];
  List<ErrorCatalog> _catalog = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      if (widget.isManagerMode) {
        final junctions = await DatabaseService.getInspectionWindowsByInspectionId(widget.inspectionId);
        final junction = junctions.where((j) => j['windowId'] == widget.windowId).firstOrNull;
        _inspectionWindowId = junction?['id'] as int?;

        _catalog = await DatabaseService.getAllErrorCatalog(assetType: 'window');

        if (_inspectionWindowId != null) {
          _errors = await DatabaseService.getInspectionWindowErrors(_inspectionWindowId!);
        }
      } else {
        final junctions = await LocalDatabaseService.getInspectionWindowsByInspectionId(widget.inspectionId);
        final junction = junctions.where((j) => j['windowId'] == widget.windowId).firstOrNull;
        _inspectionWindowId = junction?['id'] as int?;

        _catalog = await LocalDatabaseService.getAllErrorCatalog(assetType: 'window');

        if (_inspectionWindowId != null) {
          _errors = await LocalDatabaseService.getInspectionWindowErrors(_inspectionWindowId!);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden der Mängel: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addErrorToWindow(ErrorCatalog catalogItem, {int quantity = 1, String severity = 'medium', String notes = ''}) async {
    if (_inspectionWindowId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine gültige Fenster-Verknüpfung gefunden.'), backgroundColor: Colors.red),
      );
      return;
    }

    final newError = InspectionWindowError(
      inspectionWindowId: _inspectionWindowId!,
      errorId: catalogItem.errorId,
      errorCode: catalogItem.code,
      quantity: quantity,
      severity: severity,
      notes: notes,
      resolutionStatus: 'Open',
    );

    if (widget.isManagerMode) {
      await DatabaseService.insertInspectionWindowError(newError);
    } else {
      await LocalDatabaseService.insertInspectionWindowError(newError);
    }

    await _loadData();
  }

  Future<void> _deleteError(InspectionWindowError error) async {
    if (error.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mangel löschen'),
        content: Text('Möchten Sie den Mangel "${error.errorCode}" wirklich entfernen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (widget.isManagerMode) {
        await DatabaseService.deleteInspectionWindowError(error.id!);
      } else {
        await LocalDatabaseService.deleteInspectionWindowError(error.id!);
      }
      await _loadData();
    }
  }

  Future<void> _openAddErrorDialog() async {
    final searchCtrl = TextEditingController();
    String selectedCategory = 'Alle';
    final categories = ['Alle', ...{..._catalog.map((e) => e.category)}.where((c) => c.isNotEmpty)];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchCtrl.text.toLowerCase().trim();
            final filteredCatalog = _catalog.where((item) {
              final matchesCategory = selectedCategory == 'Alle' || item.category == selectedCategory;
              final matchesQuery = query.isEmpty ||
                  item.code.toLowerCase().contains(query) ||
                  item.description.toLowerCase().contains(query);
              return matchesCategory && matchesQuery;
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                top: 16,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Mangel aus Katalog wählen', style: Theme.of(context).textTheme.titleLarge),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Mangel suchen (z. B. 9.1, Dichtung, Schließblech)...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: categories.map((cat) {
                          final isSelected = selectedCategory == cat;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: FilterChip(
                              label: Text(cat, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)),
                              selected: isSelected,
                              selectedColor: Theme.of(context).primaryColor,
                              onSelected: (val) {
                                setModalState(() => selectedCategory = cat);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(height: 16),
                    Expanded(
                      child: filteredCatalog.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Kein passender Mangel im Katalog gefunden.'),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text('Neuen Freitext-Mangel anlegen'),
                                    onPressed: () async {
                                      Navigator.pop(modalCtx);
                                      await _openCreateCustomDefectDialog(initialText: searchCtrl.text);
                                    },
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredCatalog.length,
                              itemBuilder: (ctx, idx) {
                                final item = filteredCatalog[idx];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.blue.shade100,
                                      child: Text(
                                        item.code.isNotEmpty ? item.code.split('.').first : 'W',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                      ),
                                    ),
                                    title: Text('${item.code} - ${item.description}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    subtitle: Text(item.category, style: const TextStyle(fontSize: 11)),
                                    trailing: const Icon(Icons.add_circle, color: Colors.blue),
                                    onTap: () async {
                                      Navigator.pop(modalCtx);
                                      await _promptConfigureError(item);
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _promptConfigureError(ErrorCatalog item) async {
    int quantity = 1;
    String severity = item.severity.isNotEmpty ? item.severity : 'medium';
    final notesCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Text('Mangel konfigurieren: ${item.code}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.description, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Anzahl / Menge: '),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            if (quantity > 1) setDlgState(() => quantity--);
                          },
                        ),
                        Text('$quantity', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setDlgState(() => quantity++),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: severity,
                      decoration: const InputDecoration(labelText: 'Dringlichkeit / Schweregrad', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Niedrig (Hinweis / Wartung)')),
                        DropdownMenuItem(value: 'medium', child: Text('Mittel (Normaler Mangel)')),
                        DropdownMenuItem(value: 'high', child: Text('Hoch (Dringend / Sicherheitsrelevant)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDlgState(() => severity = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Zusatznotiz / Details',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _addErrorToWindow(item, quantity: quantity, severity: severity, notes: notesCtrl.text.trim());
                  },
                  child: const Text('Hinzufügen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openCreateCustomDefectDialog({String initialText = ''}) async {
    final codeCtrl = TextEditingController(text: 'WIN_PROV_${DateTime.now().millisecondsSinceEpoch % 10000}');
    final descCtrl = TextEditingController(text: initialText);
    String category = 'Fenster Mängelerfassung';
    String severity = 'medium';

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Text('Neuen Mangel erfassen'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(labelText: 'Mängel-Code', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Mängel-Beschreibung', border: OutlineInputBorder()),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: severity,
                      decoration: const InputDecoration(labelText: 'Dringlichkeit', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Niedrig')),
                        DropdownMenuItem(value: 'medium', child: Text('Mittel')),
                        DropdownMenuItem(value: 'high', child: Text('Hoch')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDlgState(() => severity = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                ElevatedButton(
                  onPressed: () async {
                    final desc = descCtrl.text.trim();
                    if (desc.isEmpty) return;

                    final newCatalogEntry = ErrorCatalog(
                      code: codeCtrl.text.trim(),
                      description: desc,
                      category: category,
                      severity: severity,
                      assetType: 'window',
                    );

                    if (widget.isManagerMode) {
                      await DatabaseService.insertErrorCatalog(newCatalogEntry);
                    } else {
                      await LocalDatabaseService.insertErrorCatalog(newCatalogEntry);
                    }

                    Navigator.pop(ctx);
                    await _addErrorToWindow(newCatalogEntry, severity: severity);
                  },
                  child: const Text('Erfassen & Zuordnen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mängel - Fenster ${widget.windowNumber}'),
        actions: [
          if (!widget.isReadOnly)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Mangel hinzufügen',
              onPressed: _openAddErrorDialog,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errors.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                      const SizedBox(height: 16),
                      Text(
                        'Keine Mängel für Fenster ${widget.windowNumber} erfasst.',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text('Das Fenster ist in mangelfreiem Zustand.'),
                      const SizedBox(height: 20),
                      if (!widget.isReadOnly)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Mangel hinzufügen'),
                          onPressed: _openAddErrorDialog,
                        ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _errors.length,
                  itemBuilder: (context, index) {
                    final err = _errors[index];
                    final catalogMatch = _catalog.firstWhereOrNull((c) => c.code == err.errorCode);
                    final desc = catalogMatch?.description ?? err.notes;

                    Color badgeColor;
                    switch (err.severity.toLowerCase()) {
                      case 'high':
                      case 'critical':
                        badgeColor = Colors.red;
                        break;
                      case 'low':
                      case 'minor':
                        badgeColor = Colors.orange;
                        break;
                      default:
                        badgeColor = Colors.amber.shade800;
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blue.shade200),
                                      ),
                                      child: Text(
                                        err.errorCode,
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: badgeColor),
                                      ),
                                      child: Text(
                                        err.severity.toUpperCase(),
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
                                      ),
                                    ),
                                  ],
                                ),
                                if (!widget.isReadOnly)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    tooltip: 'Mangel löschen',
                                    onPressed: () => _deleteError(err),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              desc.isNotEmpty ? desc : 'Mangel ${err.errorCode}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            if (catalogMatch?.category != null && catalogMatch!.category.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('Kategorie: ${catalogMatch.category}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.numbers, size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text('Anzahl: ${err.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                if (err.notes.isNotEmpty) ...[
                                  const SizedBox(width: 16),
                                  const Icon(Icons.comment_outlined, size: 16, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      err.notes,
                                      style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: (!widget.isReadOnly && _errors.isNotEmpty)
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Weiterer Mangel'),
              onPressed: _openAddErrorDialog,
            )
          : null,
    );
  }
}

extension _FirstWhereOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
  E? firstWhereOrNull(bool Function(E element) test) {
    for (E element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
