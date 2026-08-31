import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/door.dart';
import '../services/database_service.dart';
import '../services/gaeb_export_service.dart';
import '../services/kinchi_api_service.dart';
import '../widgets/edit_inspection_dialog.dart';
import '../widgets/import_report_dialog.dart';
import '../widgets/batch_migration_dialog.dart';
import '../widgets/migration_log_dialog.dart';
import '../services/customer_normalizer.dart';
import 'inspection_doors_page.dart';
import 'new_door_page.dart';
import 'door_history_page.dart';

class MasterDoorsPage extends StatefulWidget {
  const MasterDoorsPage({super.key});

  @override
  State<MasterDoorsPage> createState() => _MasterDoorsPageState();
}

enum MasterViewMode { customerInspections, doorInventory }
enum ErrorFilterOption { all, withErrors, errorFree }
enum ErrorSortOption { defaultSort, mostErrors, leastErrors }

class _MasterDoorsPageState extends State<MasterDoorsPage> {
  MasterViewMode _viewMode = MasterViewMode.customerInspections;
  ErrorFilterOption _errorFilter = ErrorFilterOption.all;
  ErrorSortOption _errorSort = ErrorSortOption.defaultSort;
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
  // PURGE ALL
  // ─────────────────────────────────────────────────────────────

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

