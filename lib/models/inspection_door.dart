// Junction: door inspected in a session
class InspectionDoor {
  final int? id;
  final int inspectionId;
  final int doorId;
  final String status;
  final String notes;
  final List<String>? attachments;
  final String? syncStatus;

  InspectionDoor({
    this.id,
    required this.inspectionId,
    required this.doorId,
    required this.status,
    required this.notes,
    this.attachments,
    this.syncStatus,
  });

  InspectionDoor copyWith({
    int? id,
    int? inspectionId,
    int? doorId,
    String? status,
    String? notes,
    List<String>? attachments,
    String? syncStatus,
  }) {
    return InspectionDoor(
      id: id ?? this.id,
      inspectionId: inspectionId ?? this.inspectionId,
      doorId: doorId ?? this.doorId,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      attachments: attachments ?? this.attachments,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': status,
        'notes': notes,
        'attachments': attachments?.join(','),
        'syncStatus': syncStatus,
      };

  factory InspectionDoor.fromMap(Map<String, dynamic> map) => InspectionDoor(
        id: map['id'],
        inspectionId: map['inspectionId'],
        doorId: map['doorId'],
        status: map['status'] ?? 'InProgress',
        notes: map['notes'] ?? '',
        attachments: map['attachments'] != null && map['attachments'].toString().isNotEmpty 
            ? map['attachments'].toString().split(',') 
            : null,
        syncStatus: map['syncStatus'],
      );
}