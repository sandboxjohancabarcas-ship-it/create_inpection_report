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

enum DoorErrorState {
  noErrors,
  hasOpenErrors,
  allErrorsResolved,
  noticesOnly,
}

class DoorErrorSummary {
  final int totalErrors;
  final int openErrors;
  final int resolvedErrors;

  final int defectCount;
  final int openDefects;
  final int resolvedDefects;

  final int noticeCount;
  final int openNotices;
  final int resolvedNotices;

  const DoorErrorSummary({
    required this.totalErrors,
    required this.openErrors,
    required this.resolvedErrors,
    this.defectCount = 0,
    this.openDefects = 0,
    this.resolvedDefects = 0,
    this.noticeCount = 0,
    this.openNotices = 0,
    this.resolvedNotices = 0,
  });

  bool get hasDefects => defectCount > 0;
  bool get hasOpenDefects => openDefects > 0;
  bool get hasResolvedDefects => resolvedDefects > 0;
  bool get isFullyResolvedDefects => defectCount > 0 && openDefects == 0;
  bool get isPartiallyResolvedDefects => openDefects > 0 && resolvedDefects > 0;

  bool get hasNotices => noticeCount > 0;
  bool get hasOpenNotices => openNotices > 0;
  bool get isNoticesOnly => defectCount == 0 && noticeCount > 0;
  bool get isClean => totalErrors == 0;

  DoorErrorState get state {
    if (totalErrors == 0) {
      return DoorErrorState.noErrors;
    } else if (openDefects > 0 || (defectCount == 0 && openErrors > 0)) {
      return DoorErrorState.hasOpenErrors;
    } else if ((defectCount > 0 && openDefects == 0) || (defectCount == 0 && openErrors == 0 && resolvedErrors > 0)) {
      return DoorErrorState.allErrorsResolved;
    } else if (noticeCount > 0) {
      return DoorErrorState.noticesOnly;
    } else {
      return DoorErrorState.noErrors;
    }
  }
}