  void _toggleCustomerInspections(List<int> inspectionIds) {
    setState(() {
      final allSelected = inspectionIds.every((id) => _selectedInspectionIds.contains(id));
      if (allSelected) {
        _selectedInspectionIds.removeAll(inspectionIds);
      } else {
        _selectedInspectionIds.addAll(inspectionIds);
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
              tooltip: 'Paket für Techniker exportieren',
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
              tooltip: 'Daten-Migration & Import (Dateien/Ordner)',
              onPressed: _isProcessing ? null : () => BatchMigrationDialog.show(context, onMigrationCompleted: _loadData),
            ),
            IconButton(
              icon: const Icon(Icons.published_with_changes, color: Colors.deepPurpleAccent),
              tooltip: 'Migrations-Audit & DB-Reparatur',
              onPressed: () => MigrationLogDialog.show(context),
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
                      Tooltip(
                        message: 'Paket für Techniker exportieren',
                        child: TextButton.icon(
                          onPressed: _isProcessing ? null : _handleExportSelectedInspections,
                          icon: const Icon(Icons.upload_file, color: Colors.green),
                          label: Text('Paket (${_selectedInspectionIds.length})', style: const TextStyle(color: Colors.green)),
                        ),
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
      final rawClient = insp['clientName']?.toString().trim() ?? '';
      final canonicalDisplay = rawClient.isNotEmpty
          ? CustomerNormalizer.getCanonicalName(rawClient)
          : 'Ohne Kundenzuordnung';
      grouped.putIfAbsent(canonicalDisplay, () => []).add(insp);
    }

    final clientKeys = grouped.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

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

        final customerInspectionIds = clientInspections
            .map((job) => job['inspectionId'] as int)
            .toList();

        final bool isAllCustomerSelected = customerInspectionIds.isNotEmpty &&
            customerInspectionIds.every((id) => _selectedInspectionIds.contains(id));
        final bool isAnyCustomerSelected = customerInspectionIds
            .any((id) => _selectedInspectionIds.contains(id));

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: Checkbox(
              value: isAllCustomerSelected
                  ? true
                  : (isAnyCustomerSelected ? null : false),
              tristate: true,
              onChanged: (_) => _toggleCustomerInspections(customerInspectionIds),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    clientName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setState(() => _isProcessing = true);
                          try {
                            final exportPath = await DatabaseService.exportJobPackage(customerInspectionIds);
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Kundenpaket ($clientName) mit ${customerInspectionIds.length} Auftrag/Aufträgen exportiert:\n$exportPath'),
                                  backgroundColor: Colors.green,
                                  duration: const Duration(seconds: 5),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('Export fehlgeschlagen: $e'), backgroundColor: Colors.red),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _isProcessing = false);
                          }
                        },
                  icon: const Icon(Icons.upload_file, color: Colors.green, size: 18),
                  label: Text(
                    'Kundenpaket (${customerInspectionIds.length})',
                    style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
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
                child: Material(
                  color: isSelected ? Colors.blue.shade50.withValues(alpha: 0.3) : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: isSelected ? Colors.blue.shade400 : Colors.grey.shade200,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                  leading: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleInspectionSelection(id),
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

    // Apply Error Status Filter
    List<Map<String, dynamic>> displayDoors = List.from(_masterDoors);
    if (_errorFilter == ErrorFilterOption.withErrors) {
      displayDoors = displayDoors.where((d) {
        final count = (d['openErrorCount'] as num?)?.toInt() ?? (d['totalErrorCount'] as num?)?.toInt() ?? 0;
        return count > 0;
      }).toList();
    } else if (_errorFilter == ErrorFilterOption.errorFree) {
      displayDoors = displayDoors.where((d) {
        final count = (d['openErrorCount'] as num?)?.toInt() ?? (d['totalErrorCount'] as num?)?.toInt() ?? 0;
        return count == 0;
      }).toList();
    }

    // Apply Error Status Sorting
    if (_errorSort == ErrorSortOption.mostErrors) {
      displayDoors.sort((a, b) {
        final countA = (a['openErrorCount'] as num?)?.toInt() ?? (a['totalErrorCount'] as num?)?.toInt() ?? 0;
        final countB = (b['openErrorCount'] as num?)?.toInt() ?? (b['totalErrorCount'] as num?)?.toInt() ?? 0;
        return countB.compareTo(countA); // Descending: Most open errors first
      });
    } else if (_errorSort == ErrorSortOption.leastErrors) {
      displayDoors.sort((a, b) {
        final countA = (a['openErrorCount'] as num?)?.toInt() ?? (a['totalErrorCount'] as num?)?.toInt() ?? 0;
        final countB = (b['openErrorCount'] as num?)?.toInt() ?? (b['totalErrorCount'] as num?)?.toInt() ?? 0;
        return countA.compareTo(countB); // Ascending: Least open errors / error-free first
      });
    } else {
      // Default: Hierarchical sort by Floor -> Room -> Door Number
      displayDoors.sort((aMap, bMap) {
        final doorA = Door.fromMap(aMap);
        final doorB = Door.fromMap(bMap);
        return CustomerNormalizer.compareDoors(doorA, doorB);
      });
    }

    return Column(
      children: [
        // Error Filter & Sort Control Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Icon(Icons.filter_list, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                const Text('Mängelfilter:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Alle Türen', style: TextStyle(fontSize: 11)),
                  selected: _errorFilter == ErrorFilterOption.all,
                  onSelected: (selected) {
                    if (selected) setState(() => _errorFilter = ErrorFilterOption.all);
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red),
                      const SizedBox(width: 4),
                      const Text('Mit Mängeln', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                  selected: _errorFilter == ErrorFilterOption.withErrors,
                  onSelected: (selected) {
                    if (selected) setState(() => _errorFilter = ErrorFilterOption.withErrors);
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      const Text('Mängelfrei', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                  selected: _errorFilter == ErrorFilterOption.errorFree,
                  onSelected: (selected) {
                    if (selected) setState(() => _errorFilter = ErrorFilterOption.errorFree);
                  },
                ),
                const SizedBox(width: 16),
                const Icon(Icons.sort, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                const Text('Sortierung:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(width: 6),
                PopupMenuButton<ErrorSortOption>(
                  initialValue: _errorSort,
                  onSelected: (opt) => setState(() => _errorSort = opt),
                  child: Chip(
                    avatar: Icon(
                      _errorSort == ErrorSortOption.mostErrors
                          ? Icons.arrow_downward
                          : _errorSort == ErrorSortOption.leastErrors
                              ? Icons.arrow_upward
                              : Icons.swap_vert,
                      size: 14,
                      color: _errorSort == ErrorSortOption.mostErrors
                          ? Colors.red
                          : _errorSort == ErrorSortOption.leastErrors
                              ? Colors.green
                              : null,
                    ),
                    label: Text(
                      _errorSort == ErrorSortOption.mostErrors
                          ? 'Meiste Mängel zuerst'
                          : _errorSort == ErrorSortOption.leastErrors
                              ? 'Wenigste Mängel zuerst'
                              : 'Standard (Reihenfolge)',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: ErrorSortOption.defaultSort,
                      child: Text('Standard (Reihenfolge)'),
                    ),
                    PopupMenuItem(
                      value: ErrorSortOption.mostErrors,
                      child: Row(
                        children: const [
                          Icon(Icons.arrow_downward, color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Expanded(child: Text('Meiste Mängel zuerst', overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: ErrorSortOption.leastErrors,
                      child: Row(
                        children: const [
                          Icon(Icons.arrow_upward, color: Colors.green, size: 18),
                          SizedBox(width: 8),
                          Expanded(child: Text('Wenigste Mängel zuerst', overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),

        // List Content
        Expanded(
          child: displayDoors.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.door_sliding_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        _errorFilter == ErrorFilterOption.withErrors
                            ? 'Keine Türen mit Mängeln gefunden'
                            : _errorFilter == ErrorFilterOption.errorFree
                                ? 'Keine mängelfreien Türen gefunden'
                                : _searchController.text.isNotEmpty || _selectedClient != 'Alle'
                                    ? 'Keine passenden Türen gefunden'
                                    : 'Keine Türen in der Hauptdatenbank vorhanden',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: displayDoors.length,
                  itemBuilder: (context, index) {
                    final doorMap = displayDoors[index];
                    final id = doorMap['id'] as int;
                    final door = Door.fromMap(doorMap);
                    final isSelected = _selectedDoorIds.contains(id);
                    final int errorCount = (doorMap['openErrorCount'] as num?)?.toInt() ?? (doorMap['totalErrorCount'] as num?)?.toInt() ?? 0;
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
                        trailing: isSelectionMode
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.history_edu, color: Colors.blueGrey),
                                    tooltip: 'Tür-Akte & Historie',
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => DoorHistoryPage(doorId: id),
                                        ),
                                      );
                                    },
                                  ),
                                  const Icon(Icons.edit_note, color: Colors.grey),
                                ],
                              ),
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
                ),
        ),
      ],
    );
  }
}
