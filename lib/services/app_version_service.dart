class AppVersionService {
  /// Major.Minor.Patch
  static const String version = '1.0.0';

  /// Internal Build Number
  static const int buildNumber = 2;

  /// Combined version string (e.g. "1.0.0+2")
  static String get fullVersion => '$version+$buildNumber';

  /// Build Date (YYYY-MM-DD)
  static const String buildDate = '2026-11-26';

  /// Returns target platform name ('Windows' for Manager, 'Android' for Inspector/Techniker)
  static String getPlatformName({bool isManager = false}) {
    return isManager ? 'Windows' : 'Android';
  }

  /// Formatted short version text
  /// e.g. "Windows Build v1.0.0+2"
  static String getShortVersionInfo({bool isManager = false}) {
    final platform = getPlatformName(isManager: isManager);
    return '$platform Build v$fullVersion';
  }

  /// Formatted full version text with platform and build date
  /// e.g. "Windows Build v1.0.0+1 (Build-Datum: 2026-11-26)"
  static String getFullVersionInfo({bool isManager = false}) {
    final platform = getPlatformName(isManager: isManager);
    return '$platform Build v$fullVersion (Build-Datum: $buildDate)';
  }

  /// Compact version text for AppBars or Subtitles
  /// e.g. "Windows v1.0.0+1 (2026-11-26)"
  static String getCompactVersionInfo({bool isManager = false}) {
    final platform = getPlatformName(isManager: isManager);
    return '$platform v$fullVersion ($buildDate)';
  }
}
