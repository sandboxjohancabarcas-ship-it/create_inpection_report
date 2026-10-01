import 'dart:io';
import 'package:wartungstool/models/door_conflict.dart';
import 'package:wartungstool/models/error_catalog.dart';
import 'package:wartungstool/models/import_report.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';

class BatchMigrationResult {
  final ImportReport aggregatedReport;
  final List<DoorConflict> doorConflicts;
  final List<ImportConflict> catalogConflicts;
  final int totalFilesFound;
  final int compliantFilesProcessed;
  final int skippedFilesCount;
  final List<String> processedFileNames;
  final List<String> skippedFileNames;

  BatchMigrationResult({
    required this.aggregatedReport,
    this.doorConflicts = const [],
    this.catalogConflicts = const [],
    required this.totalFilesFound,
    required this.compliantFilesProcessed,
    required this.skippedFilesCount,
    required this.processedFileNames,
    required this.skippedFileNames,
  });

  bool get hasConflicts => doorConflicts.isNotEmpty || catalogConflicts.isNotEmpty;
}

class SingleFileMigrationResult {
  final File file;
  final String fileName;
  final bool isSuccess;
  final bool isSkipped;
  final String? errorMessage;
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
  final List<ImportConflict> catalogConflicts;
  final ImportReport? importReport;
  final ExcelImportResult? excelResult;

  SingleFileMigrationResult({
    required this.file,
    required this.fileName,
    this.isSuccess = false,
    this.isSkipped = false,
    this.errorMessage,
    this.newDoorsCount = 0,
    this.updatedDoorsCount = 0,
    this.newInspectionsCount = 0,
    this.updatedInspectionsCount = 0,
    this.totalErrorsImported = 0,
    this.totalAttachmentsImported = 0,
    this.doorChanges = const [],
    this.newCatalogProposals = const [],
    this.fileReports = const [],
    this.doorConflicts = const [],
    this.catalogConflicts = const [],
    this.importReport,
    this.excelResult,
  });

  bool get hasConflicts => doorConflicts.isNotEmpty || catalogConflicts.isNotEmpty;
  bool get hasDoorConflicts => doorConflicts.isNotEmpty;
  bool get hasCatalogConflicts => catalogConflicts.isNotEmpty;
}

class BatchMigrationService {
  static const Set<String> packageExtensions = {'db', 'db3', 'wartung', 'sqlite'};
  static const Set<String> excelExtensions = {'xlsx', 'xls', 'xlsm', 'xlms', 'csv'};

  /// Helper to check if a file extension is supported for migration.
  static bool isCompliantFile(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return packageExtensions.contains(ext) ||
        excelExtensions.contains(ext);
  }

  /// Recursively collects all files from a directory path.
  static List<File> getFilesFromDirectory(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];

