import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import '../services/local_database_service.dart';
import '../models/models.dart';
import 'new_door_page.dart';
import 'job_selection_page.dart';

class DoorListPage extends StatefulWidget {
  const DoorListPage({super.key});

  @override
  State<DoorListPage> createState() => _DoorListPageState();
}

class _DoorListPageState extends State<DoorListPage> {
  List<Door> doors = [];
  bool _isSyncing = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selectedDoorIds = {};

  @override
  void initState() {
    super.initState();
    loadDoors();
  }

  Future<void> loadDoors() async {
    final results = await LocalDatabaseService.searchDoors(_searchController.text);
    setState(() => doors = results);
  }

  Future<void> deleteDoor(int id) async {
    await LocalDatabaseService.deleteDoor(id);
    await loadDoors();
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
          await loadDoors();
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
    if (_selectedDoorIds.isEmpty) return;

    setState(() => _isSyncing = true);
    try {
      final String downloadPath = Platform.isAndroid 
          ? '/storage/emulated/0/Download' 
          : (await getDownloadsDirectory())?.path ?? (await getApplicationDocumentsDirectory()).path;
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final exportPath = p.join(downloadPath, 'inspektion_ergebnis_$timestamp.db');

      await LocalDatabaseService.exportSelectiveJobPackage(
        _selectedDoorIds.toList(),
        exportPath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ergebnis-Paket erstellt: $exportPath'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _selectedDoorIds.clear());
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
      if (_selectedDoorIds.contains(id)) {
        _selectedDoorIds.remove(id);
      } else {
        _selectedDoorIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedDoorIds.length == doors.length) {
        _selectedDoorIds.clear();
      } else {
        _selectedDoorIds.addAll(doors.map((d) => d.id!));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isSelectionMode = _selectedDoorIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: isSelectionMode
            ? Text('${_selectedDoorIds.length} ausgewählt')
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
                    onChanged: (value) => loadDoors(),
                  )
                : const Text("Türenübersicht"),
        leading: isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedDoorIds.clear()),
              )
            : null,
        actions: isSelectionMode
            ? [
                IconButton(
                  icon: Icon(_selectedDoorIds.length == doors.length
                      ? Icons.check_box
                      : Icons.check_box_outline_blank),
                  tooltip: 'Alle auswählen',
                  onPressed: _selectAll,
                ),
                IconButton(
                  icon: const Icon(Icons.upload_file),
                  tooltip: 'Selektiver Export',
                  onPressed: _handleSelectiveExport,
                ),
              ]
            : [
                IconButton(
                  icon: Icon(_isSearching ? Icons.close : Icons.search),
                  onPressed: () {
                    setState(() {
                      _isSearching = !_isSearching;
                      if (!_isSearching) {
                        _searchController.clear();
                        loadDoors();
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
                            loadDoors();
                          }
                        },
                ),
              ],
      ),
      body: Stack(
        children: [
          doors.isEmpty
              ? const Center(child: Text("Keine Türen vorhanden"))
              : ListView.builder(
              itemCount: doors.length,
              itemBuilder: (context, index) {
                final d = doors[index];
                final isSelected = _selectedDoorIds.contains(d.id);

                return Dismissible(
                  key: Key(d.id.toString()),
                  background: Container(
                    color: Colors.red.shade400,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  direction: DismissDirection.startToEnd,
                  onDismissed: (_) => deleteDoor(d.id!),
                  child: Card(
                    color: isSelected ? Colors.blue.shade50 : null,
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      leading: isSelectionMode
                          ? Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(d.id!),
                            )
                          : const Icon(Icons.door_front_door, color: Colors.blue),
                      title: Text("Tür ${d.doorNumber}"),
                      subtitle: Text(d.roomDesignation),
                      trailing: isSelectionMode ? null : const Icon(Icons.chevron_right),
                      onTap: isSelectionMode
                          ? () => _toggleSelection(d.id!)
                          : () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DoorInspectionForm(door: d),
                                ),
                              );
                              loadDoors();
                            },
                      onLongPress: () => _toggleSelection(d.id!),
                    ),
                  ),
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
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const DoorInspectionForm(),
            ),
          );
          loadDoors();
        },
      ),
    );
  }
}
