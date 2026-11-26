// Junction: RWA system inspected in a session
class InspectionRwa {
  final int? id;
  final int inspectionId;
  final int rwaSystemId;
  final String status; // 'InProgress', 'Completed'
  final String notes;
  final List<String>? attachments;
  final String? syncStatus;

  InspectionRwa({
    this.id,
    required this.inspectionId,
    required this.rwaSystemId,
    required this.status,
    required this.notes,
    this.attachments,
    this.syncStatus,
  });

  InspectionRwa copyWith({
    int? id,
    int? inspectionId,
    int? rwaSystemId,
    String? status,
    String? notes,
    List<String>? attachments,
    String? syncStatus,
  }) {
    return InspectionRwa(
      id: id ?? this.id,
      inspectionId: inspectionId ?? this.inspectionId,
      rwaSystemId: rwaSystemId ?? this.rwaSystemId,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      attachments: attachments ?? this.attachments,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'inspectionId': inspectionId,
        'rwaSystemId': rwaSystemId,
        'status': status,
        'notes': notes,
        'attachments': attachments?.join(','),
        'syncStatus': syncStatus,
      };

  factory InspectionRwa.fromMap(Map<String, dynamic> map) => InspectionRwa(
        id: map['id'],
        inspectionId: map['inspectionId'],
        rwaSystemId: map['rwaSystemId'],
        status: map['status'] ?? 'InProgress',
        notes: map['notes'] ?? '',
        attachments: map['attachments'] != null && map['attachments'].toString().isNotEmpty
            ? map['attachments'].toString().split(',')
            : null,
        syncStatus: map['syncStatus'],
      );

  @override
  String toString() =>
      'InspectionRwa(id: $id, inspectionId: $inspectionId, rwaSystemId: $rwaSystemId, status: $status)';
}
