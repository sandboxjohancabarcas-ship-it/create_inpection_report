import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/local_database_service.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

/// Helper replicating DoorInspectionForm._isErrorDerivedLine and notes consolidation logic
bool isErrorDerivedLine(String line, List<ErrorCatalog> allCatalog, List<String> currentFormattedEntries) {
  if (line.isEmpty) return false;
  if (currentFormattedEntries.any((entry) => entry == line || entry.startsWith(line) || line.startsWith(entry))) {
    return true;
  }
  if (line.startsWith('M-') || line.startsWith('ERR_') || line.startsWith('PROP-') || line.startsWith('ALT-')) {
    return true;
  }
  final cleanLine = line.toLowerCase();
  for (final cat in allCatalog) {
    final desc = cat.description.trim().toLowerCase();
    final code = cat.code.trim().toLowerCase();
    if (desc.isNotEmpty) {
      if (cleanLine == desc ||
          cleanLine.startsWith('$desc:') ||
          cleanLine.startsWith('$desc -') ||
          cleanLine.startsWith('$desc,') ||
          cleanLine.startsWith('$desc ')) {
        return true;
      }
    }
    if (code.isNotEmpty) {
      if (cleanLine == code ||
          cleanLine.startsWith('$code:') ||
          cleanLine.startsWith('$code -') ||
          cleanLine.startsWith('$code ')) {
        return true;
      }
    }
  }
  return false;
}

