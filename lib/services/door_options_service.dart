import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' show join, dirname;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

/// Service to load and manage door options and defaults from a JSON file.
class DoorOptionsService {
  static Map<String, dynamic> _options = {};
  static bool _loaded = false;

  static final Map<String, dynamic> _defaultFallbackOptions = {
    "doorType": {
      "options": ["?", "MZT-1", "MZT-2", "T30-1", "T30-2", "T30-1 RS", "T30-2 RS", "T90-1", "T90-2", "T90-1 RS", "T90-2 RS", "RS-1", "RS-2", "WK-1 / RC-1", "WK-2 / RC-2", "FB-1", "FB-2", "FB-3", "FB-4"],
      "default": "?"
    },
    "wingCount": {
      "options": [1, 2, 3],
      "default": 1
    },
    "material": {
      "options": ["?", "Alurohrrahmen", "Stahlrohrrahmen", "Holzblatt", "Holz/Glas", "Stahlblech", "Stahlblech/Glas", "Kunststoff"],
      "default": "?"
    },
    "manufacturer": {
      "options": ["?", "Schüco", "Schüco ADS 80", "Schüco ADS 65.Ni SP", "Hueck-Alu", "Schüco Jansen-Stahl", "Forster Fuego-St.", "Forster Presto-St.", "MBB-Stahl", "RP-Stahl", "Hörmann-St.", "Teckentrup-St.", "Novoferm-St.", "Schörghuber-Holz", "Herholz-Holz", "Specht-Holz", "Schwarze-Stahl", "Hoba-Holz"],
      "default": "?"
    },
    "dinConfiguration": {
      "options": ["?", "DIN L", "DIN R", "DIN L auswärts", "DIN R auswärts", "DIN L einwärts", "DIN R einwärts", "DIN L aus St-Flg. Ver.", "DIN R aus St-Flg. Ver.", "DIN L ein St-Flg. Ver.", "DIN R ein St-Flg. Ver."],
      "default": "?"
    },
    "closerType": {
      "options": [
        {"value": "?", "label": "?"},
        {"value": "Nein", "label": "Kein Schließer"},
        {"value": "Do TS 98", "label": "Dorma TS 98"},
        {"value": "Do TS 93", "label": "Dorma TS 93"},
        {"value": "Do TS 99", "label": "Dorma TS 99"},
        {"value": "Do TS 92", "label": "Dorma TS 92"},
        {"value": "Do TS92 basic", "label": "Dorma TS 92 Basic"},
        {"value": "Do ITS 96 integr.", "label": "Dorma ITS 96 Integriert"},
        {"value": "Do TS 97 contur", "label": "Dorma TS 97 Contur"},
        {"value": "Do TS 83", "label": "Dorma TS 83"},
        {"value": "Do TS 89", "label": "Dorma TS 89"},
        {"value": "Do TS 73V", "label": "Dorma TS 73V"},
        {"value": "Do TS 72", "label": "Dorma TS 72"},
        {"value": "Do TS 71", "label": "Dorma TS 71"},
        {"value": "Do BTS 75 V", "label": "Dorma Bodenschließer BTS 75 V"},
        {"value": "Do BTS 80", "label": "Dorma Bodenschließer BTS 80"},
        {"value": "Do ED 200", "label": "Dorma ED 200 Drehflügelantrieb"},
        {"value": "Do ED 250", "label": "Dorma ED 250 Drehflügelantrieb"},
        {"value": "Ge TS 3000", "label": "GEZE TS 3000"},
        {"value": "Ge TS 4000", "label": "GEZE TS 4000"},
        {"value": "Ge TS 5000", "label": "GEZE TS 5000"}
      ],
      "default": "?"
    },
    "closingSequenceSystem": {
      "options": ["?", "Nein", "EMF", "EMR", "GSR mech.", "GSR-EMF 1", "GSR-EMF 2", "GSR-EMF 1G", "GSR-EMR 1", "GSR-EMR 2", "GSR-EMR 1G", "GSR/BG", "GSR-EMF 2/BG", "GSR-EMR 2/BG", "GSR-RF1", "G-N", "G-EMF", "G-EMR", "GSR-RF 1"],
      "default": "?"
    },
    "lockDimensions": {
      "options": ["?", "30/92/9-20 U", "34/92/9-24 U", "35/92/9-20 U", "35/92/9-28 F", "35/72/9-20 U", "40/92/9-20 U", "30/92/9-20 F", "35/92/9-20 F", "40/92/9-20 F", "40/72/9", "45/72/9-24 FR", "45/92/9-24 F", "50/72/9-24 FR", "55/72/9-24 FR", "60/72/9-24 FR", "65/72/9", "65/92/9", "MfV-35/92/10-24 U", "SVP", "Motorschloss"],
      "default": "?"
    },
    "escapeDoorControl": {
      "options": ["Nein", "Ja ?", "GFS Einhand", "GFS schwenk", "DORMA", "GEZE", "effeff"],
      "default": "Nein"
    },
    "accessControl": {
      "options": ["Nein", "Ja ?", "KABA Evolo", "CES", "U&Z"],
      "default": "Nein"
    },
    "fittingType": {
      "options": ["Nein", "D-D", "D-K", "D-Stoßgriff", "Blind", "AP-Pushbar", "AP-Touchbar"],
      "default": "Nein"
    },
    "panicFunction": {
      "options": ["Nein", "B", "E", "D", "C", "SVP2000", "M-SVP2200", "M-SVP2000", "SVP5000", "SVP6000"],
      "default": "Nein"
    }
  };

  /// Ensures that options have been loaded from external or internal assets.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    await load();
  }

  /// Loads options from the external JSON file or falls back to the asset bundle.
  static Future<void> load() async {
    try {
      final dbPath = await getDatabasesPath();
      final externalFile = File(join(dirname(dbPath), 'WartungsTool', 'door_options.json'));
      
      if (await externalFile.exists()) {
        print('[DoorOptions] Found external JSON at ${externalFile.path}. Loading...');
        final content = await externalFile.readAsString();
        _options = json.decode(content) as Map<String, dynamic>;
        _loaded = true;
        return;
      }
    } catch (e) {
      print('[DoorOptions] Error loading external options: $e');
    }

    try {
      print('[DoorOptions] Loading options from internal assets...');
      final content = await rootBundle.loadString('door_options.json');
      _options = json.decode(content) as Map<String, dynamic>;
      _loaded = true;
      return;
    } catch (e) {
      print('[DoorOptions] Error loading asset options: $e');
    }

    print('[DoorOptions] Using hardcoded fallback options.');
    _options = _defaultFallbackOptions;
    _loaded = true;
  }

  /// Resets the load status (useful for unit tests).
  static void reset() {
    _options = {};
    _loaded = false;
  }

  /// Sets custom mock options (useful for unit tests).
  static void setMockOptions(Map<String, dynamic> mockData) {
    _options = mockData;
    _loaded = true;
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
    return raw.map((e) => e.toString()).toList();
  }

  /// Helper to get options as a list of integers.
  static List<int> getIntOptions(String key) {
    final raw = getOptions(key);
    return raw.map((e) {
      if (e is int) return e;
      return int.tryParse(e.toString()) ?? 0;
    }).toList();
  }

  /// Helper to get options as value-label map pairs.
  static List<Map<String, String>> getMapOptions(String key) {
    final raw = getOptions(key);
    return raw.map((e) {
      if (e is Map) {
        return {
          'value': e['value']?.toString() ?? '',
          'label': e['label']?.toString() ?? '',
        };
      }
      return {
        'value': e.toString(),
        'label': e.toString(),
      };
    }).toList();
  }
}
