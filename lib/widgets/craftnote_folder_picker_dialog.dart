import 'package:flutter/material.dart';
import '../models/craftnote_models.dart';
import '../services/craftnote_api_service.dart';

/// Result returned from the [CraftnoteFolderPickerDialog].
class CraftnoteFolderPickerResult {
  final bool isRoot;
  final CraftnoteFile? folder;

  const CraftnoteFolderPickerResult.root()
      : isRoot = true,
        folder = null;

  const CraftnoteFolderPickerResult.folder(this.folder)
      : isRoot = false;

  String? get folderId => folder?.id;
  String get displayName => isRoot ? 'Hauptverzeichnis (Root)' : (folder?.name ?? 'Hauptverzeichnis');
}

/// A modal file-picker style dialog that allows navigating and selecting folders
/// in a designated Craftnote project.
class CraftnoteFolderPickerDialog extends StatefulWidget {
  final String projectId;
  final String projectName;
  final String? initialFolderId;
  final CraftnoteApiService? apiService;

  const CraftnoteFolderPickerDialog({
    super.key,
    required this.projectId,
    required this.projectName,
    this.initialFolderId,
    this.apiService,
  });

  static Future<CraftnoteFolderPickerResult?> show({
    required BuildContext context,
    required String projectId,
    required String projectName,
    String? initialFolderId,
    CraftnoteApiService? apiService,
  }) {
    return showDialog<CraftnoteFolderPickerResult>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CraftnoteFolderPickerDialog(
        projectId: projectId,
        projectName: projectName,
        initialFolderId: initialFolderId,
        apiService: apiService,
      ),
    );
  }

  @override
  State<CraftnoteFolderPickerDialog> createState() => _CraftnoteFolderPickerDialogState();
}

class _CraftnoteFolderPickerDialogState extends State<CraftnoteFolderPickerDialog> {
  late final CraftnoteApiService _apiService;
  final TextEditingController _filterController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  List<CraftnoteFile> _allFolders = [];
  Map<String, CraftnoteFile> _folderMap = {};

  String? _selectedFolderId; // null = Root
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? CraftnoteApiService();
    _selectedFolderId = widget.initialFolderId;
    _filterController.addListener(() {
      setState(() {
        _filterQuery = _filterController.text.trim().toLowerCase();
      });
    });
    _loadProjectFolders();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _loadProjectFolders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final files = await _apiService.getProjectFiles(widget.projectId);
      final folders = files.where((f) => f.isFolder).toList();

      final map = <String, CraftnoteFile>{};
      for (final f in folders) {
        map[f.id] = f;
      }

      // Sort alphabetically by full path
      folders.sort((a, b) {
        final pathA = _buildFullPath(a, map);
        final pathB = _buildFullPath(b, map);
        return pathA.toLowerCase().compareTo(pathB.toLowerCase());
      });

      if (mounted) {
        setState(() {
          _allFolders = folders;
          _folderMap = map;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '$e';
          _isLoading = false;
        });
      }
    }
  }

  String _buildFullPath(CraftnoteFile folder, Map<String, CraftnoteFile> map) {
    final segments = [folder.name];
    String? parentId = folder.folderId;
    int guard = 0;
    while (parentId != null && map.containsKey(parentId) && guard < 10) {
      final parent = map[parentId]!;
      segments.insert(0, parent.name);
      parentId = parent.folderId;
      guard++;
    }
    return segments.join(' / ');
  }

  List<CraftnoteFile> get _filteredFolders {
    if (_filterQuery.isEmpty) return _allFolders;
    return _allFolders.where((f) {
      final name = f.name.toLowerCase();
      final path = _buildFullPath(f, _folderMap).toLowerCase();
      return name.contains(_filterQuery) || path.contains(_filterQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.folder_shared, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Craftnote-Zielordner wählen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  'Projekt: ${widget.projectName}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.normal),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Ordner neu laden',
            onPressed: _loadProjectFolders,
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        height: 480,
        child: Column(
          children: [
            // Filter / Search bar
            TextField(
              controller: _filterController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Ordner durchsuchen...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: _filterQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _filterController.clear(),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),

            // Main Content Area
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Lade Ordnerstruktur aus Craftnote...'),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 36),
                              const SizedBox(height: 8),
                              Text('Fehler beim Laden:\n$_errorMessage', textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.refresh),
                                label: const Text('Erneut versuchen'),
                                onPressed: _loadProjectFolders,
                              ),
                            ],
                          ),
                        )
                      : Material(
                          color: Colors.grey.shade50,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            children: [
                              // ROOT FOLDER OPTION
                              Material(
                                color: Colors.transparent,
                                child: ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: _selectedFolderId == null ? Colors.blue.shade100 : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      Icons.home,
                                      color: _selectedFolderId == null ? Colors.blue.shade800 : Colors.grey.shade700,
                                      size: 22,
                                    ),
                                  ),
                                  title: const Text(
                                    '[Hauptverzeichnis / Root]',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  subtitle: const Text(
                                    'Dateien direkt im Projektstammverzeichnis ohne Unterordner ablegen',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  trailing: _selectedFolderId == null
                                      ? const Icon(Icons.check_circle, color: Colors.green)
                                      : null,
                                  selected: _selectedFolderId == null,
                                  selectedTileColor: Colors.blue.shade50,
                                  onTap: () {
                                    setState(() => _selectedFolderId = null);
                                  },
                                ),
                              ),
                              const Divider(height: 1),

                              // LIST OF FOLDERS
                              if (_filteredFolders.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Center(
                                    child: Text(
                                      _allFolders.isEmpty
                                          ? 'Keine Unterordner in diesem Projekt vorhanden.'
                                          : 'Kein Ordner entspricht "$_filterQuery".',
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                  ),
                                )
                              else
                                ..._filteredFolders.map((folder) {
                                  final isSelected = _selectedFolderId == folder.id;
                                  final path = _buildFullPath(folder, _folderMap);

                                  return Material(
                                    color: Colors.transparent,
                                    child: ListTile(
                                      leading: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: isSelected ? Colors.amber.shade100 : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Icon(
                                          isSelected ? Icons.folder_open : Icons.folder,
                                          color: isSelected ? Colors.amber.shade900 : Colors.amber.shade700,
                                          size: 22,
                                        ),
                                      ),
                                      title: Text(
                                        folder.name,
                                        style: TextStyle(
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          fontSize: 14,
                                        ),
                                      ),
                                      subtitle: Text(
                                        path,
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                      trailing: isSelected
                                          ? const Icon(Icons.check_circle, color: Colors.green)
                                          : null,
                                      selected: isSelected,
                                      selectedTileColor: Colors.amber.shade50,
                                      onTap: () {
                                        setState(() => _selectedFolderId = folder.id);
                                      },
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Auswählen'),
          onPressed: () {
            if (_selectedFolderId == null) {
              Navigator.of(context).pop(const CraftnoteFolderPickerResult.root());
            } else {
              final folder = _folderMap[_selectedFolderId];
              if (folder != null) {
                Navigator.of(context).pop(CraftnoteFolderPickerResult.folder(folder));
              } else {
                Navigator.of(context).pop(const CraftnoteFolderPickerResult.root());
              }
            }
          },
        ),
      ],
    );
  }
}
