import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../utils/inspection_year_utils.dart';

/// Dialog that allows a manager or user to change all metadata 
/// of a single inspection at once.
class EditInspectionDialog extends StatefulWidget {
  final int inspectionId;
  final Map<String, dynamic>? initialData;
  final bool isManagerMode;

  const EditInspectionDialog({
    super.key,
    required this.inspectionId,
    this.initialData,
    this.isManagerMode = true,
  });

  /// Static helper to display the dialog easily and return boolean success
  static Future<bool?> show(
    BuildContext context, {
    required int inspectionId,
    Map<String, dynamic>? initialData,
    bool isManagerMode = true,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => EditInspectionDialog(
        inspectionId: inspectionId,
        initialData: initialData,
        isManagerMode: isManagerMode,
      ),
    );
  }

  @override
  State<EditInspectionDialog> createState() => _EditInspectionDialogState();
}

class _EditInspectionDialogState extends State<EditInspectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _clientNameController;
  late TextEditingController _objectAddressController;
  late TextEditingController _jobNumberController;
  late TextEditingController _projectNumberController;
  late TextEditingController _contactPersonController;
  late TextEditingController _inspectorNameController;
  late DateTime _selectedDate;
  DateTime? _selectedRepairDate;
  String _orderType = 'Wartung';
  bool _isLocked = false;
  bool _syncBuildingData = true;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _clientNameController = TextEditingController();
    _objectAddressController = TextEditingController();
    _jobNumberController = TextEditingController();
    _projectNumberController = TextEditingController();
    _contactPersonController = TextEditingController();
    _inspectorNameController = TextEditingController();
    _selectedDate = DateTime.now();

    if (widget.initialData != null) {
      _populateFromMap(widget.initialData!);
      _isLoading = false;
    } else {
      _loadData();
    }
  }

  void _populateFromMap(Map<String, dynamic> data) {
    _clientNameController.text = data['clientName']?.toString() ?? '';
    _objectAddressController.text = data['objectAddress']?.toString() ?? '';
    _jobNumberController.text = data['jobNumber']?.toString() ?? '';
    _projectNumberController.text = data['projectNumber']?.toString() ?? '';
    _contactPersonController.text = data['contactPerson']?.toString() ?? '';
    _inspectorNameController.text = data['inspectorName']?.toString() ?? '';
    _isLocked = InspectionYearUtils.isInspectionLocked(data['isLocked']);
    _orderType = data['orderType']?.toString() ?? 'Wartung';
    
    final dateStr = data['date']?.toString();
    if (dateStr != null && dateStr.isNotEmpty) {
      try {
        _selectedDate = DateTime.parse(dateStr);
      } catch (_) {
        _selectedDate = DateTime.now();
      }
    }

    final repDateStr = data['repairDate']?.toString();
    if (repDateStr != null && repDateStr.isNotEmpty) {
      try {
        _selectedRepairDate = DateTime.parse(repDateStr);
      } catch (_) {
        _selectedRepairDate = null;
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final Map<String, dynamic>? data = widget.isManagerMode
        ? await DatabaseService.getInspectionById(widget.inspectionId)
        : await LocalDatabaseService.getInspectionById(widget.inspectionId);

    if (mounted && data != null) {
      _populateFromMap(data);
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _objectAddressController.dispose();
    _jobNumberController.dispose();
    _projectNumberController.dispose();
    _contactPersonController.dispose();
    _inspectorNameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickRepairDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedRepairDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedRepairDate = picked;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final bool canEdit = InspectionYearUtils.isEditable(
      isManagerMode: widget.isManagerMode,
      dateValue: _selectedDate,
    );
    if (!canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vorjahres-Aufträge können vom Inspektor nicht bearbeitet werden.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updatedData = {
        'inspectionId': widget.inspectionId,
        'clientName': _clientNameController.text.trim(),
        'objectAddress': _objectAddressController.text.trim(),
        'jobNumber': _jobNumberController.text.trim(),
        'projectNumber': _projectNumberController.text.trim(),
        'orderType': _orderType,
        'repairDate': (_orderType == 'Reparatur' || _orderType == 'Erledigt') && _selectedRepairDate != null
            ? _selectedRepairDate!.toIso8601String().substring(0, 10)
            : null,
        'date': _selectedDate.toIso8601String().substring(0, 10),
        'contactPerson': _contactPersonController.text.trim(),
        'inspectorName': _inspectorNameController.text.trim(),
        'isLocked': _isLocked ? 1 : 0,
      };

      if (widget.isManagerMode) {
        await DatabaseService.updateInspection(updatedData);
        if (_orderType == 'Erledigt') {
          await DatabaseService.consolidateJobToErledigt(
            jobNumber: _jobNumberController.text.trim(),
            projectNumber: _projectNumberController.text.trim(),
          );
        }
        if (_syncBuildingData) {
          final originalProj = widget.initialData?['projectNumber']?.toString().trim() ?? _projectNumberController.text.trim();
          if (originalProj.isNotEmpty || _projectNumberController.text.trim().isNotEmpty) {
            await DatabaseService.updateProjectBuildingData(
              currentProjectNumber: originalProj,
              newProjectNumber: _projectNumberController.text.trim(),
              newObjectAddress: _objectAddressController.text.trim(),
            );
          }
        }
      } else {
        await LocalDatabaseService.updateInspection(updatedData);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Speichern: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy');

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _orderType == 'Erledigt'
                ? Icons.task_alt
                : (_orderType == 'Reparatur' ? Icons.handyman_outlined : Icons.edit_note),
            color: _orderType == 'Erledigt'
                ? Colors.green.shade700
                : (_orderType == 'Reparatur' ? Colors.orange.shade700 : Colors.blue),
          ),
          const SizedBox(width: 8),
          const Text('Auftrags-Metadaten bearbeiten'),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 150,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isManagerMode) ...[
                      const Text('Auftrags-Typ / Phase:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: [
                          const ButtonSegment<String>(
                            value: 'Wartung',
                            icon: Icon(Icons.build_circle_outlined, color: Colors.blue),
                            label: Text('Wartung'),
                          ),
                          ButtonSegment<String>(
                            value: 'Reparatur',
                            icon: Icon(Icons.handyman_outlined, color: Colors.orange.shade800),
                            label: const Text('Reparatur'),
                          ),
                          ButtonSegment<String>(
                            value: 'Erledigt',
                            icon: Icon(Icons.task_alt, color: Colors.green.shade700),
                            label: const Text('Erledigt'),
                          ),
                        ],
                        selected: {_orderType},
                        onSelectionChanged: (val) {
                          setState(() {
                            _orderType = val.first;
                            if ((_orderType == 'Reparatur' || _orderType == 'Erledigt') && _selectedRepairDate == null) {
                              _selectedRepairDate = DateTime.now();
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _clientNameController,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: const InputDecoration(
                        labelText: 'Kunde / Auftraggeber',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'Bitte Kunden eingeben' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _objectAddressController,
                      readOnly: !widget.isManagerMode,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Objektadresse / Liegenschaft',
                        prefixIcon: const Icon(Icons.location_on),
                        border: const OutlineInputBorder(),
                        helperText: !widget.isManagerMode ? 'Liegenschaftsdaten sind fest verankert' : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _jobNumberController,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: _orderType == 'Reparatur' ? 'Reparatur-Auftragsnummer' : 'Auftragsnummer',
                        prefixIcon: const Icon(Icons.confirmation_number),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'Bitte Auftragsnummer eingeben' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _projectNumberController,
                      readOnly: !widget.isManagerMode,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Projektnummer (Gebäude-Anker)',
                        prefixIcon: const Icon(Icons.folder),
                        border: const OutlineInputBorder(),
                        helperText: !widget.isManagerMode ? 'Projektnummer wird vom Manager verwaltet' : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Date Selection: Show only Reparatur-Datum for Reparatur/Erledigt-Reparatur, only Prüfdatum for Wartung/Erledigt-Wartung
                    if (_orderType == 'Reparatur' || (_orderType == 'Erledigt' && _selectedRepairDate != null))
                      InkWell(
                        onTap: widget.isManagerMode ? _pickRepairDate : null,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Reparatur-Datum',
                            prefixIcon: Icon(Icons.build, color: _orderType == 'Erledigt' ? Colors.green.shade700 : Colors.orange.shade800),
                            border: const OutlineInputBorder(),
                          ),
                          child: Text(
                            _selectedRepairDate != null
                                ? dateFormat.format(_selectedRepairDate!)
                                : dateFormat.format(_selectedDate),
                            style: TextStyle(
                              color: _orderType == 'Erledigt' ? Colors.green.shade900 : Colors.orange.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                    else
                      InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Prüfdatum',
                            prefixIcon: Icon(Icons.calendar_today, color: Colors.blueAccent),
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            dateFormat.format(_selectedDate),
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _contactPersonController,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: const InputDecoration(
                        labelText: 'Ansprechpartner vor Ort',
                        prefixIcon: Icon(Icons.contacts),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _inspectorNameController,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: _orderType == 'Reparatur' ? 'Techniker / Reparateur' : 'Prüfer Name',
                        prefixIcon: const Icon(Icons.badge),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (widget.isManagerMode) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _syncBuildingData,
                        onChanged: (val) => setState(() => _syncBuildingData = val ?? true),
                        title: const Text('Liegenschaftsdaten für Projekt synchronisieren', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Aktualisiert Adresse & Projektnummer in allen historischen & aktuellen Aufträgen dieses Gebäudes', style: TextStyle(fontSize: 11)),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        value: _isLocked,
                        title: const Text('Auftrag gesperrt (Sperrstatus)'),
                        subtitle: Text(
                          _isLocked
                              ? 'Gesperrt: Inspektor kann Türen/Fehler nicht bearbeiten'
                              : 'Freigegeben: Inspektor kann Türen/Fehler bearbeiten',
                        ),
                        secondary: Icon(
                          _isLocked ? Icons.lock : Icons.lock_open,
                          color: _isLocked ? Colors.red : Colors.green,
                        ),
                        onChanged: (bool val) {
                          setState(() => _isLocked = val);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving || _isLoading ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save),
          label: const Text('Metadaten speichern'),
        ),
      ],
    );
  }
}
