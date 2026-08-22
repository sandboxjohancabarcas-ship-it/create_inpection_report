import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/models/models.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.current.path;
  }
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.current.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('InspectionDoorError Serialization and Database tests', () {
    test('toMap and fromMap should correctly serialize/deserialize attachments', () {
      final error = InspectionDoorError(
        inspectionDoorId: 1,
        errorId: 5,
        quantity: 1,
        severity: 'medium',
        notes: 'Test notes',
        resolutionStatus: 'Open',
        attachments: 'base64str1,base64str2',
      );

      final map = error.toMap();
      expect(map['attachments'], 'base64str1,base64str2');

      final deserialized = InspectionDoorError.fromMap(map);
      expect(deserialized.attachments, 'base64str1,base64str2');
    });

    test('copyWith should correctly copy attachments', () {
      final error = InspectionDoorError(
        inspectionDoorId: 1,
        quantity: 1,
        severity: 'medium',
        notes: 'Test notes',
        attachments: 'base64str1',
      );

      final copied = error.copyWith(attachments: 'base64str2');
      expect(copied.attachments, 'base64str2');
      expect(copied.notes, 'Test notes');
    });

    test('should save and retrieve attachments in database', () async {
      final db = await LocalDatabaseService.getDb();
      await db.delete('inspection_door_errors');

      final error = InspectionDoorError(
        id: 999,
        inspectionDoorId: 123,
        errorId: 5,
        quantity: 1,
        severity: 'medium',
        notes: 'Test notes with photo',
        resolutionStatus: 'Open',
        attachments: 'photo1_base64_data,photo2_base64_data',
      );

      await LocalDatabaseService.insertInspectionDoorError(error);

      final loadedErrors = await LocalDatabaseService.getErrorsForInspectionDoor(123);
      expect(loadedErrors.length, 1);
      expect(loadedErrors.first.attachments, 'photo1_base64_data,photo2_base64_data');
    });

    test('should save and retrieve large attachments (3MB) using chunked reading without crashing', () async {
      final db = await LocalDatabaseService.getDb();
      await db.delete('inspection_door_errors');

      // Generate a 3MB string
      final String largeString = 'A' * 3 * 1024 * 1024;

      final error = InspectionDoorError(
        id: 1000,
        inspectionDoorId: 456,
        errorId: 5,
        quantity: 1,
        severity: 'medium',
        notes: 'Test notes with large photo',
        resolutionStatus: 'Open',
        attachments: largeString,
      );

      await LocalDatabaseService.insertInspectionDoorError(error);

      // Verify chunked retrieval works and matches the source string exactly
      final loadedErrors = await LocalDatabaseService.getErrorsForInspectionDoor(456);
      expect(loadedErrors.length, 1);
      expect(loadedErrors.first.attachments.length, largeString.length);
      expect(loadedErrors.first.attachments, largeString);
    });
  });
}
