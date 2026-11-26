import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../services/rwa_options_service.dart';

class RwaErrorManagementPage extends StatefulWidget {
  final int rwaSystemId;
  final String systemAlias;
  final int inspectionId;
  final int inspectionRwaId;
  final String initialSettingName;
  final bool isManagerMode;
  final bool isReadOnly;

  const RwaErrorManagementPage({
    super.key,
    required this.rwaSystemId,
    required this.systemAlias,
    required this.inspectionId,
    required this.inspectionRwaId,
    this.initialSettingName = '',
    this.isManagerMode = false,
    this.isReadOnly = false,
  });

  @override
  State<RwaErrorManagementPage> createState() => _RwaErrorManagementPageState();
}

class _RwaErrorManagementPageState extends State<RwaErrorManagementPage> {
  List<InspectionRwaError> _errors = [];
  List<ErrorCatalog> _catalog = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      if (widget.isManagerMode) {
        _catalog = await DatabaseService.getAllErrorCatalog(assetType: 'rwa');
        if (_catalog.isEmpty) {
          await DatabaseService.checkAndInitializeRwaCatalog();
          _catalog = await DatabaseService.getAllErrorCatalog(assetType: 'rwa');
        }
        _errors = await DatabaseService.getInspectionRwaErrors(widget.inspectionRwaId);
      } else {
        _catalog = await LocalDatabaseService.getAllErrorCatalog(assetType: 'rwa');
        _errors = await LocalDatabaseService.getInspectionRwaErrors(widget.inspectionRwaId);
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden der Mängel: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showAddOrEditErrorDialog({InspectionRwaError? existingError}) async {
    final availableSettings = RwaOptionsService.einrichtungSettings;
    String selectedSetting = existingError?.settingName ??
        (widget.initialSettingName.isNotEmpty ? widget.initialSettingName : availableSettings.first);

    ErrorCatalog? selectedCatalogItem;
    if (existingError != null) {
      selectedCatalogItem = _catalog.where((c) => c.code == existingError.errorCode).firstOrNull;
    }

    final notesController = TextEditingController(text: existingError?.notes ?? '');
    String selectedSeverity = existingError?.severity ?? 'Major';
    final severities = ['Minor', 'Major', 'Critical'];

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existingError == null ? 'Neuen Mangel erfassen' : 'Mangel bearbeiten'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Setting selector
                      DropdownButtonFormField<String>(
                        value: availableSettings.contains(selectedSetting) ? selectedSetting : availableSettings.first,
                        decoration: const InputDecoration(labelText: 'Einrichtung / Bauteil'),
                        items: availableSettings.map((s) {
                          return DropdownMenuItem(value: s, child: Text(s));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedSetting = val);
                        },
                      ),
                      const SizedBox(height: 12),

                      // Error catalog code selector
                      DropdownButtonFormField<ErrorCatalog>(
                        value: selectedCatalogItem,
                        decoration: const InputDecoration(labelText: 'Katalog-Fehler (Code / Beschreibung)'),
                        isExpanded: true,
                        items: _catalog.map((c) {
                          return DropdownMenuItem(
                            value: c,
                            child: Text(
                              '${c.code} - ${c.description}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedCatalogItem = val;
                            if (val != null && notesController.text.isEmpty) {
                              notesController.text = val.description;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      // Severity
                      DropdownButtonFormField<String>(
                        value: selectedSeverity,
                        decoration: const InputDecoration(labelText: 'Schweregrad'),
                        items: severities.map((sev) {
                          return DropdownMenuItem(value: sev, child: Text(sev));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedSeverity = val);
                        },
                      ),
                      const SizedBox(height: 12),

                      // Notes / Description
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Beschreibung / Feststellung',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (notesController.text.trim().isEmpty && selectedCatalogItem == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Bitte eine Beschreibung oder einen Katalogfehler wählen.')),
                      );
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      final code = selectedCatalogItem?.code ?? 'RWA-GEN-001';
      final desc = notesController.text.trim().isNotEmpty
          ? notesController.text.trim()
          : (selectedCatalogItem?.description ?? 'Mangel festgestellt');

      if (existingError == null) {
        final newError = InspectionRwaError(
          inspectionRwaId: widget.inspectionRwaId,
          settingName: selectedSetting,
          errorId: selectedCatalogItem?.errorId,
          errorCode: code,
          quantity: 1,
          severity: selectedSeverity,
          notes: desc,
          resolutionStatus: 'Open',
        );

        if (widget.isManagerMode) {
          await DatabaseService.insertInspectionRwaError(newError);
        } else {
          await LocalDatabaseService.insertInspectionRwaError(newError);
        }
      } else {
        final updated = existingError.copyWith(
          settingName: selectedSetting,
          errorId: selectedCatalogItem?.errorId,
          errorCode: code,
          severity: selectedSeverity,
          notes: desc,
        );

        if (widget.isManagerMode) {
          await DatabaseService.insertInspectionRwaError(updated);
        } else {
          await LocalDatabaseService.insertInspectionRwaError(updated);
        }
      }

      await _loadData();
    }
  }

  Future<void> _deleteError(int errorId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mangel löschen?'),
        content: const Text('Möchten Sie diesen Mangel wirklich entfernen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (widget.isManagerMode) {
        await DatabaseService.deleteInspectionRwaError(errorId);
      } else {
        await LocalDatabaseService.deleteInspectionRwaError(errorId);
      }
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        appBar: AppBar(
          title: Text('Mängel: ${widget.systemAlias}'),
        ),
        floatingActionButton: widget.isReadOnly
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _showAddOrEditErrorDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Mangel erfassen'),
              ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errors.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          'Keine Mängel für dieses RWA-System erfasst.',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _errors.length,
                    itemBuilder: (context, index) {
                      final err = _errors[index];
                      final cat = _catalog.where((c) => c.code == err.errorCode).firstOrNull;

                      Color severityColor = Colors.orange;
                      if (err.severity.toLowerCase() == 'critical') severityColor = Colors.red.shade700;
                      if (err.severity.toLowerCase() == 'minor') severityColor = Colors.amber.shade700;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: severityColor.withValues(alpha: 0.2),
                            child: Icon(Icons.warning, color: severityColor, size: 20),
                          ),
                          title: Text(
                            '${err.settingName}: ${err.errorCode}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(err.notes, style: const TextStyle(fontSize: 13)),
                              if (cat?.recommendation != null && cat!.recommendation.isNotEmpty)
                                Text(
                                  'Empfehlung: ${cat.recommendation}',
                                  style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700),
                                ),
                            ],
                          ),
                          trailing: widget.isReadOnly
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 20),
                                      onPressed: () => _showAddOrEditErrorDialog(existingError: err),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                      onPressed: () => _deleteError(err.id!),
                                    ),
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
