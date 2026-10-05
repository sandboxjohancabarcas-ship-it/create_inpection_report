import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/utils/photo_name_helper.dart';

class PhotoExportResult {
  final int totalPhotos;
  final String outputDirectory;
  final List<String> exportedFileNames;

  const PhotoExportResult({
    required this.totalPhotos,
    required this.outputDirectory,
    required this.exportedFileNames,
  });
}

class PhotoExportService {
  /// Default export directory for photos.
  static Future<String> getDefaultExportDirectory({String? subFolder}) async {
    Directory? baseDir;
    try {
      baseDir = await getDownloadsDirectory();
    } catch (_) {}
    baseDir ??= await getApplicationDocumentsDirectory();

    String targetPath = p.join(baseDir.path, 'WartungsTool_Exports');
    if (subFolder != null && subFolder.isNotEmpty) {
      final safeFolder = PhotoNameHelper.sanitizeForFilename(subFolder);
      targetPath = p.join(targetPath, safeFolder);
    }

    final dir = Directory(targetPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }

  /// Exports all photos associated with a specific inspection ID.
  /// 
  /// Photos are named using the standardized format:
  /// [door alias]_Fehler_[error code]_[index].jpg
  /// 
  /// If [destinationDir] is provided, photos are saved there; otherwise a folder in the
  /// default export directory is created (e.g. `Fotos_[jobNumber]_[timestamp]`).
  static Future<PhotoExportResult> exportInspectionPhotos({
    required int inspectionId,
    String? destinationDir,
    bool isManagerMode = true,
  }) async {
    // 1. Fetch inspection metadata
    final inspection = isManagerMode
        ? await DatabaseService.getInspectionById(inspectionId)
        : await LocalDatabaseService.getInspectionById(inspectionId);

    final jobStr = inspection?['jobNumber']?.toString().trim().isNotEmpty == true
        ? inspection!['jobNumber'].toString().trim()
        : 'Auftrag_$inspectionId';
    final safeJob = PhotoNameHelper.sanitizeForFilename(jobStr);

    // 2. Fetch doors for the inspection
    final List<Door> doors = isManagerMode
        ? await DatabaseService.getDoorsByInspectionIds([inspectionId])
        : await LocalDatabaseService.getDoorsByInspectionId(inspectionId);
    final Map<int, Door> doorMap = {
      for (final d in doors)
        if (d.id != null) d.id!: d,
    };

    // 3. Fetch door junctions and errors
    final junctions = isManagerMode
        ? await DatabaseService.getInspectionDoorsByInspectionId(inspectionId)
        : [
            for (final d in doors)
              if (d.id != null)
                await LocalDatabaseService.getInspectionDoor(inspectionId, d.id!)
          ].whereType<Map<String, dynamic>>().toList();

    final List<int> junctionIds = junctions
        .map((j) => j['id'] as int?)
        .whereType<int>()
        .toList();

    final List<Map<String, dynamic>> errorRows = isManagerMode
        ? await DatabaseService.getErrorsForInspectionDoorIds(junctionIds)
        : await LocalDatabaseService.getErrorsForInspectionDoorIds(junctionIds);

    // 4. Map junctionId -> Door
    final Map<int, Door> junctionToDoorMap = {};
    for (final j in junctions) {
      final jId = j['id'] as int?;
      final doorId = j['doorId'] as int?;
      if (jId != null && doorId != null && doorMap.containsKey(doorId)) {
        junctionToDoorMap[jId] = doorMap[doorId]!;
      }
    }

    // 5. Prepare target directory
    final String targetDir;
    if (destinationDir != null && destinationDir.trim().isNotEmpty) {
      targetDir = destinationDir.trim();
      final dir = Directory(targetDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
    } else {
      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeStr = '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final timestamp = '${dateStr}_$timeStr';
      targetDir = await getDefaultExportDirectory(subFolder: 'Fotos_${safeJob}_$timestamp');
    }

    // 6. Extract photos and write to disk
    final List<String> exportedFiles = [];
    int photoCounter = 0;

    for (final errRow in errorRows) {
      final rawAttachments = (errRow['attachments'] ?? '').toString();
      if (rawAttachments.trim().isEmpty) continue;

      final junctionId = errRow['inspectionDoorId'] as int?;
      final door = junctionId != null ? junctionToDoorMap[junctionId] : null;

      final resolvedAlias = door?.doorAlias?.trim().isNotEmpty == true
          ? door!.doorAlias!.trim()
          : (door?.provisionalAlias?.trim().isNotEmpty == true
              ? door!.provisionalAlias!.trim()
              : (door?.doorNumber.trim().isNotEmpty == true ? door!.doorNumber.trim() : 'Tuer'));

      final String rawErrorCode = (errRow['errorCode'] ?? '').toString().trim();
      final errorCode = rawErrorCode.isNotEmpty
          ? rawErrorCode
          : (errRow['code'] ?? 'Fehler').toString();

      final photos = rawAttachments.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

      for (int i = 0; i < photos.length; i++) {
        final photoBase64 = photos[i];
        final fileName = PhotoNameHelper.formatPhotoName(
          doorAlias: resolvedAlias,
          errorCode: errorCode,
          photoIndex: i + 1,
          extension: 'jpg',
        );

        try {
          final bytes = base64Decode(photoBase64);
          final filePath = p.join(targetDir, fileName);
          final file = File(filePath);
          await file.writeAsBytes(bytes);
          exportedFiles.add(fileName);
          photoCounter++;
        } catch (e) {
          print('[PhotoExportService] Error saving photo "$fileName": $e');
        }
      }
    }

    return PhotoExportResult(
      totalPhotos: photoCounter,
      outputDirectory: targetDir,
      exportedFileNames: exportedFiles,
    );
  }
}
