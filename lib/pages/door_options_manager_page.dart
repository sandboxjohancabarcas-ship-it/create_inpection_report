import 'package:flutter/material.dart';
import '../services/door_options_service.dart';
import '../services/window_options_service.dart';

/// Page for Managers to view, search, create, edit, and delete dropdown options (CRUD)
/// for both Doors and Windows with full visual and data separation.
class DoorOptionsManagerPage extends StatefulWidget {
  final String initialAssetType;

  const DoorOptionsManagerPage({
    super.key,
    this.initialAssetType = 'door',
  });

  @override
  State<DoorOptionsManagerPage> createState() => _DoorOptionsManagerPageState();
}

class _DoorOptionsManagerPageState extends State<DoorOptionsManagerPage> {
  static const Map<String, String> _doorCategories = {
    'doorType': 'Türart',
    'material': 'Material',
    'manufacturer': 'Hersteller',
    'dinConfiguration': 'DIN-Konfiguration',
    'closerType': 'Schließerart',
    'closingSequenceSystem': 'Schließfolgesystem',
    'lockDimensions': 'Schlossabmessungen',
    'escapeDoorControl': 'Fluchttürsteuerung / Türwächter',
    'accessControl': 'Zutrittskontrolle',
    'fittingType': 'Beschlagstyp',
    'panicFunction': 'Panikfunktion',
    'approvalNumber': 'Zulassungsnummer',
    'manufacturerNumber': 'Herstellernummer',
    'lintelHeightInsideValue': 'Sturzhöhe innen (Meter)',
    'lintelHeightOutsideValue': 'Sturzhöhe außen (Meter)',
    'roomDesignation': 'Raumbezeichnung',
  };

  static const Map<String, String> _windowCategories = {
    'windowType': 'Fenstertyp',
    'material': 'Material',
    'wingDimensions': 'Flügelabmaße',
    'fittings': 'Beschläge (Hersteller / Art.Nr.)',
    'floor': 'Etage / Geschoss',
    'roomNumber': 'Raumnummer',
    'roomDesignation': 'Raumbezeichnung / Sonstiges',
  };

  late String _selectedAssetType; // 'door' or 'window'
  String _selectedDoorCategoryKey = 'doorType';
  String _selectedWindowCategoryKey = 'windowType';

  bool get _isWindow => _selectedAssetType == 'window';
  Color get _themeColor => _isWindow ? Colors.teal : Colors.indigo;
  IconData get _assetIcon => _isWindow ? Icons.window : Icons.door_front_door;
  String get _assetName => _isWindow ? 'Fenster' : 'Tür';

  Map<String, String> get _activeCategories =>
      _isWindow ? _windowCategories : _doorCategories;

  String get _selectedCategoryKey =>
      _isWindow ? _selectedWindowCategoryKey : _selectedDoorCategoryKey;

