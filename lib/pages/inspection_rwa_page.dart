import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../widgets/barcode_scanner_dialog.dart';
import 'new_rwa_page.dart';
import 'rwa_inspection_page.dart';

enum RwaFilter {
  all,
  ok,
  defects,
}

class InspectionRwaListPage extends StatefulWidget {
  final int inspectionId;
  final String title;
  final bool isManagerMode;

  const InspectionRwaListPage({
    super.key,
    required this.inspectionId,
    required this.title,
    this.isManagerMode = false,
  });

  @override
  State<InspectionRwaListPage> createState() => _InspectionRwaListPageState();
}

class _InspectionRwaListPageState extends State<InspectionRwaListPage> {
  List<RwaSystem> _rwaSystems = [];
  Map<int, int> _defectCounts = {};
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();
  RwaFilter _filter = RwaFilter.all;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      List<RwaSystem> systems = [];
      Map<int, int> defectCounts = {};

      if (widget.isManagerMode) {
        systems = await DatabaseService.getRwaSystemsByInspectionId(widget.inspectionId);
        final junctions = await DatabaseService.getInspectionRwasByInspectionId(widget.inspectionId);
        for (final j in junctions) {
          final rwaId = j['rwaSystemId'] as int;
          final jId = j['id'] as int;
          final errs = await DatabaseService.getInspectionRwaErrors(jId);
          defectCounts[rwaId] = errs.length;
        }
      } else {
        systems = await LocalDatabaseService.getRwaSystemsByInspectionId(widget.inspectionId);
        final junctions = await LocalDatabaseService.getInspectionRwasByInspectionId(widget.inspectionId);
        for (final j in junctions) {
          final rwaId = j['rwaSystemId'] as int;
          final jId = j['id'] as int;
          final errs = await LocalDatabaseService.getInspectionRwaErrors(jId);
          defectCounts[rwaId] = errs.length;
        }
      }

      if (mounted) {
        setState(() {
          _rwaSystems = systems;
          _defectCounts = defectCounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden der RWA-Anlagen: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  List<RwaSystem> get _filteredSystems {
    var result = _rwaSystems;
    final query = _searchCtrl.text.trim().toLowerCase();

    if (query.isNotEmpty) {
      result = result.where((s) {
        final alias = s.displayAlias.toLowerCase();
        final addr = s.objectAddress.toLowerCase();
        final b = s.building.toLowerCase();
        final f = s.floor.toLowerCase();
        final r = s.room.toLowerCase();
        final z = s.centralType.toLowerCase();
        final st = s.systemType.toLowerCase();
        return alias.contains(query) ||
            addr.contains(query) ||
            b.contains(query) ||
            f.contains(query) ||
            r.contains(query) ||
            z.contains(query) ||
            st.contains(query);
      }).toList();
    }

    if (_filter == RwaFilter.ok) {
      result = result.where((s) => (_defectCounts[s.id] ?? 0) == 0 && s.systemFunctionOK).toList();
    } else if (_filter == RwaFilter.defects) {
      result = result.where((s) => (_defectCounts[s.id] ?? 0) > 0 || !s.systemFunctionOK).toList();
    }

    return result;
  }

  Future<void> _addNewRwaSystem() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewRwaPage(
          inspectionId: widget.inspectionId,
          isManagerMode: widget.isManagerMode,
        ),
      ),
    );
    if (changed == true) {
      _loadData();
    }
  }

  Future<void> _scanBarcode() async {
    final scanned = await BarcodeScannerDialog.show(context);
    if (scanned != null && scanned.isNotEmpty) {
      RwaSystem? found;
      if (widget.isManagerMode) {
        found = await DatabaseService.findRwaSystemByBarcode(scanned);
      } else {
        found = await LocalDatabaseService.findRwaSystemByBarcode(scanned);
      }

      if (found != null && mounted) {
        _openInspection(found);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Keine RWA-Anlage mit Barcode "$scanned" gefunden.')),
        );
      }
    }
  }

  void _openInspection(RwaSystem system) async {
    final sysId = system.id;
    if (sysId == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RwaInspectionPage(
          rwaSystemId: sysId,
          inspectionId: widget.inspectionId,
          isManagerMode: widget.isManagerMode,
        ),
      ),
    );
    if (changed == true) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayList = _filteredSystems;
    final okCount = _rwaSystems
        .where((s) => (_defectCounts[s.id] ?? 0) == 0 && s.systemFunctionOK)
        .length;
    final defectCount = _rwaSystems
        .where((s) => (_defectCounts[s.id] ?? 0) > 0 || !s.systemFunctionOK)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Barcode scannen',
            onPressed: _scanBarcode,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Neu laden',
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewRwaSystem,
        icon: const Icon(Icons.add),
        label: const Text('RWA-Anlage anlegen'),
      ),
      body: Column(
        children: [
          // Unified Search Input Field
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 4.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText:
                    'Suchen (Alias, Typ, Raum, Etage, Gebäude, Adresse)...',
                hintStyle:
                    TextStyle(fontSize: 13, color: Colors.grey.shade600),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchCtrl.clear();
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: (val) {
                setState(() {});
              },
            ),
          ),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                FilterChip(
                  label: Text('Alle (${_rwaSystems.length})'),
                  selected: _filter == RwaFilter.all,
                  onSelected: (_) => setState(() => _filter = RwaFilter.all),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(Icons.check_circle_outline,
                      size: 16, color: Colors.green),
                  label: Text('In Ordnung ($okCount)'),
                  selected: _filter == RwaFilter.ok,
                  onSelected: (_) => setState(() => _filter = RwaFilter.ok),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.red),
                  label: Text('Mit Mängeln ($defectCount)'),
                  selected: _filter == RwaFilter.defects,
                  onSelected: (_) =>
                      setState(() => _filter = RwaFilter.defects),
                ),
              ],
            ),
          ),

          // List of RWA systems
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : displayList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fire_extinguisher_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'Keine RWA-Anlagen für diesen Auftrag vorhanden.',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: displayList.length,
                        itemBuilder: (context, index) {
                          final rwa = displayList[index];
                          final defectCount = _defectCounts[rwa.id] ?? 0;
                          final hasDefects = defectCount > 0 || !rwa.systemFunctionOK;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: hasDefects ? Colors.red.shade100 : Colors.green.shade100,
                                child: Icon(
                                  Icons.fire_extinguisher,
                                  color: hasDefects ? Colors.red.shade700 : Colors.green.shade700,
                                ),
                              ),
                              title: Text(
                                rwa.displayAlias,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${rwa.systemType} | ${rwa.centralType}'),
                                  Text(
                                    'Ort: ${rwa.building} ${rwa.floor} ${rwa.room}'.trim(),
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (hasDefects)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$defectCount Mängel',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade900,
                                        ),
                                      ),
                                    )
                                  else
                                    const Icon(Icons.check_circle, color: Colors.green),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () => _openInspection(rwa),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
