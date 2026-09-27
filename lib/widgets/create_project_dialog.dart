import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';

/// Dialog enabling the Manager to create a new Project/Building Anchor with
/// pre-filled building metadata and a 0-door empty template for inspectors.
class CreateProjectDialog extends StatefulWidget {
  const CreateProjectDialog({super.key});

  /// Static helper to display the dialog easily and return boolean success
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => const CreateProjectDialog(),
    );
  }

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _projectNumberController = TextEditingController();
  final _objectAddressController = TextEditingController();
  final _clientNameController = TextEditingController();
  final _jobNumberController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _inspectorNameController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _exportImmediately = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _projectNumberController.dispose();
    _objectAddressController.dispose();
    _clientNameController.dispose();
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

  Future<void> _saveAndCreate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final inspectionData = {
        'projectNumber': _projectNumberController.text.trim(),
        'objectAddress': _objectAddressController.text.trim(),
        'clientName': _clientNameController.text.trim(),
        'jobNumber': _jobNumberController.text.trim(),
        'date': _selectedDate.toIso8601String(),
        'contactPerson': _contactPersonController.text.trim(),
        'inspectorName': _inspectorNameController.text.trim(),
        'isLocked': 0,
      };

      final int inspectionId = await DatabaseService.insertInspection(inspectionData);

      String? exportPath;
      if (_exportImmediately) {
        exportPath = await DatabaseService.exportJobPackage([inspectionId]);
      }

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              exportPath != null
                  ? 'Neues Projekt angelegt & Vorlage exportiert:\n$exportPath'
                  : 'Neues Projekt & Leervorlage erfolgreich angelegt.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Anlegen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy');

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.domain_add, color: Colors.blueAccent, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Neues Projekt / Gebäude anlegen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  'Erstellt eine leere Prüfvorlage (0 Türen) für den Inspektor',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 550,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                // 1. Project Number (Building Anchor)
                TextFormField(
                  controller: _projectNumberController,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: const InputDecoration(
                    labelText: 'Projektnummer (Gebäude-Anker) *',
                    hintText: 'z.B. P-MUC-101 oder 26-14332',
                    prefixIcon: Icon(Icons.folder_special, color: Colors.blueAccent),
                    border: OutlineInputBorder(),
                    helperText: 'Dient als fester Anker für die physische Gebäudeinfrastruktur & Tür-Aliase',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Bitte Projektnummer eingeben' : null,
                ),
                const SizedBox(height: 14),

                // 2. Object Address (Building physical address)
                TextFormField(
                  controller: _objectAddressController,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: const InputDecoration(
                    labelText: 'Objektadresse / Liegenschaft *',
                    hintText: 'z.B. Musterstraße 42, 80331 München',
                    prefixIcon: Icon(Icons.location_on, color: Colors.redAccent),
                    border: OutlineInputBorder(),
                    helperText: 'Physische Adresse des Gebäudes',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Bitte Objektadresse eingeben' : null,
                ),
                const SizedBox(height: 14),

                // 3. Customer / Client Name
                TextFormField(
                  controller: _clientNameController,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: const InputDecoration(
                    labelText: 'Kunde / Auftraggeber *',
                    hintText: 'z.B. Konz & Schäfer GmbH',
                    prefixIcon: Icon(Icons.business),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Bitte Kunden eingeben' : null,
                ),
                const SizedBox(height: 14),

                // 4. Job Number
                TextFormField(
                  controller: _jobNumberController,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: const InputDecoration(
                    labelText: 'Auftragsnummer *',
                    hintText: 'z.B. AUFTRAG-2026-01',
                    prefixIcon: Icon(Icons.confirmation_number),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Bitte Auftragsnummer eingeben' : null,
                ),
                const SizedBox(height: 14),

                // 5. Date
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
                const SizedBox(height: 14),

                // 6. Contact Person
                TextFormField(
                  controller: _contactPersonController,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: const InputDecoration(
                    labelText: 'Ansprechpartner vor Ort (optional)',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),

                // 7. Inspector Name
                TextFormField(
                  controller: _inspectorNameController,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: const InputDecoration(
                    labelText: 'Prüfer Name (optional)',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Export Package Option
                CheckboxListTile(
                  value: _exportImmediately,
                  onChanged: (val) => setState(() => _exportImmediately = val ?? false),
                  title: const Text(
                    'Direkt als Techniker-Paket (.db) exportieren',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Erstellt sofort eine importierbare SQLite-Datei für das Techniker-Tablet.',
                    style: TextStyle(fontSize: 11),
                  ),
                  secondary: const Icon(Icons.send_to_mobile, color: Colors.blueAccent),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveAndCreate,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_circle_outline),
          label: Text(_exportImmediately ? 'Anlegen & Exportieren' : 'Vorlage anlegen'),
        ),
      ],
    );
  }
}
