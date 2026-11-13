import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';
import '../services/local_database_service.dart';
import '../widgets/inspection_summary_card.dart';
import '../widgets/import_report_dialog.dart';
import '../services/app_version_service.dart';
import '../widgets/app_version_dialog.dart';
import '../utils/file_export_helper.dart';
import '../utils/error_log_export_helper.dart';
import '../widgets/create_project_dialog.dart';
import '../widgets/craftnote_job_picker_modal.dart';
import '../widgets/craftnote_test_mode_switch.dart';
import '../widgets/app_log_dialog.dart';
import '../services/craftnote_sync_service.dart';
import 'inspection_doors_page.dart';
import 'inspection_windows_page.dart';
import 'package:intl/intl.dart';

class DoorListPage extends StatefulWidget {
  const DoorListPage({super.key});

  @override
  State<DoorListPage> createState() => _DoorListPageState();
}

class _DoorListPageState extends State<DoorListPage> {
  List<Map<String, dynamic>> inspections = [];
  List<String> _clients = ['Alle'];
  String _selectedClient = 'Alle';
  bool _isSyncing = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selectedIds = {};
  int _pendingUploadCount = 0;
  final CraftnoteSyncService _craftnoteSyncService = CraftnoteSyncService();
  Timer? _autoSyncTimer;