  set _selectedCategoryKey(String key) {
    if (_isWindow) {
      _selectedWindowCategoryKey = key;
    } else {
      _selectedDoorCategoryKey = key;
    }
  }

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  List<String> _currentOptions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedAssetType =
        widget.initialAssetType == 'window' ? 'window' : 'door';
    _loadOptions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() => _isLoading = true);
    await DoorOptionsService.ensureLoaded();
    await WindowOptionsService.ensureLoaded();
    setState(() => _isLoading = false);
    _refreshList();
  }

  void _refreshList() {
    final rawOptions = _isWindow
        ? WindowOptionsService.getOptions(_selectedCategoryKey)
        : DoorOptionsService.getOptions(_selectedCategoryKey);

    final List<String> parsed = rawOptions.map((e) {
      if (e is Map) {
        final val = e['value']?.toString() ?? '';
        final label = e['label']?.toString() ?? '';
        return label.isNotEmpty && label != val ? '$val ($label)' : val;
      }
      return e.toString();
    }).toList();

    setState(() {
      _currentOptions = parsed;
    });
  }

  List<String> get _filteredOptions {
    if (_searchQuery.trim().isEmpty) {
      return _currentOptions;
    }
    final q = _searchQuery.trim().toLowerCase();
    return _currentOptions
        .where((opt) => opt.toLowerCase().contains(q))
        .toList();
  }

  String _getRawValue(String displayString) {
    if (displayString.contains(' (')) {
      return displayString.split(' (').first.trim();
    }
    return displayString.trim();
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final categoryLabel =
        _activeCategories[_selectedCategoryKey] ?? _selectedCategoryKey;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(_assetIcon, color: _themeColor, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Neuer Eintrag ($_assetName)',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kategorie: $categoryLabel',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _themeColor,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Neuer Optionswert',
                hintText:
                    _isWindow ? 'z.B. DKR oder 1200x1550' : 'z.B. T30-1 RS',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _themeColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(ctx, text);
              }
            },
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      if (_isWindow) {
        WindowOptionsService.addOption(_selectedCategoryKey, result);
        await WindowOptionsService.saveOptions();
      } else {
        DoorOptionsService.addOption(_selectedCategoryKey, result);
        await DoorOptionsService.saveOptions();
      }
      _refreshList();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Eintrag "$result" erfolgreich hinzugefügt ($_assetName).'),
            backgroundColor: _themeColor,
          ),
        );
      }
    }
  }

  Future<void> _showEditDialog(String displayString) async {
    final rawVal = _getRawValue(displayString);
    if (rawVal == '?') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Standardplatzhalter "?" kann nicht bearbeitet werden.'),
        ),
      );
      return;
    }

    final controller = TextEditingController(text: rawVal);
    final categoryLabel =
        _activeCategories[_selectedCategoryKey] ?? _selectedCategoryKey;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(_assetIcon, color: _themeColor, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Eintrag bearbeiten ($_assetName)',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kategorie: $categoryLabel',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _themeColor,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Bezeichnung / Wert',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _themeColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(ctx, text);
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != rawVal) {
      final updated = _isWindow
          ? WindowOptionsService.updateOption(
              _selectedCategoryKey, rawVal, result)
          : DoorOptionsService.updateOption(
              _selectedCategoryKey, rawVal, result);

      if (updated) {
        if (_isWindow) {
          await WindowOptionsService.saveOptions();
        } else {
          await DoorOptionsService.saveOptions();
        }
        _refreshList();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Eintrag "$rawVal" geändert zu "$result".'),
              backgroundColor: _themeColor,
            ),
          );
        }
      }
    }
  }

  Future<void> _showDeleteConfirmDialog(String displayString) async {
    final rawVal = _getRawValue(displayString);
    if (rawVal == '?') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Standardplatzhalter "?" kann nicht gelöscht werden.'),
        ),
      );
      return;
    }

    final categoryLabel =
        _activeCategories[_selectedCategoryKey] ?? _selectedCategoryKey;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: Text(
          'Möchten Sie den Menüeintrag "$rawVal" aus der Kategorie "$categoryLabel" ($_assetName) wirklich löschen?\n\n'
          'Hinweis: Dieser Eintrag wird in zukünftigen Dropdown-Menüs nicht mehr zur Auswahl angeboten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final removed = _isWindow
          ? WindowOptionsService.removeOption(_selectedCategoryKey, rawVal)
          : DoorOptionsService.removeOption(_selectedCategoryKey, rawVal);

      if (removed) {
        if (_isWindow) {
          await WindowOptionsService.saveOptions();
        } else {
          await DoorOptionsService.saveOptions();
        }
        _refreshList();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Eintrag "$rawVal" wurde gelöscht.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredOptions;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Stammdaten-Optionen verwalten',
              style: TextStyle(fontSize: 18),
            ),
            Text(
              _isWindow ? 'Fenster-Stammdaten' : 'Türen-Stammdaten',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: _themeColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(_isWindow ? 'Neue Fenster-Option' : 'Neue Tür-Option'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Asset Type SegmentedButton (Doors vs Windows)
                  Center(
                    child: SegmentedButton<String>(
                      segments: [
                        ButtonSegment<String>(
                          value: 'door',
                          icon: const Icon(Icons.door_front_door),
                          label: Text(
                              'Türen (${_doorCategories.length} Kategorien)'),
                        ),
                        ButtonSegment<String>(
                          value: 'window',
                          icon: const Icon(Icons.window),
                          label: Text(
                              'Fenster (${_windowCategories.length} Kategorien)'),
                        ),
                      ],
                      selected: {_selectedAssetType},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          _selectedAssetType = newSelection.first;
                          _searchController.clear();
                          _searchQuery = '';
                        });
                        _refreshList();
                      },
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor:
                            _isWindow ? Colors.teal : Colors.indigo,
                        selectedForegroundColor: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Category selector dropdown
                  Text(
                    'Eigenschaftskategorie ($_assetName) wählen:',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: _themeColor, width: 1.5),
                      borderRadius: BorderRadius.circular(8),
                      color: _themeColor.withValues(alpha: 0.04),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _activeCategories
                                .containsKey(_selectedCategoryKey)
                            ? _selectedCategoryKey
                            : _activeCategories.keys.first,
                        items: _activeCategories.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Row(
                              children: [
                                Icon(_assetIcon, size: 16, color: _themeColor),
                                const SizedBox(width: 8),
                                Text(entry.value,
                                    style: const TextStyle(fontSize: 15)),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (newKey) {
                          if (newKey != null) {
                            setState(() {
                              _selectedCategoryKey = newKey;
                              _searchController.clear();
                              _searchQuery = '';
                            });
                            _refreshList();
                          }
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Search input field
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Einträge durchsuchen ($_assetName)',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),

                  const SizedBox(height: 14),

                  // Options header summary
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(_assetIcon, size: 16, color: _themeColor),
                          const SizedBox(width: 6),
                          Text(
                            'Verfügbare Optionen (${filtered.length}):',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _themeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: _themeColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _assetName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _themeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Options List
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off,
                                    size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'Keine Einträge für "$_searchQuery" gefunden.'
                                      : 'Keine Optionen in dieser Kategorie vorhanden.',
                                  style: TextStyle(
                                      color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final rawVal = _getRawValue(item);
                              final isProtected = rawVal == '?';

                              return Card(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 4),
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: _themeColor.withValues(alpha: 0.25),
                                    width: 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: isProtected
                                              ? Colors.grey
                                              : _themeColor,
                                          width: 4,
                                        ),
                                      ),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: isProtected
                                            ? Colors.grey.shade200
                                            : _themeColor
                                                .withValues(alpha: 0.12),
                                        child: Icon(
                                          isProtected
                                              ? Icons.help_outline
                                              : _assetIcon,
                                          color: isProtected
                                              ? Colors.grey
                                              : _themeColor,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        item,
                                        style: TextStyle(
                                          fontWeight: isProtected
                                              ? FontWeight.normal
                                              : FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: isProtected
                                          ? const Text(
                                              'Standard-Platzhalter (nicht löschbar)')
                                          : null,
                                      trailing: isProtected
                                          ? null
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: Icon(Icons.edit,
                                                      color: _themeColor),
                                                  tooltip: 'Bearbeiten',
                                                  onPressed: () =>
                                                      _showEditDialog(item),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                      Icons.delete_outline,
                                                      color: Colors.red),
                                                  tooltip: 'Löschen',
                                                  onPressed: () =>
                                                      _showDeleteConfirmDialog(
                                                          item),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
