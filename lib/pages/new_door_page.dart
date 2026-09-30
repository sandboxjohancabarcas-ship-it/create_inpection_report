import 'package:flutter/material.dart';
import '../services/local_database_service.dart';
import '../services/database_service.dart';
import '../services/door_options_service.dart';
import '../models/models.dart';
import '../widgets/master_portal_home_button.dart';
import '../widgets/editable_dropdown_field.dart';
import '../widgets/barcode_scanner_dialog.dart';
import 'error_management_page.dart';
import 'door_history_page.dart';
import '../utils/inspection_year_utils.dart';

class DoorInspectionForm extends StatefulWidget {
  final Door? door; // null = create mode
  final bool isManagerMode;
  final int? inspectionId;
  final bool? isReadOnly;
 
  const DoorInspectionForm({
    super.key,
    this.door,
    this.isManagerMode = false,
    this.inspectionId,
    this.isReadOnly,
  });

  @override
  State<DoorInspectionForm> createState() => _DoorInspectionFormState();
}

class _DoorInspectionFormState extends State<DoorInspectionForm> {
  Door? _activeDoor;

  // Controllers for inspection metadata
  late TextEditingController customerNameController;
  late TextEditingController customerAddressController;
  late TextEditingController contactPersonController;
  late TextEditingController jobNumberController;
  late TextEditingController projectNumberController;
  late TextEditingController inspectorNameController;
  
  // Controllers for door technical fields
  late TextEditingController doorNumberController;
  late TextEditingController roomDesignationController;
  late TextEditingController floorController;
  late TextEditingController roomNumberController;
  late TextEditingController lockDimensionsController;
  late TextEditingController doorAliasController;
  late TextEditingController provisionalAliasController;
  late TextEditingController dopNumberController;
  late TextEditingController notesController;
  bool isAliasManuallyEdited = false;

  // Additional free-text dropdown property states
  String approvalNumber = '?';
  String manufacturer = '?';
  String manufacturerNumber = '?';
  String manufactureYear = '?';
  String? fsaDriveAcceptanceDate;

  // Boolean states
  bool escapeSignage = false;
  bool properFunction = false;
  bool blindCylinder = false;
  bool pzCylinder = false;
  bool closerOnHingeSide = false;
  bool closerOnOppositeSide = false;
  bool lintelHeightInsideOver1m = false;
  bool lintelHeightOutsideOver1m = false;
  String? lintelHeightInsideValue;
  String? lintelHeightOutsideValue;
  bool escapeRouteSituation = false;
  bool escapeDirectionRespected = false;
  bool fullPanicStandWing = false;

  // Dropdowns
  String? escapeDoorControl;
  String? accessControl;
  String? panicFunction;
  String? doorType;
  String? material;
  String? dinConfiguration;
  String? closerType;
  String? closingSequenceSystem;
  String? fittingType;
  
  // Numeric fields
  int wingCount = 1;
  int pos = 0;
  
  // Date field
  DateTime inspectionDate = DateTime.now();
  DateTime? repairDate;
  String orderType = 'Wartung';
  int? currentInspectionId;
  bool _isLoadingOptions = true;
  int _errorCount = 0;
  int _openErrorCount = 0;

  bool get _canSave {
    if (_isFormReadOnly) return false;
    if (properFunction && _openErrorCount > 0) return false;
    if (!properFunction && _openErrorCount == 0) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _activeDoor = widget.door;
    _loadOptionsAndData();
  }

  void _updateGeneratedAlias() {
    if (_activeDoor == null && !isAliasManuallyEdited) {
      final gen = Door.generateAlias(
        projectNumber: projectNumberController.text,
        pos: pos,
        floor: floorController.text,
        doorNumber: doorNumberController.text,
      );
      provisionalAliasController.text = gen;
      doorAliasController.text = gen;
    }
  }

  Future<void> _loadOptionsAndData() async {
    await DoorOptionsService.ensureLoaded();

    final d = _activeDoor;

    // Note: These will now be handled separately from the Door object
    customerNameController = TextEditingController();
    customerAddressController = TextEditingController();
    contactPersonController = TextEditingController();
    jobNumberController = TextEditingController();
    projectNumberController = TextEditingController();
    inspectorNameController = TextEditingController();

    // Initialize door technical controllers
    doorNumberController = TextEditingController(text: d?.doorNumber ?? '');
    roomDesignationController = TextEditingController(text: d?.roomDesignation ?? '');
    floorController = TextEditingController(text: d?.floor ?? '');
    roomNumberController = TextEditingController(text: d?.roomNumber ?? '');
    lockDimensionsController = TextEditingController(text: d?.lockDimensions ?? '');
    doorAliasController = TextEditingController(text: d?.doorAlias ?? '');
    provisionalAliasController = TextEditingController(text: d?.provisionalAlias ?? d?.doorAlias ?? '');
    dopNumberController = TextEditingController(text: d?.dopNumber ?? '');
    notesController = TextEditingController(text: d?.notes ?? '');

    if (d?.doorAlias != null && d!.doorAlias!.isNotEmpty) {
      isAliasManuallyEdited = true;
    }

    if (d == null) {
      customerNameController.addListener(_updateGeneratedAlias);
      customerAddressController.addListener(_updateGeneratedAlias);
      doorNumberController.addListener(_updateGeneratedAlias);
      floorController.addListener(_updateGeneratedAlias);
      projectNumberController.addListener(_updateGeneratedAlias);
    }

    // Initialize booleans
    escapeSignage = d?.escapeRouteSignage ?? false;
    properFunction = d?.doorFunctionOK ?? false;
    blindCylinder = d?.blindCylinder ?? false;
    pzCylinder = d?.pzCylinder ?? false;
    closerOnHingeSide = d?.closerOnHingeSide ?? false;
    closerOnOppositeSide = d?.closerOnOppositeSide ?? false;
    lintelHeightInsideOver1m = d?.lintelHeightInsideOver1m ?? false;
    lintelHeightOutsideOver1m = d?.lintelHeightOutsideOver1m ?? false;
    lintelHeightInsideValue = d?.lintelHeightInsideValue;
    lintelHeightOutsideValue = d?.lintelHeightOutsideValue;
    escapeRouteSituation = d?.escapeRouteSituation ?? false;
    escapeDirectionRespected = d?.escapeDirectionRespected ?? false;
    fullPanicStandWing = d?.fullPanicStandWing ?? false;

    // Initialize free-text dropdown fields & year
    approvalNumber = d?.approvalNumber ?? '?';
    manufacturer = d?.manufacturer ?? DoorOptionsService.getDefault('manufacturer') ?? '?';
    manufacturerNumber = d?.manufacturerNumber ?? '?';
    manufactureYear = d?.manufactureYear ?? '?';
    fsaDriveAcceptanceDate = d?.fsaDriveAcceptanceDate;

    // Initialize dropdowns (use defaults from config file if creating a new door)
    escapeDoorControl = d?.escapeDoorControl ?? DoorOptionsService.getDefault('escapeDoorControl') ?? 'Nein';
    accessControl = d?.accessControl ?? DoorOptionsService.getDefault('accessControl');
    panicFunction = d?.panicFunction ?? DoorOptionsService.getDefault('panicFunction');
    doorType = d?.doorType ?? DoorOptionsService.getDefault('doorType');
    material = d?.material ?? DoorOptionsService.getDefault('material');
    dinConfiguration = d?.dinConfiguration ?? DoorOptionsService.getDefault('dinConfiguration');
    closerType = d?.closerType ?? DoorOptionsService.getDefault('closerType');
    closingSequenceSystem = d?.closingSequenceSystem ?? DoorOptionsService.getDefault('closingSequenceSystem');
    fittingType = d?.fittingType ?? DoorOptionsService.getDefault('fittingType');

    // Initialize numeric fields
    wingCount = d?.wingCount ?? DoorOptionsService.getDefault('wingCount') ?? 1;
    pos = d?.pos ?? 0;

    // Always load inspection metadata, whether creating a new door or editing an existing one
    await _loadInspectionData();

    if (mounted) {
      setState(() {
        _isLoadingOptions = false;
      });
    }
  }

