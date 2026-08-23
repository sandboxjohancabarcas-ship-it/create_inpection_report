import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/door.dart';
import '../services/database_service.dart';
import '../services/gaeb_export_service.dart';
import '../services/kinchi_api_service.dart';
import '../services/test_data_generator.dart';
import '../widgets/edit_inspection_dialog.dart';
import 'inspection_doors_page.dart';
import 'new_door_page.dart';

class MasterDoorsPage extends StatefulWidget {
  const MasterDoorsPage({super.key});

  @override
  State<MasterDoorsPage> createState() => _MasterDoorsPageState();
}

enum MasterViewMode { customerInspections, doorInventory }

class _MasterDoorsPageState extends State<MasterDoorsPage> {
  MasterViewMode _viewMode = MasterViewMode.customerInspections;
  List<Map<String, dynamic>> _masterDoors = [];
  List<Map<String, dynamic>> _inspections = [];
  List<String> _clients = ['Alle'];
  String _selectedClient = 'Alle';
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selectedDoorIds = {};
  final Set<int> _selectedInspectionIds = {};

  final KinchiApiService _apiService = KinchiApiService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final clientsList = await DatabaseService.getAllMasterClients();
      final doorsList = await DatabaseService.searchMasterDoorsDetailed(
        query: _searchController.text,
        clientFilter: _selectedClient,
      );
      final inspectionsList = await DatabaseService.searchInspections(
        _searchController.text,
        clientFilter: _selectedClient,
      );

