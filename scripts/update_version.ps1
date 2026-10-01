<#
.SYNOPSIS
    Automatically synchronizes and stamps the App Version, Build Number, and Build Date.
.DESCRIPTION
    - Updates pubspec.yaml with the latest version/build number.
    - Stretches and updates lib/services/app_version_service.dart with current buildDate (YYYY-MM-DD).
    - Updates test/app_version_test.dart to ensure test assertions stay in sync.
.PARAMETER IncrementBuild
    If set, increments the build number suffix (+1, +2, etc.).
.PARAMETER NewVersion
    Optional new semantic version (e.g. '1.0.1'). If omitted, keeps current version from pubspec.yaml.
#>
param (
    [switch]$IncrementBuild,
    [string]$NewVersion = "",
    [string]$CustomDate = ""
)

$rootDir = Split-Path -Parent $PSScriptRoot
if (!(Test-Path "$rootDir/pubspec.yaml")) {
    $rootDir = $PSScriptRoot
}

$pubspecPath = "$rootDir/pubspec.yaml"
$appVersionServicePath = "$rootDir/lib/services/app_version_service.dart"
$appVersionTestPath = "$rootDir/test/app_version_test.dart"

# 1. Read current version from pubspec.yaml
$pubspecContent = Get-Content $pubspecPath -Raw
if ($pubspecContent -match 'version:\s*([0-9\.]+)(?:\+([0-9]+))?') {
    $currentVer = $Matches[1]
    $currentBuild = if ($Matches[2]) { [int]$Matches[2] } else { 1 }
} else {
    $currentVer = "1.0.0"
    $currentBuild = 1
}

$targetVer = if (![string]::IsNullOrWhiteSpace($NewVersion)) { $NewVersion.Trim() } else { $currentVer }
$targetBuild = if ($IncrementBuild) { $currentBuild + 1 } else { $currentBuild }
$targetDate = if (![string]::IsNullOrWhiteSpace($CustomDate)) { $CustomDate.Trim() } else { (Get-Date).ToString("yyyy-MM-dd") }

Write-Host "Updating Application Version & Build Date..." -ForegroundColor Cyan
Write-Host "  Version:      $targetVer" -ForegroundColor Gray
Write-Host "  Build Number: $targetBuild" -ForegroundColor Gray
Write-Host "  Build Date:   $targetDate" -ForegroundColor Gray

# 2. Update pubspec.yaml
$newPubspecContent = $pubspecContent -replace 'version:\s*[0-9\.]+(?:\+[0-9]+)?', "version: $targetVer+$targetBuild"
Set-Content -Path $pubspecPath -Value $newPubspecContent -NoNewline

# 3. Update lib/services/app_version_service.dart
$serviceCode = @"
import 'dart:io';

class AppVersionService {
  /// Primary version name from pubspec.yaml
  static const String version = '$targetVer';

  /// Build number suffix
  static const String buildNumber = '$targetBuild';

  /// Full version string (e.g., "1.0.0+1")
  static String get fullVersion => '`$version+`$buildNumber';

  /// Build Date (YYYY-MM-DD)
  static const String buildDate = '$targetDate';

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
  /// e.g. "Windows Build v1.0.0+1 (Build-Datum: $targetDate)"
  static String getFullVersionInfo({bool isManager = false}) {
    final platform = getPlatformName(isManager: isManager);
    return '`$platform Build v`$fullVersion (Build-Datum: `$buildDate)';
  }

  /// Compact version text for AppBars or Subtitles
  /// e.g. "Windows v1.0.0+1 ($targetDate)"
  static String getCompactVersionInfo({bool isManager = false}) {
    final platform = getPlatformName(isManager: isManager);
    return '`$platform v`$fullVersion (`$buildDate)';
  }
}
"@
Set-Content -Path $appVersionServicePath -Value $serviceCode

# 4. Update test/app_version_test.dart
if (Test-Path $appVersionTestPath) {
    $testCode = @"
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/services/app_version_service.dart';

void main() {
  group('AppVersionService Tests', () {
    test('fullVersion matches $targetVer+$targetBuild', () {
      expect(AppVersionService.version, equals('$targetVer'));
      expect(AppVersionService.buildNumber, equals('$targetBuild'));
      expect(AppVersionService.fullVersion, equals('$targetVer+$targetBuild'));
    });

    test('buildDate is set to $targetDate', () {
      expect(AppVersionService.buildDate, equals('$targetDate'));
    });

    test('Manager mode returns Windows build information', () {
      final info = AppVersionService.getFullVersionInfo(isManager: true);
      expect(info, contains('Windows'));
      expect(info, contains('v$targetVer+$targetBuild'));
      expect(info, contains('$targetDate'));
    });

    test('Techniker/Inspector mode returns Android build information', () {
      final info = AppVersionService.getFullVersionInfo(isManager: false);
      expect(info, contains('v$targetVer+$targetBuild'));
      expect(info, contains('$targetDate'));
    });

    test('getCompactVersionInfo returns compact version string', () {
      final compactManager = AppVersionService.getCompactVersionInfo(isManager: true);
      expect(compactManager, contains('Windows'));
      expect(compactManager, contains('v$targetVer+$targetBuild'));
      expect(compactManager, contains('$targetDate'));
    });
  });
}
"@
    Set-Content -Path $appVersionTestPath -Value $testCode
}

Write-Host "Version stamping completed successfully: v$targetVer+$targetBuild ($targetDate)" -ForegroundColor Green
