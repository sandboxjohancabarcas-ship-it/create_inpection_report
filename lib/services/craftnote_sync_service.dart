import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/models/craftnote_models.dart';
import 'package:wartungstool/services/craftnote_api_service.dart';
import 'package:wartungstool/services/craftnote_credentials_service.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/utils/file_export_helper.dart';

/// Result container for Craftnote upload and sync operations.
class CraftnoteSyncResult {
  final bool success;
  final String message;
  final String? uploadedDbFileId;
  final String? uploadedPdfFileId;
  final bool isQueuedOffline;
  final int? queueId;
  final Object? error;

  const CraftnoteSyncResult({
    required this.success,
    required this.message,
    this.uploadedDbFileId,
    this.uploadedPdfFileId,
    this.isQueuedOffline = false,
    this.queueId,
    this.error,
  });

  @override
  String toString() =>
      'CraftnoteSyncResult(success: $success, isQueuedOffline: $isQueuedOffline, message: $message)';
}

/// Result container for Craftnote download and import operations.
class CraftnoteImportResult {
  final bool success;
  final String message;
  final ImportReport? report;
  final Object? error;

  const CraftnoteImportResult({
    required this.success,
    required this.message,
    this.report,
    this.error,
  });

  @override
  String toString() =>
      'CraftnoteImportResult(success: $success, message: $message, report: $report)';
}

/// Summary report of offline upload queue processing.
class SyncQueueReport {
  final int processed;
  final int succeeded;
  final int failed;
  final List<String> errorMessages;

  const SyncQueueReport({
    required this.processed,
    required this.succeeded,
    required this.failed,
    required this.errorMessages,
  });

  bool get hasErrors => failed > 0;
  bool get allSucceeded => processed > 0 && failed == 0;

  @override
  String toString() =>
      'SyncQueueReport(processed: $processed, succeeded: $succeeded, failed: $failed)';
}

/// Orchestrates cross-platform synchronization between WartungsTool SQLite databases
/// (both Master DB and Inspector working DB) and Craftnote cloud projects.
class CraftnoteSyncService {
  final CraftnoteApiService apiService;

  /// Optional override for testing online/offline state transitions.
  bool? overrideOnlineStatus;

  CraftnoteSyncService({
    CraftnoteApiService? apiService,
    this.overrideOnlineStatus,
  }) : apiService = apiService ?? CraftnoteApiService();

  /// Checks internet connectivity to Craftnote API servers.
  Future<bool> hasInternetConnection() async {
    if (overrideOnlineStatus != null) {
      return overrideOnlineStatus!;
    }
    // If mock adapter is explicitly active, treat as online
    if (CraftnoteCredentialsService.isMockMode) {
      return true;
    }
    return await apiService.checkInternetConnection();
  }

  // ─────────────────────────────────────────────────────────────
  // DESKTOP / MANAGER FLOW
  // ─────────────────────────────────────────────────────────────

