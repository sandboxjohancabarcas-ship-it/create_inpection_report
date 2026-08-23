class ErrorCatalog {
  final int? errorId;       // null before DB insert (AUTOINCREMENT)
  final String code;
  final String description;
  final String category;
  final String severity;     // 'low', 'medium', 'high', 'critical'
  final String recommendation;
  final String normReference; // DIN/EN norm reference
  
  // Consolidation fields
  final String status;        // 'Approved', 'Pending', 'Rejected'
  final String? requestedBy;
  final DateTime? requestDate;
  final int? sourceInspectionDoorId;

  ErrorCatalog({
    this.errorId,
    required this.code,
    required this.description,
    required this.category,
    this.severity = 'medium',
    this.recommendation = '',
    this.normReference = '',
    this.status = 'Approved', // Default for master data
    this.requestedBy,
    this.requestDate,
    this.sourceInspectionDoorId,
  });

  // CopyWith method
  ErrorCatalog copyWith({
    int? errorId,
    String? code,
    String? description,
    String? category,
    String? severity,
    String? recommendation,
    String? normReference,
    String? status,
    String? requestedBy,     
    DateTime? requestDate,
    int? sourceInspectionDoorId,
  }) {
    return ErrorCatalog(
      errorId: errorId ?? this.errorId,
      code: code ?? this.code,
      description: description ?? this.description,
      category: category ?? this.category,
      severity: severity ?? this.severity,
      recommendation: recommendation ?? this.recommendation,
      normReference: normReference ?? this.normReference,
      status: status ?? this.status,
      requestedBy: requestedBy ?? this.requestedBy,
      requestDate: requestDate ?? this.requestDate, 
      sourceInspectionDoorId: sourceInspectionDoorId ?? this.sourceInspectionDoorId,
    );
  }

  Map<String, dynamic> toMap() => {
        if (errorId != null) 'errorId': errorId,
        'code': code,
        'description': description,
        'category': category,
        'severity': severity,
        'recommendation': recommendation,
        'normReference': normReference,
        'status': status, 
        'requestedBy': requestedBy,
        'requestDate': requestDate?.toIso8601String(),
        'sourceInspectionDoorId': sourceInspectionDoorId,
      };

  static String normalizeSeverity(dynamic raw) {
    if (raw == null) return 'medium';
    final lower = raw.toString().trim().toLowerCase().replaceAll('"', '');
    switch (lower) {
      case 'low':
      case 'niedrig':
      case 'hinweis':
        return 'low';
      case 'high':
      case 'hoch':
      case 'mangel':
        return 'high';
      case 'critical':
      case 'kritisch':
      case 'gefahr':
        return 'critical';
      case 'medium':
      case 'mittel':
      default:
        return 'medium';
    }
  }

  factory ErrorCatalog.fromMap(Map<String, dynamic> map) => ErrorCatalog(
        errorId: map['errorId'],
        code: map['code'] ?? '',
        description: map['description'] ?? '',
        category: map['category'] ?? '',
        severity: normalizeSeverity(map['severity']),
        recommendation: map['recommendation'] ?? '',
        normReference: map['normReference'] ?? '',
        status: map['status'] ?? 'Approved',
        requestedBy: map['requestedBy'],
        requestDate: map['requestDate'] != null 
            ? DateTime.tryParse(map['requestDate']) 
            : null,
        sourceInspectionDoorId: map['sourceInspectionDoorId'],
      );

  @override
  String toString() {
    return '$code - $category: $description';
  }

  /// Compare the content of this catalog entry with another entry.
  /// Returns true only if all import-relevant fields are identical.
  bool isSameContent(ErrorCatalog other) {
    return code == other.code &&
        description == other.description &&
        category == other.category &&
        severity == other.severity &&
        recommendation == other.recommendation &&
        normReference == other.normReference;
  }
}

class ImportConflict {
  final String code;
  final String description;
  final ErrorCatalog incoming;
  final ErrorCatalog? existing;
  final String reason;

  ImportConflict({
    required this.code,
    required this.description,
    required this.incoming,
    this.existing,
    required this.reason,
  });

  @override
  String toString() {
    return 'Konflikt für Code $code: $reason';
  }
}

class ImportResult {
  final int insertedCount;
  final int duplicateCount;
  final List<ImportConflict> conflicts;

  ImportResult({
    required this.insertedCount,
    required this.duplicateCount,
    required this.conflicts,
  });
}

enum ResolutionAction {
  keepExisting,
  replaceExisting,
  addAsNew,
  skip,
}

class ConflictResolution {
  final ImportConflict conflict;
  final ResolutionAction action;
  final String? newCode;

  ConflictResolution({
    required this.conflict,
    required this.action,
    this.newCode,
  });

  bool get requiresNewCode => action == ResolutionAction.addAsNew;
}
