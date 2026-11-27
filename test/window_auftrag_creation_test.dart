import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/widgets/create_project_dialog.dart';

Window _createTestWindow({
  required String windowNumber,
  required String floor,
  required String roomNumber,
  String notes = '',
}) {
  return Window(
    id: null,
    windowNumber: windowNumber,
    floor: floor,
    roomNumber: roomNumber,
    roomDesignation: 'Büro',
    windowType: 'DK',
    material: 'Aluminium',
    windowFunctionOK: true,
    notes: notes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await DatabaseService.clearDatabase();
    await LocalDatabaseService.clearSyncedData();
  });

  tearDown(() async {
    await DatabaseService.closeDb();
    await LocalDatabaseService.closeDb();
  });

  group('Window Auftrag Creation & Cloning Tests (DatabaseService)', () {
    test('Manager creates blank window Wartung job from scratch', () async {
      final inspId = await DatabaseService.createAuftragFromLatestInspection(
        projectNumber: 'PRJ-WIN-01',
        objectAddress: 'Fenstergasse 10, 20095 Hamburg',
        clientName: 'Fenster Bau GmbH',
        jobNumber: 'WIN-WARTUNG-2026-01',
        date: DateTime(2026, 4, 1),
        orderType: 'Wartung',
        assetType: 'window',
        contactPerson: 'Herr Glaser',
        inspectorName: 'Prüfer Schmidt',
        cloneDoors: false,
      );

      expect(inspId, isPositive);

      final insp = await DatabaseService.getInspectionById(inspId);
      expect(insp, isNotNull);
      expect(insp!['projectNumber'], 'PRJ-WIN-01');
      expect(insp['orderType'], 'Wartung');
      expect(insp['assetType'], 'window');
      expect(insp['jobNumber'], 'WIN-WARTUNG-2026-01');

      // Verify no windows or doors are linked
      final windows = await DatabaseService.getWindowsByInspectionId(inspId);
      expect(windows, isEmpty);
      final doors = await DatabaseService.getInspectionDoorsByInspectionId(inspId);
      expect(doors, isEmpty);
    });

    test('Manager creates blank window Reparatur job from scratch', () async {
      final repDate = DateTime(2026, 5, 20);
      final inspId = await DatabaseService.createAuftragFromLatestInspection(
        projectNumber: 'PRJ-WIN-02',
        objectAddress: 'Fenstergasse 12, 20095 Hamburg',
        clientName: 'Fenster Bau GmbH',
        jobNumber: 'WIN-REP-2026-01',
        date: DateTime(2026, 5, 10),
        orderType: 'Reparatur',
        assetType: 'window',
        repairDate: repDate,
        contactPerson: 'Frau Kante',
        inspectorName: 'Techniker Otto',
        cloneDoors: false,
      );

      expect(inspId, isPositive);

      final insp = await DatabaseService.getInspectionById(inspId);
      expect(insp, isNotNull);
      expect(insp!['orderType'], 'Reparatur');
      expect(insp['assetType'], 'window');
      expect(insp['repairDate'], isNotNull);
    });

    test('Clones windows and propagates only open defects into follow-up inspection', () async {
      // 1. Base window inspection
      final baseInspId = await DatabaseService.createAuftragFromLatestInspection(
        projectNumber: 'PRJ-WIN-CLONE',
        objectAddress: 'Glasweg 1, 10115 Berlin',
        clientName: 'City Office KG',
        jobNumber: 'WIN-2025-BASE',
        date: DateTime(2025, 6, 1),
        orderType: 'Wartung',
        assetType: 'window',
        cloneDoors: false,
      );

      // Add 2 windows
      final win1 = _createTestWindow(windowNumber: 'W-01', floor: 'EG', roomNumber: '0.01');
      final win1Id = await DatabaseService.insertWindow(win1);
      final junc1Id = await DatabaseService.insertInspectionWindow({
        'inspectionId': baseInspId,
        'windowId': win1Id,
        'status': 'Geprüft',
        'notes': 'Fenster 1 Notiz',
      });

      final win2 = _createTestWindow(windowNumber: 'W-02', floor: '1.OG', roomNumber: '1.01');
      final win2Id = await DatabaseService.insertWindow(win2);
      final junc2Id = await DatabaseService.insertInspectionWindow({
        'inspectionId': baseInspId,
        'windowId': win2Id,
        'status': 'Geprüft',
        'notes': 'Fenster 2 Notiz',
      });

      // Add errors:
      // On W-01: 1 open error and 1 resolved error
      await DatabaseService.insertInspectionWindowError(
        InspectionWindowError(
          inspectionWindowId: junc1Id,
          errorCode: 'W-ERR-01',
          quantity: 1,
          severity: 'medium',
          notes: 'Dichtung defekt',
          resolutionStatus: 'Open',
        ),
      );
      await DatabaseService.insertInspectionWindowError(
        InspectionWindowError(
          inspectionWindowId: junc1Id,
          errorCode: 'W-ERR-02',
          quantity: 1,
          severity: 'low',
          notes: 'Griff locker - repariert',
          resolutionStatus: 'Gelöst',
        ),
      );

      // On W-02: only 1 resolved error
      await DatabaseService.insertInspectionWindowError(
        InspectionWindowError(
          inspectionWindowId: junc2Id,
          errorCode: 'W-ERR-03',
          quantity: 1,
          severity: 'low',
          notes: 'Justierung erledigt',
          resolutionStatus: 'Resolved',
        ),
      );

      // 2. Create follow-up Wartung job cloning windows
      final followUpInspId = await DatabaseService.createAuftragFromLatestInspection(
        projectNumber: 'PRJ-WIN-CLONE',
        objectAddress: 'Glasweg 1, 10115 Berlin',
        clientName: 'City Office KG',
        jobNumber: 'WIN-2026-FOLLOWUP',
        date: DateTime(2026, 6, 1),
        orderType: 'Wartung',
        assetType: 'window',
        cloneDoors: true,
        sourceInspectionId: baseInspId,
      );

      expect(followUpInspId, isPositive);

      final followUpWindows = await DatabaseService.getWindowsByInspectionId(followUpInspId);
      expect(followUpWindows.length, 2);

      // Status of junctions must be 'Pending'
      final junctions = await DatabaseService.getInspectionWindowsByInspectionId(followUpInspId);
      expect(junctions.length, 2);
      for (final j in junctions) {
        expect(j['status'], 'Pending');
      }

      // Check errors on W-01
      final juncW1 = junctions.firstWhere((j) => j['windowId'] == win1Id);
      final errorsW1 = await DatabaseService.getInspectionWindowErrors(juncW1['id'] as int);
      expect(errorsW1.length, 1);
      expect(errorsW1.first.errorCode, 'W-ERR-01');
      expect(errorsW1.first.resolutionStatus, 'Open');
      expect(juncW1['notes'], 'Fenster 1 Notiz');

      // Check errors on W-02 (all resolved, so should have 0 open errors and cleared notes)
      final juncW2 = junctions.firstWhere((j) => j['windowId'] == win2Id);
      final errorsW2 = await DatabaseService.getInspectionWindowErrors(juncW2['id'] as int);
      expect(errorsW2, isEmpty);
      expect(juncW2['notes'], '');
    });

    test('Follow-up Reparatur window job inherits open defects as repair guide', () async {
      // 1. Base window inspection
      final baseInspId = await DatabaseService.createAuftragFromLatestInspection(
        projectNumber: 'PRJ-WIN-REP-GUIDE',
        objectAddress: 'Sonnenschutz-Allee 5, Köln',
        clientName: 'Köln Wohnen',
        jobNumber: 'WIN-BASE-2026',
        date: DateTime(2026, 1, 10),
        orderType: 'Wartung',
        assetType: 'window',
        cloneDoors: false,
      );

      final win1 = _createTestWindow(windowNumber: 'W-100', floor: 'EG', roomNumber: '0.05');
      final win1Id = await DatabaseService.insertWindow(win1);
      final juncId = await DatabaseService.insertInspectionWindow({
        'inspectionId': baseInspId,
        'windowId': win1Id,
        'status': 'Geprüft',
        'notes': 'Raffstore blockiert',
      });

      await DatabaseService.insertInspectionWindowError(
        InspectionWindowError(
          inspectionWindowId: juncId,
          errorCode: 'W-RAFF-01',
          quantity: 1,
          severity: 'high',
          notes: 'Motor defekt',
          resolutionStatus: 'Open',
        ),
      );

      // 2. Create Reparatur order for this window inspection
      final repInspId = await DatabaseService.createAuftragFromLatestInspection(
        projectNumber: 'PRJ-WIN-REP-GUIDE',
        objectAddress: 'Sonnenschutz-Allee 5, Köln',
        clientName: 'Köln Wohnen',
        jobNumber: 'WIN-REP-2026-FIX',
        date: DateTime(2026, 1, 10),
        orderType: 'Reparatur',
        assetType: 'window',
        repairDate: DateTime(2026, 1, 15),
        cloneDoors: true,
        sourceInspectionId: baseInspId,
      );

      final insp = await DatabaseService.getInspectionById(repInspId);
      expect(insp!['orderType'], 'Reparatur');
      expect(insp['assetType'], 'window');

      final junctions = await DatabaseService.getInspectionWindowsByInspectionId(repInspId);
      expect(junctions.length, 1);
      expect(junctions.first['status'], 'Pending');
      expect(junctions.first['notes'], 'Raffstore blockiert');

      final errors = await DatabaseService.getInspectionWindowErrors(junctions.first['id'] as int);
      expect(errors.length, 1);
      expect(errors.first.errorCode, 'W-RAFF-01');
      expect(errors.first.resolutionStatus, 'Open');
    });
  });

  group('Window Auftrag Creation (LocalDatabaseService)', () {
    test('Inspector creates window Auftrag in local database', () async {
      final inspId = await LocalDatabaseService.createAuftragFromLatestInspection(
        projectNumber: 'LOCAL-PRJ-WIN-01',
        objectAddress: 'Lokale Str. 3, Kiel',
        clientName: 'Kiel Verwaltung',
        jobNumber: 'LOCAL-WIN-2026-01',
        date: DateTime(2026, 7, 1),
        orderType: 'Wartung',
        assetType: 'window',
        cloneDoors: false,
      );

      expect(inspId, isPositive);
      final insp = await LocalDatabaseService.getInspectionById(inspId);
      expect(insp, isNotNull);
      expect(insp!['assetType'], 'window');
      expect(insp['jobNumber'], 'LOCAL-WIN-2026-01');
    });
  });

  group('CreateProjectDialog Widget Tests for Windows', () {
    testWidgets('Allows selecting Fenster assetType and shows window UI copy', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CreateProjectDialog.show(
                  context,
                  initialAssetType: 'window',
                ),
                child: const Text('Open Window Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Window Dialog'));
      await tester.pumpAndSettle();

      // Check header and segments
      expect(find.text('Prüfobjekt (Gegenstand):'), findsOneWidget);
      expect(find.text('Türen'), findsOneWidget);
      expect(find.text('Fenster'), findsOneWidget);

      // In window mode, copy adapts to "0 Fenster"
      expect(find.text('Leervorlage (0 Fenster) anlegen'), findsOneWidget);

      // Switch to Türen
      await tester.tap(find.text('Türen'));
      await tester.pumpAndSettle();
      expect(find.text('Leervorlage (0 Türen) anlegen'), findsOneWidget);

      // Switch back to Fenster
      await tester.tap(find.text('Fenster'));
      await tester.pumpAndSettle();
      expect(find.text('Leervorlage (0 Fenster) anlegen'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
    });
  });
}
