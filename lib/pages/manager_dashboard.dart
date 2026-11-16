import 'package:flutter/material.dart';
import 'package:wartungstool/models/error_catalog.dart';
import '../services/database_service.dart';
import '../models/models.dart';
import 'error_consolidation_page.dart';
import 'door_options_manager_page.dart';
import '../services/app_version_service.dart';
import '../widgets/app_version_dialog.dart';
import '../widgets/craftnote_settings_dialog.dart';

class ManagerDashboard extends StatefulWidget {
  const ManagerDashboard({super.key});

  @override
  _ManagerDashboardState createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  // Navigation: 'door', 'window', 'all'
  String selectedAssetType = 'door';

  List<ErrorCatalog> doorErrors = [];
  List<ErrorCatalog> windowErrors = [];
  List<ErrorCatalog> filteredDoorErrors = [];
  List<ErrorCatalog> filteredWindowErrors = [];

  List<String> doorCategories = ['Alle'];
  List<String> windowCategories = ['Alle'];
  String selectedDoorCategory = 'Alle';
  String selectedWindowCategory = 'Alle';

  int pendingDoorCount = 0;
  int pendingWindowCount = 0;
  int get totalPendingCount => pendingDoorCount + pendingWindowCount;

  bool isLoading = true;
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadErrors();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _loadErrors() async {
    setState(() => isLoading = true);
    try {
      // Check if catalog is empty and auto-populate if necessary
      var approved =
          await DatabaseService.getAllErrorCatalog(status: 'Approved');
      var pending = await DatabaseService.getAllErrorCatalog(status: 'Pending');
      if (approved.isEmpty && pending.isEmpty) {
        await DatabaseService.checkAndInitializeCatalog();
        approved = await DatabaseService.getAllErrorCatalog(status: 'Approved');
        pending = await DatabaseService.getAllErrorCatalog(status: 'Pending');
      }

      final dbDoorCats =
          await DatabaseService.getErrorCatalogCategories(assetType: 'door');
      final dbWindowCats =
          await DatabaseService.getErrorCatalogCategories(assetType: 'window');

      final doors = approved
          .where((e) => e.assetType.toLowerCase() != 'window')
          .toList();
      final windows = approved
          .where((e) => e.assetType.toLowerCase() == 'window')
          .toList();

      final pDoors = pending
          .where((e) => e.assetType.toLowerCase() != 'window')
          .length;
      final pWindows = pending
          .where((e) => e.assetType.toLowerCase() == 'window')
          .length;

      setState(() {
        doorErrors = doors;
        windowErrors = windows;
        doorCategories = ['Alle', ...dbDoorCats];
        windowCategories = ['Alle', ...dbWindowCats];

        if (!doorCategories.contains(selectedDoorCategory)) {
          selectedDoorCategory = 'Alle';
        }
        if (!windowCategories.contains(selectedWindowCategory)) {
          selectedWindowCategory = 'Alle';
        }

        pendingDoorCount = pDoors;
        pendingWindowCount = pWindows;
        isLoading = false;
      });

      _filterErrors();
    } catch (e) {
      setState(() => isLoading = false);
      print('Error loading errors: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Laden: $e')),
      );
    }
  }

  void _filterErrors() {
    final query = searchController.text.trim().toLowerCase();

    setState(() {
      filteredDoorErrors = doorErrors.where((error) {
        final matchesCategory = selectedDoorCategory == 'Alle' ||
            error.category == selectedDoorCategory;
        final matchesSearch = query.isEmpty ||
            error.description.toLowerCase().contains(query) ||
            error.code.toLowerCase().contains(query) ||
            error.category.toLowerCase().contains(query);
        return matchesCategory && matchesSearch;
      }).toList();

      filteredWindowErrors = windowErrors.where((error) {
        final matchesCategory = selectedWindowCategory == 'Alle' ||
            error.category == selectedWindowCategory;
        final matchesSearch = query.isEmpty ||
            error.description.toLowerCase().contains(query) ||
            error.code.toLowerCase().contains(query) ||
            error.category.toLowerCase().contains(query);
        return matchesCategory && matchesSearch;
      }).toList();
    });
  }

  void _showEditErrorDialog({ErrorCatalog? error}) {
    String dialogAssetType = error?.assetType ??
        (selectedAssetType == 'window' ? 'window' : 'door');
    final codeController = TextEditingController(text: error?.code ?? '');
    final descriptionController =
        TextEditingController(text: error?.description ?? '');
    final categoryController =
        TextEditingController(text: error?.category ?? '');
    final validSeverities = ['low', 'medium', 'high', 'critical'];
    final rawSeverity =
        (error?.severity ?? 'medium').trim().toLowerCase().replaceAll('"', '');
    final initialSeverity = validSeverities.contains(rawSeverity)
        ? rawSeverity
        : DatabaseService.normalizeSeverity(rawSeverity);
    final severityController = TextEditingController(text: initialSeverity);
    final recommendationController =
        TextEditingController(text: error?.recommendation ?? '');
    final normReferenceController =
        TextEditingController(text: error?.normReference ?? '');

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentCategories = dialogAssetType == 'window'
              ? windowCategories.where((c) => c != 'Alle').toList()
              : doorCategories.where((c) => c != 'Alle').toList();

          return AlertDialog(
            title: Text(error == null ? 'Neuer Katalog-Fehler' : 'Fehler bearbeiten'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Objekttyp',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'door',
                          icon: Icon(Icons.door_front_door),
                          label: Text('Tür'),
                        ),
                        ButtonSegment<String>(
                          value: 'window',
                          icon: Icon(Icons.window),
                          label: Text('Fenster'),
                        ),
                      ],
                      selected: {dialogAssetType},
                      onSelectionChanged: (val) {
                        setDialogState(() {
                          dialogAssetType = val.first;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: codeController,
                      decoration: const InputDecoration(
                        labelText: 'Fehlercode',
                        hintText: 'z.B. 1.01 oder 9.05',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Beschreibung',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: categoryController,
                            decoration: const InputDecoration(
                              labelText: 'Kategorie',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        if (currentCategories.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          PopupMenuButton<String>(
                            tooltip: 'Aus bestehenden Kategorien wählen',
                            icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                            onSelected: (cat) {
                              setDialogState(() {
                                categoryController.text = cat;
                              });
                            },
                            itemBuilder: (ctx) => currentCategories
                                .map((c) => PopupMenuItem(value: c, child: Text(c)))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: validSeverities
                              .contains(severityController.text.toLowerCase())
                          ? severityController.text.toLowerCase()
                          : 'medium',
                      decoration: const InputDecoration(
                        labelText: 'Schweregrad',
                        border: OutlineInputBorder(),
                      ),
                      items: validSeverities.map((severity) {
                        return DropdownMenuItem<String>(
                          value: severity,
                          child: Text(_getSeverityDisplay(severity)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          severityController.text = value;
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: recommendationController,
                      decoration: const InputDecoration(
                        labelText: 'Empfehlung',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: normReferenceController,
                      decoration: const InputDecoration(
                        labelText: 'Normreferenz',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Abbrechen'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (codeController.text.trim().isNotEmpty &&
                      descriptionController.text.trim().isNotEmpty) {
                    final newError = ErrorCatalog(
                      errorId: error?.errorId,
                      code: codeController.text.trim(),
                      description: descriptionController.text.trim(),
                      category: categoryController.text.trim().isNotEmpty
                          ? categoryController.text.trim()
                          : 'Allgemein',
                      severity: severityController.text,
                      recommendation: recommendationController.text.trim(),
                      normReference: normReferenceController.text.trim(),
                      assetType: dialogAssetType,
                      status: error?.status ?? 'Approved',
                    );

                    await DatabaseService.insertErrorCatalog(newError);
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                    _loadErrors();
                  }
                },
                child: Text(error == null ? 'Erstellen' : 'Speichern'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _deleteError(ErrorCatalog error) {
    final isWin = error.assetType.toLowerCase() == 'window';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${isWin ? "Fenster-" : "Tür-"}Fehler löschen'),
        content: Text(
            'Möchten Sie den Fehler "${error.code} - ${error.description}" wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (error.errorId != null) {
                await DatabaseService.deleteErrorCatalog(error.errorId!);
                Navigator.pop(context);
                _loadErrors();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndReloadCatalog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Fehlerkatalog neu laden?'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Achtung: Dieser Vorgang liest den Fehlerkatalog aus der Vorlage (error_catalog.json) neu ein.\n',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '• Alle Standard-Fehlerbeschreibungen, Kategorien und Normverweise werden auf die Standardwerte zurückgesetzt.\n'
              '• Eigene Textanpassungen an Standardfehlern werden dabei überschrieben.\n'
              '• Bestehende Prüfungen, Mängelfotos und selbst erstellte Fehlercodes bleiben erhalten.\n\n'
              'Möchten Sie den Katalog wirklich auf die Standardwerte zurücksetzen?',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.restore_page, size: 18),
            label: const Text('Auf Standard zurücksetzen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => isLoading = true);
    try {
      await DatabaseService.checkAndInitializeCatalog(force: true);
      await _loadErrors();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehlerkatalog erfolgreich auf Standardwerte zurückgesetzt.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Neuladen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getSeverityDisplay(String severity) {
    switch (severity) {
      case 'low':
        return 'Niedrig';
      case 'medium':
        return 'Mittel';
      case 'high':
        return 'Hoch';
      case 'critical':
        return 'Kritisch';
      default:
        return severity;
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      case 'critical':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedErrors = selectedAssetType == 'door'
        ? filteredDoorErrors
        : selectedAssetType == 'window'
            ? filteredWindowErrors
            : ([...filteredDoorErrors, ...filteredWindowErrors]
              ..sort((a, b) => a.code.compareTo(b.code)));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Katalog & Freigaben (Manager)',
                style: TextStyle(fontSize: 18)),
            Text(
              AppVersionService.getCompactVersionInfo(isManager: true),
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          if (totalPendingCount > 0)
            IconButton(
              icon: Badge.count(
                count: totalPendingCount,
                backgroundColor: Colors.deepOrange,
                child: const Icon(Icons.rule, color: Colors.deepOrange),
              ),
              tooltip: '$totalPendingCount Anfragen prüfen',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ErrorConsolidationPage()),
                );
                _loadErrors();
              },
            ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => DoorOptionsManagerPage(
                          initialAssetType: selectedAssetType == 'window'
                              ? 'window'
                              : 'door',
                        )),
              );
            },
            tooltip: 'Stammdaten-Optionen verwalten',
          ),
          IconButton(
            icon: const Icon(Icons.storage),
            onPressed: _confirmAndReloadCatalog,
            tooltip: 'Fehlerkatalog auf Standard zurücksetzen',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadErrors,
            tooltip: 'Aktualisieren',
          ),
          IconButton(
            icon: const Icon(Icons.cloud_sync, color: Colors.blueAccent),
            tooltip: 'Craftnote API & Cloud-Einstellungen',
            onPressed: () => CraftnoteSettingsDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'App-Info & Version',
            onPressed: () => AppVersionDialog.show(context, isManager: true),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Pending proposals banner
                if (totalPendingCount > 0)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.deepOrange.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.rule, color: Colors.deepOrange.shade800),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$totalPendingCount ${totalPendingCount == 1 ? "neue Fehler-Anfrage" : "neue Fehler-Anfragen"} ausstehend',
                                style: TextStyle(
                                  color: Colors.deepOrange.shade900,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (pendingDoorCount > 0)
                                    Text(
                                      '$pendingDoorCount Türen',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.indigo.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  if (pendingDoorCount > 0 &&
                                      pendingWindowCount > 0)
                                    const Text('  •  ',
                                        style: TextStyle(color: Colors.grey)),
                                  if (pendingWindowCount > 0)
                                    Text(
                                      '$pendingWindowCount Fenster',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.teal.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const ErrorConsolidationPage()),
                            );
                            _loadErrors();
                          },
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: const Text('Jetzt prüfen'),
                        ),
                      ],
                    ),
                  ),

                // Search, Asset Type Segment, and Category filters
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Shared Search bar
                      TextField(
                        controller: searchController,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: 'Katalog durchsuchen (Türen & Fenster)',
                          hintText: 'Code, Beschreibung oder Kategorie...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    searchController.clear();
                                    _filterErrors();
                                  },
                                )
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) => _filterErrors(),
                      ),
                      const SizedBox(height: 12),

                      // Asset Type Selector (Türen, Fenster, Alle)
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment<String>(
                            value: 'door',
                            icon: const Icon(Icons.door_front_door),
                            label: Text('Türen (${filteredDoorErrors.length})'),
                          ),
                          ButtonSegment<String>(
                            value: 'window',
                            icon: const Icon(Icons.window),
                            label: Text('Fenster (${filteredWindowErrors.length})'),
                          ),
                          ButtonSegment<String>(
                            value: 'all',
                            icon: const Icon(Icons.all_inclusive),
                            label: Text(
                                'Alle (${filteredDoorErrors.length + filteredWindowErrors.length})'),
                          ),
                        ],
                        selected: {selectedAssetType},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() {
                            selectedAssetType = newSelection.first;
                          });
                        },
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: selectedAssetType == 'door'
                              ? Colors.indigo
                              : selectedAssetType == 'window'
                                  ? Colors.teal
                                  : Colors.blueGrey,
                          selectedForegroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Separated Category filters
                      if (selectedAssetType == 'door')
                        _buildCategoryChipList(
                          categories: doorCategories,
                          selectedCategory: selectedDoorCategory,
                          activeColor: Colors.indigo,
                          onSelected: (cat) {
                            setState(() => selectedDoorCategory = cat);
                            _filterErrors();
                          },
                        )
                      else if (selectedAssetType == 'window')
                        _buildCategoryChipList(
                          categories: windowCategories,
                          selectedCategory: selectedWindowCategory,
                          activeColor: Colors.teal,
                          onSelected: (cat) {
                            setState(() => selectedWindowCategory = cat);
                            _filterErrors();
                          },
                        )
                      else
                        // 'all' mode: Show both separated category rows
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.door_front_door,
                                    size: 14, color: Colors.indigo),
                                const SizedBox(width: 4),
                                Text(
                                  'Kategorien Türen:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo.shade800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _buildCategoryChipList(
                              categories: doorCategories,
                              selectedCategory: selectedDoorCategory,
                              activeColor: Colors.indigo,
                              onSelected: (cat) {
                                setState(() => selectedDoorCategory = cat);
                                _filterErrors();
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.window,
                                    size: 14, color: Colors.teal),
                                const SizedBox(width: 4),
                                Text(
                                  'Kategorien Fenster:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal.shade800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _buildCategoryChipList(
                              categories: windowCategories,
                              selectedCategory: selectedWindowCategory,
                              activeColor: Colors.teal,
                              onSelected: (cat) {
                                setState(() => selectedWindowCategory = cat);
                                _filterErrors();
                              },
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                // Separated Statistics Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildStatisticsSection(),
                ),

                const SizedBox(height: 12),

                // Error list
                Expanded(
                  child: displayedErrors.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.search_off,
                                  size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              const Text('Keine Fehler gefunden',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('Passen Sie Ihre Such- oder Filterkriterien an',
                                  style: TextStyle(color: Colors.grey.shade600)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: displayedErrors.length,
                          itemBuilder: (context, index) {
                            return _buildErrorCard(displayedErrors[index]);
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: "add_error",
        onPressed: () => _showEditErrorDialog(),
        tooltip: selectedAssetType == 'window'
            ? 'Neuen Fenster-Fehler im Katalog erstellen'
            : selectedAssetType == 'door'
                ? 'Neuen Tür-Fehler im Katalog erstellen'
                : 'Neuen Fehler im Katalog erstellen',
        backgroundColor: selectedAssetType == 'window'
            ? Colors.teal
            : selectedAssetType == 'door'
                ? Colors.indigo
                : null,
        foregroundColor: (selectedAssetType == 'window' ||
                selectedAssetType == 'door')
            ? Colors.white
            : null,
        icon: const Icon(Icons.add),
        label: Text(
          selectedAssetType == 'window'
              ? 'Neuer Fenster-Fehler'
              : selectedAssetType == 'door'
                  ? 'Neuer Tür-Fehler'
                  : 'Neuer Fehler',
        ),
      ),
    );
  }

  Widget _buildCategoryChipList({
    required List<String> categories,
    required String selectedCategory,
    required Color activeColor,
    required ValueChanged<String> onSelected,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((category) {
          final isSelected = selectedCategory == category;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(category),
              selected: isSelected,
              selectedColor: activeColor.withValues(alpha: 0.18),
              checkmarkColor: activeColor,
              labelStyle: TextStyle(
                color: isSelected ? activeColor : null,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              side: BorderSide(
                color: isSelected ? activeColor : Colors.grey.shade300,
              ),
              onSelected: (_) => onSelected(category),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatisticsSection() {
    if (selectedAssetType == 'door') {
      return _buildStatCard(
        title: 'Katalog-Statistik Türen',
        icon: Icons.door_front_door,
        themeColor: Colors.indigo,
        total: filteredDoorErrors.length,
        pending: pendingDoorCount,
        critical: filteredDoorErrors
            .where((e) => e.severity.toLowerCase() == 'critical')
            .length,
        high: filteredDoorErrors
            .where((e) => e.severity.toLowerCase() == 'high')
            .length,
        medium: filteredDoorErrors
            .where((e) => e.severity.toLowerCase() == 'medium')
            .length,
        low: filteredDoorErrors
            .where((e) => e.severity.toLowerCase() == 'low')
            .length,
      );
    } else if (selectedAssetType == 'window') {
      return _buildStatCard(
        title: 'Katalog-Statistik Fenster',
        icon: Icons.window,
        themeColor: Colors.teal,
        total: filteredWindowErrors.length,
        pending: pendingWindowCount,
        critical: filteredWindowErrors
            .where((e) => e.severity.toLowerCase() == 'critical')
            .length,
        high: filteredWindowErrors
            .where((e) => e.severity.toLowerCase() == 'high')
            .length,
        medium: filteredWindowErrors
            .where((e) => e.severity.toLowerCase() == 'medium')
            .length,
        low: filteredWindowErrors
            .where((e) => e.severity.toLowerCase() == 'low')
            .length,
      );
    } else {
      // 'all' mode: Show both side-by-side or stacked
      return LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 720;
          final doorCard = _buildStatCard(
            title: 'Katalog-Statistik Türen',
            icon: Icons.door_front_door,
            themeColor: Colors.indigo,
            total: filteredDoorErrors.length,
            pending: pendingDoorCount,
            critical: filteredDoorErrors
                .where((e) => e.severity.toLowerCase() == 'critical')
                .length,
            high: filteredDoorErrors
                .where((e) => e.severity.toLowerCase() == 'high')
                .length,
            medium: filteredDoorErrors
                .where((e) => e.severity.toLowerCase() == 'medium')
                .length,
            low: filteredDoorErrors
                .where((e) => e.severity.toLowerCase() == 'low')
                .length,
          );
          final windowCard = _buildStatCard(
            title: 'Katalog-Statistik Fenster',
            icon: Icons.window,
            themeColor: Colors.teal,
            total: filteredWindowErrors.length,
            pending: pendingWindowCount,
            critical: filteredWindowErrors
                .where((e) => e.severity.toLowerCase() == 'critical')
                .length,
            high: filteredWindowErrors
                .where((e) => e.severity.toLowerCase() == 'high')
                .length,
            medium: filteredWindowErrors
                .where((e) => e.severity.toLowerCase() == 'medium')
                .length,
            low: filteredWindowErrors
                .where((e) => e.severity.toLowerCase() == 'low')
                .length,
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: doorCard),
                const SizedBox(width: 12),
                Expanded(child: windowCard),
              ],
            );
          } else {
            return Column(
              children: [
                doorCard,
                const SizedBox(height: 8),
                windowCard,
              ],
            );
          }
        },
      );
    }
  }

  Widget _buildStatCard({
    required String title,
    required IconData icon,
    required Color themeColor,
    required int total,
    required int pending,
    required int critical,
    required int high,
    required int medium,
    required int low,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            BorderSide(color: themeColor.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 18, color: themeColor),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Gesamt', total, themeColor),
                _buildStatItem('Offen', pending, Colors.orange),
                _buildStatItem('Kritisch', critical, Colors.purple),
                _buildStatItem('Hoch', high, Colors.red),
                _buildStatItem('Mittel', medium, Colors.orange.shade700),
                _buildStatItem('Niedrig', low, Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard(ErrorCatalog error) {
    final isWindow = error.assetType.toLowerCase() == 'window';
    final accentColor = isWindow ? Colors.teal : Colors.indigo;
    final assetLabel = isWindow ? 'Fenster' : 'Tür';
    final assetIcon = isWindow ? Icons.window : Icons.door_front_door;
    final severityColor = _getSeverityColor(error.severity);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side:
            BorderSide(color: accentColor.withValues(alpha: 0.35), width: 1.2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accentColor, width: 5),
            ),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            leading: CircleAvatar(
              backgroundColor: severityColor,
              child: Text(
                error.code.contains('.')
                    ? error.code.split('.').first
                    : error.code,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Row(
              children: [
                Text(
                  error.code,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 8),
                // Visual badge for Tür vs Fenster
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        isWindow ? Colors.teal.shade50 : Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isWindow
                          ? Colors.teal.shade200
                          : Colors.indigo.shade200,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(assetIcon, size: 12, color: accentColor),
                      const SizedBox(width: 4),
                      Text(
                        assetLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  error.description,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        error.category,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: severityColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getSeverityDisplay(error.severity),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: severityColor,
                        ),
                      ),
                    ),
                    if (error.normReference.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blueGrey.shade200),
                        ),
                        child: Text(
                          error.normReference,
                          style: TextStyle(
                              fontSize: 10, color: Colors.blueGrey.shade700),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  _showEditErrorDialog(error: error);
                } else if (value == 'delete') {
                  _deleteError(error);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Bearbeiten'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Löschen'),
                    ],
                  ),
                ),
              ],
            ),
            onTap: () => _showEditErrorDialog(error: error),
          ),
        ),
      ),
    );
  }
}
