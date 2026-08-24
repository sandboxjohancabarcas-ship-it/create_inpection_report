class DoorChangeItem {
  final String doorAlias;
  final String doorNumber;
  final String roomDesignation;
  final String changeType; // 'new' | 'updated'
  final String? status;
  final int errorCount;

  DoorChangeItem({
    required this.doorAlias,
    required this.doorNumber,
    required this.roomDesignation,
    required this.changeType,
    this.status,
    this.errorCount = 0,
  });
}

class ImportReport {
  final String packageName;
  final DateTime importedAt;
  final int newDoorsCount;
  final int updatedDoorsCount;
  final int newInspectionsCount;
  final int updatedInspectionsCount;
  final int totalErrorsImported;
  final int totalAttachmentsImported;
  final List<DoorChangeItem> doorChanges;
  final List<String> newCatalogProposals;

  ImportReport({
    required this.packageName,
    required this.importedAt,
    required this.newDoorsCount,
    required this.updatedDoorsCount,
    required this.newInspectionsCount,
    required this.updatedInspectionsCount,
    required this.totalErrorsImported,
    required this.totalAttachmentsImported,
    required this.doorChanges,
    required this.newCatalogProposals,
  });

  int get totalDoorsProcessed => newDoorsCount + updatedDoorsCount;
}
