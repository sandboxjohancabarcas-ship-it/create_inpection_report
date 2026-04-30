// Inspection entity: session metadata
class Inspection {
  final int? inspectionId;
  final String clientName;
  final String objectAddress;
  final DateTime date;
  final String contactPerson;
  final String inspectorName;
  final String auftragsnummer;

  Inspection({
    this.inspectionId,
    required this.clientName,
    required this.objectAddress,
    required this.date,
    required this.contactPerson,
    required this.inspectorName,
    required this.auftragsnummer,
  });

  Map<String, dynamic> toMap() => {
        //'inspectionId': inspectionId,
        'clientName': clientName,
        'objectAddress': objectAddress,
        'date': date.toIso8601String(),
        'contactPerson': contactPerson,
        'inspectorName': inspectorName,
        'auftragsnummer': auftragsnummer,
      };

  factory Inspection.fromMap(Map<String, dynamic> map) => Inspection(
        inspectionId: map['inspectionId'],
        clientName: map['clientName'],
        objectAddress: map['objectAddress'],
        date: DateTime.parse(map['date']),
        contactPerson: map['contactPerson'],
        inspectorName: map['inspectorName'],
        auftragsnummer: map['auftragsnummer'],
      );
}