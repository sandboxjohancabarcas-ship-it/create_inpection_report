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
import 'package:wartungstool/services/photo_export_service.dart';
import 'package:wartungstool/utils/file_export_helper.dart';

/// Standard project target folders used by the automated Craftnote sync.
class CraftnoteProjectStandardFolders {
  final String? wartungslistenFolderId;
  final String? fotomaterialFolderId;
  final String? wartungslistenPath;
  final String? fotomaterialPath;

  const CraftnoteProjectStandardFolders({
    this.wartungslistenFolderId,
    this.fotomaterialFolderId,
    this.wartungslistenPath,
    this.fotomaterialPath,
  });

  bool get hasWartungslisten => wartungslistenFolderId != null;
  bool get hasFotomaterial => fotomaterialFolderId != null;

  String formatFolderInfo() {
    final wInfo = wartungslistenPath ?? (hasWartungslisten ? 'Wartungslisten' : 'Root');
    final fInfo = fotomaterialPath ?? (hasFotomaterial ? 'Fotomaterial' : 'Root');
    return 'Wartungslisten: $wInfo | Fotomaterial: $fInfo';
  }
}

/// Summary report of an inspection photo sync to Craftnote Fotomaterial folder.
class CraftnotePhotoSyncResult {
  final int totalFound;
  final int uploadedCount;
  final int skippedCount;
  final List<String> uploadedFiles;
  final List<String> skippedFiles;

  const CraftnotePhotoSyncResult({
    required this.totalFound,
    required this.uploadedCount,
    required this.skippedCount,
    this.uploadedFiles = const [],
    this.skippedFiles = const [],
  });

  int get totalPhotos => totalFound;
  int get uploadedPhotos => uploadedCount;
  int get skippedPhotos => skippedCount;
  List<String> get uploadedFileNames => uploadedFiles;
  List<String> get skippedFileNames => skippedFiles;
}

/// Result container for Craftnote upload and sync operations.
class CraftnoteSyncResult {
  final bool success;
  final String message;
  final String? uploadedDbFileId;
  final String? uploadedPdfFileId;
  final bool isQueuedOffline;
  final int? queueId;
  final Object? error;
  final int totalPhotos;
  final int uploadedPhotos;
  final int skippedPhotos;
  final String? wartungslistenFolderId;
  final String? fotomaterialFolderId;

  const CraftnoteSyncResult({
    required this.success,
    required this.message,
    this.uploadedDbFileId,
    this.uploadedPdfFileId,
    this.isQueuedOffline = false,
    this.queueId,
    this.error,
    this.totalPhotos = 0,
    this.uploadedPhotos = 0,
    this.skippedPhotos = 0,
    this.wartungslistenFolderId,
    this.fotomaterialFolderId,
  });

  @override
  String toString() =>
      'CraftnoteSyncResult(success: $success, isQueuedOffline: $isQueuedOffline, photos: $uploadedPhotos/$totalPhotos, message: $message)';
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

  /// Resolves the standard folders "Wartungslisten" and "Fotomaterial" for a given Craftnote project.
  Future<CraftnoteProjectStandardFolders> resolveProjectStandardFolders(String projectId) async {
    try {
      final files = await apiService.getProjectFiles(projectId);
      final folders = files.where((f) => f.isFolder).toList();

      final folderMap = {for (final f in folders) f.id: f};
      String buildPath(CraftnoteFile f) {
        final segments = <String>[f.name];
        var curr = f;
        while (curr.folderId != null && folderMap.containsKey(curr.folderId)) {
          curr = folderMap[curr.folderId]!;
          segments.insert(0, curr.name);
        }
        return segments.join(' / ');
      }

      CraftnoteFile? wartungslistenFolder;
      CraftnoteFile? fotomaterialFolder;

      for (final f in folders) {
        final lower = f.name.trim().toLowerCase();
        if (lower == 'wartungslisten' || lower.contains('wartungsliste')) {
          wartungslistenFolder = f;
        } else if (lower == 'fotomaterial' || lower.contains('fotomaterial') || lower == 'fotos') {
          fotomaterialFolder = f;
        }
      }

      return CraftnoteProjectStandardFolders(
        wartungslistenFolderId: wartungslistenFolder?.id,
        fotomaterialFolderId: fotomaterialFolder?.id,
        wartungslistenPath: wartungslistenFolder != null ? buildPath(wartungslistenFolder) : null,
        fotomaterialPath: fotomaterialFolder != null ? buildPath(fotomaterialFolder) : null,
      );
    } catch (e) {
      print('[CraftnoteSyncService] Error resolving standard folders: $e');
      return const CraftnoteProjectStandardFolders();
    }
  }

