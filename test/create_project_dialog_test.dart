import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/widgets/create_project_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await DatabaseService.clearDatabase();
  });

  tearDown(() async {
    await DatabaseService.closeDb();
  });

  group('CreateProjectDialog Widget Tests', () {
    testWidgets('Renders all required project and building fields', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CreateProjectDialog.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Neues Projekt / Gebäude anlegen'), findsOneWidget);
      expect(find.text('Projektnummer (Gebäude-Anker) *'), findsOneWidget);
      expect(find.text('Objektadresse / Liegenschaft *'), findsOneWidget);
      expect(find.text('Kunde / Auftraggeber *'), findsOneWidget);
      expect(find.text('Auftragsnummer *'), findsOneWidget);
      expect(find.text('Direkt als Techniker-Paket (.db) exportieren'), findsOneWidget);
    });

    testWidgets('Validates required fields when submitted empty', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CreateProjectDialog.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final submitButton = find.byType(ElevatedButton).last;
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.text('Bitte Projektnummer eingeben'), findsOneWidget);
      expect(find.text('Bitte Objektadresse eingeben'), findsOneWidget);
      expect(find.text('Bitte Kunden eingeben'), findsOneWidget);
      expect(find.text('Bitte Auftragsnummer eingeben'), findsOneWidget);
    });

    testWidgets('Toggles export package checkbox and cancels cleanly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await CreateProjectDialog.show(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Toggle export checkbox
      final checkbox = find.byType(CheckboxListTile);
      expect(checkbox, findsOneWidget);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      // Tap Cancel button
      final cancelButton = find.text('Abbrechen');
      expect(cancelButton, findsOneWidget);
      await tester.tap(cancelButton);
      await tester.pumpAndSettle();

      // Dialog is dismissed and returned false
      expect(find.text('Neues Projekt / Gebäude anlegen'), findsNothing);
      expect(result, isFalse);
    });
  });
}
