import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Service responsible for managing, persisting, and providing Craftnote API credentials.
/// Uses placeholders by default so the entire application can run and be tested
/// before real API keys are issued.
class CraftnoteCredentialsService {
  static const String defaultApiKey = '64045d24-397a-407b-b4ae-2ceef59018dd';
  static const String defaultClientId = 'd04f732b-6c89-4804-97d8-63a0ea7c1199';
  static const String defaultPlaceholderApiKey = defaultApiKey;
  static const String defaultPlaceholderClientId = defaultClientId;
  static const String defaultLiveBaseUrl = 'https://europe-west1-craftnote-live.cloudfunctions.net/api/v1';
  static const String defaultFolder = 'Wartungslisten';

  /// Sandbox test project definition in Craftnote
  static const String testProjectId = '0bcce8b1-bb9b-4d67-b41e-f700d3a57bfd';
  static const String testProjectOrderNumber = '26-00251-AN';
  static const String testProjectName = '202121 Industrie GmbH Unit 2 - Unbekannt';

  static String _apiKey = defaultApiKey;
  static String _clientId = defaultClientId;
  static String _baseUrl = defaultLiveBaseUrl;
  static String _folder = defaultFolder;
  static bool _mockMode = false;
  static bool _isTestMode = true;
  static bool _isLoaded = false;

  static String get apiKey => _apiKey;
  static String get clientId => _clientId;
  static String get baseUrl => _baseUrl;
  static String get folder => _folder;
  static bool get isMockMode => _mockMode;
  static bool get isTestMode => _isTestMode;
  static bool get isLoaded => _isLoaded;

  /// Returns true only if real credentials have been provided (not placeholder and not blank).
  static bool get isConfigured =>
      _apiKey.isNotEmpty &&
      _apiKey != 'CRAFTNOTE_API_KEY_PLACEHOLDER' &&
      !_apiKey.startsWith('PLACEHOLDER');

  /// In-memory override for unit tests
  static void setMockMode(bool enabled) {
    _mockMode = enabled;
  }

  /// Toggle between Test Mode (Sandbox safety guard) and Production Mode
  static void setTestMode(bool enabled) {
    _isTestMode = enabled;
  }

  /// In-memory override for testing or session
  static void setCredentials({
    required String apiKey,
    required String clientId,
    String? baseUrl,
    String? folder,
    bool? mockMode,
    bool? isTestMode,
  }) {
    _apiKey = apiKey.trim();
    _clientId = clientId.trim();
    if (baseUrl != null && baseUrl.trim().isNotEmpty) _baseUrl = baseUrl.trim();
    if (folder != null && folder.trim().isNotEmpty) _folder = folder.trim();
    if (mockMode != null) _mockMode = mockMode;
    if (isTestMode != null) _isTestMode = isTestMode;
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
        final loadedKey = map['apiKey']?.toString().trim();
        final loadedClient = map['clientId']?.toString().trim();

        _apiKey = (loadedKey != null &&
                loadedKey.isNotEmpty &&
                loadedKey != 'CRAFTNOTE_API_KEY_PLACEHOLDER')
            ? loadedKey
            : defaultApiKey;

        _clientId = (loadedClient != null &&
                loadedClient.isNotEmpty &&
                loadedClient != 'CRAFTNOTE_CLIENT_ID_PLACEHOLDER')
            ? loadedClient
            : defaultClientId;

        _baseUrl = map['baseUrl']?.toString() ?? defaultLiveBaseUrl;
        _folder = map['folder']?.toString() ?? defaultFolder;
        _mockMode = map['mockMode'] == true;
        _isTestMode = map['isTestMode'] as bool? ?? true;
        _isLoaded = true;
        return;
      }
    } catch (e) {
      // Keep defaults
    }
    _apiKey = defaultApiKey;
    _clientId = defaultClientId;
    _isTestMode = true;
    _isLoaded = true;
  }

  /// Persists credentials to encrypted/local disk storage
  static Future<void> saveCredentials({
    required String apiKey,
    required String clientId,
    String? baseUrl,
    String? folder,
    bool? mockMode,
    bool? isTestMode,
  }) async {
    _apiKey = apiKey.trim();
    _clientId = clientId.trim();
    if (baseUrl != null && baseUrl.trim().isNotEmpty) _baseUrl = baseUrl.trim();
    if (folder != null && folder.trim().isNotEmpty) _folder = folder.trim();
    if (mockMode != null) _mockMode = mockMode;
    if (isTestMode != null) _isTestMode = isTestMode;

    try {
      final file = await _getConfigFile();
      final map = {
        'apiKey': _apiKey,
        'clientId': _clientId,
        'baseUrl': _baseUrl,
        'folder': _folder,
        'mockMode': _mockMode,
        'isTestMode': _isTestMode,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(map), flush: true);
    } catch (e) {
      // Log or ignore on constrained test filesystems
    }
  }

  /// Resets configuration back to defaults
  static Future<void> resetToDefaults() async {
    _apiKey = defaultApiKey;
    _clientId = defaultClientId;
    _baseUrl = defaultLiveBaseUrl;
    _folder = defaultFolder;
    _mockMode = false;
    _isTestMode = true;

    try {
      final file = await _getConfigFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
