import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/utils/file_export_helper.dart';

void main() {
  group('Package Naming Convention Tests', () {
    test('buildPackageFileName generates exact inspector package name according to specifications', () {
      final fixedDate = DateTime(2026, 9, 25, 10, 11, 3);
      final filename = FileExportHelper.buildPackageFileName(
        jobNumber: '25-13610-AB',
        projectNumber: 'P-000604',
        objectAddress: 'LPS-Museum',
        packageType: 'inspektion_paket',
        timestamp: fixedDate,
      );

      expect(
        filename,
        equals('25-13610-AB_P-000604_LPS-Museum_inspektion_paket_20260925_101103.db'),
      );
    });

    test('buildPackageFileName generates exact manager result package name according to specifications', () {
      final fixedDate = DateTime(2026, 9, 25, 10, 11, 3);
      final filename = FileExportHelper.buildPackageFileName(
        jobNumber: '25-13610-AB',
        projectNumber: 'P-000604',
        objectAddress: 'LPS-Museum',
        packageType: 'inspektion_ergebnis',
        timestamp: fixedDate,
      );

      expect(
        filename,
        equals('25-13610-AB_P-000604_LPS-Museum_inspektion_ergebnis_20260925_101103.db'),
      );
    });

    test('buildPackageFileName replaces all whitespaces and forbidden characters with underscores', () {
      final fixedDate = DateTime(2026, 9, 27, 15, 30, 45);
      final filename = FileExportHelper.buildPackageFileName(
        jobNumber: '25-13966-AB',
        projectNumber: 'P-000604',
        objectAddress: 'Polizeimuseum Carl-Cohn-Straße 39',
        packageType: 'inspektion_ergebnis',
        timestamp: fixedDate,
      );

      expect(
        filename,
        equals('25-13966-AB_P-000604_Polizeimuseum_Carl-Cohn-Straße_39_inspektion_ergebnis_20260927_153045.db'),
      );
    });

    test('buildPackageFileName handles missing optional components cleanly', () {
      final fixedDate = DateTime(2026, 9, 27, 15, 30, 45);
      final filename = FileExportHelper.buildPackageFileName(
        jobNumber: '25-12345',
        projectNumber: null,
        objectAddress: 'Musterstraße 12',
        packageType: 'inspektion_paket',
        timestamp: fixedDate,
      );

      expect(
        filename,
        equals('25-12345_Musterstraße_12_inspektion_paket_20260927_153045.db'),
      );
    });
  });
}
