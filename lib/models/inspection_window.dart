// Junction: window inspected in a session
class InspectionWindow {
  final int? id;
  final int inspectionId;
  final int windowId;
  final String status;
  final String notes;
  final List<String>? attachments;
  final String? syncStatus;

  InspectionWindow({
    this.id,
    required this.inspectionId,
    required this.windowId,
    required this.status,
    required this.notes,
    this.attachments,
    this.syncStatus,
  });

  InspectionWindow copyWith({
    int? id,
    int? inspectionId,
    int? windowId,
    String? status,
    String? notes,
    List<String>? attachments,
    String? syncStatus,
  }) {
    return InspectionWindow(
      id: id ?? this.id,
      inspectionId: inspectionId ?? this.inspectionId,
      windowId: windowId ?? this.windowId,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      attachments: attachments ?? this.attachments,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'inspectionId': inspectionId,
        'windowId': windowId,
        'status': status,
        'notes': notes,
        'attachments': attachments?.join(','),
        'syncStatus': syncStatus,
      };

  factory InspectionWindow.fromMap(Map<String, dynamic> map) => InspectionWindow(
        id: map['id'],
        inspectionId: map['inspectionId'],
        windowId: map['windowId'],
        status: map['status'] ?? 'InProgress',
        notes: map['notes'] ?? '',
        attachments: map['attachments'] != null && map['attachments'].toString().isNotEmpty
            ? map['attachments'].toString().split(',')
            : null,
        syncStatus: map['syncStatus'],
      );
}

