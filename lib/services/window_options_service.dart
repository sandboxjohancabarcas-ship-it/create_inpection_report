import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' show join, dirname;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

/// Service to load and manage window dropdown options and defaults.
class WindowOptionsService {
  static Map<String, dynamic> _options = {};
  static bool _loaded = false;
  static bool _isTestMode = false;

  static final Map<String, dynamic> _defaultFallbackOptions = {
    "floor": {
      "options": ["?", "EG", "1.OG", "2.OG", "3.OG", "4.OG", "5.OG", "UG", "KG"],
      "default": "?"
    },
    "roomNumber": {
      "options": ["?", ".1.02", ".1.03", ".1.04", ".1.07", ".1.08", ".1.09", ".1.10", "Flur", "Herren WC", "Dusche Damen", "Treppenhaus"],
      "default": "?"
    },
    "roomDesignation": {
      "options": [
        "?",
        "AiP",
        "Aktenraum",
        "Asservatenkammer",
        "Ausnüchterungszelle",
        "Auswertung/Aktenraum",
        "Basisdienst",
        "Besprechungsraum",
        "Büro",
        "Damen WC",
        "DGF",
        "DGL",
        "DGOA",
        "Dusche Damen",
        "Empfang",
        "Flur",
        "Garderobe",
        "Gewahrsam",
        "Herren Dusche",
        "Herren WC",
        "Kopierraum",
        "Küche",
        "Lager",
        "Pausenraum",
        "Serverraum",
        "Sozialraum",
        "Teeküche",
        "Treppenhaus",
        "Umkleide",
        "Warteraum",
        "WC"
      ],
      "default": "?"
    },
    "windowType": {
      "options": [
        "?",
        "DKL",
        "DKR",
        "Kippfenster",
        "Festverglasung",
        "Drehfenster L",
        "Drehfenster R",
        "Oberlicht",
        "Schiebefenster"
      ],
      "default": "?"
    },
    "material": {
      "options": ["?", "Alu", "Kunststoff", "Holz", "Holz/Alu", "Stahl"],
      "default": "?"
    },
    "wingDimensions": {
      "options": [
        "?",
        "920x480",
        "1180x750",
        "1200x1550",
        "1230x450",
        "1230x770",
        "1250x760",
        "1280x460",
        "1280x1760",
        "1300x1550",
        "1310x480",
        "2430x750"
      ],
      "default": "?"
    },
    "fittings": {
      "options": [
        "?",
        "Schüco",
        "GEZE",
        "Hueck",
        "Roto",
        "Siegenia",
        "Winkhaus",
        "GU (Gretsch-Unitas)",
        "Hautau",
        "Maco"
      ],
      "default": "?"
    }
  };

