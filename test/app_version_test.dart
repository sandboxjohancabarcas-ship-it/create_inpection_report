import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/services/app_version_service.dart';
import 'package:wartungstool/widgets/app_version_dialog.dart';
import 'package:wartungstool/widgets/craftnote_test_mode_switch.dart';

void main() {
  group('AppVersionService Tests', () {
    test('fullVersion matches 1.0.0+2', () {
      expect(AppVersionService.version, equals('1.0.0'));
      expect(AppVersionService.buildNumber, equals('2'));
      expect(AppVersionService.fullVersion, equals('1.0.0+2'));
    });

    test('buildDate is set to 2026-11-13', () {
      expect(AppVersionService.buildDate, equals('2026-11-13'));
    });

    test('Manager mode returns Windows build information', () {
      final info = AppVersionService.getFullVersionInfo(isManager: true);
      expect(info, contains('Windows'));
      expect(info, contains('v1.0.0+2'));
      expect(info, contains('2026-11-13'));
    });

    test('Techniker/Inspector mode returns Android build information', () {
      final info = AppVersionService.getFullVersionInfo(isManager: false);
      expect(info, contains('v1.0.0+2'));
      expect(info, contains('2026-11-13'));
    });

    test('getCompactVersionInfo returns compact version string', () {
      final compactManager = AppVersionService.getCompactVersionInfo(isManager: true);
      expect(compactManager, contains('Windows'));
      expect(compactManager, contains('v1.0.0+2'));
      expect(compactManager, contains('2026-11-13'));
    });

    testWidgets('AppVersionDialog renders CraftnoteTestModeSwitch', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppVersionDialog(isManager: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CraftnoteTestModeSwitch), findsOneWidget);
      expect(find.text('Craftnote-Umgebung'), findsOneWidget);
    });
  });
}
