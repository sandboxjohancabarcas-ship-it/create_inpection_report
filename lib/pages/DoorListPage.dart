import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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

  /// Handles the upload process from Working DB to Main DB
  Future<void> _handleSync() async {
    // Prevention: Don't start if already syncing
    if (_isSyncing) return;

    setState(() => _isSyncing = true);

    try {
      // Logic: Calls the service that iterates through all 'pending' records
      // and pushes them to the Main Database Service.
      await LocalDatabaseService.syncToMainDatabase();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Daten erfolgreich hochgeladen und synchronisiert!'),
            backgroundColor: Colors.green,
          ),
        );
        // Refresh: After sync, the local DB is typically cleared of the finished job
        await loadDoors();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Synchronisierungsfehler: $e'),
            backgroundColor: Colors.red,
          ),
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
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
        lockParentWindow: true, // Helpful for Windows/Desktop stability
      );

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching 
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
        actions: [
          // Action: Toggle search bar
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
          // Action: Import a .db package file
          IconButton(
            icon: const Icon(Icons.file_open),
            tooltip: 'Paket importieren',
            onPressed: _isSyncing ? null : _handleImportPaket,
          ),
          // Action: Push local data to Main DB
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Daten in Haupt-DB hochladen',
            onPressed: _isSyncing ? null : _handleSync,
          ),
          // Action: Fetch job from Main DB
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
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.storage, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text("Keine lokalen Daten vorhanden."),
                      const SizedBox(height: 8),
                      const Text("Bitte importieren Sie ein Paket (Ordner-Icon)"),
                      const Text("oder laden Sie Aufträge aus der Haupt-DB."),
                    ],
                  ),
                )
              : ListView.builder(
              itemCount: doors.length,
              itemBuilder: (context, index) {
                final d = doors[index];

                return Dismissible(
                  key: Key(d.id.toString()),
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  direction: DismissDirection.startToEnd,
                  onDismissed: (_) => deleteDoor(d.id!),
                  child: ListTile(
                    title: Text("Tür ${d.doorNumber}"),
                    subtitle: Text(d.roomDesignation),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            await deleteDoor(d.id!);
                          },
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DoorInspectionForm(door: d),
                        ),
                      );
                      loadDoors();
                    },
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
