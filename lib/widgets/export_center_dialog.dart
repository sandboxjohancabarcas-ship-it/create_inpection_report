import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_export_service.dart';
import 'package:wartungstool/services/pdf_export_service.dart';

enum ExportScope { singleInspection, clientAudit, doorHistory }
enum ExportFormat { excel, pdf, dbPackage }

class ExportCenterDialog extends StatefulWidget {
  final int? initialInspectionId;
  final String? initialDoorAlias;

  const ExportCenterDialog({
    super.key,
    this.initialInspectionId,
    this.initialDoorAlias,
  });

  static Future<void> show(BuildContext context, {int? initialInspectionId, String? initialDoorAlias}) async {
    await showDialog(
      context: context,
      builder: (context) => ExportCenterDialog(
        initialInspectionId: initialInspectionId,
        initialDoorAlias: initialDoorAlias,
      ),
    );
  }

  @override
  State<ExportCenterDialog> createState() => _ExportCenterDialogState();
}

class _ExportCenterDialogState extends State<ExportCenterDialog> {
  final TextEditingController _searchController = TextEditingController();

  ExportScope _selectedScope = ExportScope.singleInspection;
  ExportFormat _selectedFormat = ExportFormat.excel;

  List<Map<String, dynamic>> _inspections = [];
  List<String> _clients = [];
  List<String> _doorAliases = [];

  int? _selectedInspectionId;
  String? _selectedClient;
  String? _selectedDoorAlias;

  bool _isLoading = true;
  bool _isExporting = false;
  String? _exportSuccessPath;
  String? _errorMessage;

  List<Map<String, dynamic>> get _filteredInspections {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return _inspections;
    return _inspections.where((insp) {
      final client = (insp['clientName'] ?? '').toString().toLowerCase();
      final job = (insp['jobNumber'] ?? '').toString().toLowerCase();
      final address = (insp['objectAddress'] ?? '').toString().toLowerCase();
      final date = (insp['date'] ?? '').toString().toLowerCase();
      final id = insp['inspectionId'];
      return client.contains(query) ||
          job.contains(query) ||
          address.contains(query) ||
          date.contains(query) ||
          (id != null && id == _selectedInspectionId);
    }).toList();
  }

  List<String> get _filteredClients {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return _clients;
    return _clients.where((client) {
      return client.toLowerCase().contains(query) || client == _selectedClient;
    }).toList();
  }

