import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/craftnote_credentials_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/widgets/craftnote_job_picker_modal.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getTemporaryPath() async {
    return Directory.systemTemp.path;
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
    CraftnoteCredentialsService.resetToDefaults();
    CraftnoteCredentialsService.setMockMode(true);
    CraftnoteCredentialsService.setTestMode(true);

    final localDb = await LocalDatabaseService.getDb();
    await localDb.delete('doors');
    await localDb.delete('inspections');
    await localDb.delete('inspection_doors');
  });

  tearDown(() async {
    await LocalDatabaseService.closeDb();
  });

  Future<void> pumpUntilSettled(WidgetTester tester, {int maxRounds = 25}) async {
    for (int i = 0; i < maxRounds; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    }
    await tester.pumpAndSettle();
  }

  group('CraftnoteJobPickerModal Widget Tests', () {
    test('CraftnoteCredentialsService defaults target folder to Wartungslisten', () {
      expect(CraftnoteCredentialsService.defaultFolder, 'Wartungslisten');
    });
    testWidgets('Renders targeted search without browsing all projects and pre-fills test order number in test mode', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CraftnoteJobPickerModal.show(context),
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Verify title & targeted subtitle
      expect(find.text('Auftrag aus Craftnote laden'), findsOneWidget);
      expect(find.text('Gezielter Import über die Auftragsnummer'), findsOneWidget);

      // Verify NO previous 2-column project list exists
      expect(find.text('Dateien in:'), findsNothing);
      expect(find.text('Keine Projekte gefunden.'), findsNothing);

      // Verify test mode banner and prefilled text
      expect(find.textContaining('Testumgebung aktiv: Zugriff auf Sandbox-Projekt'), findsOneWidget);
      expect(find.widgetWithText(TextField, '26-00251-AN'), findsOneWidget);
      expect(find.text('Suchen & Laden'), findsOneWidget);

      // Verify settings button is HIDDEN in inspector role
      expect(find.byTooltip('Craftnote-Einstellungen'), findsNothing);
    });

    testWidgets('Validates empty input and shows message', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CraftnoteJobPickerModal.show(context),
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Clear input and tap search
      final clearBtn = find.byIcon(Icons.clear);
      if (clearBtn.evaluate().isNotEmpty) {
        await tester.tap(clearBtn);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Suchen & Laden'));
      await tester.pumpAndSettle();

      expect(find.text('Bitte geben Sie eine Auftragsnummer oder einen Projektnamen ein.'), findsOneWidget);
    });

    testWidgets('Shows error if project is not found for unknown order number', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CraftnoteJobPickerModal.show(context),
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      await tester.enterText(textField, '99-NONEXISTENT-XX');
      await tester.tap(find.text('Suchen & Laden'));
      await pumpUntilSettled(tester);

      expect(find.textContaining('Kein Craftnote-Projekt mit Auftragsnummer "99-NONEXISTENT-XX" gefunden'), findsOneWidget);
    });

    testWidgets('Finds project by order number and auto-executes package import', (WidgetTester tester) async {
      // In mock mode, orderNumber '26-15440-AB' maps to CN-PROJ-MOCK-01 which contains a mock .db file
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CraftnoteJobPickerModal.show(context),
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      await tester.enterText(textField, '26-15440-AB');
      await tester.tap(find.text('Suchen & Laden'));

      // Pump frames for search & async mock import
      await pumpUntilSettled(tester, maxRounds: 30);

      // Modal auto-closes on successful import
      expect(find.byType(CraftnoteJobPickerModal), findsNothing);
    });

    testWidgets('Renders manager mode with dedicated title and ergebnis package description', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CraftnoteJobPickerModal.show(context, isManagerMode: true),
                child: const Text('Open Manager Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Manager Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Prüfergebnis aus Craftnote importieren'), findsOneWidget);
      expect(find.textContaining('*ergebnis*.db'), findsOneWidget);

      // Verify settings button is VISIBLE in manager role
      expect(find.byTooltip('Craftnote-Einstellungen'), findsOneWidget);
    });

    testWidgets('Manager mode filters for ergebnis package and auto-executes import into Master DB', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CraftnoteJobPickerModal.show(context, isManagerMode: true),
                child: const Text('Open Manager Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Manager Modal'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      await tester.enterText(textField, '26-15440-AB');
      await tester.tap(find.text('Suchen & Laden'));

      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      }
      await tester.pumpAndSettle();

      // Successfully imported ergebnis package into Master DB and closed modal
      expect(find.byType(CraftnoteJobPickerModal), findsNothing);
    });

    testWidgets('Manager mode checks sandbox test project for Auftragsnummer package when test mode is active', (WidgetTester tester) async {
      CraftnoteCredentialsService.setTestMode(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CraftnoteJobPickerModal.show(context, isManagerMode: true),
                child: const Text('Open Manager Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Manager Modal'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      await tester.enterText(textField, '26-15440-AB');
      await tester.tap(find.text('Suchen & Laden'));

      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      }
      await tester.pumpAndSettle();

      expect(find.byType(CraftnoteJobPickerModal), findsNothing);
    });

    testWidgets('Inspector mode detects archived project and displays warning that it cannot be processed', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CraftnoteJobPickerModal.show(context, isManagerMode: false),
                child: const Text('Open Inspector Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Inspector Modal'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      await tester.enterText(textField, '26-14078-AB');
      await tester.tap(find.text('Suchen & Laden'));

      await pumpUntilSettled(tester);

      expect(find.textContaining('bereits archiviert und kann nicht mehr bearbeitet oder importiert werden'), findsOneWidget);
      expect(find.text('ARCHIVIERT'), findsOneWidget);
      // Ensure it did not auto-close or import
      expect(find.byType(CraftnoteJobPickerModal), findsOneWidget);
    });

    testWidgets('Manager mode detects archived project and displays warning that it cannot be processed', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CraftnoteJobPickerModal.show(context, isManagerMode: true),
                child: const Text('Open Manager Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Manager Modal'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      await tester.enterText(textField, '26-14078-AB');
      await tester.tap(find.text('Suchen & Laden'));

      await pumpUntilSettled(tester);

      expect(find.textContaining('bereits archiviert und kann nicht mehr bearbeitet oder importiert werden'), findsOneWidget);
      expect(find.text('ARCHIVIERT'), findsOneWidget);
      expect(find.byType(CraftnoteJobPickerModal), findsOneWidget);
    });
  });
}
