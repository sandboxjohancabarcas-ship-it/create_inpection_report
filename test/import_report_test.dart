import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/models/import_report.dart';

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
    });
  });
}
