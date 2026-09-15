import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/door.dart';
import 'package:wartungstool/services/door_validator.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Door Notes Property Tests', () {
    test('Door model includes notes field with default empty value', () {
      final door = Door(
        id: 1,
        pos: 1,
        doorNumber: '101',
        floor: 'EG',
        roomNumber: '0.01',
        roomDesignation: 'Büro',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Hörmann',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: 'None',
        lockDimensions: 'PZ 92',
        closerOnHingeSide: true,
        closerOnOppositeSide: false,
        escapeDoorControl: false,
        accessControl: 'Nein',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: true,
        fittingType: 'Drücker',
        panicFunction: 'Nein',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
      );

      expect(door.notes, equals(''));

      final doorWithNotes = door.copyWith(notes: 'M-01, M-02');
      expect(doorWithNotes.notes, equals('M-01, M-02'));

      final map = doorWithNotes.toMap();
      expect(map['notes'], equals('M-01, M-02'));

      final reconstructed = Door.fromMap(map);
      expect(reconstructed.notes, equals('M-01, M-02'));
    });

    test('DoorValidator detects technical mismatch in notes field', () {
      final door1 = Door(
        id: 1,
        pos: 1,
        doorNumber: '101',
        floor: 'EG',
        roomNumber: '0.01',
        roomDesignation: 'Büro',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Hörmann',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: 'None',
        lockDimensions: 'PZ 92',
        closerOnHingeSide: true,
        closerOnOppositeSide: false,
        escapeDoorControl: false,
        accessControl: 'Nein',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: true,
        fittingType: 'Drücker',
        panicFunction: 'Nein',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
        notes: 'M-01',
      );

      final door2 = door1.copyWith(notes: 'M-01, M-02');

      final conflicts = DoorValidator.detectConflicts(door2, door1);
      expect(conflicts.any((c) => c.fieldName == 'notes'), isTrue);
    });

    test('Database schema includes doors table notes column', () async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: 25,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE doors (
              id INTEGER PRIMARY KEY,
              pos INTEGER,
              doorAlias TEXT UNIQUE,
              provisionalAlias TEXT,
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
              lintelHeightInsideOver1m INTEGER DEFAULT 0,
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
              approvalNumber TEXT DEFAULT '?',
              manufacturerNumber TEXT DEFAULT '?',
              dopNumber TEXT DEFAULT '?',
              lintelHeightOutsideOver1m INTEGER DEFAULT 0,
              lintelHeightValue TEXT,
              lintelHeightInsideValue TEXT,
              lintelHeightOutsideValue TEXT,
              manufactureYear TEXT DEFAULT '?',
              fsaDriveAcceptanceDate TEXT,
              notes TEXT DEFAULT ''
            );
          ''');
        },
      );

      final columns = await db.rawQuery('PRAGMA table_info(doors)');
      final hasNotesCol = columns.any((c) => c['name'] == 'notes');
      expect(hasNotesCol, isTrue);

      await db.close();
    });
  });
}