String reconcileNotes({
  required String currentNotes,
  required List<ErrorCatalog> allCatalog,
  required List<Map<String, dynamic>> errors,
}) {
  final List<String> formattedEntries = [];
  for (final e in errors) {
    final desc = (e['description'] ?? e['code'] ?? e['errorCode'] ?? '').toString().trim();
    final note = (e['notes'] ?? '').toString().trim();
    if (desc.isNotEmpty && note.isNotEmpty) {
      formattedEntries.add('$desc: $note');
    } else if (desc.isNotEmpty) {
      formattedEntries.add(desc);
    } else if (note.isNotEmpty) {
      formattedEntries.add(note);
    }
  }

  final existingLines = currentNotes
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final List<String> manualNotes = [];

  for (final line in existingLines) {
    if (!isErrorDerivedLine(line, allCatalog, formattedEntries)) {
      manualNotes.add(line);
    }
  }

  final List<String> consolidated = [];
  if (manualNotes.isNotEmpty) {
    consolidated.addAll(manualNotes);
  }
  if (formattedEntries.isNotEmpty) {
    consolidated.addAll(formattedEntries);
  }

  return consolidated.join('\n').trim();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final db = await LocalDatabaseService.getDb();
    await db.delete('inspection_door_errors');
    await db.delete('inspection_doors');
    await db.delete('inspections');
    await db.delete('doors');
    await db.delete('error_catalog');

    // Seed catalog
    await LocalDatabaseService.insertErrorCatalogItems([
      ErrorCatalog(
        code: '1.1',
        description: 'Türblatt verzogen / schließt nicht',
        category: 'Türblatt/Zarge',
        severity: 'high',
        status: 'Approved',
      ),
      ErrorCatalog(
        code: '1.2',
        description: 'Dichtung beschädigt',
        category: 'Türblatt/Zarge',
        severity: 'medium',
        status: 'Approved',
      ),
    ]);
  });

  group('Door Notes and Error Lifecycle Integrity Tests', () {
    test('Door notes correctly update on error create and delete while preserving manual notes', () async {
      final db = await LocalDatabaseService.getDb();
      final allCatalog = await LocalDatabaseService.getAllErrorCatalog();

      // 1. Create an inspection and a door with manual notes
      final inspId = await db.insert('inspections', {
        'clientName': 'Testkunde',
        'objectAddress': 'Teststraße 1',
        'date': DateTime.now().toIso8601String(),
        'jobNumber': 'JOB-01',
      });

      final initialNotes = 'Manueller Hinweis: Schlüssel beim Hausmeister\nZusatz: Vor Ort prüfen';
      final doorId = await db.insert('doors', {
        'doorNumber': 'T-101',
        'doorAlias': 'ALIAS-101',
        'floor': 'EG',
        'roomDesignation': 'Haupteingang',
        'roomNumber': '101',
        'notes': initialNotes,
      });

      final inspDoorId = await db.insert('inspection_doors', {
        'inspectionId': inspId,
        'doorId': doorId,
        'status': 'Pending',
        'notes': initialNotes,
      });

      // 2. Add two errors to the door
      final err1Id = await LocalDatabaseService.insertInspectionDoorError(InspectionDoorError(
        inspectionDoorId: inspDoorId,
        errorId: allCatalog[0].errorId ?? 1,
        errorCode: allCatalog[0].code,
        notes: 'klemmt oben rechts',
        quantity: 1,
        severity: 'high',
      ));

      final err2Id = await LocalDatabaseService.insertInspectionDoorError(InspectionDoorError(
        inspectionDoorId: inspDoorId,
        errorId: allCatalog[1].errorId ?? 2,
        errorCode: allCatalog[1].code,
        notes: 'eingerissen an Bandseite',
        quantity: 1,
        severity: 'medium',
      ));

      // 3. Reconcile notes with 2 errors present
      var activeErrors = await LocalDatabaseService.getDetailedErrorsForInspectionDoor(inspDoorId);
      var syncedNotes = reconcileNotes(
        currentNotes: initialNotes,
        allCatalog: allCatalog,
        errors: activeErrors,
      );

      expect(syncedNotes, contains('Manueller Hinweis: Schlüssel beim Hausmeister'));
      expect(syncedNotes, contains('Zusatz: Vor Ort prüfen'));
      expect(syncedNotes, contains('Türblatt verzogen / schließt nicht: klemmt oben rechts'));
      expect(syncedNotes, contains('Dichtung beschädigt: eingerissen an Bandseite'));

      // Save to database
      var doorRow = (await db.query('doors', where: 'id = ?', whereArgs: [doorId])).first;
      var doorObj = Door.fromMap(doorRow).copyWith(notes: syncedNotes);
      await LocalDatabaseService.updateDoor(doorObj);

      // 4. Now DELETE Error 2 ('1.2 Dichtung beschädigt')
      await LocalDatabaseService.deleteInspectionDoorError(err2Id);

      // 5. Reconcile notes after deletion
      activeErrors = await LocalDatabaseService.getDetailedErrorsForInspectionDoor(inspDoorId);
      final reconciledAfterDelete = reconcileNotes(
        currentNotes: syncedNotes,
        allCatalog: allCatalog,
        errors: activeErrors,
      );

      // Verify Error 2 note is REMOVED, Error 1 note is KEPT, and manual notes are KEPT
      expect(reconciledAfterDelete, contains('Manueller Hinweis: Schlüssel beim Hausmeister'));
      expect(reconciledAfterDelete, contains('Zusatz: Vor Ort prüfen'));
      expect(reconciledAfterDelete, contains('Türblatt verzogen / schließt nicht: klemmt oben rechts'));
      expect(reconciledAfterDelete.contains('Dichtung beschädigt'), isFalse);
      expect(reconciledAfterDelete.contains('eingerissen an Bandseite'), isFalse);

      // Persist update and verify DB consistency
      doorObj = doorObj.copyWith(notes: reconciledAfterDelete);
      await LocalDatabaseService.updateDoor(doorObj);
      
      final updatedDoorRow = (await db.query('doors', where: 'id = ?', whereArgs: [doorId])).first;
      final updatedDoor = Door.fromMap(updatedDoorRow);
      expect(updatedDoor.notes, equals(reconciledAfterDelete));
      expect(updatedDoor.notes!.contains('Dichtung beschädigt'), isFalse);
      expect(updatedDoor.notes!.contains('Manueller Hinweis'), isTrue);
    });
  });
}
