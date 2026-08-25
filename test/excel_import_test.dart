import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_data_importer.dart';
import 'package:wartungstool/services/local_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ExcelDataImporter Service Tests', () {
    setUp(() async {
      final db = await DatabaseService.getDb();
      await db.delete('inspections');
      await db.delete('doors');
      await db.delete('inspection_doors');
      await db.delete('inspection_door_errors');
      await db.delete('error_catalog');

      try {
        final localDb = await LocalDatabaseService.getDb();
        await localDb.delete('inspections');
        await localDb.delete('doors');
        await localDb.delete('inspection_doors');
        await localDb.delete('inspection_door_errors');
        await localDb.delete('error_catalog');
      } catch (_) {}
    });

    test('Door.generateAlias generates distinct aliases when floor differs for same doorNumber', () {
      final egAlias = Door.generateAlias('Stadt Geesthacht', 'Regenbogen', '1', floor: 'EG');
      final ogAlias = Door.generateAlias('Stadt Geesthacht', 'Regenbogen', '1', floor: '1.OG');

      expect(egAlias, isNot(equals(ogAlias)));
      expect(egAlias, contains('EG'));
      expect(ogAlias, contains('OG1'));
    });

    test('Inserting doors with same doorNumber on different floors preserves both records', () async {
      final egDoor = Door(
        id: null,
        pos: 1,
        doorAlias: Door.generateAlias('Client', 'Address', '1', floor: 'EG'),
        doorNumber: '1',
        floor: 'EG',
        roomNumber: '101',
        roomDesignation: 'Büro',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Dorma',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: '',
        lockDimensions: '',
        closerOnHingeSide: false,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: false,
        accessControl: '',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: false,
        fittingType: '',
        panicFunction: '',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
      );

      final ogDoor = Door(
        id: null,
        pos: 2,
        doorAlias: Door.generateAlias('Client', 'Address', '1', floor: '1.OG'),
        doorNumber: '1',
        floor: '1.OG',
        roomNumber: '201',
        roomDesignation: 'Büro',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Dorma',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: '',
        lockDimensions: '',
        closerOnHingeSide: false,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: false,
        accessControl: '',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: false,
        fittingType: '',
        panicFunction: '',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
      );

      await DatabaseService.insertDoor(egDoor);
      await DatabaseService.insertDoor(ogDoor);

      final allDoors = await DatabaseService.getAllDoors();
      expect(allDoors.length, equals(2), reason: 'Both EG and 1.OG doors should exist without overwriting');
    });

      final testDataDir = Directory(r'C:\Users\Cabarcas\WartungTool\create_inpection_report-1\test\test_data');

      // Convert xlsm files to xlsx in the test data directory
      if (testDataDir.existsSync()) {
        try {
          final xlsmFiles = testDataDir
              .listSync()
              .where((entity) {
                if (entity is! File) return false;
                final name = p.basename(entity.path);
                return name.endsWith('.xlsm') && !name.startsWith('~\$');
              })
              .cast<File>()
              .toList();
          for (final xlsmFile in xlsmFiles) {
            final xlsxPath = xlsmFile.path.substring(0, xlsmFile.path.length - 5) + '.xlsx';
            xlsmFile.copySync(xlsxPath);
            print('Converted test data file: ${xlsmFile.path} -> $xlsxPath');
          }
        } catch (e) {
          print('Error converting xlsm to xlsx test data files: $e');
        }
      }

      final filesToTest = testDataDir.existsSync()
          ? testDataDir
              .listSync()
              .where((entity) {
                if (entity is! File) return false;
                final name = p.basename(entity.path);
                return name.endsWith('.xlsx') && !name.startsWith('~\$');
              })
              .cast<File>()
              .toList()
          : <File>[];

    for (final file in filesToTest) {
      final filename = p.basename(file.path);

      test('importFromFile should parse doors and inspections correctly for $filename', () async {
        final bytes = await file.readAsBytes();
        final decoder = SpreadsheetDecoder.decodeBytes(bytes);
        final hasFehler = decoder.tables.containsKey('Fehlerübersicht');

        if (!hasFehler) {
          // Seed the database catalog table from default assets so mapping works
          await DatabaseService.checkAndInitializeCatalog();
        }

        final result = await ExcelDataImporter.importFromFile(file);

        expect(result.sheetsProcessed, greaterThanOrEqualTo(1));
        expect(result.doorsImported, greaterThan(0));

        if (!hasFehler) {
          expect(
            result.warnings.any((w) => w.contains('Fehlerübersicht')),
            isTrue,
            reason: 'Should log a warning when Fehlerübersicht is missing',
          );
        }

        if (result.warnings.isNotEmpty) {
          print('INFO: Warnings parsed for $filename:\n${result.warnings.join('\n')}');
        }

        final db = await DatabaseService.getDb();
        
        final expectedProjMatch = RegExp(r'(P-\d+)', caseSensitive: false).firstMatch(filename);
        final expectedProjectNumber = expectedProjMatch != null ? expectedProjMatch.group(1)!.toUpperCase() : '';
        final dbInspections = await db.query('inspections');
        expect(dbInspections, isNotEmpty);
        for (final insp in dbInspections) {
          expect(insp['projectNumber'], equals(expectedProjectNumber));
        }

        final inspectionsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inspections')) ?? 0;
        final doorsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM doors')) ?? 0;
        final junctionsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inspection_doors')) ?? 0;
        final errorsLinkedCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM inspection_door_errors')) ?? 0;

        print('======================================================================');
        print('MIGRATION REPORT FOR FILE: $filename');
        print('======================================================================');
        print('1. OVERALL METRICS:');
        print('   - Total inspections (sheets) processed: ${result.sheetsProcessed}');
        print('   - Total doors created/imported: ${result.doorsImported}');
        print('   - Total door errors linked: ${result.errorsLinked}');
        print('   - Total error catalog conflicts: ${result.catalogConflicts.length}');
        print('   - Total import warnings/mismatches: ${result.warnings.length}');
        print('----------------------------------------------------------------------');
        print('2. DETAILED MIGRATION PROTOCOL (RAW LOGS):');
        for (final logLine in result.logs) {
          print('   [LOG] $logLine');
        }
        print('----------------------------------------------------------------------');
        print('3. PER-INSPECTION (SHEET) BREAKDOWN:');
        
        // Parse sheet log statements to extract per-sheet numbers
        // E.g., Blatt "Türliste EG" abgeschlossen: 14 Türen importiert, 5 Mängel verknüpft.
        final sheetPattern = RegExp(r'Blatt "([^"]+)" abgeschlossen: (\d+) Türen importiert, (\d+) Mängel verknüpft\.');
        int sheetsFound = 0;
        for (final logLine in result.logs) {
          final match = sheetPattern.firstMatch(logLine);
          if (match != null) {
            sheetsFound++;
            final sheetName = match.group(1)!;
            final sheetDoors = int.parse(match.group(2)!);
            final sheetErrors = int.parse(match.group(3)!);
            
            // Associate warnings to this sheet by checking if the warning contains the sheet name
            final sheetWarnings = result.warnings.where((w) => w.contains(sheetName) || w.contains('"$sheetName"')).toList();
            
            print('   - Inspection Worksheet "$sheetName":');
            print('     * Doors created: $sheetDoors');
            print('     * Defects linked: $sheetErrors');
            print('     * Warnings/Mismatches: ${sheetWarnings.length}');
            for (final warn in sheetWarnings) {
              print('       -> Warning: $warn');
            }
          }
        }
        if (sheetsFound == 0) {
          print('   - No worksheets successfully parsed.');
        }
        print('----------------------------------------------------------------------');
        print('4. ERROR CATALOG ANALYSIS & MISMATCHES:');
        final catalogLogs = result.logs.where((l) => l.contains('Fehlerkatalog') || l.contains('KATALOGKONFLIKTE'));
        for (final clog in catalogLogs) {
          print('   [Catalog] $clog');
        }
        if (result.catalogConflicts.isNotEmpty) {
          print('   Catalog Conflicts Detailed:');
          for (final conf in result.catalogConflicts) {
            print('     * Code: ${conf.code}');
            print('       - Reason: ${conf.reason}');
            print('       - Excel Description: ${conf.incoming.description}');
            print('       - DB Description: ${conf.existing?.description ?? "N/A"}');
          }
        } else {
          print('   No catalog conflicts found.');
        }
        print('----------------------------------------------------------------------');
        print('5. DOOR CONFLICTS FOR REVIEW:');
        if (result.doorConflicts.isNotEmpty) {
          print('   Door Conflicts Detailed (${result.doorConflicts.length} conflicts):');
          for (final dc in result.doorConflicts) {
            print('     * Door Number: ${dc.incomingDoor.doorNumber} (Floor: ${dc.incomingDoor.floor})');
            print('       - Type: ${dc.type.label}');
            print('       - Message: ${dc.message}');
          }
        } else {
          print('   No door conflicts detected.');
        }
        print('======================================================================\n');

        expect(inspectionsCount, equals(result.sheetsProcessed));
        expect(doorsCount, lessThanOrEqualTo(result.doorsImported));
        expect(junctionsCount, equals(result.doorsImported));
        expect(errorsLinkedCount, equals(result.errorsLinked));

        // Verify that all linked errors have non-empty errorCode natural keys in Master DB
        final masterErrorRows = await db.query('inspection_door_errors');
        for (final row in masterErrorRows) {
          final code = row['errorCode'] as String? ?? '';
          expect(code.isNotEmpty, isTrue, reason: 'All imported errors must have a populated errorCode natural key');
        }

        // Verify cross-database transfer via job package download to LocalDatabaseService
        final inspections = await db.query('inspections');
        final inspectionIds = inspections.map((r) => r['inspectionId'] as int).toList();

        await LocalDatabaseService.downloadJobPackage(inspectionIds: inspectionIds);

        final localDb = await LocalDatabaseService.getDb();
        final localInspectionsCount = Sqflite.firstIntValue(await localDb.rawQuery('SELECT COUNT(*) FROM inspections')) ?? 0;
        final localDoorsCount = Sqflite.firstIntValue(await localDb.rawQuery('SELECT COUNT(*) FROM doors')) ?? 0;
        final localJunctionsCount = Sqflite.firstIntValue(await localDb.rawQuery('SELECT COUNT(*) FROM inspection_doors')) ?? 0;
        final localErrorCount = Sqflite.firstIntValue(await localDb.rawQuery('SELECT COUNT(*) FROM inspection_door_errors')) ?? 0;

        print('Local DB inspectionsCount: $localInspectionsCount');
        print('Local DB doorsCount: $localDoorsCount');
        print('Local DB junctionsCount: $localJunctionsCount');
        print('Local DB localErrorCount: $localErrorCount');

        expect(localInspectionsCount, equals(inspectionsCount));
        expect(localDoorsCount, equals(doorsCount));
        expect(localJunctionsCount, equals(junctionsCount));
        expect(localErrorCount, equals(result.errorsLinked), reason: 'Local DB should receive all errors via job package download');

        final localErrorRows = await localDb.query('inspection_door_errors');
        for (final row in localErrorRows) {
          final code = row['errorCode'] as String? ?? '';
          expect(code.isNotEmpty, isTrue, reason: 'Local DB errors must retain valid errorCode natural keys');
        }
      });
    }

    test('searchInspections matches inspections by doorAlias', () async {
      final doorId = await DatabaseService.insertDoor(Door(
        id: null,
        pos: 1,
        doorAlias: 'SPRIN-BIL40-UG-45',
        doorNumber: '45',
        floor: 'UG',
        roomNumber: '001',
        roomDesignation: 'Keller',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Dorma',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: '',
        lockDimensions: '',
        closerOnHingeSide: false,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: false,
        accessControl: '',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: false,
        fittingType: '',
        panicFunction: '',
        escapeDirectionRespected: false,
        fullPanicStandWing: false,
        doorFunctionOK: true,
      ));

      final inspId = await DatabaseService.insertInspection({
        'clientName': 'Sprinkenhof',
        'objectAddress': 'Billstraße 40',
        'date': '2025-05-10',
        'jobNumber': '25-999-AB',
      });

      await DatabaseService.insertInspectionDoor({
        'inspectionId': inspId,
        'doorId': doorId,
        'status': 'Passed',
        'notes': 'Test',
      });

      final results = await DatabaseService.searchInspections('SPRIN-BIL40-UG-45');
      expect(results.length, equals(1));
      expect(results.first['inspectionId'], equals(inspId));
    });

    test('_sanitizeDoorNumber filters out summary and footer text', () {
      final sanitized = ExcelDataImporter.sanitizeDoorNumberForTest('Gesamtzahl Türen: 45');
      expect(sanitized.startsWith('TÜR-'), isTrue);
    });
  });
}
