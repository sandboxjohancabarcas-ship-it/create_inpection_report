import 'dart:io';
import 'package:wartungstool/models/door_conflict.dart';
import 'package:wartungstool/models/import_report.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';
import 'package:wartungstool/pages/read_customer_data.dart';

class BatchMigrationResult {
  final ImportReport aggregatedReport;
  final List<DoorConflict> doorConflicts;
  final int totalFilesFound;
  final int compliantFilesProcessed;
  final int skippedFilesCount;
  final List<String> processedFileNames;
  final List<String> skippedFileNames;

  BatchMigrationResult({
    required this.aggregatedReport,
    this.doorConflicts = const [],
    required this.totalFilesFound,
    required this.compliantFilesProcessed,
    required this.skippedFilesCount,
    required this.processedFileNames,
    required this.skippedFileNames,
  });
}

class BatchMigrationService {
  static const Set<String> packageExtensions = {'db', 'db3', 'wartung', 'sqlite'};
  static const Set<String> excelExtensions = {'xlsx', 'xls', 'xlsm', 'xlms', 'csv'};
  static const Set<String> pdfExtensions = {'pdf'};

  /// Helper to check if a file extension is supported for migration.
  static bool isCompliantFile(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return packageExtensions.contains(ext) ||
        excelExtensions.contains(ext) ||
        pdfExtensions.contains(ext);
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

      if (!isCompliantFile(file.path)) {
        skippedCount++;
        skippedNames.add(fileName);
        fileReports.add(InspectionFileReportItem(
          fileName: fileName,
          status: 'Übersprungen (Nicht unterstützt)',
        ));
        continue;
      }

      final ext = file.path.split('.').last.toLowerCase();
      try {
        if (packageExtensions.contains(ext)) {
          final report = await DatabaseService.importAndMergePackage(file.path);
          newDoorsCount += report.newDoorsCount;
          updatedDoorsCount += report.updatedDoorsCount;
          newInspectionsCount += report.newInspectionsCount;
          updatedInspectionsCount += report.updatedInspectionsCount;
          totalErrorsImported += report.totalErrorsImported;
          totalAttachmentsImported += report.totalAttachmentsImported;
          doorChanges.addAll(report.doorChanges);
          newCatalogProposals.addAll(report.newCatalogProposals);
          fileReports.addAll(report.fileReports.isNotEmpty
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
                ]);
          compliantProcessed++;
          processedNames.add(fileName);
        } else if (excelExtensions.contains(ext)) {
          final excelResult = await ExcelDataImporter.importFromFile(file);
          final doorCount = excelResult.doorsImported;
          newDoorsCount += doorCount;

          if (excelResult.hasDoorConflicts) {
            doorConflicts.addAll(excelResult.doorConflicts);
          }

          final excelDoorItems = [
            DoorChangeItem(
              doorAlias: 'Excel-Import: $fileName',
              doorNumber: '$doorCount Türen',
              roomDesignation: 'Excel Import (${excelResult.sheetsProcessed} Blätter)',
              changeType: 'new',
            )
          ];

          doorChanges.addAll(excelDoorItems);
          fileReports.add(InspectionFileReportItem(
            fileName: fileName,
            newDoorsCount: doorCount,
            defectsRecordedCount: excelResult.errorsLinked,
            doorChanges: excelDoorItems,
            status: excelResult.hasDoorConflicts
                ? 'Konflikte zur Überprüfung (${excelResult.doorConflicts.length})'
                : 'Erfolgreich',
          ));
          compliantProcessed++;
          processedNames.add(fileName);
        } else if (pdfExtensions.contains(ext)) {
          await CustomerDataImporter.importFromPdfFile(file);
          compliantProcessed++;
          processedNames.add(fileName);
          final pdfDoorItem = DoorChangeItem(
            doorAlias: 'PDF-Import: $fileName',
            doorNumber: 'Kundendaten',
            roomDesignation: 'PDF Stammimport',
            changeType: 'new',
          );
          doorChanges.add(pdfDoorItem);
          fileReports.add(InspectionFileReportItem(
            fileName: fileName,
            doorChanges: [pdfDoorItem],
            status: 'Erfolgreich',
          ));
        }
      } catch (e) {
        skippedCount++;
        skippedNames.add('$fileName (Fehler: $e)');
        fileReports.add(InspectionFileReportItem(
          fileName: fileName,
          status: 'Fehler: $e',
        ));
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
    );

    return BatchMigrationResult(
      aggregatedReport: aggregatedReport,
      doorConflicts: doorConflicts,
      totalFilesFound: files.length,
      compliantFilesProcessed: compliantProcessed,
      skippedFilesCount: skippedCount,
      processedFileNames: processedNames,
      skippedFileNames: skippedNames,
    );
  }
}
