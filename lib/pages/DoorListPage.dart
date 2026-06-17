import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import '../services/local_database_service.dart';
import '../models/models.dart' hide JobSelectionPage; // Hide JobSelectionPage to prevent conflict
import '../widgets/inspection_summary_card.dart';
import 'new_door_page.dart';
import 'job_selection_page.dart';
import 'inspection_doors_page.dart';

class DoorListPage extends StatefulWidget {
  const DoorListPage({super.key});

  @override
  State<DoorListPage> createState() => _DoorListPageState();
}

class _DoorListPageState extends State<DoorListPage> {
  List<Map<String, dynamic>> inspections = [];
  bool _isSyncing = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    loadInspections();
  }

  Future<void> loadInspections() async {
    final results = await LocalDatabaseService.getAllInspections();
    setState(() => inspections = results);
  }

  /// Confirms deletion with the user, consistent with JobSelectionPage logic.
  Future<bool> _confirmDeletion(int count) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Löschen bestätigen'),
        content: Text('$count Tür(en) und zugehörige Prüfungsdaten unwiderruflich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;
  }

  /// Handles both single and bulk deletion of doors.
  Future<void> _handleDeleteDoors(List<int> ids) async {
    if (ids.isEmpty) return;

    final confirmed = await _confirmDeletion(ids.length);
    if (!confirmed) return;

    try {
      setState(() => _isSyncing = true);
      // Since ids are inspectionIds at this level, use purgeExportedData
      await LocalDatabaseService.purgeExportedData(ids);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ausgewählte Türen gelöscht.')),
        );
        setState(() {
          _selectedIds.clear();
        });
        await loadInspections();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Löschen: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  /// Opens a file picker to select a .db file and imports it into the Working DB.
  /// This allows inspectors to load packages prepared by the manager.
  Future<void> _handleImportPaket() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;

        if (!mounted) return;

        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Paket importieren'),
            content: const Text(
              'Möchten Sie dieses Inspektionspaket importieren? '
              'Bestehende lokale Daten auf diesem Gerät werden überschrieben.'
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Importieren', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );

        if (confirm != true) return;

        setState(() => _isSyncing = true);
        await LocalDatabaseService.importWorkingDb(path);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Paket erfolgreich importiert.'), backgroundColor: Colors.green),
          );
          // Reset search state to show all newly imported doors
          setState(() {
            _searchController.clear();
            _isSearching = false;
          });
          await loadInspections();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import-Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  /// Triggers the selective export for the inspector results
  Future<void> _handleSelectiveExport() async {
    if (_selectedIds.isEmpty) return;

    setState(() => _isSyncing = true);
    try {
      // Resolve all Door IDs belonging to the selected inspections
      List<int> doorIdsToExport = [];
      for (int inspId in _selectedIds) {
        final doors = await LocalDatabaseService.getDoorsByInspectionId(inspId);
        doorIdsToExport.addAll(doors.map((d) => d.id!));
      }

      if (doorIdsToExport.isEmpty) throw Exception('Keine Türen in den gewählten Aufträgen gefunden.');

      final String downloadPath = Platform.isAndroid 
          ? '/storage/emulated/0/Download' 
          : (await getDownloadsDirectory())?.path ?? (await getApplicationDocumentsDirectory()).path;
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final exportPath = p.join(downloadPath, 'inspektion_ergebnis_$timestamp.db');

      await LocalDatabaseService.exportSelectiveJobPackage(
        doorIdsToExport,
        exportPath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ergebnis-Paket erstellt: $exportPath'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _selectedIds.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export-Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == inspections.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(inspections.map((i) => i['inspectionId'] as int));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isSelectionMode = _selectedIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: isSelectionMode
            ? Text('${_selectedIds.length} ausgewählt')
            : _isSearching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Suchen (Tür, Code, Fehler)...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.white70),
                    ),
                    style: const TextStyle(color: Colors.white),
                    onChanged: (value) => loadInspections(),
                  )
                : const Text("Prüfpakete (Techniker)"),
        leading: isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedIds.clear()),
              )
            : null,
        actions: isSelectionMode
            ? [
                IconButton(
                  icon: Icon(_selectedIds.length == inspections.length
                      ? Icons.check_box
                      : Icons.check_box_outline_blank),
                  tooltip: 'Alle auswählen',
                  onPressed: _selectAll,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.admin_panel_settings),
                  tooltip: 'Projektleiter',
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const JobSelectionPage()),
                  ),
                ),
                IconButton(
                  icon: Icon(_isSearching ? Icons.close : Icons.search),
                  onPressed: () {
                    setState(() {
                      _isSearching = !_isSearching;
                      if (!_isSearching) {
                        _searchController.clear();
                        loadInspections();
                      }
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.file_open),
                  tooltip: 'Paket importieren',
                  onPressed: _isSyncing ? null : _handleImportPaket,
                ),
                IconButton(
                  icon: const Icon(Icons.cloud_download),
                  tooltip: 'Auftrag aus Haupt-DB laden',
                  onPressed: _isSyncing
                      ? null
                      : () async {
                          final result = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(builder: (context) => const JobSelectionPage()),
                          );
                          if (result == true) {
                            loadInspections();
                          }
                        },
                ),
              ],
      ),
      body: Stack(
        children: [
          inspections.isEmpty
              ? const Center(child: Text("Keine Aufträge geladen"))
              : ListView.builder(
              itemCount: inspections.length,
              itemBuilder: (context, index) {
                final insp = inspections[index];
                final id = insp['inspectionId'] as int;
                final isSelected = _selectedIds.contains(id);

                return InspectionSummaryCard(
                  inspectionId: id,
                  clientName: insp['clientName'] ?? 'Unbekannt',
                  jobNumber: insp['jobNumber'] ?? 'N/A',
                  date: insp['date'] ?? '',
                  isSelected: isSelected,
                  onSelectionChanged: (value) => _toggleSelection(id),
                  onLongPress: () => _toggleSelection(id),
                  onTap: () async {
                    if (isSelectionMode) {
                      _toggleSelection(id);
                    } else {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InspectionDoorsPage(
                            inspectionId: id,
                            title: insp['clientName'] ?? 'Türenliste',
                            isManagerMode: false,
                          ),
                        ),
                      );
                      loadInspections();
                    }
                  },
                );
              },
            ),
          // UI: Loading overlay for the sync process
          if (_isSyncing)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Card(
                  margin: EdgeInsets.all(32),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text("Synchronisierung läuft..."),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: !isSelectionMode
          ? null
          : BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    onPressed: () => _handleDeleteDoors(_selectedIds.toList()),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Auswahl löschen',
                  ),
                  const VerticalDivider(),
                  TextButton.icon(
                    onPressed: _handleSelectiveExport,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Exportieren'),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const DoorInspectionForm(),
            ),
          );
          loadInspections();
        },
      ),
    );
  }
}
