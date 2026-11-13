import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../services/window_options_service.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/editable_dropdown_field.dart';
import 'window_error_management_page.dart';

class NewWindowPage extends StatefulWidget {
  final Window? window;
  final int inspectionId;
  final bool isManagerMode;
  final bool isReadOnly;

  const NewWindowPage({
    super.key,
    this.window,
    required this.inspectionId,
    this.isManagerMode = false,
    this.isReadOnly = false,
  });

  @override
  State<NewWindowPage> createState() => _NewWindowPageState();
}

class _NewWindowPageState extends State<NewWindowPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _windowNumberCtrl;
  late TextEditingController _aliasCtrl;
  late TextEditingController _notesCtrl;

  String _floor = '?';
  String _roomNumber = '?';
  String _roomDesignation = '?';
  String _windowType = '?';
  String _material = '?';
  String _wingDimensions = '?';
  String _fittings = '?';

  bool _windowFunctionOK = true;
  // Raffstore state: 0 = Nicht vorhanden, 1 = In Ordnung, 2 = Defekt
  int _raffstoreState = 0;

  int? _activeWindowId;
  int _defectCount = 0;
  bool _isLoading = true;
  String _projectNumber = '';

  @override
  void initState() {
    super.initState();
    final w = widget.window;
    _activeWindowId = w?.id;

    _windowNumberCtrl = TextEditingController(text: w?.windowNumber ?? '');
    _aliasCtrl = TextEditingController(text: w?.windowAlias ?? w?.provisionalAlias ?? '');
    _notesCtrl = TextEditingController(text: w?.notes ?? '');

    _floor = (w?.floor != null && w!.floor.isNotEmpty) ? w.floor : '?';
    _roomNumber = (w?.roomNumber != null && w!.roomNumber.isNotEmpty) ? w.roomNumber : '?';
    _roomDesignation = (w?.roomDesignation != null && w!.roomDesignation.isNotEmpty) ? w.roomDesignation : '?';
    _windowType = (w?.windowType != null && w!.windowType.isNotEmpty) ? w.windowType : '?';
    _material = (w?.material != null && w!.material.isNotEmpty) ? w.material : '?';
    _wingDimensions = (w?.wingDimensions != null && w!.wingDimensions.isNotEmpty) ? w.wingDimensions : '?';
    _fittings = (w?.fittings != null && w!.fittings.isNotEmpty) ? w.fittings : '?';

    _windowFunctionOK = w?.windowFunctionOK ?? true;

    if (w?.hasRaffstore == true) {
      _raffstoreState = (w?.raffstoreOK == false) ? 2 : 1;
    } else {
      _raffstoreState = 0;
    }

    _loadInitialData();
  }

  @override
  void dispose() {
    _windowNumberCtrl.dispose();
    _aliasCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    await WindowOptionsService.ensureLoaded();

    try {
      // Fetch inspection metadata to get projectNumber
      Map<String, dynamic>? insp;
      if (widget.isManagerMode) {
        insp = await DatabaseService.getInspectionById(widget.inspectionId);
      } else {
        insp = await LocalDatabaseService.getInspectionById(widget.inspectionId);
      }
      if (insp != null) {
        _projectNumber = insp['projectNumber']?.toString() ?? insp['jobNumber']?.toString() ?? '';
      }

      await _refreshDefectCount();
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshDefectCount() async {
    if (_activeWindowId == null) return;
    try {
      int count = 0;
      if (widget.isManagerMode) {
        final junctions = await DatabaseService.getInspectionWindowsByInspectionId(widget.inspectionId);
        final junction = junctions.where((j) => j['windowId'] == _activeWindowId).firstOrNull;
        if (junction != null) {
          final errs = await DatabaseService.getInspectionWindowErrors(junction['id'] as int);
          count = errs.length;
        }
      } else {
        final junctions = await LocalDatabaseService.getInspectionWindowsByInspectionId(widget.inspectionId);
        final junction = junctions.where((j) => j['windowId'] == _activeWindowId).firstOrNull;
        if (junction != null) {
          final errs = await LocalDatabaseService.getInspectionWindowErrors(junction['id'] as int);
          count = errs.length;
        }
      }

      if (mounted) {
        setState(() {
          _defectCount = count;
          if (_defectCount > 0) {
            _windowFunctionOK = false;
          }
        });
      }
    } catch (_) {}
  }

  void _onWindowNumberChanged(String val) {
    if (_aliasCtrl.text.isEmpty || _aliasCtrl.text.startsWith('F-') || _aliasCtrl.text.startsWith('TMP-F-')) {
      final autoAlias = Window.generateAlias(
        projectNumber: _projectNumber,
        windowNumber: val.trim(),
      );
      _aliasCtrl.text = autoAlias;
    }
  }

  Future<void> _scanBarcode() async {
    final scanned = await BarcodeScannerDialog.show(context, title: 'Fenster-Barcode scannen');
    if (scanned != null && scanned.trim().isNotEmpty) {
      setState(() {
        _aliasCtrl.text = scanned.trim();
        // If window number is empty, we can set it to barcode or last token
        if (_windowNumberCtrl.text.trim().isEmpty) {
          _windowNumberCtrl.text = scanned.trim();
        }
      });
    }
  }

  Future<bool> _saveWindowData() async {
    if (!_formKey.currentState!.validate()) return false;

    final winNum = _windowNumberCtrl.text.trim();
    final alias = _aliasCtrl.text.trim().isNotEmpty
        ? _aliasCtrl.text.trim()
        : Window.generateAlias(projectNumber: _projectNumber, windowNumber: winNum);

    final bool hasRaffstore = _raffstoreState > 0;
    final bool? raffstoreOK = _raffstoreState == 0 ? null : (_raffstoreState == 1);

    final windowData = Window(
      id: _activeWindowId,
      windowNumber: winNum,
      floor: _floor == '?' ? '' : _floor,
      roomNumber: _roomNumber == '?' ? '' : _roomNumber,
      roomDesignation: _roomDesignation == '?' ? '' : _roomDesignation,
      windowType: _windowType == '?' ? '' : _windowType,
      material: _material == '?' ? '' : _material,
      wingDimensions: _wingDimensions == '?' ? '' : _wingDimensions,
      fittings: _fittings == '?' ? '' : _fittings,
      windowFunctionOK: _windowFunctionOK,
      hasRaffstore: hasRaffstore,
      raffstoreOK: raffstoreOK,
      notes: _notesCtrl.text.trim(),
      windowAlias: alias,
      provisionalAlias: alias,
    );

    // Save dropdown options dynamically if new values were added
    if (_floor != '?' && _floor.isNotEmpty) WindowOptionsService.addOption('floor', _floor);
    if (_roomNumber != '?' && _roomNumber.isNotEmpty) WindowOptionsService.addOption('roomNumber', _roomNumber);
    if (_roomDesignation != '?' && _roomDesignation.isNotEmpty) WindowOptionsService.addOption('roomDesignation', _roomDesignation);
    if (_windowType != '?' && _windowType.isNotEmpty) WindowOptionsService.addOption('windowType', _windowType);
    if (_material != '?' && _material.isNotEmpty) WindowOptionsService.addOption('material', _material);
    if (_wingDimensions != '?' && _wingDimensions.isNotEmpty) WindowOptionsService.addOption('wingDimensions', _wingDimensions);
    if (_fittings != '?' && _fittings.isNotEmpty) WindowOptionsService.addOption('fittings', _fittings);
    await WindowOptionsService.save();

    if (widget.isManagerMode) {
      if (_activeWindowId == null) {
        final newId = await DatabaseService.insertWindow(windowData);
        _activeWindowId = newId;
        await DatabaseService.insertInspectionWindow({
          'inspectionId': widget.inspectionId,
          'windowId': newId,
          'status': _windowFunctionOK ? 'In Ordnung' : 'Mängel',
          'notes': windowData.notes,
        });
      } else {
        await DatabaseService.updateWindow(windowData);
        await DatabaseService.updateInspectionWindowStatus(
          inspectionId: widget.inspectionId,
          windowId: _activeWindowId!,
          status: _windowFunctionOK ? 'In Ordnung' : 'Mängel',
          notes: windowData.notes,
        );
      }
    } else {
      if (_activeWindowId == null) {
        final newId = await LocalDatabaseService.insertWindow(windowData);
        _activeWindowId = newId;
        await LocalDatabaseService.insertInspectionWindow({
          'inspectionId': widget.inspectionId,
          'windowId': newId,
          'status': _windowFunctionOK ? 'In Ordnung' : 'Mängel',
          'notes': windowData.notes,
        });
      } else {
        await LocalDatabaseService.updateWindow(windowData);
        await LocalDatabaseService.updateInspectionWindowStatus(
          inspectionId: widget.inspectionId,
          windowId: _activeWindowId!,
          status: _windowFunctionOK ? 'In Ordnung' : 'Mängel',
          notes: windowData.notes,
        );
      }
    }

    return true;
  }

  Future<void> _onManageDefectsPressed() async {
    // Ensure window is saved before navigating to defect management
    final saved = await _saveWindowData();
    if (!saved || _activeWindowId == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WindowErrorManagementPage(
          windowId: _activeWindowId!,
          windowNumber: _windowNumberCtrl.text.trim(),
          inspectionId: widget.inspectionId,
          isManagerMode: widget.isManagerMode,
          isReadOnly: widget.isReadOnly,
        ),
      ),
    );

    await _refreshDefectCount();
  }

  Future<void> _onSaveAndClose() async {
    final success = await _saveWindowData();
    if (success && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _onSaveAndNext() async {
    final success = await _saveWindowData();
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fenster ${_windowNumberCtrl.text} gespeichert.'), duration: const Duration(seconds: 1)),
      );
      setState(() {
        _activeWindowId = null;
        _windowNumberCtrl.clear();
        _aliasCtrl.clear();
        _notesCtrl.clear();
        _windowFunctionOK = true;
        _defectCount = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isNew = _activeWindowId == null;
    final title = isNew ? 'Neues Fenster erfassen' : 'Fenster ${_windowNumberCtrl.text}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!widget.isReadOnly)
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Speichern',
              onPressed: _onSaveAndClose,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 1. IDENTIFIKATION ───────────────────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.qr_code, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text('Identifikation & Ort', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _windowNumberCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Fenster Nr. *',
                              hintText: 'z. B. 03-044',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Fenster-Nr. ist erforderlich';
                              return null;
                            },
                            onChanged: _onWindowNumberChanged,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.qr_code_scanner),
                          tooltip: 'Barcode scannen',
                          onPressed: _scanBarcode,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _aliasCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Fenster-Alias / Barcode',
                        hintText: 'z. B. F-000000-03-044',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    EditableDropdownField(
                      label: 'Etage',
                      currentValue: _floor,
                      options: WindowOptionsService.getStringOptions('floor'),
                      onChanged: (val) => setState(() => _floor = val),
                    ),
                    const SizedBox(height: 8),
                    EditableDropdownField(
                      label: 'Raum Nr.',
                      currentValue: _roomNumber,
                      options: WindowOptionsService.getStringOptions('roomNumber'),
                      onChanged: (val) => setState(() => _roomNumber = val),
                    ),
                    const SizedBox(height: 8),
                    EditableDropdownField(
                      label: 'Sonstiges / Raumbezeichnung',
                      currentValue: _roomDesignation,
                      options: WindowOptionsService.getStringOptions('roomDesignation'),
                      onChanged: (val) => setState(() => _roomDesignation = val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── 2. TECHNISCHE EIGENSCHAFTEN ──────────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.window, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text('Technische Spezifikationen', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(height: 20),
                    EditableDropdownField(
                      label: 'Fenstertyp (z. B. DKR, DKL, Fest)',
                      currentValue: _windowType,
                      options: WindowOptionsService.getStringOptions('windowType'),
                      onChanged: (val) => setState(() => _windowType = val),
                    ),
                    const SizedBox(height: 8),
                    EditableDropdownField(
                      label: 'Material (z. B. Alu, Kunststoff, Holz)',
                      currentValue: _material,
                      options: WindowOptionsService.getStringOptions('material'),
                      onChanged: (val) => setState(() => _material = val),
                    ),
                    const SizedBox(height: 8),
                    EditableDropdownField(
                      label: 'Flügelabmaße (Breite x Höhe x Flügeltiefe)',
                      currentValue: _wingDimensions,
                      options: WindowOptionsService.getStringOptions('wingDimensions'),
                      onChanged: (val) => setState(() => _wingDimensions = val),
                    ),
                    const SizedBox(height: 8),
                    EditableDropdownField(
                      label: 'Beschläge (Hersteller / Art.Nr.)',
                      currentValue: _fittings,
                      options: WindowOptionsService.getStringOptions('fittings'),
                      onChanged: (val) => setState(() => _fittings = val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── 3. FUNKTION & RAFFSTORE ──────────────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.checklist, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text('Zustand & Raffstore', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(height: 20),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Fenster in Ordnung', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(_windowFunctionOK ? 'Voll funktionsfähig' : 'Mängel vorhanden'),
                      value: _windowFunctionOK,
                      activeColor: Colors.green,
                      inactiveThumbColor: Colors.red,
                      onChanged: widget.isReadOnly
                          ? null
                          : (val) {
                              setState(() => _windowFunctionOK = val);
                            },
                    ),
                    const SizedBox(height: 12),
                    const Text('Raffstore (Außenjalousie):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Nicht vorh.')),
                        ButtonSegment(value: 1, label: Text('In Ordnung')),
                        ButtonSegment(value: 2, label: Text('Defekt')),
                      ],
                      selected: {_raffstoreState},
                      onSelectionChanged: widget.isReadOnly
                          ? null
                          : (newSet) {
                              setState(() => _raffstoreState = newSet.first);
                            },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── 4. MÄNGELVERFASSUNG ──────────────────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.report_problem_outlined, color: Colors.orange),
                            const SizedBox(width: 8),
                            Text('Mängelerfassung', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (_defectCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade300),
                            ),
                            child: Text(
                              '$_defectCount Mangel${_defectCount > 1 ? 's' : ''}',
                              style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                    const Divider(height: 20),
                    Center(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.build),
                        label: Text(_defectCount > 0 ? 'Mängel verwalten ($_defectCount erfasst)' : 'Mängel verwalten'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          backgroundColor: _defectCount > 0 ? Colors.orange.shade800 : Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _onManageDefectsPressed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── 5. ANMERKUNGEN ──────────────────────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notes, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text('Anmerkungen & Notizen', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(height: 20),
                    TextFormField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Freie Notizen zum Fenster oder Zustand...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── 6. ACTIONS ──────────────────────────────────────────────────
            if (!widget.isReadOnly) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Speichern & Schließen'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: _onSaveAndClose,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.add_task),
                label: const Text('Speichern & Nächstes Fenster'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _onSaveAndNext,
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

