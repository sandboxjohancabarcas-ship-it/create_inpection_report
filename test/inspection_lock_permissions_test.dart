import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/utils/inspection_year_utils.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Inspection Lock & Permissions System Tests', () {
    test('InspectionYearUtils.isEditable respects manager mode and lock status', () {
      // Manager mode: always editable regardless of lock status or date
      expect(InspectionYearUtils.isEditable(isManagerMode: true, isLocked: true), isTrue);
      expect(InspectionYearUtils.isEditable(isManagerMode: true, isLocked: false), isTrue);

      // Inspector mode: editable only when unlocked (isLocked == false / 0), including previous years (e.g. 2021)
      expect(InspectionYearUtils.isEditable(isManagerMode: false, isLocked: false, dateValue: '2021-05-15'), isTrue);
      expect(InspectionYearUtils.isEditable(isManagerMode: false, isLocked: 0, dateValue: '2021-05-15'), isTrue);
      expect(InspectionYearUtils.isInspectionLocked(0, '2021-05-15'), isFalse);

      // Inspector mode: locked inspection is read-only
      expect(InspectionYearUtils.isEditable(isManagerMode: false, isLocked: true, dateValue: '2021-05-15'), isFalse);
      expect(InspectionYearUtils.isEditable(isManagerMode: false, isLocked: 1, dateValue: '2021-05-15'), isFalse);
      expect(InspectionYearUtils.isInspectionLocked(1, '2021-05-15'), isTrue);
    });

    test('Inspection metadata is strictly uneditable for inspectors', () {
      expect(InspectionYearUtils.isMetadataEditable(isManagerMode: true), isTrue);
      expect(InspectionYearUtils.isMetadataEditable(isManagerMode: false), isFalse);
    });

    test('isInspectionLocked helper identifies locked state correctly', () {
      expect(InspectionYearUtils.isInspectionLocked(true), isTrue);
      expect(InspectionYearUtils.isInspectionLocked(1), isTrue);
      expect(InspectionYearUtils.isInspectionLocked(false), isFalse);
      expect(InspectionYearUtils.isInspectionLocked(0), isFalse);
    });

    test('Database schema includes isLocked column', () async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: 26,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE inspections (
              inspectionId INTEGER PRIMARY KEY AUTOINCREMENT,
              clientName TEXT,
              objectAddress TEXT,
              date TEXT,
              contactPerson TEXT,
              inspectorName TEXT,
              jobNumber TEXT,
              projectNumber TEXT,
              isLocked INTEGER DEFAULT 0
            );
          ''');
        },
      );

      final columns = await db.rawQuery('PRAGMA table_info(inspections)');
      final hasLockCol = columns.any((c) => c['name'] == 'isLocked');
      expect(hasLockCol, isTrue);

      await db.insert('inspections', {
        'clientName': 'Test Client',
        'jobNumber': 'P-100',
        'date': '2026-09-15',
        'isLocked': 0,
      });

      final rows = await db.query('inspections', where: 'jobNumber = ?', whereArgs: ['P-100']);
      expect(rows.first['isLocked'], equals(0));

      await db.update('inspections', {'isLocked': 1}, where: 'jobNumber = ?', whereArgs: ['P-100']);
      final updatedRows = await db.query('inspections', where: 'jobNumber = ?', whereArgs: ['P-100']);
      expect(updatedRows.first['isLocked'], equals(1));

      await db.close();
    });
  });
}
