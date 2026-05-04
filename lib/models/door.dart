class Door {
  // Inspection Metadata
  final String customerName;
  final String customerAddress;
  final String contactPerson;
  final String jobNumber;
  final DateTime inspectionDate;
  final String inspectorName;
  
  // Door Technical Specifications
  final int id;
  final int pos;
  final String doorNumber;
  final String floor;
  final String roomNumber;
  final String roomDesignation;
  final String doorType;
  final int wingCount;
  final String material;
  final String manufacturer;
  final String dinConfiguration;
  final String closerType;
  final String closingSequenceSystem;
  final String lockDimensions;
  final bool closerOnHingeSide;
  final bool closerOnOppositeSide;
  final bool lintelHeightUnder1m;
  final bool escapeDoorControl;
  final String accessControl;
  final bool escapeRouteSituation;
  final bool escapeRouteSignage;
  final bool blindCylinder;
  final bool pzCylinder;
  final String fittingType;
  final String panicFunction;
  final bool escapeDirectionRespected;
  final bool fullPanicStandWing;
  final bool doorFunctionOK;

  Door({
    required this.customerName,
    required this.customerAddress,
    required this.contactPerson,
    required this.jobNumber,
    required this.inspectionDate,
    required this.inspectorName,
    required this.id,
    required this.pos,
    required this.doorNumber,
    required this.floor,
    required this.roomNumber,
    required this.roomDesignation,
    required this.doorType,
    required this.wingCount,
    required this.material,
    required this.manufacturer,
    required this.dinConfiguration,
    required this.closerType,
    required this.closingSequenceSystem,
    required this.lockDimensions,
    required this.closerOnHingeSide,
    required this.closerOnOppositeSide,
    required this.lintelHeightUnder1m,
    required this.escapeDoorControl,
    required this.accessControl,
    required this.escapeRouteSituation,
    required this.escapeRouteSignage,
    required this.blindCylinder,
    required this.pzCylinder,
    required this.fittingType,
    required this.panicFunction,
    required this.escapeDirectionRespected,
    required this.fullPanicStandWing,
    required this.doorFunctionOK,
  });

  // ---------------------------------------------------------
  // COPYWITH METHOD (added)
  // ---------------------------------------------------------
  Door copyWith({
    // Inspection metadata
    String? customerName,
    String? customerAddress,
    String? contactPerson,
    String? jobNumber,
    DateTime? inspectionDate,
    String? inspectorName,
    
    // Door specifications
    int? id,
    int? pos,
    String? doorNumber,
    String? floor,
    String? roomNumber,
    String? roomDesignation,
    String? doorType,
    int? wingCount,
    String? material,
    String? manufacturer,
    String? dinConfiguration,
    String? closerType,
    String? closingSequenceSystem,
    String? lockDimensions,
    bool? closerOnHingeSide,
    bool? closerOnOppositeSide,
    bool? lintelHeightUnder1m,
    bool? escapeDoorControl,
    String? accessControl,
    bool? escapeRouteSituation,
    bool? escapeRouteSignage,
    bool? blindCylinder,
    bool? pzCylinder,
    String? fittingType,
    String? panicFunction,
    bool? escapeDirectionRespected,
    bool? fullPanicStandWing,
    bool? doorFunctionOK,
  }) {
    return Door(
      customerName: customerName ?? this.customerName,
      customerAddress: customerAddress ?? this.customerAddress,
      contactPerson: contactPerson ?? this.contactPerson,
      jobNumber: jobNumber ?? this.jobNumber,
      inspectionDate: inspectionDate ?? this.inspectionDate,
      inspectorName: inspectorName ?? this.inspectorName,
      id: id ?? this.id,
      pos: pos ?? this.pos,
      doorNumber: doorNumber ?? this.doorNumber,
      floor: floor ?? this.floor,
      roomNumber: roomNumber ?? this.roomNumber,
      roomDesignation: roomDesignation ?? this.roomDesignation,
      doorType: doorType ?? this.doorType,
      wingCount: wingCount ?? this.wingCount,
      material: material ?? this.material,
      manufacturer: manufacturer ?? this.manufacturer,
      dinConfiguration: dinConfiguration ?? this.dinConfiguration,
      closerType: closerType ?? this.closerType,
      closingSequenceSystem:
          closingSequenceSystem ?? this.closingSequenceSystem,
      lockDimensions: lockDimensions ?? this.lockDimensions,
      closerOnHingeSide: closerOnHingeSide ?? this.closerOnHingeSide,
      closerOnOppositeSide:
          closerOnOppositeSide ?? this.closerOnOppositeSide,
      lintelHeightUnder1m:
          lintelHeightUnder1m ?? this.lintelHeightUnder1m,
      escapeDoorControl: escapeDoorControl ?? this.escapeDoorControl,
      accessControl: accessControl ?? this.accessControl,
      escapeRouteSituation:
          escapeRouteSituation ?? this.escapeRouteSituation,
      escapeRouteSignage:
          escapeRouteSignage ?? this.escapeRouteSignage,
      blindCylinder: blindCylinder ?? this.blindCylinder,
      pzCylinder: pzCylinder ?? this.pzCylinder,
      fittingType: fittingType ?? this.fittingType,
      panicFunction: panicFunction ?? this.panicFunction,
      escapeDirectionRespected:
          escapeDirectionRespected ?? this.escapeDirectionRespected,
      fullPanicStandWing:
          fullPanicStandWing ?? this.fullPanicStandWing,
      doorFunctionOK: doorFunctionOK ?? this.doorFunctionOK,
    );
  }

  Map<String, dynamic> toMap() => {
        // Inspection metadata
        'customerName': customerName,
        'customerAddress': customerAddress,
        'contactPerson': contactPerson,
        'jobNumber': jobNumber,
        'inspectionDate': inspectionDate.toIso8601String(),
        'inspectorName': inspectorName,
        
        // Door specifications
        'id': id,
        'pos': pos,
        'doorNumber': doorNumber,
        'floor': floor,
        'roomNumber': roomNumber,
        'roomDesignation': roomDesignation,
        'doorType': doorType,
        'wingCount': wingCount,
        'material': material,
        'manufacturer': manufacturer,
        'dinConfiguration': dinConfiguration,
        'closerType': closerType,
        'closingSequenceSystem': closingSequenceSystem,
        'lockDimensions': lockDimensions,
        'closerOnHingeSide': closerOnHingeSide ? 1 : 0,
        'closerOnOppositeSide': closerOnOppositeSide ? 1 : 0,
        'lintelHeightUnder1m': lintelHeightUnder1m ? 1 : 0,
        'escapeDoorControl': escapeDoorControl ? 1 : 0,
        'accessControl': accessControl,
        'escapeRouteSituation': escapeRouteSituation ? 1 : 0,
        'escapeRouteSignage': escapeRouteSignage ? 1 : 0,
        'blindCylinder': blindCylinder ? 1 : 0,
        'pzCylinder': pzCylinder ? 1 : 0,
        'fittingType': fittingType,
        'panicFunction': panicFunction,
        'escapeDirectionRespected':
            escapeDirectionRespected ? 1 : 0,
        'fullPanicStandWing': fullPanicStandWing ? 1 : 0,
        'doorFunctionOK': doorFunctionOK ? 1 : 0,
      };

  factory Door.fromMap(Map<String, dynamic> map) => Door(
        // Inspection metadata
        customerName: map['customerName'] ?? '',
        customerAddress: map['customerAddress'] ?? '',
        contactPerson: map['contactPerson'] ?? '',
        jobNumber: map['jobNumber'] ?? '',
        inspectionDate: DateTime.parse(map['inspectionDate'] ?? DateTime.now().toIso8601String()),
        inspectorName: map['inspectorName'] ?? '',
        
        // Door specifications
        id: map['id'],
        pos: map['pos'],
        doorNumber: map['doorNumber'],
        floor: map['floor'],
        roomNumber: map['roomNumber'],
        roomDesignation: map['roomDesignation'],
        doorType: map['doorType'],
        wingCount: map['wingCount'],
        material: map['material'],
        manufacturer: map['manufacturer'],
        dinConfiguration: map['dinConfiguration'],
        closerType: map['closerType'],
        closingSequenceSystem: map['closingSequenceSystem'],
        lockDimensions: map['lockDimensions'],
        closerOnHingeSide: map['closerOnHingeSide'] == 1,
        closerOnOppositeSide: map['closerOnOppositeSide'] == 1,
        lintelHeightUnder1m: map['lintelHeightUnder1m'] == 1,
        escapeDoorControl: map['escapeDoorControl'] == 1,
        accessControl: map['accessControl'],
        escapeRouteSituation: map['escapeRouteSituation'] == 1,
        escapeRouteSignage: map['escapeRouteSignage'] == 1,
        blindCylinder: map['blindCylinder'] == 1,
        pzCylinder: map['pzCylinder'] == 1,
        fittingType: map['fittingType'],
        panicFunction: map['panicFunction'],
        escapeDirectionRespected:
            map['escapeDirectionRespected'] == 1,
        fullPanicStandWing:
            map['fullPanicStandWing'] == 1,
        doorFunctionOK: map['doorFunctionOK'] == 1,
      );
}
