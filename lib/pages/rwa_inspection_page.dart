import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../services/rwa_options_service.dart';
import 'rwa_error_management_page.dart';

class RwaInspectionPage extends StatefulWidget {
  final int rwaSystemId;
  final int inspectionId;
  final bool isManagerMode;
  final bool isReadOnly;

  const RwaInspectionPage({
    super.key,
    required this.rwaSystemId,
    required this.inspectionId,
    this.isManagerMode = false,
    this.isReadOnly = false,
  });

  @override
  State<RwaInspectionPage> createState() => _RwaInspectionPageState();
}

class _RwaInspectionPageState extends State<RwaInspectionPage> {
  RwaSystem? _rwaSystem;
  int? _inspectionRwaId;
  List<RwaInspectionSetting> _settings = [];
  Map<String, int> _defectCountBySetting = {};
  int _totalDefects = 0;
  bool _isLoading = true;
  bool _isSaving = false;

  final Map<String, TextEditingController> _annotationControllers = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final c in _annotationControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Load RWA System
      RwaSystem? system;
      List<Map<String, dynamic>> junctions = [];
      if (widget.isManagerMode) {
        system = await DatabaseService.getRwaSystemById(widget.rwaSystemId);
        junctions = await DatabaseService.getInspectionRwasByInspectionId(widget.inspectionId);
      } else {
        system = await LocalDatabaseService.getRwaSystemById(widget.rwaSystemId);
        junctions = await LocalDatabaseService.getInspectionRwasByInspectionId(widget.inspectionId);
      }

      // 2. Find or create junction
      final j = junctions.where((m) => m['rwaSystemId'] == widget.rwaSystemId).firstOrNull;
      int junctionId;
      if (j != null) {
        junctionId = j['id'] as int;
      } else {
        final newJ = InspectionRwa(
          inspectionId: widget.inspectionId,
          rwaSystemId: widget.rwaSystemId,
          status: 'InProgress',
          notes: '',
        );
        if (widget.isManagerMode) {
          junctionId = await DatabaseService.insertInspectionRwa(newJ.toMap());
        } else {
          junctionId = await LocalDatabaseService.insertInspectionRwa(newJ.toMap());
        }
      }

      // 3. Load settings
      List<RwaInspectionSetting> loadedSettings = [];
      if (widget.isManagerMode) {
        loadedSettings = await DatabaseService.getRwaInspectionSettings(junctionId);
      } else {
        loadedSettings = await LocalDatabaseService.getRwaInspectionSettings(junctionId);
      }

      // If settings are empty, initialize with default 12 items
      if (loadedSettings.isEmpty) {
        final defaultNames = RwaOptionsService.einrichtungSettings;
        loadedSettings = defaultNames.map((name) {
          return RwaInspectionSetting(
            inspectionRwaId: junctionId,
            settingName: name,
            result: 'OK',
            rawResult: 'I.O',
            annotation: '',
          );
        }).toList();
        if (widget.isManagerMode) {
          await DatabaseService.saveRwaInspectionSettings(junctionId, loadedSettings);
        } else {
          await LocalDatabaseService.saveRwaInspectionSettings(junctionId, loadedSettings);
        }
      }

      // 4. Load defects count
      List<InspectionRwaError> errors = [];
      if (widget.isManagerMode) {
        errors = await DatabaseService.getInspectionRwaErrors(junctionId);
      } else {
        errors = await LocalDatabaseService.getInspectionRwaErrors(junctionId);
      }

      final counts = <String, int>{};
      for (final err in errors) {
        counts[err.settingName] = (counts[err.settingName] ?? 0) + 1;
      }

      // 5. Setup controllers
      for (final s in loadedSettings) {
        if (!_annotationControllers.containsKey(s.settingName)) {
          _annotationControllers[s.settingName] = TextEditingController(text: s.annotation);
        } else {
          _annotationControllers[s.settingName]!.text = s.annotation;
        }
      }