  @override
  void dispose() {
    doorAliasController.dispose();
    provisionalAliasController.dispose();
    projectNumberController.dispose();
    dopNumberController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> _loadInspectionData() async {
    // Select correct database based on role
    final db = widget.isManagerMode 
        ? await DatabaseService.getDb() 
        : await LocalDatabaseService.getDb();
        
    List<Map<String, dynamic>> results = [];
    if (widget.door != null && widget.door!.id != null) {
      if (widget.inspectionId != null) {
        results = await db.rawQuery('''
          SELECT i.* 
          FROM inspections i
          INNER JOIN inspection_doors id ON i.inspectionId = id.inspectionId
          WHERE id.doorId = ? AND i.inspectionId = ?
          LIMIT 1
        ''', [widget.door!.id!, widget.inspectionId!]);

        if (results.isEmpty) {
          results = await db.query(
            'inspections',
            where: 'inspectionId = ?',
            whereArgs: [widget.inspectionId!],
            limit: 1,
          );
        }
      } else {
        results = await db.rawQuery('''
          SELECT i.* 
          FROM inspections i
          INNER JOIN inspection_doors id ON i.inspectionId = id.inspectionId
          WHERE id.doorId = ?
          ORDER BY i.date DESC
          LIMIT 1
        ''', [widget.door!.id!]);
      }
    } else if (widget.inspectionId != null) {
      results = await db.query(
        'inspections',
        where: 'inspectionId = ?',
        whereArgs: [widget.inspectionId!],
        limit: 1,
      );
    } else {
      // If creating a new door without explicit inspectionId:
      // Load the most recent inspection available in the database
      results = await db.query(
        'inspections',
        orderBy: 'inspectionId DESC',
        limit: 1,
      );
    }

    if (results.isNotEmpty) {
      final insp = results.first;
      final repDateStr = insp['repairDate']?.toString();
      setState(() {
        currentInspectionId = widget.inspectionId ?? insp['inspectionId'];
        _isLocked = InspectionYearUtils.isInspectionLocked(insp['isLocked'], insp['date']);
        customerNameController.text = insp['clientName'] ?? '';
        customerAddressController.text = insp['objectAddress'] ?? '';
        contactPersonController.text = insp['contactPerson'] ?? '';
        jobNumberController.text = insp['jobNumber'] ?? '';
        projectNumberController.text = insp['projectNumber'] ?? '';
        inspectorNameController.text = insp['inspectorName'] ?? '';
        inspectionDate = DateTime.tryParse(insp['date'] ?? '') ?? DateTime.now();
        orderType = insp['orderType']?.toString() ?? 'Wartung';
        repairDate = (repDateStr != null && repDateStr.isNotEmpty) ? DateTime.tryParse(repDateStr) : null;
      });

      // Calculate next available door position (pos) for this inspection if creating a new door
      if (_activeDoor == null && currentInspectionId != null) {
        final existingDoors = await db.rawQuery('''
          SELECT MAX(d.pos) as maxPos, COUNT(d.id) as doorCount
          FROM doors d
          INNER JOIN inspection_doors id ON d.id = id.doorId
          WHERE id.inspectionId = ?
        ''', [currentInspectionId!]);

        if (existingDoors.isNotEmpty) {
          final maxPos = (existingDoors.first['maxPos'] as num?)?.toInt();
          final count = (existingDoors.first['doorCount'] as num?)?.toInt() ?? 0;
          setState(() {
            pos = (maxPos != null && maxPos > 0) ? maxPos + 1 : count + 1;
          });
        } else {
          setState(() {
            pos = 1;
          });
        }
        _updateGeneratedAlias();
      }
    } else if (widget.inspectionId != null) {
      setState(() {
        currentInspectionId = widget.inspectionId;
      });
    }

    await _syncErrorNotes();
  }

  Future<void> syncErrorNotes() => _syncErrorNotes();

  Future<void> _syncErrorNotes() async {
    final doorId = _activeDoor?.id ?? widget.door?.id;
    if (doorId == null || currentInspectionId == null) {
      if (mounted) {
        setState(() {
          _errorCount = 0;
        });
      }
      return;
    }
    try {
      final db = widget.isManagerMode 
          ? await DatabaseService.getDb() 
          : await LocalDatabaseService.getDb();

      final junctionResults = await db.query(
        'inspection_doors',
        columns: ['id'],
        where: 'doorId = ? AND inspectionId = ?',
        whereArgs: [doorId, currentInspectionId!],
        limit: 1,
      );

      final allCatalog = widget.isManagerMode
          ? await DatabaseService.getAllErrorCatalog()
          : await LocalDatabaseService.getAllErrorCatalog();

      if (junctionResults.isNotEmpty) {
        final junctionId = junctionResults.first['id'] as int;
        final errors = widget.isManagerMode
            ? await DatabaseService.getDetailedErrorsForInspectionDoor(junctionId)
            : await LocalDatabaseService.getDetailedErrorsForInspectionDoor(junctionId);

        final List<String> formattedEntries = [];
        for (final e in errors) {
          final desc = (e['description'] ?? e['code'] ?? e['errorCode'] ?? '').toString().trim();
          final note = (e['notes'] ?? '').toString().trim();
          final status = (e['resolutionStatus']?.toString() ?? 'open').toLowerCase();
          final isResolved = (status == 'resolved' || status == 'gelöst' || status == 'beholfen');
          final statusSuffix = isResolved ? ' [Gelöst]' : '';

          if (desc.isNotEmpty && note.isNotEmpty) {
            formattedEntries.add('$desc: $note$statusSuffix');
          } else if (desc.isNotEmpty) {
            formattedEntries.add('$desc$statusSuffix');
          } else if (note.isNotEmpty) {
            formattedEntries.add('$note$statusSuffix');
          }
        }

        // Reconcile current notesController text: preserve manual notes, replace/remove error lines
        final existingLines = notesController.text
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        final List<String> manualNotes = [];

        for (final line in existingLines) {
          if (!_isErrorDerivedLine(line, allCatalog, formattedEntries)) {
            manualNotes.add(line);
          }
        }

        final List<String> consolidated = [];
        if (manualNotes.isNotEmpty) {
          consolidated.addAll(manualNotes);
        }
        if (formattedEntries.isNotEmpty) {
          consolidated.addAll(formattedEntries);
        }

        final newNotesText = consolidated.join('\n').trim();

        int openErrors = 0;
        for (final e in errors) {
          final status = (e['resolutionStatus']?.toString() ?? 'open').toLowerCase();
          if (status != 'resolved' && status != 'gelöst' && status != 'beholfen') {
            openErrors++;
          }
        }

        if (mounted) {
          setState(() {
            _errorCount = errors.length;
            _openErrorCount = openErrors;
            if (openErrors > 0) {
              properFunction = false;
            }
            notesController.text = newNotesText;
          });
        }

        // Keep database in sync
        if (_activeDoor != null && _activeDoor!.id != null) {
          final updatedDoor = _activeDoor!.copyWith(notes: newNotesText);
          _activeDoor = updatedDoor;
          if (widget.isManagerMode) {
            await DatabaseService.updateDoor(updatedDoor);
            await DatabaseService.updateInspectionDoorStatus(
              inspectionId: currentInspectionId!,
              doorId: updatedDoor.id!,
              status: properFunction ? 'Inspected' : 'Pending',
              notes: newNotesText,
            );
          } else {
            await LocalDatabaseService.updateDoor(updatedDoor);
            await LocalDatabaseService.updateInspectionDoorStatus(
              inspectionId: currentInspectionId!,
              doorId: updatedDoor.id!,
              status: properFunction ? 'Inspected' : 'Pending',
              notes: newNotesText,
            );
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _errorCount = 0;
            _openErrorCount = 0;
          });
        }
      }
    } catch (e) {
      print('Error syncing error notes: $e');
    }
  }

