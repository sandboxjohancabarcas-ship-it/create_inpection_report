class InspectionError {
  final int? id;           // null before DB insert (AUTOINCREMENT)
  final int doorId;         // Foreign key to doors table
  final int errorId;         // Foreign key to error_catalog table
  final String notes;        // Inspector notes for this specific error
  final String status;        // 'open', 'in_progress', 'resolved'
  final DateTime reportedDate;
  final DateTime? resolvedDate;

  InspectionError({
    this.id,
    required this.doorId,
    required this.errorId,
    this.notes = '',
    this.status = 'open',
    required this.reportedDate,
    this.resolvedDate,
  });

  // CopyWith method
  InspectionError copyWith({
    int? id,
    int? doorId,
    int? errorId,
    String? notes,
    String? status,
    DateTime? reportedDate,
    DateTime? resolvedDate,
  }) {
    return InspectionError(
      id: id ?? this.id,
      doorId: doorId ?? this.doorId,
      errorId: errorId ?? this.errorId,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      reportedDate: reportedDate ?? this.reportedDate,
      resolvedDate: resolvedDate ?? this.resolvedDate,
    );
  }

  // ToMap for database
  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'doorId': doorId,
        'errorId': errorId,
        'notes': notes,
        'status': status,
        'reportedDate': reportedDate.toIso8601String(),
        if (resolvedDate != null) 'resolvedDate': resolvedDate!.toIso8601String(),
      };

  // FromMap for database
  factory InspectionError.fromMap(Map<String, dynamic> map) => InspectionError(
        id: map['id'],
        doorId: map['doorId'],
        errorId: map['errorId'],
        notes: map['notes'] ?? '',
        status: map['status'] ?? 'open',
        reportedDate: DateTime.parse(map['reportedDate']),
        resolvedDate: map['resolvedDate'] != null 
            ? DateTime.parse(map['resolvedDate']) 
            : null,
      );

  @override
  String toString() {
    return 'Error $errorId for Door $doorId: $status';
  }
}

// Error status management
class ErrorStatus {
  static List<String> getAllStatuses() {
    return ['open', 'in_progress', 'resolved'];
  }

  static String getStatusDisplay(String status) {
    switch (status) {
      case 'open':
        return 'Offen';
      case 'in_progress':
        return 'In Bearbeitung';
      case 'resolved':
        return 'Gelöst';
      default:
        return status;
    }
  }

  static String getStatusColor(String status) {
    switch (status) {
      case 'open':
        return 'red';
      case 'in_progress':
        return 'orange';
      case 'resolved':
        return 'green';
      default:
        return 'grey';
    }
  }
}