      if (mounted) {
        setState(() {
          _rwaSystem = system;
          _inspectionRwaId = junctionId;
          _settings = loadedSettings;
          _defectCountBySetting = counts;
          _totalDefects = errors.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateSettingResult(int index, String newResult) async {
    if (widget.isReadOnly) return;
    final current = _settings[index];
    final updated = current.copyWith(
      result: newResult,
      rawResult: newResult == 'OK' ? 'I.O' : (newResult == 'DEFECT' ? 'X' : 'n.v'),
      annotation: _annotationControllers[current.settingName]?.text ?? current.annotation,
    );

    setState(() {
      _settings[index] = updated;
    });

    if (_inspectionRwaId != null) {
      if (widget.isManagerMode) {
        await DatabaseService.saveRwaInspectionSettings(_inspectionRwaId!, _settings);
      } else {
        await LocalDatabaseService.saveRwaInspectionSettings(_inspectionRwaId!, _settings);
      }
    }

    // If marked as DEFECT, directly prompt to add an error if none exists yet
    if (newResult == 'DEFECT') {
      _openDefectManagement(current.settingName);
    }
  }

  Future<void> _saveAll() async {
    if (widget.isReadOnly || _inspectionRwaId == null) return;
    setState(() => _isSaving = true);
    try {
      final updatedSettings = <RwaInspectionSetting>[];
      bool hasDefects = false;

      for (final s in _settings) {
        final ann = _annotationControllers[s.settingName]?.text.trim() ?? '';
        final res = s.result;
        if (res == 'DEFECT') hasDefects = true;
        updatedSettings.add(s.copyWith(annotation: ann));
      }

      if (widget.isManagerMode) {
        await DatabaseService.saveRwaInspectionSettings(_inspectionRwaId!, updatedSettings);
        if (_rwaSystem != null) {
          await DatabaseService.updateRwaSystem(_rwaSystem!.copyWith(
            systemFunctionOK: !hasDefects && _totalDefects == 0,
          ));
        }
      } else {
        await LocalDatabaseService.saveRwaInspectionSettings(_inspectionRwaId!, updatedSettings);
        if (_rwaSystem != null) {
          await LocalDatabaseService.updateRwaSystem(_rwaSystem!.copyWith(
            systemFunctionOK: !hasDefects && _totalDefects == 0,
          ));
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prüfung erfolgreich gespeichert!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Speichern: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openDefectManagement(String settingName) async {
    if (_rwaSystem == null || _inspectionRwaId == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RwaErrorManagementPage(
          rwaSystemId: _rwaSystem!.id!,
          systemAlias: _rwaSystem!.displayAlias,
          inspectionId: widget.inspectionId,
          inspectionRwaId: _inspectionRwaId!,
          initialSettingName: settingName,
          isManagerMode: widget.isManagerMode,
          isReadOnly: widget.isReadOnly,
        ),
      ),
    );
    if (changed == true) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final system = _rwaSystem;
    final title = system?.displayAlias ?? 'RWA-Prüfung';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.report_problem_outlined),
            tooltip: 'Mängelübersicht ($_totalDefects)',
            onPressed: () => _openDefectManagement(''),
          ),
          if (!widget.isReadOnly)
            IconButton(
              icon: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check),
              tooltip: 'Speichern',
              onPressed: _saveAll,
            ),
        ],
      ),
      body: Column(
        children: [
          // Header summary card
          _buildSystemHeaderCard(),

          // 12 Einrichtung inspection items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _settings.length,
              itemBuilder: (context, index) {
                final setting = _settings[index];
                return _buildSettingCard(setting, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemHeaderCard() {
    final sys = _rwaSystem;
    if (sys == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fire_extinguisher, color: Colors.deepOrange, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${sys.systemType} - ${sys.objectAddress}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _totalDefects > 0 ? Colors.red.shade100 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _totalDefects > 0 ? '$_totalDefects Mängel' : 'Keine Mängel',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _totalDefects > 0 ? Colors.red.shade900 : Colors.green.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Gebäude: ${sys.building.isEmpty ? "-" : sys.building} | Geschoss: ${sys.floor.isEmpty ? "-" : sys.floor} | Raum: ${sys.room.isEmpty ? "-" : sys.room}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          if (sys.centralType.isNotEmpty)
            Text(
              'Zentrale: ${sys.centralType}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
        ],
      ),
    );
  }

  Widget _buildSettingCard(RwaInspectionSetting setting, int index) {
    final defectCount = _defectCountBySetting[setting.settingName] ?? 0;
    final isDefect = setting.result == 'DEFECT' || defectCount > 0;
    final isOk = setting.result == 'OK' && defectCount == 0;
    final isNotPresent = setting.result == 'NOT_PRESENT';

    Color cardBorderColor = Colors.grey.shade300;
    if (isDefect) {
      cardBorderColor = Colors.red.shade400;
    } else if (isOk) {
      cardBorderColor = Colors.green.shade400;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cardBorderColor, width: isDefect ? 1.5 : 1.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    setting.settingName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                // Quick Toggle Buttons: i.O. | Mangel | N.V.
                _buildSegmentButton('i.O.', 'OK', isOk, Colors.green, () => _updateSettingResult(index, 'OK')),
                const SizedBox(width: 6),
                _buildSegmentButton('Mangel', 'DEFECT', isDefect, Colors.red, () => _updateSettingResult(index, 'DEFECT')),
                const SizedBox(width: 6),
                _buildSegmentButton('N.V.', 'NOT_PRESENT', isNotPresent, Colors.grey, () => _updateSettingResult(index, 'NOT_PRESENT')),
              ],
            ),
            const SizedBox(height: 8),

            // Annotation text field & Defect button
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _annotationControllers[setting.settingName],
                    enabled: !widget.isReadOnly,
                    decoration: InputDecoration(
                      labelText: 'Anmerkungen / Spezifikation (z.B. Akku-Baujahr, Details)',
                      labelStyle: const TextStyle(fontSize: 11),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Badge(
                    label: Text('$defectCount'),
                    isLabelVisible: defectCount > 0,
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: defectCount > 0 ? Colors.red : Colors.grey.shade600,
                    ),
                  ),
                  tooltip: 'Mängel für "${setting.settingName}" erfassen',
                  onPressed: () => _openDefectManagement(setting.settingName),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentButton(
    String label,
    String value,
    bool isSelected,
    Color activeColor,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: widget.isReadOnly ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey.shade400,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? activeColor : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
