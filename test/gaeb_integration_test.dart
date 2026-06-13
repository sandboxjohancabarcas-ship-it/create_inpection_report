import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/test_data_generator.dart';
import 'package:wartungstool/services/gaeb_export_service.dart';
import 'package:wartungstool/models/door.dart';
import 'package:wartungstool/models/error_catalog.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await DatabaseService.closeDb();
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'door_inspection.db');
    if (await File(path).exists()) await File(path).delete();
    await DatabaseService.getDb(); // Re-initialize with a fresh DB
  });

  tearDown(() async {
    await DatabaseService.closeDb();
    // Clean up generated export files
    final directory = await getApplicationDocumentsDirectory();
    final exportDirPath = p.join(directory.path, 'WartungsTool', 'Exports');
    final exportDir = Directory(exportDirPath);
    if (await exportDir.exists()) {
      await exportDir.delete(recursive: true);
    }
  });

  group('GAEB Export Integration Test', () {
    test('Generate test data and export to X83 file', () async {
      // 1. Generate specific test data: 1 company, 1 object, 3 doors, 1 inspection
      await TestDataGenerator.generate(
        numCustomers: 1,
        numObjectsPerCustomer: 1,
        numDoorsPerObject: 3,
        numInspectionsPerObject: 1,
      );

      // 2. Retrieve the generated inspection data
      final inspections = await DatabaseService.searchInspections('');
      expect(inspections.length, equals(1), reason: 'Should have exactly one inspection');
      final inspection = inspections.first;
      final int inspectionId = inspection['inspectionId'] as int;
      final String clientName = inspection['clientName'] as String;
      final String projectName = inspection['objectAddress'] as String; // Using objectAddress as project name for simplicity
      final String jobNumber = inspection['jobNumber'] as String;

      final List<Map<String, dynamic>> exportData = [];

      final inspectionDoors = await DatabaseService.getInspectionDoorsByInspectionId(inspectionId);
      expect(inspectionDoors.length, equals(3), reason: 'Should have 3 inspection doors');

      for (var junction in inspectionDoors) {
        final int doorId = junction['doorId'] as int;
        final Door? door = await DatabaseService.getDoorByAlias(junction['doorAlias'] ?? ''); // Assuming doorAlias is set in TestDataGenerator

        if (door == null) {
          fail('Door not found for junction ID: ${junction['id']}');
        }

        final List<Map<String, dynamic>> errorsForDoor = [];
        final inspectionDoorErrors = await DatabaseService.getErrorsForInspectionDoor(junction['id'] as int);

        for (var ide in inspectionDoorErrors) {
          final ErrorCatalog? errorCatalogEntry = await DatabaseService.getErrorCatalogItemById(ide.errorId!);
          if (errorCatalogEntry != null) {
            errorsForDoor.add({
              'code': errorCatalogEntry.code,
              'description': errorCatalogEntry.description,
            });
          }
        }
        
        // Only add doors that actually have errors, as per GAEB export service logic
        if (errorsForDoor.isNotEmpty) {
          exportData.add({
            'door': door,
            'errors': errorsForDoor,
          });
        }
      }
      
      // Ensure we have data to export
      expect(exportData.length, equals(3), reason: 'All 3 doors should have errors and be in exportData');

      // 3. Instantiate GaebExportService and export to X83
      final gaebService = GaebExportService(
        customer: clientName,
        projectName: projectName,
        jobNumber: jobNumber,
      );

      final File exportedFile = await gaebService.exportToXml(exportData);

      // 4. Assertions
      expect(await exportedFile.exists(), isTrue, reason: 'Exported X83 file should exist');

      final String fileContent = await exportedFile.readAsString();
      
      // Basic XML structure checks
      expect(fileContent, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(fileContent, contains('<GAEB xmlns="http://www.gaeb.de/GAEB_DA_XML/DA83/3.2">'));
      
      // Check Project Info
      final cleanJobNo = jobNumber.replaceAll(RegExp(r'[^0-9]'), '');
      final validJobNo = cleanJobNo.isEmpty ? "100" : cleanJobNo;
      expect(fileContent, contains('<NamePrj>$validJobNo</NamePrj>'));
      expect(fileContent, contains('<LblPrj>$clientName - $projectName</LblPrj>'));

      // Check for each door and its errors
      for (var entry in exportData) {
        final Door door = entry['door'] as Door;
        final List<Map<String, dynamic>> errors = entry['errors'] as List<Map<String, dynamic>>;

        // Check BoQCtgy for the door
        expect(fileContent, contains('ID="${door.doorAlias}"'), reason: 'BoQCtgy ID should be the door alias');
        expect(fileContent, contains('RNoPart="${door.doorNumber}"'), reason: 'Door number should be in BoQCtgy RNoPart');
        expect(fileContent, contains('<span style="font-weight:bold;">${door.doorNumber}</span>'), reason: 'Door number should be in LblTx without prefix');

        // Check each error item
        for (int i = 0; i < errors.length; i++) {
          final error = errors[i];
          final String errorCode = error['code'] as String;
          final String errorDescription = error['description'] as String;
          
          expect(fileContent, contains('ID="${door.doorAlias}_err$i"'), reason: 'Item ID should use door alias');
          expect(fileContent, contains('RNoPart="$errorCode"'), reason: 'Error code should be in Item RNoPart');
          expect(fileContent, contains('<p><span><span style="font-weight:bold;">$errorDescription</span></span></p>'), reason: 'Error description should be in DetailTxt');
          expect(fileContent, contains('<OutlTxt><TextOutlTxt><p><span>$errorDescription</span></p></TextOutlTxt></OutlTxt>'), reason: 'Error description should be in OutlineText');
        }
      }
    });
  });
}