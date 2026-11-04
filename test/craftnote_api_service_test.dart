import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wartungstool/services/craftnote_api_service.dart';
import 'package:wartungstool/services/craftnote_credentials_service.dart';

void main() {
  group('CraftnoteCredentialsService Tests', () {
    setUp(() {
      CraftnoteCredentialsService.resetToDefaults();
    });

    test('Initial defaults use configured default keys and isConfigured is true', () {
      expect(CraftnoteCredentialsService.apiKey, '64045d24-397a-407b-b4ae-2ceef59018dd');
      expect(CraftnoteCredentialsService.clientId, 'd04f732b-6c89-4804-97d8-63a0ea7c1199');
      expect(CraftnoteCredentialsService.isConfigured, isTrue);
    });

    test('isConfigured is false for placeholder or empty keys', () {
      CraftnoteCredentialsService.setCredentials(
        apiKey: 'CRAFTNOTE_API_KEY_PLACEHOLDER',
        clientId: 'any',
      );
      expect(CraftnoteCredentialsService.isConfigured, isFalse);

      CraftnoteCredentialsService.setCredentials(
        apiKey: 'PLACEHOLDER_KEY',
        clientId: 'any',
      );
      expect(CraftnoteCredentialsService.isConfigured, isFalse);
    });

    test('setCredentials updates in-memory values and sets isConfigured to true for real keys', () {
      CraftnoteCredentialsService.setCredentials(
        apiKey: 'real_secret_key_123',
        clientId: 'real_client_id_456',
        folder: '02_Berichte',
      );

      expect(CraftnoteCredentialsService.apiKey, 'real_secret_key_123');
      expect(CraftnoteCredentialsService.clientId, 'real_client_id_456');
      expect(CraftnoteCredentialsService.folder, '02_Berichte');
      expect(CraftnoteCredentialsService.isConfigured, isTrue);
    });
  });

  group('CraftnoteApiService Mock Adapter Tests', () {
    setUp(() {
      CraftnoteCredentialsService.setMockMode(true);
    });

    tearDown(() {
      CraftnoteCredentialsService.setMockMode(false);
    });

    test('getMe returns mock member profile', () async {
      final service = CraftnoteApiService();
      final me = await service.getMe();

      expect(me.id, isNotEmpty);
      expect(me.displayName, contains('Mustermann'));
      expect(me.email, contains('@gottsberg.de'));
    });

    test('getProjects returns predefined mock facilities and supports filtering', () async {
      final service = CraftnoteApiService();
      final allProjects = await service.getProjects();

      expect(allProjects.length, greaterThanOrEqualTo(3));
      expect(allProjects.any((p) => p.orderNumber == '26-15440-AB'), isTrue);

      final filtered = await service.getProjects(search: 'Polizei');
      expect(filtered.length, 1);
      expect(filtered.first.name, contains('Polizeipräsidium'));
    });

    test('getProjectFiles returns mock db and pdf documents', () async {
      final service = CraftnoteApiService();
      final files = await service.getProjectFiles('CN-PROJ-MOCK-01');

      expect(files.length, greaterThanOrEqualTo(2));
      expect(files.any((f) => f.isSqliteDatabase), isTrue);
      expect(files.any((f) => f.isPdfReport), isTrue);
      expect(files.any((f) => f.isFolder), isTrue);
    });

    test('downloadFile in mock mode writes valid dummy binary payload', () async {
      final service = CraftnoteApiService();
      final tempPath = '${Directory.systemTemp.path}/test_cn_mock_download_${DateTime.now().millisecondsSinceEpoch}.db';

      final file = await service.downloadFile('CN-FILE-MOCK-01', tempPath);
      expect(await file.exists(), isTrue);

      final content = await file.readAsString();
      expect(content, contains('MOCK_SQLITE_PACKAGE_BINARY_DATA'));
      await file.delete();
    });

    test('uploadFile in mock mode returns completed CraftnoteFile metadata', () async {
      final service = CraftnoteApiService();
      final tempFile = File('${Directory.systemTemp.path}/test_upload_${DateTime.now().millisecondsSinceEpoch}.db');
      await tempFile.writeAsString('test package content');

      final uploaded = await service.uploadFile(
        projectId: 'CN-PROJ-MOCK-01',
        file: tempFile,
        fileName: 'Inspektion_2026.db',
      );

      expect(uploaded.name, 'Inspektion_2026.db');
      expect(uploaded.id, startsWith('CN-FILE-UPLOADED'));
      await tempFile.delete();
    });
  });

  group('CraftnoteApiService Real HTTP Protocol Tests (MockClient)', () {
    test('getMe sends proper X-CN-API-KEY and X-CN-CLIENT-ID headers and parses response', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/company/members/me');
        expect(request.headers['X-CN-API-KEY'], 'test_api_key_abc');
        expect(request.headers['X-CN-CLIENT-ID'], 'test_client_id_xyz');
        expect(request.headers['Accept'], 'application/json');

        return http.Response(
          jsonEncode({
            'id': 'MEM-100',
            'name': 'Johan',
            'lastname': 'Cabarcas',
            'email': 'cabarcas@gottsberg.de',
            'role': 'Manager',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = CraftnoteApiService(
        client: mockClient,
        apiKey: 'test_api_key_abc',
        clientId: 'test_client_id_xyz',
        baseUrl: 'https://test.craftnote.de/api/v1',
      );

      final me = await service.getMe();
      expect(me.displayName, 'Johan Cabarcas');
      expect(me.email, 'cabarcas@gottsberg.de');
    });

    test('getMe throws CraftnoteApiException with 401 when API Key is unauthorized', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'Unauthorized'}), 401);
      });

      final service = CraftnoteApiService(
        client: mockClient,
        apiKey: 'invalid_key',
        baseUrl: 'https://test.craftnote.de/api/v1',
      );

      expect(() => service.getMe(), throwsA(isA<CraftnoteApiException>().having((e) => e.statusCode, 'statusCode', 401)));
    });

    test('getProjects parses project list with full address and orderNumber', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/projects');
        expect(request.url.queryParameters['limit'], '100');
        expect(request.url.queryParameters['offset'], '0');

        return http.Response(
          jsonEncode([
            {
              'id': 'PROJ-99',
              'name': 'Großbaustelle Speicherstadt',
              'orderNumber': '26-99999-AB',
              'street': 'Am Sandtorkai 1',
              'zipcode': '20457',
              'city': 'Hamburg',
              'clientName': 'HHLA',
            }
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = CraftnoteApiService(
        client: mockClient,
        apiKey: 'key',
        baseUrl: 'https://test.craftnote.de/api/v1',
      );

      final projects = await service.getProjects();
      expect(projects.length, 1);
      expect(projects.first.orderNumber, '26-99999-AB');
      expect(projects.first.fullAddress, contains('Am Sandtorkai 1, 20457 Hamburg'));
    });

    test('getProjects parses projects with OpenAPI envelope { "projects": [...] }', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'projects': [
              {
                'id': 'PROJ-LIVE-1',
                'name': 'UKE Hamburg Neubau',
                'orderNumber': '26-11111-AB',
                'street': 'Martinistraße 52',
                'zipcode': '20246',
                'city': 'Hamburg',
                'clientName': 'UKE',
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = CraftnoteApiService(
        client: mockClient,
        apiKey: 'key',
        baseUrl: 'https://test.craftnote.de/api/v1',
      );

      final projects = await service.getProjects();
      expect(projects.length, 1);
      expect(projects.first.id, 'PROJ-LIVE-1');
      expect(projects.first.name, 'UKE Hamburg Neubau');
    });

    test('getProjectFiles parses files with OpenAPI envelope { "files": [...] }', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'files': [
              {
                'id': 'FILE-100',
                'name': 'Prüfpaket.db',
                'type': 'DOCUMENT',
                'size': 12345,
                'creationTimestamp': 1700000000,
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = CraftnoteApiService(
        client: mockClient,
        apiKey: 'key',
        baseUrl: 'https://test.craftnote.de/api/v1',
      );

      final files = await service.getProjectFiles('PROJ-LIVE-1');
      expect(files.length, 1);
      expect(files.first.name, 'Prüfpaket.db');
      expect(files.first.size, 12345);
    });

    test('postMessage sends correct JSON payload to /projects/{id}/messages', () async {
      bool messageSent = false;
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/projects/PROJ-123/messages');
        expect(request.headers['Content-Type'], contains('application/json'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['content'], contains('Prüfpaket hochgeladen'));
        messageSent = true;
        return http.Response('{"id":"MSG-1"}', 201);
      });

      final service = CraftnoteApiService(
        client: mockClient,
        apiKey: 'key',
        baseUrl: 'https://test.craftnote.de/api/v1',
      );

      await service.postMessage('PROJ-123', 'Prüfpaket hochgeladen durch Manager');
      expect(messageSent, isTrue);
    });

    test('findProjects paginates across pages and finds project by orderNumber', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        if (offset == 0) {
          // Page 1: doesn't have target project
          return http.Response(
            jsonEncode({
              'projects': [
                {'id': 'P-1', 'name': 'Other Project', 'orderNumber': '26-00001-AB'}
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        } else {
          // Page 2: has target project
          return http.Response(
            jsonEncode({
              'projects': [
                {
                  'id': '0bcce8b1-bb9b-4d67-b41e-f700d3a57bfd',
                  'name': '202121 Industrie GmbH Unit 2 - Unbekannt',
                  'orderNumber': '26-00251-AN',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
      });

      final service = CraftnoteApiService(
        client: mockClient,
        apiKey: 'key',
        baseUrl: 'https://test.craftnote.de/api/v1',
      );

      final matches = await service.findProjects(orderNumber: '26-00251-AN', pageSize: 1);
      expect(matches.length, 1);
      expect(matches.first.id, '0bcce8b1-bb9b-4d67-b41e-f700d3a57bfd');
      expect(matches.first.name, '202121 Industrie GmbH Unit 2 - Unbekannt');
      expect(requestCount, 2);
    });
  });
}
