// Inspection entity: session metadata
class Inspection {
  final int? inspectionId;
  final String clientName;
  final String objectAddress;
  final DateTime date;
  final String contactPerson;
  final String inspectorName;
  final String auftragsnummer;
  final String? syncStatus;

  Inspection({
    this.inspectionId,
    required this.clientName,
    required this.objectAddress,
    required this.date,
    required this.contactPerson,
    required this.inspectorName,
    required this.auftragsnummer,
    this.syncStatus,
  });

  Inspection copyWith({
    int? inspectionId,
    String? clientName,
    String? objectAddress,
    DateTime? date,
    String? contactPerson,
    String? inspectorName,
    String? auftragsnummer,
    String? syncStatus,
  }) {
    return Inspection(
      inspectionId: inspectionId ?? this.inspectionId,
      clientName: clientName ?? this.clientName,
      objectAddress: objectAddress ?? this.objectAddress,
      date: date ?? this.date,
      contactPerson: contactPerson ?? this.contactPerson,
      inspectorName: inspectorName ?? this.inspectorName,
      auftragsnummer: auftragsnummer ?? this.auftragsnummer,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() => {
        if (inspectionId != null) 'inspectionId': inspectionId,
        'clientName': clientName,
        'objectAddress': objectAddress,
        'date': date.toIso8601String(),
        'contactPerson': contactPerson,
        'inspectorName': inspectorName,
        'auftragsnummer': auftragsnummer,
        'syncStatus': syncStatus,
      };

  factory Inspection.fromMap(Map<String, dynamic> map) => Inspection(
        inspectionId: map['inspectionId'],
        clientName: map['clientName'] ?? '',
        objectAddress: map['objectAddress'],
        date: map['date'] != null ? DateTime.parse(map['date']) : DateTime.now(),
        contactPerson: map['contactPerson'],
        inspectorName: map['inspectorName'],
        auftragsnummer: map['auftragsnummer'],
        syncStatus: map['syncStatus'],
      );
}