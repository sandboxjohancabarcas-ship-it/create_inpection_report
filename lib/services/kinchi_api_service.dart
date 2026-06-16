import 'dart:convert';
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
    if (json == null) return null;
    if (json is List) return json.map((i) => _flatten(i)).toList();
    if (json is! Map) return json;

    // Handle Strapi v4 'data' envelope
    if (json is Map && json.containsKey('data')) return _flatten(json['data']);

    // Handle Strapi v4 item structure: { id: X, attributes: { ... } }
    if (json is Map && json.containsKey('attributes')) {
      final Map<String, dynamic> flattened = Map<String, dynamic>.from(json['attributes']);
      if (json.containsKey('id')) {
        var rawId = json['id'];
        flattened['id'] = rawId is String ? int.tryParse(rawId) ?? rawId : rawId;
      }
      // Recursively flatten nested maps
      flattened.updateAll((key, value) => _flatten(value));
      return flattened;
    }
    return json;
  }

  /// Fetches available directories from the KINCHI API
  /// Handles pagination to retrieve all directories.
  Future<List<dynamic>> getDirectories() async {
    if (_token == null) throw Exception("Not authenticated");

    List<dynamic> allDirectories = [];
    int page = 1; // Strapi pagination usually starts at 1
    const int pageSize = 100; // Fetch a larger page size to reduce API calls

    while (true) {
      final uri = Uri.parse("$baseUrl/directories").replace(queryParameters: {
        'pagination[page]': page.toString(),
        'pagination[pageSize]': pageSize.toString(),
      });

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decodedBody = jsonDecode(response.body);
        final dynamic flattened = _flatten(decodedBody);
        
        // Normalize data to a list and add to results
        if (flattened is List) {
          allDirectories.addAll(flattened);
        } else if (flattened != null) {
          allDirectories.add(flattened);
        }

        // Safely extract pagination metadata only if decodedBody is a Map
        if (decodedBody is Map && decodedBody.containsKey('meta')) {
          final pagination = decodedBody['meta']?['pagination'];
          final int? pageCount = pagination?['pageCount'];

          if (pageCount == null || page >= pageCount) break;
          page++;
        } else {
          break; // No pagination metadata available, assume single page
        }
      } else {
        throw Exception("Failed to fetch directories: ${response.body}");
      }
    }
    return allDirectories;
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