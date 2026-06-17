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
import '../widgets/inspection_summary_card.dart';
import 'inspection_doors_page.dart';
import 'DoorListPage.dart'; // Import DoorListPage for navigation
import 'manager_dashboard.dart';
import 'package:http/http.dart' as http;

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
  /// Authentication and directory selection already happened in _confirmCloudUpload
  Future<void> _uploadToCloud(File file, String jobNumber, int directoryId) async {
    if (!mounted) return;

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datei wird hochgeladen...')),
        );
      }
      final docId = await _apiService.uploadGaebFile(file.path, directoryId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cloud-Upload erfolgreich (Dokument ID: $docId)'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      String errorMessage = 'Unbekannter Fehler';
      if (e is Exception) {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      } else if (e is http.ClientException) {
        errorMessage = 'Netzwerkfehler: ${e.message}';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cloud-Upload fehlgeschlagen: $errorMessage'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  /// Asks the user if they want to upload the file to Kinchi and which directory to use.
  /// Returns the selected directory ID or null if cancelled.
  Future<int?> _confirmCloudUpload() async {
    // 1. Ask user to select credentials
    final userCredentials = await _showUserSelectionDialog();
    if (userCredentials == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload abgebrochen.')));
      return null;
    }

    // 2. Authenticate
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anmeldung am Cloud-Dienst...')));
    try {
      final loggedIn = await _apiService.login(userCredentials['username']!, userCredentials['password']!);
      if (!loggedIn) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login fehlgeschlagen.'), backgroundColor: Colors.orange));
        return null;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login-Fehler: $e'), backgroundColor: Colors.orange));
      return null;
    }

    // 3. Fetch directories
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verzeichnisse werden geladen...')));
    List<dynamic> fetchedDirectories = [];
    try {
      fetchedDirectories = await _apiService.getDirectories();
      if (fetchedDirectories.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keine Verzeichnisse gefunden.'), backgroundColor: Colors.orange));
        return null;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler beim Laden: $e'), backgroundColor: Colors.orange));
      return null;
    }

    // 4. Ask user to select a directory
    return await _showDirectorySelectionDialog(fetchedDirectories);
  }

  /// Dialog to select between predefined users.
  Future<Map<String, String>?> _showUserSelectionDialog() async {
    String? selectedUserOption;
    return await showDialog<Map<String, String>?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Benutzer für Cloud-Upload auswählen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<String>(
                    title: const Text('cabarcas@gottsberg.de'),
                    value: 'cabarcas',
                    groupValue: selectedUserOption,
                    onChanged: (value) {
                      setDialogState(() {
                        selectedUserOption = value;
                      });
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('s.bluemel@konzschaefer.de'),
                    value: 'bluemel',
                    groupValue: selectedUserOption,
                    onChanged: (value) {
                      setDialogState(() {
                        selectedUserOption = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: selectedUserOption == null ? null : () {
                    if (selectedUserOption == 'cabarcas') {
                      Navigator.pop(context, {'username': "cabarcas@gottsberg.de", 'password': "KINCHI_HiLdE21042017!"});
                    } else {
                      Navigator.pop(context, {'username': "s.bluemel@konzschaefer.de", 'password': "Konz2006"});
                    }
                  },
                  child: const Text('Weiter'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Dialog to display fetched directories and allow selection by name.
  Future<int?> _showDirectorySelectionDialog(List<dynamic> directories) async {
    int? selectedDirectoryId;
    return await showDialog<int?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Verzeichnis auswählen'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: directories.length,
                  itemBuilder: (context, index) {
                    final dir = directories[index];
                    return RadioListTile<int>(
                      title: Text(dir['name'] ?? 'Unbenannt'),
                      subtitle: Text('ID: ${dir['id']}'),
                      value: dir['id'] as int,
                      groupValue: selectedDirectoryId,
                      onChanged: (value) => setDialogState(() => selectedDirectoryId = value),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: selectedDirectoryId == null ? null : () => Navigator.pop(context, selectedDirectoryId),
                  child: const Text('Auswählen'),
                ),
              ],
            );
          },
        );
      },
    );
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

  /// Selects all items currently visible in the search results
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
        final junction = junctionList.firstWhere(
          (j) => j['doorId'] == door.id, 
          orElse: () => <String, dynamic>{}
        );
        if (junction.isEmpty) continue;

        final doorErrors = allErrors
            .where((e) => e['inspectionDoorId'] == junction['id'])
            .map((e) => {
              'code': e['code']?.toString() ?? 'MISSING_CODE',
              'description': e['description']?.toString() ?? 'Fehlerbeschreibung fehlt',
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
  Future<void> _handleJobDownload(List<int> ids) async {
    setState(() => _isDownloading = true);

    try {
      await LocalDatabaseService.downloadJobPackage(
        inspectionIds: ids,
      );

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
        _refreshInspections();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Download: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// Handles the import of an inspector's result package into the Main DB
  Future<void> _handleImportResultPackage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;

        if (!mounted) return;

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
        await DatabaseService.importAndMergePackage(path);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Paket erfolgreich in Haupt-DB integriert.'),
              backgroundColor: Colors.green,
            ),
          );
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
                  await DatabaseService.clearDatabase();
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
        title: const Text('Manager / Projektleiter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Fehlerkatalog verwalten',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ManagerDashboard()),
            ),
          ),
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
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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

                        return InspectionSummaryCard(
                          inspectionId: id,
                          clientName: job['clientName'] ?? 'Unbekannter Kunde',
                          jobNumber: job['jobNumber'] ?? 'N/A',
                          date: job['date'] ?? '',
                          isSelected: isSelected,
                          onSelectionChanged: (_) => toggleSelection(),
                          onLongPress: toggleSelection,
                          onTap: _isDownloading
                              ? null
                              : () async {
                                  if (_selectedInspectionIds.isNotEmpty) {
                                    toggleSelection();
                                  } else {
                                    // Navigate to the door list sub-page for this inspection
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => InspectionDoorsPage(
                                          inspectionId: id,
                                          title: job['clientName'] ?? 'Türenliste',
                                          isManagerMode: true,
                                        ),
                                      ),
                                    );
                                    _refreshInspections();
                                  }
                                },
                        );
                      },
                    );
                  },
                ),
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
                  projectName: inspection['objectAddress'] ?? 'Unbekannt',
                  jobNumber: inspection['jobNumber'] ?? 'MultiJob',
                );
                
                final data = await _prepareExportData();
                final file = await service.exportToD83(data);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('GAEB 90 exportiert nach: ${file.path}')),
                  );
                  
                  final result = await _confirmCloudUpload();
                  if (result != null && mounted) {
                    await _uploadToCloud(file, service.jobNumber, result);
                  }
                }
              },
              icon: const Icon(Icons.description),
              label: const Text('GAEB 90'),
            ),
            const VerticalDivider(),
            TextButton.icon(
              onPressed: () async {
                final inspection = _currentVisibleResults.firstWhere((i) => _selectedInspectionIds.contains(i['inspectionId']));
                final service = GaebExportService(
                  customer: inspection['clientName'] ?? 'Unbekannt',
                  projectName: inspection['objectAddress'] ?? 'Unbekannt',
                  jobNumber: inspection['jobNumber'] ?? 'MultiJob',
                );

                final data = await _prepareExportData();
                final file = await service.exportToXml(data);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('GAEB XML exportiert nach: ${file.path}')),
                  );

                  final result = await _confirmCloudUpload();
                  if (result != null && mounted) {
                    await _uploadToCloud(file, service.jobNumber, result);
                  }
                }
              },
              icon: const Icon(Icons.code),
              label: const Text('GAEB XML'),
            ),
            const VerticalDivider(),
            TextButton.icon(
              onPressed: () => _handleJobDownload(_selectedInspectionIds.toList()),
              icon: const Icon(Icons.download_for_offline, color: Colors.green),
              label: const Text('Paket laden', style: TextStyle(color: Colors.green)),
            ),
          ],
        ),
      ),
    );
  }
}
