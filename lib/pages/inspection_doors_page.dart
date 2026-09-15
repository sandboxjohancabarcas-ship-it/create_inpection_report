import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../utils/inspection_year_utils.dart';
import '../widgets/edit_inspection_dialog.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/master_portal_home_button.dart';
import 'new_door_page.dart';
import 'door_history_page.dart';

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
  String? _inspectionDate;
  bool _isEditable = true;

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

    final Map<String, dynamic>? inspData = widget.isManagerMode
        ? await DatabaseService.getInspectionById(widget.inspectionId)
        : await LocalDatabaseService.getInspectionById(widget.inspectionId);

    _inspectionDate = inspData?['date']?.toString();
    final isLocked = inspData?['isLocked'];
    _isEditable = InspectionYearUtils.isEditable(
      isManagerMode: widget.isManagerMode,
      dateValue: _inspectionDate,
      isLocked: isLocked,
    );

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
    if (!_isEditable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Türen in Vorjahres-Aufträgen können vom Inspektor nicht gelöscht werden.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
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
    if (!_isEditable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vorjahres-Aufträge sind für Inspektoren schreibgeschützt.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final scanned = await BarcodeScannerDialog.show(
      context,
      title: 'Barcode für Türsuche / Alias-Zuweisung scannen',
    );
    if (scanned == null || scanned.isEmpty || !mounted) return;

    final matchingDoor = _doors.firstWhereOrNull(
      (d) => (d.doorAlias?.toLowerCase() == scanned.toLowerCase()) ||
             (d.provisionalAlias?.toLowerCase() == scanned.toLowerCase()) ||
             (d.doorNumber.toLowerCase() == scanned.toLowerCase()),
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
            isReadOnly: !_isEditable,
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
    if (!_isEditable) return;
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
    if (door.id == null || !_isEditable) return;
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

  void _showDoorNotesPopUp(Door door) {
    final notesText = door.notes.isNotEmpty ? door.notes : '(Keine Notizen erfasst)';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.note_alt_outlined, color: Colors.blue.shade800, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tür ${door.doorNumber} - Notizen & Mängel', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Barcode: ${door.doorAlias ?? "Kein Alias"}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SelectableText(
                    notesText,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Schließen'),
            onPressed: () => Navigator.pop(ctx),
          ),
          if (_isEditable)
            ElevatedButton.icon(
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Formular bearbeiten'),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DoorInspectionForm(
                      door: door,
                      isManagerMode: widget.isManagerMode,
                      inspectionId: widget.inspectionId,
                      isReadOnly: !_isEditable,
                    ),
                  ),
                ).then((_) => _loadDoors());
              },
            ),
        ],
      ),
    );
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(widget.title, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _isEditable ? Colors.green.shade50 : Colors.red.shade50,
                    border: Border.all(color: _isEditable ? Colors.green.shade300 : Colors.red.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isEditable ? Icons.lock_open : Icons.lock,
                        size: 10,
                        color: _isEditable ? Colors.green.shade900 : Colors.red.shade900,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isEditable ? 'Freigegeben' : 'Gesperrt',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _isEditable ? Colors.green.shade900 : Colors.red.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Text(
              'ID: ${widget.inspectionId} • ${_doors.length} Tür(en)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: isSelectionMode
            ? [
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
                ),
              ]
            : [
                if (widget.isManagerMode)
            IconButton(
              icon: Icon(
                _isEditable ? Icons.lock_open : Icons.lock,
                color: _isEditable ? Colors.green : Colors.red,
              ),
              tooltip: _isEditable ? 'Auftrag sperren (für Inspektor sperren)' : 'Auftrag entsperren (für Inspektor freigeben)',
              onPressed: () async {
                await DatabaseService.setInspectionLockStatus(widget.inspectionId, _isEditable);
                _loadDoors();
              },
            ),
          if (_isEditable)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Colors.deepPurple),
              tooltip: 'Barcode / QR-Code scannen',
              onPressed: _handleScanBarcode,
            ),
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: widget.isManagerMode
                ? 'Auftrags-Metadaten & Sperrstatus bearbeiten'
                : 'Schreibgeschützt für Inspektor',
            onPressed: () async {
              if (!widget.isManagerMode) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Inspektionsdaten können nur vom Manager bearbeitet werden.'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
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
          if (!_isEditable)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_clock, color: Colors.orange.shade900),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Gesperrte Inspektion: Im Lesemodus. Inspektoren können gesperrte Inspektionen nicht bearbeiten.',
                      style: TextStyle(fontSize: 13, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
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
                                        if (door.notes.isNotEmpty)
                                          IconButton(
                                            icon: const Icon(Icons.note_alt_outlined, color: Colors.blue, size: 20),
                                            tooltip: 'Notizen & Mängel im Pop-Up Fenster öffnen',
                                            onPressed: () => _showDoorNotesPopUp(door),
                                          ),
                                        IconButton(
                                          icon: const Icon(Icons.history_edu, color: Colors.blueGrey, size: 20),
                                          tooltip: 'Tür-Akte & Historie',
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => DoorHistoryPage(
                                                  doorId: door.id,
                                                  doorAlias: door.doorAlias,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        if (_isEditable)
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
                                        Icon(_isEditable ? Icons.edit_note : Icons.visibility, color: _isEditable ? null : Colors.grey),
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
                                        isReadOnly: !_isEditable,
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
                    onPressed: (_isSyncing || !_isEditable) ? null : _handleDeleteDoors,
                    icon: Icon(Icons.delete_outline, color: _isEditable ? Colors.red : Colors.grey),
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
      floatingActionButton: (widget.isManagerMode || isSelectionMode || !_isEditable)
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