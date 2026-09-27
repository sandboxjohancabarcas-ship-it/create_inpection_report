import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' show join, dirname;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;
import 'package:wartungstool/models/door.dart';

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
      "options": [
        "?",
        "30/92/9-20 U",
        "34/92/9-24 U",
        "35/92/9-20 U",
        "35/92/9-28 F",
        "35/72/9-20 U",
        "40/92/9-20 U",
        "30/92/9-20 F",
        "35/92/9-20 F",
        "40/92/9-20 F",
        "40/72/9",
        "45/72/9-24 FR",
        "45/92/9-24 F",
        "50/72/9-24 FR",
        "55/72/9-24 FR",
        "60/72/9-24 FR",
        "65/72/9",
        "65/92/9",
        "Rollenschloß",
        "235/24 - 72/65/50/9 FSR",
        "270/24 - 92/35/65/9 FSE",
        "245/24 - 72/35/60 U",
        "235/20 - 72/65/50/9 FSR",
        "30/92/9/24-245U",
        "65/72/8/24-235FR",
        "65/72/9/24-235FR",
        "35/92/9/28-270F",
        "30/72/9/24-245U",
        "30/92/9/24-270Ff",
        "35/92/9/24-270F",
        "65/72/9/20-235FR",
        "30/92/9/28-270F"
      ],
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
    },
    "approvalNumber": {
      "options": ["?"],
      "default": "?"
    },
    "manufacturerNumber": {
      "options": ["?"],
      "default": "?"
    },
    "lintelHeightValue": {
      "options": ["?", "0,5m", "1m", "2m", "3m", "4m", "5m", ">5m"],
      "default": "?"
    },
    "lintelHeightInsideValue": {
      "options": ["?", "0,5m", "1m", "2m", "3m", "4m", "5m", ">5m"],
      "default": "?"
    },
    "lintelHeightOutsideValue": {
      "options": ["?", "0,5m", "1m", "2m", "3m", "4m", "5m", ">5m"],
      "default": "?"
    }
  };

  /// Ensures that options have been loaded from external or internal assets.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    await load();
  }

  /// Loads options from the external JSON file or falls back to the asset bundle.
  static Future<void> load() async {
    if (_isTestMode) return;
    try {
      final dbPath = await getDatabasesPath();
      final externalFile = File(join(dirname(dbPath), 'WartungsTool', 'door_options.json'));
      
      if (await externalFile.exists()) {
        print('[DoorOptions] Found external JSON at ${externalFile.path}. Loading...');
        final content = await externalFile.readAsString();
        _options = json.decode(content) as Map<String, dynamic>;
        _mergeFallbackDefaults();
        _loaded = true;
        return;
      }

      final projectFile = File(join(Directory.current.path, 'door_options.json'));
      if (await projectFile.exists()) {
        print('[DoorOptions] Found project JSON at ${projectFile.path}. Loading...');
        final content = await projectFile.readAsString();
        _options = json.decode(content) as Map<String, dynamic>;
        _mergeFallbackDefaults();
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
      _mergeFallbackDefaults();
      _loaded = true;
      return;
    } catch (e) {
      print('[DoorOptions] Error loading asset options: $e');
    }

    print('[DoorOptions] Using hardcoded fallback options.');
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
              } else if (opt is Map) {
                if (!currentOpts.any((e) => e is Map && e['value'] == opt['value'])) {
                  currentOpts.add(opt);
                }
              }
            }
          }
        }
      }
    });

    // Remove legacy / erroneous '0,5' and '0.5' without 'm' from lintel height dropdowns
    const lintelKeys = ['lintelHeightValue', 'lintelHeightInsideValue', 'lintelHeightOutsideValue'];
    for (final k in lintelKeys) {
      if (_options.containsKey(k) && _options[k]['options'] is List) {
        final list = _options[k]['options'] as List;
        list.removeWhere((e) => e.toString().trim() == '0,5' || e.toString().trim() == '0.5');
        list.sort(compareOptions);
      }
    }

    if (_options.containsKey('lockDimensions') && _options['lockDimensions']['options'] is List) {
      final list = _options['lockDimensions']['options'] as List;
      list.removeWhere((e) =>
          e.toString().trim() == 'Schloßmaße/Stulp' ||
          e.toString().trim() == 'DM/Abst./Nuß-Stulp');
    }
  }

  /// Comparison function that places '?' first and orders numeric/meter items ascendingly.
  static int compareOptions(dynamic a, dynamic b) {
    final strA = (a is Map ? a['value'] : a)?.toString() ?? '';
    final strB = (b is Map ? b['value'] : b)?.toString() ?? '';
    if (strA == strB) return 0;
    if (strA == '?') return -1;
    if (strB == '?') return 1;

    final numA = _extractNumeric(strA);
    final numB = _extractNumeric(strB);
    if (numA != null && numB != null) {
      final comp = numA.compareTo(numB);
      if (comp != 0) return comp;
    }
    return strA.toLowerCase().compareTo(strB.toLowerCase());
  }

  static double? _extractNumeric(String s) {
    final clean = s.replaceAll('>', '').replaceAll('m', '').replaceAll('M', '').replaceAll(',', '.').trim();
    final parsed = double.tryParse(clean);
    if (parsed != null && s.startsWith('>')) {
      return parsed + 0.001;
    }
    return parsed;
  }

  static bool _isTestMode = false;

  /// Resets the load status (useful for unit tests).
  static void reset() {
    _options = {};
    _loaded = false;
    _isTestMode = false;
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
      if (key.startsWith('lintelHeight')) {
        currentList.sort(compareOptions);
      }
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
      final item = currentList[i];
      if (item is Map) {
        if (item['value']?.toString().trim().toLowerCase() == oldVal.toLowerCase()) {
          index = i;
          break;
        }
      } else {
        if (item.toString().trim().toLowerCase() == oldVal.toLowerCase()) {
          index = i;
          break;
        }
      }
    }

    if (index != -1) {
      final existingItem = currentList[index];
      if (existingItem is Map) {
        currentList[index] = {
          'value': newVal,
          'label': newVal,
        };
      } else {
        currentList[index] = newVal;
      }
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
    final initialLength = currentList.length;
    
    currentList.removeWhere((item) {
      if (item is Map) {
        return item['value']?.toString().trim().toLowerCase() == val.toLowerCase();
      }
      return item.toString().trim().toLowerCase() == val.toLowerCase();
    });

    if (currentList.length < initialLength) {
      _options[key]['options'] = currentList;
      return true;
    }
    return false;
  }

  /// Saves current options to external JSON file on disk.
  static Future<bool> saveOptions() async {
    try {
      final dbPath = await getDatabasesPath();
      final externalDir = Directory(join(dirname(dbPath), 'WartungsTool'));
      if (!await externalDir.exists()) {
        await externalDir.create(recursive: true);
      }
      final externalFile = File(join(externalDir.path, 'door_options.json'));
      final encoder = const JsonEncoder.withIndent('  ');
      final content = encoder.convert(_options);
      await externalFile.writeAsString(content);
      print('[DoorOptions] Saved options to ${externalFile.path}');

      if (!_isTestMode) {
        final projectFile = File(join(Directory.current.path, 'door_options.json'));
        if (await projectFile.exists()) {
          await projectFile.writeAsString(content);
          print('[DoorOptions] Saved options to project root ${projectFile.path}');
        }
      }
      return true;
    } catch (e) {
      print('[DoorOptions] Error saving options to file: $e');
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

  /// Syncs any custom non-empty property values from a [Door] into master dropdown options.
  static void syncFromDoor(Door door) {
    final Map<String, String> dropdownValues = {
      'approvalNumber': door.approvalNumber,
      'manufacturerNumber': door.manufacturerNumber,
      'manufacturer': door.manufacturer,
      'doorType': door.doorType,
      'material': door.material,
      'dinConfiguration': door.dinConfiguration,
      'closingSequenceSystem': door.closingSequenceSystem,
      'lockDimensions': door.lockDimensions,
      'accessControl': door.accessControl,
      'fittingType': door.fittingType,
      'panicFunction': door.panicFunction,
    };

    for (final entry in dropdownValues.entries) {
      final val = entry.value.trim();
      if (val.isNotEmpty && val != '?' && val.toLowerCase() != 'nein' && val != '(leer)') {
        addOption(entry.key, val);
      }
    }
  }

  /// Scans all doors stored in [db] and registers any unlisted custom dropdown options.
  static Future<void> syncFromDatabase(dynamic db) async {
    if (_isTestMode) return;
    try {
      final List<Map<String, dynamic>> rows = await db.query('doors');
      for (final row in rows) {
        final door = Door.fromMap(row);
        syncFromDoor(door);
      }
      await saveOptions();
    } catch (e) {
      print('[DoorOptions] Error syncing options from database: $e');
    }
  }
}
