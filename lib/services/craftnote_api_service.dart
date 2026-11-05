import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../models/craftnote_models.dart';
import 'craftnote_credentials_service.dart';

/// Exception thrown on Craftnote API communication or authentication errors.
class CraftnoteApiException implements Exception {
  final int statusCode;
  final String message;
  final String? responseBody;

  const CraftnoteApiException(this.message, {this.statusCode = 0, this.responseBody});

  @override
  String toString() {
    if (responseBody != null && responseBody!.trim().isNotEmpty) {
      return 'CraftnoteApiException: [$statusCode] $message (Server-Antwort: $responseBody)';
    }
    return 'CraftnoteApiException: [$statusCode] $message';
  }
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

  /// Logs outgoing API request with masked API key for security
  void _logRequest(String method, Uri uri, {Map<String, String>? headers, String? body}) {
    final effectiveHeaders = headers != null ? Map<String, String>.from(headers) : Map<String, String>.from(_headers);
    if (effectiveHeaders.containsKey('X-CN-API-KEY')) {
      final key = effectiveHeaders['X-CN-API-KEY']!;
      if (key.length > 8) {
        effectiveHeaders['X-CN-API-KEY'] = '${key.substring(0, 4)}...${key.substring(key.length - 4)}';
      }
    }
    print('[CraftnoteApi] >>> REQUEST: $method ${uri.toString()}');
    print('[CraftnoteApi]     Headers: $effectiveHeaders');
    if (body != null && body.isNotEmpty) {
      final preview = body.length > 250 ? '${body.substring(0, 250)}... (${body.length} chars)' : body;
      print('[CraftnoteApi]     Payload: $preview');
    }
  }

