class InspectionDoorError {
  final int? id;
  final int inspectionDoorId;
  final int? errorId;           // nullable: null while an ErrorRequest is pending
  final String errorCode;       // stable natural key (e.g. 'ERR_CLOSER_01') — survives DB transfers
  final int quantity;
  final String severity;        // 'Minor' | 'Major' | 'Critical'
  final String notes;
  final String resolutionStatus; // 'Open' | 'In Progress' | 'Resolved'
  final String attachments;     // comma-separated list of image paths

  InspectionDoorError({
    this.id,
    required this.inspectionDoorId,
    this.errorId,
    this.errorCode = '',
    required this.quantity,
    required this.severity,
    required this.notes,
    this.resolutionStatus = 'Open',
    this.attachments = '',
  });

  InspectionDoorError copyWith({
    int? id,
    int? inspectionDoorId,
    int? errorId,
    String? errorCode,
    int? quantity,
    String? severity,
    String? notes,
    String? resolutionStatus,
    String? attachments,
  }) {
    return InspectionDoorError(
      id: id ?? this.id,
      inspectionDoorId: inspectionDoorId ?? this.inspectionDoorId,
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
        'inspectionDoorId': inspectionDoorId,
        'errorId': errorId,
        'errorCode': errorCode,
        'quantity': quantity,
        'severity': severity,
        'notes': notes,
        'resolutionStatus': resolutionStatus,
        'attachments': attachments,
      };

  factory InspectionDoorError.fromMap(Map<String, dynamic> map) =>
      InspectionDoorError(
        id: map['id'],
        inspectionDoorId: map['inspectionDoorId'],
        errorId: map['errorId'],
        errorCode: map['errorCode'] as String? ?? '',
        quantity: map['quantity'] ?? 1,
        severity: map['severity'] ?? 'Minor',
        notes: map['notes'] ?? '',
        resolutionStatus: map['resolutionStatus'] ?? 'Open',
        attachments: map['attachments'] ?? '',
      );
}
