import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/craftnote_models.dart';
import 'package:wartungstool/services/craftnote_api_service.dart';
import 'package:wartungstool/services/craftnote_credentials_service.dart';
import 'package:wartungstool/services/craftnote_sync_service.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir = Directory.systemTemp.createTempSync('cn_sync_test_');

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;

  @override
  Future<String?> getDownloadsPath() async => tempDir.path;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = MockPathProviderPlatform();
  });

  group('CraftnoteSyncService Unit Tests', () {
    late CraftnoteSyncService syncService;

    setUp(() async {
      CraftnoteCredentialsService.resetToDefaults();
      CraftnoteCredentialsService.setMockMode(true);

      // Clean local and main tables
      final localDb = await LocalDatabaseService.getDb();
      await localDb.delete('doors');
      await localDb.delete('inspections');
      await localDb.delete('inspection_doors');
      await localDb.delete('inspection_door_errors');
      await localDb.delete('craftnote_upload_queue');

      final mainDb = await DatabaseService.getDb();
      await mainDb.delete('doors');
      await mainDb.delete('inspections');
      await mainDb.delete('inspection_doors');
      await mainDb.delete('inspection_door_errors');

      syncService = CraftnoteSyncService(
        apiService: CraftnoteApiService(),
      );
    });

    test('hasInternetConnection respects override and mock mode', () async {
      // In mock mode it should default to true
      expect(await syncService.hasInternetConnection(), isTrue);

      // Explicit offline override
      syncService.overrideOnlineStatus = false;
      expect(await syncService.hasInternetConnection(), isFalse);

      // Explicit online override
      syncService.overrideOnlineStatus = true;
      expect(await syncService.hasInternetConnection(), isTrue);
    });

    test('completeAndUploadFromLocalDb enqueues task into offline queue when device is offline', () async {
      syncService.overrideOnlineStatus = false;

      // 1. Insert local door & inspection with linked Craftnote project
      final localDb = await LocalDatabaseService.getDb();
      await localDb.insert('doors', {
        'id': 101,
        'doorAlias': 'OFFLINE-DOOR-01',
        'doorNumber': 'T-101',
        'floor': 'EG',
        'roomDesignation': 'Haupteingang',
        'doorType': 'T30',
      });

      await localDb.insert('inspections', {
        'inspectionId': 201,
        'clientName': 'Kunde Offline AG',
        'objectAddress': 'Musterstr. 10, Hamburg',
        'jobNumber': '26-99999-AB',
        'inspectorName': 'Max Prüfer',
        'craftnoteProjectId': 'CN-PROJ-OFFLINE-01',
        'craftnoteSyncStatus': 'downloaded',
      });

      await localDb.insert('inspection_doors', {
        'id': 301,
        'inspectionId': 201,
        'doorId': 101,
        'status': 'Inspected',
        'notes': 'Türprüfung offline erfolgreich',
      });

      // 2. Execute complete and upload in offline state
      final result = await syncService.completeAndUploadFromLocalDb(inspectionId: 201);

      expect(result.success, isTrue);
      expect(result.isQueuedOffline, isTrue);
      expect(result.queueId, isNotNull);
      expect(result.message, contains('Offline-Modus'));

      // 3. Verify SQLite local state
      final pendingQueue = await LocalDatabaseService.getPendingCraftnoteUploads();
      expect(pendingQueue.length, 1);
      expect(pendingQueue.first.craftnoteProjectId, 'CN-PROJ-OFFLINE-01');
      expect(pendingQueue.first.inspectionId, 201);
      expect(File(pendingQueue.first.packageFilePath).existsSync(), isTrue);

      final updatedInsp = await LocalDatabaseService.getInspectionById(201);
      expect(updatedInsp?['craftnoteSyncStatus'], 'queued');
    });

    test('completeAndUploadFromLocalDb uploads directly when device is online', () async {
      syncService.overrideOnlineStatus = true;

      // 1. Insert local door & inspection
      final localDb = await LocalDatabaseService.getDb();
      await localDb.insert('doors', {
        'id': 102,
        'doorAlias': 'ONLINE-DOOR-01',
        'doorNumber': 'T-102',
        'floor': '1.OG',
        'doorType': 'T90',
      });

      await localDb.insert('inspections', {
        'inspectionId': 202,
        'clientName': 'Kunde Online GmbH',
        'objectAddress': 'Hauptstr. 5, Berlin',
        'jobNumber': '26-88888-AB',
        'inspectorName': 'Erika Mustermann',
        'craftnoteProjectId': 'CN-PROJ-ONLINE-01',
        'craftnoteSyncStatus': 'downloaded',
      });

      await localDb.insert('inspection_doors', {
        'id': 302,
        'inspectionId': 202,
        'doorId': 102,
        'status': 'Inspected',
      });

      // 2. Execute complete and upload in online state
      final result = await syncService.completeAndUploadFromLocalDb(inspectionId: 202);

      expect(result.success, isTrue);
      expect(result.isQueuedOffline, isFalse);
      expect(result.uploadedDbFileId, isNotNull);
      expect(result.message, contains('erfolgreich'));

      // 3. Verify queue remains empty and inspection status is 'synced'
      final pendingQueue = await LocalDatabaseService.getPendingCraftnoteUploads();
      expect(pendingQueue, isEmpty);

      final updatedInsp = await LocalDatabaseService.getInspectionById(202);
      expect(updatedInsp?['craftnoteSyncStatus'], 'synced');
      expect(updatedInsp?['craftnoteFileId'], result.uploadedDbFileId);
    });

    test('processPendingUploadQueue processes offline queued items when connection restores', () async {
      // 1. Manually enqueue an offline item
      final tempDocDir = Directory.systemTemp.createTempSync('queue_test_');
      final dummyPkgFile = File('${tempDocDir.path}/test_pkg.db');
      await dummyPkgFile.writeAsString('DUMMY_SQLITE_PACKAGE');

      final queueId = await LocalDatabaseService.enqueueCraftnoteUpload(
        CraftnoteUploadQueueItem(
          inspectionId: 777,
          craftnoteProjectId: 'CN-PROJ-QUEUE-01',
          packageFilePath: dummyPkgFile.path,
          queuedAt: DateTime.now().toIso8601String(),
        ),
      );
      expect(queueId, greaterThan(0));

      // 2. When still offline, processPendingUploadQueue skips processing
      syncService.overrideOnlineStatus = false;
      var report = await syncService.processPendingUploadQueue();
      expect(report.processed, 0);

      // 3. When online, processPendingUploadQueue uploads and clears queue item
      syncService.overrideOnlineStatus = true;
      report = await syncService.processPendingUploadQueue();

      expect(report.processed, 1);
      expect(report.succeeded, 1);
      expect(report.failed, 0);

      final remainingQueue = await LocalDatabaseService.getPendingCraftnoteUploads();
      expect(remainingQueue, isEmpty);
    });

    test('exportInspectionFromMasterDb creates package and updates Master DB status', () async {
      syncService.overrideOnlineStatus = true;

      // 1. Insert door and inspection in Master DB
      final mainDb = await DatabaseService.getDb();
      await mainDb.insert('doors', {
        'id': 501,
        'doorAlias': 'MASTER-DOOR-01',
        'doorNumber': 'T-501',
        'floor': 'EG',
        'doorType': 'T30',
      });

      await mainDb.insert('inspections', {
        'inspectionId': 601,
        'clientName': 'Master Kunde AG',
        'objectAddress': 'Industriestr. 1, Köln',
        'jobNumber': '26-77777-AB',
        'inspectorName': 'Chef',
        'craftnoteSyncStatus': 'none',
      });

      await mainDb.insert('inspection_doors', {
        'id': 701,
        'inspectionId': 601,
        'doorId': 501,
        'status': 'Planned',
      });

      // 2. Export inspection from Master DB
      final result = await syncService.exportInspectionFromMasterDb(
        inspectionId: 601,
        craftnoteProjectId: 'CN-PROJ-MASTER-01',
      );

      expect(result.success, isTrue);
      expect(result.uploadedDbFileId, isNotNull);

      // 3. Verify Master DB inspection was updated
      final updatedInsp = await DatabaseService.getInspectionById(601);
      expect(updatedInsp?['craftnoteProjectId'], 'CN-PROJ-MASTER-01');
      expect(updatedInsp?['craftnoteSyncStatus'], 'synced');
      expect(updatedInsp?['craftnoteFileId'], result.uploadedDbFileId);
    });
  });
}