    final files = <File>[];
    try {
      final entities = dir.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          // Skip hidden OS/system files
          final name = entity.path.split(Platform.pathSeparator).last;
          if (!name.startsWith('.')) {
            files.add(entity);
          }
        }
      }
    } catch (_) {}
    return files;
  }

  /// Migrates a single file and returns detailed per-file results and conflicts.
  static Future<SingleFileMigrationResult> migrateSingleFile(
    File file, {
    List<ConflictResolution>? resolutions,
  }) async {
    final fileName = file.path.split(Platform.pathSeparator).last;

    if (!isCompliantFile(file.path)) {
      return SingleFileMigrationResult(
        file: file,
        fileName: fileName,
        isSkipped: true,
        errorMessage: 'Nicht unterstützt',
        fileReports: [
          InspectionFileReportItem(
            fileName: fileName,
            status: 'Übersprungen (Nicht unterstützt)',
          ),
        ],
      );
    }

    final ext = file.path.split('.').last.toLowerCase();
    try {
      if (packageExtensions.contains(ext)) {
        final report = await DatabaseService.importAndMergePackage(file.path);
        final fileReports = report.fileReports.isNotEmpty
            ? report.fileReports
            : [
                InspectionFileReportItem(
                  fileName: fileName,
                  newDoorsCount: report.newDoorsCount,
                  updatedDoorsCount: report.updatedDoorsCount,
                  defectsRecordedCount: report.totalErrorsImported,
                  attachmentsCount: report.totalAttachmentsImported,
                  doorChanges: report.doorChanges,
                  status: 'Erfolgreich',
                ),
              ];

        return SingleFileMigrationResult(
          file: file,
          fileName: fileName,
          isSuccess: true,
          newDoorsCount: report.newDoorsCount,
          updatedDoorsCount: report.updatedDoorsCount,
          newInspectionsCount: report.newInspectionsCount,
          updatedInspectionsCount: report.updatedInspectionsCount,
          totalErrorsImported: report.totalErrorsImported,
          totalAttachmentsImported: report.totalAttachmentsImported,
          doorChanges: report.doorChanges,
          newCatalogProposals: report.newCatalogProposals,
          fileReports: fileReports,
          doorConflicts: report.doorConflicts,
          importReport: report,
        );
      } else if (excelExtensions.contains(ext)) {
        final excelResult = await ExcelDataImporter.importFromFile(file, resolutions: resolutions);
        final doorCount = excelResult.doorsImported;
        final excelDoorItems = [
          DoorChangeItem(
            doorAlias: 'Excel-Import: $fileName',
            doorNumber: '$doorCount Türen',
            roomDesignation: 'Excel Import (${excelResult.sheetsProcessed} Blätter)',
            changeType: 'new',
          )
        ];

        String statusStr = 'Erfolgreich';
        final conflictParts = <String>[];
        if (excelResult.hasDoorConflicts) {
          conflictParts.add('${excelResult.doorConflicts.length} Türkonflikte');
        }
        if (excelResult.hasCatalogConflicts) {
          conflictParts.add('${excelResult.catalogConflicts.length} Katalogkonflikte');
        }
        if (conflictParts.isNotEmpty) {
          statusStr = 'Konflikte zur Überprüfung (${conflictParts.join(", ")})';
        }

        return SingleFileMigrationResult(
          file: file,
          fileName: fileName,
          isSuccess: true,
          newDoorsCount: doorCount,
          totalErrorsImported: excelResult.errorsLinked,
          doorChanges: excelDoorItems,
          fileReports: [
            InspectionFileReportItem(
              fileName: fileName,
              newDoorsCount: doorCount,
              defectsRecordedCount: excelResult.errorsLinked,
              doorChanges: excelDoorItems,
              status: statusStr,
            ),
          ],
          doorConflicts: excelResult.doorConflicts,
          catalogConflicts: excelResult.catalogConflicts,
          excelResult: excelResult,
        );
      }
    } catch (e) {
      return SingleFileMigrationResult(
        file: file,
        fileName: fileName,
        isSuccess: false,
        isSkipped: true,
        errorMessage: 'Fehler: $e',
        fileReports: [
          InspectionFileReportItem(
            fileName: fileName,
            status: 'Fehler: $e',
          ),
        ],
      );
    }

    return SingleFileMigrationResult(
      file: file,
      fileName: fileName,
      isSkipped: true,
      errorMessage: 'Unbekanntes Dateiformat',
      fileReports: [
        InspectionFileReportItem(
          fileName: fileName,
          status: 'Übersprungen (Unbekanntes Format)',
        ),
      ],
    );
  }

  /// Processes a list of files sequentially, updating progress via callback.
  static Future<BatchMigrationResult> migrateFiles(
    List<File> files, {
    Function(int current, int total, String currentFileName)? onProgress,
  }) async {
    int newDoorsCount = 0;
    int updatedDoorsCount = 0;
    int newInspectionsCount = 0;
    int updatedInspectionsCount = 0;
    int totalErrorsImported = 0;
    int totalAttachmentsImported = 0;
    final List<DoorChangeItem> doorChanges = [];
    final List<String> newCatalogProposals = [];
    final List<InspectionFileReportItem> fileReports = [];
    final List<DoorConflict> doorConflicts = [];
    final List<ImportConflict> catalogConflicts = [];
    final List<LegacyMigrationAudit> legacyAudits = [];

    int compliantProcessed = 0;
    int skippedCount = 0;
    final List<String> processedNames = [];
    final List<String> skippedNames = [];

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileName = file.path.split(Platform.pathSeparator).last;

      if (onProgress != null) {
        onProgress(i + 1, files.length, fileName);
      }

      final singleResult = await migrateSingleFile(file);

      if (singleResult.isSkipped) {
        skippedCount++;
        skippedNames.add(singleResult.errorMessage != null ? '$fileName (${singleResult.errorMessage})' : fileName);
        fileReports.addAll(singleResult.fileReports);
        continue;
      }

      compliantProcessed++;
      processedNames.add(fileName);
      newDoorsCount += singleResult.newDoorsCount;
      updatedDoorsCount += singleResult.updatedDoorsCount;
      newInspectionsCount += singleResult.newInspectionsCount;
      updatedInspectionsCount += singleResult.updatedInspectionsCount;
      totalErrorsImported += singleResult.totalErrorsImported;
      totalAttachmentsImported += singleResult.totalAttachmentsImported;
      doorChanges.addAll(singleResult.doorChanges);
      newCatalogProposals.addAll(singleResult.newCatalogProposals);
      fileReports.addAll(singleResult.fileReports);
      doorConflicts.addAll(singleResult.doorConflicts);
      catalogConflicts.addAll(singleResult.catalogConflicts);
      if (singleResult.importReport != null && singleResult.importReport!.legacyAudits.isNotEmpty) {
        legacyAudits.addAll(singleResult.importReport!.legacyAudits);
      }
    }

    final aggregatedReport = ImportReport(
      packageName: 'Batch-Migration (${processedNames.length} Dateien)',
      importedAt: DateTime.now(),
      newDoorsCount: newDoorsCount,
      updatedDoorsCount: updatedDoorsCount,
      newInspectionsCount: newInspectionsCount,
      updatedInspectionsCount: updatedInspectionsCount,
      totalErrorsImported: totalErrorsImported,
      totalAttachmentsImported: totalAttachmentsImported,
      doorChanges: doorChanges,
      newCatalogProposals: newCatalogProposals,
      fileReports: fileReports,
      doorConflicts: doorConflicts,
      legacyAudits: legacyAudits,
    );

    return BatchMigrationResult(
      aggregatedReport: aggregatedReport,
      doorConflicts: doorConflicts,
      catalogConflicts: catalogConflicts,
      totalFilesFound: files.length,
      compliantFilesProcessed: compliantProcessed,
      skippedFilesCount: skippedCount,
      processedFileNames: processedNames,
      skippedFileNames: skippedNames,
    );
  }
}
