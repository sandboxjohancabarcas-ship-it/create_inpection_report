import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/pages/error_management_page.dart';
import 'package:wartungstool/services/local_database_service.dart';

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
    await LocalDatabaseService.closeDb();

    final dbPath = await getDatabasesPath();
    final localPath = p.join(dbPath, 'working.db');

    try {
      if (await File(localPath).exists()) await File(localPath).delete();
    } catch (_) {}

    final db = await LocalDatabaseService.getDb();
    await db.delete('inspection_door_errors');
    await db.delete('error_catalog');
    await db.delete('inspection_doors');
    await db.delete('doors');
    await db.delete('inspections');

    // Insert sample catalog errors across multiple categories
    await LocalDatabaseService.insertErrorCatalogItems([
      ErrorCatalog(
        code: '1.1.1',
        description: 'Türschließer verliert Öl',
        category: 'Türschließer',
        severity: 'high',
        status: 'Approved',
      ),
      ErrorCatalog(
        code: '1.1.2',
        description: 'Schließkraft unzureichend',
        category: 'Türschließer',
        severity: 'medium',
        status: 'Approved',
      ),
      ErrorCatalog(
        code: '2.1.1',
        description: 'Schlossfalle defekt',
        category: 'Schloss',
        severity: 'critical',
        status: 'Approved',
      ),
      ErrorCatalog(
        code: '3.1.1',
        description: 'Feststellanlage schließt nicht bei Auslösung',
        category: 'Feststellanlage',
        severity: 'critical',
        status: 'Approved',
      ),
    ]);

    await db.insert('doors', {
      'id': 1,
      'doorNumber': 'T-001',
      'doorType': 'T30-1',
    });

    await db.insert('inspections', {
      'inspectionId': 1,
      'clientName': 'Test Client',
      'jobNumber': 'JOB-100',
    });

    await db.insert('inspection_doors', {
      'id': 1,
      'inspectionId': 1,
      'doorId': 1,
      'status': 'Open',
    });
  });

  tearDown(() async {
    await LocalDatabaseService.closeDb();
  });

  testWidgets('Error management dialog allows category filtering, search, notes pop-up and error addition', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ErrorManagementPage(
            doorId: 1,
            doorNumber: 'T-001',
            inspectionId: 1,
          ),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Tap on FAB to open dialog
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    await tester.tap(fab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify dialog is open and shows category selection & search bar
    expect(find.text('Fehler hinzufügen'), findsWidgets);
    expect(find.text('1. Fehlerkategorie wählen:'), findsOneWidget);
    expect(find.text('2. Suche (nach Kategorie, Code oder Beschreibung):'), findsOneWidget);

    // Verify error list count
    expect(find.text('4 Fehler gefunden'), findsOneWidget);
    expect(find.text('1.1.1'), findsOneWidget);
    expect(find.text('2.1.1'), findsOneWidget);

    // Select category "Schloss"
    final categoryDropdown = find.byType(DropdownButtonFormField<String?>);
    expect(categoryDropdown, findsOneWidget);
    await tester.tap(categoryDropdown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Tap on "Schloss (1 Fehler)" in dropdown
    final schlossItem = find.text('Schloss (1 Fehler)').last;
    await tester.tap(schlossItem);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Now only Schloss error should be found
    expect(find.text('1 Fehler gefunden'), findsOneWidget);
    expect(find.text(' in "Schloss"'), findsOneWidget);
    expect(find.text('2.1.1'), findsOneWidget);
    expect(find.text('1.1.1'), findsNothing);

    // Test Search input
    final searchField = find.widgetWithText(TextField, 'Suchbegriff eingeben...');
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'defekt');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('2.1.1'), findsOneWidget);

    // Select error 2.1.1
    final selectButton = find.widgetWithText(ElevatedButton, 'Auswählen');
    expect(selectButton, findsOneWidget);
    await tester.tap(selectButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Selected error card should be displayed with Notes pop-up button and Photo buttons
    expect(find.text('Ausgewählter Fehler:'), findsOneWidget);
    expect(find.text('In separatem Fenster bearbeiten'), findsOneWidget);
    expect(find.text('Kamera'), findsOneWidget);
    expect(find.text('Galerie'), findsOneWidget);

    // Open Notes Pop-up
    await tester.tap(find.text('In separatem Fenster bearbeiten'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Notizen zum Fehler'), findsOneWidget);
    expect(find.text('Geben Sie hier detaillierte Beobachtungen und Notizen zum Fehler ein:'), findsOneWidget);

    // Enter notes in pop-up
    final popUpTextField = find.widgetWithText(TextField, 'Detaillierte Fehlerbeschreibung, Fundort, Ursache, Bemerkungen...');
    expect(popUpTextField, findsOneWidget);
    await tester.enterText(popUpTextField, 'Schlossfalle klemmt beim Zuziehen');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Tap Übernehmen
    await tester.tap(find.widgetWithText(ElevatedButton, 'Übernehmen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Save the error
    await tester.runAsync(() async {
      final submitButton = find.widgetWithText(ElevatedButton, 'Fehler hinzufügen').last;
      await tester.tap(submitButton);
      await Future.delayed(const Duration(milliseconds: 800));
    });
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Verify error is added to list on error management page
    expect(find.text('2.1.1'), findsOneWidget);
    expect(find.text('Schlossfalle defekt'), findsOneWidget);
    expect(find.text('Notizen: Schlossfalle klemmt beim Zuziehen'), findsOneWidget);
  });
}