  List<String> get _filteredDoorAliases {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return _doorAliases;
    return _doorAliases.where((alias) {
      return alias.toLowerCase().contains(query) || alias == _selectedDoorAlias;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      _inspections = await DatabaseService.getAllInspections();
      _clients = await DatabaseService.getAllClientsForExport();
      _doorAliases = await DatabaseService.getAllDoorAliases();

      if (widget.initialInspectionId != null) {
        _selectedScope = ExportScope.singleInspection;
        _selectedInspectionId = widget.initialInspectionId;
      } else if (widget.initialDoorAlias != null) {
        _selectedScope = ExportScope.doorHistory;
        _selectedDoorAlias = widget.initialDoorAlias;
      } else {
        if (_inspections.isNotEmpty) {
          _selectedInspectionId = _inspections.first['inspectionId'] as int?;
        }
        if (_clients.isNotEmpty) {
          _selectedClient = _clients.first;
        }
        if (_doorAliases.isNotEmpty) {
          _selectedDoorAlias = _doorAliases.first;
        }
      }
    } catch (e) {
      _errorMessage = 'Fehler beim Laden der Export-Optionen: $e';
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String> _getExportDirectory() async {
    Directory? downloadsDir;
    try {
      downloadsDir = await getDownloadsDirectory();
    } catch (_) {}
    downloadsDir ??= await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(downloadsDir.path, 'WartungsTool_Exports'));
    if (!exportDir.existsSync()) {
      exportDir.createSync(recursive: true);
    }
    return exportDir.path;
  }

  Future<void> _executeExport() async {
    setState(() {
      _isExporting = true;
      _exportSuccessPath = null;
      _errorMessage = null;
    });

    try {
      final exportDir = await _getExportDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String targetPath = '';

      if (_selectedScope == ExportScope.singleInspection) {
        if (_selectedInspectionId == null) {
          throw Exception('Bitte wählen Sie eine Inspektion aus.');
        }
        final insp = _inspections.firstWhere((i) => i['inspectionId'] == _selectedInspectionId);
        final jobStr = insp['jobNumber'] ?? 'Auftrag';
        final safeJob = jobStr.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

        if (_selectedFormat == ExportFormat.excel) {
          targetPath = p.join(exportDir, 'Inspektion_${safeJob}_$timestamp.xlsx');
          await ExcelExportService.exportSingleInspection(_selectedInspectionId!, targetPath);
        } else if (_selectedFormat == ExportFormat.pdf) {
          targetPath = p.join(exportDir, 'Inspektion_${safeJob}_$timestamp.pdf');
          await PdfExportService.exportSingleInspectionPdf(_selectedInspectionId!, targetPath);
        } else if (_selectedFormat == ExportFormat.dbPackage) {
          targetPath = p.join(exportDir, 'Inspektion_${safeJob}_$timestamp.db');
          await DatabaseService.exportJobPackage([_selectedInspectionId!]);
        }
      } else if (_selectedScope == ExportScope.clientAudit) {
        if (_selectedClient == null || _selectedClient!.isEmpty) {
          throw Exception('Bitte wählen Sie einen Kunden aus.');
        }
        final safeClient = _selectedClient!.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

        if (_selectedFormat == ExportFormat.excel) {
          targetPath = p.join(exportDir, 'Kunden_Audit_${safeClient}_$timestamp.xlsx');
          await ExcelExportService.exportClientAudit(_selectedClient!, targetPath);
        } else if (_selectedFormat == ExportFormat.pdf) {
          targetPath = p.join(exportDir, 'Kunden_Audit_${safeClient}_$timestamp.pdf');
          // Export first inspection or full audit payload to PDF
          final inspList = _inspections.where((i) => i['clientName'] == _selectedClient).toList();
          if (inspList.isNotEmpty) {
            await PdfExportService.exportSingleInspectionPdf(inspList.first['inspectionId'] as int, targetPath);
          } else {
            throw Exception('Keine Inspektionen für diesen Kunden vorhanden.');
          }
        } else if (_selectedFormat == ExportFormat.dbPackage) {
          targetPath = p.join(exportDir, 'Kunden_Audit_${safeClient}_$timestamp.db');
          final clientInsps = _inspections.where((i) => i['clientName'] == _selectedClient).map((i) => i['inspectionId'] as int).toList();
          await DatabaseService.exportJobPackage(clientInsps);
        }
      } else if (_selectedScope == ExportScope.doorHistory) {
        if (_selectedDoorAlias == null || _selectedDoorAlias!.isEmpty) {
          throw Exception('Bitte wählen Sie einen Tür-Alias aus.');
        }
        final safeAlias = _selectedDoorAlias!.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final historyData = await DatabaseService.getDoorHistoryData(doorAlias: _selectedDoorAlias!);
        if (historyData == null || historyData.isEmpty) {
          throw Exception('Tür-Akte nicht gefunden.');
        }

        if (_selectedFormat == ExportFormat.excel) {
          targetPath = p.join(exportDir, 'TuerAkte_${safeAlias}_$timestamp.xlsx');
          await ExcelExportService.exportDoorHistoryReport(historyData, targetPath);
        } else if (_selectedFormat == ExportFormat.pdf) {
          targetPath = p.join(exportDir, 'TuerAkte_${safeAlias}_$timestamp.pdf');
          await PdfExportService.exportDoorHistoryPdf(historyData, targetPath);
        } else if (_selectedFormat == ExportFormat.dbPackage) {
          targetPath = p.join(exportDir, 'TuerAkte_${safeAlias}_$timestamp.db');
          final doorObj = historyData['door'];
          final doorId = (doorObj is Door)
              ? doorObj.id
              : (doorObj is Map ? doorObj['id'] as int? : null);
          if (doorId != null) {
            await DatabaseService.exportDoorsPackage([doorId]);
          }
        }
      }

      setState(() {
        _exportSuccessPath = targetPath;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Export fehlgeschlagen: $e';
      });
    } finally {
      setState(() => _isExporting = false);
    }
  }

  void _openFileLocation(String filePath) {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        Process.run('explorer.exe', ['/select,', filePath]);
      } else {
        final dir = p.dirname(filePath);
        Process.run('explorer.exe', [dir]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.drive_file_move_outlined, color: theme.colorScheme.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daten Export & Berichte',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Inspektionen, Tür-Akten & Revisions-Audits exportieren',
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 32),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              // Scope Selector
              Text('1. Export-Umfang wählen', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<ExportScope>(
                segments: const [
                  ButtonSegment(
                    value: ExportScope.singleInspection,
                    label: Text('Inspektion'),
                    icon: Icon(Icons.assignment_outlined),
                  ),
                  ButtonSegment(
                    value: ExportScope.clientAudit,
                    label: Text('Kunden-Audit'),
                    icon: Icon(Icons.business_outlined),
                  ),
                  ButtonSegment(
                    value: ExportScope.doorHistory,
                    label: Text('Tür-Akte'),
                    icon: Icon(Icons.meeting_room_outlined),
                  ),
                ],
                selected: {_selectedScope},
                onSelectionChanged: (set) {
                  setState(() {
                    _selectedScope = set.first;
                    _searchController.clear();
                    _exportSuccessPath = null;
                    _errorMessage = null;
                  });
                },
              ),
              const SizedBox(height: 20),

              // Search Filter Bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: _selectedScope == ExportScope.singleInspection
                      ? 'Inspektionen durchsuchen (Auftrag, Kunde, Datum)...'
                      : _selectedScope == ExportScope.clientAudit
                          ? 'Kunden durchsuchen...'
                          : 'Tür-Alias / Nummer / Raum durchsuchen...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),

              // Specific Target Selector Dropdown
              if (_selectedScope == ExportScope.singleInspection) ...[
                Text('Inspektion auswählen (${_filteredInspections.length} von ${_inspections.length}):', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  value: _filteredInspections.any((i) => i['inspectionId'] == _selectedInspectionId)
                      ? _selectedInspectionId
                      : (_filteredInspections.isNotEmpty ? _filteredInspections.first['inspectionId'] as int? : null),
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: _filteredInspections.map((insp) {
                    final client = insp['clientName'] ?? 'Unbekannt';
                    final job = insp['jobNumber'] ?? '';
                    final date = insp['date'] ?? '';
                    return DropdownMenuItem<int>(
                      value: insp['inspectionId'] as int,
                      child: Text('$client | Auftrag: $job ($date)'),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedInspectionId = val),
                ),
              ] else if (_selectedScope == ExportScope.clientAudit) ...[
                Text('Kunde für Revisions-Audit wählen (${_filteredClients.length} von ${_clients.length}):', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _filteredClients.contains(_selectedClient)
                      ? _selectedClient
                      : (_filteredClients.isNotEmpty ? _filteredClients.first : null),
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: _filteredClients.map((client) {
                    return DropdownMenuItem<String>(
                      value: client,
                      child: Text(client),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedClient = val),
                ),
              ] else if (_selectedScope == ExportScope.doorHistory) ...[
                Text('Tür-Alias für Patientenauszug wählen (${_filteredDoorAliases.length} von ${_doorAliases.length}):', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _filteredDoorAliases.contains(_selectedDoorAlias)
                      ? _selectedDoorAlias
                      : (_filteredDoorAliases.isNotEmpty ? _filteredDoorAliases.first : null),
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: _filteredDoorAliases.map((alias) {
                    return DropdownMenuItem<String>(
                      value: alias,
                      child: Text('Tür-Alias: $alias'),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedDoorAlias = val),
                ),
              ],

              const SizedBox(height: 20),

              // Format Selector
              Text('2. Dateiformat wählen', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.table_chart, color: Colors.green, size: 18),
                          SizedBox(width: 8),
                          Text('Excel (.xlsx)'),
                        ],
                      ),
                      selected: _selectedFormat == ExportFormat.excel,
                      onSelected: (val) => setState(() => _selectedFormat = ExportFormat.excel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.picture_as_pdf, color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Text('PDF (.pdf)'),
                        ],
                      ),
                      selected: _selectedFormat == ExportFormat.pdf,
                      onSelected: (val) => setState(() => _selectedFormat = ExportFormat.pdf),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.storage, color: Colors.blue, size: 18),
                          SizedBox(width: 8),
                          Text('DB Paket (.db)'),
                        ],
                      ),
                      selected: _selectedFormat == ExportFormat.dbPackage,
                      onSelected: (val) => setState(() => _selectedFormat = ExportFormat.dbPackage),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Success Banner / Error Banner
              if (_exportSuccessPath != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Export erfolgreich erstellt!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            Text(_exportSuccessPath!, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('Ordner öffnen'),
                        onPressed: () => _openFileLocation(_exportSuccessPath!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Footer Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isExporting ? null : _executeExport,
                    icon: _isExporting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download),
                    label: Text(_isExporting ? 'Exportiere...' : 'Jetzt Exportieren'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
