import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';

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
  late TextEditingController _contactPersonController;
  late TextEditingController _inspectorNameController;
  late DateTime _selectedDate;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _clientNameController = TextEditingController();
    _objectAddressController = TextEditingController();
    _jobNumberController = TextEditingController();
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
    _contactPersonController.text = data['contactPerson']?.toString() ?? '';
    _inspectorNameController.text = data['inspectorName']?.toString() ?? '';
    
    final dateStr = data['date']?.toString();
    if (dateStr != null && dateStr.isNotEmpty) {
      try {
        _selectedDate = DateTime.parse(dateStr);
      } catch (_) {
        _selectedDate = DateTime.now();
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final updatedData = {
        'inspectionId': widget.inspectionId,
        'clientName': _clientNameController.text.trim(),
        'objectAddress': _objectAddressController.text.trim(),
        'jobNumber': _jobNumberController.text.trim(),
        'date': _selectedDate.toIso8601String(),
        'contactPerson': _contactPersonController.text.trim(),
        'inspectorName': _inspectorNameController.text.trim(),
      };

      if (widget.isManagerMode) {
        await DatabaseService.updateInspection(updatedData);
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
      title: const Row(
        children: [
          Icon(Icons.edit_note, color: Colors.blue),
          SizedBox(width: 8),
          Text('Auftrags-Metadaten bearbeiten'),
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
                  children: [
                    TextFormField(
                      controller: _clientNameController,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: const InputDecoration(
                        labelText: 'Kunde / Aufraggeber',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'Bitte Kunden eingeben' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _objectAddressController,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: const InputDecoration(
                        labelText: 'Objektadresse / Projekt',
                        prefixIcon: Icon(Icons.location_on),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _jobNumberController,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: const InputDecoration(
                        labelText: 'Auftragsnummer',
                        prefixIcon: Icon(Icons.confirmation_number),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'Bitte Auftragsnummer eingeben' : null,
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Prüfdatum',
                          prefixIcon: Icon(Icons.calendar_today),
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
                      decoration: const InputDecoration(
                        labelText: 'Prüfer Name',
                        prefixIcon: Icon(Icons.badge),
                        border: OutlineInputBorder(),
                      ),
                    ),
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
