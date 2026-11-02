import 'package:flutter/material.dart';
import 'package:wartungstool/models/craftnote_models.dart';
import 'package:wartungstool/services/craftnote_api_service.dart';
import 'package:wartungstool/services/craftnote_sync_service.dart';
import 'package:wartungstool/widgets/craftnote_settings_dialog.dart';

/// Modal dialog allowing inspectors to discover Craftnote cloud projects,
/// view attached SQLite packages (.db), and import them into the local working DB in 1 click.
class CraftnoteJobPickerModal extends StatefulWidget {
  const CraftnoteJobPickerModal({super.key});

  static Future<CraftnoteImportResult?> show(BuildContext context) async {
    return await showDialog<CraftnoteImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CraftnoteJobPickerModal(),
    );
  }

  @override
  State<CraftnoteJobPickerModal> createState() => _CraftnoteJobPickerModalState();
}

class _CraftnoteJobPickerModalState extends State<CraftnoteJobPickerModal> {
  final CraftnoteApiService _apiService = CraftnoteApiService();
  final CraftnoteSyncService _syncService = CraftnoteSyncService();

  final TextEditingController _searchController = TextEditingController();

  List<CraftnoteProject> _projects = [];
  CraftnoteProject? _selectedProject;
  List<CraftnoteFile> _projectFiles = [];

  bool _isLoadingProjects = true;
  bool _isLoadingFiles = false;
  bool _isImporting = false;
  String? _importingFileName;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProjects({String? query}) async {
    setState(() {
      _isLoadingProjects = true;
      _errorMessage = null;
    });

    try {
      final projects = await _apiService.getProjects(search: query);
      setState(() {
        _projects = projects;
        if (_selectedProject != null) {
          // Re-select if still in list
          _selectedProject = projects.firstWhere(
            (p) => p.id == _selectedProject!.id,
            orElse: () => projects.isNotEmpty ? projects.first : _selectedProject!,
          );
        } else if (projects.isNotEmpty) {
          _selectedProject = projects.first;
        }
      });

      if (_selectedProject != null) {
        await _loadProjectFiles(_selectedProject!.id);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Fehler beim Laden der Craftnote-Projekte:\n$e';
      });
    } finally {
      setState(() => _isLoadingProjects = false);
    }
  }

  Future<void> _loadProjectFiles(String projectId) async {
    setState(() {
      _isLoadingFiles = true;
      _projectFiles = [];
    });

    try {
      final files = await _apiService.getProjectFiles(projectId);
      setState(() {
        _projectFiles = files;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dateien konnten nicht geladen werden: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingFiles = false);
    }
  }

  Future<void> _importFile(CraftnoteFile file) async {
    if (_selectedProject == null) return;

    setState(() {
      _isImporting = true;
      _importingFileName = file.name;
    });

    try {
      final result = await _syncService.downloadAndImportPackage(
        project: _selectedProject!,
        file: file,
      );

      if (mounted) {
        if (result.success) {
          Navigator.of(context).pop(result);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import fehlgeschlagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _importingFileName = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      title: Row(
        children: [
          Icon(Icons.cloud_download, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(child: Text('Auftrag aus Craftnote importieren')),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Craftnote-Einstellungen',
            onPressed: () async {
              final changed = await CraftnoteSettingsDialog.show(context);
              if (changed == true) {
                _loadProjects();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: () => _loadProjects(query: _searchController.text),
          ),
        ],
      ),
      content: SizedBox(
        width: 750,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Input
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Projekt, Auftragsnummer oder Stadt suchen...',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _loadProjects();
                        },
                      )
                    : null,
              ),
              onSubmitted: (val) => _loadProjects(query: val),
            ),
            const SizedBox(height: 12),

            if (_isImporting)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade300),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Importiere "$_importingFileName" und synchronisiere lokale Datenbank...',
                        style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                ),
              ),

            // Two-column layout: Left = Projects, Right = Files
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column: Project List
                  Expanded(
                    flex: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _isLoadingProjects
                          ? const Center(child: CircularProgressIndicator())
                          : _projects.isEmpty
                              ? const Center(
                                  child: Text('Keine Projekte gefunden.',
                                      style: TextStyle(color: Colors.grey)),
                                )
                              : ListView.separated(
                                  itemCount: _projects.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, idx) {
                                    final p = _projects[idx];
                                    final isSelected = _selectedProject?.id == p.id;
                                    return ListTile(
                                      selected: isSelected,
                                      selectedTileColor: Colors.blue.shade50,
                                      dense: true,
                                      title: Text(
                                        p.name,
                                        style: TextStyle(
                                          fontWeight:
                                              isSelected ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                      subtitle: Text(
                                        [
                                          if (p.orderNumber.isNotEmpty) '#${p.orderNumber}',
                                          if (p.city.isNotEmpty) p.city,
                                        ].join(' • '),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      trailing: isSelected
                                          ? const Icon(Icons.arrow_forward_ios, size: 14)
                                          : null,
                                      onTap: () {
                                        setState(() => _selectedProject = p);
                                        _loadProjectFiles(p.id);
                                      },
                                    );
                                  },
                                ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Right Column: Files in selected project
                  Expanded(
                    flex: 5,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedProject != null
                                ? 'Dateien in: ${_selectedProject!.name}'
                                : 'Dateien',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Divider(),
                          Expanded(
                            child: _isLoadingFiles
                                ? const Center(child: CircularProgressIndicator())
                                : _projectFiles.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'Keine Dateien in diesem Projekt hinterlegt.',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: _projectFiles.length,
                                        itemBuilder: (context, idx) {
                                          final f = _projectFiles[idx];
                                          final isDb = f.isSqliteDatabase;
                                          final isPdf = f.isPdfReport;

                                          return Card(
                                            margin: const EdgeInsets.symmetric(vertical: 4),
                                            color: isDb ? Colors.green.shade50 : Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(6),
                                              side: BorderSide(
                                                color: isDb
                                                    ? Colors.green.shade300
                                                    : Colors.grey.shade300,
                                              ),
                                            ),
                                            child: ListTile(
                                              dense: true,
                                              leading: Icon(
                                                isDb
                                                    ? Icons.storage
                                                    : isPdf
                                                        ? Icons.picture_as_pdf
                                                        : Icons.insert_drive_file,
                                                color: isDb
                                                    ? Colors.green.shade700
                                                    : isPdf
                                                        ? Colors.red.shade700
                                                        : Colors.grey.shade700,
                                              ),
                                              title: Text(
                                                f.name,
                                                style: TextStyle(
                                                  fontWeight:
                                                      isDb ? FontWeight.bold : FontWeight.normal,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              subtitle: Text(
                                                f.formattedSize,
                                                style: const TextStyle(fontSize: 11),
                                              ),
                                              trailing: isDb
                                                  ? ElevatedButton.icon(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: Colors.green.shade700,
                                                        foregroundColor: Colors.white,
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 10, vertical: 6),
                                                      ),
                                                      onPressed: _isImporting
                                                          ? null
                                                          : () => _importFile(f),
                                                      icon: const Icon(Icons.download, size: 16),
                                                      label: const Text('Importieren',
                                                          style: TextStyle(fontSize: 12)),
                                                    )
                                                  : null,
                                            ),
                                          );
                                        },
                                      ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}
