import 'dart:io';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../services/excel_export_service.dart';
import '../utils/file_export_helper.dart';
import '../widgets/barcode_scanner_dialog.dart';
import 'new_window_page.dart';

enum InspectionWindowFilter {
  all,
  ok,
  defects,
  raffstoreDefect,
}

class InspectionWindowsPage extends StatefulWidget {
  final int inspectionId;
  final String title;
  final bool isManagerMode;

  const InspectionWindowsPage({
    super.key,
    required this.inspectionId,
    required this.title,
    this.isManagerMode = false,
  });

  @override
  State<InspectionWindowsPage> createState() => _InspectionWindowsPageState();
}

class _InspectionWindowsPageState extends State<InspectionWindowsPage> {
  List<Window> _windows = [];
  Map<int, int> _windowDefectCounts = {};
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  InspectionWindowFilter _filter = InspectionWindowFilter.all;
  String _selectedFloor = 'Alle';
  List<String> _availableFloors = ['Alle'];

  @override
  void initState() {
    super.initState();
    _loadWindows();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWindows() async {
    setState(() => _isLoading = true);
    try {
      List<Window> fetchedWindows = [];
      Map<int, int> defectCounts = {};

      if (widget.isManagerMode) {
        fetchedWindows = await DatabaseService.getWindowsByInspectionId(widget.inspectionId);
        final junctions = await DatabaseService.getInspectionWindowsByInspectionId(widget.inspectionId);
        for (final j in junctions) {
          final winId = j['windowId'] as int;
          final jId = j['id'] as int;
          final errs = await DatabaseService.getInspectionWindowErrors(jId);
          defectCounts[winId] = errs.length;
        }
      } else {
        fetchedWindows = await LocalDatabaseService.getWindowsByInspectionId(widget.inspectionId);
        final junctions = await LocalDatabaseService.getInspectionWindowsByInspectionId(widget.inspectionId);
        for (final j in junctions) {
          final winId = j['windowId'] as int;
          final jId = j['id'] as int;
          final errs = await LocalDatabaseService.getInspectionWindowErrors(jId);
          defectCounts[winId] = errs.length;
        }
      }

      final floors = {'Alle', ...fetchedWindows.map((w) => w.floor.trim()).where((f) => f.isNotEmpty)}.toList()..sort();

      if (mounted) {
        setState(() {
          _windows = fetchedWindows;
          _windowDefectCounts = defectCounts;
          _availableFloors = floors;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden der Fenster: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _scanBarcodeToFindWindow() async {
    final scanned = await BarcodeScannerDialog.show(context, title: 'Fenster scannen');
    if (scanned == null || scanned.trim().isEmpty) return;

    final token = scanned.trim().toLowerCase();
    final match = _windows.where((w) {
      final aliasMatch = w.windowAlias?.toLowerCase() == token || w.provisionalAlias?.toLowerCase() == token;
      final numMatch = w.windowNumber.toLowerCase() == token;
      return aliasMatch || numMatch;
    }).firstOrNull;

    if (match != null) {
      _openWindowDetails(match);
    } else {
      final create = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fenster nicht gefunden'),
          content: Text('Kein Fenster mit Barcode/Nummer "$scanned" in dieser Liste gefunden.\nMöchten Sie es jetzt neu erfassen?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Neu anlegen')),
          ],
        ),
      );

      if (create == true && mounted) {
        final newWin = Window(
          windowNumber: scanned.trim(),
          floor: '',
          roomNumber: '',
          windowType: '',
          material: '',
          windowAlias: scanned.trim(),
        );
        _openWindowDetails(newWin);
      }
    }
  }

  Future<void> _openWindowDetails(Window? window) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewWindowPage(
          window: window,
          inspectionId: widget.inspectionId,
          isManagerMode: widget.isManagerMode,
        ),
      ),
    );

