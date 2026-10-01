import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/import_report.dart';
import 'package:wartungstool/services/batch_migration_service.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Legacy Database Compatibility & Migration Audit Tests', () {
    late String legacyFixturePath;

    setUp(() async {
      await DatabaseService.getDb();
      await LocalDatabaseService.getDb();

      final testDataDir = Directory('test/test_data');
      final files = testDataDir.listSync().whereType<File>();
      final fixtureFile = files.firstWhere(
        (f) => f.path.endsWith('.db') && f.path.contains('Hammerbrook'),
        orElse: () => files.firstWhere((f) => f.path.endsWith('.db') && !f.path.endsWith('test.db')),
      );
      legacyFixturePath = fixtureFile.absolute.path;
    });

    test('Fixture file exists and is valid SQLite database with schema v16', () async {
      final file = File(legacyFixturePath);
      expect(file.existsSync(), isTrue, reason: 'Legacy fixture db file must exist');

      final db = await openDatabase(file.absolute.path, readOnly: true);
      final verRes = await db.rawQuery('PRAGMA user_version');
      final version = verRes.first.values.first as int;
      expect(version, equals(16));

      final doors = await db.query('doors');
      expect(doors.length, equals(71));

      final inspections = await db.query('inspections');
      expect(inspections.length, equals(1));
      
      final tableInfo = await db.rawQuery('PRAGMA table_info(inspections)');
      final columnNames = tableInfo.map((r) => r['name'] as String).toSet();
      expect(columnNames.contains('orderType'), isFalse);
      expect(columnNames.contains('repairDate'), isFalse);

      await db.close();
    });

    test('Master DB importAndMergePackage imports legacy fixture, preserves Wartung orderType, and generates LegacyMigrationAudit', () async {
      final report = await DatabaseService.importAndMergePackage(legacyFixturePath);

      expect(report.totalDoorsProcessed, equals(71));
      expect(report.totalErrorsImported, equals(17));
      expect(report.hasLegacyAudit, isTrue);

      final audit = report.legacyAudit;
      expect(audit, isNotNull);
      expect(audit!.packageVersion, equals(16));
      expect(audit.targetVersion, equals(27));
      expect(audit.jobNumber.isNotEmpty, isTrue);
      expect(audit.defaultOrderType, equals('Wartung'));
      expect(audit.newFeatures.isNotEmpty, isTrue);
      expect(audit.convertedProperties.isNotEmpty, isTrue);
      expect(audit.placeholderDoorProperties.isNotEmpty, isTrue);
      expect(audit.placeholderSampleDoors.isNotEmpty, isTrue);
      expect(audit.managerActionHints.isNotEmpty, isTrue);

      // Verify the generated report text contains all essential sections
      final text = audit.generateFormattedReportText();
      expect(text, contains('ALTDATEN-KOMPATIBILITÄTS- & MIGRATIONSBERICHT'));
      expect(text, contains('v16 (Legacy) ➔ Ziel-Version: v27 (Aktuell)'));
      expect(text, contains('Auftrag: ${audit.jobNumber}'));
      expect(text, contains('Standard-Auftragsphase: Wartung'));
      expect(text, contains('1. NEUE FUNKTIONEN DER AKTUELLEN VERSION'));
      expect(text, contains('2. DURCHGEFÜHRTE ATTRIBUT-KONVERTIERUNGEN & WHITELISTING'));
      expect(text, contains('3. ZUR MANUELLEN PRÜFUNG / ERGÄNZUNG DURCH DEN MANAGER'));
      expect(text, contains('4. HANDLUNGSEMPFEHLUNGEN FÜR DEN MANAGER'));

      // Verify inspections in Master DB preserved orderType = 'Wartung' (not forced to 'Erledigt')
      final masterDb = await DatabaseService.getDb();
      final masterInspections = await masterDb.query('inspections', where: 'jobNumber = ?', whereArgs: [audit.jobNumber]);
      expect(masterInspections.length, equals(1));
      expect(masterInspections.first['orderType'], equals('Wartung'));
    });

    test('LocalDatabaseService imports legacy package, sets Wartung, and attaches LegacyMigrationAudit', () async {
      final report = await LocalDatabaseService.importAndMergePackage(legacyFixturePath);

      expect(report.totalDoorsProcessed, equals(71));
      expect(report.totalErrorsImported, equals(17));
      expect(report.hasLegacyAudit, isTrue);
      expect(report.legacyAudit!.packageVersion, equals(16));
      expect(report.legacyAudit!.targetVersion, equals(17));

      final localDb = await LocalDatabaseService.getDb();
      final localInspections = await localDb.query('inspections', where: 'jobNumber = ?', whereArgs: [report.legacyAudit!.jobNumber]);
      expect(localInspections.length, equals(1));
      expect(localInspections.first['orderType'], equals('Wartung'));
    });

    test('BatchMigrationService aggregates legacy audits correctly across file list', () async {
      final batchResult = await BatchMigrationService.migrateFiles([File(legacyFixturePath)]);

      expect(batchResult.compliantFilesProcessed, equals(1));
      expect(batchResult.aggregatedReport.hasLegacyAudit, isTrue);
      expect(batchResult.aggregatedReport.legacyAudits.length, equals(1));
      expect(batchResult.aggregatedReport.legacyAudits.first.jobNumber.isNotEmpty, isTrue);
      expect(batchResult.aggregatedReport.totalDoorsProcessed, equals(71));
    });
  });
}
