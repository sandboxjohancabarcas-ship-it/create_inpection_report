import 'package:flutter/material.dart';
import '../services/door_options_service.dart';

/// Page for Managers to view, search, create, edit, and delete dropdown options (CRUD).
class DoorOptionsManagerPage extends StatefulWidget {
  const DoorOptionsManagerPage({super.key});

  @override
  State<DoorOptionsManagerPage> createState() => _DoorOptionsManagerPageState();
}

class _DoorOptionsManagerPageState extends State<DoorOptionsManagerPage> {
  static const Map<String, String> _categories = {
    'doorType': 'Türart',
    'material': 'Material',
    'manufacturer': 'Hersteller',
    'dinConfiguration': 'DIN-Konfiguration',
    'closerType': 'Schließerart',
    'closingSequenceSystem': 'Schließfolgesystem',
    'lockDimensions': 'Schlossabmessungen',
    'accessControl': 'Zutrittskontrolle',
    'fittingType': 'Beschlagstyp',
    'panicFunction': 'Panikfunktion',
    'approvalNumber': 'Zulassungsnummer',
    'manufacturerNumber': 'Herstellernummer',
    'roomDesignation': 'Raumbezeichnung',
  };

  String _selectedCategoryKey = 'doorType';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  List<String> _currentOptions = [];

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    await DoorOptionsService.ensureLoaded();
    _refreshList();
  }

  void _refreshList() {
    final rawOptions = DoorOptionsService.getOptions(_selectedCategoryKey);
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
    return _currentOptions.where((opt) => opt.toLowerCase().contains(q)).toList();
  }

  String _getRawValue(String displayString) {
    if (displayString.contains(' (')) {
      return displayString.split(' (').first.trim();
    }
    return displayString.trim();
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final categoryLabel = _categories[_selectedCategoryKey] ?? _selectedCategoryKey;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Neuer Eintrag für "$categoryLabel"'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Neuer Optionswert',
            hintText: 'z.B. T30-1 RS',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
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
      DoorOptionsService.addOption(_selectedCategoryKey, result);
      await DoorOptionsService.saveOptions();
      _refreshList();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eintrag "$result" erfolgreich hinzugefügt.')),
        );
      }
    }
  }

  Future<void> _showEditDialog(String displayString) async {
    final rawVal = _getRawValue(displayString);
    if (rawVal == '?') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Standardplatzhalter "?" kann nicht bearbeitet werden.')),
      );
      return;
    }

    final controller = TextEditingController(text: rawVal);
    final categoryLabel = _categories[_selectedCategoryKey] ?? _selectedCategoryKey;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eintrag bearbeiten ("$categoryLabel")'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Bezeichnung / Wert',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
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
      final updated = DoorOptionsService.updateOption(_selectedCategoryKey, rawVal, result);
      if (updated) {
        await DoorOptionsService.saveOptions();
        _refreshList();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Eintrag "$rawVal" geändert zu "$result".')),
          );
        }
      }
    }
  }

  Future<void> _showDeleteConfirmDialog(String displayString) async {
    final rawVal = _getRawValue(displayString);
    if (rawVal == '?') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Standardplatzhalter "?" kann nicht gelöscht werden.')),
      );
      return;
    }

    final categoryLabel = _categories[_selectedCategoryKey] ?? _selectedCategoryKey;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: Text(
          'Möchten Sie den Menüeintrag "$rawVal" aus der Kategorie "$categoryLabel" wirklich löschen?\n\n'
          'Hinweis: Dieser Eintrag wird in zukünftigen Dropdown-Menüs nicht mehr zur Auswahl angeboten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final removed = DoorOptionsService.removeOption(_selectedCategoryKey, rawVal);
      if (removed) {
        await DoorOptionsService.saveOptions();
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
        title: const Text('Stammdaten-Optionen verwalten'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Neuer Eintrag'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category selector dropdown
            const Text(
              'Eigenschaftskategorie wählen:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedCategoryKey,
                  items: _categories.entries.map((entry) {
                    return DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value, style: const TextStyle(fontSize: 16)),
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

            const SizedBox(height: 16),

            // Search input field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Einträge durchsuchen',
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

            const SizedBox(height: 16),

            // Options header summary
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Verfügbare Optionen (${filtered.length}):',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                          Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'Keine Einträge für "$_searchQuery" gefunden.'
                                : 'Keine Optionen in dieser Kategorie vorhanden.',
                            style: TextStyle(color: Colors.grey.shade600),
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
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isProtected ? Colors.grey.shade200 : Colors.blue.shade50,
                              child: Icon(
                                isProtected ? Icons.help_outline : Icons.label_outlined,
                                color: isProtected ? Colors.grey : Colors.blue,
                              ),
                            ),
                            title: Text(
                              item,
                              style: TextStyle(
                                fontWeight: isProtected ? FontWeight.normal : FontWeight.w500,
                              ),
                            ),
                            subtitle: isProtected ? const Text('Standard-Platzhalter (nicht löschbar)') : null,
                            trailing: isProtected
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.blue),
                                        tooltip: 'Bearbeiten',
                                        onPressed: () => _showEditDialog(item),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                                        tooltip: 'Löschen',
                                        onPressed: () => _showDeleteConfirmDialog(item),
                                      ),
                                    ],
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