    if (result == true) {
      await _loadWindows();
    }
  }

  Future<void> _exportToExcel() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Excel-Export wird erstellt...')),
      );

      final tempDir = Directory.systemTemp;
      final fileName = 'Fensterliste_${widget.title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final outputPath = '${tempDir.path}/$fileName';

      final exportedFile = await ExcelExportService.exportSingleWindowInspection(
        widget.inspectionId,
        outputPath,
      );

      final savedPath = await FileExportHelper.saveFileSafely(
        defaultFileName: fileName,
        dialogTitle: 'Fensterliste exportieren',
        sourceFile: exportedFile,
        allowedExtensions: ['xlsx'],
      );

      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel-Datei erfolgreich gespeichert: $savedPath'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export-Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.toLowerCase().trim();

    final filteredWindows = _windows.where((w) {
      if (_selectedFloor != 'Alle' && w.floor.trim() != _selectedFloor) return false;

      final count = _windowDefectCounts[w.id] ?? 0;
      switch (_filter) {
        case InspectionWindowFilter.ok:
          if (!w.windowFunctionOK || count > 0) return false;
          break;
        case InspectionWindowFilter.defects:
          if (w.windowFunctionOK && count == 0) return false;
          break;
        case InspectionWindowFilter.raffstoreDefect:
          if (!w.hasRaffstore || w.raffstoreOK != false) return false;
          break;
        case InspectionWindowFilter.all:
          break;
      }

      if (query.isNotEmpty) {
        final inNum = w.windowNumber.toLowerCase().contains(query);
        final inFloor = w.floor.toLowerCase().contains(query);
        final inRoom = w.roomNumber.toLowerCase().contains(query);
        final inDesig = w.roomDesignation.toLowerCase().contains(query);
        final inType = w.windowType.toLowerCase().contains(query);
        final inMat = w.material.toLowerCase().contains(query);
        final inFit = w.fittings.toLowerCase().contains(query);
        final inNotes = w.notes.toLowerCase().contains(query);
        final inAlias = (w.windowAlias?.toLowerCase().contains(query) ?? false) ||
            (w.provisionalAlias?.toLowerCase().contains(query) ?? false);
        return inNum || inFloor || inRoom || inDesig || inType || inMat || inFit || inNotes || inAlias;
      }

      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Fenster suchen...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : Text('${widget.title} (${_windows.length})'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? 'Suche beenden' : 'Suchen',
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) _searchCtrl.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Barcode scannen',
            onPressed: _scanBarcodeToFindWindow,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'export_excel') _exportToExcel();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'export_excel',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Excel exportieren'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey.shade100,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('Alle (${_windows.length})'),
                    selected: _filter == InspectionWindowFilter.all,
                    onSelected: (val) => setState(() => _filter = InspectionWindowFilter.all),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('In Ordnung'),
                    selected: _filter == InspectionWindowFilter.ok,
                    onSelected: (val) => setState(() => _filter = InspectionWindowFilter.ok),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Mit Mängeln'),
                    selected: _filter == InspectionWindowFilter.defects,
                    onSelected: (val) => setState(() => _filter = InspectionWindowFilter.defects),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Raffstore defekt'),
                    selected: _filter == InspectionWindowFilter.raffstoreDefect,
                    onSelected: (val) => setState(() => _filter = InspectionWindowFilter.raffstoreDefect),
                  ),
                  if (_availableFloors.length > 2) ...[
                    const SizedBox(width: 16),
                    DropdownButton<String>(
                      value: _selectedFloor,
                      underline: const SizedBox(),
                      items: _availableFloors
                          .map((f) => DropdownMenuItem(value: f, child: Text(f == 'Alle' ? 'Alle Etagen' : f)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedFloor = val);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredWindows.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.window_outlined, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              _windows.isEmpty ? 'Noch keine Fenster in dieser Prüfung.' : 'Keine Fenster gefunden.',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            if (_windows.isEmpty)
                              ElevatedButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text('Erstes Fenster erfassen'),
                                onPressed: () => _openWindowDetails(null),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredWindows.length,
                        itemBuilder: (context, index) {
                          final w = filteredWindows[index];
                          final count = _windowDefectCounts[w.id] ?? 0;
                          final bool isOk = w.windowFunctionOK && count == 0;

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            elevation: 1.5,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isOk ? Colors.green.shade100 : Colors.red.shade100,
                                child: Icon(
                                  Icons.window,
                                  color: isOk ? Colors.green.shade800 : Colors.red.shade800,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    w.windowNumber,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(width: 8),
                                  if (w.floor.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blue.shade200),
                                      ),
                                      child: Text(w.floor, style: TextStyle(fontSize: 11, color: Colors.blue.shade900)),
                                    ),
                                  const Spacer(),
                                  if (isOk)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.green.shade300),
                                      ),
                                      child: const Text('In Ordnung', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.red.shade300),
                                      ),
                                      child: Text('$count Mängel', style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      if (w.roomNumber.isNotEmpty) 'Raum ${w.roomNumber}',
                                      if (w.roomDesignation.isNotEmpty) w.roomDesignation,
                                      if (w.windowType.isNotEmpty) w.windowType,
                                      if (w.material.isNotEmpty) w.material,
                                      if (w.wingDimensions.isNotEmpty) w.wingDimensions,
                                      if (w.fittings.isNotEmpty) w.fittings,
                                    ].join(' • '),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (w.hasRaffstore) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          w.raffstoreOK == true ? Icons.check : Icons.warning_amber_rounded,
                                          size: 14,
                                          color: w.raffstoreOK == true ? Colors.green : Colors.orange.shade800,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Raffstore: ${w.raffstoreOK == true ? "In Ordnung" : "Defekt"}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: w.raffstoreOK == true ? Colors.green.shade800 : Colors.orange.shade800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (w.notes.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Notiz: ${w.notes}',
                                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openWindowDetails(w),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Fenster erfassen'),
        onPressed: () => _openWindowDetails(null),
      ),
    );
  }
}
