import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/craftnote_credentials_service.dart';
import 'package:wartungstool/widgets/export_center_dialog.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.current.path;
  }
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.current.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseService.clearDatabase();
    await DatabaseService.getDb();
    CraftnoteCredentialsService.setTestMode(true);
  });

  tearDown(() async {
    await DatabaseService.closeDb();
  });

  group('ExportCenterDialog Overflow and Layout Tests', () {
    testWidgets('Renders cleanly on 900px height without RenderFlex overflow (Craftnote mode)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterErrorDetails? caughtError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        caughtError = details;
        originalOnError?.call(details);
      };
      addTearDown(() {
        FlutterError.onError = originalOnError;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ExportCenterDialog.show(
                  context,
                  isManagerMode: true,
                ),
                child: const Text('Open Export Center'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Export Center'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
        if (!tester.any(find.byType(CircularProgressIndicator))) break;
      }
      await tester.pump();

      // Find and select Craftnote format chip
      final craftnoteChip = find.text('Craftnote Cloud');
      expect(craftnoteChip, findsOneWidget);
      await tester.tap(craftnoteChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify that no Flutter overflow error was thrown
      expect(caughtError, isNull, reason: 'RenderFlex overflow occurred!');

      // Check key sections are rendered
      expect(find.text('Daten Export & Berichte'), findsOneWidget);
      expect(find.text('Automatisches Datei-Routing:'), findsOneWidget);
      expect(find.text('Jetzt Exportieren'), findsOneWidget);
    });

    testWidgets('Renders cleanly on small 800x600 screen and scrolls without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterErrorDetails? caughtError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        caughtError = details;
        originalOnError?.call(details);
      };
      addTearDown(() {
        FlutterError.onError = originalOnError;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ExportCenterDialog.show(
                  context,
                  isManagerMode: true,
                ),
                child: const Text('Open Export Center'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Export Center'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
        if (!tester.any(find.byType(CircularProgressIndicator))) break;
      }
      await tester.pump();

      // Scroll to Craftnote Cloud chip and tap
      await tester.ensureVisible(find.text('Craftnote Cloud'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Craftnote Cloud'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(caughtError, isNull, reason: 'RenderFlex overflow occurred on 600px screen!');

      // Drag/scroll up inside SingleChildScrollView
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 100));

      expect(caughtError, isNull);
      expect(find.text('Jetzt Exportieren'), findsOneWidget);
    });
  });
}
