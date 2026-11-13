class InspectionWindowError {
  final int? id;
  final int inspectionWindowId;
  final int? errorId; // nullable: null while an ErrorRequest is pending
  final String errorCode; // stable natural key (e.g. '9.1', '20.1')
  final int quantity;
  final String severity; // 'Minor' | 'Major' | 'Critical' | 'low' | 'medium' | 'high'
  final String notes;
  final String resolutionStatus; // 'Open' | 'In Progress' | 'Resolved'
  final String attachments; // comma-separated list of image paths

  InspectionWindowError({
    this.id,
    required this.inspectionWindowId,
    this.errorId,
    this.errorCode = '',
    required this.quantity,
    required this.severity,
    required this.notes,
    this.resolutionStatus = 'Open',
    this.attachments = '',
  });

  InspectionWindowError copyWith({
    int? id,
    int? inspectionWindowId,
    int? errorId,
    String? errorCode,
    int? quantity,
    String? severity,
    String? notes,
    String? resolutionStatus,
    String? attachments,
  }) {
    return InspectionWindowError(
      id: id ?? this.id,
      inspectionWindowId: inspectionWindowId ?? this.inspectionWindowId,
      errorId: errorId ?? this.errorId,
      errorCode: errorCode ?? this.errorCode,
      quantity: quantity ?? this.quantity,
      severity: severity ?? this.severity,
      notes: notes ?? this.notes,
      resolutionStatus: resolutionStatus ?? this.resolutionStatus,
      attachments: attachments ?? this.attachments,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'inspectionWindowId': inspectionWindowId,
        'errorId': errorId,
        'errorCode': errorCode,
        'quantity': quantity,
        'severity': severity,
        'notes': notes,
        'resolutionStatus': resolutionStatus,
        'attachments': attachments,
      };

  factory InspectionWindowError.fromMap(Map<String, dynamic> map) =>
      InspectionWindowError(
        id: map['id'],
        inspectionWindowId: map['inspectionWindowId'],
        errorId: map['errorId'],
        errorCode: map['errorCode'] ?? '',
        quantity: map['quantity'] ?? 1,
        severity: map['severity'] ?? 'medium',
        notes: map['notes'] ?? '',
        resolutionStatus: map['resolutionStatus'] ?? 'Open',
        attachments: map['attachments'] ?? '',
      );

  bool get isOpen => resolutionStatus == 'Open';
  bool get isInProgress => resolutionStatus == 'In Progress';
  bool get isResolved => resolutionStatus == 'Resolved';

  @override
  String toString() {
    return 'InspectionWindowError($errorCode, qty: $quantity, severity: $severity, status: $resolutionStatus)';
  }
}

