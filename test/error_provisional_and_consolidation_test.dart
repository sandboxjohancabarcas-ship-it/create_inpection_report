import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/error_catalog.dart';
import 'package:wartungstool/models/inspection_door_error.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/catalog_integrity_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final db = await DatabaseService.getDb();
    await db.delete('inspection_door_errors');
    await db.delete('inspection_doors');
    await db.delete('inspections');
    await db.delete('doors');
    await db.delete('error_catalog');

    // Seed official catalog entries
    await DatabaseService.insertErrorCatalog(ErrorCatalog(
      code: '1.1',
      description: 'Türblatt verzogen / schließt nicht',
      category: 'Türblatt/Zarge',
      severity: 'high',
      status: 'Approved',
    ));
    await DatabaseService.insertErrorCatalog(ErrorCatalog(
      code: '1.2',
      description: 'Dichtung beschädigt',
      category: 'Türblatt/Zarge',
      severity: 'medium',
      status: 'Approved',
    ));
    await DatabaseService.insertErrorCatalog(ErrorCatalog(
      code: '11.1',
      description: 'Rauchmelder verschmutzt',
      category: 'Feststellanlagen (FSA)',
      severity: 'medium',
      status: 'Approved',
    ));
  });

  group('Provisional Error & Integrity Validation Tests', () {
    test('Identifies collision and proposes next free code for category', () async {
      final officialCatalog = await DatabaseService.getAllErrorCatalog();

      // Check collision on existing 1.1
      final collision = CatalogIntegrityService.findCodeCollision('1.1', officialCatalog);
      expect(collision, isNotNull);
      expect(collision!.description, equals('Türblatt verzogen / schließt nicht'));

      // Check non-colliding new code
      final noCollision = CatalogIntegrityService.findCodeCollision('1.3', officialCatalog);
      expect(noCollision, isNull);

      // Propose next code for Türblatt/Zarge -> should be 1.3
      final nextCode = CatalogIntegrityService.proposeNextCodeForCategory('Türblatt/Zarge', officialCatalog);
      expect(nextCode, equals('1.3'));
    });

    test('Identifies description similarity to avoid duplicate defect creation', () async {
      final officialCatalog = await DatabaseService.getAllErrorCatalog();

      // Slightly rephrased description
      final similar = CatalogIntegrityService.findSimilarDescription(
        'Türblatt verzogen, schließt nicht richtig',
        officialCatalog,
        threshold: 0.70,
      );

      expect(similar, isNotNull);
      expect(similar!.existing.code, equals('1.1'));
      expect(similar.similarityPercentage, greaterThanOrEqualTo(70));
    });

    test('approveAndRemapPendingError updates linked door errors when code is updated', () async {
      final db = await DatabaseService.getDb();

      // 1. Insert a pending proposal
      await DatabaseService.insertErrorCatalog(ErrorCatalog(
        code: 'PROP-99',
        description: 'Bodenabschlussdichtung schleift',
        category: 'Türblatt/Zarge',
        severity: 'medium',
        status: 'Pending',
      ));

      final pendingList = await DatabaseService.getAllErrorCatalog(status: 'Pending');
      expect(pendingList.length, equals(1));
      final pendingItem = pendingList.first;

      // 2. Insert linked door error referencing PROP-99
      await db.insert('inspection_door_errors', {
        'inspectionDoorId': 100,
        'errorId': pendingItem.errorId ?? 999,
        'errorCode': 'PROP-99',
        'notes': 'Beim Kunden vor Ort festgestellt',
        'quantity': 1,
        'severity': 'medium',
      });

      // 3. Manager approves with standardized official code 1.3
      final approvedItem = pendingItem.copyWith(
        code: '1.3',
        status: 'Approved',
      );

      await DatabaseService.approveAndRemapPendingError(
        approvedItem,
        oldCode: 'PROP-99',
        oldErrorId: pendingItem.errorId,
      );

      // Verify catalog item status and code
      final updatedCatalog = await DatabaseService.getAllErrorCatalog();
      final approvedInCatalog = updatedCatalog.firstWhere((e) => e.code == '1.3');
      expect(approvedInCatalog.status, equals('Approved'));
      expect(approvedInCatalog.description, equals('Bodenabschlussdichtung schleift'));

      // Verify no pending proposals remain
      final remainingPending = await DatabaseService.getAllErrorCatalog(status: 'Pending');
      expect(remainingPending.isEmpty, isTrue);

      // Verify linked door error was remapped to 1.3
      final linkedErrors = await db.query('inspection_door_errors');
      expect(linkedErrors.length, equals(1));
      expect(linkedErrors.first['errorCode'], equals('1.3'));
      expect(linkedErrors.first['errorId'], equals(approvedInCatalog.errorId));
    });

    test('mergePendingErrorIntoExisting remaps door errors to official target and removes proposal', () async {
      final db = await DatabaseService.getDb();

      // 1. Insert pending proposal with duplicate intent
      await DatabaseService.insertErrorCatalog(ErrorCatalog(
        code: 'PROP-DUP',
        description: 'Türblatt verzogen',
        category: 'Türblatt/Zarge',
        severity: 'high',
        status: 'Pending',
      ));

      final pendingItem = (await DatabaseService.getAllErrorCatalog(status: 'Pending')).first;
      final targetOfficial = (await DatabaseService.getAllErrorCatalog()).firstWhere((e) => e.code == '1.1');

      // 2. Insert linked door error
      await db.insert('inspection_door_errors', {
        'inspectionDoorId': 101,
        'errorId': pendingItem.errorId ?? 888,
        'errorCode': 'PROP-DUP',
        'notes': 'Doppelter Eintrag vom Monteur',
        'quantity': 1,
        'severity': 'high',
      });

      // 3. Manager merges proposal into 1.1
      await DatabaseService.mergePendingErrorIntoExisting(
        pendingError: pendingItem,
        targetError: targetOfficial,
      );

      // Verify proposal is removed from catalog
      final pendingAfter = await DatabaseService.getAllErrorCatalog(status: 'Pending');
      expect(pendingAfter.isEmpty, isTrue);

      // Verify door error was remapped to target 1.1
      final linkedErrors = await db.query('inspection_door_errors');
      expect(linkedErrors.length, equals(1));
      expect(linkedErrors.first['errorCode'], equals('1.1'));
      expect(linkedErrors.first['errorId'], equals(targetOfficial.errorId));
    });
  });
}
