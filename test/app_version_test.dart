import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/services/app_version_service.dart';

void main() {
  group('AppVersionService Tests', () {
    test('fullVersion matches 1.0.0+1', () {
      expect(AppVersionService.version, equals('1.0.0'));
      expect(AppVersionService.buildNumber, equals('1'));
      expect(AppVersionService.fullVersion, equals('1.0.0+1'));
    });

    test('buildDate is set to 2026-09-21', () {
      expect(AppVersionService.buildDate, equals('2026-09-21'));
    });

    test('Manager mode returns Windows build information', () {
      final info = AppVersionService.getFullVersionInfo(isManager: true);
      expect(info, contains('Windows'));
      expect(info, contains('v1.0.0+1'));
      expect(info, contains('2026-09-21'));
    });

    test('Techniker/Inspector mode returns Android build information', () {
      final info = AppVersionService.getFullVersionInfo(isManager: false);
      expect(info, contains('v1.0.0+1'));
      expect(info, contains('2026-09-21'));
    });

    test('getCompactVersionInfo returns compact version string', () {
      final compactManager = AppVersionService.getCompactVersionInfo(isManager: true);
      expect(compactManager, contains('Windows'));
      expect(compactManager, contains('v1.0.0+1'));
      expect(compactManager, contains('2026-09-21'));
    });
  });
}
