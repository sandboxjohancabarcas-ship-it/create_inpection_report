import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'photo_name_helper.dart';

/// Result object for captured property or door photo.
class PropertyPhotoResult {
  final String? savedPath;
  final Uint8List imageBytes;
  final String base64Data;
  final DateTime timestamp;

  PropertyPhotoResult({
    this.savedPath,
    required this.imageBytes,
    required this.base64Data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Helper utility for capturing and saving property and door photos.
class PropertyPhotoHelper {
  /// Captures an image via Camera or Gallery, prompts for save destination if [promptSaveLocation] is true,
  /// and returns a [PropertyPhotoResult] containing the raw bytes, base64 string, and optional save path.
  static Future<PropertyPhotoResult?> capturePropertyPhoto({
    required BuildContext context,
    required String doorAlias,
    required String propertyName,
    required int indexNumber,
    String? jobNumber,
    bool promptSaveLocation = true,
    ImagePicker? imagePicker,
  }) async {
    final bool isDoorPhoto = propertyName.toLowerCase() == 'tuer' || propertyName.toLowerCase() == 'tür';
    final String displayTitle = isDoorPhoto ? 'Türfoto' : 'Foto für $propertyName';

    // 1. Choose photo source: Kamera or Galerie / Datei
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext ctx) {
        return SimpleDialog(
          title: Text(displayTitle),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(ImageSource.camera),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Icon(Icons.camera_alt, color: Colors.blue),
                    SizedBox(width: 12),
                    Text('Kamera (Foto aufnehmen)'),
                  ],
                ),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(ImageSource.gallery),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Icon(Icons.photo_library, color: Colors.green),
                    SizedBox(width: 12),
                    Text('Galerie / Foto auswählen'),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );

    if (source == null) return null;

    // 2. Capture / pick the image
    Uint8List? imageBytes;
    try {
      final ImagePicker picker = imagePicker ?? ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        imageBytes = await image.readAsBytes();
      }
    } catch (e) {
      debugPrint('PropertyPhotoHelper: ImagePicker error: $e');
      if (source == ImageSource.gallery) {
        try {
          final result = await FilePicker.platform.pickFiles(type: FileType.image);
          if (result != null && result.files.single.path != null) {
            final file = File(result.files.single.path!);
            imageBytes = await file.readAsBytes();
          }
        } catch (fileErr) {
          debugPrint('PropertyPhotoHelper: FilePicker fallback error: $fileErr');
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Kamera konnte nicht geöffnet werden: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }
    }

    if (imageBytes == null || imageBytes.isEmpty) {
      return null;
    }

    final DateTime captureTime = DateTime.now();

    // 3. Generate standardized filename
    final String defaultFileName = isDoorPhoto
        ? PhotoNameHelper.formatGeneralDoorPhotoName(
            doorAlias: doorAlias,
            jobNumber: jobNumber ?? 'Auftrag',
            timestamp: captureTime,
            photoIndex: indexNumber > 1 ? indexNumber : null,
          )
        : PhotoNameHelper.formatPropertyPhotoName(
            doorAlias: doorAlias,
            propertyName: propertyName,
            indexNumber: indexNumber,
            extension: 'jpg',
          );

    String? savePath;
    if (promptSaveLocation) {
      // 4. Prompt user for save destination
      final String saveDialogTitle = isDoorPhoto ? 'Türfoto speichern unter...' : 'Foto speichern unter...';
      savePath = await FilePicker.platform.saveFile(
        dialogTitle: saveDialogTitle,
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        bytes: imageBytes,
      );

      // Ensure bytes are physically written to disk if location chosen
      if (savePath != null && savePath.isNotEmpty) {
        try {
          final targetFile = File(savePath);
          if (!await targetFile.exists() || (await targetFile.length()) == 0) {
            await targetFile.writeAsBytes(imageBytes, flush: true);
          }
        } catch (e) {
          debugPrint('PropertyPhotoHelper: Error writing saved photo: $e');
        }
      }
    }

    return PropertyPhotoResult(
      savedPath: savePath,
      imageBytes: imageBytes,
      base64Data: base64Encode(imageBytes),
      timestamp: captureTime,
    );
  }

  /// Prompts the user to capture or pick an image, then prompts for the save location on disk
  /// pre-filled with the standardized filename.
  ///
  /// Returns the saved file path if successful, or `null` if the user cancelled or an error occurred.
  static Future<String?> captureAndSavePropertyPhoto({
    required BuildContext context,
    required String doorAlias,
    required String propertyName,
    required int indexNumber,
    String? jobNumber,
    ImagePicker? imagePicker,
  }) async {
    final result = await capturePropertyPhoto(
      context: context,
      doorAlias: doorAlias,
      propertyName: propertyName,
      indexNumber: indexNumber,
      jobNumber: jobNumber,
      promptSaveLocation: true,
      imagePicker: imagePicker,
    );
    return result?.savedPath;
  }
}
