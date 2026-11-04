import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wartungstool/services/craftnote_api_service.dart';
import 'package:wartungstool/services/craftnote_credentials_service.dart';
import 'package:wartungstool/widgets/craftnote_folder_picker_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CraftnoteCredentialsService.resetToDefaults();
    CraftnoteCredentialsService.setMockMode(false);
  });

  group('CraftnoteFolderPickerDialog Widget Tests', () {
    testWidgets('Renders root and folders without ListTile background or ink splash assertion', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/files')) {
          return http.Response(
            jsonEncode({
              'files': [
                {
                  'id': 'f-root-1',
                  'name': '11 Medien',
                  'type': 'FOLDER',
                  'projectId': 'proj-1',
                  'folderId': null,
                },
                {
                  'id': 'f-sub-1',
                  'name': 'Wartungslisten',
                  'type': 'FOLDER',
                  'projectId': 'proj-1',
                  'folderId': 'f-root-1',
                },
                {
                  'id': 'file-pdf-1',
                  'name': 'Prüfbericht.pdf',
                  'type': 'FILE',
                  'projectId': 'proj-1',
                  'folderId': 'f-sub-1',
                },
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"error":"not found"}', 404);
      });

      final apiService = CraftnoteApiService(client: mockClient);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CraftnoteFolderPickerDialog(
              projectId: 'proj-1',
              projectName: 'Test Projekt Unit 2',
              apiService: apiService,
            ),
          ),
        ),
      );

      // Wait for async file loading
      await tester.pumpAndSettle();

      // Verify header
      expect(find.text('Craftnote-Zielordner wählen'), findsOneWidget);
      expect(find.text('Projekt: Test Projekt Unit 2'), findsOneWidget);

      // Verify Root entry
      expect(find.text('[Hauptverzeichnis / Root]'), findsOneWidget);

      // Verify Folders
      final medienTile = find.byWidgetPredicate(
        (w) => w is ListTile && w.title is Text && (w.title as Text).data == '11 Medien',
      );
      final wartungTile = find.byWidgetPredicate(
        (w) => w is ListTile && w.title is Text && (w.title as Text).data == 'Wartungslisten',
      );
      expect(medienTile, findsOneWidget);
      expect(wartungTile, findsOneWidget);
      expect(find.text('11 Medien / Wartungslisten'), findsOneWidget);

      // Verify regular files are not shown in folder picker
      expect(find.text('Prüfbericht.pdf'), findsNothing);

      // Tap on Wartungslisten
      await tester.tap(wartungTile);
      await tester.pumpAndSettle();

      // Tap on Root
      await tester.tap(find.text('[Hauptverzeichnis / Root]'));
      await tester.pumpAndSettle();
    });

    testWidgets('Search filter filters folder list correctly', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'files': [
              {
                'id': 'f1',
                'name': '11 Medien',
                'type': 'FOLDER',
                'projectId': 'p1',
              },
              {
                'id': 'f2',
                'name': 'Wartungslisten',
                'type': 'FOLDER',
                'projectId': 'p1',
              },
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = CraftnoteApiService(client: mockClient);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CraftnoteFolderPickerDialog(
              projectId: 'p1',
              projectName: 'Test Search',
              apiService: apiService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final medienTile = find.byWidgetPredicate(
        (w) => w is ListTile && w.title is Text && (w.title as Text).data == '11 Medien',
      );
      final wartungTile = find.byWidgetPredicate(
        (w) => w is ListTile && w.title is Text && (w.title as Text).data == 'Wartungslisten',
      );

      expect(medienTile, findsOneWidget);
      expect(wartungTile, findsOneWidget);

      // Filter by "Wartung"
      await tester.enterText(find.byType(TextField), 'Wartung');
      await tester.pumpAndSettle();

      expect(medienTile, findsNothing);
      expect(wartungTile, findsOneWidget);
    });
  });
}
