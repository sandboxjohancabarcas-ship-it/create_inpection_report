import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Database Schema Version & SSOT Consistency Tests', () {
    test('Master DB canonical version constant matches active schema migration version', () {
      expect(DatabaseService.currentDatabaseVersion, equals(29),
          reason: 'Master DB schema version must be 29 (v29 includes Windows tables)');
    });

    test('Local DB canonical version constant matches active schema migration version', () {
      expect(LocalDatabaseService.currentDatabaseVersion, equals(19),
          reason: 'Local DB schema version must be 19 (v19 includes Windows tables)');
    });

    test('Master DB PRAGMA user_version matches currentDatabaseVersion on getDb()', () async {
      final db = await DatabaseService.getDb();
      final rows = await db.rawQuery('PRAGMA user_version');
      final userVersion = rows.first.values.first as int;
      expect(userVersion, equals(DatabaseService.currentDatabaseVersion));
    });

    test('Local DB PRAGMA user_version matches currentDatabaseVersion on getDb()', () async {
      final db = await LocalDatabaseService.getDb();
      final rows = await db.rawQuery('PRAGMA user_version');
      final userVersion = rows.first.values.first as int;
      expect(userVersion, equals(LocalDatabaseService.currentDatabaseVersion));
    });
  });
}
