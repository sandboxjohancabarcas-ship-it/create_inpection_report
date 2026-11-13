class Window {
  final int? id;
  final String?
      windowAlias; // Physical barcode / QR code or assigned business alias
  final String?
      provisionalAlias; // Auto-generated business alias: F-[ProjectNumber]-[WindowNumber]
  final String windowNumber; // e.g. "03-001"
  final String floor; // e.g. "3.OG", "EG"
  final String roomNumber; // e.g. ".1.02", "Flur", "Herren WC"
  final String
      roomDesignation; // e.g. "Flur", "Büro", "Aktenraum" (from Sonstiges)
  final String windowType; // e.g. "DKL", "DKR", "Festverglasung", "Kippfenster"
  final String material; // e.g. "Alu", "Kunststoff", "Holz"
  final String
      wingDimensions; // e.g. "2430x750", "1180x750" (Flügelabmaße: Breite x Höhe x Flügeltiefe)
  final String
      fittings; // e.g. "Schüco", "GEZE" (Beschläge: Hersteller / ArtikelNr.)
  final bool windowFunctionOK; // Fenster in Ordnung (true = Ja / false = Nein)
  final bool hasRaffstore; // Raffstore vorhanden
  final bool?
      raffstoreOK; // Raffstore in Ordnung (true = Ja, false = Nein, null = Nicht vorhanden)
  final String notes; // Anmerkung / Notizen

  Window({
    this.id,
    this.windowAlias,
    this.provisionalAlias,
    required this.windowNumber,
    required this.floor,
    required this.roomNumber,
    this.roomDesignation = '',
    required this.windowType,
    required this.material,
    this.wingDimensions = '',
    this.fittings = '',
    this.windowFunctionOK = true,
    this.hasRaffstore = false,
    this.raffstoreOK,
    this.notes = '',
  });

  Window copyWith({
    int? id,
    String? windowAlias,
    String? provisionalAlias,
    String? windowNumber,
    String? floor,
    String? roomNumber,
    String? roomDesignation,
    String? windowType,
    String? material,
    String? wingDimensions,
    String? fittings,
    bool? windowFunctionOK,
    bool? hasRaffstore,
    bool? raffstoreOK,
    String? notes,
  }) {
    return Window(
      id: id ?? this.id,
      windowAlias: windowAlias ?? this.windowAlias,
      provisionalAlias: provisionalAlias ?? this.provisionalAlias,
      windowNumber: windowNumber ?? this.windowNumber,
      floor: floor ?? this.floor,
      roomNumber: roomNumber ?? this.roomNumber,
      roomDesignation: roomDesignation ?? this.roomDesignation,
      windowType: windowType ?? this.windowType,
      material: material ?? this.material,
      wingDimensions: wingDimensions ?? this.wingDimensions,
      fittings: fittings ?? this.fittings,
      windowFunctionOK: windowFunctionOK ?? this.windowFunctionOK,
      hasRaffstore: hasRaffstore ?? this.hasRaffstore,
      raffstoreOK: raffstoreOK ?? this.raffstoreOK,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'windowAlias': windowAlias,
        'provisionalAlias': provisionalAlias,
        'windowNumber': windowNumber,
        'floor': floor,
        'roomNumber': roomNumber,
        'roomDesignation': roomDesignation,
        'windowType': windowType,
        'material': material,
        'wingDimensions': wingDimensions,
        'fittings': fittings,
        'windowFunctionOK': windowFunctionOK ? 1 : 0,
        'hasRaffstore': hasRaffstore ? 1 : 0,
        'raffstoreOK': raffstoreOK == null ? null : (raffstoreOK! ? 1 : 0),
        'notes': notes,
      };

  static bool _parseBool(dynamic val, {bool defaultValue = false}) {
    if (val == null) return defaultValue;
    if (val is bool) return val;
    if (val is int) return val == 1;
    final str = val.toString().trim().toLowerCase();
    return str == '1' ||
        str == 'true' ||
        str == 'ja' ||
        str == 'j' ||
        str == 'x';
  }

  static bool? _parseNullableBool(dynamic val) {
    if (val == null) return null;
    if (val is bool) return val;
    if (val is int) return val == 1;
    final str = val.toString().trim().toLowerCase();
    if (str.isEmpty || str == '?' || str == 'none' || str == 'nicht vorhanden')
      return null;
    if (str == '1' || str == 'true' || str == 'ja' || str == 'j' || str == 'x')
      return true;
    if (str == '0' || str == 'false' || str == 'nein' || str == 'n')
      return false;
    return null;
  }

  factory Window.fromMap(Map<String, dynamic> map) => Window(
        id: map['id'],
        windowAlias: map['windowAlias'],
        provisionalAlias: map['provisionalAlias'],
        windowNumber: map['windowNumber']?.toString() ?? '',
        floor: map['floor']?.toString() ?? '',
        roomNumber: map['roomNumber']?.toString() ?? '',
        roomDesignation: map['roomDesignation']?.toString() ?? '',
        windowType: map['windowType']?.toString() ?? '',
        material: map['material']?.toString() ?? '',
        wingDimensions: map['wingDimensions']?.toString() ?? '',
        fittings: map['fittings']?.toString() ?? '',
        windowFunctionOK:
            _parseBool(map['windowFunctionOK'], defaultValue: true),
        hasRaffstore: _parseBool(map['hasRaffstore'], defaultValue: false),
        raffstoreOK: _parseNullableBool(map['raffstoreOK']),
        notes: map['notes']?.toString() ?? '',
      );

  /// Generates structured business alias for windows.
  /// Format: F-[ProjectNumber (without P-)]-[WindowNumber]
  /// Examples:
  /// - projectNumber: "P-000000", windowNumber: "03-044" -> "F-000000-03-044"
  /// - projectNumber: "24-24583-AN", windowNumber: "00-001" -> "F-24583-AN-00-001"
  static String generateAlias({
    String projectNumber = '',
    String windowNumber = '',
  }) {
    final projPart = cleanProjectNumber(projectNumber);
    final winPart = cleanWindowToken(windowNumber);

    List<String> parts = ['F'];
    if (projPart.isNotEmpty) parts.add(projPart);
    if (winPart.isNotEmpty) parts.add(winPart);

    return parts.join('-');
  }

  /// Extracts and cleans the project number, e.g. "P-000000" -> "000000",
  /// or extracts from combined strings like "24-00000-AB P-000000" -> "000000".
  static String cleanProjectNumber(String rawProj) {
    String trimmed = rawProj.trim();
    final pMatch = RegExp(r'P-(\d+)', caseSensitive: false).firstMatch(trimmed);
    if (pMatch != null) {
      return pMatch.group(1)!;
    }
    if (trimmed.toLowerCase().startsWith('p-')) {
      trimmed = trimmed.substring(2).trim();
    }
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '');
  }

  /// Cleans window number tokens, preserving alphanumeric characters, hyphens, and dots.
  static String cleanWindowToken(String raw) {
    if (raw.trim().isEmpty) return '';
    String cleaned = raw.trim().replaceAll(',', '.');
    // Allow letters, digits, dots, hyphens, German umlauts
    cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9\.\-\äöüÄÖÜß]'), '');
    // Strip leading or trailing hyphens or dots
    cleaned = cleaned.replaceAll(RegExp(r'^[\.\-]+|[\.\-]+$'), '');
    return cleaned;
  }

  /// Standardized, compact temporary alias for windows created ad-hoc in the field.
  /// Format: TMP-F-[HEX4]-[WINDOW] (e.g. TMP-F-A1B2-03-001)
  static String generateTemporaryAlias(String windowNumber) {
    final hexStamp = (DateTime.now().millisecondsSinceEpoch % 0xFFFF)
        .toRadixString(16)
        .padLeft(4, '0')
        .toUpperCase();
    final cleanWin = cleanWindowToken(windowNumber);
    return cleanWin.isNotEmpty
        ? 'TMP-F-$hexStamp-$cleanWin'
        : 'TMP-F-$hexStamp';
  }

  @override
  String toString() {
    return 'Window($windowNumber, floor: $floor, room: $roomNumber, alias: $windowAlias)';
  }
}
