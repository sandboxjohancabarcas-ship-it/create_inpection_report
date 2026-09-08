import 'door_conflict.dart';

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
}
