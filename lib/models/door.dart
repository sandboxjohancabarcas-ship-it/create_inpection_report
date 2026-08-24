class Door {
  // Door Technical Specifications (Physical data only)
  final int? id;
  final int pos;
  final String? doorAlias; // Business ID: Customer-Address-Building
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
    required this.id,
    required this.pos,
    this.doorAlias,
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
    // Door specifications
    int? id,
    int? pos,
    String? doorAlias,
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
      id: id ?? this.id,
      pos: pos ?? this.pos,
      doorAlias: doorAlias ?? this.doorAlias,
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
        
        // Door specifications
        'id': id,
        'pos': pos,
        'doorAlias': doorAlias,
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
        // Door specifications
        id: map['id'],
        pos: map['pos'] ?? 0,
        doorAlias: map['doorAlias'],
        doorNumber: map['doorNumber'] ?? '',
        floor: map['floor'] ?? '',
        roomNumber: map['roomNumber'] ?? '',
        roomDesignation: map['roomDesignation'] ?? '',
        doorType: map['doorType'] ?? '',
        wingCount: map['wingCount'] ?? 1,
        material: map['material'] ?? '',
        manufacturer: map['manufacturer'] ?? '',
        dinConfiguration: map['dinConfiguration'] ?? '',
        closerType: map['closerType'] ?? '',
        closingSequenceSystem: map['closingSequenceSystem'] ?? '',
        lockDimensions: map['lockDimensions'] ?? '',
        closerOnHingeSide: map['closerOnHingeSide'] == 1,
        closerOnOppositeSide: map['closerOnOppositeSide'] == 1,
        lintelHeightUnder1m: map['lintelHeightUnder1m'] == 1,
        escapeDoorControl: map['escapeDoorControl'] == 1,
        accessControl: map['accessControl'] ?? '',
        escapeRouteSituation: map['escapeRouteSituation'] == 1,
        escapeRouteSignage: map['escapeRouteSignage'] == 1,
        blindCylinder: map['blindCylinder'] == 1,
        pzCylinder: map['pzCylinder'] == 1,
        fittingType: map['fittingType'] ?? '',
        panicFunction: map['panicFunction'] ?? '',
        escapeDirectionRespected:
            map['escapeDirectionRespected'] == 1,
        fullPanicStandWing:
            map['fullPanicStandWing'] == 1,
        doorFunctionOK: map['doorFunctionOK'] == 1,
      );

  /// Generates an intelligent, human-readable, structured business alias.
  /// Format: [CUSTOMER 5]-[ADDRESS 5]-[FLOOR 2..3]-[DOOR 2..4]
  /// Examples:
  /// - "Gottsberg GmbH", "Ebner-Eschenbach-Weg 43, 21035 Hamburg", "EG", "1" -> "GOTTS-EBN43-EG-01"
  /// - "Konz Schäfer", "Hauptstraße 12b", "1. OG", "4" -> "KONSC-HAU12-OG1-04"
  /// - "Siemens AG", "Werner-von-Siemens-Ring 50", "2. Obergeschoss", "T-201" -> "SIEME-WSI50-OG2-T201"
  /// - "Deutsche Bahn", "Bahnhofsplatz 1", "", "12" -> "DBAHN-BAH01-12"
  static String generateAlias(
    String customer,
    String address,
    String doorNumber, {
    String floor = '',
  }) {
    if (customer.trim().isEmpty &&
        address.trim().isEmpty &&
        doorNumber.trim().isEmpty &&
        floor.trim().isEmpty) {
      return '';
    }

    final custPart = _extractCustomerToken(customer, targetLength: 5);
    final addrPart = _extractAddressToken(address, targetLength: 5);
    final floorPart = _normalizeFloorToken(floor);
    final doorPart = _normalizeDoorNumber(doorNumber);

    List<String> parts = [];
    if (custPart.isNotEmpty) parts.add(custPart);
    if (addrPart.isNotEmpty) parts.add(addrPart);
    if (floorPart.isNotEmpty) parts.add(floorPart);
    if (doorPart.isNotEmpty) parts.add(doorPart);

    return parts.join('-');
  }

  /// Standardized, compact temporary alias for doors created ad-hoc in the field.
  /// Format: TMP-[HEX4]-[DOOR] (e.g. TMP-F4A1-01)
  static String generateTemporaryAlias(String doorNumber) {
    final hexStamp = (DateTime.now().millisecondsSinceEpoch % 0xFFFF)
        .toRadixString(16)
        .padLeft(4, '0')
        .toUpperCase();
    final cleanDoor = _normalizeDoorNumber(doorNumber);
    return cleanDoor.isNotEmpty ? 'TMP-$hexStamp-$cleanDoor' : 'TMP-$hexStamp';
  }

  /// Transliterates German umlauts and accents into standard ASCII.
  static String _transliterate(String input) {
    return input
        .replaceAll('ä', 'ae')
        .replaceAll('Ä', 'AE')
        .replaceAll('ö', 'oe')
        .replaceAll('Ö', 'OE')
        .replaceAll('ü', 'ue')
        .replaceAll('Ü', 'UE')
        .replaceAll('ß', 'ss');
  }

  /// Extracts a meaningful 4-5 char acronym/stem for the customer.
  static String _extractCustomerToken(String rawCustomer, {int targetLength = 5}) {
    if (rawCustomer.trim().isEmpty) return '';

    String cleaned = _transliterate(rawCustomer.trim());

    // Remove common German & international legal form suffixes
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(GmbH\s*&\s*Co\.?\s*KG|GmbH|AG|e\.?V\.?|KG|GbR|OHG|SE|UG|Ltd\.?|Inc\.?|Corp\.?|Holding|Verwaltung|Immobilien)\b', caseSensitive: false),
      '',
    );

    // Remove common stop words
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(und|&|von|der|die|das|des|dem|den|im|am|fur|fuer)\b', caseSensitive: false),
      '',
    );

    // Extract alphanumeric word tokens
    final words = cleaned
        .split(RegExp(r'[^a-zA-Z0-9]+'))
        .where((w) => w.trim().isNotEmpty)
        .toList();

    if (words.isEmpty) {
      final fallback = rawCustomer.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
      return fallback.length > targetLength ? fallback.substring(0, targetLength) : fallback;
    }

    if (words.length == 1) {
      final w = words.first.toUpperCase();
      return w.length > targetLength ? w.substring(0, targetLength) : w;
    }

    if (words.length == 2) {
      final w1 = words[0].toUpperCase();
      final w2 = words[1].toUpperCase();
      final len1 = w1.length >= 3 ? 3 : w1.length;
      final len2 = (targetLength - len1).clamp(1, w2.length);
      return '${w1.substring(0, len1)}${w2.substring(0, len2)}';
    }

    // 3 or more words (e.g. "Hamburg Port Authority")
    String combined = '';
    for (int i = 0; i < words.length && combined.length < targetLength; i++) {
      final w = words[i].toUpperCase();
      int take = (targetLength - combined.length) > (words.length - i) ? 2 : 1;
      if (take > w.length) take = w.length;
      combined += w.substring(0, take);
    }
    return combined;
  }

  /// Extracts a meaningful 4-5 char address token combining street stem & building/house number.
  static String _extractAddressToken(String rawAddress, {int targetLength = 5}) {
    if (rawAddress.trim().isEmpty) return '';

    String cleaned = _transliterate(rawAddress.trim());

    // 1. Extract House/Building Number (e.g. "43", "12a", "3B", "H4")
    // Avoid capturing 5-digit German postal codes (e.g. 21035)
    String numberPart = '';
    final numMatch = RegExp(r'\b(?<!\d)(\d{1,4}[a-zA-Z]?)\b(?!\s*\d{4})').allMatches(cleaned);
    for (final m in numMatch) {
      final val = m.group(1)!;
      if (val.length < 5) {
        numberPart = val.toUpperCase();
      }
    }

    // 2. Strip street suffixes and noise
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(strasse|straße|str\.?|weg|platz|pl\.?|allee|chaussee|ring|gasse|damm|ufer|stieg|pfad|zeile|haus|gebaeude|bauteil)\b', caseSensitive: false),
      '',
    );

    // Remove common stop words in address (e.g. von, der, am, im)
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(und|&|von|der|die|das|des|dem|den|im|am|an|fur|fuer)\b', caseSensitive: false),
      '',
    );

    // Remove postal code + city if present (e.g. "21035 Hamburg")
    cleaned = cleaned.replaceAll(RegExp(r'\b\d{5}\b.*$'), '');

    final words = cleaned
        .split(RegExp(r'[^a-zA-Z0-9]+'))
        .where((w) => w.trim().isNotEmpty && !RegExp(r'^\d+$').hasMatch(w))
        .toList();

    String streetPart = '';
    if (words.isNotEmpty) {
      if (words.length == 1) {
        streetPart = words.first.toUpperCase();
      } else {
        // Multi-word street (e.g. "Ebner-Eschenbach" -> "EBNE" or "Werner Siemens" -> "WERSI")
        final w1 = words[0].toUpperCase();
        final w2 = words[1].toUpperCase();
        final len1 = w1.length >= 3 ? 3 : w1.length;
        final len2 = (targetLength - len1).clamp(1, w2.length);
        streetPart = '${w1.substring(0, len1)}${w2.substring(0, len2)}';
      }
    } else {
      streetPart = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    }

    if (numberPart.isNotEmpty) {
      final availableForStreet = targetLength - numberPart.length;
      if (availableForStreet > 0) {
        final st = streetPart.length > availableForStreet ? streetPart.substring(0, availableForStreet) : streetPart;
        return '$st$numberPart';
      }
      return numberPart.length > targetLength ? numberPart.substring(0, targetLength) : numberPart;
    }

    return streetPart.length > targetLength ? streetPart.substring(0, targetLength) : streetPart;
  }

  /// Normalizes floor to 2-3 standard uppercase characters (e.g. "EG", "OG1", "UG", "KG", "DG").
  static String _normalizeFloorToken(String rawFloor) {
    if (rawFloor.trim().isEmpty) return '';

    String cleaned = _transliterate(rawFloor.trim().toLowerCase());

    if (cleaned.contains('erd') || cleaned == 'eg' || cleaned.contains('parterre') || cleaned.contains('ground')) {
      return 'EG';
    }
    if (cleaned.contains('dach') || cleaned == 'dg') {
      return 'DG';
    }
    if (cleaned.contains('keller') || cleaned == 'kg') {
      return 'KG';
    }
    if (cleaned.contains('unter') || cleaned.contains('ug') || cleaned.contains('basement')) {
      final ugMatch = RegExp(r'(\d+)\.?\s*(?:ug|unter)|(?:ug|unter)\s*(\d+)').firstMatch(cleaned);
      if (ugMatch != null) {
        final num = ugMatch.group(1) ?? ugMatch.group(2) ?? '';
        if (num.isNotEmpty) return 'UG$num';
      }
      return 'UG';
    }

    final ogMatch = RegExp(r'(\d+)\.?\s*(?:og|ober|etage|stock)|(?:og|ober)\s*(\d+)').firstMatch(cleaned);
    if (ogMatch != null) {
      final num = ogMatch.group(1) ?? ogMatch.group(2) ?? '';
      if (num.isNotEmpty) return 'OG$num';
    }

    if (cleaned.contains('og')) return 'OG';

    final fallback = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    return fallback.length > 3 ? fallback.substring(0, 3) : fallback;
  }

  /// Normalizes door numbers (pads single digits to 2 digits, cleans noise).
  static String _normalizeDoorNumber(String rawDoor) {
    if (rawDoor.trim().isEmpty) return '';
    String cleaned = rawDoor.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    if (RegExp(r'^\d$').hasMatch(cleaned)) {
      return '0$cleaned';
    }
    return cleaned;
  }
}
