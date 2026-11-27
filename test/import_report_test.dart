import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/models/import_report.dart';
import 'package:wartungstool/widgets/import_report_dialog.dart';

void main() {
  group('ImportReport Model Tests', () {
    test('ImportReport calculates totalDoorsProcessed correctly', () {
      final report = ImportReport(
        packageName: 'inspektion_ergebnis_2026.db',
        importedAt: DateTime.now(),
        newDoorsCount: 3,
        updatedDoorsCount: 5,
        newInspectionsCount: 1,
        updatedInspectionsCount: 0,
        totalErrorsImported: 8,
        totalAttachmentsImported: 4,
        doorChanges: [
          DoorChangeItem(
            doorAlias: 'DOOR-001',
            doorNumber: 'T-101',
            roomDesignation: 'Serverraum',
            changeType: 'new',
            status: 'Completed',
            errorCount: 2,
          ),
          DoorChangeItem(
            doorAlias: 'DOOR-002',
            doorNumber: 'T-102',
            roomDesignation: 'Büro 1.02',
            changeType: 'updated',
            status: 'InProgress',
            errorCount: 0,
          ),
        ],
        newCatalogProposals: ['CAT-99: Neue Panikschloss Störung'],
      );

      expect(report.totalDoorsProcessed, equals(8));
      expect(report.newDoorsCount, equals(3));
      expect(report.updatedDoorsCount, equals(5));
      expect(report.totalErrorsImported, equals(8));
      expect(report.totalAttachmentsImported, equals(4));
      expect(report.doorChanges.length, equals(2));
      expect(report.doorChanges.first.doorAlias, equals('DOOR-001'));
      expect(report.doorChanges.first.changeType, equals('new'));
      expect(report.newCatalogProposals.first, contains('CAT-99'));
      expect(report.effectiveAssetType, equals('door'));
      expect(report.totalItemsProcessed, equals(8));
      expect(report.newItemsCount, equals(3));
      expect(report.updatedItemsCount, equals(5));
      expect(report.isWindowReport, isFalse);
    });

    test('AssetTypeHelper resolves labels and icons correctly', () {
      expect(AssetTypeHelper.getLabel('window', plural: false), equals('Fenster'));
      expect(AssetTypeHelper.getLabel('window', plural: true), equals('Fenster'));
      expect(AssetTypeHelper.getLabel('door', plural: false), equals('Tür'));
      expect(AssetTypeHelper.getLabel('door', plural: true), equals('Türen'));
      expect(AssetTypeHelper.getLabel('mixed', plural: false), equals('Objekt'));
      expect(AssetTypeHelper.getLabel('mixed', plural: true), equals('Objekte'));
      expect(AssetTypeHelper.getLabel('schiebetor', plural: true), equals('Schiebetore'));
      expect(AssetTypeHelper.getLabel('rwa', plural: true), equals('RWA-Anlagen'));
      expect(AssetTypeHelper.getLabel('rwa', plural: false), equals('RWA-Anlage'));
      expect(AssetTypeHelper.getLabel('rwa-anlage', plural: true), equals('RWA-Anlagen'));
      expect(AssetTypeHelper.getLabel('smoke_ventilation', plural: true), equals('RWA-Anlagen'));
      expect(AssetTypeHelper.getLabel('smoke ventilation', plural: true), equals('RWA-Anlagen'));
      expect(AssetTypeHelper.getLabel('smoke ventilation', plural: false), equals('RWA-Anlage'));
      expect(AssetTypeHelper.getLabel('tor', plural: true), equals('Tore'));
      expect(AssetTypeHelper.getIcon('rwa'), equals(Icons.air));
      expect(AssetTypeHelper.getIcon('smoke_ventilation'), equals(Icons.air));
    });

    test('ImportReport recognizes window imports and calculates window metrics', () {
      final report = ImportReport(
        packageName: '24-00000-AB P-000000 Fensterliste.xlsx',
        importedAt: DateTime.now(),
        assetType: 'window',
        newWindowsCount: 213,
        updatedWindowsCount: 0,
        doorChanges: [
          DoorChangeItem(
            doorAlias: 'WIN-001',
            doorNumber: '03-044',
            roomDesignation: 'Büro 3.44',
            changeType: 'new',
            status: 'Completed',
            assetType: 'window',
            errorCount: 1,
          ),
        ],
        fileReports: [
          InspectionFileReportItem(
            fileName: 'Fensterliste.xlsx',
            status: 'Erfolgreich',
            assetType: 'window',
            newWindowsCount: 213,
            doorChanges: [
              DoorChangeItem(
                doorAlias: 'WIN-001',
                doorNumber: '03-044',
                roomDesignation: 'Büro 3.44',
                assetType: 'window',
              ),
            ],
          ),
        ],
      );

      expect(report.isWindowReport, isTrue);
      expect(report.effectiveAssetType, equals('window'));
      expect(report.totalWindowsProcessed, equals(213));
      expect(report.totalItemsProcessed, equals(213));
      expect(report.newItemsCount, equals(213));
      expect(report.updatedItemsCount, equals(0));
      expect(report.doorChanges.first.isWindow, isTrue);
      expect(report.fileReports.first.isWindow, isTrue);
      expect(report.fileReports.first.totalItems, equals(213));
    });

    test('ImportReport handles mixed imports correctly', () {
      final report = ImportReport(
        packageName: 'Misch-Paket',
        importedAt: DateTime.now(),
        newDoorsCount: 5,
        newWindowsCount: 10,
        doorChanges: [
          DoorChangeItem(doorAlias: 'D-1', doorNumber: '1', roomDesignation: '', assetType: 'door'),
          DoorChangeItem(doorAlias: 'W-1', doorNumber: '1', roomDesignation: '', assetType: 'window'),
        ],
      );

      expect(report.effectiveAssetType, equals('mixed'));
      expect(report.totalDoorsProcessed, equals(5));
      expect(report.totalWindowsProcessed, equals(10));
      expect(report.totalItemsProcessed, equals(15));
      expect(report.newItemsCount, equals(15));
    });

    testWidgets('ImportReportDialog displays window metrics and titles correctly', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final windowReport = ImportReport(
        packageName: '24-00000-AB Fensterliste.xlsx',
        importedAt: DateTime.now(),
        assetType: 'window',
        newWindowsCount: 213,
        updatedWindowsCount: 0,
        doorChanges: [
          DoorChangeItem(
            doorAlias: 'F-24-00000-AB-03-044',
            doorNumber: '03-044',
            roomDesignation: 'Büro 3.44',
            changeType: 'new',
            status: 'geprüft',
            assetType: 'window',
            errorCount: 1,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportReportDialog(report: windowReport),
          ),
        ),
      );

      // Verify that window labels are shown, NOT door labels
      expect(find.text('Verarbeitete Fenster'), findsOneWidget);
      expect(find.text('213'), findsOneWidget);
      expect(find.text('+213 neu, 0 aktualisiert'), findsOneWidget);
      expect(find.text('Alle Fenster (1)'), findsOneWidget);
      expect(find.text('Fenster 03-044'), findsOneWidget);
      expect(find.text('Verarbeitete Türen'), findsNothing);
    });

    testWidgets('ImportReportDialog displays door metrics and titles for door report', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final doorReport = ImportReport(
        packageName: 'Türenliste.xlsx',
        importedAt: DateTime.now(),
        assetType: 'door',
        newDoorsCount: 42,
        updatedDoorsCount: 3,
        doorChanges: [
          DoorChangeItem(
            doorAlias: 'T-001',
            doorNumber: 'T-01',
            roomDesignation: 'Flur',
            changeType: 'new',
            status: 'geprüft',
            assetType: 'door',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportReportDialog(report: doorReport),
          ),
        ),
      );

      expect(find.text('Verarbeitete Türen'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
      expect(find.text('+42 neu, 3 aktualisiert'), findsOneWidget);
      expect(find.text('Alle Türen (1)'), findsOneWidget);
      expect(find.text('Tür T-01'), findsOneWidget);
      expect(find.text('Verarbeitete Fenster'), findsNothing);
      expect(find.text('Verarbeitete RWA-Anlagen'), findsNothing);
    });

    test('ImportReport recognizes RWA imports and calculates RWA metrics', () {
      final report = ImportReport(
        packageName: '26-14517-AB Checkliste RWA-Anlage-1 Gebäude G.xlsx',
        importedAt: DateTime.now(),
        assetType: 'rwa',
        newRwaCount: 4,
        updatedRwaCount: 1,
        totalErrorsImported: 2,
        doorChanges: [
          DoorChangeItem(
            doorAlias: 'RWA-01',
            doorNumber: 'RWA-01',
            roomDesignation: 'Gebäude G',
            changeType: 'new',
            status: 'Geprüft',
            assetType: 'rwa',
            errorCount: 2,
          ),
        ],
        fileReports: [
          InspectionFileReportItem(
            fileName: 'Checkliste RWA-Anlage-1.xlsx',
            status: 'Erfolgreich',
            assetType: 'rwa',
            newRwaCount: 4,
            updatedRwaCount: 1,
            doorChanges: [
              DoorChangeItem(
                doorAlias: 'RWA-01',
                doorNumber: 'RWA-01',
                roomDesignation: 'Gebäude G',
                assetType: 'rwa',
              ),
            ],
          ),
        ],
      );

      expect(report.isRwaReport, isTrue);
      expect(report.isWindowReport, isFalse);
      expect(report.effectiveAssetType, equals('rwa'));
      expect(report.totalRwaProcessed, equals(5));
      expect(report.totalItemsProcessed, equals(5));
      expect(report.newItemsCount, equals(4));
      expect(report.updatedItemsCount, equals(1));
      expect(report.doorChanges.first.isRwa, isTrue);
      expect(report.fileReports.first.isRwa, isTrue);
      expect(report.fileReports.first.totalItems, equals(5));
    });

    testWidgets('ImportReportDialog displays RWA / smoke ventilation metrics and titles correctly', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final rwaReport = ImportReport(
        packageName: '26-14517-AB Checkliste RWA-Anlage-1 Gebäude G.xlsx',
        importedAt: DateTime.now(),
        assetType: 'rwa',
        newRwaCount: 1,
        updatedRwaCount: 0,
        doorChanges: [
          DoorChangeItem(
            doorAlias: 'RWA-Gebäude-G',
            doorNumber: 'Anlage 1',
            roomDesignation: 'Gebäude G / EG',
            changeType: 'new',
            status: 'geprüft',
            assetType: 'rwa',
            errorCount: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportReportDialog(report: rwaReport),
          ),
        ),
      );

      // Verify that RWA labels are shown, NOT door labels
      expect(find.text('Verarbeitete RWA-Anlagen'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('+1 neu, 0 aktualisiert'), findsOneWidget);
      expect(find.text('Alle RWA-Anlagen (1)'), findsOneWidget);
      expect(find.text('RWA-Anlage Anlage 1'), findsOneWidget);
      expect(find.text('Verarbeitete Türen'), findsNothing);
      expect(find.text('Verarbeitete Fenster'), findsNothing);
    });
  });
}
