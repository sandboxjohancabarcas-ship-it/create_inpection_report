import 'package:flutter/material.dart';
import '../services/local_database_service.dart';
import '../models/models.dart';
import 'error_management_page.dart';

class DoorInspectionForm extends StatefulWidget {
  final Door? door; // null = create mode

  const DoorInspectionForm({super.key, this.door});

  @override
  _DoorInspectionFormState createState() => _DoorInspectionFormState();
}

class _DoorInspectionFormState extends State<DoorInspectionForm> {
  // Controllers for inspection metadata
  late TextEditingController customerNameController;
  late TextEditingController customerAddressController;
  late TextEditingController contactPersonController;
  late TextEditingController jobNumberController;
  late TextEditingController inspectorNameController;
  
  // Controllers for door technical fields
  late TextEditingController doorNumberController;
  late TextEditingController roomDesignationController;
  late TextEditingController floorController;
  late TextEditingController roomNumberController;
  late TextEditingController manufacturerController;
  late TextEditingController lockDimensionsController;

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

  @override
  void initState() {
    super.initState();

    final d = widget.door;

       // Note: These will now be handled separately from the Door object
    customerNameController = TextEditingController();
    customerAddressController = TextEditingController();
    contactPersonController = TextEditingController();
    jobNumberController = TextEditingController();
    inspectorNameController = TextEditingController();


    // Initialize door technical controllers
    doorNumberController = TextEditingController(text: d?.doorNumber ?? '');
    roomDesignationController = TextEditingController(text: d?.roomDesignation ?? '');
    floorController = TextEditingController(text: d?.floor ?? '');
    roomNumberController = TextEditingController(text: d?.roomNumber ?? '');
    manufacturerController = TextEditingController(text: d?.manufacturer ?? '');
    lockDimensionsController = TextEditingController(text: d?.lockDimensions ?? '');

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

    // Initialize dropdowns
    accessControl = d?.accessControl;
    panicFunction = d?.panicFunction;
    doorType = d?.doorType;
    material = d?.material;
    dinConfiguration = d?.dinConfiguration;
    closerType = d?.closerType;
    closingSequenceSystem = d?.closingSequenceSystem;
    fittingType = d?.fittingType;

    // Initialize numeric fields
    wingCount = d?.wingCount ?? 1;
    pos = d?.pos ?? 0;
  }

  // Build a Door object from form fields
  Door buildDoor() {
    return Door(
      id: widget.door?.id ?? DateTime.now().millisecondsSinceEpoch,
      pos: pos,
      doorNumber: doorNumberController.text,
      floor: floorController.text,
      roomNumber: roomNumberController.text,
      roomDesignation: roomDesignationController.text,
      doorType: doorType ?? 'T30',
      wingCount: wingCount,
      material: material ?? 'Stahl',
      manufacturer: manufacturerController.text,
      dinConfiguration: dinConfiguration ?? 'DIN L',
      closerType: closerType ?? 'Standard',
      closingSequenceSystem: closingSequenceSystem ?? 'Keine',
      lockDimensions: lockDimensionsController.text,
      closerOnHingeSide: closerOnHingeSide,
      closerOnOppositeSide: closerOnOppositeSide,
      lintelHeightUnder1m: lintelHeightUnder1m,
      escapeDoorControl: escapeDoorControl,
      accessControl: accessControl ?? 'Nein',
      escapeRouteSituation: escapeRouteSituation,
      escapeRouteSignage: escapeSignage,
      blindCylinder: blindCylinder,
      pzCylinder: pzCylinder,
      fittingType: fittingType ?? 'Drückergarnitur',
      panicFunction: panicFunction ?? 'Nein',
      escapeDirectionRespected: escapeDirectionRespected,
      fullPanicStandWing: fullPanicStandWing,
      doorFunctionOK: properFunction,
      syncStatus: widget.door?.syncStatus ?? 'pending',  // Set to 'pending' for new doors
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
      'auftragsnummer': jobNumberController.text,
      'syncStatus': 'pending',
    };
    
    if (currentInspectionId != null) {
      inspectionData['inspectionId'] = currentInspectionId;
    }

    final id = await LocalDatabaseService.insertInspection(inspectionData);
    setState(() => currentInspectionId = id);

    if (widget.door == null) {
      final insertedDoorId = await LocalDatabaseService.insertDoor(door);
      // Link the newly created door to the inspection
      await LocalDatabaseService.insertInspectionDoor({
        'inspectionId': currentInspectionId,
        'doorId': insertedDoorId,
        'status': 'InProgress', // Default status for a new inspection door
        'notes': '',
        'attachments': null,
        'syncStatus': 'pending',
      });
    } else {
      await LocalDatabaseService.updateDoor(door.toMap());
      // For existing doors, we assume the linkage already exists or is handled elsewhere.
      // If an existing door is being edited, its inspectionId should already be known.
      // For simplicity, we're not re-creating inspection_doors for updates here.
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
              initialValue: doorType,
              items: ["T30", "T60", "T90", "RS", "Sonstige"]
                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                  .toList(),
              onChanged: (val) => setState(() => doorType = val),
            ),

            // Wing count
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: "Flügelanzahl"),
              initialValue: wingCount,
              items: [1, 2, 3]
                  .map((val) => DropdownMenuItem(value: val, child: Text(val.toString())))
                  .toList(),
              onChanged: (val) => setState(() => wingCount = val ?? 1),
            ),

            // Material
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Material"),
              initialValue: material,
              items: ["Stahl", "Aluminium", "Holz", "Kunststoff", "Glas"]
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
              initialValue: dinConfiguration,
              items: ["DIN L", "DIN R", "DIN LR", "Ohne"]
                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                  .toList(),
              onChanged: (val) => setState(() => dinConfiguration = val),
            ),

            // Closer type
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Schließerart"),
              initialValue: closerType,
              items: ["Standard", "Überkopf", "Boden", "Feststell"]
                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                  .toList(),
              onChanged: (val) => setState(() => closerType = val),
            ),

            // Closing sequence system
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Schließfolgesystem"),
              initialValue: closingSequenceSystem,
              items: ["Keine", "Einfach", "Doppel", "Mehrfach"]
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
              initialValue: accessControl,
              items: ["HID multiclass SE", "Nein", "Primion", "Siedle"]
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
              initialValue: fittingType,
              items: ["Drückergarnitur", "Knaufgarnitur", "Hebelgarnitur", "Sonstige"]
                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                  .toList(),
              onChanged: (val) => setState(() => fittingType = val),
            ),

            // Panic function
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Panikfunktion"),
              initialValue: panicFunction,
              items: ["A", "B", "E", "Nein"]
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
                      if (widget.door != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ErrorManagementPage(
                              doorId: widget.door!.id,
                              doorNumber: widget.door!.doorNumber,
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Bitte speichern Sie zuerst die Tür')),
                        );
                      }
                    },
                    child: Text('Fehler verwalten'),
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
