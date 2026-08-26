import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../widgets/edit_inspection_dialog.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/master_portal_home_button.dart';
import 'new_door_page.dart';

class InspectionDoorsPage extends StatefulWidget {
  final int inspectionId;
  final String title;
  final bool isManagerMode;

  const InspectionDoorsPage({
    super.key,
    required this.inspectionId,
    required this.title,
    this.isManagerMode = false,
  });

  @override
  State<InspectionDoorsPage> createState() => _InspectionDoorsPageState();
}

class _InspectionDoorsPageState extends State<InspectionDoorsPage> {
  List<Door> _doors = [];
  Map<int, DoorErrorSummary> _errorSummaries = {};
  bool _isLoading = true;
  final Set<int> _selectedDoorIds = {};
  bool _isSyncing = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDoors();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDoors() async {
    setState(() => _isLoading = true);
    List<Door> doors;
    Map<int, DoorErrorSummary> errorSummaries;
    _selectedDoorIds.clear();

    if (widget.isManagerMode) {
      doors = await DatabaseService.getDoorsByInspectionIds(
        [widget.inspectionId],
        query: _searchController.text,
      );
      errorSummaries = await DatabaseService.getDoorErrorSummariesForInspection(widget.inspectionId);
    } else {
      doors = await LocalDatabaseService.getDoorsByInspectionId(
        widget.inspectionId,
        query: _searchController.text,
      );
      errorSummaries = await LocalDatabaseService.getDoorErrorSummariesForInspection(widget.inspectionId);
    }

    setState(() {
      _doors = doors;
      _errorSummaries = errorSummaries;
      _isLoading = false;
    });
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

  Future<void> _handleDeleteDoors() async {
    if (_selectedDoorIds.isEmpty) return;
    final bool confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Löschen bestätigen'),
        content: Text('${_selectedDoorIds.length} Tür(en) unwiderruflich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (!confirm) return;
    await LocalDatabaseService.deleteDoors(_selectedDoorIds.toList());
    _loadDoors();
  }

  Future<void> _handleExportDoors() async {
    if (_selectedDoorIds.isEmpty) return;
    setState(() => _isSyncing = true);
    try {
      final String downloadPath = Platform.isAndroid 
          ? '/storage/emulated/0/Download' 
          : (await getDownloadsDirectory())?.path ?? (await getApplicationDocumentsDirectory()).path;
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final exportPath = p.join(downloadPath, 'tueren_export_$timestamp.db');

      await LocalDatabaseService.exportSelectiveJobPackage(_selectedDoorIds.toList(), exportPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export erfolgreich: $exportPath'), backgroundColor: Colors.green));
        setState(() => _selectedDoorIds.clear());
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export fehlgeschlagen: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  Future<void> _handleScanBarcode() async {
    final scanned = await BarcodeScannerDialog.show(
      context,
      title: 'Barcode für Türsuche / Alias-Zuweisung scannen',
    );
    if (scanned == null || scanned.isEmpty || !mounted) return;

    final matchingDoor = _doors.firstWhereOrNull(
      (d) => (d.doorAlias?.toLowerCase() == scanned.toLowerCase()) || (d.doorNumber.toLowerCase() == scanned.toLowerCase()),
    );

    if (matchingDoor != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tür ${matchingDoor.doorNumber} (Alias: ${matchingDoor.doorAlias}) gefunden!'),
          backgroundColor: Colors.green,
        ),
      );
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DoorInspectionForm(
            door: matchingDoor,
            isManagerMode: widget.isManagerMode,
            inspectionId: widget.inspectionId,
          ),
        ),
      );
      _loadDoors();
    } else {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Barcode nicht zugeordnet'),
          content: Text('Der gescannte Barcode "$scanned" konnte keiner Tür in diesem Auftrag zugeordnet werden.\n\nMöchten Sie diesen Barcode einer bestehenden Tür als Alias zuweisen?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'assign'),
              icon: const Icon(Icons.link),
              label: const Text('Existierender Tür zuweisen'),
            ),
          ],
        ),
      );

