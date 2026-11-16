import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../services/window_options_service.dart';
import '../utils/property_photo_helper.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/editable_dropdown_field.dart';
import '../widgets/full_screen_photo_viewer.dart';
import '../widgets/master_portal_home_button.dart';
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

  // Controllers for inspection metadata
  late TextEditingController customerNameController;
  late TextEditingController customerAddressController;
  late TextEditingController contactPersonController;
  late TextEditingController jobNumberController;
  late TextEditingController projectNumberController;
  late TextEditingController inspectorNameController;
  DateTime inspectionDate = DateTime.now();

  // Controllers for window properties
  late TextEditingController _windowNumberCtrl;
  late TextEditingController _aliasCtrl;
  late TextEditingController _notesCtrl;

  // Photo attachments for this window
  List<String> _windowPhotos = [];

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
  int _openDefectCount = 0;
  bool _isLoading = true;
  String _projectNumber = '';

  bool get _canSave {
    if (widget.isReadOnly) return false;
    if (_windowFunctionOK && _openDefectCount > 0) return false;
    if (!_windowFunctionOK && _openDefectCount == 0) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    final w = widget.window;
    _activeWindowId = w?.id;

    customerNameController = TextEditingController();
    customerAddressController = TextEditingController();
    contactPersonController = TextEditingController();
    jobNumberController = TextEditingController();
    projectNumberController = TextEditingController();
    inspectorNameController = TextEditingController();

    _windowNumberCtrl = TextEditingController(text: w?.windowNumber ?? '');
    _aliasCtrl = TextEditingController(
        text: w?.windowAlias ?? w?.provisionalAlias ?? '');
    _notesCtrl = TextEditingController(text: w?.notes ?? '');

    _floor = (w?.floor != null && w!.floor.isNotEmpty) ? w.floor : '?';
    _roomNumber = (w?.roomNumber != null && w!.roomNumber.isNotEmpty)
        ? w.roomNumber
        : '?';
    _roomDesignation =
        (w?.roomDesignation != null && w!.roomDesignation.isNotEmpty)
            ? w.roomDesignation
            : '?';
    _windowType = (w?.windowType != null && w!.windowType.isNotEmpty)
        ? w.windowType
        : '?';
    _material =
        (w?.material != null && w!.material.isNotEmpty) ? w.material : '?';
    _wingDimensions =
        (w?.wingDimensions != null && w!.wingDimensions.isNotEmpty)
            ? w.wingDimensions
            : '?';
    _fittings =
        (w?.fittings != null && w!.fittings.isNotEmpty) ? w.fittings : '?';

    _windowFunctionOK = w?.windowFunctionOK ?? true;

    if (w?.hasRaffstore == true) {
      _raffstoreState = (w?.raffstoreOK == false) ? 2 : 1;
    } else {
      _raffstoreState = 0;
    }

    if (w == null) {
      projectNumberController.addListener(_onAutoAliasUpdate);
      _windowNumberCtrl.addListener(_onAutoAliasUpdate);
    }

    _loadInitialData();
  }

  void _onAutoAliasUpdate() {
    if (_aliasCtrl.text.isEmpty ||
        _aliasCtrl.text.startsWith('F-') ||
        _aliasCtrl.text.startsWith('TMP-F-')) {
      final autoAlias = Window.generateAlias(
        projectNumber: projectNumberController.text.trim().isNotEmpty
            ? projectNumberController.text.trim()
            : _projectNumber,
        windowNumber: _windowNumberCtrl.text.trim(),
      );
      _aliasCtrl.text = autoAlias;
    }
  }

  @override
  void dispose() {
    customerNameController.dispose();
    customerAddressController.dispose();
    contactPersonController.dispose();
    jobNumberController.dispose();
    projectNumberController.dispose();
    inspectorNameController.dispose();
    _windowNumberCtrl.dispose();
    _aliasCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    await WindowOptionsService.ensureLoaded();

    try {
      // Fetch inspection metadata to get projectNumber and inspection metadata
      Map<String, dynamic>? insp;
      if (widget.isManagerMode) {
        insp = await DatabaseService.getInspectionById(widget.inspectionId);
      } else {
        insp =
            await LocalDatabaseService.getInspectionById(widget.inspectionId);
      }
      if (insp != null) {
        _projectNumber = insp['projectNumber']?.toString() ??
            insp['jobNumber']?.toString() ??
            '';
        customerNameController.text = insp['clientName']?.toString() ?? '';
        customerAddressController.text = insp['objectAddress']?.toString() ?? '';
        contactPersonController.text = insp['contactPerson']?.toString() ?? '';
        jobNumberController.text = insp['jobNumber']?.toString() ?? '';
        projectNumberController.text = insp['projectNumber']?.toString() ?? '';
        inspectorNameController.text = insp['inspectorName']?.toString() ?? '';
        if (insp['date'] != null && insp['date'].toString().isNotEmpty) {
          final parsedDate = DateTime.tryParse(insp['date'].toString());
          if (parsedDate != null) {
            inspectionDate = parsedDate;
          }
        }
      }

      // Load window photo attachments
      if (_activeWindowId != null) {
        final junctions = widget.isManagerMode
            ? await DatabaseService.getInspectionWindowsByInspectionId(
                widget.inspectionId)
            : await LocalDatabaseService.getInspectionWindowsByInspectionId(
                widget.inspectionId);
        final junction = junctions
            .where((j) => j['windowId'] == _activeWindowId)
            .firstOrNull;
        if (junction != null) {
          final atts = junction['attachments'] as String?;
          if (atts != null && atts.isNotEmpty) {
            _windowPhotos =
                atts.split(',').where((s) => s.trim().isNotEmpty).toList();
          }
        }
      }

      await _refreshDefectCount();
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _takeWindowPhoto() async {
    final alias = _aliasCtrl.text.trim().isNotEmpty
        ? _aliasCtrl.text.trim()
        : Window.generateAlias(
            projectNumber: projectNumberController.text.trim().isNotEmpty
                ? projectNumberController.text.trim()
                : _projectNumber,
            windowNumber: _windowNumberCtrl.text.trim(),
          );
    final jobNum = jobNumberController.text.trim().isNotEmpty
        ? jobNumberController.text.trim()
        : 'Auftrag';

    final result = await PropertyPhotoHelper.capturePropertyPhoto(
      context: context,
      doorAlias: alias,
      propertyName: 'Fenster',
      indexNumber: _windowPhotos.length + 1,
      jobNumber: jobNum,
    );

    if (result != null) {
      final timeStr = DateFormat('yyyyMMdd_HHmmss').format(result.timestamp);
      final photoEntry = '$timeStr#${result.base64Data}';

      setState(() {
        _windowPhotos.add(photoEntry);
      });

      if (_activeWindowId != null) {
        final atts = _windowPhotos.join(',');
        if (widget.isManagerMode) {
          await DatabaseService.updateInspectionWindowStatus(
            inspectionId: widget.inspectionId,
            windowId: _activeWindowId!,
            status: _windowFunctionOK ? 'In Ordnung' : 'Mängel',
            notes: _notesCtrl.text.trim(),
            attachments: atts,
          );
        } else {
          await LocalDatabaseService.updateInspectionWindowStatus(
            inspectionId: widget.inspectionId,
            windowId: _activeWindowId!,
            status: _windowFunctionOK ? 'In Ordnung' : 'Mängel',
            notes: _notesCtrl.text.trim(),
            attachments: atts,
          );
        }
      }
    }
  }

  Future<void> _deleteWindowPhoto(int index) async {
    if (index < 0 || index >= _windowPhotos.length) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto löschen?'),
        content: const Text('Möchten Sie dieses Fensterfoto wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _windowPhotos.removeAt(index);
      });
      if (_activeWindowId != null) {
        final atts = _windowPhotos.isNotEmpty ? _windowPhotos.join(',') : null;
        if (widget.isManagerMode) {
          await DatabaseService.updateInspectionWindowStatus(
            inspectionId: widget.inspectionId,
            windowId: _activeWindowId!,
            status: _windowFunctionOK ? 'In Ordnung' : 'Mängel',
            notes: _notesCtrl.text.trim(),
            attachments: atts,
          );
        } else {
          await LocalDatabaseService.updateInspectionWindowStatus(
            inspectionId: widget.inspectionId,
            windowId: _activeWindowId!,
            status: _windowFunctionOK ? 'In Ordnung' : 'Mängel',
            notes: _notesCtrl.text.trim(),
            attachments: atts,
          );
        }
      }
    }
  }

  void _showWindowPhotosDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Fensterfotos (${_windowPhotos.length})'),
                if (!widget.isReadOnly)
                  IconButton(
                    icon: const Icon(Icons.add_a_photo, color: Colors.blue),
                    tooltip: 'Neues Foto aufnehmen',
                    onPressed: () async {
                      await _takeWindowPhoto();
                      setDialogState(() {});
                    },
                  ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: _windowPhotos.isEmpty
                  ? const Center(child: Text('Keine Fotos vorhanden'))
                  : GridView.builder(
                      itemCount: _windowPhotos.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemBuilder: (ctx, idx) {
                        final photoEntry = _windowPhotos[idx];
                        String rawData = photoEntry;
                        if (photoEntry.contains('#')) {
                          rawData = photoEntry.split('#').sublist(1).join('#');
                        }
                        Uint8List? bytes;
                        try {
                          bytes = base64Decode(rawData);
                        } catch (_) {}

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                onTap: () {
                                  final allBase64 = _windowPhotos.map((p) {
                                    return p.contains('#')
                                        ? p.split('#').sublist(1).join('#')
                                        : p;
                                  }).toList();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          FullScreenPhotoGalleryViewer(
                                        photos: allBase64,
                                        initialIndex: idx,
                                      ),
                                    ),
                                  );
                                },
                                child: bytes != null
                                    ? Image.memory(bytes, fit: BoxFit.cover)
                                    : Container(
                                        color: Colors.grey.shade200,
                                        child: const Icon(Icons.broken_image),
                                      ),
                              ),
                            ),
                            if (!widget.isReadOnly)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.white, size: 16),
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
                                    onPressed: () async {
                                      await _deleteWindowPhoto(idx);
                                      setDialogState(() {});
                                      if (_windowPhotos.isEmpty && mounted) {
                                        Navigator.pop(dialogCtx);
                                      }
                                    },
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Schließen'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _refreshDefectCount() async {
    if (_activeWindowId == null) return;
    try {
      int count = 0;
      int openCount = 0;
      if (widget.isManagerMode) {
        final junctions =
            await DatabaseService.getInspectionWindowsByInspectionId(
                widget.inspectionId);
        final junction = junctions
            .where((j) => j['windowId'] == _activeWindowId)
            .firstOrNull;
        if (junction != null) {
          final errs = await DatabaseService.getInspectionWindowErrors(
              junction['id'] as int);
          count = errs.length;
          openCount = errs
              .where((e) => e.resolutionStatus.toLowerCase() != 'resolved')
              .length;
        }
      } else {
        final junctions =
            await LocalDatabaseService.getInspectionWindowsByInspectionId(
                widget.inspectionId);
        final junction = junctions
            .where((j) => j['windowId'] == _activeWindowId)
            .firstOrNull;
        if (junction != null) {
          final errs = await LocalDatabaseService.getInspectionWindowErrors(
              junction['id'] as int);
          count = errs.length;
          openCount = errs
              .where((e) => e.resolutionStatus.toLowerCase() != 'resolved')
              .length;
        }
      }

      if (mounted) {
        setState(() {
          _defectCount = count;
          _openDefectCount = openCount;
          if (_openDefectCount > 0) {
            _windowFunctionOK = false;
          }
        });
      }
    } catch (_) {}
  }

  void _onWindowNumberChanged(String val) {
    if (_aliasCtrl.text.isEmpty ||
        _aliasCtrl.text.startsWith('F-') ||
        _aliasCtrl.text.startsWith('TMP-F-')) {
      final autoAlias = Window.generateAlias(
        projectNumber: _projectNumber,
        windowNumber: val.trim(),
      );
      _aliasCtrl.text = autoAlias;
    }
  }

  Future<void> _scanBarcode() async {
    final scanned = await BarcodeScannerDialog.show(context,
        title: 'Fenster-Barcode scannen');
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

  Future<bool> _saveWindowData({bool isDraftForErrors = false}) async {
    if (!isDraftForErrors) {
      if (!_canSave) {
        if (widget.isReadOnly) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Gesperrte bzw. schreibgeschützte Inspektionen können nicht bearbeitet oder gespeichert werden.'),
              backgroundColor: Colors.orange,
            ),
          );
        } else if (_windowFunctionOK && _openDefectCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Funktion steht auf "Ja", aber es sind noch $_openDefectCount offene Mängel vorhanden. Bitte offene Mängel als "Gelöst" markieren oder Funktion auf "Nein" setzen.'),
              backgroundColor: Colors.red,
            ),
          );
        } else if (!_windowFunctionOK && _openDefectCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Wenn Bewertung auf "Nein" steht, muss mindestens ein offener Mangel über "Fehler verwalten" erfasst werden.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }
    }

    if (!_formKey.currentState!.validate()) return false;

    final winNum = _windowNumberCtrl.text.trim();
    final alias = _aliasCtrl.text.trim().isNotEmpty
        ? _aliasCtrl.text.trim()
        : Window.generateAlias(
            projectNumber: _projectNumber, windowNumber: winNum);

    final bool hasRaffstore = _raffstoreState > 0;
    final bool? raffstoreOK =
        _raffstoreState == 0 ? null : (_raffstoreState == 1);

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
    if (_floor != '?' && _floor.isNotEmpty)
      WindowOptionsService.addOption('floor', _floor);
    if (_roomNumber != '?' && _roomNumber.isNotEmpty)
      WindowOptionsService.addOption('roomNumber', _roomNumber);
    if (_roomDesignation != '?' && _roomDesignation.isNotEmpty)
      WindowOptionsService.addOption('roomDesignation', _roomDesignation);
    if (_windowType != '?' && _windowType.isNotEmpty)
      WindowOptionsService.addOption('windowType', _windowType);
    if (_material != '?' && _material.isNotEmpty)
      WindowOptionsService.addOption('material', _material);
    if (_wingDimensions != '?' && _wingDimensions.isNotEmpty)
      WindowOptionsService.addOption('wingDimensions', _wingDimensions);
    if (_fittings != '?' && _fittings.isNotEmpty)
      WindowOptionsService.addOption('fittings', _fittings);
    await WindowOptionsService.save();

    final String? photoAttachments =
        _windowPhotos.isNotEmpty ? _windowPhotos.join(',') : null;

    final Map<String, dynamic> inspectionData = {
      'inspectionId': widget.inspectionId,
      'clientName': customerNameController.text.trim(),
      'objectAddress': customerAddressController.text.trim(),
      'contactPerson': contactPersonController.text.trim(),
      'jobNumber': jobNumberController.text.trim(),
      'projectNumber': projectNumberController.text.trim(),
      'inspectorName': inspectorNameController.text.trim(),
      'date': inspectionDate.toIso8601String().substring(0, 10),
    };

    if (widget.isManagerMode) {
      await DatabaseService.updateInspection(inspectionData);
      if (_activeWindowId == null) {
        final newId = await DatabaseService.insertWindow(windowData);
        _activeWindowId = newId;
        await DatabaseService.insertInspectionWindow({
          'inspectionId': widget.inspectionId,
          'windowId': newId,
          'status': _windowFunctionOK ? 'In Ordnung' : 'Mängel',
          'notes': windowData.notes,
          'attachments': photoAttachments,
        });
      } else {
        await DatabaseService.updateWindow(windowData);
        await DatabaseService.updateInspectionWindowStatus(
          inspectionId: widget.inspectionId,
          windowId: _activeWindowId!,
          status: _windowFunctionOK ? 'In Ordnung' : 'Mängel',
          notes: windowData.notes,
          attachments: photoAttachments,
        );
      }
    } else {
      await LocalDatabaseService.updateInspection(inspectionData);
      if (_activeWindowId == null) {
        final newId = await LocalDatabaseService.insertWindow(windowData);
        _activeWindowId = newId;
        await LocalDatabaseService.insertInspectionWindow({
          'inspectionId': widget.inspectionId,
          'windowId': newId,
          'status': _windowFunctionOK ? 'In Ordnung' : 'Mängel',
          'notes': windowData.notes,
          'attachments': photoAttachments,
        });
      } else {
        await LocalDatabaseService.updateWindow(windowData);
        await LocalDatabaseService.updateInspectionWindowStatus(
          inspectionId: widget.inspectionId,
          windowId: _activeWindowId!,
          status: _windowFunctionOK ? 'In Ordnung' : 'Mängel',
          notes: windowData.notes,
          attachments: photoAttachments,
        );
      }
    }

    return true;
  }

  Future<void> _onManageDefectsPressed() async {
    // If window is not saved yet, persist draft first so errors can be attached
    if (_activeWindowId == null) {
      if (!_formKey.currentState!.validate()) return;
      final saved = await _saveWindowData(isDraftForErrors: true);
      if (!saved || _activeWindowId == null) return;
    }

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
        SnackBar(
            content: Text('Fenster ${_windowNumberCtrl.text} gespeichert.'),
            duration: const Duration(seconds: 1)),
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
    final title =
        isNew ? 'Neues Fenster erfassen' : 'Fenster ${_windowNumberCtrl.text}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          MasterPortalHomeButton(isManagerMode: widget.isManagerMode),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Action buttons (Top)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _canSave ? _onSaveAndClose : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _canSave ? Colors.orange : Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                        widget.isReadOnly ? 'Schreibgeschützt' : 'Speichern'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _onManageDefectsPressed,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Fehler verwalten'),
                  ),
                ),
              ],
            ),
            if (!widget.isReadOnly &&
                !_windowFunctionOK &&
                _openDefectCount == 0) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border.all(color: Colors.amber.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber.shade900, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bewertung ist "Nein": Bitte fügen Sie mindestens einen Fehler über "Fehler verwalten" hinzu, um speichern zu können.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // ── 0. INSPEKTIONSDATEN ─────────────────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.assignment, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text('Inspektionsdaten',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(height: 20),
                    TextFormField(
                      controller: customerNameController,
                      enabled: widget.isManagerMode && !widget.isReadOnly,
                      decoration: InputDecoration(
                        labelText: 'Kundenname',
                        helperText: !widget.isManagerMode
                            ? 'Schreibgeschützt für Inspektor'
                            : null,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: customerAddressController,
                      enabled: widget.isManagerMode && !widget.isReadOnly,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Kundenadresse / Objektadresse',
                        helperText: !widget.isManagerMode
                            ? 'Schreibgeschützt für Inspektor'
                            : null,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: contactPersonController,
                      enabled: widget.isManagerMode && !widget.isReadOnly,
                      decoration: InputDecoration(
                        labelText: 'Ansprechpartner',
                        helperText: !widget.isManagerMode
                            ? 'Schreibgeschützt für Inspektor'
                            : null,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: jobNumberController,
                            enabled: widget.isManagerMode && !widget.isReadOnly,
                            decoration: InputDecoration(
                              labelText: 'Auftragsnummer',
                              helperText: !widget.isManagerMode
                                  ? 'Schreibgeschützt'
                                  : null,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: projectNumberController,
                            enabled: widget.isManagerMode && !widget.isReadOnly,
                            decoration: InputDecoration(
                              labelText: 'Projektnummer',
                              helperText: !widget.isManagerMode
                                  ? 'Schreibgeschützt'
                                  : null,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: inspectorNameController,
                            enabled: widget.isManagerMode && !widget.isReadOnly,
                            decoration: InputDecoration(
                              labelText: 'Inspektor / Prüfer',
                              helperText: !widget.isManagerMode
                                  ? 'Schreibgeschützt'
                                  : null,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: (widget.isManagerMode && !widget.isReadOnly)
                                ? () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: inspectionDate,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (picked != null) {
                                      setState(() => inspectionDate = picked);
                                    }
                                  }
                                : null,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Inspektionsdatum',
                                helperText: !widget.isManagerMode
                                    ? 'Schreibgeschützt'
                                    : null,
                                border: const OutlineInputBorder(),
                                isDense: true,
                                suffixIcon:
                                    const Icon(Icons.calendar_today, size: 20),
                              ),
                              child: Text(
                                DateFormat('dd.MM.yyyy').format(inspectionDate),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── 1. IDENTIFIKATION ───────────────────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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
                            const Icon(Icons.qr_code, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text('Identifikation & Ort',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        OutlinedButton.icon(
                          onPressed: widget.isReadOnly
                              ? null
                              : () => _windowPhotos.isEmpty
                                  ? _takeWindowPhoto()
                                  : _showWindowPhotosDialog(),
                          icon: const Icon(Icons.camera_alt, size: 18),
                          label: Text(_windowPhotos.isNotEmpty
                              ? 'Fensterfoto (${_windowPhotos.length})'
                              : 'Fensterfoto aufnehmen'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
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
                              if (val == null || val.trim().isEmpty)
                                return 'Fenster-Nr. ist erforderlich';
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
                      options:
                          WindowOptionsService.getStringOptions('roomNumber'),
                      onChanged: (val) => setState(() => _roomNumber = val),
                    ),
                    const SizedBox(height: 8),
                    EditableDropdownField(
                      label: 'Sonstiges / Raumbezeichnung',
                      currentValue: _roomDesignation,
                      options: WindowOptionsService.getStringOptions(
                          'roomDesignation'),
                      onChanged: (val) =>
                          setState(() => _roomDesignation = val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── 2. TECHNISCHE EIGENSCHAFTEN ──────────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.window, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text('Technische Spezifikationen',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(height: 20),
                    EditableDropdownField(
                      label: 'Fenstertyp (z. B. DKR, DKL, Fest)',
                      currentValue: _windowType,
                      options:
                          WindowOptionsService.getStringOptions('windowType'),
                      onChanged: (val) => setState(() => _windowType = val),
                    ),
                    const SizedBox(height: 8),
                    EditableDropdownField(
                      label: 'Material (z. B. Alu, Kunststoff, Holz)',
                      currentValue: _material,
                      options:
                          WindowOptionsService.getStringOptions('material'),
                      onChanged: (val) => setState(() => _material = val),
                    ),
                    const SizedBox(height: 8),
                    EditableDropdownField(
                      label: 'Flügelabmaße (Breite x Höhe x Flügeltiefe)',
                      currentValue: _wingDimensions,
                      options: WindowOptionsService.getStringOptions(
                          'wingDimensions'),
                      onChanged: (val) => setState(() => _wingDimensions = val),
                    ),
                    const SizedBox(height: 8),
                    EditableDropdownField(
                      label: 'Beschläge (Hersteller / Art.Nr.)',
                      currentValue: _fittings,
                      options:
                          WindowOptionsService.getStringOptions('fittings'),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.checklist, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text('Zustand & Raffstore',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(height: 20),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Fenster in Ordnung',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(_windowFunctionOK
                          ? 'Voll funktionsfähig'
                          : 'Mängel vorhanden'),
                      value: _windowFunctionOK,
                      activeThumbColor: Colors.green,
                      inactiveThumbColor: Colors.red,
                      onChanged: widget.isReadOnly
                          ? null
                          : (val) {
                              if (val && _openDefectCount > 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Es sind noch $_openDefectCount offene Mängel vorhanden. Bitte offene Mängel als "Gelöst" markieren oder Bewertung auf "Nein" belassen.'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                              setState(() => _windowFunctionOK = val);
                            },
                    ),
                    const SizedBox(height: 12),
                    const Text('Raffstore (Außenjalousie):',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
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

            // ── 4. ANMERKUNGEN ──────────────────────────────────────────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notes, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text('Anmerkungen & Notizen',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
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
            const SizedBox(height: 16),

            // Validation Warning Hints (as in door inspection)
            if (!widget.isReadOnly &&
                _windowFunctionOK &&
                _openDefectCount > 0) ...[
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 4),
                child: Text(
                  'Hinweis: Das Fenster ist als ordnungsgemäß (Ja) markiert, hat aber noch $_openDefectCount offene Mängel. Bitte Mängel auf "Gelöst" setzen oder Bewertung auf "Nein" ändern, um speichern zu können.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ] else if (!widget.isReadOnly &&
                !_windowFunctionOK &&
                _openDefectCount == 0) ...[
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 4),
                child: Text(
                  'Hinweis: Da das Fenster nicht als ordnungsgemäß bewertet ist, muss mindestens ein offener Mangel über "Fehler verwalten" hinzugefügt werden, um zu speichern.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            if (!widget.isReadOnly) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.add_task),
                label: const Text('Speichern & Nächstes Fenster'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _canSave ? _onSaveAndNext : null,
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