  /// Logs incoming API response status and body
  void _logResponse(String method, Uri uri, int statusCode, {String? body, int? elapsedMs}) {
    final elapsedStr = elapsedMs != null ? ' in ${elapsedMs}ms' : '';
    final symbol = (statusCode >= 200 && statusCode < 300) ? '✅' : '❌';
    print('[CraftnoteApi] <<< RESPONSE: $symbol [$statusCode] $method ${uri.toString()}$elapsedStr');
    if (body != null && body.isNotEmpty) {
      if (statusCode >= 200 && statusCode < 300) {
        final preview = body.length > 250 ? '${body.substring(0, 250)}... (${body.length} bytes)' : body;
        print('[CraftnoteApi]     Response: $preview');
      } else {
        // Log full response body on error
        print('[CraftnoteApi]     Error Body: $body');
      }
    }
  }

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
      print('[CraftnoteApi] (Mock) GET /company/members/me');
      return const CraftnoteMember(
        id: 'MOCK-USER-001',
        name: 'Max',
        lastname: 'Mustermann',
        email: 'max.mustermann@gottsberg.de',
        role: 'Admin',
      );
    }

    final uri = Uri.parse('$_baseUrl/company/members/me');
    _logRequest('GET', uri);
    final sw = Stopwatch()..start();

    try {
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      sw.stop();
      _logResponse('GET', uri, response.statusCode, body: response.body, elapsedMs: sw.elapsedMilliseconds);

      if (response.statusCode == 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return CraftnoteMember.fromJson(body);
      } else if (response.statusCode == 401) {
        throw CraftnoteApiException(
          'Ungültiger API-Key oder fehlende Berechtigung (401 Unauthorized).',
          statusCode: 401,
          responseBody: response.body,
        );
      } else {
        throw CraftnoteApiException(
          'Authentifizierungsprüfung fehlgeschlagen.',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      if (e is! CraftnoteApiException) {
        print('[CraftnoteApi] ❌ Connection error on GET $uri: $e');
      }
      rethrow;
    }
  }

  /// Queries all accessible Craftnote projects for a given page.
  /// Calls GET /projects
  /// If [status] is 'active', only active (non-archived) projects are returned.
  /// If [status] is 'archived', only archived projects are returned.
  Future<List<CraftnoteProject>> getProjects({
    int limit = 100,
    int offset = 0,
    String? search,
    String? status,
  }) async {
    if (CraftnoteCredentialsService.isMockMode) {
      final mockProjects = [
        const CraftnoteProject(
          id: CraftnoteCredentialsService.testProjectId,
          name: CraftnoteCredentialsService.testProjectName,
          orderNumber: CraftnoteCredentialsService.testProjectOrderNumber,
          street: 'Industriestraße 1',
          zipcode: '12345',
          city: 'Musterstadt',
          clientName: 'Industrie GmbH',
          archived: false,
        ),
        const CraftnoteProject(
          id: 'CN-PROJ-MOCK-01',
          name: 'Universitätsklinikum Hamburg Haus 4',
          orderNumber: '26-15440-AB',
          street: 'Martinistraße 52',
          zipcode: '20246',
          city: 'Hamburg',
          clientName: 'UKE Facility Management',
          archived: false,
        ),
        const CraftnoteProject(
          id: 'CN-PROJ-MOCK-02',
          name: 'Polizeipräsidium Carl-Cohn-Straße',
          orderNumber: '25-13966-AB',
          street: 'Carl-Cohn-Straße 39',
          zipcode: '22297',
          city: 'Hamburg',
          clientName: 'Polizei Hamburg',
          archived: false,
        ),
        const CraftnoteProject(
          id: 'CN-PROJ-MOCK-03',
          name: 'Feuerwache Jenfelder Allee',
          orderNumber: '26-15464-AB',
          street: 'Jenfelder Allee 75',
          zipcode: '22043',
          city: 'Hamburg',
          clientName: 'Feuerwehr Hamburg',
          archived: false,
        ),
        const CraftnoteProject(
          id: 'CN-PROJ-MOCK-ARCHIVED-01',
          name: 'W Ellernreihe 135 (Archiviert)',
          orderNumber: '26-15613-AB',
          street: 'Ellernreihe 135',
          zipcode: '22179',
          city: 'Hamburg',
          clientName: 'Wohnungsbaugesellschaft Hamburg',
          archived: true,
        ),
      ];

      List<CraftnoteProject> list = mockProjects;
      if (status == 'active') {
        list = list.where((p) => !p.archived).toList();
      } else if (status == 'archived') {
        list = list.where((p) => p.archived).toList();
      }

      if (search != null && search.trim().isNotEmpty) {
        final query = search.trim().toLowerCase();
        return list.where((p) =>
            p.name.toLowerCase().contains(query) ||
            p.orderNumber.toLowerCase().contains(query) ||
            p.city.toLowerCase().contains(query)).toList();
      }
      return list;
    }

    final queryParams = {
      'limit': '$limit',
      'offset': '$offset',
      if (status != null && status.isNotEmpty) 'status': status,
    };

    final uri = Uri.parse('$_baseUrl/projects').replace(queryParameters: queryParams);
    _logRequest('GET', uri);
    final sw = Stopwatch()..start();

    try {
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      sw.stop();
      _logResponse('GET', uri, response.statusCode, body: response.body, elapsedMs: sw.elapsedMilliseconds);

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
        List<dynamic> list;
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map<String, dynamic>) {
          list = (decoded['projects'] ?? decoded['data'] ?? decoded['items'] ?? []) as List<dynamic>;
        } else {
          list = [];
        }
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
    } catch (e) {
      if (e is! CraftnoteApiException) {
        print('[CraftnoteApi] ❌ Connection error on GET $uri: $e');
      }
      rethrow;
    }
  }

  /// Searches for projects across pages in Craftnote by orderNumber, name, or UUID.
  /// Paginates through GET /projects until matches are found or maxPages reached.
  /// If [status] is 'active', only active projects are searched.
  /// If [status] is 'archived', only archived projects are searched.
  Future<List<CraftnoteProject>> findProjects({
    String? query,
    String? orderNumber,
    String? name,
    String? status,
    int maxPages = 25,
    int pageSize = 100,
  }) async {
    final cleanQuery = query?.trim() ?? '';
    final cleanOrder = orderNumber?.trim() ?? '';
    final cleanName = name?.trim() ?? '';

    // Direct UUID match check
    final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    if (uuidRegex.hasMatch(cleanQuery)) {
      try {
        final proj = await getProjectById(cleanQuery);
        if (status == 'active' && proj.archived) return [];
        if (status == 'archived' && !proj.archived) return [];
        return [proj];
      } catch (_) {}
    }

    if (CraftnoteCredentialsService.isMockMode) {
      final all = await getProjects(status: status);
      final qLower = cleanQuery.toLowerCase();
      final ordLower = cleanOrder.toLowerCase();
      final nameLower = cleanName.toLowerCase();
      return all.where((p) {
        final matchOrd = ordLower.isNotEmpty && p.orderNumber.toLowerCase().contains(ordLower);
        final matchName = nameLower.isNotEmpty && p.name.toLowerCase().contains(nameLower);
        final matchQuery = qLower.isNotEmpty &&
            (p.name.toLowerCase().contains(qLower) ||
             p.orderNumber.toLowerCase().contains(qLower) ||
             p.id.toLowerCase() == qLower);
        return matchOrd || matchName || matchQuery;
      }).toList();
    }

    print('[CraftnoteApi] 🔍 Searching projects in Craftnote: orderNumber="$cleanOrder", name="$cleanName", query="$cleanQuery", status="${status ?? 'all'}" (maxPages: $maxPages, pageSize: $pageSize)...');

    final ordLower = cleanOrder.toLowerCase();
    final nameLower = cleanName.toLowerCase();
    final qLower = cleanQuery.toLowerCase();

    final List<CraftnoteProject> matches = [];
    int offset = 0;
    final limit = pageSize;

    for (int page = 0; page < maxPages; page++) {
      final pageProjects = await getProjects(limit: limit, offset: offset, status: status);
      if (pageProjects.isEmpty) break;

      for (final p in pageProjects) {
        if (status == 'active' && p.archived) continue;
        if (status == 'archived' && !p.archived) continue;

        final pOrd = p.orderNumber.toLowerCase();
        final pName = p.name.toLowerCase();
        final pId = p.id.toLowerCase();

        final matchOrd = ordLower.isNotEmpty && (pOrd.contains(ordLower) || pId == ordLower);
        final matchName = nameLower.isNotEmpty && pName.contains(nameLower);
        final matchQuery = qLower.isNotEmpty && (pName.contains(qLower) || pOrd.contains(qLower) || pId == qLower);

        if (matchOrd || matchName || matchQuery) {
          matches.add(p);
        }
      }

      // If we found an exact match for orderNumber, we can stop early
      if (ordLower.isNotEmpty && matches.any((p) => p.orderNumber.toLowerCase() == ordLower)) {
        print('[CraftnoteApi] 🎯 Exact match for orderNumber "$cleanOrder" found at offset $offset: "${matches.first.name}" (ID: ${matches.first.id})');
        break;
      }

      if (pageProjects.length < limit) break;
      offset += pageProjects.length;
    }

    print('[CraftnoteApi] 🔍 Project search finished. Found ${matches.length} matching project(s).');
    return matches;
  }

  /// Searches for an active project by orderNumber/query first.
  /// If no active project is found, it automatically checks archived projects.
  /// If found in archives, returns a result with [isArchived: true] so the caller
  /// can only inform the user that the project is archived and cannot be processed.
  Future<CraftnoteProjectSearchResult> findProjectWithArchiveCheck({
    required String orderNumber,
    String? query,
    int maxPages = 25,
  }) async {
    final cleanOrder = orderNumber.trim();
    final cleanQuery = query?.trim() ?? cleanOrder;

    // 1. Search active projects ONLY
    final activeResults = await findProjects(
      orderNumber: cleanOrder,
      query: cleanQuery,
      status: 'active',
      maxPages: maxPages,
    );

    final activeMatches = activeResults.where((p) => !p.archived).toList();
    if (activeMatches.isNotEmpty) {
      final match = activeMatches.firstWhere(
        (p) => p.orderNumber.trim().toLowerCase() == cleanOrder.toLowerCase(),
        orElse: () => activeMatches.first,
      );
      return CraftnoteProjectSearchResult(
        activeProject: match,
        isArchived: false,
      );
    }

    // 2. If no active project was found, search in archived projects
    final archivedResults = await findProjects(
      orderNumber: cleanOrder,
      query: cleanQuery,
      status: 'archived',
      maxPages: maxPages,
    );

    final archivedMatches = archivedResults.where((p) => p.archived).toList();
    if (archivedMatches.isNotEmpty) {
      final match = archivedMatches.firstWhere(
        (p) => p.orderNumber.trim().toLowerCase() == cleanOrder.toLowerCase(),
        orElse: () => archivedMatches.first,
      );
      return CraftnoteProjectSearchResult(
        archivedProject: match,
        isArchived: true,
        errorMessage:
            'Das Craftnote-Projekt "${match.name}" (#${match.orderNumber.isNotEmpty ? match.orderNumber : match.id}) ist bereits archiviert und kann nicht mehr bearbeitet oder importiert werden.\n\nBitte aktivieren Sie das Projekt in Craftnote, falls es erneut bearbeitet werden soll.',
      );
    }

    // 3. Not found in either active or archived
    return const CraftnoteProjectSearchResult(
      isArchived: false,
    );
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
    _logRequest('GET', uri);
    final sw = Stopwatch()..start();

    try {
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      sw.stop();
      _logResponse('GET', uri, response.statusCode, body: response.body, elapsedMs: sw.elapsedMilliseconds);

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
    } catch (e) {
      if (e is! CraftnoteApiException) {
        print('[CraftnoteApi] ❌ Connection error on GET $uri: $e');
      }
      rethrow;
    }
  }

  /// Queries all files attached to a project.
  /// Calls GET /projects/{projectId}/files
  Future<List<CraftnoteFile>> getProjectFiles(String projectId) async {
    if (CraftnoteCredentialsService.isMockMode) {
      if (projectId.contains('EMPTY')) return [];
      return [
        const CraftnoteFile(
          id: 'CN-FOLDER-MEDIEN',
          name: '11 Medien',
          type: 'FOLDER',
        ),
        const CraftnoteFile(
          id: 'CN-FOLDER-WARTUNGLISTEN',
          name: 'Wartungslisten',
          type: 'FOLDER',
          folderId: 'CN-FOLDER-MEDIEN',
        ),
        const CraftnoteFile(
          id: 'CN-FOLDER-FOTOMATERIAL',
          name: 'Fotomaterial',
          type: 'FOLDER',
          folderId: 'CN-FOLDER-MEDIEN',
        ),
        CraftnoteFile(
          id: 'CN-FILE-MOCK-01',
          name: 'Inspektion_26-15440-AB_Prüfpaket.db',
          type: 'DOCUMENT',
          size: 482465,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          folderId: 'CN-FOLDER-WARTUNGLISTEN',
        ),
        CraftnoteFile(
          id: 'CN-FILE-MOCK-ERGEBNIS-01',
          name: '26-15440-AB_Universitätsklinikum_inspektion_ergebnis_20261104.db',
          type: 'DOCUMENT',
          size: 512000,
          creationTimestamp: (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 100,
          folderId: 'CN-FOLDER-WARTUNGLISTEN',
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
    _logRequest('GET', uri);
    final sw = Stopwatch()..start();

    try {
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      sw.stop();
      _logResponse('GET', uri, response.statusCode, body: response.body, elapsedMs: sw.elapsedMilliseconds);

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
        List<dynamic> list;
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map<String, dynamic>) {
          list = (decoded['files'] ?? decoded['data'] ?? decoded['items'] ?? []) as List<dynamic>;
        } else {
          list = [];
        }
        return list.map((item) => CraftnoteFile.fromJson(item as Map<String, dynamic>)).toList();
      } else {
        throw CraftnoteApiException(
          'Dateien für Projekt $projectId konnten nicht geladen werden.',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      if (e is! CraftnoteApiException) {
        print('[CraftnoteApi] ❌ Connection error on GET $uri: $e');
      }
      rethrow;
    }
  }

  /// Downloads a file binary and writes it to targetFilePath.
  /// Calls GET /files/{fileId}?download=true with 302 redirect handling.
  Future<File> downloadFile(String fileId, String targetFilePath) async {
    final targetFile = File(targetFilePath);
    await targetFile.parent.create(recursive: true);

    if (CraftnoteCredentialsService.isMockMode) {
      print('[CraftnoteApi] (Mock) downloadFile for $fileId -> $targetFilePath');
      if (targetFilePath.toLowerCase().endsWith('.db')) {
        try {
          // Generate valid SQLite package for realistic mock testing
          final mockDb = await openDatabase(targetFilePath, version: 1, onCreate: (db, v) async {
            await db.execute('CREATE TABLE doors (id INTEGER PRIMARY KEY, doorNumber TEXT, doorAlias TEXT)');
            await db.execute('CREATE TABLE inspections (inspectionId INTEGER PRIMARY KEY, clientName TEXT, jobNumber TEXT, date TEXT)');
            await db.execute('CREATE TABLE inspection_doors (id INTEGER PRIMARY KEY, inspectionId INTEGER, doorId INTEGER, status TEXT, notes TEXT)');
            await db.execute('CREATE TABLE inspection_door_errors (id INTEGER PRIMARY KEY, inspectionDoorId INTEGER, errorCode TEXT, code TEXT, description TEXT, attachments TEXT)');
            await db.execute('CREATE TABLE error_catalog (id INTEGER PRIMARY KEY, errorId INTEGER, code TEXT, description TEXT, category TEXT)');
            await db.insert('inspections', {'inspectionId': 99, 'clientName': 'Mock Kunde', 'jobNumber': '26-15440-AB', 'date': '2026-11-04'});
            await db.insert('doors', {'id': 99, 'doorNumber': 'T-099', 'doorAlias': 'MOCK-DOOR-01'});
            await db.insert('inspection_doors', {'id': 99, 'inspectionId': 99, 'doorId': 99, 'status': 'Open'});
          });
          await mockDb.close();
        } catch (_) {
          // Fallback if sqflite databaseFactory is not initialized in lightweight unit tests
          await targetFile.writeAsBytes(utf8.encode('MOCK_SQLITE_PACKAGE_BINARY_DATA'));
        }
      } else {
        await targetFile.writeAsBytes(utf8.encode('MOCK_SQLITE_PACKAGE_BINARY_DATA'));
      }
      return targetFile;
    }

    final uri = Uri.parse('$_baseUrl/files/$fileId?download=true');
    _logRequest('GET', uri);
    final sw = Stopwatch()..start();

    try {
      final request = http.Request('GET', uri)
        ..headers.addAll(_headers)
        ..followRedirects = true;

      final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 60));
      sw.stop();

      if (streamedResponse.statusCode == 200) {
        final sink = targetFile.openWrite();
        await streamedResponse.stream.pipe(sink);
        await sink.flush();
        await sink.close();
        final bytesCount = await targetFile.length();
        _logResponse('GET', uri, streamedResponse.statusCode, body: '<Binary data: $bytesCount bytes>', elapsedMs: sw.elapsedMilliseconds);
        print('[CraftnoteApi] 📥 Downloaded $fileId ($bytesCount bytes) to $targetFilePath');
        return targetFile;
      } else {
        final responseBody = await streamedResponse.stream.bytesToString();
        _logResponse('GET', uri, streamedResponse.statusCode, body: responseBody, elapsedMs: sw.elapsedMilliseconds);
        throw CraftnoteApiException(
          'Dateidownload für $fileId fehlgeschlagen.',
          statusCode: streamedResponse.statusCode,
          responseBody: responseBody,
        );
      }
    } catch (e) {
      if (e is! CraftnoteApiException) {
        print('[CraftnoteApi] ❌ Connection error on GET $uri: $e');
      }
      rethrow;
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

    final fileSize = await file.length();

    if (CraftnoteCredentialsService.isMockMode) {
      print('[CraftnoteApi] (Mock) uploadFile $fileName ($fileSize bytes) to project $projectId (folderId: $folderId)');
      return CraftnoteFile(
        id: 'CN-FILE-UPLOADED-${DateTime.now().millisecondsSinceEpoch}',
        name: fileName,
        type: 'DOCUMENT',
        size: fileSize,
        creationTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        folderId: folderId,
      );
    }

    final uri = Uri.parse('$_baseUrl/projects/$projectId/files');
    _logRequest('POST', uri, body: 'Multipart payload: fileName="$fileName", size=$fileSize bytes, folderId="$folderId", localPath="${file.path}"');
    final sw = Stopwatch()..start();

    try {
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
      sw.stop();
      final responseBody = await streamedResponse.stream.bytesToString();
      _logResponse('POST', uri, streamedResponse.statusCode, body: responseBody, elapsedMs: sw.elapsedMilliseconds);

      if (streamedResponse.statusCode == 200 || streamedResponse.statusCode == 201) {
        final map = jsonDecode(responseBody) as Map<String, dynamic>;
        print('[CraftnoteApi] 📤 Upload completed successfully for "$fileName" to project $projectId.');
        return CraftnoteFile.fromJson(map);
      } else {
        throw CraftnoteApiException(
          'Fehler beim Hochladen der Datei zu Projekt $projectId.',
          statusCode: streamedResponse.statusCode,
          responseBody: responseBody,
        );
      }
    } catch (e) {
      if (e is! CraftnoteApiException) {
        print('[CraftnoteApi] ❌ Connection error on POST $uri: $e');
      }
      rethrow;
    }
  }

  /// Posts a status notification or chat message into the project feed.
  /// Calls POST /projects/{projectId}/messages
  Future<void> postMessage(String projectId, String message) async {
    if (CraftnoteCredentialsService.isMockMode) {
      print('[CraftnoteApi] (Mock) postMessage to project $projectId: $message');
      return;
    }

    final uri = Uri.parse('$_baseUrl/projects/$projectId/messages');
    final body = jsonEncode({'content': message});

    final headers = Map<String, String>.from(_headers);
    headers['Content-Type'] = 'application/json';

    _logRequest('POST', uri, headers: headers, body: body);
    final sw = Stopwatch()..start();

    try {
      final response = await _client.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 15));
      sw.stop();
      _logResponse('POST', uri, response.statusCode, body: response.body, elapsedMs: sw.elapsedMilliseconds);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw CraftnoteApiException(
          'Fehler beim Senden der Projektbenachrichtigung.',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      if (e is! CraftnoteApiException) {
        print('[CraftnoteApi] ❌ Connection error on POST $uri: $e');
      }
      rethrow;
    }
  }
}
