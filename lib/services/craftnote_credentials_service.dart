import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Service responsible for managing, persisting, and providing Craftnote API credentials.
/// Uses placeholders by default so the entire application can run and be tested
/// before real API keys are issued.
class CraftnoteCredentialsService {
  static const String defaultPlaceholderApiKey = 'CRAFTNOTE_API_KEY_PLACEHOLDER';
  static const String defaultPlaceholderClientId = 'CRAFTNOTE_CLIENT_ID_PLACEHOLDER';
  static const String defaultLiveBaseUrl = 'https://europe-west1-craftnote-live.cloudfunctions.net/api/v1';
  static const String defaultFolder = '01_Wartungsberichte';

  static String _apiKey = defaultPlaceholderApiKey;
  static String _clientId = defaultPlaceholderClientId;
  static String _baseUrl = defaultLiveBaseUrl;
  static String _folder = defaultFolder;
  static bool _mockMode = false;
  static bool _isLoaded = false;

  static String get apiKey => _apiKey;
  static String get clientId => _clientId;
  static String get baseUrl => _baseUrl;
  static String get folder => _folder;
  static bool get isMockMode => _mockMode;
  static bool get isLoaded => _isLoaded;

  /// Returns true only if real credentials have been provided (not placeholder and not blank).
  static bool get isConfigured =>
      _apiKey.isNotEmpty &&
      _apiKey != defaultPlaceholderApiKey &&
      !_apiKey.startsWith('PLACEHOLDER');

  /// In-memory override for unit tests
  static void setMockMode(bool enabled) {
    _mockMode = enabled;
  }

  /// In-memory override for testing or session
  static void setCredentials({
    required String apiKey,
    required String clientId,
    String? baseUrl,
    String? folder,
    bool? mockMode,
  }) {
    _apiKey = apiKey.trim();
    _clientId = clientId.trim();
    if (baseUrl != null && baseUrl.trim().isNotEmpty) _baseUrl = baseUrl.trim();
    if (folder != null && folder.trim().isNotEmpty) _folder = folder.trim();
    if (mockMode != null) _mockMode = mockMode;
    _isLoaded = true;
  }

  /// Resolves the configuration file path
  static Future<File> _getConfigFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final configDir = Directory('${dir.path}/WartungsTool');
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }
      return File('${configDir.path}/craftnote_config.json');
    } catch (_) {
      // Fallback to local directory (e.g. CLI or test environment)
      return File('craftnote_config.json');
    }
  }

  /// Loads persisted credentials from disk
  static Future<void> loadCredentials() async {
    try {
      final file = await _getConfigFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        _apiKey = map['apiKey']?.toString() ?? defaultPlaceholderApiKey;
        _clientId = map['clientId']?.toString() ?? defaultPlaceholderClientId;
        _baseUrl = map['baseUrl']?.toString() ?? defaultLiveBaseUrl;
        _folder = map['folder']?.toString() ?? defaultFolder;
        _mockMode = map['mockMode'] == true;
        _isLoaded = true;
        return;
      }
    } catch (e) {
      // Keep defaults
    }
    _isLoaded = true;
  }

  /// Persists credentials to encrypted/local disk storage
  static Future<void> saveCredentials({
    required String apiKey,
    required String clientId,
    String? baseUrl,
    String? folder,
    bool? mockMode,
  }) async {
    _apiKey = apiKey.trim();
    _clientId = clientId.trim();
    if (baseUrl != null && baseUrl.trim().isNotEmpty) _baseUrl = baseUrl.trim();
    if (folder != null && folder.trim().isNotEmpty) _folder = folder.trim();
    if (mockMode != null) _mockMode = mockMode;

    try {
      final file = await _getConfigFile();
      final map = {
        'apiKey': _apiKey,
        'clientId': _clientId,
        'baseUrl': _baseUrl,
        'folder': _folder,
        'mockMode': _mockMode,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(map), flush: true);
    } catch (e) {
      // Log or ignore on constrained test filesystems
    }
  }

  /// Resets configuration back to defaults
  static Future<void> resetToDefaults() async {
    _apiKey = defaultPlaceholderApiKey;
    _clientId = defaultPlaceholderClientId;
    _baseUrl = defaultLiveBaseUrl;
    _folder = defaultFolder;
    _mockMode = false;

    try {
      final file = await _getConfigFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
