class InspectionRwaError {
  final int? id;
  final int inspectionRwaId;
  final String settingName; // Linked installation setting, e.g. 'Feuertaster', 'Notstrombatterie'
  final int? errorId; // nullable: null while an ErrorRequest is pending
  final String errorCode; // stable natural key (e.g. 'RWA-FT-001', 'RWA-AK-001')
  final int quantity;
  final String severity; // 'Minor' | 'Major' | 'Critical' | 'low' | 'medium' | 'high'
  final String notes;
  final String resolutionStatus; // 'Open' | 'In Progress' | 'Resolved'
  final String attachments; // comma-separated list of image paths

  InspectionRwaError({
    this.id,
    required this.inspectionRwaId,
    this.settingName = '',
    this.errorId,
    this.errorCode = '',
    required this.quantity,
    required this.severity,
    required this.notes,
    this.resolutionStatus = 'Open',
    this.attachments = '',
  });

  InspectionRwaError copyWith({
    int? id,
    int? inspectionRwaId,
    String? settingName,
    int? errorId,
    String? errorCode,
    int? quantity,
    String? severity,
    String? notes,
    String? resolutionStatus,
    String? attachments,
  }) {
    return InspectionRwaError(
      id: id ?? this.id,
      inspectionRwaId: inspectionRwaId ?? this.inspectionRwaId,
      settingName: settingName ?? this.settingName,
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
        'inspectionRwaId': inspectionRwaId,
        'settingName': settingName,
        'errorId': errorId,
        'errorCode': errorCode,
        'quantity': quantity,
        'severity': severity,
        'notes': notes,
        'resolutionStatus': resolutionStatus,
        'attachments': attachments,
      };

  factory InspectionRwaError.fromMap(Map<String, dynamic> map) =>
      InspectionRwaError(
        id: map['id'],
        inspectionRwaId: map['inspectionRwaId'],
        settingName: map['settingName'] ?? '',
        errorId: map['errorId'],
        errorCode: map['errorCode'] ?? '',
        quantity: map['quantity'] ?? 1,
        severity: map['severity'] ?? 'medium',
        notes: map['notes'] ?? '',
        resolutionStatus: map['resolutionStatus'] ?? 'Open',
        attachments: map['attachments'] ?? '',
      );

  @override
  String toString() =>
      'InspectionRwaError(id: $id, inspectionRwaId: $inspectionRwaId, code: $errorCode, setting: $settingName, severity: $severity)';
}
