class InspectionDoorError {
  final int? id;
  final int inspectionDoorId;
  final int? errorId;           // nullable: null while an ErrorRequest is pending
  final int quantity;
  final String severity;        // 'Minor' | 'Major' | 'Critical'
  final String notes;
  final String resolutionStatus; // 'Open' | 'In Progress' | 'Resolved'

  InspectionDoorError({
    this.id,
    required this.inspectionDoorId,
    this.errorId,
    required this.quantity,
    required this.severity,
    required this.notes,
    this.resolutionStatus = 'Open',
  });

  InspectionDoorError copyWith({
    int? id,
    int? inspectionDoorId,
    int? errorId,
    int? quantity,
    String? severity,
    String? notes,
    String? resolutionStatus,
  }) {
    return InspectionDoorError(
      id: id ?? this.id,
      inspectionDoorId: inspectionDoorId ?? this.inspectionDoorId,
      errorId: errorId ?? this.errorId,
      quantity: quantity ?? this.quantity,
      severity: severity ?? this.severity,
      notes: notes ?? this.notes,
      resolutionStatus: resolutionStatus ?? this.resolutionStatus,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'inspectionDoorId': inspectionDoorId,
        'errorId': errorId,
        'quantity': quantity,
        'severity': severity,
        'notes': notes,
        'resolutionStatus': resolutionStatus,
      };

  factory InspectionDoorError.fromMap(Map<String, dynamic> map) =>
      InspectionDoorError(
        id: map['id'],
        inspectionDoorId: map['inspectionDoorId'],
        errorId: map['errorId'],
        quantity: map['quantity'] ?? 1,
        severity: map['severity'] ?? 'Minor',
        notes: map['notes'] ?? '',
        resolutionStatus: map['resolutionStatus'] ?? 'Open',
      );
}
