class RwaSystem {
  final int? id;
  final String? systemAlias; // e.g. "Anlage 1 - M-PIC-Ost", physical barcode or assigned alias
  final String? provisionalAlias; // Auto-generated alias: RWA-[ProjectNumber]-[Number]
  final String projectNumber;
  final String systemType; // "elektromotorisch / CO2", "CO2", "elektromotorisch", etc.
  final String objectAddress; // e.g. "Hohe-Schar-Str. 36, 21107 Hamburg"
  final String building; // e.g. "Gebäude G", "Gebäude C"
  final String floor; // e.g. "Dach", "EG", "1.OG"
  final String room; // e.g. "Treppenhaus 2", "Town Hall", "Lubes-Blending"
  final String centralType; // Zentrale Fabrikat / Typ
  final String fireButtonSpec; // Feuertaster Spezifikation / Anzahl
  final String smokeDetectorSpec; // Rauch/Wärmemelder Spezifikation
  final String actuatorSpec; // Antriebe Spezifikation
  final String ventilationButtonSpec; // Lüftungstaster Spezifikation
  final String emergencyPowerSpec; // Notstrombatterie Spezifikation
  final String co2BottleSpec; // CO2- Flaschen Spezifikation
  final String thermalBottleSpec; // Thermoflasche Spezifikation
  final String rwaFlapSpec; // RWA-Klappen Spezifikation
  final String ventilationFlapSpec; // Lüftungsklappen Spezifikation
  final String damperSpec; // Dämpfer Spezifikation
  final bool systemFunctionOK; // Anlage in Ordnung (Gesamtstatus)
  final String notes;

  RwaSystem({
    this.id,
    this.systemAlias,
    this.provisionalAlias,
    required this.projectNumber,
    required this.systemType,
    required this.objectAddress,
    this.building = '',
    this.floor = '',
    this.room = '',
    this.centralType = '',
    this.fireButtonSpec = '',
    this.smokeDetectorSpec = '',
    this.actuatorSpec = '',
    this.ventilationButtonSpec = '',
    this.emergencyPowerSpec = '',
    this.co2BottleSpec = '',
    this.thermalBottleSpec = '',
    this.rwaFlapSpec = '',
    this.ventilationFlapSpec = '',
    this.damperSpec = '',
    this.systemFunctionOK = true,
    this.notes = '',
  });

  RwaSystem copyWith({
    int? id,
    String? systemAlias,
    String? provisionalAlias,
    String? projectNumber,
    String? systemType,
    String? objectAddress,
    String? building,
    String? floor,
    String? room,
    String? centralType,
    String? fireButtonSpec,
    String? smokeDetectorSpec,
    String? actuatorSpec,
    String? ventilationButtonSpec,
    String? emergencyPowerSpec,
    String? co2BottleSpec,
    String? thermalBottleSpec,
    String? rwaFlapSpec,
    String? ventilationFlapSpec,
    String? damperSpec,
    bool? systemFunctionOK,
    String? notes,
  }) {
    return RwaSystem(
      id: id ?? this.id,
      systemAlias: systemAlias ?? this.systemAlias,
      provisionalAlias: provisionalAlias ?? this.provisionalAlias,
      projectNumber: projectNumber ?? this.projectNumber,
      systemType: systemType ?? this.systemType,
      objectAddress: objectAddress ?? this.objectAddress,
      building: building ?? this.building,
      floor: floor ?? this.floor,
      room: room ?? this.room,
      centralType: centralType ?? this.centralType,
      fireButtonSpec: fireButtonSpec ?? this.fireButtonSpec,
      smokeDetectorSpec: smokeDetectorSpec ?? this.smokeDetectorSpec,
      actuatorSpec: actuatorSpec ?? this.actuatorSpec,
      ventilationButtonSpec: ventilationButtonSpec ?? this.ventilationButtonSpec,
      emergencyPowerSpec: emergencyPowerSpec ?? this.emergencyPowerSpec,
      co2BottleSpec: co2BottleSpec ?? this.co2BottleSpec,
      thermalBottleSpec: thermalBottleSpec ?? this.thermalBottleSpec,
      rwaFlapSpec: rwaFlapSpec ?? this.rwaFlapSpec,
      ventilationFlapSpec: ventilationFlapSpec ?? this.ventilationFlapSpec,
      damperSpec: damperSpec ?? this.damperSpec,
      systemFunctionOK: systemFunctionOK ?? this.systemFunctionOK,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'systemAlias': systemAlias,
        'provisionalAlias': provisionalAlias,
        'projectNumber': projectNumber,
        'systemType': systemType,
        'objectAddress': objectAddress,
        'building': building,
        'floor': floor,
        'room': room,
        'centralType': centralType,
        'fireButtonSpec': fireButtonSpec,
        'smokeDetectorSpec': smokeDetectorSpec,
        'actuatorSpec': actuatorSpec,
        'ventilationButtonSpec': ventilationButtonSpec,
        'emergencyPowerSpec': emergencyPowerSpec,
        'co2BottleSpec': co2BottleSpec,
        'thermalBottleSpec': thermalBottleSpec,
        'rwaFlapSpec': rwaFlapSpec,
        'ventilationFlapSpec': ventilationFlapSpec,
        'damperSpec': damperSpec,
        'systemFunctionOK': systemFunctionOK ? 1 : 0,
        'notes': notes,
      };

  factory RwaSystem.fromMap(Map<String, dynamic> map) => RwaSystem(
        id: map['id'],
        systemAlias: map['systemAlias'],
        provisionalAlias: map['provisionalAlias'],
        projectNumber: map['projectNumber'] ?? '',
        systemType: map['systemType'] ?? '',
        objectAddress: map['objectAddress'] ?? '',
        building: map['building'] ?? '',
        floor: map['floor'] ?? '',
        room: map['room'] ?? '',
        centralType: map['centralType'] ?? '',
        fireButtonSpec: map['fireButtonSpec'] ?? '',
        smokeDetectorSpec: map['smokeDetectorSpec'] ?? '',
        actuatorSpec: map['actuatorSpec'] ?? '',
        ventilationButtonSpec: map['ventilationButtonSpec'] ?? '',
        emergencyPowerSpec: map['emergencyPowerSpec'] ?? '',
        co2BottleSpec: map['co2BottleSpec'] ?? '',
        thermalBottleSpec: map['thermalBottleSpec'] ?? '',
        rwaFlapSpec: map['rwaFlapSpec'] ?? '',
        ventilationFlapSpec: map['ventilationFlapSpec'] ?? '',
        damperSpec: map['damperSpec'] ?? '',
        systemFunctionOK: map['systemFunctionOK'] == 1 || map['systemFunctionOK'] == true,
        notes: map['notes'] ?? '',
      );

  String get effectiveAlias =>
      (systemAlias != null && systemAlias!.trim().isNotEmpty)
          ? systemAlias!
          : (provisionalAlias ?? 'RWA-$id');

  String get displayAlias => effectiveAlias;

  @override
  String toString() =>
      'RwaSystem(id: $id, alias: $effectiveAlias, type: $systemType, address: $objectAddress)';
}
