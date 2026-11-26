import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' show join, dirname;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

/// Service to load and manage RWA system dropdown options and defaults.
class RwaOptionsService {
  static Map<String, dynamic> _options = {};
  static bool _loaded = false;
  static bool _isTestMode = false;

  static final Map<String, dynamic> _defaultFallbackOptions = {
    "systemType": {
      "options": [
        "elektromotorisch / CO2",
        "CO2",
        "elektromotorisch",
        "pyrotechnisch"
      ],
      "default": "elektromotorisch / CO2"
    },
    "centralType": {
      "options": [
        "JET - FIREJET 165J",
        "Essmann TRZ Plus 2A",
        "TRZ Plus 2A",
        "Velux RWA-Steuerung KFC 210",
        "Velux RWA-Steuerung KFX 214 EU",
        "RZN 4102 K",
        "MZ 2A - 1RG - 1LG",
        "EL 24 / a"
      ],
      "default": ""
    },
    "fireButton": {
      "options": [
        "1",
        "2",
        "2 Auslöseeinheiten CO2",
        "2 Rauchzugs Nottaster",
        "Hauptbedienstelle Orange / KFK 104"
      ],
      "default": "2"
    },
    "smokeDetector": {
      "options": [
        "---",
        "1 Rauchmelder",
        "2 Rauchmelder",
        "Velux 3FA F01 WW (55000-317VLX)",
        "KFA 100"
      ],
      "default": "---"
    },
    "actuator": {
      "options": [
        "1",
        "2",
        "2 Stück CO2 Zylinder",
        "je Kuppel 1 CO2 Zylinder",
        "1 Stück Linearspindelantrieb Windowdrive M2/500",
        "1 Stück Linealspindelantrieb",
        "Kettenantrieb"
      ],
      "default": "1"
    },
    "ventilationButton": {
      "options": [
        "---",
        "1",
        "1 Auf/Zu",
        "nicht vorhanden",
        "nicht vorhanden (deaktiviert)"
      ],
      "default": "---"
    },
    "emergencyPower": {
      "options": [
        "---",
        "2 Stück 12V 1,2 Ah",
        "2 Stück 12V 1,3 Ah (LxHxT - 97x50x48 mm)",
        "2 x 12V 7,2 Ah"
      ],
      "default": "---"
    },
    "co2Bottles": {
      "options": [
        "---",
        "2 Stück 501.105, CO2 Patrone 45 gr., 1/2\" UNF Gew.",
        "1 Stück 501.307, CO2 Flasche 150 gr., M14 x 1,25 Essmann",
        "1 Stück 501.109, CO2 Flasche 500 gr., 1/2\" Gew.",
        "4 Stück 501.110 - 80 gr. 1/2\" UNF Gew.",
        "3 Stück 501.130 - 500 gr. M18x1,5 Gew. mit Steigrohr",
        "1 Stück 501.110 - 80 gr. 1/2\" UNF Gew.",
        "1 Stück 501.130 - 500 gr. M18x1,5 Gew. mit Steigrohr",
        "2 Stück 501.129, CO2 Patrone 300 gr., M18 x 1,5 mit Steigrohr",
        "2 Stück 501.307, CO2 Flasche 150 gr., M14 x 1,25"
      ],
      "default": "---"
    },
    "thermalBottle": {
      "options": [
        "---",
        "2 Stück 501.513, Thermoflasche 68°C F4"
      ],
      "default": "---"
    },
    "rwaFlaps": {
      "options": [
        "---",
        "1",
        "1 x Kuppel",
        "1 Stück RWA Kuppeln",
        "2 Stück RWA Kuppeln",
        "4 x Kuppel",
        "Velux Rauchabzugsfenster GGU SK08 007040D Alu PU Thermo"
      ],
      "default": "1"
    },
    "ventilationFlaps": {
      "options": [
        "---",
        "1",
        "n.v"
      ],
      "default": "---"
    },
    "dampers": {
      "options": [
        "---",
        "1",
        "2 Stück links und rechts am Dachfenster"
      ],
      "default": "---"
    },
    "einrichtungSettings": [
      "RWA-Klappen",
      "Antriebe",
      "Verriegelung",
      "Beschläge",
      "Feuertaster",
      "Lüftungstaster",
      "Rauch/wärmemelder",
      "Rauchabzugszentrale",
      "Notstrombatterie",
      "Anlage ausgelöst",
      "Anlage geschlossen",
      "Fremdansteuerung"
    ]
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

      if (kDebugMode) {
        final tempFile = File(join(externalDir.path, 'temp_rwa_properties.json'));
        if (await tempFile.exists()) {
          final content = await tempFile.readAsString();
          _options = json.decode(content) as Map<String, dynamic>;
          _mergeFallbackDefaults();
          _loaded = true;
          return;
        }
      }

      if (!kDebugMode) {
        final externalFile = File(join(externalDir.path, 'rwa_options.json'));
        if (await externalFile.exists()) {
          final content = await externalFile.readAsString();
          _options = json.decode(content) as Map<String, dynamic>;
          _mergeFallbackDefaults();
          _loaded = true;
          return;
        }
      }

      final projectFile = File(join(Directory.current.path, 'rwa_options.json'));
      if (await projectFile.exists()) {
        final content = await projectFile.readAsString();
        _options = json.decode(content) as Map<String, dynamic>;
        _mergeFallbackDefaults();
        _loaded = true;
        return;
      }
    } catch (e) {
      debugPrint('[RwaOptions] Error loading external options: $e');
    }

