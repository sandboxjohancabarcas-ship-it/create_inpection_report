import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/utils/error_log_export_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Legacy Schema Import & Error Diagnostics Tests', () {
    late Directory tempDir;
    late String legacyPackagePath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wartungstool_legacy_test_');
      legacyPackagePath = p.join(tempDir.path, 'legacy_export.db');

      // 1. Create a simulated legacy exported DB with `lintelHeightUnder1m` column in `doors`
      final legacyDb = await openDatabase(
        legacyPackagePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE doors (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              pos INTEGER,
              doorAlias TEXT UNIQUE,
              doorNumber TEXT,
              floor TEXT,
              roomNumber TEXT,
              roomDesignation TEXT,
              doorType TEXT,
              wingCount INTEGER,
              material TEXT,
              manufacturer TEXT,
              dinConfiguration TEXT,
              closerType TEXT,
              closingSequenceSystem TEXT,
              lockDimensions TEXT,
              closerOnHingeSide INTEGER,
              closerOnOppositeSide INTEGER,
              lintelHeightUnder1m INTEGER DEFAULT 1,
              escapeDoorControl INTEGER,
              accessControl TEXT,
              escapeRouteSituation INTEGER,
              escapeRouteSignage INTEGER,
              blindCylinder INTEGER,
              pzCylinder INTEGER,
              fittingType TEXT,
              panicFunction TEXT,
              escapeDirectionRespected INTEGER,
              fullPanicStandWing INTEGER,
              doorFunctionOK INTEGER,
              notes TEXT
            );
          ''');

          await db.execute('''
            CREATE TABLE inspections (
              inspectionId INTEGER PRIMARY KEY AUTOINCREMENT,
              clientName TEXT,
              objectAddress TEXT,
              date TEXT,
              contactPerson TEXT,
              inspectorName TEXT,
              jobNumber TEXT
            );
          ''');

          await db.execute('''
            CREATE TABLE inspection_doors (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              inspectionId INTEGER,
              doorId INTEGER,
              status TEXT,
              notes TEXT
            );
          ''');

          await db.execute('''
            CREATE TABLE inspection_door_errors (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              inspectionDoorId INTEGER,
              errorId INTEGER,
              errorCode TEXT,
              quantity INTEGER,
              severity TEXT,
              notes TEXT,
              resolutionStatus TEXT
            );
          ''');

          await db.execute('''
            CREATE TABLE error_catalog (
              errorId INTEGER PRIMARY KEY AUTOINCREMENT,
              code TEXT UNIQUE,
              description TEXT,
              category TEXT,
              severity TEXT,
              status TEXT
            );
          ''');

          // Seed test data in legacy DB
          await db.insert('doors', {
            'pos': 1,
            'doorAlias': 'LEGACY-001',
            'doorNumber': 'T-101',
            'floor': 'OG1',
            'roomNumber': '101',
            'roomDesignation': 'Büro',
            'doorType': 'T30',
            'wingCount': 1,
            'material': 'Stahl',
            'manufacturer': 'Dorma',
            'dinConfiguration': 'DIN L',
            'closerType': 'TS93',
            'closingSequenceSystem': 'Keine',
            'lockDimensions': '30/92/9-20 U',
            'closerOnHingeSide': 1,
            'closerOnOppositeSide': 0,
            'lintelHeightUnder1m': 1, // Legacy column that was causing the crash!
            'escapeDoorControl': 0,
            'accessControl': 'Nein',
            'escapeRouteSituation': 1,
            'escapeRouteSignage': 1,
            'blindCylinder': 0,
            'pzCylinder': 1,
            'fittingType': 'Drücker',
            'panicFunction': 'Keine',
            'escapeDirectionRespected': 1,
            'fullPanicStandWing': 0,
            'doorFunctionOK': 1,
            'notes': 'Test-Tür mit Altschema',
          });

          await db.insert('inspections', {
            'clientName': 'Musterkunde',
            'objectAddress': 'Musterstr. 1',
            'date': '2026-09-26',
            'contactPerson': 'Herr Test',
            'inspectorName': 'Prüfer Lenovo',
            'jobNumber': 'AUF-9999',
          });

          await db.insert('inspection_doors', {
            'inspectionId': 1,
            'doorId': 1,
            'status': 'InProgress',
            'notes': 'Prüfung läuft',
          });

          await db.insert('error_catalog', {
            'code': 'T01',
            'description': 'Schließkraft unzureichend',
            'category': 'Türschließer',
            'severity': 'medium',
            'status': 'Approved',
          });

          await db.insert('inspection_door_errors', {
            'inspectionDoorId': 1,
            'errorId': 1,
            'errorCode': 'T01',
            'quantity': 1,
            'severity': 'medium',
            'notes': 'Tür schließt schwer',
            'resolutionStatus': 'Offen',
          });
        },
      );
      await legacyDb.close();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Compatibility check detects legacy columns in exported package', () async {
      final compat = await ErrorLogExportHelper.checkPackageCompatibility(legacyPackagePath);
      expect(compat.hasVersionMismatch, isTrue);
      expect(compat.legacyColumns.any((c) => c.contains('lintelHeightUnder1m')), isTrue);
    });

    test('importAndMergePackage safely imports legacy package without SQL column crash', () async {
      // Ensure master database is initialized
      await DatabaseService.getDb();

      // Attempt to import the package that has `lintelHeightUnder1m`
      final report = await DatabaseService.importAndMergePackage(legacyPackagePath);

      expect(report.newDoorsCount + report.updatedDoorsCount, greaterThan(0));
      expect(report.totalErrorsImported, equals(1));

      // Verify the door was correctly inserted/mapped into Master DB
      final masterDb = await DatabaseService.getDb();
      final importedDoorRows = await masterDb.query(
        'doors',
        where: 'doorAlias = ?',
        whereArgs: ['LEGACY-001'],
      );
      expect(importedDoorRows, isNotEmpty);
      expect(importedDoorRows.first['doorNumber'], equals('T-101'));
      // Verify legacy lintel height was converted safely to lintelHeightInsideOver1m
      expect(importedDoorRows.first['lintelHeightInsideOver1m'], equals(1));
    });

    test('ErrorLogExportHelper generates structured developer text report', () async {
      final report = await ErrorLogExportHelper.generateErrorReport(
        error: const FormatException('Simulierter Formatfehler für Testbericht'),
        stackTrace: StackTrace.current,
        packagePath: legacyPackagePath,
        operation: 'Test Merge Operation',
      );

      expect(report, contains('WARTUNGSTOOL - DIAGNOSE & FEHLERBERICHT'));
      expect(report, contains('Simulierter Formatfehler für Testbericht'));
      expect(report, contains('doors'));
      expect(report, contains('lintelHeightUnder1m'));
      expect(report, contains('STACK TRACE'));
    });
  });
}
