import 'dart:convert';
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
        craftnoteProjectId: CraftnoteCredentialsService.testProjectId,
      );

      expect(result.success, isTrue);
      expect(result.uploadedDbFileId, isNotNull);

      // 3. Verify Master DB inspection was updated
      final updatedInsp = await DatabaseService.getInspectionById(601);
      expect(updatedInsp?['craftnoteProjectId'], CraftnoteCredentialsService.testProjectId);
      expect(updatedInsp?['craftnoteSyncStatus'], 'synced');
      expect(updatedInsp?['craftnoteFileId'], result.uploadedDbFileId);
    });

    test('resolveProjectStandardFolders resolves Wartungslisten and Fotomaterial folders', () async {
      final folders = await syncService.resolveProjectStandardFolders('CN-PROJ-TEST-01');

      expect(folders.hasWartungslisten, isTrue);
      expect(folders.wartungslistenFolderId, 'CN-FOLDER-WARTUNGLISTEN');
      expect(folders.hasFotomaterial, isTrue);
      expect(folders.fotomaterialFolderId, 'CN-FOLDER-FOTOMATERIAL');
      expect(folders.formatFolderInfo(), contains('Wartungslisten'));
      expect(folders.formatFolderInfo(), contains('Fotomaterial'));
    });

    test('syncInspectionPhotos extracts defect photos and uploads them with deduplication', () async {
      // 1. Insert door, inspection, inspection_door, and error with photo in Master DB
      final mainDb = await DatabaseService.getDb();
      await mainDb.insert('doors', {
        'id': 801,
        'doorAlias': 'FOTO-DOOR-01',
        'doorNumber': 'T-801',
        'floor': '1.OG',
        'doorType': 'T30',
      });

      await mainDb.insert('inspections', {
        'inspectionId': 901,
        'clientName': 'Foto Kunde GmbH',
        'objectAddress': 'Fotoweg 12, Köln',
        'jobNumber': '26-00251-AN',
        'inspectorName': 'Foto Prüfer',
        'craftnoteSyncStatus': 'none',
      });

      await mainDb.insert('inspection_doors', {
        'id': 1001,
        'inspectionId': 901,
        'doorId': 801,
        'status': 'Inspected',
      });

      // Valid base64 payload for a small dummy jpg
      final dummyBase64 = base64Encode(utf8.encode('DUMMY_PHOTO_BYTES_123'));
      await mainDb.insert('inspection_door_errors', {
        'id': 2001,
        'inspectionDoorId': 1001,
        'errorCode': 'E101',
        'notes': 'Tür schließt nicht dicht',
        'attachments': dummyBase64,
      });

      // 2. Sync photos
      final photoResult = await syncService.syncInspectionPhotos(
        inspectionId: 901,
        craftnoteProjectId: 'CN-PROJ-TEST-01',
        isManagerMode: true,
      );

      expect(photoResult.totalPhotos, 1);
      expect(photoResult.uploadedPhotos, 1);
      expect(photoResult.skippedPhotos, 0);
      expect(photoResult.uploadedFileNames, contains('FOTO-DOOR-01_Fehler_E101_1.jpg'));
    });

    test('exportInspectionFromMasterDb with syncPhotos routes .db to Wartungslisten and synchronizes photos', () async {
      // 1. Setup inspection with photo
      final mainDb = await DatabaseService.getDb();
      await mainDb.insert('doors', {
        'id': 802,
        'doorAlias': 'SYNC-DOOR-02',
        'doorNumber': 'T-802',
        'floor': '2.OG',
        'doorType': 'T90',
      });

      await mainDb.insert('inspections', {
        'inspectionId': 902,
        'clientName': 'Auto Route AG',
        'objectAddress': 'Industriestr. 99, Berlin',
        'jobNumber': '26-00251-AN',
        'inspectorName': 'Chef',
        'craftnoteSyncStatus': 'none',
      });

      await mainDb.insert('inspection_doors', {
        'id': 1002,
        'inspectionId': 902,
        'doorId': 802,
        'status': 'Planned',
      });

      final dummyBase64 = base64Encode(utf8.encode('DUMMY_PHOTO_BYTES_456'));
      await mainDb.insert('inspection_door_errors', {
        'id': 2002,
        'inspectionDoorId': 1002,
        'errorCode': 'E202',
        'notes': 'Dichtung beschädigt',
        'attachments': dummyBase64,
      });

      // 2. Export with syncPhotos: true
      final syncResult = await syncService.exportInspectionFromMasterDb(
        inspectionId: 902,
        craftnoteProjectId: 'CN-PROJ-TEST-01',
        syncPhotos: true,
      );

      expect(syncResult.success, isTrue);
      expect(syncResult.wartungslistenFolderId, 'CN-FOLDER-WARTUNGLISTEN');
      expect(syncResult.fotomaterialFolderId, 'CN-FOLDER-FOTOMATERIAL');
      expect(syncResult.totalPhotos, 1);
      expect(syncResult.uploadedPhotos, 1);
      expect(syncResult.message, contains('Wartungslisten'));
    });

    test('test mode redirects uploads from production project ID to testProjectId', () async {
      CraftnoteCredentialsService.setTestMode(true);

      final mainDb = await DatabaseService.getDb();
      await mainDb.insert('doors', {
        'id': 803,
        'doorAlias': 'PROD-DOOR-01',
        'doorNumber': 'T-803',
      });
      await mainDb.insert('inspections', {
        'inspectionId': 903,
        'clientName': 'Produktiv Kunde',
        'jobNumber': '23-09574-AB',
        'craftnoteSyncStatus': 'none',
      });
      await mainDb.insert('inspection_doors', {
        'id': 1003,
        'inspectionId': 903,
        'doorId': 803,
      });

      final result = await syncService.exportInspectionFromMasterDb(
        inspectionId: 903,
        craftnoteProjectId: 'REAL-PROD-PROJECT-UUID-1234',
        syncPhotos: false,
      );

      expect(result.success, isTrue);
      // Verify that Master DB stored the redirect to testProjectId to avoid production writes
      final updated = await DatabaseService.getInspectionById(903);
      expect(updated?['craftnoteProjectId'], CraftnoteCredentialsService.testProjectId);
      expect(result.message, contains('Sandbox-Testprojekt'));
    });

    test('production mode allows uploads directly to requested project ID', () async {
      CraftnoteCredentialsService.setTestMode(false);

      final mainDb = await DatabaseService.getDb();
      await mainDb.insert('doors', {
        'id': 804,
        'doorAlias': 'PROD-DOOR-02',
        'doorNumber': 'T-804',
      });
      await mainDb.insert('inspections', {
        'inspectionId': 904,
        'clientName': 'Live Kunde',
        'jobNumber': '24-11111-AB',
        'craftnoteSyncStatus': 'none',
      });
      await mainDb.insert('inspection_doors', {
        'id': 1004,
        'inspectionId': 904,
        'doorId': 804,
      });

      final result = await syncService.exportInspectionFromMasterDb(
        inspectionId: 904,
        craftnoteProjectId: 'PROD-ALLOWED-PROJECT-UUID',
        syncPhotos: false,
      );

      expect(result.success, isTrue);
      final updated = await DatabaseService.getInspectionById(904);
      expect(updated?['craftnoteProjectId'], 'PROD-ALLOWED-PROJECT-UUID');
      expect(result.message, isNot(contains('Sandbox-Testprojekt')));
    });

    test('getProjectDbPackages resolves sqlite packages prioritizing Wartungslisten folder', () async {
      final packages = await syncService.getProjectDbPackages('CN-PROJ-MOCK-01');
      expect(packages.isNotEmpty, isTrue);
      expect(packages.every((p) => p.isSqliteDatabase || p.name.endsWith('.db')), isTrue);
    });

    test('importProjectJobPackage returns error if no package exists in project', () async {
      const emptyProject = CraftnoteProject(
        id: 'CN-EMPTY-PROJ',
        name: 'Empty Project Without DB',
        orderNumber: '99-00000-XX',
      );

      final result = await syncService.importProjectJobPackage(project: emptyProject);
      expect(result.success, isFalse);
      expect(result.message, contains('kein Wartungspaket (.db) gefunden'));
    });

    test('importProjectJobPackage in test mode checks sandbox test project if target project has no package', () async {
      CraftnoteCredentialsService.setTestMode(true);
      const emptyProjectWithKnownOrder = CraftnoteProject(
        id: 'CN-EMPTY-PROJ',
        name: 'Empty Target Project',
        orderNumber: '26-15440-AB',
      );

      final result = await syncService.importProjectJobPackage(
        project: emptyProjectWithKnownOrder,
        isManagerMode: true,
      );
      expect(result.success, isTrue);
      expect(result.message, contains('Prüfergebnis erfolgreich aus Craftnote importiert'));
    });

    test('completeAndUploadFromLocalDb resolves project by orderNumber, routes to Wartungslisten and Fotomaterial, and enforces test mode sandbox guard', () async {
      syncService.overrideOnlineStatus = true;
      CraftnoteCredentialsService.setTestMode(true);

      final localDb = await LocalDatabaseService.getDb();
      await localDb.insert('doors', {
        'id': 105,
        'doorAlias': 'INSP-DOOR-01',
        'doorNumber': 'T-105',
        'floor': 'EG',
        'doorType': 'T30',
      });

      // Inspection with live job number matching mock project CN-PROJ-MOCK-01 (orderNumber: 26-15440-AB)
      await localDb.insert('inspections', {
        'inspectionId': 205,
        'clientName': 'Universitätsklinikum Hamburg',
        'jobNumber': '26-15440-AB',
        'inspectorName': 'Tom Prüfer',
        'craftnoteSyncStatus': 'inProgress',
      });

      await localDb.insert('inspection_doors', {
        'id': 305,
        'inspectionId': 205,
        'doorId': 105,
        'status': 'Inspected',
      });

      // Insert defect error with a photo in base64
      final dummyBase64 = base64Encode(utf8.encode('DUMMY_PHOTO_BYTES_INSP_123'));
      await localDb.insert('inspection_door_errors', {
        'id': 405,
        'inspectionDoorId': 305,
        'errorCode': 'E501',
        'notes': 'Schließer defekt',
        'attachments': dummyBase64,
      });

      final result = await syncService.completeAndUploadFromLocalDb(inspectionId: 205);

      expect(result.success, isTrue);
      expect(result.isQueuedOffline, isFalse);
      expect(result.uploadedDbFileId, isNotNull);
      // Feedback contains project name and orderNumber from search
      expect(result.message, contains('Universitätsklinikum Hamburg Haus 4'));
      expect(result.message, contains('26-15440-AB'));
      // Sandbox protection notice present in test mode
      expect(result.message, contains('Sandbox-Testprojekt'));
      expect(result.message, contains('26-00251-AN'));
      // Folders resolved
      expect(result.wartungslistenFolderId, 'CN-FOLDER-WARTUNGLISTEN');
      expect(result.fotomaterialFolderId, 'CN-FOLDER-FOTOMATERIAL');
      // Photo uploaded to Fotomaterial
      expect(result.uploadedPhotos, 1);

      // Local DB updated to test project ID in test mode
      final updatedInsp = await LocalDatabaseService.getInspectionById(205);
      expect(updatedInsp?['craftnoteSyncStatus'], 'synced');
      expect(updatedInsp?['craftnoteProjectId'], CraftnoteCredentialsService.testProjectId);
    });

    test('completeAndUploadFromLocalDb in production mode uploads directly to found project ID', () async {
      syncService.overrideOnlineStatus = true;
      CraftnoteCredentialsService.setTestMode(false);

      final localDb = await LocalDatabaseService.getDb();
      await localDb.insert('doors', {
        'id': 106,
        'doorAlias': 'PROD-INSP-DOOR-01',
        'doorNumber': 'T-106',
        'floor': '1.OG',
        'doorType': 'T90',
      });

      // Inspection matching CN-PROJ-MOCK-02 (orderNumber: 25-13966-AB)
      await localDb.insert('inspections', {
        'inspectionId': 206,
        'clientName': 'Polizeipräsidium',
        'jobNumber': '25-13966-AB',
        'inspectorName': 'Chefprüfer',
        'craftnoteSyncStatus': 'inProgress',
      });

      await localDb.insert('inspection_doors', {
        'id': 306,
        'inspectionId': 206,
        'doorId': 106,
        'status': 'Inspected',
      });

      final result = await syncService.completeAndUploadFromLocalDb(inspectionId: 206);

      expect(result.success, isTrue);
      expect(result.isQueuedOffline, isFalse);
      expect(result.message, isNot(contains('Sandbox-Testprojekt')));
      expect(result.message, contains('Polizeipräsidium Carl-Cohn-Straße'));

      final updatedInsp = await LocalDatabaseService.getInspectionById(206);
      expect(updatedInsp?['craftnoteSyncStatus'], 'synced');
      expect(updatedInsp?['craftnoteProjectId'], 'CN-PROJ-MOCK-02');
    });

    test('completeAndUploadFromLocalDb rejects upload if target project is archived', () async {
      syncService.overrideOnlineStatus = true;
      CraftnoteCredentialsService.setTestMode(false);

      final localDb = await LocalDatabaseService.getDb();
      await localDb.insert('doors', {
        'id': 107,
        'doorAlias': 'ARCHIVED-DOOR-01',
        'doorNumber': 'T-107',
        'floor': 'Keller',
        'doorType': 'T30',
      });

      // Inspection matching archived project 26-15613-AB (CN-PROJ-MOCK-ARCHIVED-01)
      await localDb.insert('inspections', {
        'inspectionId': 207,
        'clientName': 'W Ellernreihe',
        'jobNumber': '26-15613-AB',
        'inspectorName': 'Prüfer Archiv',
        'craftnoteSyncStatus': 'inProgress',
      });

      await localDb.insert('inspection_doors', {
        'id': 307,
        'inspectionId': 207,
        'doorId': 107,
        'status': 'Inspected',
      });

      final result = await syncService.completeAndUploadFromLocalDb(inspectionId: 207);

      expect(result.success, isFalse);
      expect(result.message, contains('bereits archiviert'));
      expect(result.message, contains('26-15613-AB'));
    });

    test('importProjectJobPackage rejects import if project is marked as archived', () async {
      const archivedProject = CraftnoteProject(
        id: 'CN-PROJ-MOCK-ARCHIVED-01',
        name: 'W Ellernreihe 135 (Archiviert)',
        orderNumber: '26-15613-AB',
        archived: true,
      );

      final resultInspector = await syncService.importProjectJobPackage(
        project: archivedProject,
        isManagerMode: false,
      );
      expect(resultInspector.success, isFalse);
      expect(resultInspector.message, contains('bereits archiviert'));

      final resultManager = await syncService.importProjectJobPackage(
        project: archivedProject,
        isManagerMode: true,
      );
      expect(resultManager.success, isFalse);
      expect(resultManager.message, contains('bereits archiviert'));
    });
  });
}
