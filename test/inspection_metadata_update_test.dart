import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Single Inspection Metadata Update Tests', () {
    test('Master DB updateInspection modifies all metadata fields at once', () async {
      final int inspectionId = await DatabaseService.insertInspection({
        'clientName': 'Kunde Alt',
        'objectAddress': 'Adresse Alt 1',
        'date': '2026-01-01T00:00:00.000',
        'contactPerson': 'Herr Alt',
        'inspectorName': 'Prüfer 1',
        'jobNumber': 'JOB-100',
        'projectNumber': 'P-000100',
      });

      final initial = await DatabaseService.getInspectionById(inspectionId);
      expect(initial, isNotNull);
      expect(initial!['clientName'], equals('Kunde Alt'));
      expect(initial['jobNumber'], equals('JOB-100'));
      expect(initial['projectNumber'], equals('P-000100'));

      // Update metadata at once
      await DatabaseService.updateInspection({
        'inspectionId': inspectionId,
        'clientName': 'Kunde Neu',
        'objectAddress': 'Adresse Neu 99',
        'date': '2026-08-05T12:00:00.000',
        'contactPerson': 'Frau Neu',
        'inspectorName': 'Prüfer 2',
        'jobNumber': 'JOB-200',
        'projectNumber': 'P-000200',
      });

      final updated = await DatabaseService.getInspectionById(inspectionId);
      expect(updated, isNotNull);
      expect(updated!['clientName'], equals('Kunde Neu'));
      expect(updated['objectAddress'], equals('Adresse Neu 99'));
      expect(updated['jobNumber'], equals('JOB-200'));
      expect(updated['contactPerson'], equals('Frau Neu'));
      expect(updated['inspectorName'], equals('Prüfer 2'));
      expect(updated['projectNumber'], equals('P-000200'));
    });

    test('Local DB updateInspection modifies all metadata fields at once', () async {
      final int inspectionId = await LocalDatabaseService.insertInspection({
        'clientName': 'Local Kunde Alt',
        'objectAddress': 'Local Alt 1',
        'date': '2026-01-01T00:00:00.000',
        'contactPerson': 'Herr Alt',
        'inspectorName': 'Prüfer Local 1',
        'jobNumber': 'LJOB-100',
        'projectNumber': 'P-000100',
      });

      final initial = await LocalDatabaseService.getInspectionById(inspectionId);
      expect(initial, isNotNull);
      expect(initial!['clientName'], equals('Local Kunde Alt'));
      expect(initial['projectNumber'], equals('P-000100'));

      // Update metadata at once
      await LocalDatabaseService.updateInspection({
        'inspectionId': inspectionId,
        'clientName': 'Local Kunde Neu',
        'objectAddress': 'Local Neu 99',
        'date': '2026-08-05T12:00:00.000',
        'contactPerson': 'Frau Local Neu',
        'inspectorName': 'Prüfer Local 2',
        'jobNumber': 'LJOB-200',
        'projectNumber': 'P-000200',
      });

      final updated = await LocalDatabaseService.getInspectionById(inspectionId);
      expect(updated, isNotNull);
      expect(updated!['clientName'], equals('Local Kunde Neu'));
      expect(updated['objectAddress'], equals('Local Neu 99'));
      expect(updated['jobNumber'], equals('LJOB-200'));
      expect(updated['projectNumber'], equals('P-000200'));
    });
  });
}