  bool _isErrorDerivedLine(String line, List<ErrorCatalog> allCatalog, List<String> currentFormattedEntries) {
    if (line.isEmpty) return false;
    // Direct match with any currently active error note entry
    if (currentFormattedEntries.any((entry) => entry == line || entry.startsWith(line) || line.startsWith(entry))) {
      return true;
    }
    // Legacy error prefixes
    if (line.startsWith('M-') || line.startsWith('ERR_') || line.startsWith('PROP-') || line.startsWith('ALT-')) {
      return true;
    }
    // Match against any known catalog error description or code prefix
    final cleanLine = line
        .replaceAll(RegExp(r'\s*\[Gelöst\]|\s*\(Gelöst\)', caseSensitive: false), '')
        .trim()
        .toLowerCase();
    for (final cat in allCatalog) {
      final desc = cat.description.trim().toLowerCase();
      final code = cat.code.trim().toLowerCase();
      if (desc.isNotEmpty) {
        if (cleanLine == desc ||
            cleanLine.startsWith('$desc:') ||
            cleanLine.startsWith('$desc -') ||
            cleanLine.startsWith('$desc,') ||
            cleanLine.startsWith('$desc ')) {
          return true;
        }
      }
      if (code.isNotEmpty) {
        if (cleanLine == code ||
            cleanLine.startsWith('$code:') ||
            cleanLine.startsWith('$code -') ||
            cleanLine.startsWith('$code ')) {
          return true;
        }
      }
    }
    return false;
  }

  void _openNotesDialog() {
    final dialogController = TextEditingController(text: notesController.text);
    final bool readOnly = widget.isReadOnly ?? false;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.note_alt_outlined, color: Colors.blue.shade800, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tür-Notizen & Mängelhinweise',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    doorAliasController.text.isNotEmpty
                        ? 'Barcode: ${doorAliasController.text}'
                        : 'Türnummer: ${doorNumberController.text}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: Colors.blue.shade800),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          readOnly
                              ? 'Erfasste Notizen und automatisch dokumentierte Mängelhinweise zu dieser Tür (Lesemodus).'
                              : 'Hier werden angemeldete Mängelhinweise und Notizen zusammengefasst. Sie können den Text beliebig erweitern oder ergänzen.',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: dialogController,
                  readOnly: readOnly,
                  maxLines: 14,
                  minLines: 8,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                  decoration: InputDecoration(
                    labelText: 'Notizen & Mängelbeschreibungen (Volltext)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'Keine Notizen erfasst...',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!readOnly) ...[
            TextButton.icon(
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('Text leeren'),
              onPressed: () {
                dialogController.clear();
              },
            ),
            TextButton(
              child: const Text('Abbrechen'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Übernehmen'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () {
                setState(() {
                  notesController.text = dialogController.text;
                });
                Navigator.of(ctx).pop();
              },
            ),
          ] else ...[
            TextButton(
              child: const Text('Schließen'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ],
      ),
    );
  }

