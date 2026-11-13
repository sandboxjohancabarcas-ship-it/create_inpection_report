typedef InspectionList = List<Map<String, dynamic>>;

class Inspection {
  final int? id;
  final String? clientName;
  final String? jobNumber;
  final String? projectNumber;
  final String? objectAddress;
  final String? date;
  final String? orderType;
  final String? repairDate;
  final int? doorCount;
  final int? windowCount;
  final String assetType;
  final dynamic isLocked;

  const Inspection({
    this.id,
    this.clientName,
    this.jobNumber,
    this.projectNumber,
    this.objectAddress,
    this.date,
    this.orderType,
    this.repairDate,
    this.doorCount,
    this.windowCount,
    this.assetType = 'door',
    this.isLocked,
  });

  bool get isDoorInspection => assetType.toLowerCase() == 'door';
  bool get isWindowInspection => assetType.toLowerCase() == 'window';

  factory Inspection.fromMap(Map<String, dynamic> map) {
    return Inspection(
      id: map['id'] ?? map['inspectionId'],
      clientName: map['clientName']?.toString(),
      jobNumber:
          map['jobNumber']?.toString() ?? map['auftragsnummer']?.toString(),
      projectNumber: map['projectNumber']?.toString(),
      objectAddress: map['objectAddress']?.toString(),
      date: map['date']?.toString(),
      orderType: map['orderType']?.toString(),
      repairDate: map['repairDate']?.toString(),
      doorCount: (map['doorCount'] as num?)?.toInt(),
      windowCount: (map['windowCount'] as num?)?.toInt(),
      assetType: map['assetType']?.toString() ?? 'door',
      isLocked: map['isLocked'],
    );
  }
}