  /// Ensures that options have been loaded from external or internal assets.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    await load();
  }

  /// Loads options from dynamic temp file (in debug mode), external JSON file, or falls back to defaults.
  static Future<void> load() async {
    if (_isTestMode) return;
    try {
      final dbPath = await getDatabasesPath();
      final externalDir = Directory(join(dirname(dbPath), 'WartungsTool'));

      // In debug mode, check for dynamically modified temp options first
      if (kDebugMode) {
        final tempFile = File(join(externalDir.path, 'temp_window_properties.json'));
        if (await tempFile.exists()) {
          final content = await tempFile.readAsString();
          _options = json.decode(content) as Map<String, dynamic>;
          _mergeFallbackDefaults();
          _loaded = true;
          return;
        }
      }

      // In production mode, check for persistent external window_options.json
      if (!kDebugMode) {
        final externalFile = File(join(externalDir.path, 'window_options.json'));
        if (await externalFile.exists()) {
          final content = await externalFile.readAsString();
          _options = json.decode(content) as Map<String, dynamic>;
          _mergeFallbackDefaults();
          _loaded = true;
          return;
        }
      }

      // Read default project JSON
      final projectFile = File(join(Directory.current.path, 'window_options.json'));
      if (await projectFile.exists()) {
        final content = await projectFile.readAsString();
        _options = json.decode(content) as Map<String, dynamic>;
        _mergeFallbackDefaults();
        _loaded = true;
        return;
      }
    } catch (e) {
      print('[WindowOptions] Error loading external options: $e');
    }

    try {
      final content = await rootBundle.loadString('window_options.json');
      _options = json.decode(content) as Map<String, dynamic>;
      _mergeFallbackDefaults();
      _loaded = true;
      return;
    } catch (_) {}

    _options = Map<String, dynamic>.from(_defaultFallbackOptions);
    _loaded = true;
  }

  static void _mergeFallbackDefaults() {
    _defaultFallbackOptions.forEach((key, defaultVal) {
      if (!_options.containsKey(key)) {
        _options[key] = Map<String, dynamic>.from(defaultVal);
      } else {
        final currentEntry = _options[key];
        if (currentEntry is Map && defaultVal is Map) {
          final defaultOpts = defaultVal['options'];
          final currentOpts = currentEntry['options'];
          if (defaultOpts is List && currentOpts is List) {
            for (final opt in defaultOpts) {
              if (opt is String) {
                if (!currentOpts.any((e) => e.toString().toLowerCase() == opt.toLowerCase())) {
                  currentOpts.add(opt);
                }
              }
            }
          }
        }
      }
    });
  }

  /// Sets custom mock options (useful for unit tests).
  static void setMockOptions(Map<String, dynamic> mockData) {
    _options = mockData;
    _loaded = true;
    _isTestMode = true;
  }

  /// Adds a new option value to the list for a given property key if it doesn't already exist.
  static void addOption(String key, String value) {
    final val = value.trim();
    if (val.isEmpty || val == '?') return;

    if (!_loaded || _options.isEmpty) {
      _options = Map<String, dynamic>.from(_defaultFallbackOptions);
      _loaded = true;
    }

    if (!_options.containsKey(key)) {
      _options[key] = {
        "options": ["?", val],
        "default": "?"
      };
      return;
    }

    final List<dynamic> currentList = List.from(_options[key]['options'] ?? []);
    final exists = currentList.any((e) => e.toString().trim().toLowerCase() == val.toLowerCase());
    if (!exists) {
      currentList.add(val);
      _options[key]['options'] = currentList;
    }
  }

  /// Updates/renames an existing option value for a given property key.
  static bool updateOption(String key, String oldValue, String newValue) {
    final oldVal = oldValue.trim();
    final newVal = newValue.trim();
    if (newVal.isEmpty || !_options.containsKey(key)) return false;

    final List<dynamic> currentList = List.from(_options[key]['options'] ?? []);
    int index = -1;
    for (int i = 0; i < currentList.length; i++) {
      if (currentList[i].toString().trim().toLowerCase() == oldVal.toLowerCase()) {
        index = i;
        break;
      }
    }

    if (index != -1) {
      currentList[index] = newVal;
      _options[key]['options'] = currentList;
      return true;
    }
    return false;
  }

  /// Removes an option value from a given property key.
  static bool removeOption(String key, String value) {
    final val = value.trim();
    if (val.isEmpty || !_options.containsKey(key)) return false;

    final List<dynamic> currentList = List.from(_options[key]['options'] ?? []);
    final beforeLength = currentList.length;
    currentList.removeWhere((e) => e.toString().trim().toLowerCase() == val.toLowerCase());

    if (currentList.length < beforeLength) {
      _options[key]['options'] = currentList;
      return true;
    }
    return false;
  }

  /// Persists the current options to storage.
  static Future<bool> save() async {
    if (_options.isEmpty) return false;
    try {
      final dbPath = await getDatabasesPath();
      final externalDir = Directory(join(dirname(dbPath), 'WartungsTool'));
      if (!await externalDir.exists()) {
        await externalDir.create(recursive: true);
      }
      final encoder = const JsonEncoder.withIndent('  ');
      final content = encoder.convert(_options);

      if (kDebugMode || _isTestMode) {
        final tempFile = File(join(externalDir.path, 'temp_window_properties.json'));
        await tempFile.writeAsString(content);
      } else {
        final externalFile = File(join(externalDir.path, 'window_options.json'));
        await externalFile.writeAsString(content);
      }
      return true;
    } catch (e) {
      print('[WindowOptions] Error saving options to file: $e');
      return false;
    }
  }

  /// Gets raw options for a given key.
  static List<dynamic> getOptions(String key) {
    if (!_loaded || !_options.containsKey(key)) {
      return _defaultFallbackOptions[key]?['options'] ?? [];
    }
    return _options[key]['options'] ?? [];
  }

  /// Gets default fallback value for a given key.
  static dynamic getDefault(String key) {
    if (!_loaded || !_options.containsKey(key)) {
      return _defaultFallbackOptions[key]?['default'];
    }
    return _options[key]['default'];
  }

  /// Helper to get options as a list of strings.
  static List<String> getStringOptions(String key) {
    final raw = getOptions(key);
    final List<String> list = [];
    for (final item in raw) {
      if (item is String) {
        list.add(item);
      } else if (item != null) {
        list.add(item.toString());
      }
    }
    if (!list.contains('?')) {
      list.insert(0, '?');
    }
    return list;
  }

  /// Resets options to default fallback options.
  static void resetToDefaults() {
    _options = Map<String, dynamic>.from(_defaultFallbackOptions);
    _loaded = true;
  }
}