  // Build a Door object from form fields
  Door buildDoor() {
    String prov = provisionalAliasController.text.trim();
    String alias = doorAliasController.text.trim();
    if (prov.isEmpty && alias.isNotEmpty) {
      prov = alias;
    } else if (prov.isEmpty) {
      prov = Door.generateAlias(
        projectNumber: projectNumberController.text,
        pos: pos,
        floor: floorController.text,
        doorNumber: doorNumberController.text,
      );
    }
    if (alias.isEmpty) {
      alias = prov;
    }
    return Door(
      id: _activeDoor?.id ?? widget.door?.id, // Leave null for new doors to allow AUTOINCREMENT
      pos: pos,
      doorAlias: alias,
      provisionalAlias: prov,
      doorNumber: doorNumberController.text,
      floor: floorController.text,
      roomNumber: roomNumberController.text,
      roomDesignation: roomDesignationController.text,
      doorType: doorType ?? DoorOptionsService.getDefault('doorType') ?? 'T30',
      wingCount: wingCount,
      material: material ?? DoorOptionsService.getDefault('material') ?? 'Stahl',
      manufacturer: manufacturer,
      dinConfiguration: dinConfiguration ?? DoorOptionsService.getDefault('dinConfiguration') ?? 'DIN L',
      closerType: closerType ?? DoorOptionsService.getDefault('closerType') ?? 'TS93',
      closingSequenceSystem: closingSequenceSystem ?? DoorOptionsService.getDefault('closingSequenceSystem') ?? 'None',
      lockDimensions: lockDimensionsController.text,
      closerOnHingeSide: closerOnHingeSide,
      closerOnOppositeSide: closerOnOppositeSide,
      lintelHeightInsideOver1m: lintelHeightInsideOver1m,
      escapeDoorControl: escapeDoorControl ?? DoorOptionsService.getDefault('escapeDoorControl') ?? 'Nein',
      accessControl: accessControl ?? DoorOptionsService.getDefault('accessControl') ?? 'Nein',
      escapeRouteSituation: escapeRouteSituation,
      escapeRouteSignage: escapeSignage,
      blindCylinder: blindCylinder,
      pzCylinder: pzCylinder,
      fittingType: fittingType ?? DoorOptionsService.getDefault('fittingType') ?? 'Drücker',
      panicFunction: panicFunction ?? DoorOptionsService.getDefault('panicFunction') ?? 'Nein',
      escapeDirectionRespected: escapeDirectionRespected,
      fullPanicStandWing: fullPanicStandWing,
      doorFunctionOK: properFunction,
      approvalNumber: approvalNumber,
      manufacturerNumber: manufacturerNumber,
      dopNumber: dopNumberController.text,
      lintelHeightOutsideOver1m: lintelHeightOutsideOver1m,
      lintelHeightInsideValue: lintelHeightInsideOver1m ? lintelHeightInsideValue : null,
      lintelHeightOutsideValue: lintelHeightOutsideOver1m ? lintelHeightOutsideValue : null,
      manufactureYear: manufactureYear,
      fsaDriveAcceptanceDate: fsaDriveAcceptanceDate,
      notes: notesController.text,
    );
  }

  bool _isLocked = false;

  bool get _isFormReadOnly {
    if (widget.isReadOnly == true) return true;
    if (widget.isManagerMode) return false;
    return _isLocked;
  }

  Future<bool> _validateBarcodeUniqueness([String? customBarcode]) async {
    final barcodeToTest = (customBarcode ?? doorAliasController.text).trim();
    if (barcodeToTest.isEmpty) return true;

    final currentId = _activeDoor?.id ?? widget.door?.id;
    final existingDoor = widget.isManagerMode
        ? await DatabaseService.findDoorByBarcode(barcodeToTest, excludeDoorId: currentId)
        : await LocalDatabaseService.findDoorByBarcode(barcodeToTest, excludeDoorId: currentId);

    if (existingDoor != null) {
      if (mounted) {
        final doorDesc = existingDoor.doorNumber.isNotEmpty ? existingDoor.doorNumber : 'Pos. ${existingDoor.pos}';
        final locationInfo = [
          if (existingDoor.floor.isNotEmpty) existingDoor.floor,
          if (existingDoor.roomDesignation.isNotEmpty) existingDoor.roomDesignation,
        ].join(', ');
        final locationText = locationInfo.isNotEmpty ? ' ($locationInfo)' : '';

        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                SizedBox(width: 8),
                Text('Barcode bereits vergeben'),
              ],
            ),
            content: Text(
              'Der Barcode "$barcodeToTest" wird bereits für Tür "$doorDesc"$locationText verwendet.\n\n'
              'Ein Barcode darf nicht mehrfach vergeben werden.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return false;
    }
    return true;
  }

