import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/pages/read_customer_data.dart';
import 'package:wartungstool/models/models.dart';

void main() {
  // Initialize FFI for local SQLite testing on Windows
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CustomerDataImporter Integration Tests', () {
    setUp(() async {
      // Start with a clean slate for each test
      await DatabaseService.clearDatabase();
      
      // Seed the required catalog items to match our CSV "Source of Truth"
      // These IDs are required for the mapping logic to find a target in the DB
      await DatabaseService.insertErrorCatalog(ErrorCatalog(code: "3", description: "Unzulässige Feststellung", category: "Allgemein"));
      await DatabaseService.insertErrorCatalog(ErrorCatalog(code: "14", description: "Kein Kennzeichnungsschild", category: "Allgemein"));
      await DatabaseService.insertErrorCatalog(ErrorCatalog(code: "1", description: "Kein Zugang", category: "Allgemein"));
    });

    test('Full OCR Import Verification (Pivot and Alias Logic)', () async {
      // Mocked snippet from the provided PDF OCR
      const mockOcr = '''
Prüfprotokoll Brand- und Rauchschutztüren
Kunde: Stadt Geesthacht, Markt 15, 21502 Geesthacht Objekt: Fam. Zentrum Regenbogen, Neuer Krug 31, 21502 Geesthacht Datum: 24.02.2025 Ansprechpartner: Herr Basau Monteur: Gert Auftragsnummer: 25-12115-AB
==End of OCR for page 1==
1 1- 1.OG Lagerraum Lagerraum MZT-1 1 Holzblatt ? DIN L Nein Nein 65/72/8/20x2 35/FR Nein Nein X X D-D Nein N 1 1 Sicherungskasten im Raum!
10 10- EG Flur Putzmittelraum MZT-1 1 Holzblatt ? DIN R Nein Nein 65/72/8/20x2 35/FR Nein Nein X D-D Nein X N 0 0 0 0 0 0 0 0 0 1 Heizkreisverteiler
''';

      await CustomerDataImporter.importFromOcr(mockOcr);

      // 1. Verify Inspection Header Extraction
      final inspections = await DatabaseService.searchInspections('Geesthacht');
      expect(inspections.length, 1, reason: 'Should create one inspection record');
      expect(inspections.first['jobNumber'], '25-12115-AB');
      expect(inspections.first['clientName'], 'Stadt Geesthacht, Markt 15, 21502 Geesthacht');

      // 2. Verify Door "Patient" Identity (Alias Logic)
      final doors = await DatabaseService.getAllDoors();
      expect(doors.length, 2, reason: 'Should parse two door rows (Pos 1 and 10)');
      
      final door1 = doors.firstWhere((d) => d.doorNumber == '1-');
      // Alias: shortened to max 12 chars: STA-FAM-1
      expect(door1.doorAlias, 'STA-FAM-1');
      expect(door1.roomDesignation, 'Lagerraum', reason: 'Should deduplicate "Lagerraum Lagerraum"');

      // 3. Verify Pivot Logic (okay column 'N' -> function not ok)
      expect(door1.doorFunctionOK, isFalse);

      // 4. Verify Error Mapping
      // Pos 10 in mock has a '1' in the 10th column after pivot. 
      // Importer maps Col 10 to CSV Code "1" (Kein Zugang).
      final door10 = doors.firstWhere((d) => d.doorNumber == '10-');
      final inspectionId = inspections.first['inspectionId'];
      final junctions = await DatabaseService.getInspectionDoorsByInspectionId(inspectionId);
      
      final door10Junction = junctions.firstWhere((j) => j['doorId'] == door10.id);
      final errors = await DatabaseService.getErrorsForInspectionDoorIds([door10Junction['id']]);

      expect(errors.any((e) => e['code'] == '1'), isTrue, 
          reason: 'Column 10 indicator should map to Error Catalog Code 1');
    });
  });
}