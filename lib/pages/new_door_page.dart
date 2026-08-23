import 'package:flutter/material.dart';
import '../services/local_database_service.dart';
import '../services/database_service.dart';
import '../services/door_options_service.dart';
import '../models/models.dart';
import 'error_management_page.dart';

class DoorInspectionForm extends StatefulWidget {
  final Door? door; // null = create mode
  final bool isManagerMode;
  final int? inspectionId;
 
  const DoorInspectionForm({
    super.key,
    this.door,
    this.isManagerMode = false,
    this.inspectionId,
  });

  @override
  _DoorInspectionFormState createState() => _DoorInspectionFormState();
}

class _DoorInspectionFormState extends State<DoorInspectionForm> {
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
  late TextEditingController manufacturerController;
  late TextEditingController lockDimensionsController;
  late TextEditingController doorAliasController;
  bool isAliasManuallyEdited = false;

  // Boolean states
  bool escapeSignage = false;
  bool escapeDoorControl = false;
  bool properFunction = false;
  bool blindCylinder = false;
  bool pzCylinder = false;
  bool closerOnHingeSide = false;
  bool closerOnOppositeSide = false;
  bool lintelHeightUnder1m = false;
  bool escapeRouteSituation = false;
  bool escapeDirectionRespected = false;
  bool fullPanicStandWing = false;

  // Dropdowns
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
  int? currentInspectionId;
  bool _isLoadingOptions = true;

  @override
  void initState() {
    super.initState();
    _loadOptionsAndData();
  }

  Future<void> _loadOptionsAndData() async {
    await DoorOptionsService.ensureLoaded();

    final d = widget.door;

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
    manufacturerController = TextEditingController(text: d?.manufacturer ?? '');
    lockDimensionsController = TextEditingController(text: d?.lockDimensions ?? '');
    doorAliasController = TextEditingController(text: d?.doorAlias ?? '');

    if (d?.doorAlias != null && d!.doorAlias!.isNotEmpty) {
      isAliasManuallyEdited = true;
    }

    if (d == null) {
      void updateAlias() {
        if (!isAliasManuallyEdited) {
          doorAliasController.text = Door.generateAlias(
            customerNameController.text,
            customerAddressController.text,
            doorNumberController.text,
            floor: floorController.text,
          );
        }
      }
      customerNameController.addListener(updateAlias);
      customerAddressController.addListener(updateAlias);
      doorNumberController.addListener(updateAlias);
      floorController.addListener(updateAlias);
    }

    doorAliasController.addListener(() {
      final expected = Door.generateAlias(
        customerNameController.text,
        customerAddressController.text,
        doorNumberController.text,
        floor: floorController.text,
      );
      if (doorAliasController.text != expected && doorAliasController.text.isNotEmpty) {
        isAliasManuallyEdited = true;
      }
    });

    // Initialize booleans
    escapeSignage = d?.escapeRouteSignage ?? false;
    escapeDoorControl = d?.escapeDoorControl ?? false;
    properFunction = d?.doorFunctionOK ?? false;
    blindCylinder = d?.blindCylinder ?? false;
    pzCylinder = d?.pzCylinder ?? false;
    closerOnHingeSide = d?.closerOnHingeSide ?? false;
    closerOnOppositeSide = d?.closerOnOppositeSide ?? false;
    lintelHeightUnder1m = d?.lintelHeightUnder1m ?? false;
    escapeRouteSituation = d?.escapeRouteSituation ?? false;
    escapeDirectionRespected = d?.escapeDirectionRespected ?? false;
    fullPanicStandWing = d?.fullPanicStandWing ?? false;

    // Initialize dropdowns (use defaults from config file if creating a new door)
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

    if (d != null) {
      await _loadInspectionData();
    }

    if (mounted) {
      setState(() {
        _isLoadingOptions = false;
      });
    }
  }

