import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';

/// Dialog enabling the Manager to create a new Project or prepare a new Auftrag
/// ("Wartung" or "Reparatur"), pre-filled with door specifications from the
/// latest inspection or as a blank template for inspectors.
class CreateProjectDialog extends StatefulWidget {
  final String? initialProjectNumber;
  final String? initialObjectAddress;
  final String? initialClientName;
  final String initialOrderType;

  const CreateProjectDialog({
    super.key,
    this.initialProjectNumber,
    this.initialObjectAddress,
    this.initialClientName,
    this.initialOrderType = 'Wartung',
  });

  /// Static helper to display the dialog easily and return boolean success
  static Future<bool?> show(
    BuildContext context, {
    String? initialProjectNumber,
    String? initialObjectAddress,
    String? initialClientName,
    String initialOrderType = 'Wartung',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => CreateProjectDialog(
        initialProjectNumber: initialProjectNumber,
        initialObjectAddress: initialObjectAddress,
        initialClientName: initialClientName,
        initialOrderType: initialOrderType,
      ),
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
  DateTime _selectedRepairDate = DateTime.now();
  String _orderType = 'Wartung'; // 'Wartung' or 'Reparatur'
  bool _clonePreviousDoors = true;
  bool _exportImmediately = true;
  bool _isSaving = false;
  List<Map<String, String>> _existingProjects = [];
  bool _hasExistingInspection = false;

  @override
  void initState() {
    super.initState();
    _projectNumberController.text = widget.initialProjectNumber ?? '';
    _objectAddressController.text = widget.initialObjectAddress ?? '';
    _clientNameController.text = widget.initialClientName ?? '';
    _orderType = widget.initialOrderType;
    _loadExistingProjects();
  }

  Future<void> _loadExistingProjects() async {
    try {
      final projects = await DatabaseService.getAllMasterProjects();
      if (mounted) {
        setState(() {
          _existingProjects = projects;
          _checkIfProjectExists();
        });
      }
    } catch (_) {}
  }

  void _checkIfProjectExists() {
    final pNum = _projectNumberController.text.trim();
    final addr = _objectAddressController.text.trim();
    final match = _existingProjects.any((p) =>
        (pNum.isNotEmpty && p['projectNumber'] == pNum) ||
        (addr.isNotEmpty && p['objectAddress'] == addr));
    setState(() {
      _hasExistingInspection = match;
      if (!match && widget.initialProjectNumber == null) {
        _clonePreviousDoors = false;
      } else if (match) {
        _clonePreviousDoors = true;
      }
    });
  }

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

  Future<void> _pickRepairDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedRepairDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _selectedRepairDate) {
      setState(() {
        _selectedRepairDate = picked;
      });
    }
  }

  Future<void> _saveAndCreate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final int inspectionId = await DatabaseService.createAuftragFromLatestInspection(
        projectNumber: _projectNumberController.text.trim(),
        objectAddress: _objectAddressController.text.trim(),
        clientName: _clientNameController.text.trim(),
        jobNumber: _jobNumberController.text.trim(),
        date: _selectedDate,
        orderType: _orderType,
        repairDate: _orderType == 'Reparatur' ? _selectedRepairDate : null,
        contactPerson: _contactPersonController.text.trim(),
        inspectorName: _inspectorNameController.text.trim(),
        cloneDoors: _clonePreviousDoors,
      );

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
                  ? 'Neuer Auftrag ($_orderType) angelegt & exportiert:\n$exportPath'
                  : 'Neuer Auftrag ($_orderType) erfolgreich angelegt.',
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
      title: Row(
        children: [
          Icon(
            _orderType == 'Reparatur' ? Icons.handyman_outlined : Icons.domain_add,
            color: _orderType == 'Reparatur' ? Colors.orange.shade700 : Colors.blueAccent,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _hasExistingInspection
                      ? 'Neuen Auftrag vorbereiten'
                      : 'Neues Projekt / Auftrag anlegen',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  _orderType == 'Reparatur'
                      ? 'Reparatur-Auftrag mit bestehenden Mängeln als Leitfaden'
                      : (_clonePreviousDoors
                          ? 'Wartung: Türen & Eigenschaften aus Vorjahr übernehmen (Mängel/Notizen leer)'
                          : 'Leervorlage (0 Türen) für den Inspektor erstellen'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Phase / Auftrags-Typ Switcher
                const Text('Auftrags-Typ / Phase:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment<String>(
                      value: 'Wartung',
                      icon: const Icon(Icons.build_circle_outlined, color: Colors.blue),
                      label: const Text('Wartung (Prüfung)'),
                    ),
                    ButtonSegment<String>(
                      value: 'Reparatur',
                      icon: Icon(Icons.handyman_outlined, color: Colors.orange.shade800),
                      label: const Text('Reparatur (Instandsetzung)'),
                    ),
                  ],
                  selected: {_orderType},
                  onSelectionChanged: (val) {
                    setState(() {
                      _orderType = val.first;
                    });
                  },
                ),
                const SizedBox(height: 14),

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
                  onChanged: (_) => _checkIfProjectExists(),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Bitte Projektnummer eingeben' : null,
                ),
                const SizedBox(height: 12),

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
                  onChanged: (_) => _checkIfProjectExists(),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Bitte Objektadresse eingeben' : null,
                ),
                const SizedBox(height: 12),

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
                const SizedBox(height: 12),

