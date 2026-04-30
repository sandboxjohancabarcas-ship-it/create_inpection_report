// Junction: door inspected in a session
class InspectionDoor {
  final int id;
  final int inspectionId;
  final int doorId;
  final String status;
  final String notes;
  final List<String>? attachments;

  InspectionDoor({
    required this.id,
    required this.inspectionId,
    required this.doorId,
    required this.status,
    required this.notes,
    this.attachments,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': status,
        'notes': notes,
        'attachments': attachments?.join(','),
      };

  factory InspectionDoor.fromMap(Map<String, dynamic> map) => InspectionDoor(
        id: map['id'],
        inspectionId: map['inspectionId'],
        doorId: map['doorId'],
        status: map['status'],
        notes: map['notes'],
        attachments: map['attachments']?.split(','),
      );
}