// logic to be implemented in gaeb_export_service.dart

class KinchiApiService {
  final String baseUrl = "https://api.dev.kinchi.actihosting.de/api";
  final String authUrl = "https://keycloak.dev.kinchi.actihosting.de/realms/kinchi/protocol/openid-connect/token";
  String? _token;

  // 1. Authentication
  // Maps to kinchi_client.py:login
  Future<void> authenticate(String username, String password) async {
    // Post to authUrl with 'grant_type': 'password', 'client_id': 'idm'
    // Store response['access_token'] in _token
  }

  // 2. Data Flattening Helper
  // Maps to kinchi_client.py:_extract_data
  // Essential because Strapi v4 nests everything in 'data' and 'attributes'
  dynamic flattenStrapiResponse(dynamic json) {
    if (json is List) return json.map((i) => flattenStrapiResponse(i)).toList();
    if (json is Map && json.containsKey('attributes')) {
      var attrs = json['attributes'];
      var id = json['id'];
      attrs['id'] = id; // Ensure ID is preserved at the top level
      return flattenStrapiResponse(attrs);
    }
    // Recursive cleaning for nested objects
    return json;
  }

  // 3. Document Upload Lifecycle
  // Maps to kinchi_client.py:upload_and_create_document
  Future<int> uploadGaebFile(String filePath, int directoryId) async {
    // A. Upload physical file
    // Use http.MultipartRequest('POST', '$baseUrl/upload')
    // Get the mediaId from the response

    // B. Create Document Record
    // POST to '$baseUrl/documents' with payload:
    // { "data": { "file": [mediaId], "directory": directoryId } }
    
    // Return the Document Record ID
  }

  // 4. Orchestrated Deletion
  // Maps to kinchi_client.py:delete_uploaded_document
  Future<void> purgeDocument(int documentId, {bool deletePhysicalFile = true}) async {
    if (deletePhysicalFile) {
      // 1. GET document with populate=file to find media IDs
      // 2. For each file ID: DELETE '$baseUrl/upload/files/$fileId'
    }
    
    // 3. DELETE '$baseUrl/documents/$d                ocumentId'
  }
}
