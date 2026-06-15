import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../services/gaeb_export_service.dart';
import '../services/test_data_generator.dart';
import '../models/door.dart';
import '../services/kinchi_api_service.dart';

// Define a typedef for the complex list type to improve readability and avoid parsing issues
typedef InspectionList = List<Map<String, dynamic>>;

class JobSelectionPage extends StatefulWidget {
  /// This page allows inspectors to view available jobs from the Main DB
  /// and download them to the Local DB for offline use.
  /// It is the starting point of the inspector workflow.
  const JobSelectionPage({super.key});

  @override
  State<JobSelectionPage> createState() => _JobSelectionPageState();
}

class _JobSelectionPageState extends State<JobSelectionPage> {
  // State variable to track if a job is currently being transferred between databases
  bool _isDownloading = false;
  bool _isImporting = false;
  late Future<InspectionList> _inspectionsFuture;
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selectedInspectionIds = {};
  InspectionList _currentVisibleResults = [];

  final KinchiApiService _apiService = KinchiApiService();

  /// Initializes the inspection list
  @override
  void initState() {
    super.initState();
    // Initialize the future once to prevent re-fetching on every rebuild
    _refreshInspections();
  }

  /// Handles the cloud upload of a generated GAEB file
  Future<void> _uploadToCloud(File file, String jobNumber) async {
    try {
      // Using hardcoded test credentials as requested
      final loggedIn = await _apiService.login(
        "konzschaefer  ", 
        "rihute94"
      );

      if (!loggedIn) throw Exception("Login fehlgeschlagen");

      // Dynamically fetch directories to find a valid ID, avoiding the 400 ValidationError
      final List<dynamic> directories = await _apiService.getDirectories();
      if (directories.isEmpty) {
        throw Exception("Keine Zielverzeichnisse in der Cloud konfiguriert.");
      }
      final int targetDirectoryId = directories.first['id'] as int;

      final docId = await _apiService.uploadGaebFile(file.path, targetDirectoryId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cloud-Upload erfolgreich (ID: $docId)'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cloud-Upload fehlgeschlagen: $e'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  /// Confirms and executes deletion of specific inspections
  Future<void> _handleDeleteInspections(List<int> ids) async {
    final bool confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Löschen bestätigen'),
        content: Text('${ids.length} Auftrag/Aufträge und zugehörige Prüfungsdaten unwiderruflich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      await DatabaseService.deleteInspections(ids);
      _refreshInspections();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ausgewählte Daten gelöscht.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Löschen: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Confirms and executes clearing of all job-related data
  Future<void> _handlePurgeAll() async {
    final bool confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alle Auftragsdaten löschen?'),
        content: const Text(
          'Dies wird ALLE Aufträge, Prüfungsdetails und Fehlerzuordnungen löschen.\n\n'
          'Türen (Stammdaten) und der Fehlerkatalog bleiben erhalten.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Alles löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;
    if (confirm) await DatabaseService.purgeAllInspections();
    _refreshInspections();
  }

  void _refreshInspections() {
    setState(() {
      _selectedInspectionIds.clear();
      _currentVisibleResults = [];
      _inspectionsFuture = DatabaseService.searchInspections(_searchController.text);
    });
  }

  /// Selects all items currently visible in the search results (Block 3)
  void _selectAllResults() {
    setState(() {
      for (var job in _currentVisibleResults) {
        final id = job['inspectionId'];
        if (id != null) {
          _selectedInspectionIds.add(id as int);
        }
      }
    });
  }

  /// Collects full data for selected inspections including doors and errors
  Future<List<Map<String, dynamic>>> _prepareExportData() async {
    List<Map<String, dynamic>> flatExportList = [];
    
    for (int inspectionId in _selectedInspectionIds) {
      final doors = await DatabaseService.getDoorsByInspectionIds([inspectionId]);

      final junctionList = await DatabaseService.getInspectionDoorsByInspectionId(inspectionId);
      final List<int> junctionIds = junctionList.map((j) => j['id'] as int).toList();
      final allErrors = await DatabaseService.getErrorsForInspectionDoorIds(junctionIds);

      for (var door in doors) {
        // Find the junction that links this door to this inspection
        final junction = junctionList.firstWhere(
          (j) => j['doorId'] == door.id, 
          orElse: () => <String, dynamic>{}
        );
        if (junction.isEmpty) continue;

        final doorErrors = allErrors
            .where((e) => e['inspectionDoorId'] == junction['id'])
            .map((e) => {
              'code': e['code']?.toString() ?? 'MISSING_CODE', // Fallback for RNoPart
              'description': e['description']?.toString() ?? 'Fehlerbeschreibung fehlt', // Fallback for description
            })
            .toList();

        flatExportList.add({
          'door': door,
          'errors': doorErrors,
        });
      }
    }
    return flatExportList;
  }

  /// Orchestrates the data handoff from Main DB to Working DB.
  /// Can handle a single job or a 'Wide Spectrum' package of multiple inspections.
  Future<void> _handleJobDownload(List<int> ids) async {
    // Show the modal loading overlay
    setState(() => _isDownloading = true);

    try {
      // Logic: Orchestrates the handoff from Main DB to Working DB.
      // It wipes the old 'working.db' and injects the new package (Isolation Protocol).
      await LocalDatabaseService.downloadJobPackage(
        inspectionIds: ids,
      );

      // Export the file to the Documents folder for manual handoff
      final String downloadPath = Platform.isAndroid 
          ? '/storage/emulated/0/Download' 
          : (await getDownloadsDirectory())?.path ?? (await getApplicationDocumentsDirectory()).path;
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final exportPath = p.join(downloadPath, 'inspektion_paket_$timestamp.db');
      
      await LocalDatabaseService.exportWorkingDb(exportPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Paket erstellt: $exportPath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );

        // Clear selection after successful export so manager can continue working
        _refreshInspections();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Download: $e')),
        );
      }
    } finally {
      // Hide the modal loading overlay regardless of success or failure
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// Handles the import of an inspector's result package into the Main DB (Block 4)
  Future<void> _handleImportResultPackage() async {
    try {
      // Select the .db file from the inspector
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;

        if (!mounted) return;

        // User Confirmation Dialog (German UX)
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Ergebnis-Paket importieren'),
            content: const Text(
              'Möchten Sie dieses Paket in die Haupt-Datenbank einspielen? '
              'Bestehende Daten werden bei Übereinstimmung (Alias/Auftragsnummer) aktualisiert.'
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Importieren', style: TextStyle(color: Colors.blue)),
              ),
            ],
          ),
        );

        if (confirm != true) return;

        setState(() => _isImporting = true);
        
        // Execute the merge logic defined in Block 2
        await DatabaseService.importAndMergePackage(path);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Paket erfolgreich in Haupt-DB integriert.'),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh to show updated data
          _refreshInspections();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import-Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  /// Interactive Data Generation Dialog for manual testing efficiency
  void _showSeedDataDialog() {
    int customers = 2;
    int objects = 2;
    int doors = 5;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Testdaten generieren'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Wählen Sie die Parameter für die Massenerstellung:'),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: customers,
                decoration: const InputDecoration(labelText: 'Anzahl Kunden'),
                items: [1, 2, 5, 10].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                onChanged: (v) => setDialogState(() => customers = v!),
              ),
              DropdownButtonFormField<int>(
                initialValue: objects,
                decoration: const InputDecoration(labelText: 'Objekte pro Kunde'),
                items: [1, 2, 3].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                onChanged: (v) => setDialogState(() => objects = v!),
              ),
              DropdownButtonFormField<int>(
                initialValue: doors,
                decoration: const InputDecoration(labelText: 'Türen pro Objekt'),
                items: [5, 10, 20, 50].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                onChanged: (v) => setDialogState(() => doors = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                setState(() => _isDownloading = true);
                try {
                  await DatabaseService.clearDatabase(); // Start with a clean slate
                  await TestDataGenerator.generate(
                    numCustomers: customers,
                    numObjectsPerCustomer: objects,
                    numDoorsPerObject: doors,
                  );
                  _refreshInspections();
                } finally {
                  setState(() => _isDownloading = false);
                }
              },
              child: const Text('Generieren'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auftrag auswählen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Alle Aufträge löschen',
            onPressed: _isImporting || _isDownloading ? null : _handlePurgeAll,
          ),
          IconButton(
            icon: const Icon(Icons.drive_folder_upload),
            tooltip: 'Ergebnis importieren',
            onPressed: _isImporting || _isDownloading ? null : _handleImportResultPackage,
          ),
          IconButton(
            icon: const Icon(Icons.science_outlined),
            tooltip: 'Testdaten generieren',
            onPressed: _isDownloading ? null : _showSeedDataDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Persistent Search Bar Widget
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Aufträge durchsuchen',
                hintText: 'Kunde, Projekt oder Datum...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _refreshInspections();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) => _refreshInspections(),
            ),
          ),
          // Selection Controls Row (Block 3)
          if (_searchController.text.isNotEmpty || _selectedInspectionIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  if (_currentVisibleResults.isNotEmpty)
                    TextButton.icon(
                      onPressed: _selectAllResults,
                      icon: const Icon(Icons.select_all),
                      label: const Text('Alle Ergebnisse wählen'),
                    ),
                  const Spacer(),
                  if (_selectedInspectionIds.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => setState(() => _selectedInspectionIds.clear()),
                      icon: const Icon(Icons.deselect),
                      label: Text('Auswahl aufheben (${_selectedInspectionIds.length})'),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              // Stack allows the 'Downloading' indicator to appear on top of the list
              children: [
                FutureBuilder<InspectionList>(
                  future: _inspectionsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text('Keine passenden Aufträge gefunden.'),
                      );
                    }

                    final inspections = snapshot.data!;
                    
                    // Cache currently visible results for selection logic
                    _currentVisibleResults = inspections;

                    return ListView.builder(
                      itemCount: inspections.length,
                      itemBuilder: (context, index) {
                        final job = inspections[index];
                        final id = job['inspectionId'];
                        final isSelected = _selectedInspectionIds.contains(id);

                        void toggleSelection() {
                          setState(() {
                            if (isSelected) {
                              _selectedInspectionIds.remove(id);
                            } else {
                              _selectedInspectionIds.add(id);
                            }
                          });
                        }

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                            leading: const Icon(Icons.business, color: Colors.blue),
                            title: Text(job['clientName'] ?? 'Unbekannter Kunde'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Projekt: ${job['jobNumber']}'),
                                Text('Datum: ${job['date']}'),
                              ],
                            ),
                            trailing: Checkbox(
                              value: isSelected,
                              onChanged: (_) => toggleSelection(),
                            ),
                            onTap: _isDownloading 
                                ? null 
                                : (_selectedInspectionIds.isEmpty 
                                    ? () => _handleJobDownload([job['inspectionId']])
                                    : toggleSelection),
                            onLongPress: toggleSelection,
                          ),
                        );
                      },
                    );
                  },
                ),
                // UI: Conditional overlay during the sync process
                if (_isDownloading)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 20),
                          Text(
                            'Job-Daten werden vorbereitet...',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                // UI: Overlay for the import process
                if (_isImporting)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 20),
                          Text(
                            'Paket wird importiert...',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _selectedInspectionIds.isEmpty ? null : BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: () => _handleDeleteInspections(_selectedInspectionIds.toList()),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Auswahl löschen',
            ),
            const VerticalDivider(),
            TextButton.icon(
              onPressed: () async {
                final inspection = _currentVisibleResults.firstWhere((i) => _selectedInspectionIds.contains(i['inspectionId']));
                final service = GaebExportService(
                  customer: inspection['clientName'] ?? 'Unbekannt',
                  projectName: inspection['projectName'] ?? 'Unbekannt',
                  jobNumber: inspection['jobNumber'] ?? 'MultiJob',
                );
                
                final data = await _prepareExportData();
                final file = await service.exportToD83(data);
                if (mounted && file != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('GAEB 90 exportiert nach: ${file.path}')),
                  );
                  
                  // Trigger Cloud Upload
                  await _uploadToCloud(file, service.jobNumber);
                }
              },
              icon: const Icon(Icons.description),
              label: const Text('GAEB 90 exportieren'),
            ),
            const VerticalDivider(),
            TextButton.icon(
              onPressed: () async {
                final inspection = _currentVisibleResults.firstWhere((i) => _selectedInspectionIds.contains(i['inspectionId']));
                final service = GaebExportService(
                  customer: inspection['clientName'] ?? 'Unbekannt',
                  projectName: inspection['projectName'] ?? 'Unbekannt',
                  jobNumber: inspection['jobNumber'] ?? 'MultiJob',
                );

                final data = await _prepareExportData();
                final file = await service.exportToXml(data);
                if (mounted && file != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('GAEB XML exportiert nach: ${file.path}')),
                  );

                  // Trigger Cloud Upload
                  await _uploadToCloud(file, service.jobNumber);
                }
              },
              icon: const Icon(Icons.code),
              label: const Text('GAEB XML exportieren'),
            ),
            const VerticalDivider(),
            TextButton.icon(
              onPressed: () => _handleJobDownload(_selectedInspectionIds.toList()),
              icon: const Icon(Icons.download_for_offline, color: Colors.green),
              label: const Text(
                'Paket laden',
                style: TextStyle(color: Colors.green),
              ),
            ),
          ],
        ),
      ),
    );
  }
}