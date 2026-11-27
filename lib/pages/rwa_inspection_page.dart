import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../services/rwa_options_service.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/editable_dropdown_field.dart';
import '../widgets/master_portal_home_button.dart';
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
  final _formKey = GlobalKey<FormState>();

  RwaSystem? _rwaSystem;
  int? _inspectionRwaId;
  List<RwaInspectionSetting> _settings = [];
  Map<String, int> _defectCountBySetting = {};
  int _totalDefects = 0;
  bool _isLoading = true;
  bool _isSaving = false;

  // Controllers for Category 1: Inspektionsdaten (Metadata)
  late TextEditingController _customerNameCtrl;
  late TextEditingController _customerAddressCtrl;
  late TextEditingController _contactPersonCtrl;
  late TextEditingController _jobNumberCtrl;
  late TextEditingController _projectNumberCtrl;
  late TextEditingController _inspectorNameCtrl;
  DateTime _inspectionDate = DateTime.now();

  // Controllers & state for Category 2: RWA-System (Identification & Specs)
  late TextEditingController _aliasCtrl;
  late TextEditingController _buildingCtrl;
  late TextEditingController _floorCtrl;
  late TextEditingController _roomCtrl;
  late TextEditingController _systemNotesCtrl;

  String _systemType = '';
  String _centralType = '';
  String _fireButtonSpec = '';
  String _smokeDetectorSpec = '';
  String _actuatorSpec = '';
  String _ventilationButtonSpec = '';
  String _emergencyPowerSpec = '';
  String _co2BottleSpec = '';
  String _thermalBottleSpec = '';
  String _rwaFlapSpec = '';
  String _ventilationFlapSpec = '';
  String _damperSpec = '';

  // Controllers for Category 3: Einrichtung (Annotations for 12 items)
  final Map<String, TextEditingController> _annotationControllers = {};

  bool get _canSave => !widget.isReadOnly;

  @override
  void initState() {
    super.initState();
    _customerNameCtrl = TextEditingController();
    _customerAddressCtrl = TextEditingController();
    _contactPersonCtrl = TextEditingController();
    _jobNumberCtrl = TextEditingController();
    _projectNumberCtrl = TextEditingController();
    _inspectorNameCtrl = TextEditingController();

    _aliasCtrl = TextEditingController();
    _buildingCtrl = TextEditingController();
    _floorCtrl = TextEditingController();
    _roomCtrl = TextEditingController();
    _systemNotesCtrl = TextEditingController();

    _loadData();
  }

  @override
  void dispose() {
    _customerNameCtrl.dispose();
    _customerAddressCtrl.dispose();
    _contactPersonCtrl.dispose();
    _jobNumberCtrl.dispose();
    _projectNumberCtrl.dispose();
    _inspectorNameCtrl.dispose();

    _aliasCtrl.dispose();
    _buildingCtrl.dispose();
    _floorCtrl.dispose();
    _roomCtrl.dispose();
    _systemNotesCtrl.dispose();

    for (final c in _annotationControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await RwaOptionsService.ensureLoaded();

      // 1. Load Inspection Metadata
      Map<String, dynamic>? insp;
      if (widget.isManagerMode) {
        insp = await DatabaseService.getInspectionById(widget.inspectionId);
      } else {
        insp = await LocalDatabaseService.getInspectionById(widget.inspectionId);
      }

      if (insp != null) {
        _customerNameCtrl.text = (insp['clientName'] ?? '').toString();
        _customerAddressCtrl.text = (insp['objectAddress'] ?? '').toString();
        _contactPersonCtrl.text = (insp['contactPerson'] ?? '').toString();
        _jobNumberCtrl.text = (insp['jobNumber'] ?? '').toString();
        _projectNumberCtrl.text = (insp['projectNumber'] ?? '').toString();
        _inspectorNameCtrl.text = (insp['inspectorName'] ?? '').toString();
        final rawDate = insp['date']?.toString();
        if (rawDate != null && rawDate.isNotEmpty) {
          try {
            _inspectionDate = DateTime.parse(rawDate);
          } catch (_) {}
        }
      }

      // 2. Load RWA System
      RwaSystem? system;
      List<Map<String, dynamic>> junctions = [];
      if (widget.isManagerMode) {
        system = await DatabaseService.getRwaSystemById(widget.rwaSystemId);
        junctions = await DatabaseService.getInspectionRwasByInspectionId(widget.inspectionId);
      } else {
        system = await LocalDatabaseService.getRwaSystemById(widget.rwaSystemId);
        junctions = await LocalDatabaseService.getInspectionRwasByInspectionId(widget.inspectionId);
      }

      if (system != null) {
        _aliasCtrl.text = system.systemAlias ?? '';
        if (_customerAddressCtrl.text.isEmpty && system.objectAddress.isNotEmpty) {
          _customerAddressCtrl.text = system.objectAddress;
        }
        _buildingCtrl.text = system.building;
        _floorCtrl.text = system.floor;
        _roomCtrl.text = system.room;
        _systemNotesCtrl.text = system.notes;

        _systemType = system.systemType.isNotEmpty ? system.systemType : RwaOptionsService.getDefault('systemType');
        _centralType = system.centralType.isNotEmpty ? system.centralType : RwaOptionsService.getDefault('centralType');
        _fireButtonSpec = system.fireButtonSpec.isNotEmpty ? system.fireButtonSpec : RwaOptionsService.getDefault('fireButton');
        _smokeDetectorSpec = system.smokeDetectorSpec.isNotEmpty ? system.smokeDetectorSpec : RwaOptionsService.getDefault('smokeDetector');
        _actuatorSpec = system.actuatorSpec.isNotEmpty ? system.actuatorSpec : RwaOptionsService.getDefault('actuator');
        _ventilationButtonSpec = system.ventilationButtonSpec.isNotEmpty ? system.ventilationButtonSpec : RwaOptionsService.getDefault('ventilationButton');
        _emergencyPowerSpec = system.emergencyPowerSpec.isNotEmpty ? system.emergencyPowerSpec : RwaOptionsService.getDefault('emergencyPower');
        _co2BottleSpec = system.co2BottleSpec.isNotEmpty ? system.co2BottleSpec : RwaOptionsService.getDefault('co2Bottles');
        _thermalBottleSpec = system.thermalBottleSpec.isNotEmpty ? system.thermalBottleSpec : RwaOptionsService.getDefault('thermalBottle');
        _rwaFlapSpec = system.rwaFlapSpec.isNotEmpty ? system.rwaFlapSpec : RwaOptionsService.getDefault('rwaFlaps');
        _ventilationFlapSpec = system.ventilationFlapSpec.isNotEmpty ? system.ventilationFlapSpec : RwaOptionsService.getDefault('ventilationFlaps');
        _damperSpec = system.damperSpec.isNotEmpty ? system.damperSpec : RwaOptionsService.getDefault('dampers');
      }

      // 3. Find or create junction
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

      // 4. Load settings
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

      // 5. Load defects count
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

      // 6. Setup controllers for annotations
      for (final s in loadedSettings) {
        _annotationControllers.putIfAbsent(s.settingName, () => TextEditingController(text: s.annotation));
        _annotationControllers[s.settingName]!.text = s.annotation;
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

  Future<void> _refreshDefectsOnly() async {
    final junctionId = _inspectionRwaId;
    if (junctionId == null) return;
    try {
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

      if (mounted) {
        setState(() {
          _defectCountBySetting = counts;
          _totalDefects = errors.length;
        });
      }
    } catch (_) {}
  }

  Future<void> _updateSettingResult(int index, String newResult) async {
    if (widget.isReadOnly) return;
    final current = _settings[index];
    final updated = current.copyWith(
      result: newResult,
      rawResult: newResult == 'OK'
          ? 'I.O'
          : newResult == 'DEFECT'
              ? 'Mangel'
              : 'N.V.',
    );

    setState(() {
      _settings[index] = updated;
    });

    final junctionId = _inspectionRwaId;
    if (junctionId != null) {
      if (widget.isManagerMode) {
        await DatabaseService.saveRwaInspectionSettings(junctionId, _settings);
      } else {
        await LocalDatabaseService.saveRwaInspectionSettings(junctionId, _settings);
      }
    }

    // If marked as DEFECT, directly prompt to add an error if none exists yet
    if (newResult == 'DEFECT') {
      _openDefectManagement(current.settingName);
    }
  }

  Future<void> _saveAll() async {
    final junctionId = _inspectionRwaId;
    if (widget.isReadOnly || junctionId == null) return;
    setState(() => _isSaving = true);
    try {
      // 1. Save Inspection metadata
      final dateStr = DateFormat('yyyy-MM-dd').format(_inspectionDate);
      final inspectionData = <String, dynamic>{
        'inspectionId': widget.inspectionId,
        'clientName': _customerNameCtrl.text.trim(),
        'objectAddress': _customerAddressCtrl.text.trim(),
        'contactPerson': _contactPersonCtrl.text.trim(),
        'jobNumber': _jobNumberCtrl.text.trim(),
        'projectNumber': _projectNumberCtrl.text.trim(),
        'inspectorName': _inspectorNameCtrl.text.trim(),
        'date': dateStr,
      };

      if (widget.isManagerMode) {
        await DatabaseService.updateInspection(inspectionData);
      } else {
        await LocalDatabaseService.updateInspection(inspectionData);
      }

      // 2. Save Einrichtung settings
      final updatedSettings = <RwaInspectionSetting>[];
      bool hasDefects = false;

      for (final s in _settings) {
        final ann = _annotationControllers[s.settingName]?.text.trim() ?? '';
        final res = s.result;
        if (res == 'DEFECT') hasDefects = true;
        updatedSettings.add(s.copyWith(annotation: ann));
      }

      if (widget.isManagerMode) {
        await DatabaseService.saveRwaInspectionSettings(junctionId, updatedSettings);
      } else {
        await LocalDatabaseService.saveRwaInspectionSettings(junctionId, updatedSettings);
      }

      // 3. Save RWA-System properties & dropdown values
      if (_rwaSystem != null) {
        final updatedRwa = _rwaSystem!.copyWith(
          systemAlias: _aliasCtrl.text.trim(),
          objectAddress: _customerAddressCtrl.text.trim().isNotEmpty
              ? _customerAddressCtrl.text.trim()
              : _rwaSystem!.objectAddress,
          building: _buildingCtrl.text.trim(),
          floor: _floorCtrl.text.trim(),
          room: _roomCtrl.text.trim(),
          systemType: _systemType,
          centralType: _centralType,
          fireButtonSpec: _fireButtonSpec,
          smokeDetectorSpec: _smokeDetectorSpec,
          actuatorSpec: _actuatorSpec,
          ventilationButtonSpec: _ventilationButtonSpec,
          emergencyPowerSpec: _emergencyPowerSpec,
          co2BottleSpec: _co2BottleSpec,
          thermalBottleSpec: _thermalBottleSpec,
          rwaFlapSpec: _rwaFlapSpec,
          ventilationFlapSpec: _ventilationFlapSpec,
          damperSpec: _damperSpec,
          notes: _systemNotesCtrl.text.trim(),
          systemFunctionOK: !hasDefects && _totalDefects == 0,
        );

        if (widget.isManagerMode) {
          await DatabaseService.updateRwaSystem(updatedRwa);
          await DatabaseService.updateInspectionRwaStatus(
            inspectionId: widget.inspectionId,
            rwaSystemId: widget.rwaSystemId,
            status: (!hasDefects && _totalDefects == 0) ? 'Completed' : 'Defects',
            notes: _systemNotesCtrl.text.trim(),
          );
        } else {
          await LocalDatabaseService.updateRwaSystem(updatedRwa);
          await LocalDatabaseService.updateInspectionRwaStatus(
            inspectionId: widget.inspectionId,
            rwaSystemId: widget.rwaSystemId,
            status: (!hasDefects && _totalDefects == 0) ? 'Completed' : 'Defects',
            notes: _systemNotesCtrl.text.trim(),
          );
        }
        _rwaSystem = updatedRwa;
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
    final junctionId = _inspectionRwaId;
    if (junctionId == null) return;
    final sysId = _rwaSystem?.id ?? widget.rwaSystemId;
    final sysAlias = _rwaSystem?.displayAlias ?? _aliasCtrl.text;

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RwaErrorManagementPage(
          rwaSystemId: sysId,
          systemAlias: sysAlias,
          inspectionId: widget.inspectionId,
          inspectionRwaId: junctionId,
          initialSettingName: settingName,
          isManagerMode: widget.isManagerMode,
          isReadOnly: widget.isReadOnly,
        ),
      ),
    );
    if (changed == true) {
      await _refreshDefectsOnly();
    }
  }

  Future<void> _scanBarcode() async {
    final scanned = await BarcodeScannerDialog.show(
      context,
      title: 'RWA-Barcode scannen',
    );
    if (scanned != null && scanned.trim().isNotEmpty) {
      setState(() {
        _aliasCtrl.text = scanned.trim();
      });
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
          MasterPortalHomeButton(isManagerMode: widget.isManagerMode),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Action buttons (Top) - exactly like Door & Window inspection page
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _canSave ? _saveAll : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canSave ? Colors.orange : Colors.grey.shade400,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(widget.isReadOnly ? 'Schreibgeschützt' : 'Speichern'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _openDefectManagement(''),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.report_problem_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(_totalDefects > 0 ? 'Mängel ($_totalDefects)' : 'Fehler verwalten'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              if (_totalDefects > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    border: Border.all(color: Colors.amber.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Es wurden $_totalDefects Mängel an dieser RWA-Anlage dokumentiert. Details siehe "Fehler verwalten".',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // ── 1. INSPEKTIONSDATEN ─────────────────────────────────────────
              const Text(
                'Inspektionsdaten',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _customerNameCtrl,
                enabled: widget.isManagerMode && !widget.isReadOnly,
                decoration: InputDecoration(
                  labelText: 'Kundenname',
                  helperText: !widget.isManagerMode ? 'Schreibgeschützt für Inspektor' : null,
                ),
              ),

              TextField(
                controller: _customerAddressCtrl,
                enabled: widget.isManagerMode && !widget.isReadOnly,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Kundenadresse / Objektadresse',
                  helperText: !widget.isManagerMode ? 'Schreibgeschützt für Inspektor' : null,
                ),
              ),

              TextField(
                controller: _contactPersonCtrl,
                enabled: widget.isManagerMode && !widget.isReadOnly,
                decoration: InputDecoration(
                  labelText: 'Ansprechpartner',
                  helperText: !widget.isManagerMode ? 'Schreibgeschützt für Inspektor' : null,
                ),
              ),

              TextField(
                controller: _jobNumberCtrl,
                enabled: widget.isManagerMode && !widget.isReadOnly,
                decoration: InputDecoration(
                  labelText: 'Auftragsnummer',
                  helperText: !widget.isManagerMode ? 'Schreibgeschützt für Inspektor' : null,
                ),
              ),

              TextField(
                controller: _projectNumberCtrl,
                enabled: widget.isManagerMode && !widget.isReadOnly,
                decoration: InputDecoration(
                  labelText: 'Projektnummer',
                  helperText: !widget.isManagerMode ? 'Schreibgeschützt für Inspektor' : null,
                ),
              ),

              TextField(
                controller: _inspectorNameCtrl,
                enabled: widget.isManagerMode && !widget.isReadOnly,
                decoration: InputDecoration(
                  labelText: 'Inspektor',
                  helperText: !widget.isManagerMode ? 'Schreibgeschützt für Inspektor' : null,
                ),
              ),

              ListTile(
                title: Text(
                  'Inspektionsdatum: ${DateFormat('dd.MM.yyyy').format(_inspectionDate)}',
                ),
                subtitle: !widget.isManagerMode
                    ? const Text('Schreibgeschützt für Inspektor', style: TextStyle(fontSize: 12, color: Colors.grey))
                    : null,
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: (widget.isManagerMode && !widget.isReadOnly)
                      ? () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _inspectionDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => _inspectionDate = picked);
                          }
                        }
                      : null,
                ),
              ),

              const SizedBox(height: 20),

              // ── 2. RWA-SYSTEM ───────────────────────────────────────────────
              const Text(
                'RWA-System',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              // Barcode / Alias
              TextField(
                controller: _aliasCtrl,
                enabled: !widget.isReadOnly,
                decoration: InputDecoration(
                  labelText: 'Anlagen-Alias / Barcode',
                  helperText: 'Physischer Barcode / Kennzeichnung der RWA-Anlage',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner, color: Colors.deepPurple),
                    tooltip: 'Barcode / QR-Code scannen',
                    onPressed: _scanBarcode,
                  ),
                ),
              ),

              TextField(
                controller: _buildingCtrl,
                enabled: !widget.isReadOnly,
                decoration: const InputDecoration(labelText: 'Gebäude'),
              ),

              TextField(
                controller: _floorCtrl,
                enabled: !widget.isReadOnly,
                decoration: const InputDecoration(labelText: 'Geschoss'),
              ),

              TextField(
                controller: _roomCtrl,
                enabled: !widget.isReadOnly,
                decoration: const InputDecoration(labelText: 'Raum / Bereich'),
              ),

              const SizedBox(height: 12),

              // Dropdown specifications collected across all Excel files
              EditableDropdownField(
                label: 'RWA-Systemtyp',
                currentValue: _systemType,
                options: RwaOptionsService.getOptions('systemType'),
                onChanged: !widget.isReadOnly
                    ? (val) {
                        setState(() => _systemType = val);
                        RwaOptionsService.addCustomOption('systemType', val);
                      }
                    : (_) {},
              ),

              EditableDropdownField(
                label: 'Zentrale Fabrikat / Typ',
                currentValue: _centralType,
                options: RwaOptionsService.getOptions('centralType'),
                onChanged: !widget.isReadOnly
                    ? (val) {
                        setState(() => _centralType = val);
                        RwaOptionsService.addCustomOption('centralType', val);
                      }
                    : (_) {},
              ),

              EditableDropdownField(
                label: 'Feuertaster / Handauslöser',
                currentValue: _fireButtonSpec,
                options: RwaOptionsService.getOptions('fireButton'),
                onChanged: !widget.isReadOnly
                    ? (val) {
                        setState(() => _fireButtonSpec = val);
                        RwaOptionsService.addCustomOption('fireButton', val);
                      }
                    : (_) {},
              ),

              EditableDropdownField(
                label: 'Rauch- und Wärmemelder',
                currentValue: _smokeDetectorSpec,
                options: RwaOptionsService.getOptions('smokeDetector'),
                onChanged: !widget.isReadOnly
                    ? (val) {
                        setState(() => _smokeDetectorSpec = val);
                        RwaOptionsService.addCustomOption('smokeDetector', val);
                      }
                    : (_) {},
              ),

              EditableDropdownField(
                label: 'Antriebe / Öffneraggregate',
                currentValue: _actuatorSpec,
                options: RwaOptionsService.getOptions('actuator'),
                onChanged: !widget.isReadOnly
                    ? (val) {
                        setState(() => _actuatorSpec = val);
                        RwaOptionsService.addCustomOption('actuator', val);
                      }
                    : (_) {},
              ),

              EditableDropdownField(
                label: 'Lüftungstaster',
                currentValue: _ventilationButtonSpec,
                options: RwaOptionsService.getOptions('ventilationButton'),
                onChanged: !widget.isReadOnly
                    ? (val) {
                        setState(() => _ventilationButtonSpec = val);
                        RwaOptionsService.addCustomOption('ventilationButton', val);
                      }
                    : (_) {},
              ),

              EditableDropdownField(
                label: 'Notstromversorgung / Akkus',
                currentValue: _emergencyPowerSpec,
                options: RwaOptionsService.getOptions('emergencyPower'),
                onChanged: !widget.isReadOnly
                    ? (val) {
                        setState(() => _emergencyPowerSpec = val);
                        RwaOptionsService.addCustomOption('emergencyPower', val);
                      }
                    : (_) {},
              ),

              EditableDropdownField(
                label: 'CO2-Flaschen',
                currentValue: _co2BottleSpec,
                options: RwaOptionsService.getOptions('co2Bottles'),
                onChanged: !widget.isReadOnly
                    ? (val) {
                        setState(() => _co2BottleSpec = val);
                        RwaOptionsService.addCustomOption('co2Bottles', val);
                      }
                    : (_) {},
              ),

              EditableDropdownField(
                label: 'Thermische Auslöser',
                currentValue: _thermalBottleSpec,
                options: RwaOptionsService.getOptions('thermalBottle'),
                onChanged: !widget.isReadOnly
                    ? (val) {
                        setState(() => _thermalBottleSpec = val);
                        RwaOptionsService.addCustomOption('thermalBottle', val);
                      }
                    : (_) {},
              ),

              EditableDropdownField(
                label: 'RWA-Klappen / Lamellen',
                currentValue: _rwaFlapSpec,
                options: RwaOptionsService.getOptions('rwaFlaps'),
                onChanged: !widget.isReadOnly
                    ? (val) {
                        setState(() => _rwaFlapSpec = val);
                        RwaOptionsService.addCustomOption('rwaFlaps', val);
                      }
                    : (_) {},
              ),

              EditableDropdownField(
                label: 'Zuluft / Zuluftflügel',
                currentValue: _ventilationFlapSpec,
                options: RwaOptionsService.getOptions('ventilationFlaps'),
                onChanged: !widget.isReadOnly
                    ? (val) {
                        setState(() => _ventilationFlapSpec = val);
                        RwaOptionsService.addCustomOption('ventilationFlaps', val);
                      }
                    : (_) {},
              ),

              EditableDropdownField(
                label: 'Zuluftklappen / Nachströmung',
                currentValue: _damperSpec,
                options: RwaOptionsService.getOptions('dampers'),
                onChanged: !widget.isReadOnly
                    ? (val) {
                        setState(() => _damperSpec = val);
                        RwaOptionsService.addCustomOption('dampers', val);
                      }
                    : (_) {},
              ),

              const SizedBox(height: 12),

              TextField(
                controller: _systemNotesCtrl,
                enabled: !widget.isReadOnly,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Allgemeine Bemerkungen zur RWA-Anlage',
                  hintText: 'Freie Notizen zur Anlage, Standortbesonderheiten...',
                ),
              ),

              const SizedBox(height: 20),

              // ── 3. EINRICHTUNG ──────────────────────────────────────────────
              const Text(
                'Einrichtung',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '12 Komponenten der Funktionsprüfung:',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),

              ..._settings.asMap().entries.map((entry) => _buildSettingItem(entry.value, entry.key)),

              const SizedBox(height: 16),

              // Bottom Save button for easy access after scrolling
              if (!widget.isReadOnly) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Text('Speichern & Übernehmen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _saveAll,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingItem(RwaInspectionSetting setting, int index) {
    final defectCount = _defectCountBySetting[setting.settingName] ?? 0;
    final isDefect = setting.result == 'DEFECT' || defectCount > 0;
    final isOk = setting.result == 'OK' && defectCount == 0;
    final isNotPresent = setting.result == 'NOT_PRESENT';

    final controller = _annotationControllers.putIfAbsent(
      setting.settingName,
      () => TextEditingController(text: setting.annotation),
    );

    Color itemBorderColor = Colors.grey.shade300;
    Color itemBgColor = Colors.white;
    if (isDefect) {
      itemBorderColor = Colors.red.shade400;
      itemBgColor = Colors.red.shade50.withValues(alpha: 0.3);
    } else if (isOk) {
      itemBorderColor = Colors.green.shade400;
      itemBgColor = Colors.green.shade50.withValues(alpha: 0.2);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: itemBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: itemBorderColor, width: isDefect ? 1.5 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  setting.settingName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              _buildSegmentButton('i.O.', 'OK', isOk, Colors.green, () => _updateSettingResult(index, 'OK')),
              const SizedBox(width: 6),
              _buildSegmentButton('Mangel', 'DEFECT', isDefect, Colors.red, () => _updateSettingResult(index, 'DEFECT')),
              const SizedBox(width: 6),
              _buildSegmentButton('N.V.', 'NOT_PRESENT', isNotPresent, Colors.grey, () => _updateSettingResult(index, 'NOT_PRESENT')),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
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
