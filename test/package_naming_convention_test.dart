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
        equals('25-13610-AB_P-000604_LPS-Museum_25092026_101103_inspektion_paket.db'),
      );
    });

    test('buildPackageFileName generates exact manager result package name according to specifications', () {
      final fixedDate = DateTime(2026, 9, 25, 10, 11, 3);
      final filename = FileExportHelper.buildPackageFileName(
        jobNumber: '25-13610-AB',
        projectNumber: 'P-000604',
        objectAddress: 'LPS-Museum',
        packageType: 'paket_ergebnis',
        timestamp: fixedDate,
      );

      expect(
        filename,
        equals('25-13610-AB_P-000604_LPS-Museum_25092026_101103_paket_ergebnis.db'),
      );
    });

    test('buildPackageFileName handles user example package name at end', () {
      final fixedDate = DateTime(2026, 11, 19, 11, 57, 58);
      final filename = FileExportHelper.buildPackageFileName(
        jobNumber: '26-15230-AB',
        projectNumber: 'P-003527',
        objectAddress: 'FFW Saseler Parkweg 1 22393 Hamburg',
        packageType: 'inspektion_paket',
        timestamp: fixedDate,
      );

      expect(
        filename,
        equals('26-15230-AB_P-003527_FFW_Saseler_Parkweg_1_22393_Hamburg_19112026_115758_inspektion_paket.db'),
      );
    });

    test('buildPackageFileName replaces all whitespaces and forbidden characters with underscores', () {
      final fixedDate = DateTime(2026, 9, 27, 15, 30, 45);
      final filename = FileExportHelper.buildPackageFileName(
        jobNumber: '25-13966-AB',
        projectNumber: 'P-000604',
        objectAddress: 'Polizeimuseum Carl-Cohn-Straße 39',
        packageType: 'paket_ergebnis',
        timestamp: fixedDate,
      );

      expect(
        filename,
        equals('25-13966-AB_P-000604_Polizeimuseum_Carl-Cohn-Straße_39_27092026_153045_paket_ergebnis.db'),
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
        equals('25-12345_Musterstraße_12_27092026_153045_inspektion_paket.db'),
      );
    });
  });
}