      if (mounted) {
        setState(() {
          _clients = ['Alle', ...clientsList];
          if (!_clients.contains(_selectedClient)) {
            _selectedClient = 'Alle';
          }
          _masterDoors = doorsList;
          _inspections = inspectionsList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PACKAGE EXPORT (TECHNICIAN DB PACKAGES)
  // ─────────────────────────────────────────────────────────────

  Future<void> _handleExportInspection(int inspectionId) async {
    setState(() => _isProcessing = true);
    try {
      final exportPath = await DatabaseService.exportJobPackage([inspectionId]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Inspektionspaket erfolgreich exportiert:\n$exportPath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleExportSelectedInspections() async {
    if (_selectedInspectionIds.isEmpty) return;
    setState(() => _isProcessing = true);
    try {
      final exportPath = await DatabaseService.exportJobPackage(_selectedInspectionIds.toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedInspectionIds.length} Prüfpaket(e) exportiert:\n$exportPath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
        setState(() => _selectedInspectionIds.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleExportSelectedDoors() async {
    if (_selectedDoorIds.isEmpty) return;
    setState(() => _isProcessing = true);
    try {
      final exportPath = await DatabaseService.exportDoorsPackage(_selectedDoorIds.toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Prüfpaket für ${_selectedDoorIds.length} Tür(en) exportiert:\n$exportPath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
        setState(() => _selectedDoorIds.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // IMPORT TECHNICIAN RESULT PACKAGE INTO MASTER DB
  // ─────────────────────────────────────────────────────────────

  Future<void> _handleImportResultPackage() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (!mounted) return;

        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Techniker-Ergebnis importieren'),
            content: const Text(
              'Möchten Sie dieses Ergebnis-Paket in die Haupt-Datenbank einspielen?\n\n'
              'Bestehende Daten werden anhand von Alias & Auftragsnummer aktualisiert, '
              'erfasste Mängel werden in den Master integriert.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('In Haupt-DB integrieren'),
              ),
            ],
          ),
        );

        if (confirm != true) return;

        setState(() => _isProcessing = true);
        await DatabaseService.importAndMergePackage(path);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ergebnis-Paket erfolgreich in die Haupt-DB integriert.'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadData();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import-Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // GAEB EXPORT & CLOUD UPLOAD
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _prepareGaebExportData(List<int> inspectionIds) async {
    List<Map<String, dynamic>> flatExportList = [];
    for (int inspectionId in inspectionIds) {
      final doors = await DatabaseService.getDoorsByInspectionIds([inspectionId]);
      final junctionList = await DatabaseService.getInspectionDoorsByInspectionId(inspectionId);
      final List<int> junctionIds = junctionList.map((j) => j['id'] as int).toList();
      final allErrors = await DatabaseService.getErrorsForInspectionDoorIds(junctionIds);

      for (var door in doors) {
        final junction = junctionList.firstWhere(
          (j) => j['doorId'] == door.id,
          orElse: () => <String, dynamic>{},
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

  Future<void> _handleGaebExport({required bool isXml, List<int>? targetInspectionIds}) async {
    final ids = targetInspectionIds ?? _selectedInspectionIds.toList();
    if (ids.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final inspection = _inspections.firstWhere(
        (i) => ids.contains(i['inspectionId']),
        orElse: () => _inspections.first,
      );

      final service = GaebExportService(
        customer: inspection['clientName'] ?? 'Unbekannt',
        projectName: inspection['objectAddress'] ?? 'Unbekannt',
        jobNumber: inspection['jobNumber'] ?? 'MultiJob',
      );

      final data = await _prepareGaebExportData(ids);
      final File file = isXml ? await service.exportToXml(data) : await service.exportToD83(data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${isXml ? "GAEB XML" : "GAEB 90"} exportiert:\n${file.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );

        final cloudResult = await _confirmCloudUpload();
        if (cloudResult != null && mounted) {
          await _uploadToCloud(file, service.jobNumber, cloudResult);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GAEB-Export fehlgeschlagen: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _uploadToCloud(File file, String jobNumber, int directoryId) async {
    if (!mounted) return;
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datei wird in die Cloud hochgeladen...')),
      );
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
      String msg = 'Netzwerkfehler: $e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cloud-Upload fehlgeschlagen: $msg'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<int?> _confirmCloudUpload() async {
    final userCredentials = await _showUserSelectionDialog();
    if (userCredentials == null) return null;

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

    return await _showDirectorySelectionDialog(fetchedDirectories);
  }

  Future<Map<String, String>?> _showUserSelectionDialog() async {
    String? selectedUserOption;
    return await showDialog<Map<String, String>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cloud-Benutzer wählen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('cabarcas@gottsberg.de'),
                value: 'cabarcas',
                groupValue: selectedUserOption,
                onChanged: (val) => setDialogState(() => selectedUserOption = val),
              ),
              RadioListTile<String>(
                title: const Text('s.bluemel@konzschaefer.de'),
                value: 'bluemel',
                groupValue: selectedUserOption,
                onChanged: (val) => setDialogState(() => selectedUserOption = val),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Überspringen')),
            ElevatedButton(
              onPressed: selectedUserOption == null
                  ? null
                  : () {
                      if (selectedUserOption == 'cabarcas') {
                        Navigator.pop(context, {'username': "cabarcas@gottsberg.de", 'password': "KINCHI_HiLdE21042017!"});
                      } else {
                        Navigator.pop(context, {'username': "s.bluemel@konzschaefer.de", 'password': "Konz2006"});
                      }
                    },
              child: const Text('Weiter'),
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> _showDirectorySelectionDialog(List<dynamic> directories) async {
    int? selectedId;
    return await showDialog<int?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cloud-Verzeichnis wählen'),
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
                  groupValue: selectedId,
                  onChanged: (val) => setDialogState(() => selectedId = val),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: selectedId == null ? null : () => Navigator.pop(context, selectedId),
              child: const Text('Hochladen'),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SEED DATA & PURGE ALL
  // ─────────────────────────────────────────────────────────────

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
                setState(() => _isProcessing = true);
                try {
                  await DatabaseService.clearDatabase();
                  await TestDataGenerator.generate(
                    numCustomers: customers,
                    numObjectsPerCustomer: objects,
                    numDoorsPerObject: doors,
                  );
                  await _loadData();
                } finally {
                  if (mounted) setState(() => _isProcessing = false);
                }
              },
              child: const Text('Generieren'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePurgeAll() async {
    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Alle Auftragsdaten löschen?'),
            content: const Text(
              'Dies wird ALLE Aufträge, Prüfungsdetails und Fehlerzuordnungen löschen.\n\n'
              'Türen (Stammdaten) und der Fehlerkatalog bleiben erhalten.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Alles löschen', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
    if (confirm) {
      setState(() => _isProcessing = true);
      await DatabaseService.purgeAllInspections();
      await _loadData();
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SELECTION & DELETION
  // ─────────────────────────────────────────────────────────────

  void _toggleDoorSelection(int doorId) {
    setState(() {
      if (_selectedDoorIds.contains(doorId)) {
        _selectedDoorIds.remove(doorId);
      } else {
        _selectedDoorIds.add(doorId);
      }
    });
  }

  void _selectAllDoors() {
    setState(() {
      if (_selectedDoorIds.length == _masterDoors.length) {
        _selectedDoorIds.clear();
      } else {
        _selectedDoorIds.addAll(_masterDoors.map((d) => d['id'] as int));
      }
    });
  }

  void _toggleInspectionSelection(int inspectionId) {
    setState(() {
      if (_selectedInspectionIds.contains(inspectionId)) {
        _selectedInspectionIds.remove(inspectionId);
      } else {
        _selectedInspectionIds.add(inspectionId);
      }
    });
  }

  Future<void> _handleDeleteSelectedDoors() async {
    if (_selectedDoorIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Türen aus Haupt-DB löschen'),
        content: Text(
          'Möchten Sie ${_selectedDoorIds.length} ausgewählte Tür(en) und alle zugehörigen '
          'Prüfungsdaten unwiderruflich aus der Haupt-Datenbank löschen?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await DatabaseService.deleteDoors(_selectedDoorIds.toList());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Türen erfolgreich gelöscht.')),
          );
          _selectedDoorIds.clear();
          await _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler beim Löschen: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleDeleteSelectedInspections() async {
    if (_selectedInspectionIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aufträge löschen'),
        content: Text(
          'Möchten Sie ${_selectedInspectionIds.length} Auftrag/Aufträge und alle zugehörigen '
          'Prüfungsdaten unwiderruflich löschen?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await DatabaseService.deleteInspections(_selectedInspectionIds.toList());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aufträge erfolgreich gelöscht.')),
          );
          _selectedInspectionIds.clear();
          await _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler beim Löschen: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD METHOD
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool isDoorSelectionMode = _selectedDoorIds.isNotEmpty;
    final bool isInspectionSelectionMode = _selectedInspectionIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: isDoorSelectionMode
            ? Text('${_selectedDoorIds.length} Türen ausgewählt')
            : isInspectionSelectionMode
                ? Text('${_selectedInspectionIds.length} Aufträge ausgewählt')
                : _isSearching
                    ? TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Suchen (Kunde, Türnummer, Alias, Raum)...',
                          border: InputBorder.none,
                        ),
                        onChanged: (val) => _loadData(),
                      )
                    : const Text('Master-Portal (Manager)'),
        leading: (isDoorSelectionMode || isInspectionSelectionMode)
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectedDoorIds.clear();
                  _selectedInspectionIds.clear();
                }),
              )
            : null,
        actions: [
          if (isDoorSelectionMode) ...[
            IconButton(
              icon: Icon(_selectedDoorIds.length == _masterDoors.length
                  ? Icons.check_box
                  : Icons.check_box_outline_blank),
              tooltip: 'Alle auswählen',
              onPressed: _selectAllDoors,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Ausgewählte löschen',
              onPressed: _handleDeleteSelectedDoors,
            ),
          ] else if (isInspectionSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Prüfpakete exportieren',
              onPressed: _handleExportSelectedInspections,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Ausgewählte löschen',
              onPressed: _handleDeleteSelectedInspections,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.drive_folder_upload),
              tooltip: 'Techniker-Ergebnis importieren',
              onPressed: _isProcessing ? null : _handleImportResultPackage,
            ),
            IconButton(
              icon: const Icon(Icons.science_outlined),
              tooltip: 'Testdaten generieren',
              onPressed: _isProcessing ? null : _showSeedDataDialog,
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Alle Aufträge löschen',
              onPressed: _isProcessing ? null : _handlePurgeAll,
            ),
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchController.clear();
                    _loadData();
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Aktualisieren',
              onPressed: _loadData,
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Segmented Switcher: Prüfungen pro Kunde vs. Türen-Inventar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: SegmentedButton<MasterViewMode>(
                  segments: const [
                    ButtonSegment<MasterViewMode>(
                      value: MasterViewMode.customerInspections,
                      icon: Icon(Icons.business_center_outlined),
                      label: Text('Aufträge & Prüfungen'),
                    ),
                    ButtonSegment<MasterViewMode>(
                      value: MasterViewMode.doorInventory,
                      icon: Icon(Icons.door_front_door_outlined),
                      label: Text('Türen-Inventar'),
                    ),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _viewMode = newSelection.first;
                      _selectedDoorIds.clear();
                      _selectedInspectionIds.clear();
                    });
                  },
                ),
              ),

              // Customer Filter Chips
              if (_clients.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.business, size: 18, color: Colors.grey),
                      const SizedBox(width: 8),
                      const Text('Kunde:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _clients.map((client) {
                              final isSelected = client == _selectedClient;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6.0),
                                child: ChoiceChip(
                                  label: Text(client, style: const TextStyle(fontSize: 12)),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() => _selectedClient = client);
                                      _loadData();
                                    }
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const Divider(height: 1),

              // Main View Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _viewMode == MasterViewMode.customerInspections
                        ? _buildCustomerInspectionsView()
                        : _buildDoorInventoryView(),
              ),
            ],
          ),

          // Processing Overlay
          if (_isProcessing)
            Container(
              color: Colors.black38,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Vorgang wird ausgeführt...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: isDoorSelectionMode
          ? BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    onPressed: _handleDeleteSelectedDoors,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Auswahl löschen',
                  ),
                  const VerticalDivider(),
                  TextButton.icon(
                    onPressed: _isProcessing ? null : _handleExportSelectedDoors,
                    icon: const Icon(Icons.upload_file),
                    label: Text('Paket exportieren (${_selectedDoorIds.length})'),
                  ),
                ],
              ),
            )
          : isInspectionSelectionMode
              ? BottomAppBar(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: _handleDeleteSelectedInspections,
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'Auswahl löschen',
                      ),
                      const VerticalDivider(),
                      TextButton.icon(
                        onPressed: _isProcessing ? null : () => _handleGaebExport(isXml: false),
                        icon: const Icon(Icons.description),
                        label: const Text('GAEB 90'),
                      ),
                      const VerticalDivider(),
                      TextButton.icon(
                        onPressed: _isProcessing ? null : () => _handleGaebExport(isXml: true),
                        icon: const Icon(Icons.code),
                        label: const Text('GAEB XML'),
                      ),
                      const VerticalDivider(),
                      TextButton.icon(
                        onPressed: _isProcessing ? null : _handleExportSelectedInspections,
                        icon: const Icon(Icons.upload_file, color: Colors.green),
                        label: Text('Paket (${_selectedInspectionIds.length})', style: const TextStyle(color: Colors.green)),
                      ),
                    ],
                  ),
                )
              : null,
      floatingActionButton: (_viewMode == MasterViewMode.doorInventory && !isDoorSelectionMode)
          ? FloatingActionButton(
              heroTag: 'fab_master_doors',
              tooltip: 'Neue Tür im Master anlegen',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DoorInspectionForm(isManagerMode: true),
                  ),
                );
                _loadData();
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // VIEW 1: AUFTRÄGE & PRÜFUNGEN PRO KUNDE
  // ─────────────────────────────────────────────────────────────

  Widget _buildCustomerInspectionsView() {
    if (_inspections.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty || _selectedClient != 'Alle'
                  ? 'Keine passenden Aufträge gefunden'
                  : 'Keine Aufträge in der Hauptdatenbank vorhanden',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
          ],
        ),
      );
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final insp in _inspections) {
      final client = (insp['clientName']?.toString().trim().isNotEmpty ?? false)
          ? insp['clientName'].toString().trim()
          : 'Ohne Kundenzuordnung';
      grouped.putIfAbsent(client, () => []).add(insp);
    }

    final clientKeys = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: clientKeys.length,
      itemBuilder: (context, index) {
        final clientName = clientKeys[index];
        final clientInspections = grouped[clientName]!;
        final totalDoors = clientInspections.fold<int>(
          0,
          (sum, item) => sum + ((item['doorCount'] as num?)?.toInt() ?? 0),
        );

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.business, color: Theme.of(context).colorScheme.primary),
            ),
            title: Text(
              clientName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              '${clientInspections.length} Auftrag/Aufträge • $totalDoors Tür(en) gesamt',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            children: clientInspections.map((job) {
              final id = job['inspectionId'] as int;
              final isSelected = _selectedInspectionIds.contains(id);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  leading: _selectedInspectionIds.isNotEmpty
                      ? Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleInspectionSelection(id),
                        )
                      : CircleAvatar(
                          backgroundColor: Colors.blue.shade50,
                          child: Icon(Icons.assignment, color: Colors.blue.shade700, size: 20),
                        ),
                  title: Row(
                    children: [
                      Text(
                        'Auftrag: ${job['jobNumber'] ?? "N/A"}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(width: 8),
                      if (job['date'] != null && job['date'].toString().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            job['date'].toString(),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (job['objectAddress'] != null && job['objectAddress'].toString().isNotEmpty)
                          Text(
                            'Objekt: ${job['objectAddress']}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                        Text(
                          '${(job['doorCount'] as num?)?.toInt() ?? 0} Türen erfasst',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.blue.shade800),
                        ),
                      ],
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.upload_file, color: Colors.indigo),
                        tooltip: 'Paket für Techniker exportieren',
                        onPressed: _isProcessing ? null : () => _handleExportInspection(id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.description, color: Colors.teal),
                        tooltip: 'GAEB 90 exportieren',
                        onPressed: _isProcessing ? null : () => _handleGaebExport(isXml: false, targetInspectionIds: [id]),
                      ),
                      IconButton(
                        icon: const Icon(Icons.code, color: Colors.deepPurple),
                        tooltip: 'GAEB XML exportieren',
                        onPressed: _isProcessing ? null : () => _handleGaebExport(isXml: true, targetInspectionIds: [id]),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Colors.grey),
                        tooltip: 'Auftrag bearbeiten',
                        onPressed: () async {
                          final updated = await EditInspectionDialog.show(
                            context,
                            inspectionId: id,
                            initialData: job,
                            isManagerMode: true,
                          );
                          if (updated == true && mounted) {
                            _loadData();
                          }
                        },
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onLongPress: () => _toggleInspectionSelection(id),
                  onTap: () async {
                    if (_selectedInspectionIds.isNotEmpty) {
                      _toggleInspectionSelection(id);
                    } else {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InspectionDoorsPage(
                            inspectionId: id,
                            title: '${job['clientName'] ?? clientName} - ${job['jobNumber'] ?? ""}',
                            isManagerMode: true,
                          ),
                        ),
                      );
                      _loadData();
                    }
                  },
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // VIEW 2: TÜREN-INVENTAR (ALL DOORS LIST)
  // ─────────────────────────────────────────────────────────────

  Widget _buildDoorInventoryView() {
    final isSelectionMode = _selectedDoorIds.isNotEmpty;

    if (_masterDoors.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.door_sliding_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty || _selectedClient != 'Alle'
                  ? 'Keine passenden Türen gefunden'
                  : 'Keine Türen in der Hauptdatenbank vorhanden',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _masterDoors.length,
      itemBuilder: (context, index) {
        final doorMap = _masterDoors[index];
        final id = doorMap['id'] as int;
        final door = Door.fromMap(doorMap);
        final isSelected = _selectedDoorIds.contains(id);
        final int errorCount = (doorMap['totalErrorCount'] as num?)?.toInt() ?? 0;
        final String clientName = doorMap['clientName'] ?? 'Ohne Zuordnung';
        final String jobNumber = doorMap['jobNumber'] ?? '';
        final int? inspectionId = doorMap['inspectionId'] as int?;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          elevation: isSelected ? 4 : 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: isSelectionMode
                ? Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleDoorSelection(id),
                  )
                : CircleAvatar(
                    backgroundColor: errorCount > 0 ? Colors.red.shade100 : Colors.green.shade100,
                    child: Icon(
                      Icons.door_front_door,
                      color: errorCount > 0 ? Colors.red.shade800 : Colors.green.shade800,
                    ),
                  ),
            title: Row(
              children: [
                Text(
                  door.doorNumber.isNotEmpty ? 'Tür ${door.doorNumber}' : 'Tür ohne Nummer',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                if (door.doorAlias != null && door.doorAlias!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      border: Border.all(color: Colors.blue.shade300),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code, size: 12, color: Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text(
                          door.doorAlias!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (errorCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$errorCount ${errorCount == 1 ? "Mangel" : "Mängel"}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Mängelfrei',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kunde: $clientName ${jobNumber.isNotEmpty ? "($jobNumber)" : ""}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${door.floor.isNotEmpty ? "${door.floor} | " : ""}${door.roomDesignation.isNotEmpty ? door.roomDesignation : "Kein Raum"} ${door.roomNumber.isNotEmpty ? "(${door.roomNumber})" : ""}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Typ: ${door.doorType} | Material: ${door.material} | Schließer: ${door.closerType}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            trailing: isSelectionMode ? null : const Icon(Icons.edit_note),
            onTap: () async {
              if (isSelectionMode) {
                _toggleDoorSelection(id);
              } else {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DoorInspectionForm(
                      door: door,
                      isManagerMode: true,
                      inspectionId: inspectionId,
                    ),
                  ),
                );
                _loadData();
              }
            },
            onLongPress: () => _toggleDoorSelection(id),
          ),
        );
      },
    );
  }
}