    try {
      final content = await rootBundle.loadString('rwa_options.json');
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
        _options[key] = defaultVal is Map
            ? Map<String, dynamic>.from(defaultVal)
            : List<dynamic>.from(defaultVal as List);
      } else {
        final currentEntry = _options[key];
        if (currentEntry is Map && defaultVal is Map) {
          final defaultOpts = defaultVal['options'];
          final currentOpts = currentEntry['options'];
          if (defaultOpts is List && currentOpts is List) {
            final existingSet = currentOpts.map((e) => e.toString()).toSet();
            for (final dOpt in defaultOpts) {
              if (!existingSet.contains(dOpt.toString())) {
                currentOpts.add(dOpt);
              }
            }
          }
        }
      }
    });
  }

  /// Sets test mode with custom mock options.
  static void setTestMode(bool enabled, [Map<String, dynamic>? customOptions]) {
    _isTestMode = enabled;
    if (enabled) {
      _options = customOptions != null
          ? Map<String, dynamic>.from(customOptions)
          : Map<String, dynamic>.from(_defaultFallbackOptions);
      _loaded = true;
    } else {
      _loaded = false;
    }
  }

  /// Returns list of available string options for a specific field name.
  static List<String> getOptions(String fieldName) {
    if (!_loaded && !_isTestMode) {
      load();
    }
    final fieldData = _options[fieldName];
    if (fieldData is List) {
      return fieldData.map((e) => e.toString()).toList();
    }
    if (fieldData is Map && fieldData['options'] is List) {
      return (fieldData['options'] as List).map((e) => e.toString()).toList();
    }
    final fallback = _defaultFallbackOptions[fieldName];
    if (fallback is List) {
      return fallback.map((e) => e.toString()).toList();
    }
    if (fallback is Map && fallback['options'] is List) {
      return (fallback['options'] as List).map((e) => e.toString()).toList();
    }
    return [];
  }

  /// Returns default selection string for a specific field name.
  static String getDefault(String fieldName) {
    if (!_loaded && !_isTestMode) {
      load();
    }
    final fieldData = _options[fieldName];
    if (fieldData is Map && fieldData['default'] != null) {
      return fieldData['default'].toString();
    }
    final fallback = _defaultFallbackOptions[fieldName];
    if (fallback is Map && fallback['default'] != null) {
      return fallback['default'].toString();
    }
    return '';
  }

  /// The standard 12 Einrichtung inspection items.
  static List<String> get einrichtungSettings {
    final list = getOptions('einrichtungSettings');
    if (list.isNotEmpty) return list;
    return List<String>.from(_defaultFallbackOptions['einrichtungSettings'] as List);
  }

  /// Adds a custom option to a field and persists it.
  static Future<void> addCustomOption(String fieldName, String value) async {
    final cleanValue = value.trim();
    if (cleanValue.isEmpty) return;

    if (!_options.containsKey(fieldName)) {
      _options[fieldName] = {"options": <String>[], "default": cleanValue};
    }

    final entry = _options[fieldName];
    if (entry is Map && entry['options'] is List) {
      final opts = entry['options'] as List;
      if (!opts.contains(cleanValue)) {
        opts.add(cleanValue);
        await saveOptions();
      }
    } else if (entry is List) {
      if (!entry.contains(cleanValue)) {
        entry.add(cleanValue);
        await saveOptions();
      }
    }
  }

  /// Saves the current options map to disk.
  static Future<void> saveOptions() async {
    try {
      final dbPath = await getDatabasesPath();
      final externalDir = Directory(join(dirname(dbPath), 'WartungsTool'));
      if (!await externalDir.exists()) {
        await externalDir.create(recursive: true);
      }

      final fileName = kDebugMode ? 'temp_rwa_properties.json' : 'rwa_options.json';
      final file = File(join(externalDir.path, fileName));
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(_options));
    } catch (e) {
      debugPrint('[RwaOptions] Error saving options: $e');
    }
  }

  /// Resets options to defaults.
  static void resetToDefaults() {
    _options = Map<String, dynamic>.from(_defaultFallbackOptions);
    _loaded = true;
  }

  static Map<String, dynamic> get allOptions => Map.unmodifiable(_options);
}
