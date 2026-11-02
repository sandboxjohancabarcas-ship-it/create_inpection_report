import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/craftnote_models.dart';
import 'craftnote_credentials_service.dart';

/// Exception thrown on Craftnote API communication or authentication errors.
class CraftnoteApiException implements Exception {
  final int statusCode;
  final String message;
  final String? responseBody;

  const CraftnoteApiException(this.message, {this.statusCode = 0, this.responseBody});

  @override
  String toString() => 'CraftnoteApiException: [$statusCode] $message';
}

/// Service implementing the Craftnote REST API client (v1 OpenAPI specification).
class CraftnoteApiService {
  final http.Client _client;
  final String? _explicitApiKey;
  final String? _explicitClientId;
  final String? _explicitBaseUrl;

  CraftnoteApiService({
    http.Client? client,
    String? apiKey,
    String? clientId,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _explicitApiKey = apiKey,
        _explicitClientId = clientId,
        _explicitBaseUrl = baseUrl;

  String get _apiKey => _explicitApiKey ?? CraftnoteCredentialsService.apiKey;
  String get _clientId => _explicitClientId ?? CraftnoteCredentialsService.clientId;
  String get _baseUrl => (_explicitBaseUrl ?? CraftnoteCredentialsService.baseUrl).replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers => {
        'X-CN-API-KEY': _apiKey,
        if (_clientId.isNotEmpty) 'X-CN-CLIENT-ID': _clientId,
        'Accept': 'application/json',
      };

  /// Validates whether device currently has general Internet access
  Future<bool> checkInternetConnection() async {
    try {
      final res = await InternetAddress.lookup('craftnote.de')
          .timeout(const Duration(seconds: 4));
      return res.isNotEmpty && res[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Verifies API Key authentication and returns the current user profile.
  /// Calls GET /company/members/me
  Future<CraftnoteMember> getMe() async {
    if (CraftnoteCredentialsService.isMockMode) {
      return const CraftnoteMember(
        id: 'MOCK-USER-001',
        name: 'Max',
        lastname: 'Mustermann',
        email: 'max.mustermann@gottsberg.de',
        role: 'Admin',
      );
    }

    final uri = Uri.parse('$_baseUrl/company/members/me');
    final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return CraftnoteMember.fromJson(body);
    } else if (response.statusCode == 401) {
      throw const CraftnoteApiException(
        'Ungültiger API-Key oder fehlende Berechtigung (401 Unauthorized).',
        statusCode: 401,
      );
    } else {
      throw CraftnoteApiException(
        'Authentifizierungsprüfung fehlgeschlagen.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// Queries all accessible Craftnote projects.
  /// Calls GET /projects
  Future<List<CraftnoteProject>> getProjects({
    int limit = 100,
    int offset = 0,
    String? search,
  }) async {
    if (CraftnoteCredentialsService.isMockMode) {
      final mockProjects = [
        const CraftnoteProject(
          id: 'CN-PROJ-MOCK-01',
          name: 'Universitätsklinikum Hamburg Haus 4',
          orderNumber: '26-15440-AB',
          street: 'Martinistraße 52',
          zipcode: '20246',
          city: 'Hamburg',
          clientName: 'UKE Facility Management',
        ),
        const CraftnoteProject(
          id: 'CN-PROJ-MOCK-02',
          name: 'Polizeipräsidium Carl-Cohn-Straße',
          orderNumber: '25-13966-AB',
          street: 'Carl-Cohn-Straße 39',
          zipcode: '22297',
          city: 'Hamburg',
          clientName: 'Polizei Hamburg',
        ),
        const CraftnoteProject(
          id: 'CN-PROJ-MOCK-03',
          name: 'Feuerwache Jenfelder Allee',
          orderNumber: '26-15464-AB',
          street: 'Jenfelder Allee 75',
          zipcode: '22043',
          city: 'Hamburg',
          clientName: 'Feuerwehr Hamburg',
        ),
      ];

      if (search != null && search.trim().isNotEmpty) {
        final query = search.trim().toLowerCase();
        return mockProjects.where((p) =>
            p.name.toLowerCase().contains(query) ||
            p.orderNumber.toLowerCase().contains(query) ||
            p.city.toLowerCase().contains(query)).toList();
      }
      return mockProjects;
    }

    final queryParams = {
      'limit': '$limit',
      'offset': '$offset',
    };

    final uri = Uri.parse('$_baseUrl/projects').replace(queryParameters: queryParams);
    final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      final list = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
      final projects = list.map((item) => CraftnoteProject.fromJson(item as Map<String, dynamic>)).toList();
      
      if (search != null && search.trim().isNotEmpty) {
        final query = search.trim().toLowerCase();
        return projects.where((p) =>
            p.name.toLowerCase().contains(query) ||
            p.orderNumber.toLowerCase().contains(query) ||
            p.city.toLowerCase().contains(query)).toList();
      }
      return projects;
    } else {
      throw CraftnoteApiException(
        'Fehler beim Laden der Craftnote-Projekte.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// Retrieves a single project by UUID.
  /// Calls GET /projects/{projectId}
  Future<CraftnoteProject> getProjectById(String projectId) async {
    if (CraftnoteCredentialsService.isMockMode) {
      final projects = await getProjects();
      return projects.firstWhere(
        (p) => p.id == projectId,
        orElse: () => CraftnoteProject(
          id: projectId,
          name: 'Projekt $projectId',
        ),
      );
    }

    final uri = Uri.parse('$_baseUrl/projects/$projectId');
    final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final map = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return CraftnoteProject.fromJson(map);
    } else {
      throw CraftnoteApiException(
        'Projekt konnte nicht gefunden werden.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// Queries all files attached to a project.
  /// Calls GET /projects/{projectId}/files
  Future<List<CraftnoteFile>> getProjectFiles(String projectId) async {
    if (CraftnoteCredentialsService.isMockMode) {
      return [
        CraftnoteFile(
          id: 'CN-FILE-MOCK-01',
          name: 'Inspektion_26-15440-AB_Prüfpaket.db',
          type: 'DOCUMENT',
          size: 482465,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
        CraftnoteFile(
          id: 'CN-FILE-MOCK-02',
          name: 'Lageplan_Haus4.pdf',
          type: 'DOCUMENT',
          size: 1204000,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
      ];
    }

    final uri = Uri.parse('$_baseUrl/projects/$projectId/files?limit=100');
    final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      final list = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
      return list.map((item) => CraftnoteFile.fromJson(item as Map<String, dynamic>)).toList();
    } else {
      throw CraftnoteApiException(
        'Dateien für Projekt $projectId konnten nicht geladen werden.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// Downloads a file binary and writes it to targetFilePath.
  /// Calls GET /files/{fileId}?download=true with 302 redirect handling.
  Future<File> downloadFile(String fileId, String targetFilePath) async {
    final targetFile = File(targetFilePath);
    await targetFile.parent.create(recursive: true);

    if (CraftnoteCredentialsService.isMockMode) {
      // In mock mode, write a valid dummy byte payload
      await targetFile.writeAsBytes(utf8.encode('MOCK_SQLITE_PACKAGE_BINARY_DATA'));
      return targetFile;
    }

    final uri = Uri.parse('$_baseUrl/files/$fileId?download=true');
    final request = http.Request('GET', uri)
      ..headers.addAll(_headers)
      ..followRedirects = true;

    final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 60));

    if (streamedResponse.statusCode == 200) {
      final sink = targetFile.openWrite();
      await streamedResponse.stream.pipe(sink);
      await sink.flush();
      await sink.close();
      return targetFile;
    } else {
      final responseBody = await streamedResponse.stream.bytesToString();
      throw CraftnoteApiException(
        'Dateidownload für $fileId fehlgeschlagen.',
        statusCode: streamedResponse.statusCode,
        responseBody: responseBody,
      );
    }
  }

  /// Uploads a file to a Craftnote project.
  /// Calls POST /projects/{projectId}/files (multipart/form-data)
  Future<CraftnoteFile> uploadFile({
    required String projectId,
    required File file,
    required String fileName,
    String? folderId,
  }) async {
    if (!await file.exists()) {
      throw CraftnoteApiException('Datei existiert nicht lokal: ${file.path}');
    }

    if (CraftnoteCredentialsService.isMockMode) {
      return CraftnoteFile(
        id: 'CN-FILE-UPLOADED-${DateTime.now().millisecondsSinceEpoch}',
        name: fileName,
        type: 'DOCUMENT',
        size: await file.length(),
        creationTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        folderId: folderId,
      );
    }

    final uri = Uri.parse('$_baseUrl/projects/$projectId/files');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll({
      'X-CN-API-KEY': _apiKey,
      if (_clientId.isNotEmpty) 'X-CN-CLIENT-ID': _clientId,
    });

    request.fields['type'] = 'DOCUMENT';
    request.fields['name'] = fileName;
    if (folderId != null && folderId.isNotEmpty) {
      request.fields['folderId'] = folderId;
    }

    request.files.add(await http.MultipartFile.fromPath('data', file.path, filename: fileName));

    final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 90));
    final responseBody = await streamedResponse.stream.bytesToString();

    if (streamedResponse.statusCode == 200 || streamedResponse.statusCode == 201) {
      final map = jsonDecode(responseBody) as Map<String, dynamic>;
      return CraftnoteFile.fromJson(map);
    } else {
      throw CraftnoteApiException(
        'Fehler beim Hochladen der Datei zu Projekt $projectId.',
        statusCode: streamedResponse.statusCode,
        responseBody: responseBody,
      );
    }
  }

  /// Posts a status notification or chat message into the project feed.
  /// Calls POST /projects/{projectId}/messages
  Future<void> postMessage(String projectId, String message) async {
    if (CraftnoteCredentialsService.isMockMode) {
      return;
    }

    final uri = Uri.parse('$_baseUrl/projects/$projectId/messages');
    final body = jsonEncode({'content': message});

    final headers = Map<String, String>.from(_headers);
    headers['Content-Type'] = 'application/json';

    final response = await _client.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw CraftnoteApiException(
        'Fehler beim Senden der Projektbenachrichtigung.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }
}