  Future<void> saveDoor() async {
    if (!_canSave) {
      if (_isFormReadOnly) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gesperrte Inspektionen können vom Inspektor nicht bearbeitet oder gespeichert werden.'),
            backgroundColor: Colors.orange,
          ),
        );
      } else if (properFunction && _openErrorCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Funktion steht auf "Ja", aber es sind noch $_openErrorCount offene Mängel vorhanden. Bitte offene Mängel als "Gelöst" markieren oder Funktion auf "Nein" setzen.'),
            backgroundColor: Colors.red,
          ),
        );
      } else if (!properFunction && _openErrorCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wenn Bewertung auf "Nein" steht, muss mindestens ein offener Mangel über "Fehler verwalten" erfasst werden.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!await _validateBarcodeUniqueness()) {
      return;
    }

    final door = buildDoor();
    
    // Save Inspection Metadata first
    final Map<String, dynamic> inspectionData = {
      'clientName': customerNameController.text,
      'objectAddress': customerAddressController.text,
      'date': inspectionDate.toIso8601String(),
      'orderType': orderType,
      'repairDate': repairDate?.toIso8601String(),
      'contactPerson': contactPersonController.text,
      'inspectorName': inspectorNameController.text,
      'jobNumber': jobNumberController.text,
      'projectNumber': projectNumberController.text,
    };
    
    if (currentInspectionId != null) {
      inspectionData['inspectionId'] = currentInspectionId;
    }

    final isNew = (_activeDoor == null);
    if (widget.isManagerMode) {
      final id = await DatabaseService.insertInspection(inspectionData);
      setState(() => currentInspectionId = id);

      if (isNew) {
        final insertedDoorId = await DatabaseService.insertDoor(door);
        _activeDoor = door.copyWith(id: insertedDoorId);
        await DatabaseService.insertInspectionDoor({
          'inspectionId': currentInspectionId,
          'doorId': insertedDoorId,
          'status': 'Inspected',
          'notes': notesController.text,
          'attachments': null,
        });
      } else {
        final updatedDoor = door.copyWith(id: _activeDoor!.id);
        await DatabaseService.updateDoor(updatedDoor);
        if (currentInspectionId != null && updatedDoor.id != null) {
          await DatabaseService.updateInspectionDoorStatus(
            inspectionId: currentInspectionId!,
            doorId: updatedDoor.id!,
            status: 'Inspected',
            notes: notesController.text,
          );
        }
      }
    } else {
      final id = await LocalDatabaseService.insertInspection(inspectionData);
      setState(() => currentInspectionId = id);

      if (isNew) {
        final insertedDoorId = await LocalDatabaseService.insertDoor(door);
        _activeDoor = door.copyWith(id: insertedDoorId);
        await LocalDatabaseService.insertInspectionDoor({
          'inspectionId': currentInspectionId,
          'doorId': insertedDoorId,
          'status': 'Inspected',
          'notes': notesController.text,
          'attachments': null,
        });
      } else {
        final updatedDoor = door.copyWith(id: _activeDoor!.id);
        await LocalDatabaseService.updateDoor(updatedDoor);
        if (currentInspectionId != null && updatedDoor.id != null) {
          await LocalDatabaseService.updateInspectionDoorStatus(
            inspectionId: currentInspectionId!,
            doorId: updatedDoor.id!,
            status: 'Inspected',
            notes: notesController.text,
          );
        }
      }
    }

    if (widget.isManagerMode) {
      DoorOptionsService.syncFromDoor(door);
      await DoorOptionsService.saveOptions();
    }

    if (mounted) Navigator.pop(context);
  }

  List<String> _getDropdownItems(String key, String? currentValue) {
    final list = DoorOptionsService.getStringOptions(key);
    if (currentValue != null && currentValue.isNotEmpty && !list.contains(currentValue)) {
      list.add(currentValue);
    }
    if (key.startsWith('lintelHeight')) {
      list.removeWhere((e) => e == '0,5' || e == '0.5');
      list.sort(DoorOptionsService.compareOptions);
    }
    return list;
  }

  String? _getDropdownValue(String key, String? currentValue) {
    final list = _getDropdownItems(key, currentValue);
    return list.contains(currentValue) ? currentValue : null;
  }

  List<int> _getIntDropdownItems(String key, int? currentValue) {
    final list = DoorOptionsService.getIntOptions(key);
    if (currentValue != null && !list.contains(currentValue)) {
      list.add(currentValue);
    }
    return list;
  }

  int? _getIntDropdownValue(String key, int? currentValue) {
    final list = _getIntDropdownItems(key, currentValue);
    return list.contains(currentValue) ? currentValue : null;
  }

  List<Map<String, String>> _getMapDropdownItems(String key, String? currentValue) {
    final list = DoorOptionsService.getMapOptions(key);
    if (currentValue != null && currentValue.isNotEmpty) {
      final hasValue = list.any((e) => e['value'] == currentValue);
      if (!hasValue) {
        list.add({'value': currentValue, 'label': currentValue});
      }
    }
    return list;
  }

  String? _getMapDropdownValue(String key, String? currentValue) {
    final list = _getMapDropdownItems(key, currentValue);
    final hasValue = list.any((e) => e['value'] == currentValue);
    return hasValue ? currentValue : null;
  }

  Future<String?> _showYearOnlyPickerDialog(BuildContext context, String currentYearStr) async {
    final DateTime now = DateTime.now();
    final int currentYearInt = int.tryParse(currentYearStr) ?? now.year;
    int selectedYear = currentYearInt;

    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Baujahr auswählen"),
          content: SizedBox(
            width: 300,
            height: 300,
            child: YearPicker(
              firstDate: DateTime(1900),
              lastDate: DateTime(now.year + 2),
              selectedDate: DateTime(selectedYear),
              onChanged: (DateTime dateTime) {
                Navigator.pop(dialogContext, dateTime.year.toString());
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, '?'),
              child: const Text('? (Unbekannt)'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, null),
              child: const Text('Abbrechen'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingOptions) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Türinspektion"),
        actions: [
          if (widget.door?.id != null || widget.door?.doorAlias != null)
            IconButton(
              icon: const Icon(Icons.history_edu),
              tooltip: 'Tür-Akte & Historie',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DoorHistoryPage(
                      doorId: widget.door?.id,
                      doorAlias: widget.door?.doorAlias,
                    ),
                  ),
                );
              },
            ),
          const MasterPortalHomeButton(),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isFormReadOnly)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_clock, color: Colors.orange.shade900),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Gesperrte Inspektion: Im Lesemodus. Änderungen können von Inspektoren nicht gespeichert werden.',
                        style: TextStyle(fontSize: 13, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            // Action buttons (Top)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _canSave ? () async {
                      await saveDoor();
                    } : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _canSave ? Colors.orange : Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(_isFormReadOnly ? 'Schreibgeschützt' : 'Speichern'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_activeDoor == null) {
                        if (!await _validateBarcodeUniqueness()) return;

                        // Persist new door draft first so errors can be linked to this specific door
                        final door = buildDoor();
                        final Map<String, dynamic> inspectionData = {
                          'clientName': customerNameController.text,
                          'objectAddress': customerAddressController.text,
                          'date': inspectionDate.toIso8601String(),
                          'contactPerson': contactPersonController.text,
                          'inspectorName': inspectorNameController.text,
                          'jobNumber': jobNumberController.text,
                          'projectNumber': projectNumberController.text,
                        };
                        if (currentInspectionId != null) {
                          inspectionData['inspectionId'] = currentInspectionId;
                        }
                        int insertedDoorId;
                        if (widget.isManagerMode) {
                          final id = await DatabaseService.insertInspection(inspectionData);
                          setState(() => currentInspectionId = id);
                          insertedDoorId = await DatabaseService.insertDoor(door);
                          await DatabaseService.insertInspectionDoor({
                            'inspectionId': currentInspectionId,
                            'doorId': insertedDoorId,
                            'status': 'Pending',
                            'notes': notesController.text,
                            'attachments': null,
                          });
                        } else {
                          final id = await LocalDatabaseService.insertInspection(inspectionData);
                          setState(() => currentInspectionId = id);
                          insertedDoorId = await LocalDatabaseService.insertDoor(door);
                          await LocalDatabaseService.insertInspectionDoor({
                            'inspectionId': currentInspectionId,
                            'doorId': insertedDoorId,
                            'status': 'Pending',
                            'notes': notesController.text,
                            'attachments': null,
                          });
                        }
                        setState(() {
                          _activeDoor = door.copyWith(id: insertedDoorId);
                        });
                      }

                      if (_activeDoor != null && currentInspectionId != null) {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ErrorManagementPage(
                              doorId: _activeDoor!.id!,
                              doorNumber: _activeDoor!.doorNumber.isNotEmpty ? _activeDoor!.doorNumber : doorNumberController.text,
                              inspectionId: currentInspectionId!,
                              isManagerMode: widget.isManagerMode,
                              isReadOnly: _isFormReadOnly,
                            ),
                          ),
                        );
                        await _syncErrorNotes();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Fehler verwalten'),
                  ),
                ),
              ],
            ),
            if (!_isFormReadOnly && !properFunction && _errorCount == 0) ...[
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
                        'Bewertung ist "Nein": Bitte fügen Sie mindestens einen Fehler über "Fehler verwalten" hinzu, um speichern zu können.',
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Inspection Metadata Section
            const Text("Inspektionsdaten", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            
            // Customer name
            TextField(
              controller: customerNameController,
              enabled: widget.isManagerMode && !_isFormReadOnly,
              decoration: InputDecoration(
                labelText: "Kundenname",
                helperText: !widget.isManagerMode ? "Schreibgeschützt für Inspektor" : null,
              ),
            ),
            
            // Customer address
            TextField(
              controller: customerAddressController,
              enabled: widget.isManagerMode && !_isFormReadOnly,
              decoration: InputDecoration(
                labelText: "Kundenadresse",
                helperText: !widget.isManagerMode ? "Schreibgeschützt für Inspektor" : null,
              ),
              maxLines: 2,
            ),
            
            // Contact person
            TextField(
              controller: contactPersonController,
              enabled: widget.isManagerMode && !_isFormReadOnly,
              decoration: InputDecoration(
                labelText: "Ansprechpartner",
                helperText: !widget.isManagerMode ? "Schreibgeschützt für Inspektor" : null,
              ),
            ),
            
            // Job number
            TextField(
              controller: jobNumberController,
              enabled: widget.isManagerMode && !_isFormReadOnly,
              decoration: InputDecoration(
                labelText: "Auftragsnummer",
                helperText: !widget.isManagerMode ? "Schreibgeschützt für Inspektor" : null,
              ),
            ),
            
            // Project number
            TextField(
              controller: projectNumberController,
              enabled: widget.isManagerMode && !_isFormReadOnly,
              decoration: InputDecoration(
                labelText: "Projektnummer",
                helperText: !widget.isManagerMode ? "Schreibgeschützt für Inspektor" : null,
              ),
            ),
            
            // Inspector name
            TextField(
              controller: inspectorNameController,
              enabled: widget.isManagerMode && !_isFormReadOnly,
              decoration: InputDecoration(
                labelText: "Inspektor",
                helperText: !widget.isManagerMode ? "Schreibgeschützt für Inspektor" : null,
              ),
            ),
            
            // Date Section: Exactly one date is displayed based on whether the event is a Reparatur or Wartung
            if (orderType == 'Reparatur' || (orderType == 'Erledigt' && repairDate != null))
              ListTile(
                title: Text(
                  "Reparaturdatum: ${repairDate != null ? '${repairDate!.day.toString().padLeft(2, '0')}.${repairDate!.month.toString().padLeft(2, '0')}.${repairDate!.year}' : '-'}",
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  orderType == 'Erledigt' ? "Instandsetzung abgeschlossen (Erledigt)" : "Instandsetzungsphase",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                  ),
                ),
                trailing: (widget.isManagerMode && !_isFormReadOnly)
                    ? IconButton(
                        icon: Icon(Icons.build, color: Colors.orange.shade800),
                        tooltip: 'Reparaturdatum ändern',
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: repairDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (date != null) {
                            setState(() => repairDate = date);
                          }
                        },
                      )
                    : null,
              )
            else
              ListTile(
                title: Text("Inspektionsdatum: ${inspectionDate.day.toString().padLeft(2, '0')}.${inspectionDate.month.toString().padLeft(2, '0')}.${inspectionDate.year}"),
                subtitle: !widget.isManagerMode ? const Text("Schreibgeschützt für Inspektor", style: TextStyle(fontSize: 12, color: Colors.grey)) : null,
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: (widget.isManagerMode && !_isFormReadOnly) ? () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: inspectionDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() => inspectionDate = date);
                    }
                  } : null,
                ),
              ),

            const SizedBox(height: 20),

            // Basic Information Section
            const Text("Grundinformationen", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            
            // Door number
            TextField(
              controller: doorNumberController,
              decoration: const InputDecoration(labelText: "Türnummer"),
            ),

            // Alias (Generated/Provisional Alias)
            TextField(
              controller: provisionalAliasController,
              enabled: widget.isManagerMode, // Read-only for Inspector, editable for Manager
              decoration: InputDecoration(
                labelText: "Alias",
                helperText: widget.isManagerMode 
                    ? "Automatisch erzeugter Alias (vom Manager bearbeitbar)"
                    : "Automatisch erzeugter Alias (schreibgeschützt für Inspektor)",
                prefixIcon: const Icon(Icons.pin, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),

            // Barcode (Physical Barcode / QR)
            TextField(
              controller: doorAliasController,
              enabled: true, // Editable at all times for inspector and manager
              maxLength: 32,
              onChanged: (val) {
                if (val.trim().isEmpty) {
                  isAliasManuallyEdited = false;
                  _updateGeneratedAlias();
                } else {
                  isAliasManuallyEdited = true;
                }
              },
              decoration: InputDecoration(
                labelText: "Barcode",
                helperText: "Physischer Barcode / QR-Code der Tür (jederzeit bearbeitbar)",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner, color: Colors.deepPurple),
                  tooltip: "Barcode / QR-Code scannen",
                  onPressed: () async {
                    final scanned = await BarcodeScannerDialog.show(
                      context,
                      title: 'Tür-Barcode scannen',
                    );
                    if (scanned != null && scanned.trim().isNotEmpty) {
                      final isUnique = await _validateBarcodeUniqueness(scanned.trim());
                      if (!isUnique) return;
                      setState(() {
                        doorAliasController.text = scanned.trim();
                        isAliasManuallyEdited = true;
                      });
                    }
                  },
                ),
              ),
            ),
            
            // Floor
            TextField(
              controller: floorController,
              decoration: const InputDecoration(labelText: "Geschoss"),
            ),
            
            // Room number
            TextField(
              controller: roomNumberController,
              decoration: const InputDecoration(labelText: "Raumnummer"),
            ),

            // Room designation
            TextField(
              controller: roomDesignationController,
              decoration: const InputDecoration(labelText: "Raumbezeichnung"),
            ),

            const SizedBox(height: 20),

            // Door Specifications Section
            const Text("Türspezifikationen", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            // Door type
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Türart"),
              initialValue: _getDropdownValue('doorType', doorType),
              items: _getDropdownItems('doorType', doorType)
                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                  .toList(),
              onChanged: (val) => setState(() => doorType = val),
            ),

            // Zulassungsnummer (Approval number)
            EditableDropdownField(
              label: "Zulassungsnummer",
              currentValue: approvalNumber,
              options: DoorOptionsService.getStringOptions('approvalNumber'),
              onChanged: (val) => setState(() => approvalNumber = val),
            ),

            // Hersteller (Manufacturer - Custom drop-down)
            EditableDropdownField(
              label: "Hersteller",
              currentValue: manufacturer,
              options: DoorOptionsService.getStringOptions('manufacturer'),
              onChanged: (val) => setState(() => manufacturer = val),
            ),

            // Herstellernummer (Manufacturer number - Placed directly below Hersteller)
            EditableDropdownField(
              label: "Herstellernummer",
              currentValue: manufacturerNumber,
              options: DoorOptionsService.getStringOptions('manufacturerNumber'),
              onChanged: (val) => setState(() => manufacturerNumber = val),
            ),

            // DoP-Nummer (Leistungserklärung) - Free alphanumeric field
            TextField(
              controller: dopNumberController,
              decoration: const InputDecoration(labelText: "DoP-Nummer (Leistungserklärung)"),
            ),

            // Baujahr (Year-only picker dialog)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text("Baujahr: $manufactureYear"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.calendar_today),
                    tooltip: 'Jahr auswählen',
                    onPressed: () async {
                      final year = await _showYearOnlyPickerDialog(context, manufactureYear);
                      if (year != null) {
                        setState(() => manufactureYear = year);
                      }
                    },
                  ),
                  TextButton(
                    onPressed: () => setState(() => manufactureYear = '?'),
                    child: const Text('? (Unbekannt)'),
                  ),
                ],
              ),
            ),

            // Wing count
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: "Flügelanzahl"),
              initialValue: _getIntDropdownValue('wingCount', wingCount),
              items: _getIntDropdownItems('wingCount', wingCount)
                  .map((val) => DropdownMenuItem(value: val, child: Text(val.toString())))
                  .toList(),
              onChanged: (val) => setState(() => wingCount = val ?? 1),
            ),

            // Material
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Material"),
              initialValue: _getDropdownValue('material', material),
              items: _getDropdownItems('material', material)
                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                  .toList(),
              onChanged: (val) => setState(() => material = val),
            ),

            // DIN configuration
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "DIN-Konfiguration"),
              initialValue: _getDropdownValue('dinConfiguration', dinConfiguration),
              items: _getDropdownItems('dinConfiguration', dinConfiguration)
                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                  .toList(),
              onChanged: (val) => setState(() => dinConfiguration = val),
            ),

            // Closer type
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Schließerart"),
              initialValue: _getMapDropdownValue('closerType', closerType),
              items: _getMapDropdownItems('closerType', closerType)
                  .map((map) => DropdownMenuItem(value: map['value']!, child: Text(map['label']!)))
                  .toList(),
              onChanged: (val) => setState(() => closerType = val),
            ),

            // Closing sequence system
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Schließfolgesystem"),
              initialValue: _getDropdownValue('closingSequenceSystem', closingSequenceSystem),
              items: _getDropdownItems('closingSequenceSystem', closingSequenceSystem)
                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                  .toList(),
              onChanged: (val) => setState(() => closingSequenceSystem = val),
            ),

            // Lock dimensions (Dynamic Combobox / Editable Dropdown)
            EditableDropdownField(
              label: "Schlossabmessungen",
              currentValue: lockDimensionsController.text.isNotEmpty ? lockDimensionsController.text : '?',
              options: DoorOptionsService.getStringOptions('lockDimensions'),
              onChanged: (val) => setState(() => lockDimensionsController.text = val),
            ),

            // Notizen (Türspezifikation) - Pop-Up Window Integration
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade400),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.notes, color: Theme.of(context).primaryColor, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            "Notizen & Mängelhinweise",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: _openNotesDialog,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(widget.isReadOnly == true ? "Notizen ansehen" : "In Pop-Up Fenster bearbeiten"),
                        style: ElevatedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _openNotesDialog,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 60),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        notesController.text.trim().isNotEmpty
                            ? notesController.text.trim()
                            : "(Keine Notizen erfasst. Klicken Sie hier oder auf den Pop-Up Button, um Notizen einzugeben...)",
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: notesController.text.trim().isNotEmpty
                              ? Theme.of(context).textTheme.bodyMedium?.color
                              : Colors.grey.shade600,
                          fontStyle: notesController.text.trim().isNotEmpty ? FontStyle.normal : FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Installation Section
            const Text("Installation", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            // Abnahme FSA / Antrieb (Datetime)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                "Abnahme FSA / Antrieb: ${fsaDriveAcceptanceDate != null && fsaDriveAcceptanceDate!.isNotEmpty ? fsaDriveAcceptanceDate : '? (Keine Abnahme)'}",
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.calendar_today),
                    tooltip: 'Datum auswählen',
                    onPressed: () async {
                      final initial = DateTime.tryParse(fsaDriveAcceptanceDate ?? '') ?? DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initial,
                        firstDate: DateTime(1970),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        final formatted = "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                        setState(() => fsaDriveAcceptanceDate = formatted);
                      }
                    },
                  ),
                  if (fsaDriveAcceptanceDate != null && fsaDriveAcceptanceDate!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Datum zurücksetzen',
                      onPressed: () => setState(() => fsaDriveAcceptanceDate = null),
                    ),
                ],
              ),
            ),

            // Lintel height / Closer position on hinge side
            SwitchListTile(
              title: const Text("Türschließer auf Bandseite"),
              value: closerOnHingeSide,
              onChanged: (val) => setState(() => closerOnHingeSide = val),
            ),

            // Lintel height / Closer position on opposite side
            SwitchListTile(
              title: const Text("Türschließer auf Bandgegenseite"),
              value: closerOnOppositeSide,
              onChanged: (val) => setState(() => closerOnOppositeSide = val),
            ),

            // Lintel height inside over 0,5m
            SwitchListTile(
              title: const Text("Sturzhöhe auf Bandseite innen über 0,5m"),
              value: lintelHeightInsideOver1m,
              onChanged: (val) => setState(() {
                lintelHeightInsideOver1m = val;
                if (!val) {
                  lintelHeightInsideValue = null;
                } else if (lintelHeightInsideValue == null) {
                  lintelHeightInsideValue = '0,5m';
                }
              }),
            ),

            // Dropdown menu for inside lintel height (visible only when lintelHeightInsideOver1m is true)
            if (lintelHeightInsideOver1m)
              Padding(
                padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0),
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: "Sturzhöhe innen (Meter)",
                    border: OutlineInputBorder(),
                  ),
                  value: _getDropdownValue('lintelHeightInsideValue', lintelHeightInsideValue),
                  items: _getDropdownItems('lintelHeightInsideValue', lintelHeightInsideValue)
                      .map((val) => DropdownMenuItem<String>(
                            value: val,
                            child: Text(val),
                          ))
                      .toList(),
                  onChanged: (val) => setState(() => lintelHeightInsideValue = val),
                ),
              ),

            // Lintel height outside over 0,5m
            SwitchListTile(
              title: const Text("Sturzhöhe auf Bandgegenseite außen über 0,5m"),
              value: lintelHeightOutsideOver1m,
              onChanged: (val) => setState(() {
                lintelHeightOutsideOver1m = val;
                if (!val) {
                  lintelHeightOutsideValue = null;
                } else if (lintelHeightOutsideValue == null) {
                  lintelHeightOutsideValue = '0,5m';
                }
              }),
            ),

            // Dropdown menu for outside lintel height (visible only when lintelHeightOutsideOver1m is true)
            if (lintelHeightOutsideOver1m)
              Padding(
                padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0),
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: "Sturzhöhe außen (Meter)",
                    border: OutlineInputBorder(),
                  ),
                  value: _getDropdownValue('lintelHeightOutsideValue', lintelHeightOutsideValue),
                  items: _getDropdownItems('lintelHeightOutsideValue', lintelHeightOutsideValue)
                      .map((val) => DropdownMenuItem<String>(
                            value: val,
                            child: Text(val),
                          ))
                      .toList(),
                  onChanged: (val) => setState(() => lintelHeightOutsideValue = val),
                ),
              ),

            const SizedBox(height: 20),

            // Safety & Security Section
            const Text("Sicherheit & Zugang", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            // Access control (Dynamic Combobox / Editable Dropdown)
            EditableDropdownField(
              label: "Zutrittskontrolle",
              currentValue: accessControl ?? 'Nein',
              options: DoorOptionsService.getStringOptions('accessControl'),
              onChanged: (val) => setState(() => accessControl = val),
            ),

            // Escape door control (Dynamic Combobox / Editable Dropdown)
            EditableDropdownField(
              label: "Fluchttürsteuerung / Türwächter",
              currentValue: escapeDoorControl ?? 'Nein',
              options: DoorOptionsService.getStringOptions('escapeDoorControl'),
              onChanged: (val) => setState(() => escapeDoorControl = val),
            ),

            // Escape route situation
            SwitchListTile(
              title: const Text("Fluchtwegsituation"),
              value: escapeRouteSituation,
              onChanged: (val) => setState(() => escapeRouteSituation = val),
            ),

            // Escape route signage
            SwitchListTile(
              title: const Text("Fluchtwegbeschilderung vorhanden?"),
              value: escapeSignage,
              onChanged: (val) => setState(() => escapeSignage = val),
            ),

            // Blind cylinder
            SwitchListTile(
              title: const Text("Blindzylinder"),
              value: blindCylinder,
              onChanged: (val) => setState(() => blindCylinder = val),
            ),

            // PZ cylinder
            SwitchListTile(
              title: const Text("PZ-Zylinder"),
              value: pzCylinder,
              onChanged: (val) => setState(() => pzCylinder = val),
            ),

            // Fitting type
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Beschlagart"),
              initialValue: _getDropdownValue('fittingType', fittingType),
              items: _getDropdownItems('fittingType', fittingType)
                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                  .toList(),
              onChanged: (val) => setState(() => fittingType = val),
            ),

            // Panic function
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Panikfunktion"),
              initialValue: _getDropdownValue('panicFunction', panicFunction),
              items: _getDropdownItems('panicFunction', panicFunction)
                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                  .toList(),
              onChanged: (val) => setState(() => panicFunction = val),
            ),

            // Escape direction respected
            SwitchListTile(
              title: const Text("Fluchtrichtung beachtet"),
              value: escapeDirectionRespected,
              onChanged: (val) => setState(() => escapeDirectionRespected = val),
            ),

            // Full panic stand wing
            SwitchListTile(
              title: const Text("Vollpanik-Standflügel"),
              value: fullPanicStandWing,
              onChanged: (val) => setState(() => fullPanicStandWing = val),
            ),

            const SizedBox(height: 20),

            // Final Status Section
            const Text("Bewertung", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            // Door function OK
            SwitchListTile(
              title: const Text("Tür inkl. Komponenten in ordentlicher Funktion"),
              subtitle: Text(
                properFunction
                    ? (_openErrorCount > 0
                        ? "Ja (Warnung: $_openErrorCount offene Mängel!)"
                        : (_errorCount > 0 ? "Ja (Alle Mängel gelöst/behoben)" : "Ja (Keine Mängel)"))
                    : (_openErrorCount > 0
                        ? "Nein ($_openErrorCount offene Mängel)"
                        : "Nein (Mängel müssen erfasst werden)"),
                style: TextStyle(
                  fontSize: 12,
                  color: properFunction
                      ? (_openErrorCount > 0 ? Colors.red.shade700 : Colors.green.shade700)
                      : (_openErrorCount > 0 ? Colors.orange.shade800 : Colors.red.shade700),
                ),
              ),
              value: properFunction,
              onChanged: (val) => setState(() => properFunction = val),
            ),
            if (!_isFormReadOnly && properFunction && _openErrorCount > 0) ...[
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 4),
                child: Text(
                  'Hinweis: Die Tür ist als ordnungsgemäß (Ja) markiert, hat aber noch $_openErrorCount offene Mängel. Bitte Mängel auf "Gelöst" setzen oder Bewertung auf "Nein" ändern, um speichern zu können.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ] else if (!_isFormReadOnly && !properFunction && _openErrorCount == 0) ...[
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 4),
                child: Text(
                  'Hinweis: Da die Tür nicht als ordnungsgemäß bewertet ist, muss mindestens ein offener Mangel über "Fehler verwalten" hinzugefügt werden, um zu speichern.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
