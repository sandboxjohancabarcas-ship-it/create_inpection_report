import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
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
  bool _isLoading = true;
  final Set<int> _selectedDoorIds = {};
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadDoors();
  }

  Future<void> _loadDoors() async {
    setState(() => _isLoading = true);
    List<Door> doors;
    _selectedDoorIds.clear();
    if (widget.isManagerMode) {
      doors = await DatabaseService.getDoorsByInspectionIds([widget.inspectionId]);
    } else {
      doors = await LocalDatabaseService.getDoorsByInspectionId(widget.inspectionId);
    }
    setState(() {
      _doors = doors;
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
              'ID: ${widget.inspectionId}',
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
        ] : null,
        leading: isSelectionMode ? IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _selectedDoorIds.clear()),
        ) : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _doors.isEmpty
              ? const Center(child: Text("Keine Türen in diesem Auftrag gefunden"))
              : ListView.builder(
                  itemCount: _doors.length,
                  itemBuilder: (context, index) {
                    final door = _doors[index];
                    final isSelected = _selectedDoorIds.contains(door.id);

                    return Card(
                      color: isSelected ? Colors.blue.shade50 : null,
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: isSelectionMode 
                          ? Checkbox(value: isSelected, onChanged: (_) => _toggleSelection(door.id!))
                          : const Icon(Icons.door_front_door, color: Colors.blue),
                        title: Text('Tür ${door.doorNumber}'),
                        subtitle: Text('ID: ${door.doorAlias ?? "Kein Alias"}\n${door.floor} | ${door.roomDesignation}'),
                        trailing: isSelectionMode ? null : const Icon(Icons.edit_note),
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
              tooltip: 'Neue Tür hinzufügen',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DoorInspectionForm(
                      isManagerMode: widget.isManagerMode,
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