  @override
  void initState() {
    super.initState();
    loadInspections();
    // Periodically verify if pending uploads can be automatically synchronized
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_pendingUploadCount > 0 && !_isSyncing && mounted) {
        _autoProcessOfflineQueue();
      }
    });
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadInspections() async {
    final results = await LocalDatabaseService.getAllInspections(
      query: _searchController.text,
      clientFilter: _selectedClient,
    );
    final clientList = await LocalDatabaseService.getAllLocalClients();
    final pendingList = await LocalDatabaseService.getPendingCraftnoteUploads();

    if (mounted) {
      setState(() {
        inspections = results;
        _pendingUploadCount = pendingList.length;
        _clients = ['Alle', ...clientList];
        if (!_clients.contains(_selectedClient)) {
          _selectedClient = 'Alle';
        }
      });

      // Automatically trigger offline queue processing when online
      if (pendingList.isNotEmpty && !_isSyncing) {
        _autoProcessOfflineQueue();
      }
    }
  }

  /// Automatically processes pending offline uploads in the background when an active internet connection is present
  Future<void> _autoProcessOfflineQueue() async {
    if (_isSyncing) return;
    final isOnline = await _craftnoteSyncService.hasInternetConnection();
    if (!isOnline) return;

    try {
      final report = await _craftnoteSyncService.processPendingUploadQueue();
      if (report.succeeded > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${report.succeeded} Auftrag/Aufträge aus der Offline-Warteschlange automatisch mit Craftnote synchronisiert.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        final results = await LocalDatabaseService.getAllInspections(
          query: _searchController.text,
          clientFilter: _selectedClient,
        );
        final pendingList = await LocalDatabaseService.getPendingCraftnoteUploads();
        if (mounted) {
          setState(() {
            inspections = results;
            _pendingUploadCount = pendingList.length;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _handleCraftnoteImport() async {
    final result = await CraftnoteJobPickerModal.show(context);
    if (result != null && result.success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.green,
          ),
        );
        await loadInspections();
      }
    }
  }

  Future<void> _handleProcessOfflineQueue() async {
    setState(() => _isSyncing = true);
    try {
      final report = await _craftnoteSyncService.processPendingUploadQueue();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              report.succeeded > 0
                  ? '${report.succeeded} Auftrag/Aufträge erfolgreich mit Craftnote synchronisiert.'
                  : (report.hasErrors
                      ? 'Synchronisierung fehlgeschlagen: ${report.errorMessages.join(", ")}'
                      : 'Keine ausstehenden Aufträge in der Warteschlange.'),
            ),
            backgroundColor:
                report.succeeded > 0 ? Colors.green : Colors.orange,
          ),
        );
        await loadInspections();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler bei der Synchronisierung: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  /// Confirms deletion with the user, consistent with JobSelectionPage logic.
  Future<bool> _confirmDeletion(int count) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Löschen bestätigen'),
            content: Text(
                '$count Tür(en) und zugehörige Prüfungsdaten unwiderruflich löschen?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Abbrechen')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child:
                    const Text('Löschen', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
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
          SnackBar(
              content: Text('Fehler beim Löschen: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  /// Opens a file picker to select a .db file and imports it into the Working DB.
  /// Supports merging packages or replacing the working DB.
  Future<void> _handleImportPaket() async {
    try {
      FilePickerResult? result =
          await FilePicker.platform.pickFiles(type: FileType.any);

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;

        if (!mounted) return;

        // Check compatibility before showing import options
        final compat = await ErrorLogExportHelper.checkPackageCompatibility(
            path,
            targetVersion: 17);
        if (compat.hasVersionMismatch) {
          final proceed = await ErrorLogExportHelper.showVersionWarningDialog(
            context,
            compatibility: compat,
            fileName: p.basename(path),
          );
          if (!proceed) return;
        }

        if (!mounted) return;

        final bool hasInspections =
            await LocalDatabaseService.hasInspectionsToSave();

        final String? action = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Inspektionspaket importieren'),
            content: Text(
                'Wie möchten Sie das Paket importieren?\n\n• Hinzufügen (Merge): Ergänzt Ihre bestehenden Aufträge auf diesem Gerät.\n\n• Ersetzen: Ersetzt die vorherigen Daten durch dieses Paket.\n\n${hasInspections ? 'Hinweis: Da bestehende Prüfungsdaten vorhanden sind, werden Sie vor dem Import aufgefordert, den Speicherort für eine Sicherheitskopie auszuwählen.' : 'Hinweis: Es sind keine vorherigen Prüfungsdaten vorhanden, die gesichert werden müssen.'}'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Abbrechen')),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, 'replace'),
                child: const Text('Ersetzen',
                    style: TextStyle(color: Colors.orange)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, 'merge'),
                child: const Text('Hinzufügen (Merge)'),
              ),
            ],
          ),
        );

        if (action == null) return;

        String? savedBackupPath;
        if (hasInspections) {
          final workingDbPath = await LocalDatabaseService.getWorkingDbPath();
          final workingDbFile = File(workingDbPath);
          final timeStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
          final tag = action == 'replace' ? 'pre_replace' : 'pre_merge';
          final defaultFileName =
              'Sicherheitskopie_WartungsTool_${tag}_$timeStr.db';

          savedBackupPath = await FileExportHelper.saveFileSafely(
            defaultFileName: defaultFileName,
            dialogTitle: 'Sicherheitskopie der aktuellen Daten speichern unter',
            sourceFile: workingDbFile,
            allowedExtensions: ['db'],
          );

          if (savedBackupPath == null) {
            if (!mounted) return;
            final bool? proceed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Keine Sicherheitskopie gespeichert'),
                content: const Text(
                    'Sie haben keinen Speicherort für die Sicherheitskopie ausgewählt.\n\n'
                    'Möchten Sie den Import wirklich ohne Sicherheitskopie fortsetzen?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Import abbrechen'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Ohne Backup importieren'),
                  ),
                ],
              ),
            );
            if (proceed != true) {
              return;
            }
          }
        }

        setState(() => _isSyncing = true);
        ImportReport? report;
        if (action == 'merge') {
          report = await LocalDatabaseService.importAndMergePackage(path);
        } else {
          await LocalDatabaseService.importWorkingDb(path);
        }

        if (mounted) {
          // Reset search state to show all newly imported doors
          setState(() {
            _searchController.clear();
            _isSearching = false;
          });
          await loadInspections();
          if (report != null && mounted) {
            await ImportReportDialog.show(context, report);
          } else if (mounted) {
            final String msg = savedBackupPath != null
                ? 'Paket erfolgreich importiert (Sicherheitskopie gespeichert: ${p.basename(savedBackupPath)}).'
                : 'Paket erfolgreich importiert.';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e, stackTrace) {
      if (mounted) {
        await ErrorLogExportHelper.handleExceptionWithDialog(
          context,
          error: e,
          stackTrace: stackTrace,
          operation: 'Inspektionspaket importieren',
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
    String? tempExportPath;
    try {
      // Resolve all Doors and statuses belonging to the selected inspections
      List<Door> doorsToExport = [];
      Map<int, String> statuses = {};
      for (int inspId in _selectedIds) {
        final doors = await LocalDatabaseService.getDoorsByInspectionId(inspId);
        doorsToExport.addAll(doors);
        final inspStatuses =
            await LocalDatabaseService.getDoorInspectionStatuses(inspId);
        statuses.addAll(inspStatuses);
      }

      if (doorsToExport.isEmpty)
        throw Exception('Keine Türen in den gewählten Aufträgen gefunden.');

      final canProceed = await FileExportHelper.confirmUnprocessedDoors(
        context: context,
        doors: doorsToExport,
        statuses: statuses,
        actionName: 'Paket-Export',
      );
      if (!canProceed) return;

      List<int> doorIdsToExport = doorsToExport.map((d) => d.id!).toList();

      Map<String, dynamic>? inspData;
      if (_selectedIds.isNotEmpty) {
        inspData =
            await LocalDatabaseService.getInspectionById(_selectedIds.first);
      }
      final defaultFileName = FileExportHelper.buildPackageFileName(
        jobNumber: inspData?['jobNumber']?.toString() ??
            inspData?['auftragsnummer']?.toString(),
        projectNumber: inspData?['projectNumber']?.toString(),
        objectAddress: inspData?['objectAddress']?.toString() ??
            inspData?['clientName']?.toString(),
        packageType: 'inspektion_ergebnis',
      );
      tempExportPath = await FileExportHelper.getTempFilePath(defaultFileName);

      await LocalDatabaseService.exportSelectiveJobPackage(
        doorIdsToExport,
        tempExportPath,
      );

      final tempFile = File(tempExportPath);
      final savedPath = await FileExportHelper.saveFileSafely(
        defaultFileName: defaultFileName,
        dialogTitle: 'Inspektions-Paket speichern unter',
        sourceFile: tempFile,
        allowedExtensions: ['db'],
      );

      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ergebnis-Paket gespeichert: $savedPath'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _selectedIds.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Export-Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (tempExportPath != null) {
        try {
          final tf = File(tempExportPath);
          if (await tf.exists()) await tf.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  /// Exports the selected inspection(s) directly to Craftnote without browsing projects.
  /// Automatically resolves project by Auftragsnummer and routes to Wartungslisten and Fotomaterial.
  Future<void> _handleCraftnoteExport() async {
    if (_selectedIds.isEmpty) return;

    setState(() => _isSyncing = true);
    final results = <CraftnoteSyncResult>[];
    try {
      for (final id in _selectedIds) {
        final res = await _craftnoteSyncService.completeAndUploadFromLocalDb(
          inspectionId: id,
        );
        results.add(res);
      }

      if (mounted) {
        setState(() => _selectedIds.clear());
        await loadInspections();
        if (!mounted) return;

        if (results.length == 1) {
          final res = results.first;
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Row(
                children: [
                  Icon(
                    res.isQueuedOffline
                        ? Icons.cloud_queue
                        : (res.success ? Icons.cloud_done : Icons.error_outline),
                    color: res.isQueuedOffline
                        ? Colors.orange
                        : (res.success ? Colors.green : Colors.red),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    res.isQueuedOffline
                        ? 'Offline eingereiht'
                        : (res.success ? 'Export erfolgreich' : 'Export fehlgeschlagen'),
                  ),
                ],
              ),
              content: SelectableText(res.message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          final succeeded = results.where((r) => r.success && !r.isQueuedOffline).length;
          final queued = results.where((r) => r.isQueuedOffline).length;
          final failed = results.where((r) => !r.success).length;
          final summary = '$succeeded erfolgreich übertragen, $queued offline eingereiht, $failed fehlgeschlagen.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(summary),
              backgroundColor: failed == 0 ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Export nach Craftnote: $e'),
            backgroundColor: Colors.red,
          ),
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
                    decoration: InputDecoration(
                      hintText: 'Suchen (Tür, Code, Fehler)...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6)),
                    ),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface),
                    onChanged: (value) => loadInspections(),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Prüfpakete (Techniker)",
                          style: TextStyle(fontSize: 18)),
                      Text(
                        AppVersionService.getCompactVersionInfo(
                            isManager: false),
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
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
                if (_pendingUploadCount > 0)
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        icon:
                            const Icon(Icons.cloud_queue, color: Colors.orange),
                        tooltip:
                            '$_pendingUploadCount Auftrag/Aufträge in Offline-Warteschlange (Antippen zum Synchronisieren)',
                        onPressed:
                            _isSyncing ? null : _handleProcessOfflineQueue,
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints:
                              const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            '$_pendingUploadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                CraftnoteTestModeSwitch(
                  compact: true,
                  onChanged: (_) => setState(() {}),
                ),
                IconButton(
                  icon: const Icon(Icons.cloud_download, color: Colors.blue),
                  tooltip: 'Aus Craftnote laden',
                  onPressed: _isSyncing ? null : _handleCraftnoteImport,
                ),
                IconButton(
                  icon: const Icon(Icons.file_open),
                  tooltip: 'Paket importieren',
                  onPressed: _isSyncing ? null : _handleImportPaket,
                ),
                IconButton(
                  icon: const Icon(Icons.receipt_long_outlined),
                  tooltip: 'Anwendungsprotokoll (Log) anzeigen & herunterladen',
                  onPressed: () => AppLogDialog.show(context),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'App-Info & Version',
                  onPressed: () =>
                      AppVersionDialog.show(context, isManager: false),
                ),
              ],
      ),
      body: Column(
        children: [
          if (_clients.length > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.3),
              child: Row(
                children: [
                  const Icon(Icons.business, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  const Text('Kunde:',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
                              label: Text(client,
                                  style: const TextStyle(fontSize: 12)),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _selectedClient = client);
                                  loadInspections();
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
          Expanded(
            child: Stack(
              children: [
                inspections.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _searchController.text.isNotEmpty ||
                                      _selectedClient != 'Alle'
                                  ? 'Keine passenden Aufträge gefunden'
                                  : 'Keine Aufträge vorhanden',
                              style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500),
                            ),
                            if (_searchController.text.isEmpty &&
                                _selectedClient == 'Alle') ...[
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text('Neuen Auftrag anlegen'),
                                onPressed: () async {
                                  final created =
                                      await CreateProjectDialog.show(
                                    context,
                                    isInspectorMode: true,
                                  );
                                  if (created == true) {
                                    loadInspections();
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        key: const PageStorageKey('inspector_job_list'),
                        itemCount: inspections.length,
                        itemBuilder: (context, index) {
                          final insp = inspections[index];
                          final id = insp['inspectionId'] as int;
                          final isSelected = _selectedIds.contains(id);
                          final isWindow = (insp['assetType']?.toString().toLowerCase() == 'window');
                          final doorCount = insp['doorCount'] != null ? (insp['doorCount'] as num).toInt() : null;
                          final windowCount = insp['windowCount'] != null ? (insp['windowCount'] as num).toInt() : null;

                          return InspectionSummaryCard(
                            inspectionId: id,
                            clientName: insp['clientName'] ?? 'Unbekannt',
                            jobNumber: insp['jobNumber'] ?? 'N/A',
                            projectNumber:
                                insp['projectNumber']?.toString() ?? '',
                            date: insp['date'] ?? '',
                            orderType:
                                insp['orderType']?.toString() ?? 'Wartung',
                            repairDate: insp['repairDate']?.toString(),
                            doorCount: doorCount,
                            assetType: insp['assetType']?.toString(),
                            windowCount: windowCount,
                            isLocked: insp['isLocked'],
                            craftnoteSyncStatus:
                                insp['craftnoteSyncStatus']?.toString(),
                            isSelected: isSelected,
                            onSelectionChanged: (value) => _toggleSelection(id),
                            onLongPress: () => _toggleSelection(id),
                            onTap: () async {
                              if (isSelectionMode) {
                                _toggleSelection(id);
                              } else {
                                if (isWindow) {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => InspectionWindowsPage(
                                        inspectionId: id,
                                        title: insp['clientName'] ?? 'Fensterliste',
                                        isManagerMode: false,
                                      ),
                                    ),
                                  );
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
                                }
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
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Lokal (.db)'),
                  ),
                  const VerticalDivider(),
                  ElevatedButton.icon(
                    onPressed: _isSyncing ? null : _handleCraftnoteExport,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('An Craftnote senden'),
                  ),
                  CraftnoteTestModeSwitch(
                    compact: true,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_door_list',
        tooltip: 'Neuen Auftrag anlegen',
        child: const Icon(Icons.add),
        onPressed: () async {
          int? targetInspId;
          if (_selectedIds.length == 1) {
            targetInspId = _selectedIds.first;
          } else if (_selectedClient != 'Alle' && inspections.isNotEmpty) {
            targetInspId = inspections.first['inspectionId'] as int?;
          } else if (inspections.isNotEmpty) {
            targetInspId = inspections.first['inspectionId'] as int?;
          }

          final created = await CreateProjectDialog.show(
            context,
            isInspectorMode: true,
            sourceInspectionId: targetInspId,
          );

          if (created == true) {
            loadInspections();
          }
        },
      ),
    );
  }
}