                // 4. Job Number
                TextFormField(
                  controller: _jobNumberController,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: _orderType == 'Reparatur' ? 'Reparatur-Auftragsnummer *' : 'Auftragsnummer *',
                    hintText: _orderType == 'Reparatur' ? 'z.B. REP-2026-01' : 'z.B. AUFTRAG-2026-01',
                    prefixIcon: const Icon(Icons.confirmation_number),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Bitte Auftragsnummer eingeben' : null,
                ),
                const SizedBox(height: 12),

                // 5. Dates Row
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: _orderType == 'Reparatur' ? 'Prüfdatum (Bezug)' : 'Prüfdatum',
                            prefixIcon: const Icon(Icons.calendar_today),
                            border: const OutlineInputBorder(),
                          ),
                          child: Text(
                            dateFormat.format(_selectedDate),
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ),
                      ),
                    ),
                    if (_orderType == 'Reparatur') ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: _pickRepairDate,
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Reparatur-Datum *',
                              prefixIcon: Icon(Icons.build, color: Colors.orange.shade800),
                              border: const OutlineInputBorder(),
                            ),
                            child: Text(
                              dateFormat.format(_selectedRepairDate),
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),

                // 6. Contact Person & Inspector Row
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _contactPersonController,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        decoration: const InputDecoration(
                          labelText: 'Ansprechpartner (opt.)',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _inspectorNameController,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: _orderType == 'Reparatur' ? 'Techniker / Reparateur' : 'Prüfer Name',
                          prefixIcon: const Icon(Icons.badge_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Door cloning option
                Material(
                  color: _orderType == 'Reparatur'
                      ? Colors.orange.shade50
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _orderType == 'Reparatur'
                            ? Colors.orange.shade200
                            : Colors.blue.shade200,
                      ),
                    ),
                    child: CheckboxListTile(
                      value: _clonePreviousDoors,
                      onChanged: (val) => setState(() => _clonePreviousDoors = val ?? true),
                      title: Text(
                        _orderType == 'Reparatur'
                            ? 'Türen & erfasste Mängel als Leitfaden übernehmen'
                            : 'Türen & technische Daten aus letzter Prüfung übernehmen',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: Text(
                        _orderType == 'Reparatur'
                            ? 'Kopiert alle Türen, Notizen und bestehenden Mängel für die Reparaturdurchführung.'
                            : 'Spart Zeit für den Prüfer: Alle Türeigenschaften bleiben erhalten, Notizen & Mängel starten leer.',
                        style: const TextStyle(fontSize: 11),
                      ),
                      secondary: Icon(
                        _clonePreviousDoors ? Icons.copy : Icons.note_add_outlined,
                        color: _orderType == 'Reparatur' ? Colors.orange.shade800 : Colors.blue.shade800,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

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
            backgroundColor: _orderType == 'Reparatur'
                ? Colors.orange.shade800
                : Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_circle_outline),
          label: Text(_exportImmediately ? 'Anlegen & Exportieren' : 'Auftrag anlegen'),
        ),
      ],
    );
  }
}