  @override
  void dispose() {
    doorAliasController.dispose();
    projectNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadInspectionData() async {
    // Select correct database based on role
    final db = widget.isManagerMode 
        ? await DatabaseService.getDb() 
        : await LocalDatabaseService.getDb();
        
    List<Map<String, dynamic>> results;
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

    if (results.isNotEmpty) {
      final insp = results.first;
      setState(() {
        currentInspectionId = widget.inspectionId ?? insp['inspectionId'];
        customerNameController.text = insp['clientName'] ?? '';
        customerAddressController.text = insp['objectAddress'] ?? '';
        contactPersonController.text = insp['contactPerson'] ?? '';
        jobNumberController.text = insp['jobNumber'] ?? '';
        projectNumberController.text = insp['projectNumber'] ?? '';
        inspectorNameController.text = insp['inspectorName'] ?? '';
        inspectionDate = DateTime.tryParse(insp['date'] ?? '') ?? DateTime.now();
      });
    } else if (widget.inspectionId != null) {
      setState(() {
        currentInspectionId = widget.inspectionId;
      });
    }
  }

  // Build a Door object from form fields
  Door buildDoor() {
    String alias = doorAliasController.text.trim();
    if (alias.isEmpty) {
      alias = Door.generateAlias(
        customerNameController.text,
        customerAddressController.text,
        doorNumberController.text,
        floor: floorController.text,
      );
    }
    return Door(
      id: widget.door?.id, // Leave null for new doors to allow AUTOINCREMENT
      pos: pos,
      doorAlias: alias,
      doorNumber: doorNumberController.text,
      floor: floorController.text,
      roomNumber: roomNumberController.text,
      roomDesignation: roomDesignationController.text,
      doorType: doorType ?? DoorOptionsService.getDefault('doorType') ?? 'T30',
      wingCount: wingCount,
      material: material ?? DoorOptionsService.getDefault('material') ?? 'Stahl',
      manufacturer: manufacturerController.text,
      dinConfiguration: dinConfiguration ?? DoorOptionsService.getDefault('dinConfiguration') ?? 'DIN L',
      closerType: closerType ?? DoorOptionsService.getDefault('closerType') ?? 'TS93',
      closingSequenceSystem: closingSequenceSystem ?? DoorOptionsService.getDefault('closingSequenceSystem') ?? 'None',
      lockDimensions: lockDimensionsController.text,
      closerOnHingeSide: closerOnHingeSide,
      closerOnOppositeSide: closerOnOppositeSide,
      lintelHeightUnder1m: lintelHeightUnder1m,
      escapeDoorControl: escapeDoorControl,
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
    );
  }

  Future<void> saveDoor() async {
    final door = buildDoor();
    
    // Save Inspection Metadata first
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

    if (widget.isManagerMode) {
      final id = await DatabaseService.insertInspection(inspectionData);
      setState(() => currentInspectionId = id);

      if (widget.door == null) {
        final insertedDoorId = await DatabaseService.insertDoor(door);
        await DatabaseService.insertInspectionDoor({
          'inspectionId': currentInspectionId,
          'doorId': insertedDoorId,
          'status': 'InProgress',
          'notes': '',
          'attachments': null,
        });
      } else {
        await DatabaseService.updateDoor(door);
      }
    } else {
      final id = await LocalDatabaseService.insertInspection(inspectionData);
      setState(() => currentInspectionId = id);

      if (widget.door == null) {
        final insertedDoorId = await LocalDatabaseService.insertDoor(door);
        await LocalDatabaseService.insertInspectionDoor({
          'inspectionId': currentInspectionId,
          'doorId': insertedDoorId,
          'status': 'InProgress',
          'notes': '',
          'attachments': null,
        });
      } else {
        await LocalDatabaseService.updateDoor(door);
      }
    }

    if (mounted) Navigator.pop(context);
  }

  List<String> _getDropdownItems(String key, String? currentValue) {
    final list = DoorOptionsService.getStringOptions(key);
    if (currentValue != null && currentValue.isNotEmpty && !list.contains(currentValue)) {
      list.add(currentValue);
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
      appBar: AppBar(title: const Text("Türinspektion")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Inspection Metadata Section
            const Text("Inspektionsdaten", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            
            // Customer name
            TextField(
              controller: customerNameController,
              decoration: const InputDecoration(labelText: "Kundenname"),
            ),
            
            // Customer address
            TextField(
              controller: customerAddressController,
              decoration: const InputDecoration(labelText: "Kundenadresse"),
              maxLines: 2,
            ),
            
            // Contact person
            TextField(
              controller: contactPersonController,
              decoration: const InputDecoration(labelText: "Ansprechpartner"),
            ),
            
            // Job number
            TextField(
              controller: jobNumberController,
              decoration: const InputDecoration(labelText: "Auftragsnummer"),
            ),
            
            // Project number
            TextField(
              controller: projectNumberController,
              decoration: const InputDecoration(labelText: "Projektnummer"),
            ),
            
            // Inspector name
            TextField(
              controller: inspectorNameController,
              decoration: const InputDecoration(labelText: "Inspektor"),
            ),
            
            // Inspection date
            ListTile(
              title: Text("Inspektionsdatum: ${inspectionDate.day.toString().padLeft(2, '0')}.${inspectionDate.month.toString().padLeft(2, '0')}.${inspectionDate.year}"),
              trailing: IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: inspectionDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setState(() => inspectionDate = date);
                  }
                },
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

            // Door Alias (Barcode / Unique ID)
            TextField(
              controller: doorAliasController,
              enabled: true, // Editable by Inspector (first physical inspection barcode scan) and Manager
              maxLength: 12,
              decoration: const InputDecoration(
                labelText: "Tür-Identität (Alias / Barcode)",
                helperText: "Dauerhafte, eindeutige ID (z.B. Barcode bei Erstprüfung)",
                suffixIcon: Icon(Icons.qr_code_scanner),
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

            // Manufacturer
            TextField(
              controller: manufacturerController,
              decoration: const InputDecoration(labelText: "Hersteller"),
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

            // Lock dimensions
            TextField(
              controller: lockDimensionsController,
              decoration: const InputDecoration(labelText: "Schlossabmessungen"),
            ),

            const SizedBox(height: 20),

            // Installation Section
            const Text("Installation", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            // Closer on hinge side
            SwitchListTile(
              title: const Text("Schließer auf Bandseite"),
              value: closerOnHingeSide,
              onChanged: (val) => setState(() => closerOnHingeSide = val),
            ),

            // Closer on opposite side
            SwitchListTile(
              title: const Text("Schließer auf Gegenseite"),
              value: closerOnOppositeSide,
              onChanged: (val) => setState(() => closerOnOppositeSide = val),
            ),

            // Lintel height under 1m
            SwitchListTile(
              title: const Text("Sturzhöhe unter 1m"),
              value: lintelHeightUnder1m,
              onChanged: (val) => setState(() => lintelHeightUnder1m = val),
            ),

            const SizedBox(height: 20),

            // Safety & Security Section
            const Text("Sicherheit & Zugang", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            // Access control
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Zutrittskontrolle"),
              initialValue: _getDropdownValue('accessControl', accessControl),
              items: _getDropdownItems('accessControl', accessControl)
                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                  .toList(),
              onChanged: (val) => setState(() => accessControl = val),
            ),

            // Escape door control
            SwitchListTile(
              title: const Text("Fluchttürsteuerung"),
              value: escapeDoorControl,
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
              value: properFunction,
              onChanged: (val) => setState(() => properFunction = val),
            ),

            const SizedBox(height: 30),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await saveDoor();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: Text('Speichern'),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (widget.door != null && currentInspectionId != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ErrorManagementPage(
                              doorId: widget.door!.id!,
                              doorNumber: widget.door!.doorNumber,
                              inspectionId: currentInspectionId!,
                              isManagerMode: widget.isManagerMode,
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Bitte speichern Sie zuerst die Tür')),
                        );
                      }
                    },
                    child: const Text('Fehler verwalten'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
