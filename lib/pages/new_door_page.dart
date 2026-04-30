import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/models.dart';

class DoorInspectionForm extends StatefulWidget {
  final Door? door; // null = create mode

  const DoorInspectionForm({super.key, this.door});

  @override
  _DoorInspectionFormState createState() => _DoorInspectionFormState();
}

class _DoorInspectionFormState extends State<DoorInspectionForm> {
  // Controllers for text fields (add more as needed)
  late TextEditingController doorNumberController;
  late TextEditingController roomDesignationController;

  // Boolean states
  bool escapeSignage = false;
  bool escapeDoorControl = false;
  bool properFunction = false;
  bool blindCylinder = false;
  bool pzCylinder = false;

  // Dropdowns
  String? accessControl;
  String? panicFunction;

  @override
  void initState() {
    super.initState();

    final d = widget.door;

    // Initialize controllers with DB values or empty
    doorNumberController = TextEditingController(text: d?.doorNumber ?? '');
    roomDesignationController =
        TextEditingController(text: d?.roomDesignation ?? '');

    // Initialize booleans
    escapeSignage = d?.escapeRouteSignage ?? false;
    escapeDoorControl = d?.escapeDoorControl ?? false;
    properFunction = d?.doorFunctionOK ?? false;
    blindCylinder = d?.blindCylinder ?? false;
    pzCylinder = d?.pzCylinder ?? false;

    // Dropdowns
    accessControl = d?.accessControl;
    panicFunction = d?.panicFunction;
  }

  // Build a Door object from the form fields
  Door buildDoor() {
    return Door(
      id: widget.door?.id ?? DateTime.now().millisecondsSinceEpoch,
      pos: widget.door?.pos ?? 0,
      doorNumber: doorNumberController.text,
      floor: '1',
      roomNumber: '101',
      roomDesignation: roomDesignationController.text,
      doorType: 'T30',
      wingCount: 1,
      material: 'Steel',
      manufacturer: 'Hörmann',
      dinConfiguration: 'DIN L',
      closerType: 'Standard',
      closingSequenceSystem: 'None',
      lockDimensions: '72mm',
      closerOnHingeSide: false,
      closerOnOppositeSide: false,
      lintelHeightUnder1m: false,
      escapeDoorControl: escapeDoorControl,
      accessControl: accessControl ?? 'None',
      escapeRouteSituation: true,
      escapeRouteSignage: escapeSignage,
      blindCylinder: blindCylinder,
      pzCylinder: pzCylinder,
      fittingType: 'Drückergarnitur',
      panicFunction: panicFunction ?? 'B',
      escapeDirectionRespected: true,
      fullPanicStandWing: false,
      doorFunctionOK: properFunction,
    );
  }

  Future<void> saveDoor() async {
    final door = buildDoor();

    if (widget.door == null) {
      await DatabaseService.insertDoor(door);
    } else {
      await DatabaseService.updateDoor(door);
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
          children: [
            // Door number
            TextField(
              controller: doorNumberController,
              decoration: const InputDecoration(labelText: "Türnummer"),
            ),

            // Room designation
            TextField(
              controller: roomDesignationController,
              decoration: const InputDecoration(labelText: "Raumbezeichnung"),
            ),

            const SizedBox(height: 20),

            // Dropdown: Zutrittskontrolle
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Zutrittskontrolle"),
              value: accessControl,
              items: ["HID multiclass SE", "Nein", "Primion", "Siedle"]
                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                  .toList(),
              onChanged: (val) => setState(() => accessControl = val),
            ),

            // Switch: Fluchtwegbeschilderung
            SwitchListTile(
              title: const Text("Fluchtwegbeschilderung vorhanden?"),
              value: escapeSignage,
              onChanged: (val) => setState(() => escapeSignage = val),
            ),

            // Dropdown: Panikfunktion
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Panikfunktion"),
              value: panicFunction,
              items: ["B", "E", "Nein"]
                  .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                  .toList(),
              onChanged: (val) => setState(() => panicFunction = val),
            ),

            // Switch: Türfunktion OK
            SwitchListTile(
              title: const Text("Tür inkl. Komponenten in ordentlicher Funktion"),
              value: properFunction,
              onChanged: (val) => setState(() => properFunction = val),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: saveDoor,
              child: Text(widget.door == null ? "Speichern" : "Aktualisieren"),
            ),
          ],
        ),
      ),
    );
  }
}
