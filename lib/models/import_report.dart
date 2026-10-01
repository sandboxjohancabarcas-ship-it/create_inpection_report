import 'door_conflict.dart';

class DoorChangeItem {
  final String doorAlias;
  final String doorNumber;
  final String roomDesignation;
  final String floor;
  final String changeType; // 'new' | 'updated'
  final String? status;
  final int errorCount;
  final int? pos;

  DoorChangeItem({
    required this.doorAlias,
    required this.doorNumber,
    required this.roomDesignation,
    this.floor = '',
    required this.changeType,
    this.status,
    this.errorCount = 0,
    this.pos,
  });

  /// Returns true if this door is marked as inspected/processed.
  bool get isProcessed {
    final s = (status ?? '').trim().toLowerCase();
    return s == 'inspected' ||
        s == 'geprüft' ||
        s == 'completed' ||
        s == 'passed' ||
        s == 'failed' ||
        s == 'done' ||
        s == 'bearbeitet';
  }
}

class InspectionFileReportItem {
  final String fileName;
  final String clientName;
  final String objectAddress;
  final String jobNumber;
  final String inspectionDate;
  final int newDoorsCount;
  final int updatedDoorsCount;
  final int defectsRecordedCount;
  final int attachmentsCount;
  final List<DoorChangeItem> doorChanges;
  final String status;

  InspectionFileReportItem({
    required this.fileName,
    this.clientName = '',
    this.objectAddress = '',
    this.jobNumber = '',
    this.inspectionDate = '',
    this.newDoorsCount = 0,
    this.updatedDoorsCount = 0,
    this.defectsRecordedCount = 0,
    this.attachmentsCount = 0,
    this.doorChanges = const [],
    this.status = 'Erfolgreich',
  });

  int get totalDoors => newDoorsCount + updatedDoorsCount;

  List<DoorChangeItem> get unprocessedDoors =>
      doorChanges.where((d) => !d.isProcessed).toList();
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
  final List<InspectionFileReportItem> fileReports;
  final List<DoorConflict> doorConflicts;

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
    this.fileReports = const [],
    this.doorConflicts = const [],
  });

  int get totalDoorsProcessed => newDoorsCount + updatedDoorsCount;

  /// Returns all doors from the imported package that are in an unprocessed/pending status.
  List<DoorChangeItem> get unprocessedDoors =>
      doorChanges.where((d) => !d.isProcessed).toList();

  /// Whether there are any unprocessed doors in the imported package.
  bool get hasUnprocessedDoors => unprocessedDoors.isNotEmpty;
}
