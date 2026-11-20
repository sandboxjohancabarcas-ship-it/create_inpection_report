import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/services/excel_data_importer.dart';
import 'package:wartungstool/utils/date_format_helper.dart';
import 'package:wartungstool/utils/file_export_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('General Inspection Changes Requirements Tests', () {
    test('Requirement 1: Job number strictly extracted from file name and not from content', () async {
      // Find a real test file with a job number in the filename
      final testFile = File('test/test_data/23-08561-AB Tesdorpfstraße 8 Fensterliste Final.xlsx');
      if (testFile.existsSync()) {
        final result = await ExcelDataImporter.importFromFile(testFile);
        expect(result.jobNumber, equals('23-08561-AB'));
      }

      final doorTestFile = File('test/test_data/template_25-13966-AB P-000604 LPS Polizeimuseum Carl-Cohn-Straße 39 Türen.xlsx');
      if (doorTestFile.existsSync()) {
        final result = await ExcelDataImporter.importFromFile(doorTestFile);
        expect(result.jobNumber, equals('25-13966-AB'));
      }
    });

    test('Requirement 2: .db filename has package type at the very end', () {
      final fixedDate = DateTime(2026, 11, 19, 11, 57, 58);
      
      // inspektion_paket
      final pkgName = FileExportHelper.buildPackageFileName(
        jobNumber: '26-15230-AB',
        projectNumber: 'P-003527',
        objectAddress: 'FFW Saseler Parkweg 1 22393 Hamburg',
        packageType: 'inspektion_paket',
        timestamp: fixedDate,
      );
      expect(
        pkgName,
        equals('26-15230-AB_P-003527_FFW_Saseler_Parkweg_1_22393_Hamburg_19112026_115758_inspektion_paket.db'),
      );

      // paket_ergebnis
      final resName = FileExportHelper.buildPackageFileName(
        jobNumber: '26-15230-AB',
        projectNumber: 'P-003527',
        objectAddress: 'FFW Saseler Parkweg 1 22393 Hamburg',
        packageType: 'paket_ergebnis',
        timestamp: fixedDate,
      );
      expect(
        resName,
        equals('26-15230-AB_P-003527_FFW_Saseler_Parkweg_1_22393_Hamburg_19112026_115758_paket_ergebnis.db'),
      );

      // Legacy inspektion_ergebnis mapped to paket_ergebnis
      final legacyName = FileExportHelper.buildPackageFileName(
        jobNumber: '26-15230-AB',
        projectNumber: 'P-003527',
        objectAddress: 'FFW Saseler Parkweg 1 22393 Hamburg',
        packageType: 'inspektion_ergebnis',
        timestamp: fixedDate,
      );
      expect(
        legacyName,
        equals('26-15230-AB_P-003527_FFW_Saseler_Parkweg_1_22393_Hamburg_19112026_115758_paket_ergebnis.db'),
      );
    });

    test('Requirement 3: Date formatting everywhere converts to Day.Month.Year', () {
      expect(DateFormatHelper.formatDate('2026-11-19'), equals('19.11.2026'));
      expect(DateFormatHelper.formatDate('2026-05-04'), equals('04.05.2026'));
      expect(DateFormatHelper.formatDate(DateTime(2026, 11, 19)), equals('19.11.2026'));
      expect(DateFormatHelper.formatDate('19.11.2026'), equals('19.11.2026'));
      expect(DateFormatHelper.formatDate(''), equals(''));
      expect(DateFormatHelper.formatDate(null), equals(''));
    });
  });
}
