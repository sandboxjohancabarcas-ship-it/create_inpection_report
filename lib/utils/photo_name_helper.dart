/// Helper utility for generating standardized inspection photo filenames.
/// 
/// Format: [door alias]_Fehler_[error code]_[number of picture].jpg
/// Examples:
/// - 000100-1-EG-21.2_Fehler_1.1.1_1.jpg
/// - 000331-2-2.UG-Geb.63-2_Fehler_3.2.1_2.jpg
/// - 000250-4-1.OG-Tuer12_Fehler_Hinweis-02_3.jpg
class PhotoNameHelper {
  /// Generates the standardized photo filename.
  /// [photoIndex] is 1-based (1, 2, 3...).
  static String formatPhotoName({
    required String doorAlias,
    required String errorCode,
    required int photoIndex,
    String extension = 'jpg',
  }) {
    final cleanAlias = sanitizeForFilename(doorAlias.trim().isNotEmpty ? doorAlias.trim() : 'Door');
    final cleanCode = sanitizeForFilename(errorCode.trim().isNotEmpty ? errorCode.trim() : 'Fehler');
    final cleanExt = extension.startsWith('.') ? extension.substring(1) : extension;
    final indexNum = photoIndex > 0 ? photoIndex : 1;
    return '${cleanAlias}_Fehler_${cleanCode}_$indexNum.$cleanExt';
  }

  /// Generates a list of standardized photo names for multiple photos attached to an error.
  static List<String> formatPhotoNames({
    required String doorAlias,
    required String errorCode,
    required int photoCount,
    String extension = 'jpg',
  }) {
    return List.generate(
      photoCount,
      (index) => formatPhotoName(
        doorAlias: doorAlias,
        errorCode: errorCode,
        photoIndex: index + 1,
        extension: extension,
      ),
    );
  }

  /// Sanitizes invalid filesystem characters (: * ? " < > | \ /) to prevent file write issues.
  static String sanitizeForFilename(String input) {
    return input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
  }
}
