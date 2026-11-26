import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../services/rwa_options_service.dart';
import '../widgets/editable_dropdown_field.dart';

class NewRwaPage extends StatefulWidget {
  final RwaSystem? rwaSystem;
  final int inspectionId;
  final bool isManagerMode;
  final bool isReadOnly;

  const NewRwaPage({
    super.key,
    this.rwaSystem,
    required this.inspectionId,
    this.isManagerMode = false,
    this.isReadOnly = false,
  });

  @override
  State<NewRwaPage> createState() => _NewRwaPageState();
}

class _NewRwaPageState extends State<NewRwaPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _aliasCtrl;
  late TextEditingController _objectAddressCtrl;
  late TextEditingController _buildingCtrl;
  late TextEditingController _floorCtrl;
  late TextEditingController _roomCtrl;
  late TextEditingController _notesCtrl;

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

  bool _isLoading = true;
  String _projectNumber = '';

  @override
  void initState() {
    super.initState();
    _initFields();
  }

  Future<void> _initFields() async {
    final existing = widget.rwaSystem;

    // Load inspection projectNumber if creating new
    if (existing == null) {
      if (widget.isManagerMode) {
        final insp = await DatabaseService.getInspectionById(widget.inspectionId);
        _projectNumber = insp?['projectNumber'] ?? '';
      } else {
        final insp = await LocalDatabaseService.getInspectionById(widget.inspectionId);
        _projectNumber = insp?['projectNumber'] ?? '';
      }
    } else {
      _projectNumber = existing.projectNumber;
    }

    _aliasCtrl = TextEditingController(text: existing?.systemAlias ?? '');
    _objectAddressCtrl = TextEditingController(text: existing?.objectAddress ?? '');
    _buildingCtrl = TextEditingController(text: existing?.building ?? '');
    _floorCtrl = TextEditingController(text: existing?.floor ?? '');
    _roomCtrl = TextEditingController(text: existing?.room ?? '');
    _notesCtrl = TextEditingController(text: existing?.notes ?? '');

    _systemType = existing?.systemType ?? RwaOptionsService.getDefault('systemType');
    _centralType = existing?.centralType ?? RwaOptionsService.getDefault('centralType');
    _fireButtonSpec = existing?.fireButtonSpec ?? RwaOptionsService.getDefault('fireButton');
    _smokeDetectorSpec = existing?.smokeDetectorSpec ?? RwaOptionsService.getDefault('smokeDetector');
    _actuatorSpec = existing?.actuatorSpec ?? RwaOptionsService.getDefault('actuator');
    _ventilationButtonSpec = existing?.ventilationButtonSpec ?? RwaOptionsService.getDefault('ventilationButton');
    _emergencyPowerSpec = existing?.emergencyPowerSpec ?? RwaOptionsService.getDefault('emergencyPower');
    _co2BottleSpec = existing?.co2BottleSpec ?? RwaOptionsService.getDefault('co2Bottles');
    _thermalBottleSpec = existing?.thermalBottleSpec ?? RwaOptionsService.getDefault('thermalBottle');
    _rwaFlapSpec = existing?.rwaFlapSpec ?? RwaOptionsService.getDefault('rwaFlaps');
    _ventilationFlapSpec = existing?.ventilationFlapSpec ?? RwaOptionsService.getDefault('ventilationFlaps');
    _damperSpec = existing?.damperSpec ?? RwaOptionsService.getDefault('dampers');

    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _objectAddressCtrl.dispose();
    _buildingCtrl.dispose();
    _floorCtrl.dispose();
    _roomCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final alias = _aliasCtrl.text.trim();
    final address = _objectAddressCtrl.text.trim();
    final building = _buildingCtrl.text.trim();
    final floor = _floorCtrl.text.trim();
    final room = _roomCtrl.text.trim();
    final notes = _notesCtrl.text.trim();

    final rwa = RwaSystem(
      id: widget.rwaSystem?.id,
      projectNumber: _projectNumber.isNotEmpty ? _projectNumber : 'P-RWA',
      systemAlias: alias.isNotEmpty ? alias : null,
      systemType: _systemType.isNotEmpty ? _systemType : 'elektromotorisch',
      objectAddress: address,
      building: building,
      floor: floor,
      room: room,
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
      systemFunctionOK: widget.rwaSystem?.systemFunctionOK ?? true,
      notes: notes,
    );

    int rwaId;
    if (widget.rwaSystem == null) {
      if (widget.isManagerMode) {
        rwaId = await DatabaseService.insertRwaSystem(rwa);
        await DatabaseService.insertInspectionRwa(InspectionRwa(
          inspectionId: widget.inspectionId,
          rwaSystemId: rwaId,
          status: 'InProgress',
          notes: '',
        ).toMap());
      } else {
        rwaId = await LocalDatabaseService.insertRwaSystem(rwa);
        await LocalDatabaseService.insertInspectionRwa(InspectionRwa(
          inspectionId: widget.inspectionId,
          rwaSystemId: rwaId,
          status: 'InProgress',
          notes: '',
        ).toMap());
      }
    } else {
      rwaId = widget.rwaSystem!.id!;
      if (widget.isManagerMode) {
        await DatabaseService.updateRwaSystem(rwa);
      } else {
        await LocalDatabaseService.updateRwaSystem(rwa);
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RWA-Anlage erfolgreich gespeichert!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rwaSystem == null ? 'Neue RWA-Anlage' : 'RWA-Stammdaten bearbeiten'),
        actions: [
          if (!widget.isReadOnly)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _save,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // General Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Standort & Identifikation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _aliasCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Anlagen-Alias / Bezeichnung (z.B. Treppenhaus Ost)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _objectAddressCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Objektadresse',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _buildingCtrl,
                            decoration: const InputDecoration(labelText: 'Gebäude', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _floorCtrl,
                            decoration: const InputDecoration(labelText: 'Geschoss', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _roomCtrl,
                            decoration: const InputDecoration(labelText: 'Raum', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // System Properties Card (Dropdowns with new input)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Anlageneigenschaften & Komponenten', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),

                    EditableDropdownField(
                      label: 'RWA-Systemtyp',
                      currentValue: _systemType,
                      options: RwaOptionsService.getOptions('systemType'),
                      onChanged: (val) {
                        setState(() => _systemType = val);
                        RwaOptionsService.addCustomOption('systemType', val);
                      },
                    ),
                    const SizedBox(height: 12),

                    EditableDropdownField(
                      label: 'Zentrale Fabrikat / Typ',
                      currentValue: _centralType,
                      options: RwaOptionsService.getOptions('centralType'),
                      onChanged: (val) {
                        setState(() => _centralType = val);
                        RwaOptionsService.addCustomOption('centralType', val);
                      },
                    ),
                    const SizedBox(height: 12),

                    EditableDropdownField(
                      label: 'Feuertaster',
                      currentValue: _fireButtonSpec,
                      options: RwaOptionsService.getOptions('fireButton'),
                      onChanged: (val) {
                        setState(() => _fireButtonSpec = val);
                        RwaOptionsService.addCustomOption('fireButton', val);
                      },
                    ),
                    const SizedBox(height: 12),

                    EditableDropdownField(
                      label: 'Rauch-/Wärmemelder',
                      currentValue: _smokeDetectorSpec,
                      options: RwaOptionsService.getOptions('smokeDetector'),
                      onChanged: (val) {
                        setState(() => _smokeDetectorSpec = val);
                        RwaOptionsService.addCustomOption('smokeDetector', val);
                      },
                    ),
                    const SizedBox(height: 12),

                    EditableDropdownField(
                      label: 'Antriebe',
                      currentValue: _actuatorSpec,
                      options: RwaOptionsService.getOptions('actuator'),
                      onChanged: (val) {
                        setState(() => _actuatorSpec = val);
                        RwaOptionsService.addCustomOption('actuator', val);
                      },
                    ),
                    const SizedBox(height: 12),

                    EditableDropdownField(
                      label: 'Lüftungstaster',
                      currentValue: _ventilationButtonSpec,
                      options: RwaOptionsService.getOptions('ventilationButton'),
                      onChanged: (val) {
                        setState(() => _ventilationButtonSpec = val);
                        RwaOptionsService.addCustomOption('ventilationButton', val);
                      },
                    ),
                    const SizedBox(height: 12),

                    EditableDropdownField(
                      label: 'Notstrombatterie',
                      currentValue: _emergencyPowerSpec,
                      options: RwaOptionsService.getOptions('emergencyPower'),
                      onChanged: (val) {
                        setState(() => _emergencyPowerSpec = val);
                        RwaOptionsService.addCustomOption('emergencyPower', val);
                      },
                    ),
                    const SizedBox(height: 12),

                    EditableDropdownField(
                      label: 'CO2-Flaschen',
                      currentValue: _co2BottleSpec,
                      options: RwaOptionsService.getOptions('co2Bottles'),
                      onChanged: (val) {
                        setState(() => _co2BottleSpec = val);
                        RwaOptionsService.addCustomOption('co2Bottles', val);
                      },
                    ),
                    const SizedBox(height: 12),

                    EditableDropdownField(
                      label: 'Thermoflasche',
                      currentValue: _thermalBottleSpec,
                      options: RwaOptionsService.getOptions('thermalBottle'),
                      onChanged: (val) {
                        setState(() => _thermalBottleSpec = val);
                        RwaOptionsService.addCustomOption('thermalBottle', val);
                      },
                    ),
                    const SizedBox(height: 12),

                    EditableDropdownField(
                      label: 'RWA-Klappen',
                      currentValue: _rwaFlapSpec,
                      options: RwaOptionsService.getOptions('rwaFlaps'),
                      onChanged: (val) {
                        setState(() => _rwaFlapSpec = val);
                        RwaOptionsService.addCustomOption('rwaFlaps', val);
                      },
                    ),
                    const SizedBox(height: 12),

                    EditableDropdownField(
                      label: 'Lüftungsklappen',
                      currentValue: _ventilationFlapSpec,
                      options: RwaOptionsService.getOptions('ventilationFlaps'),
                      onChanged: (val) {
                        setState(() => _ventilationFlapSpec = val);
                        RwaOptionsService.addCustomOption('ventilationFlaps', val);
                      },
                    ),
                    const SizedBox(height: 12),

                    EditableDropdownField(
                      label: 'Dämpfer',
                      currentValue: _damperSpec,
                      options: RwaOptionsService.getOptions('dampers'),
                      onChanged: (val) {
                        setState(() => _damperSpec = val);
                        RwaOptionsService.addCustomOption('dampers', val);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Notes
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextFormField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Allgemeine Notizen / Bemerkungen',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