      if (action == 'assign' && mounted) {
        _showAssignBarcodeDialog(scanned);
      }
    }
  }

  void _showAssignBarcodeDialog(String scannedAlias) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tür für Alias-Zuweisung wählen'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _doors.length,
            itemBuilder: (context, index) {
              final door = _doors[index];
              return ListTile(
                leading: const Icon(Icons.door_front_door, color: Colors.deepPurple),
                title: Text('Tür ${door.doorNumber}'),
                subtitle: Text('Aktueller Alias: ${door.doorAlias ?? "Keiner"}\n${door.floor} | ${door.roomDesignation}'),
                onTap: () async {
                  Navigator.pop(context);
                  await _updateDoorAlias(door, scannedAlias);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        ],
      ),
    );
  }

  Future<void> _updateDoorAlias(Door door, String newAlias) async {
    if (door.id == null) return;
    if (widget.isManagerMode) {
      await DatabaseService.updateDoorAlias(door.id!, newAlias);
    } else {
      await LocalDatabaseService.updateDoorAlias(door.id!, newAlias);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Neuer Alias "$newAlias" für Tür ${door.doorNumber} gespeichert.'),
          backgroundColor: Colors.green,
        ),
      );
      _loadDoors();
    }
  }

  Widget _buildErrorStatusBadge(DoorErrorSummary summary) {
    Color bg;
    Color fg;
    IconData icon;
    String text;

    switch (summary.state) {
      case DoorErrorState.hasOpenErrors:
        bg = Colors.red.shade100;
        fg = Colors.red.shade900;
        icon = Icons.error;
        text = summary.openErrors > 1
            ? '${summary.openErrors} Fehler'
            : 'Fehlerhaft';
        break;
      case DoorErrorState.allErrorsResolved:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        icon = Icons.check_circle;
        text = 'Fehler gelöst';
        break;
      case DoorErrorState.noErrors:
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        icon = Icons.check_circle_outline;
        text = 'Keine Fehler';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeadingIcon(DoorErrorSummary summary, bool isSelected, bool isSelectionMode, int doorId) {
    if (isSelectionMode) {
      return Checkbox(
        value: isSelected,
        onChanged: (_) => _toggleSelection(doorId),
      );
    }

    Color iconColor;
    Color avatarBg;
    IconData icon;

    switch (summary.state) {
      case DoorErrorState.hasOpenErrors:
        iconColor = Colors.red.shade700;
        avatarBg = Colors.red.shade50;
        icon = Icons.error;
        break;
      case DoorErrorState.allErrorsResolved:
        iconColor = Colors.amber.shade800;
        avatarBg = Colors.amber.shade50;
        icon = Icons.check_circle;
        break;
      case DoorErrorState.noErrors:
        iconColor = Colors.green.shade700;
        avatarBg = Colors.green.shade50;
        icon = Icons.door_front_door;
        break;
    }

    return CircleAvatar(
      backgroundColor: avatarBg,
      child: Icon(icon, color: iconColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isSelectionMode = _selectedDoorIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: isSelectionMode 
          ? Text('${_selectedDoorIds.length} ausgewählt')
          : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            Text(
              'ID: ${widget.inspectionId} • ${_doors.length} Tür(en)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: isSelectionMode ? [
          IconButton(
            icon: Icon(_selectedDoorIds.length == _doors.length ? Icons.check_box : Icons.check_box_outline_blank),
            onPressed: () {
              setState(() {
                if (_selectedDoorIds.length == _doors.length) {
                  _selectedDoorIds.clear();
                } else {
                  _selectedDoorIds.addAll(_doors.map((d) => d.id!));
                }
              });
            },
          )
        ] : [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Colors.deepPurple),
            tooltip: 'Barcode / QR-Code scannen',
            onPressed: _handleScanBarcode,
          ),
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Auftrags-Metadaten bearbeiten',
            onPressed: () async {
              final updated = await EditInspectionDialog.show(
                context,
                inspectionId: widget.inspectionId,
                isManagerMode: widget.isManagerMode,
              );
              if (updated == true && mounted) {
                _loadDoors();
              }
            },
          ),
          const MasterPortalHomeButton(),
        ],
        leading: isSelectionMode ? IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _selectedDoorIds.clear()),
        ) : null,
      ),
      body: Column(
        children: [
          if (!isSelectionMode)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Türen durchsuchen',
                  hintText: 'Türnummer, Raum, Bezeichnung oder Fehler...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _loadDoors();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (value) => _loadDoors(),
              ),
            ),
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _searchController.text.isNotEmpty
                        ? 'Gefundene Türen: ${_doors.length}'
                        : 'Türen gesamt: ${_doors.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _doors.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isNotEmpty
                              ? 'Keine Türen für "${_searchController.text}" gefunden'
                              : 'Keine Türen in diesem Auftrag gefunden',
                        ),
                      )
                    : ListView.builder(
                        itemCount: _doors.length,
                        itemBuilder: (context, index) {
                          final door = _doors[index];
                          final isSelected = _selectedDoorIds.contains(door.id);
                          final summary = _errorSummaries[door.id] ?? const DoorErrorSummary(totalErrors: 0, openErrors: 0, resolvedErrors: 0);

                          return Card(
                            color: isSelected ? Colors.blue.shade50 : null,
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              leading: _buildLeadingIcon(summary, isSelected, isSelectionMode, door.id!),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Tür ${door.doorNumber}',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (!isSelectionMode) _buildErrorStatusBadge(summary),
                                ],
                              ),
                              subtitle: Text('ID: ${door.doorAlias ?? "Kein Alias"}\n${door.floor} | ${door.roomDesignation}'),
                              trailing: isSelectionMode
                                  ? null
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.qr_code_scanner, color: Colors.deepPurple, size: 20),
                                          tooltip: 'Barcode scannen & Alias zuweisen',
                                          onPressed: () async {
                                            final scanned = await BarcodeScannerDialog.show(
                                              context,
                                              title: 'Neuen Barcode für Tür ${door.doorNumber} scannen',
                                            );
                                            if (scanned != null && scanned.isNotEmpty && mounted) {
                                              await _updateDoorAlias(door, scanned);
                                            }
                                          },
                                        ),
                                        const Icon(Icons.edit_note),
                                      ],
                                    ),
                              onTap: () async {
                                if (isSelectionMode) {
                                  _toggleSelection(door.id!);
                                } else {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DoorInspectionForm(
                                        door: door,
                                        isManagerMode: widget.isManagerMode,
                                        inspectionId: widget.inspectionId,
                                      ),
                                    ),
                                  );
                                  _loadDoors();
                                }
                              },
                              onLongPress: () => _toggleSelection(door.id!),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: (!isSelectionMode || widget.isManagerMode)
          ? null
          : BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    onPressed: _isSyncing ? null : _handleDeleteDoors,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Löschen',
                  ),
                  const VerticalDivider(),
                  TextButton.icon(
                    onPressed: _isSyncing ? null : _handleExportDoors,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Exportieren'),
                  ),
                ],
              ),
            ),
      floatingActionButton: (widget.isManagerMode || isSelectionMode)
          ? null
          : FloatingActionButton(
              heroTag: 'fab_inspection_doors',
              tooltip: 'Neue Tür hinzufügen',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DoorInspectionForm(
                      isManagerMode: widget.isManagerMode,
                      inspectionId: widget.inspectionId,
                    ),
                  ),
                );
                _loadDoors();
              },
              child: const Icon(Icons.add),
            ),
    );
  }
}