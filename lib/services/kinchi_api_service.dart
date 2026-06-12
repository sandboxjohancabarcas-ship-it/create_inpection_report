import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class KinchiApiService {
  final String baseUrl = "https://api.dev.kinchi.actihosting.de/api";
  final String authUrl = "https://keycloak.dev.kinchi.actihosting.de/realms/kinchi/protocol/openid-connect/token";
  String? _token;

  /// Exchanges credentials for a JWT via Keycloak
  Future<bool> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse(authUrl),
        body: {
          'grant_type': 'password',
          'client_id': 'idm',
          'username': username,
          'password': password,
          'scope': 'openid',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['access_token'];
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Recursively flattens Strapi v4 'data' and 'attributes' envelopes
  dynamic _flatten(dynamic json) {
    if (json is List) return json.map((i) => _flatten(i)).toList();
    if (json is Map && json.containsKey('data')) return _flatten(json['data']);
    if (json is Map && json.containsKey('attributes')) {
      final Map<String, dynamic> flattened = Map<String, dynamic>.from(json['attributes']);
      if (json.containsKey('id')) flattened['id'] = json['id'];
      flattened.forEach((key, value) => flattened[key] = _flatten(value));
      return flattened;
    }
    return json;
  }

  /// Fetches available directories from the KINCHI API
  Future<List<dynamic>> getDirectories() async {
    if (_token == null) throw Exception("Not authenticated");

    final response = await http.get(
      Uri.parse("$baseUrl/directories"),
      headers: {'Authorization': 'Bearer $_token'},
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      return _flatten(jsonDecode(response.body)) as List<dynamic>;
    }
    throw Exception("Failed to fetch directories: ${response.body}");
  }

  /// High-level routine: 
  /// 1. Uploads physical file 
  /// 2. Links it to a directory record
  /// Returns the Document Record ID
  Future<int> uploadGaebFile(String filePath, int directoryId) async {
    if (_token == null) throw Exception("Not authenticated");

    // A. Upload physical file to Media Library
    final uploadUri = Uri.parse("$baseUrl/upload");
    final request = http.MultipartRequest('POST', uploadUri);
    request.headers['Authorization'] = 'Bearer $_token';
    
    final file = await http.MultipartFile.fromPath(
      'files', 
      filePath,
      filename: p.basename(filePath),
    );
    request.files.add(file);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception("Upload failed: ${response.body}");
    }

    // Strapi returns a List of Media objects
    final List<dynamic> mediaList = jsonDecode(response.body);
    if (mediaList.isEmpty) throw Exception("No media ID returned");
    final int mediaId = mediaList[0]['id'];

    // B. Create Document Record linking file to directory
    final docResponse = await http.post(
      Uri.parse("$baseUrl/documents"),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "data": {
          "file": [mediaId],
          "directory": directoryId,
        }
      }),
    );

    if (docResponse.statusCode != 200 && docResponse.statusCode != 201) {
      throw Exception("Document record creation failed: ${docResponse.body}");
    }

    final result = _flatten(jsonDecode(docResponse.body));
    return result['id'] as int;
  }
}