  /// Extracts inspection photos and uploads only non-existing ones into the Craftnote Fotomaterial folder.
  Future<CraftnotePhotoSyncResult> syncInspectionPhotos({
    required int inspectionId,
    required String craftnoteProjectId,
    String? fotomaterialFolderId,
    bool isManagerMode = true,
  }) async {
    // Safety Sandbox Guard: Redirect to testProjectId if test mode is active
    String targetProjectId = craftnoteProjectId;
    if (CraftnoteCredentialsService.isTestMode && craftnoteProjectId != CraftnoteCredentialsService.testProjectId) {
      targetProjectId = CraftnoteCredentialsService.testProjectId;
    }

    final tempDir = await Directory.systemTemp.createTemp('craftnote_photos_');
    try {
      final photoResult = await PhotoExportService.exportInspectionPhotos(
        inspectionId: inspectionId,
        destinationDir: tempDir.path,
        isManagerMode: isManagerMode,
      );

      if (photoResult.totalPhotos == 0 || photoResult.exportedFileNames.isEmpty) {
        return const CraftnotePhotoSyncResult(
          totalFound: 0,
          uploadedCount: 0,
          skippedCount: 0,
        );
      }

      // Query existing files in Craftnote project
      final projectFiles = await apiService.getProjectFiles(targetProjectId);
      final existingNames = projectFiles
          .where((f) => !f.isFolder && (fotomaterialFolderId == null || f.folderId == fotomaterialFolderId))
          .map((f) => f.name.toLowerCase().trim())
          .toSet();

      final List<String> uploaded = [];
      final List<String> skipped = [];

      for (final fileName in photoResult.exportedFileNames) {
        final lowerName = fileName.toLowerCase().trim();
        if (existingNames.contains(lowerName)) {
          print('[CraftnoteSyncService] ⏩ Photo "$fileName" already exists in Fotomaterial, skipping upload.');
          skipped.add(fileName);
          continue;
        }

        final photoFile = File(p.join(tempDir.path, fileName));
        if (!await photoFile.exists()) continue;

        print('[CraftnoteSyncService] ⬆️ Uploading photo "$fileName" to Fotomaterial...');
        await apiService.uploadFile(
          projectId: targetProjectId,
          file: photoFile,
          fileName: fileName,
          folderId: fotomaterialFolderId,
        );
        uploaded.add(fileName);
        existingNames.add(lowerName); // prevent double upload if same filename in batch
      }

      return CraftnotePhotoSyncResult(
        totalFound: photoResult.totalPhotos,
        uploadedCount: uploaded.length,
        skippedCount: skipped.length,
        uploadedFiles: uploaded,
        skippedFiles: skipped,
      );
    } catch (e) {
      print('[CraftnoteSyncService] ⚠️ Error syncing inspection photos: $e');
      return const CraftnotePhotoSyncResult(
        totalFound: 0,
        uploadedCount: 0,
        skippedCount: 0,
      );
    } finally {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  // ─────────────────────────────────────────────────────────────
  // DESKTOP / MANAGER FLOW
  // ─────────────────────────────────────────────────────────────

  /// Exports an inspection from Master DB, bundles it into a standard SQLite package,
  /// uploads it directly to the designated Craftnote project, and posts a project message.
  Future<CraftnoteSyncResult> exportInspectionFromMasterDb({
    required int inspectionId,
    required String craftnoteProjectId,
    String? targetFolderId,
    String? pdfReportPath,
    bool postChatMessage = false,
    bool syncPhotos = true,
  }) async {
    try {
      final insp = await DatabaseService.getInspectionById(inspectionId);
      if (insp == null) {
        return CraftnoteSyncResult(
          success: false,
          message: 'Auftrag mit ID $inspectionId wurde nicht in der Master-Datenbank gefunden.',
        );
      }

      // Safety Sandbox Guard: Redirect to testProjectId if test mode is active
      String targetProjectId = craftnoteProjectId;
      bool wasRedirected = false;
      if (CraftnoteCredentialsService.isTestMode && craftnoteProjectId != CraftnoteCredentialsService.testProjectId) {
        print('[CraftnoteSyncService] 🛡️ TEST MODE GUARD: Redirecting upload from "$craftnoteProjectId" to sandbox test project "${CraftnoteCredentialsService.testProjectId}" (#${CraftnoteCredentialsService.testProjectOrderNumber}) to protect live production data.');
        targetProjectId = CraftnoteCredentialsService.testProjectId;
        wasRedirected = true;
      } else if (!CraftnoteCredentialsService.isTestMode) {
        // In Production Mode: Prevent export into archived projects
        try {
          final targetProj = await apiService.getProjectById(craftnoteProjectId);
          if (targetProj.archived) {
            return CraftnoteSyncResult(
              success: false,
              message: 'Das Ziel-Projekt "${targetProj.name}" (#${targetProj.orderNumber}) ist in Craftnote bereits archiviert. Ein Export in archivierte Projekte ist nicht möglich.',
            );
          }
        } catch (_) {}
      }

      // 1. Resolve standard project target folders ("Wartungslisten" and "Fotomaterial")
      final standardFolders = await resolveProjectStandardFolders(targetProjectId);
      final effectiveWartungslistenId = targetFolderId ?? standardFolders.wartungslistenFolderId;

      // 2. Generate package file (.db)
      final packagePath = await DatabaseService.exportJobPackage([inspectionId]);
      final packageFile = File(packagePath);
      if (!await packageFile.exists()) {
        return const CraftnoteSyncResult(
          success: false,
          message: 'Export-Paketdatei konnte nicht generiert werden.',
        );
      }

      // 3. Upload SQLite database package into "Wartungslisten"
      final dbUpload = await apiService.uploadFile(
        projectId: targetProjectId,
        file: packageFile,
        fileName: p.basename(packagePath),
        folderId: effectiveWartungslistenId,
      );

      // 4. Upload PDF report if provided
      CraftnoteFile? pdfUpload;
      if (pdfReportPath != null && await File(pdfReportPath).exists()) {
        pdfUpload = await apiService.uploadFile(
          projectId: targetProjectId,
          file: File(pdfReportPath),
          fileName: p.basename(pdfReportPath),
          folderId: effectiveWartungslistenId,
        );
      }

      // 5. Upload inspection photos into "Fotomaterial" with deduplication
      CraftnotePhotoSyncResult photoSync = const CraftnotePhotoSyncResult(totalFound: 0, uploadedCount: 0, skippedCount: 0);
      if (syncPhotos) {
        photoSync = await syncInspectionPhotos(
          inspectionId: inspectionId,
          craftnoteProjectId: targetProjectId,
          fotomaterialFolderId: standardFolders.fotomaterialFolderId,
          isManagerMode: true,
        );
      }

      // 6. Optionally post chat notification to project feed
      String? messageWarning;
      if (postChatMessage) {
        try {
          final jobNum = insp['jobNumber'] ?? insp['auftragsnummer'] ?? '$inspectionId';
          final client = insp['clientName'] ?? insp['customerName'] ?? '';
          final address = insp['objectAddress'] ?? '';
          final buffer = StringBuffer('📦 [WartungsTool] Neuer Wartungsauftrag übertragen:\n');
          buffer.writeln('• Auftrag: #$jobNum');
          if (client.toString().isNotEmpty) buffer.writeln('• Kunde: $client');
          if (address.toString().isNotEmpty) buffer.writeln('• Objekt: $address');
          buffer.writeln('• Paketdatei: ${p.basename(packagePath)} (${standardFolders.wartungslistenPath ?? "Wartungslisten"})');
          if (pdfUpload != null) buffer.writeln('• PDF-Bericht beigelegt');
          if (photoSync.totalFound > 0) {
            buffer.writeln('• Fotos: ${photoSync.uploadedCount} neu übertragen, ${photoSync.skippedCount} übersprungen (${standardFolders.fotomaterialPath ?? "Fotomaterial"})');
          }

          await apiService.postMessage(
            targetProjectId,
            buffer.toString().trim(),
          );
        } catch (e) {
          messageWarning = 'Chat-Nachricht konnte nicht gesendet werden (erfordert Craftnote Advanced API: $e)';
          print('[CraftnoteSyncService] ⚠️ $messageWarning');
        }
      }

      // 7. Update Master DB inspection linkage & status
      await DatabaseService.updateInspectionCraftnoteStatus(
        inspectionId,
        projectId: targetProjectId,
        fileId: dbUpload.id,
        syncStatus: 'synced',
        lastSyncTime: DateTime.now().toIso8601String(),
      );

      final buffer = StringBuffer('Auftrag erfolgreich nach Craftnote exportiert.\n');
      if (wasRedirected) {
        buffer.writeln('🛡️ [Testumgebung aktiv] Upload wurde sicher in das Sandbox-Testprojekt (#${CraftnoteCredentialsService.testProjectOrderNumber}) geleitet, um Produktivdaten zu schützen.');
      }
      buffer.writeln('• Job-Paket abgelegt in: ${standardFolders.wartungslistenPath ?? "Wartungslisten"}');
      if (photoSync.totalFound > 0) {
        buffer.writeln('• Fotos: ${photoSync.uploadedCount} hochgeladen, ${photoSync.skippedCount} bereits vorhanden (übersprungen) in: ${standardFolders.fotomaterialPath ?? "Fotomaterial"}');
      } else {
        buffer.writeln('• Fotos: Keine Mängelfotos in dieser Inspektion enthalten.');
      }
      if (messageWarning != null) {
        buffer.writeln('\n(Hinweis: $messageWarning)');
      }

      return CraftnoteSyncResult(
        success: true,
        message: buffer.toString().trim(),
        uploadedDbFileId: dbUpload.id,
        uploadedPdfFileId: pdfUpload?.id,
        totalPhotos: photoSync.totalFound,
        uploadedPhotos: photoSync.uploadedCount,
        skippedPhotos: photoSync.skippedCount,
        wartungslistenFolderId: effectiveWartungslistenId,
        fotomaterialFolderId: standardFolders.fotomaterialFolderId,
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
  /// into either the local working database (for inspectors) or the Master database (for managers).
  Future<CraftnoteImportResult> downloadAndImportPackage({
    required CraftnoteProject project,
    required CraftnoteFile file,
    bool isManagerMode = false,
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

      if (isManagerMode) {
        // Merge into Master database
        final report = await DatabaseService.importAndMergePackage(tempPath);

        // Update Craftnote linkage on Master DB inspections matching this project or filename
        final masterInspections = await DatabaseService.getAllInspections();
        for (final insp in masterInspections) {
          final jobNum = (insp['jobNumber'] ?? insp['auftragsnummer'] ?? '').toString().trim();
          if (jobNum.isNotEmpty && (jobNum == project.orderNumber || file.name.contains(jobNum))) {
            final inspId = insp['inspectionId'] as int;
            await DatabaseService.updateInspectionCraftnoteStatus(
              inspId,
              projectId: project.id,
              fileId: file.id,
              syncStatus: 'synced',
              lastSyncTime: DateTime.now().toIso8601String(),
            );
          }
        }

        // Clean up temporary download file
        try {
          if (await downloadedFile.exists()) {
            await downloadedFile.delete();
          }
        } catch (_) {}

        return CraftnoteImportResult(
          success: true,
          message: 'Prüfergebnis erfolgreich aus Craftnote importiert (${report.newDoorsCount} Türen neu, ${report.updatedDoorsCount} aktualisiert).',
          report: report,
        );
      } else {
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
      }
    } catch (e) {
      return CraftnoteImportResult(
        success: false,
        message: 'Fehler beim Importieren aus Craftnote: $e',
        error: e,
      );
    }
  }

  /// Lists all SQLite (.db) job packages available in the given project,
  /// prioritizing the "Wartungslisten" folder.
  /// If [mustContainWord] is specified (e.g. 'ergebnis'), only files containing that word are returned.
  /// If [excludeWord] is specified (e.g. 'ergebnis'), files containing that word are excluded.
  Future<List<CraftnoteFile>> getProjectDbPackages(
    String projectId, {
    String? mustContainWord,
    String? excludeWord,
  }) async {
    try {
      final standardFolders = await resolveProjectStandardFolders(projectId);
      final files = await apiService.getProjectFiles(projectId);
      final wordFilter = mustContainWord?.trim().toLowerCase();
      final excludeFilter = excludeWord?.trim().toLowerCase();

      bool matchesFilter(CraftnoteFile f) {
        if (f.isFolder) return false;
        final isDb = f.isSqliteDatabase || f.name.toLowerCase().endsWith('.db');
        if (!isDb) return false;
        if (wordFilter != null && wordFilter.isNotEmpty) {
          if (!f.name.toLowerCase().contains(wordFilter)) return false;
        }
        if (excludeFilter != null && excludeFilter.isNotEmpty) {
          if (f.name.toLowerCase().contains(excludeFilter)) return false;
        }
        return true;
      }

      // 1. First look in Wartungslisten folder
      if (standardFolders.hasWartungslisten) {
        final inWartungslisten = files
            .where((f) =>
                f.folderId == standardFolders.wartungslistenFolderId &&
                matchesFilter(f))
            .toList();

        if (inWartungslisten.isNotEmpty) {
          inWartungslisten.sort((a, b) =>
              (b.creationTimestamp ?? 0).compareTo(a.creationTimestamp ?? 0));
          return inWartungslisten;
        }
      }

      // 2. Fallback: check all non-folder files in project
      final allDbFiles = files.where(matchesFilter).toList();

      allDbFiles.sort((a, b) =>
          (b.creationTimestamp ?? 0).compareTo(a.creationTimestamp ?? 0));
      return allDbFiles;
    } catch (_) {
      return [];
    }
  }

  /// Discovers the standard SQLite package for a project (looking in Wartungslisten folder first,
  /// then fallback to any .db in the project) and downloads/imports it into local or master DB.
  /// When [isManagerMode] is true, [mustContainWord] defaults to 'ergebnis' to ensure
  /// only inspector-generated result packages are imported.
  Future<CraftnoteImportResult> importProjectJobPackage({
    required CraftnoteProject project,
    CraftnoteFile? preferredFile,
    bool isManagerMode = false,
    String? mustContainWord,
    String? excludeWord,
  }) async {
    try {
      if (project.archived) {
        return CraftnoteImportResult(
          success: false,
          message:
              'Das Craftnote-Projekt "${project.name}" (#${project.orderNumber.isNotEmpty ? project.orderNumber : project.id}) ist bereits archiviert und kann nicht mehr importiert werden.',
        );
      }

      CraftnoteFile? targetPackage = preferredFile;

      if (targetPackage == null) {
        final filterWord = mustContainWord ?? (isManagerMode ? 'ergebnis' : null);
        final exclude = excludeWord ?? (isManagerMode ? null : 'ergebnis');
        var packages = await getProjectDbPackages(
          project.id,
          mustContainWord: filterWord,
          excludeWord: exclude,
        );

        CraftnoteProject effectiveProject = project;
        // In Test Mode: The inspector upload was redirected to the sandbox test project.
        // If no package was found in the target project, also check the sandbox test project!
        if (CraftnoteCredentialsService.isTestMode &&
            project.id != CraftnoteCredentialsService.testProjectId &&
            packages.isEmpty) {
          try {
            final testPackages = await getProjectDbPackages(
              CraftnoteCredentialsService.testProjectId,
              mustContainWord: filterWord,
              excludeWord: exclude,
            );
            final matching = testPackages.where((p) {
              final ord = project.orderNumber.trim().toLowerCase();
              return ord.isNotEmpty && p.name.toLowerCase().contains(ord);
            }).toList();
            if (matching.isNotEmpty) {
              packages = matching;
              effectiveProject = await apiService.getProjectById(CraftnoteCredentialsService.testProjectId);
            }
          } catch (_) {}
        }

        if (packages.isEmpty) {
          final typeDesc = isManagerMode ? 'Prüfergebnis-Paket (*ergebnis*.db)' : 'Wartungspaket (.db)';
          return CraftnoteImportResult(
            success: false,
            message:
                'In Projekt "${project.name}" (#${project.orderNumber.isNotEmpty ? project.orderNumber : project.id}) wurde kein $typeDesc gefunden.',
          );
        }
        targetPackage = packages.first;

        return await downloadAndImportPackage(
          project: effectiveProject,
          file: targetPackage,
          isManagerMode: isManagerMode,
        );
      }

      return await downloadAndImportPackage(
        project: project,
        file: targetPackage,
        isManagerMode: isManagerMode,
      );
    } catch (e) {
      return CraftnoteImportResult(
        success: false,
        message: 'Fehler beim Abrufen des Wartungspakets: $e',
        error: e,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // MOBILE / INSPECTOR RETURN & OFFLINE QUEUE FLOW
  // ─────────────────────────────────────────────────────────────

  /// Completes an inspection in the local database and uploads the result package (.db)
  /// back to Craftnote. If offline, the task is safely persisted in the SQLite offline queue.
  /// The target Craftnote project is automatically resolved by Auftragsnummer (orderNumber).
  /// Under Test Mode, searches run against real data for verification, but file uploads
  /// are securely redirected to the sandbox test project to safeguard production.
  Future<CraftnoteSyncResult> completeAndUploadFromLocalDb({
    required int inspectionId,
    String? pdfReportPath,
  }) async {
    try {
      final insp = await LocalDatabaseService.getInspectionById(inspectionId);
      if (insp == null) {
        return CraftnoteSyncResult(
          success: false,
          message: 'Auftrag mit ID $inspectionId wurde nicht in der lokalen Datenbank gefunden.',
        );
      }

      final jobNumber = (insp['jobNumber']?.toString().trim().isNotEmpty == true)
          ? insp['jobNumber'].toString().trim()
          : (insp['auftragsnummer']?.toString().trim() ?? '');

      if (jobNumber.isEmpty && (insp['craftnoteProjectId'] == null || insp['craftnoteProjectId'].toString().trim().isEmpty)) {
        return const CraftnoteSyncResult(
          success: false,
          message: 'Keine Auftragsnummer (orderNumber) für diesen Auftrag hinterlegt. Das zugehörige Craftnote-Projekt kann nicht ermittelt werden.',
        );
      }

      // Retrieve doors associated with this inspection
      final doors = await LocalDatabaseService.getDoorsByInspectionId(inspectionId);
      final doorIds = doors.map((d) => d.id!).whereType<int>().toList();
      if (doorIds.isEmpty) {
        return const CraftnoteSyncResult(
          success: false,
          message: 'Keine Türen in diesem Auftrag vorhanden. Export abgebrochen.',
        );
      }

      // Generate selective job package to documents directory
      final docDir = await getApplicationDocumentsDirectory();
      final fileName = FileExportHelper.buildPackageFileName(
        jobNumber: jobNumber.isNotEmpty ? jobNumber : insp['jobNumber']?.toString(),
        projectNumber: insp['projectNumber']?.toString(),
        objectAddress: insp['objectAddress']?.toString() ?? insp['clientName']?.toString(),
        packageType: 'inspektion_ergebnis',
      );
      final exportPackagePath = p.join(docDir.path, fileName);
      await LocalDatabaseService.exportSelectiveJobPackage(doorIds, exportPackagePath);

      final isOnline = await hasInternetConnection();

      // ─────────────────────────────────────────────────────────────
      // OFFLINE HANDLING: Enqueue in SQLite offline queue
      // ─────────────────────────────────────────────────────────────
      if (!isOnline) {
        final targetProj = (insp['craftnoteProjectId']?.toString().isNotEmpty == true)
            ? insp['craftnoteProjectId']!.toString()
            : (CraftnoteCredentialsService.isTestMode
                ? CraftnoteCredentialsService.testProjectId
                : jobNumber);

        final queueItem = CraftnoteUploadQueueItem(
          inspectionId: inspectionId,
          craftnoteProjectId: targetProj,
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
          message: 'Offline-Modus: Keine Internetverbindung verfügbar.\n'
              'Der Auftrag ($jobNumber) wurde sicher in die Offline-Warteschlange eingereiht und wird automatisch hochgeladen, sobald eine Verbindung besteht.',
        );
      }

      // ─────────────────────────────────────────────────────────────
      // ONLINE HANDLING: Find Project automatically via Auftragsnummer
      // ─────────────────────────────────────────────────────────────
      CraftnoteProject? matchedProject;
      bool projectFoundInSearch = false;

      if (jobNumber.isNotEmpty) {
        try {
          final searchResult = await apiService.findProjectWithArchiveCheck(orderNumber: jobNumber);
          if (searchResult.isArchived) {
            final projName = searchResult.archivedProject?.name ?? jobNumber;
            return CraftnoteSyncResult(
              success: false,
              message:
                  'Das Craftnote-Projekt "$projName" (#$jobNumber) ist bereits archiviert und kann nicht mehr aktualisiert oder hochgeladen werden.\nBitte aktivieren Sie das Projekt in Craftnote, falls es erneut bearbeitet werden soll.',
            );
          }
          if (searchResult.activeProject != null) {
            matchedProject = searchResult.activeProject;
            projectFoundInSearch = true;
          }
        } catch (e) {
          print('[CraftnoteSyncService] Warning finding project for $jobNumber: $e');
        }
      }

      // Fallback: If not found by jobNumber, check if craftnoteProjectId was already linked
      if (matchedProject == null && insp['craftnoteProjectId']?.toString().isNotEmpty == true) {
        try {
          matchedProject = await apiService.getProjectById(insp['craftnoteProjectId'].toString());
        } catch (_) {}
      }

      if (matchedProject != null && matchedProject.archived) {
        return CraftnoteSyncResult(
          success: false,
          message:
              'Das Craftnote-Projekt "${matchedProject.name}" (#$jobNumber) ist bereits archiviert und kann nicht mehr aktualisiert oder hochgeladen werden.\nBitte aktivieren Sie das Projekt in Craftnote, falls es erneut bearbeitet werden soll.',
        );
      }

      // Fallback for Test Mode: Fallback to sandbox test project
      if (matchedProject == null) {
        if (CraftnoteCredentialsService.isTestMode) {
          try {
            final testResults = await apiService.findProjects(orderNumber: CraftnoteCredentialsService.testProjectOrderNumber);
            if (testResults.isNotEmpty) {
              matchedProject = testResults.first;
            } else {
              matchedProject = await apiService.getProjectById(CraftnoteCredentialsService.testProjectId);
            }
          } catch (_) {
            matchedProject = const CraftnoteProject(
              id: CraftnoteCredentialsService.testProjectId,
              name: CraftnoteCredentialsService.testProjectName,
              orderNumber: CraftnoteCredentialsService.testProjectOrderNumber,
            );
          }
        } else {
          // In production mode, we cannot upload if project is not found
          return CraftnoteSyncResult(
            success: false,
            message: 'Kein passendes Projekt in Craftnote für Auftragsnummer "$jobNumber" gefunden. Bitte prüfen Sie die Auftragsnummer.',
          );
        }
      }

      // Safety Sandbox Guard: Redirect to testProjectId if test mode is active
      String targetProjectId = matchedProject.id;
      bool wasRedirected = false;
      if (CraftnoteCredentialsService.isTestMode && targetProjectId != CraftnoteCredentialsService.testProjectId) {
        print('[CraftnoteSyncService] 🛡️ TEST MODE GUARD (Inspector): Redirecting upload from "$targetProjectId" to sandbox test project "${CraftnoteCredentialsService.testProjectId}" (#${CraftnoteCredentialsService.testProjectOrderNumber}) to protect live production data.');
        targetProjectId = CraftnoteCredentialsService.testProjectId;
        wasRedirected = true;
      }

      // Resolve standard project target folders ("Wartungslisten" and "Fotomaterial")
      final standardFolders = await resolveProjectStandardFolders(targetProjectId);
      final effectiveWartungslistenId = standardFolders.wartungslistenFolderId;
      final effectiveFotomaterialId = standardFolders.fotomaterialFolderId;

      // Attempt online upload
      try {
        // 1. Upload SQLite package (.db) into "Wartungslisten"
        final dbUpload = await apiService.uploadFile(
          projectId: targetProjectId,
          file: File(exportPackagePath),
          fileName: p.basename(exportPackagePath),
          folderId: effectiveWartungslistenId,
        );

        // 2. Upload defect photos into "Fotomaterial" with deduplication
        final photoSync = await syncInspectionPhotos(
          inspectionId: inspectionId,
          craftnoteProjectId: targetProjectId,
          fotomaterialFolderId: effectiveFotomaterialId,
          isManagerMode: false,
        );

        // 3. Upload optional PDF report
        CraftnoteFile? pdfUpload;
        if (pdfReportPath != null && await File(pdfReportPath).exists()) {
          pdfUpload = await apiService.uploadFile(
            projectId: targetProjectId,
            file: File(pdfReportPath),
            fileName: p.basename(pdfReportPath),
            folderId: effectiveWartungslistenId,
          );
        }

        // 4. Optionally post chat message
        try {
          final inspector = insp['inspectorName'] ?? 'Techniker';
          final buffer = StringBuffer('✅ [WartungsTool] Wartungsergebnis hochgeladen von $inspector:\n');
          buffer.writeln('• Auftrag: #${matchedProject.orderNumber.isNotEmpty ? matchedProject.orderNumber : jobNumber}');
          buffer.writeln('• ${doorIds.length} Tür(en) geprüft');
          buffer.writeln('• Ergebnis-Paket: ${p.basename(exportPackagePath)} (${standardFolders.wartungslistenPath ?? "Wartungslisten"})');
          if (pdfUpload != null) buffer.writeln('• PDF-Prüfbericht angehängt');
          if (photoSync.totalFound > 0) {
            buffer.writeln('• Mängelfotos: ${photoSync.uploadedCount} neu übertragen, ${photoSync.skippedCount} übersprungen (${standardFolders.fotomaterialPath ?? "Fotomaterial"})');
          }

          await apiService.postMessage(
            targetProjectId,
            buffer.toString().trim(),
          );
        } catch (_) {}

        // 5. Update local database sync status
        await LocalDatabaseService.updateInspectionCraftnoteStatus(
          inspectionId,
          projectId: targetProjectId,
          fileId: dbUpload.id,
          syncStatus: 'synced',
          lastSyncTime: DateTime.now().toIso8601String(),
        );

        // 6. Build inspector feedback confirmation message
        final buffer = StringBuffer('Wartungsauftrag erfolgreich zu Craftnote exportiert!\n\n');
        buffer.writeln('• Projekt: ${matchedProject.name} (#${matchedProject.orderNumber.isNotEmpty ? matchedProject.orderNumber : jobNumber})');
        if (wasRedirected) {
          buffer.writeln('🛡️ [Testmodus aktiv]: Uploads wurden sicher in das Sandbox-Testprojekt (#${CraftnoteCredentialsService.testProjectOrderNumber}) übertragen, um Produktivdaten zu schützen.');
        } else if (!projectFoundInSearch && CraftnoteCredentialsService.isTestMode) {
          buffer.writeln('🛡️ [Testmodus aktiv]: Auftragsnummer nicht in Craftnote gefunden; Fallback auf Sandbox-Testprojekt (#${CraftnoteCredentialsService.testProjectOrderNumber}).');
        }
        buffer.writeln('• Paketdatei: ${p.basename(exportPackagePath)} in "${standardFolders.wartungslistenPath ?? "Wartungslisten"}"');
        if (photoSync.totalFound > 0) {
          buffer.writeln('• Fotos: ${photoSync.uploadedCount} neu hochgeladen, ${photoSync.skippedCount} bereits vorhanden (übersprungen) in "${standardFolders.fotomaterialPath ?? "Fotomaterial"}"');
        } else {
          buffer.writeln('• Fotos: Keine Mängelfotos in diesem Auftrag vorhanden.');
        }

        return CraftnoteSyncResult(
          success: true,
          isQueuedOffline: false,
          uploadedDbFileId: dbUpload.id,
          uploadedPdfFileId: pdfUpload?.id,
          totalPhotos: photoSync.totalFound,
          uploadedPhotos: photoSync.uploadedCount,
          skippedPhotos: photoSync.skippedCount,
          wartungslistenFolderId: effectiveWartungslistenId,
          fotomaterialFolderId: effectiveFotomaterialId,
          message: buffer.toString().trim(),
        );
      } catch (uploadError) {
        // Fallback to offline queue if upload fails unexpectedly
        final queueItem = CraftnoteUploadQueueItem(
          inspectionId: inspectionId,
          craftnoteProjectId: targetProjectId,
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
          message: 'Verbindungsabbruch während der Übertragung: $uploadError\n'
              'Der Auftrag ($jobNumber) wurde sicher in die Offline-Warteschlange eingereiht.',
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
        // Determine target project and enforce Test Mode guard
        String targetProjectId = item.craftnoteProjectId;
        if (CraftnoteCredentialsService.isTestMode && targetProjectId != CraftnoteCredentialsService.testProjectId) {
          targetProjectId = CraftnoteCredentialsService.testProjectId;
        }

        // Resolve standard folders ("Wartungslisten" and "Fotomaterial")
        final standardFolders = await resolveProjectStandardFolders(targetProjectId);

        // Upload .db package to Wartungslisten folder
        final dbUpload = await apiService.uploadFile(
          projectId: targetProjectId,
          file: pkgFile,
          fileName: p.basename(item.packageFilePath),
          folderId: standardFolders.wartungslistenFolderId,
        );

        // Upload PDF if present
        if (item.pdfFilePath != null && await File(item.pdfFilePath!).exists()) {
          await apiService.uploadFile(
            projectId: targetProjectId,
            file: File(item.pdfFilePath!),
            fileName: p.basename(item.pdfFilePath!),
            folderId: standardFolders.wartungslistenFolderId,
          );
        }

        // Upload defect photos to Fotomaterial if inspectionId is available
        if (item.inspectionId != null) {
          await syncInspectionPhotos(
            inspectionId: item.inspectionId!,
            craftnoteProjectId: targetProjectId,
            fotomaterialFolderId: standardFolders.fotomaterialFolderId,
            isManagerMode: false,
          );
        }

        try {
          await apiService.postMessage(
            targetProjectId,
            '🔄 [WartungsTool] Nachträgliche Synchronisierung aus Offline-Warteschlange erfolgreich abgeschlossen (${p.basename(item.packageFilePath)}).',
          );
        } catch (_) {}

        await LocalDatabaseService.deleteCraftnoteUploadQueueItem(item.id!);

        if (item.inspectionId != null) {
          await LocalDatabaseService.updateInspectionCraftnoteStatus(
            item.inspectionId!,
            fileId: dbUpload.id,
            projectId: targetProjectId,
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
