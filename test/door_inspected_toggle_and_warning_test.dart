import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/models/import_report.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/utils/file_export_helper.dart';
import 'package:wartungstool/widgets/import_report_dialog.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationSupportPath() async => Directory.current.path;
  @override
  Future<String?> getApplicationDocumentsPath() async => Directory.current.path;
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
  @override
  Future<String?> getDownloadsPath() async => Directory.systemTemp.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Door "Geprüft" Toggle & Unprocessed Warning Tests', () {
    test('Setting and undoing inspection status in LocalDatabaseService and DatabaseService', () async {
      final db = await LocalDatabaseService.getDb();
      await db.delete('inspection_doors');
      await db.delete('doors');
      await db.delete('inspections');

      final inspId = await db.insert('inspections', {
        'jobNumber': 'AUF-2026-001',
        'clientName': 'Musterkunde',
        'date': '2026-09-30',
      });

      final doorId = await db.insert('doors', {
        'doorNumber': 'T-01',
        'floor': 'OG1',
        'roomDesignation': 'Besprechung 101',
        'provisionalAlias': 'ALIAS-001',
      });

      // 1. Initially Pending
      await LocalDatabaseService.setDoorInspectionStatus(
        inspectionId: inspId,
        doorId: doorId,
        status: 'Pending',
      );
      var statuses = await LocalDatabaseService.getDoorInspectionStatuses(inspId);
      expect(statuses[doorId], 'Pending');

      // 2. Set to Inspected ("Geprüft")
      await LocalDatabaseService.setDoorInspectionStatus(
        inspectionId: inspId,
        doorId: doorId,
        status: 'Inspected',
      );
      statuses = await LocalDatabaseService.getDoorInspectionStatuses(inspId);
      expect(statuses[doorId], 'Inspected');

      // 3. Undo marker back to Pending ("Offen")
      await LocalDatabaseService.setDoorInspectionStatus(
        inspectionId: inspId,
        doorId: doorId,
        status: 'Pending',
      );
      statuses = await LocalDatabaseService.getDoorInspectionStatuses(inspId);
      expect(statuses[doorId], 'Pending');

      // 4. Same toggle capability in DatabaseService
      final mDb = await DatabaseService.getDb();
      await mDb.delete('inspection_doors');
      await mDb.delete('doors');
      await mDb.delete('inspections');

      final mInspId = await mDb.insert('inspections', {
        'jobNumber': 'AUF-MGR-001',
        'clientName': 'Manager Kunde',
        'date': '2026-09-30',
      });

      final mDoorId = await mDb.insert('doors', {
        'doorNumber': 'T-02',
        'floor': 'EG',
        'roomDesignation': 'Empfang',
      });

      await DatabaseService.setDoorInspectionStatus(
        inspectionId: mInspId,
        doorId: mDoorId,
        status: 'Inspected',
      );
      var mStatuses = await DatabaseService.getDoorInspectionStatuses(mInspId);
      expect(mStatuses[mDoorId], 'Inspected');

      await DatabaseService.setDoorInspectionStatus(
        inspectionId: mInspId,
        doorId: mDoorId,
        status: 'Pending',
      );
      mStatuses = await DatabaseService.getDoorInspectionStatuses(mInspId);
      expect(mStatuses[mDoorId], 'Pending');
    });

    test('DoorChangeItem and ImportReport properly identify unprocessed doors', () {
      final item1 = DoorChangeItem(
        doorAlias: 'D-001',
        doorNumber: 'T-101',
        roomDesignation: 'Küche',
        floor: 'EG',
        changeType: 'updated',
        status: 'Inspected',
      );
      final item2 = DoorChangeItem(
        doorAlias: 'D-002',
        doorNumber: 'T-102',
        roomDesignation: 'Lager',
        floor: 'UG',
        changeType: 'updated',
        status: 'Pending',
      );
      final item3 = DoorChangeItem(
        doorAlias: 'D-003',
        doorNumber: 'T-103',
        roomDesignation: 'Archiv',
        floor: 'UG',
        changeType: 'new',
        status: null,
      );

      expect(item1.isProcessed, isTrue);
      expect(item2.isProcessed, isFalse);
      expect(item3.isProcessed, isFalse);

      final report = ImportReport(
        packageName: 'test_ergebnis.db',
        importedAt: DateTime.now(),
        newDoorsCount: 1,
        updatedDoorsCount: 2,
        newInspectionsCount: 1,
        updatedInspectionsCount: 0,
        totalErrorsImported: 1,
        totalAttachmentsImported: 0,
        doorChanges: [item1, item2, item3],
        newCatalogProposals: [],
      );

      expect(report.hasUnprocessedDoors, isTrue);
      expect(report.unprocessedDoors.length, 2);
      expect(report.unprocessedDoors.map((d) => d.doorNumber).toList(), containsAll(['T-102', 'T-103']));
    });

    testWidgets('FileExportHelper.confirmUnprocessedDoors returns true if all doors inspected', (tester) async {
      late BuildContext testContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final doors = [
        Door.fromMap({'id': 1, 'pos': 1, 'doorNumber': 'T-01', 'floor': 'EG', 'roomDesignation': 'Raum 1'}),
        Door.fromMap({'id': 2, 'pos': 2, 'doorNumber': 'T-02', 'floor': 'EG', 'roomDesignation': 'Raum 2'}),
      ];
      final statuses = {
        1: 'Inspected',
        2: 'Geprüft',
      };

      final result = await FileExportHelper.confirmUnprocessedDoors(
        context: testContext,
        doors: doors,
        statuses: statuses,
      );

      expect(result, isTrue);
    });

    testWidgets('FileExportHelper.confirmUnprocessedDoors shows warning dialog when doors are unprocessed', (tester) async {
      bool? dialogResult;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                return ElevatedButton(
                  onPressed: () async {
                    final doors = [
                      Door.fromMap({'id': 1, 'pos': 1, 'doorNumber': 'T-01', 'floor': 'EG', 'roomDesignation': 'Büro 1'}),
                      Door.fromMap({'id': 2, 'pos': 2, 'doorNumber': 'T-02', 'floor': '1.OG', 'roomDesignation': 'Labor'}),
                    ];
                    final statuses = {
                      1: 'Inspected',
                      2: 'Pending',
                    };
                    dialogResult = await FileExportHelper.confirmUnprocessedDoors(
                      context: ctx,
                      doors: doors,
                      statuses: statuses,
                    );
                  },
                  child: const Text('Export Test'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Export Test'));
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.text('Unbearbeitete Türen vorhanden'), findsOneWidget);
      expect(find.textContaining('1 von 2 Türen offen'), findsOneWidget);
      expect(find.text('Tür T-02'), findsOneWidget);
      expect(find.text('Trotzdem exportieren'), findsOneWidget);
      expect(find.text('Abbrechen / Weiter prüfen'), findsOneWidget);

      // Tap Trotzdem exportieren
      await tester.tap(find.text('Trotzdem exportieren'));
      await tester.pumpAndSettle();

      expect(dialogResult, isTrue);
    });

    testWidgets('ImportReportDialog displays prominent unprocessed doors warning banner', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() async => await tester.binding.setSurfaceSize(null));

      final report = ImportReport(
        packageName: 'auftrag_ergebnis.db',
        importedAt: DateTime(2026, 9, 30, 14, 0),
        newDoorsCount: 0,
        updatedDoorsCount: 2,
        newInspectionsCount: 0,
        updatedInspectionsCount: 1,
        totalErrorsImported: 2,
        totalAttachmentsImported: 0,
        doorChanges: [
          DoorChangeItem(
            doorAlias: 'ALIAS-01',
            doorNumber: 'T-101',
            roomDesignation: 'Besprechungsraum',
            floor: 'EG',
            changeType: 'updated',
            status: 'Inspected',
          ),
          DoorChangeItem(
            doorAlias: 'ALIAS-02',
            doorNumber: 'T-102',
            roomDesignation: 'Schaltzentrale',
            floor: '2.OG',
            changeType: 'updated',
            status: 'Offen',
          ),
        ],
        newCatalogProposals: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportReportDialog(report: report),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Warning banner presence
      expect(find.textContaining('1 unbearbeitete / nicht geprüfte Tür(en) im Paket!'), findsOneWidget);
      expect(find.textContaining('Tür T-102 (2.OG | Schaltzentrale)'), findsOneWidget);

      // In the doors list
      expect(find.text('Geprüft'), findsOneWidget);
      expect(find.text('Nicht geprüft'), findsOneWidget);
    });
  });
}
