import 'dart:io';

class AppVersionService {
  /// Primary version name from pubspec.yaml
  static const String version = '1.0.0';

  /// Build number suffix
  static const String buildNumber = '1';

  /// Full version string (e.g., "1.0.0+1")
  static String get fullVersion => '$version+$buildNumber';

  /// Build Date (YYYY-MM-DD)
  static const String buildDate = '2026-09-21';

  /// Returns target platform name ('Windows' for Manager, 'Android' for Inspector/Techniker)
  static String getPlatformName({bool isManager = false}) {
    if (Platform.isWindows) {
      return 'Windows';
    } else if (Platform.isAndroid) {
      return 'Android';
    } else if (isManager) {
      return 'Windows';
    } else {
      return Platform.operatingSystem.toUpperCase();
    }
  }

  /// Formatted full version text with platform and build date
  /// e.g. "Windows Build v1.0.0+1 (Build-Datum: 2026-09-21)"
  static String getFullVersionInfo({bool isManager = false}) {
    final platform = getPlatformName(isManager: isManager);
    return '$platform Build v$fullVersion (Build-Datum: $buildDate)';
  }

  /// Compact version text for AppBars or Subtitles
  /// e.g. "Windows v1.0.0+1 (2026-09-21)"
  static String getCompactVersionInfo({bool isManager = false}) {
    final platform = getPlatformName(isManager: isManager);
    return '$platform v$fullVersion ($buildDate)';
  }
}