  /// Exports an inspection from Master DB, bundles it into a standard SQLite package,
  /// uploads it directly to the designated Craftnote project, and posts a project message.
  Future<CraftnoteSyncResult> exportInspectionFromMasterDb({
    required int inspectionId,
    required String craftnoteProjectId,
    String? pdfReportPath,
  }) async {
    try {
      final insp = await DatabaseService.getInspectionById(inspectionId);
      if (insp == null) {
        return CraftnoteSyncResult(
          success: false,
          message: 'Auftrag mit ID $inspectionId wurde nicht in der Master-Datenbank gefunden.',
        );
      }

      // Generate package file (.db)
      final packagePath = await DatabaseService.exportJobPackage([inspectionId]);
      final packageFile = File(packagePath);
      if (!await packageFile.exists()) {
        return const CraftnoteSyncResult(
          success: false,
          message: 'Export-Paketdatei konnte nicht generiert werden.',
        );
      }

      // Upload SQLite database package
      final dbUpload = await apiService.uploadFile(
        projectId: craftnoteProjectId,
        file: packageFile,
        fileName: p.basename(packagePath),
      );

      // Upload PDF report if provided
      CraftnoteFile? pdfUpload;
      if (pdfReportPath != null && await File(pdfReportPath).exists()) {
        pdfUpload = await apiService.uploadFile(
          projectId: craftnoteProjectId,
          file: File(pdfReportPath),
          fileName: p.basename(pdfReportPath),
        );
      }

      // Post chat notification to project
      final jobNum = insp['jobNumber'] ?? insp['auftragsnummer'] ?? '$inspectionId';
      final client = insp['clientName'] ?? insp['customerName'] ?? '';
      final address = insp['objectAddress'] ?? '';
      final buffer = StringBuffer('📦 [WartungsTool] Neuer Wartungsauftrag übertragen:\n');
      buffer.writeln('• Auftrag: #$jobNum');
      if (client.toString().isNotEmpty) buffer.writeln('• Kunde: $client');
      if (address.toString().isNotEmpty) buffer.writeln('• Objekt: $address');
      buffer.writeln('• Paketdatei: ${p.basename(packagePath)}');
      if (pdfUpload != null) buffer.writeln('• PDF-Bericht beigelegt');

      await apiService.postMessage(
        craftnoteProjectId,
        buffer.toString().trim(),
      );

      // Update Master DB inspection linkage & status
      await DatabaseService.updateInspectionCraftnoteStatus(
        inspectionId,
        projectId: craftnoteProjectId,
        fileId: dbUpload.id,
        syncStatus: 'synced',
        lastSyncTime: DateTime.now().toIso8601String(),
      );

      return CraftnoteSyncResult(
        success: true,
        message: 'Auftrag erfolgreich nach Craftnote exportiert.',
        uploadedDbFileId: dbUpload.id,
        uploadedPdfFileId: pdfUpload?.id,
      );
    } catch (e) {
      return CraftnoteSyncResult(
        success: false,
        message: 'Fehler beim Export nach Craftnote: $e',
        error: e,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // MOBILE / INSPECTOR IMPORT FLOW
  // ─────────────────────────────────────────────────────────────

  /// Downloads an inspection package (.db) from Craftnote and imports/merges it
  /// into the local working SQLite database.
  Future<CraftnoteImportResult> downloadAndImportPackage({
    required CraftnoteProject project,
    required CraftnoteFile file,
  }) async {
    try {
      if (!file.isSqliteDatabase && !file.name.toLowerCase().endsWith('.db')) {
        return CraftnoteImportResult(
          success: false,
          message: 'Die ausgewählte Datei "${file.name}" ist keine SQLite-Paketdatenbank (.db).',
        );
      }

      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(
        tempDir.path,
        'cn_import_${DateTime.now().millisecondsSinceEpoch}_${file.name}',
      );

      // Download file from Craftnote
      await apiService.downloadFile(
        file.id,
        tempPath,
      );

      final downloadedFile = File(tempPath);
      if (!await downloadedFile.exists() || await downloadedFile.length() == 0) {
        return const CraftnoteImportResult(
          success: false,
          message: 'Heruntergeladene Datei ist leer oder existiert nicht.',
        );
      }

      // Merge into local working database
      final report = await LocalDatabaseService.importAndMergePackage(tempPath);

      // Link newly imported inspection(s) to this Craftnote project
      final localInspections = await LocalDatabaseService.getAllInspections();
      for (final insp in localInspections) {
        final inspId = insp['inspectionId'] as int;
        await LocalDatabaseService.updateInspectionCraftnoteStatus(
          inspId,
          projectId: project.id,
          fileId: file.id,
          syncStatus: 'downloaded',
          lastSyncTime: DateTime.now().toIso8601String(),
        );
      }

      // Clean up temporary download file
      try {
        if (await downloadedFile.exists()) {
          await downloadedFile.delete();
        }
      } catch (_) {}

      return CraftnoteImportResult(
        success: true,
        message: 'Auftrag erfolgreich aus Craftnote importiert (${report.newDoorsCount} Türen neu, ${report.updatedDoorsCount} aktualisiert).',
        report: report,
      );
    } catch (e) {
      return CraftnoteImportResult(
        success: false,
        message: 'Fehler beim Importieren aus Craftnote: $e',
        error: e,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // MOBILE / INSPECTOR RETURN & OFFLINE QUEUE FLOW
  // ─────────────────────────────────────────────────────────────

  /// Completes an inspection in the local database and uploads the result package (.db)
  /// back to Craftnote. If offline, the task is safely persisted in the SQLite offline queue.
  Future<CraftnoteSyncResult> completeAndUploadFromLocalDb({
    required int inspectionId,
    String? pdfReportPath,
  }) async {
    try {
      final insp = await LocalDatabaseService.getInspectionById(inspectionId);
      if (insp == null) {
        return CraftnoteSyncResult(
          success: false,
          message: 'Inspektion $inspectionId nicht in lokaler Datenbank gefunden.',
        );
      }

      final projectId = insp['craftnoteProjectId']?.toString();
      if (projectId == null || projectId.trim().isEmpty) {
        return const CraftnoteSyncResult(
          success: false,
          message: 'Kein verknüpftes Craftnote-Projekt für diesen Auftrag hinterlegt. Bitte verknüpfen Sie den Auftrag zuerst mit einem Projekt.',
        );
      }

      // Retrieve doors associated with this inspection
      final db = await LocalDatabaseService.getDb();
      final junctionRows = await db.query(
        'inspection_doors',
        columns: ['doorId'],
        where: 'inspectionId = ?',
        whereArgs: [inspectionId],
      );
      final doorIds = junctionRows.map((r) => r['doorId'] as int).toList();
      if (doorIds.isEmpty) {
        return const CraftnoteSyncResult(
          success: false,
          message: 'Keine Türen in dieser Inspektion enthalten. Export abgebrochen.',
        );
      }

      // Generate selective job package to documents directory
      final docDir = await getApplicationDocumentsDirectory();
      final fileName = FileExportHelper.buildPackageFileName(
        jobNumber: insp['jobNumber']?.toString(),
        projectNumber: insp['projectNumber']?.toString(),
        objectAddress: insp['objectAddress']?.toString() ?? insp['clientName']?.toString(),
        packageType: 'inspektion_ergebnis',
      );
      final exportPackagePath = p.join(docDir.path, fileName);
      await LocalDatabaseService.exportSelectiveJobPackage(doorIds, exportPackagePath);

      final isOnline = await hasInternetConnection();

      if (!isOnline) {
        // Enqueue offline for background sync
        final queueItem = CraftnoteUploadQueueItem(
          inspectionId: inspectionId,
          craftnoteProjectId: projectId,
          packageFilePath: exportPackagePath,
          pdfFilePath: (pdfReportPath != null && await File(pdfReportPath).exists()) ? pdfReportPath : null,
          queuedAt: DateTime.now().toIso8601String(),
        );
        final queueId = await LocalDatabaseService.enqueueCraftnoteUpload(queueItem);
        await LocalDatabaseService.updateInspectionCraftnoteStatus(
          inspectionId,
          syncStatus: 'queued',
        );

        return CraftnoteSyncResult(
          success: true,
          isQueuedOffline: true,
          queueId: queueId,
          message: 'Offline-Modus: Kein Internet verfügbar. Der Auftrag wurde sicher in die Offline-Warteschlange eingereiht.',
        );
      }

      // Attempt online upload
      try {
        final dbUpload = await apiService.uploadFile(
          projectId: projectId,
          file: File(exportPackagePath),
          fileName: p.basename(exportPackagePath),
        );

        CraftnoteFile? pdfUpload;
        if (pdfReportPath != null && await File(pdfReportPath).exists()) {
          pdfUpload = await apiService.uploadFile(
            projectId: projectId,
            file: File(pdfReportPath),
            fileName: p.basename(pdfReportPath),
          );
        }

        final inspector = insp['inspectorName'] ?? 'Prüfer';
        final jobNum = insp['jobNumber'] ?? '$inspectionId';
        final buffer = StringBuffer('✅ [WartungsTool] Wartung abgeschlossen von $inspector:\n');
        buffer.writeln('• Auftrag: #$jobNum');
        buffer.writeln('• ${doorIds.length} Türen geprüft und übertragen');
        buffer.writeln('• Ergebnis-Paket: ${p.basename(exportPackagePath)}');
        if (pdfUpload != null) buffer.writeln('• PDF-Prüfbericht angehängt');

        await apiService.postMessage(
          projectId,
          buffer.toString().trim(),
        );

        await LocalDatabaseService.updateInspectionCraftnoteStatus(
          inspectionId,
          fileId: dbUpload.id,
          syncStatus: 'synced',
          lastSyncTime: DateTime.now().toIso8601String(),
        );

        return CraftnoteSyncResult(
          success: true,
          isQueuedOffline: false,
          uploadedDbFileId: dbUpload.id,
          uploadedPdfFileId: pdfUpload?.id,
          message: 'Wartung erfolgreich abgeschlossen und mit Craftnote synchronisiert.',
        );
      } catch (uploadError) {
        // Fallback to offline queue if upload fails unexpectedly
        final queueItem = CraftnoteUploadQueueItem(
          inspectionId: inspectionId,
          craftnoteProjectId: projectId,
          packageFilePath: exportPackagePath,
          pdfFilePath: (pdfReportPath != null && await File(pdfReportPath).exists()) ? pdfReportPath : null,
          queuedAt: DateTime.now().toIso8601String(),
          lastError: uploadError.toString(),
        );
        final queueId = await LocalDatabaseService.enqueueCraftnoteUpload(queueItem);
        await LocalDatabaseService.updateInspectionCraftnoteStatus(
          inspectionId,
          syncStatus: 'queued',
        );

        return CraftnoteSyncResult(
          success: true,
          isQueuedOffline: true,
          queueId: queueId,
          message: 'Verbindungsabbruch während der Übertragung. Auftrag wurde in die Offline-Warteschlange eingereiht.',
          error: uploadError,
        );
      }
    } catch (e) {
      return CraftnoteSyncResult(
        success: false,
        message: 'Fehler beim Abschließen der Inspektion: $e',
        error: e,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // BACKGROUND SYNC / QUEUE PROCESSOR
  // ─────────────────────────────────────────────────────────────

  /// Processes all pending upload tasks currently in the SQLite offline queue.
  /// Automatically called on app start, reconnect, or manual trigger.
  Future<SyncQueueReport> processPendingUploadQueue() async {
    final isOnline = await hasInternetConnection();
    if (!isOnline) {
      return const SyncQueueReport(
        processed: 0,
        succeeded: 0,
        failed: 0,
        errorMessages: ['Keine Internetverbindung verfügbar.'],
      );
    }

    final pendingItems = await LocalDatabaseService.getPendingCraftnoteUploads();
    if (pendingItems.isEmpty) {
      return const SyncQueueReport(
        processed: 0,
        succeeded: 0,
        failed: 0,
        errorMessages: [],
      );
    }

    int succeeded = 0;
    int failed = 0;
    final errorMessages = <String>[];

    for (final item in pendingItems) {
      final pkgFile = File(item.packageFilePath);
      if (!await pkgFile.exists()) {
        failed++;
        final err = 'Paketdatei ${item.packageFilePath} nicht mehr auf dem Gerät vorhanden.';
        errorMessages.add(err);
        await LocalDatabaseService.incrementCraftnoteUploadAttempt(item.id!, error: err);
        continue;
      }

      try {
        final dbUpload = await apiService.uploadFile(
          projectId: item.craftnoteProjectId,
          file: pkgFile,
          fileName: p.basename(item.packageFilePath),
        );

        if (item.pdfFilePath != null && await File(item.pdfFilePath!).exists()) {
          await apiService.uploadFile(
            projectId: item.craftnoteProjectId,
            file: File(item.pdfFilePath!),
            fileName: p.basename(item.pdfFilePath!),
          );
        }

        await apiService.postMessage(
          item.craftnoteProjectId,
          '🔄 [WartungsTool] Nachträgliche Synchronisierung aus Offline-Warteschlange erfolgreich abgeschlossen (${p.basename(item.packageFilePath)}).',
        );

        await LocalDatabaseService.deleteCraftnoteUploadQueueItem(item.id!);

        if (item.inspectionId != null) {
          await LocalDatabaseService.updateInspectionCraftnoteStatus(
            item.inspectionId!,
            fileId: dbUpload.id,
            syncStatus: 'synced',
            lastSyncTime: DateTime.now().toIso8601String(),
          );
        }

        succeeded++;
      } catch (e) {
        failed++;
        errorMessages.add('Fehler bei Upload für Projekt ${item.craftnoteProjectId}: $e');
        await LocalDatabaseService.incrementCraftnoteUploadAttempt(item.id!, error: e.toString());
      }
    }

    return SyncQueueReport(
      processed: pendingItems.length,
      succeeded: succeeded,
      failed: failed,
      errorMessages: errorMessages,
    );
  }
}
