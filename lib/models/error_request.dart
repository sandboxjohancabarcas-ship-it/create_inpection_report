class ErrorRequest {
  final int? requestId;
  final String proposedCode;
  final String proposedDescription;
  final String category;
  final int inspectionDoorId;   // which door inspection triggered this
  final String date;
  final String status;           // 'pending' | 'approved' | 'rejected'
  final String? managerNotes;
  final int? replacedByErrorId; // set on rejection: the catalog entry chosen by manager

  ErrorRequest({
    this.requestId,
    required this.proposedCode,
    required this.proposedDescription,
    required this.category,
    required this.inspectionDoorId,
    required this.date,
    this.status = 'pending',
    this.managerNotes,
    this.replacedByErrorId,
  });

  Map<String, dynamic> toMap() => {
        if (requestId != null) 'requestId': requestId,
        'proposedCode': proposedCode,
        'proposedDescription': proposedDescription,
        'category': category,
        'inspectionDoorId': inspectionDoorId,
        'date': date,
        'status': status,
        'managerNotes': managerNotes,
        'replacedByErrorId': replacedByErrorId,
      };

  factory ErrorRequest.fromMap(Map<String, dynamic> map) => ErrorRequest(
        requestId: map['requestId'],
        proposedCode: map['proposedCode'] ?? '',
        proposedDescription: map['proposedDescription'] ?? '',
        category: map['category'] ?? '',
        inspectionDoorId: map['inspectionDoorId'] ?? 0,
        date: map['date'] ?? '',
        status: map['status'] ?? 'pending',
        managerNotes: map['managerNotes'],
        replacedByErrorId: map['replacedByErrorId'],
      );
}
