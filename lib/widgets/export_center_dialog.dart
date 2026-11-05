import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/services/excel_export_service.dart';
import 'package:wartungstool/services/pdf_export_service.dart';
import 'package:wartungstool/services/photo_export_service.dart';
import 'package:wartungstool/services/craftnote_api_service.dart';
import 'package:wartungstool/services/craftnote_sync_service.dart';
import 'package:wartungstool/models/craftnote_models.dart';
import 'package:wartungstool/services/craftnote_credentials_service.dart';
import 'package:wartungstool/widgets/craftnote_settings_dialog.dart';
import '../utils/file_export_helper.dart';

enum ExportScope { singleInspection, clientAudit, doorHistory }

enum ExportFormat { excel, pdf, dbPackage, photos, craftnote }

class ExportCenterDialog extends StatefulWidget {
  final int? initialInspectionId;
  final String? initialDoorAlias;
  final bool isManagerMode;

  const ExportCenterDialog({
    super.key,
    this.initialInspectionId,
    this.initialDoorAlias,
    this.isManagerMode = false,
  });

  static Future<void> show(BuildContext context,
      {int? initialInspectionId,
      String? initialDoorAlias,
      bool isManagerMode = false}) async {
    await showDialog(
      context: context,
      builder: (context) => ExportCenterDialog(
        initialInspectionId: initialInspectionId,
        initialDoorAlias: initialDoorAlias,
        isManagerMode: isManagerMode,
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

  List<CraftnoteProject> _craftnoteProjects = [];
  CraftnoteProject? _selectedCraftnoteProject;
  CraftnoteProject? _matchedProductionProject;
  bool _postChatMessage = false;
  bool _isLoadingCraftnoteProjects = false;
  String? _craftnoteProjectsError;
  String _targetProjectName = '';
  String _targetAngebotsnummer = '';

  bool _isLoading = true;
  bool _isExporting = false;
  String? _exportSuccessPath;
  String? _errorMessage;

  String _getEffectiveAuftragsnummer() {
    if (_selectedInspectionId != null && _inspections.isNotEmpty) {
      final insp = _inspections.firstWhere(
        (i) => i['inspectionId'] == _selectedInspectionId,
        orElse: () => <String, dynamic>{},
      );
      final job =
          (insp['jobNumber'] ?? insp['auftragsnummer'] ?? '').toString().trim();
      if (job.isNotEmpty) return job;
    }
    // Default test fallback when no job number or inspection selected
    return '26-00251-AN';
  }

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

  Future<Map<String, String>?> _promptProjectSearchDialog(
      {String? initialId}) async {
    final idCtrl =
        TextEditingController(text: initialId ?? _targetAngebotsnummer);
    final nameCtrl = TextEditingController(text: _targetProjectName);

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.search, color: Colors.orange),
              SizedBox(width: 10),
              Expanded(
                child: Text('Craftnote-Zielprojekt suchen (Testumgebung)',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Geben Sie die ID-Nummer / Auftragsnummer oder den Projektnamen ein, um das Craftnote-Projekt abzufragen:',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Auftragsnummer / Angebotsnummer (Qomet)',
                    hintText: '26-00251-AN',
                    prefixIcon: Icon(Icons.tag),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Projektname in Craftnote (optional)',
                    hintText: '202121 Industrie GmbH Unit 2 - Unbekannt',
                    prefixIcon: Icon(Icons.business),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Projekt suchen'),
              onPressed: () {
                Navigator.of(ctx).pop({
                  'idNumber': idCtrl.text.trim(),
                  'projectName': nameCtrl.text.trim(),
                });
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _promptAndLoadCraftnoteProjects(
      {bool forcePrompt = false}) async {
    final effectiveAuftrag = _getEffectiveAuftragsnummer();

    if (forcePrompt) {
      final searchParams =
          await _promptProjectSearchDialog(initialId: effectiveAuftrag);
      if (searchParams == null && _craftnoteProjects.isEmpty) {
        return;
      }
      if (searchParams != null) {
        _targetAngebotsnummer =
            searchParams['idNumber'] ?? _targetAngebotsnummer;
        _targetProjectName = searchParams['projectName'] ?? _targetProjectName;
      }
    } else {
      // Automatically query using the inspection's Auftragsnummer
      _targetAngebotsnummer = effectiveAuftrag;
    }

    setState(() {
      _isLoadingCraftnoteProjects = true;
      _craftnoteProjectsError = null;
    });

    try {
      final service = CraftnoteApiService();
      print(
          '[ExportCenterDialog] Searching Craftnote projects: Auftragsnummer="$_targetAngebotsnummer", Name="$_targetProjectName"');

      List<CraftnoteProject> results = [];
      if (_targetAngebotsnummer.isNotEmpty || _targetProjectName.isNotEmpty) {
        results = await service.findProjects(
          orderNumber:
              _targetAngebotsnummer.isNotEmpty ? _targetAngebotsnummer : null,
          name: _targetProjectName.isNotEmpty ? _targetProjectName : null,
          status: 'active',
        );
      } else {
        results = await service.getProjects(limit: 50, status: 'active');
      }

      if (mounted) {
        setState(() {
          _matchedProductionProject = results.isNotEmpty ? results.first : null;

          if (CraftnoteCredentialsService.isTestMode) {
            // In Test Mode: Lock upload destination to sandbox test project to protect production data
            _selectedCraftnoteProject = CraftnoteProject(
              id: CraftnoteCredentialsService.testProjectId,
              name: CraftnoteCredentialsService.testProjectName,
              orderNumber: CraftnoteCredentialsService.testProjectOrderNumber,
            );
            _craftnoteProjects = [_selectedCraftnoteProject!];
            _craftnoteProjectsError = null;
            print(
                '[ExportCenterDialog] 🛡️ Test Mode active. Matched production: ${_matchedProductionProject?.name ?? "None"}. Locked target: ${_selectedCraftnoteProject!.name} (${_selectedCraftnoteProject!.id})');
          } else {
            // In Production Mode: Select matched project or allow selection
            _craftnoteProjects = results;
            if (_craftnoteProjects.isNotEmpty) {
              _selectedCraftnoteProject = _craftnoteProjects.first;
              _craftnoteProjectsError = null;
            } else {
              _selectedCraftnoteProject = null;
              _craftnoteProjectsError =
                  'Kein Projekt in Craftnote gefunden für Auftragsnummer "$_targetAngebotsnummer"${_targetProjectName.isNotEmpty ? ' / Name "$_targetProjectName"' : ''}.';
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _craftnoteProjectsError = '$e';
          _errorMessage = 'Craftnote-Projekte konnten nicht geladen werden: $e';
          _selectedCraftnoteProject = null;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingCraftnoteProjects = false);
    }
  }

  Future<void> _loadCraftnoteProjects() =>
      _promptAndLoadCraftnoteProjects(forcePrompt: false);

  Future<String> _getExportDirectory() async {
    Directory? downloadsDir;
    try {
      downloadsDir = await getDownloadsDirectory();
    } catch (_) {}
    downloadsDir ??= await getApplicationDocumentsDirectory();
    final exportDir =
        Directory(p.join(downloadsDir.path, 'WartungsTool_Exports'));
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
      final now = DateTime.now();
      final dateStr =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final timestamp = '${dateStr}_$timeStr';
      String targetPath = '';

      if (_selectedScope == ExportScope.singleInspection) {
        if (_selectedInspectionId == null) {
          throw Exception('Bitte wählen Sie eine Inspektion aus.');
        }

        if (!widget.isManagerMode) {
          final doors = await LocalDatabaseService.getDoorsByInspectionId(
              _selectedInspectionId!);
          final statuses = await LocalDatabaseService.getDoorInspectionStatuses(
              _selectedInspectionId!);
          if (!mounted) return;
          final canProceed = await FileExportHelper.confirmUnprocessedDoors(
            context: context,
            doors: doors,
            statuses: statuses,
            actionName: 'Export',
          );
          if (!canProceed || !mounted) {
            if (mounted) setState(() => _isExporting = false);
            return;
          }
        }

        final insp = _inspections
            .firstWhere((i) => i['inspectionId'] == _selectedInspectionId);
        final jobStr = insp['jobNumber'] ?? 'Auftrag';
        final safeJob = jobStr.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

        if (_selectedFormat == ExportFormat.excel) {
          targetPath =
              p.join(exportDir, 'Inspektion_${safeJob}_$timestamp.xlsx');
          await ExcelExportService.exportSingleInspection(
              _selectedInspectionId!, targetPath);
        } else if (_selectedFormat == ExportFormat.pdf) {
          targetPath =
              p.join(exportDir, 'Inspektion_${safeJob}_$timestamp.pdf');
          await PdfExportService.exportSingleInspectionPdf(
              _selectedInspectionId!, targetPath);
        } else if (_selectedFormat == ExportFormat.dbPackage) {
          final fileName = FileExportHelper.buildPackageFileName(
            jobNumber: insp['jobNumber']?.toString() ??
                insp['auftragsnummer']?.toString(),
            projectNumber: insp['projectNumber']?.toString(),
            objectAddress: insp['objectAddress']?.toString() ??
                insp['clientName']?.toString(),
            packageType: 'inspektion_paket',
          );
          targetPath = p.join(exportDir, fileName);
          await DatabaseService.exportJobPackage([_selectedInspectionId!],
              destinationPath: targetPath);
        } else if (_selectedFormat == ExportFormat.photos) {
          final photoResult = await PhotoExportService.exportInspectionPhotos(
            inspectionId: _selectedInspectionId!,
            isManagerMode: widget.isManagerMode,
          );
          targetPath = photoResult.outputDirectory;
          if (photoResult.totalPhotos == 0) {
            _exportSuccessPath =
                'Ordner erstellt (Keine Fotos in diesem Auftrag vorhanden):\n$targetPath';
          } else {
            _exportSuccessPath =
                '${photoResult.totalPhotos} Foto(s) erfolgreich exportiert in:\n$targetPath';
          }
        } else if (_selectedFormat == ExportFormat.craftnote) {
          if (_selectedScope != ExportScope.singleInspection ||
              _selectedInspectionId == null) {
            throw Exception(
                'Craftnote-Export wird für Einzel-Inspektionen unterstützt.');
          }
          if (_selectedCraftnoteProject == null) {
            throw Exception('Bitte wählen Sie ein Craftnote-Zielprojekt aus.');
          }
          final syncService = CraftnoteSyncService();
          final syncResult = await syncService.exportInspectionFromMasterDb(
            inspectionId: _selectedInspectionId!,
            craftnoteProjectId: _selectedCraftnoteProject!.id,
            syncPhotos: true,
            postChatMessage: _postChatMessage,
          );
          if (!syncResult.success) {
            throw Exception(syncResult.message);
          }
          final photoSummary = syncResult.totalPhotos > 0
              ? '\n• Fotos: ${syncResult.uploadedPhotos} neu hochgeladen, ${syncResult.skippedPhotos} bereits vorhanden in Ordner "Fotomaterial"'
              : '\n• Fotos: Keine Fotos in diesem Auftrag vorhanden';

          final isTestMode = CraftnoteCredentialsService.isTestMode;
          final modeNote = isTestMode
              ? '\n• Modus: 🛡️ Test-Modus aktiv (Gespeichert im Sandbox-Testprojekt #${CraftnoteCredentialsService.testProjectOrderNumber})'
              : '\n• Modus: ⚠️ Produktiv-Modus (Gespeichert in ${_selectedCraftnoteProject!.name})';

          _exportSuccessPath = 'Erfolgreich nach Craftnote übertragen:\n'
              '• Zielprojekt: ${_selectedCraftnoteProject!.name} (#${_selectedCraftnoteProject!.orderNumber})'
              '$modeNote\n'
              '• Wartungsliste (.db): Gespeichert in Ordner "Wartungslisten"$photoSummary\n\n'
              '${syncResult.message}';
          targetPath = 'craftnote:${_selectedCraftnoteProject!.id}';
        }
      } else if (_selectedScope == ExportScope.clientAudit) {
        if (_selectedClient == null || _selectedClient!.isEmpty) {
          throw Exception('Bitte wählen Sie einen Kunden aus.');
        }
        final safeClient =
            _selectedClient!.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

        if (_selectedFormat == ExportFormat.excel) {
          targetPath =
              p.join(exportDir, 'Kunden_Audit_${safeClient}_$timestamp.xlsx');
          await ExcelExportService.exportClientAudit(
              _selectedClient!, targetPath);
        } else if (_selectedFormat == ExportFormat.pdf) {
          targetPath =
              p.join(exportDir, 'Kunden_Audit_${safeClient}_$timestamp.pdf');
          // Export first inspection or full audit payload to PDF
          final inspList = _inspections
              .where((i) => i['clientName'] == _selectedClient)
              .toList();
          if (inspList.isNotEmpty) {
            await PdfExportService.exportSingleInspectionPdf(
                inspList.first['inspectionId'] as int, targetPath);
          } else {
            throw Exception('Keine Inspektionen für diesen Kunden vorhanden.');
          }
        } else if (_selectedFormat == ExportFormat.dbPackage) {
          targetPath =
              p.join(exportDir, 'Kunden_Audit_${safeClient}_$timestamp.db');
          final clientInsps = _inspections
              .where((i) => i['clientName'] == _selectedClient)
              .map((i) => i['inspectionId'] as int)
              .toList();
          await DatabaseService.exportJobPackage(clientInsps,
              destinationPath: targetPath);
        }
      } else if (_selectedScope == ExportScope.doorHistory) {
        if (_selectedDoorAlias == null || _selectedDoorAlias!.isEmpty) {
          throw Exception('Bitte wählen Sie einen Tür-Alias aus.');
        }
        final safeAlias =
            _selectedDoorAlias!.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final historyData = await DatabaseService.getDoorHistoryData(
            doorAlias: _selectedDoorAlias!);
        if (historyData == null || historyData.isEmpty) {
          throw Exception('Tür-Akte nicht gefunden.');
        }

        if (_selectedFormat == ExportFormat.excel) {
          targetPath =
              p.join(exportDir, 'TuerAkte_${safeAlias}_$timestamp.xlsx');
          await ExcelExportService.exportDoorHistoryReport(
              historyData, targetPath);
        } else if (_selectedFormat == ExportFormat.pdf) {
          targetPath =
              p.join(exportDir, 'TuerAkte_${safeAlias}_$timestamp.pdf');
          await PdfExportService.exportDoorHistoryPdf(historyData, targetPath);
        } else if (_selectedFormat == ExportFormat.dbPackage) {
          targetPath = p.join(exportDir, 'TuerAkte_${safeAlias}_$timestamp.db');
          final doorObj = historyData['door'];
          final doorId = (doorObj is Door)
              ? doorObj.id
              : (doorObj is Map ? doorObj['id'] as int? : null);
          if (doorId != null) {
            await DatabaseService.exportDoorsPackage([doorId],
                destinationPath: targetPath);
          }
        }
      }

      if (!widget.isManagerMode && _selectedInspectionId != null) {
        await LocalDatabaseService.setInspectionLockStatus(
            _selectedInspectionId!, true);
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 860),
        child: Padding(
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
                    child: Icon(Icons.drive_file_move_outlined,
                        color: theme.colorScheme.primary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daten Export & Berichte',
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Inspektionen, Tür-Akten & Revisions-Audits exportieren',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey.shade600),
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
              const Divider(height: 24),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        // Scope Selector
                        Text('1. Export-Umfang wählen',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
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
                            hintText: _selectedScope ==
                                    ExportScope.singleInspection
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
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),

                        // Specific Target Selector Dropdown
                        if (_selectedScope == ExportScope.singleInspection) ...[
                          Text(
                              'Inspektion auswählen (${_filteredInspections.length} von ${_inspections.length}):',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<int>(
                            initialValue: _filteredInspections.any((i) =>
                                    i['inspectionId'] == _selectedInspectionId)
                                ? _selectedInspectionId
                                : (_filteredInspections.isNotEmpty
                                    ? _filteredInspections.first['inspectionId']
                                        as int?
                                    : null),
                            isExpanded: true,
                            decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10)),
                            items: _filteredInspections.map((insp) {
                              final client = insp['clientName'] ?? 'Unbekannt';
                              final job = insp['jobNumber'] ?? '';
                              final date = insp['date'] ?? '';
                              return DropdownMenuItem<int>(
                                value: insp['inspectionId'] as int,
                                child: Text('$client | Auftrag: $job ($date)'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() => _selectedInspectionId = val);
                              if (_selectedFormat == ExportFormat.craftnote) {
                                _loadCraftnoteProjects();
                              }
                            },
                          ),
                        ] else if (_selectedScope ==
                            ExportScope.clientAudit) ...[
                          Text(
                              'Kunde für Revisions-Audit wählen (${_filteredClients.length} von ${_clients.length}):',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue:
                                _filteredClients.contains(_selectedClient)
                                    ? _selectedClient
                                    : (_filteredClients.isNotEmpty
                                        ? _filteredClients.first
                                        : null),
                            isExpanded: true,
                            decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10)),
                            items: _filteredClients.map((client) {
                              return DropdownMenuItem<String>(
                                value: client,
                                child: Text(client),
                              );
                            }).toList(),
                            onChanged: (val) =>
                                setState(() => _selectedClient = val),
                          ),
                        ] else if (_selectedScope ==
                            ExportScope.doorHistory) ...[
                          Text(
                              'Tür-Alias für Patientenauszug wählen (${_filteredDoorAliases.length} von ${_doorAliases.length}):',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _filteredDoorAliases
                                    .contains(_selectedDoorAlias)
                                ? _selectedDoorAlias
                                : (_filteredDoorAliases.isNotEmpty
                                    ? _filteredDoorAliases.first
                                    : null),
                            isExpanded: true,
                            decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10)),
                            items: _filteredDoorAliases.map((alias) {
                              return DropdownMenuItem<String>(
                                value: alias,
                                child: Text('Tür-Alias: $alias'),
                              );
                            }).toList(),
                            onChanged: (val) =>
                                setState(() => _selectedDoorAlias = val),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Format Selector
                        Text('2. Dateiformat wählen',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.table_chart,
                                      color: Colors.green, size: 18),
                                  SizedBox(width: 8),
                                  Text('Excel (.xlsx)'),
                                ],
                              ),
                              selected: _selectedFormat == ExportFormat.excel,
                              onSelected: (val) => setState(
                                  () => _selectedFormat = ExportFormat.excel),
                            ),
                            ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.picture_as_pdf,
                                      color: Colors.red, size: 18),
                                  SizedBox(width: 8),
                                  Text('PDF (.pdf)'),
                                ],
                              ),
                              selected: _selectedFormat == ExportFormat.pdf,
                              onSelected: (val) => setState(
                                  () => _selectedFormat = ExportFormat.pdf),
                            ),
                            ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.storage,
                                      color: Colors.blue, size: 18),
                                  SizedBox(width: 8),
                                  Text('DB Paket (.db)'),
                                ],
                              ),
                              selected:
                                  _selectedFormat == ExportFormat.dbPackage,
                              onSelected: (val) => setState(() =>
                                  _selectedFormat = ExportFormat.dbPackage),
                            ),
                            ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.photo_library,
                                      color: Colors.purple, size: 18),
                                  SizedBox(width: 8),
                                  Text('Fotos (JPG-Ordner)'),
                                ],
                              ),
                              selected: _selectedFormat == ExportFormat.photos,
                              onSelected: (val) => setState(
                                  () => _selectedFormat = ExportFormat.photos),
                            ),
                            ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.cloud_upload,
                                      color: Colors.orange, size: 18),
                                  SizedBox(width: 8),
                                  Text('Craftnote Cloud'),
                                ],
                              ),
                              selected:
                                  _selectedFormat == ExportFormat.craftnote,
                              onSelected: (val) {
                                setState(() =>
                                    _selectedFormat = ExportFormat.craftnote);
                                _loadCraftnoteProjects();
                              },
                            ),
                          ],
                        ),

                        if (_selectedFormat == ExportFormat.craftnote) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Text(
                                '3. Craftnote Cloud-Export',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.search,
                                    size: 20, color: Colors.orange),
                                tooltip:
                                    'Projektsuche / Auftragsnummer anpassen',
                                onPressed: () =>
                                    _promptAndLoadCraftnoteProjects(
                                        forcePrompt: true),
                              ),
                              IconButton(
                                icon: const Icon(Icons.settings, size: 18),
                                tooltip: 'Craftnote API-Einstellungen',
                                onPressed: () async {
                                  final updated =
                                      await CraftnoteSettingsDialog.show(
                                          context);
                                  if (updated == true) _loadCraftnoteProjects();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh, size: 18),
                                tooltip: 'Erneut abfragen',
                                onPressed: _loadCraftnoteProjects,
                              ),
                            ],
                          ),

                          if (_isLoadingCraftnoteProjects)
                            const Center(
                                child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator()))
                          else ...[
                            // Card A: Auftragsnummer Search Feedback
                            Container(
                              margin: const EdgeInsets.only(top: 6, bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _matchedProductionProject != null
                                    ? Colors.green.shade50
                                    : Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _matchedProductionProject != null
                                      ? Colors.green.shade300
                                      : Colors.amber.shade300,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    _matchedProductionProject != null
                                        ? Icons.check_circle
                                        : Icons.info_outline,
                                    color: _matchedProductionProject != null
                                        ? Colors.green.shade700
                                        : Colors.amber.shade800,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _matchedProductionProject != null
                                              ? 'Projekt in Craftnote gefunden (Auftrag: $_targetAngebotsnummer)'
                                              : 'Kein Projekt für Auftrag "$_targetAngebotsnummer" in Craftnote gefunden',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: _matchedProductionProject !=
                                                    null
                                                ? Colors.green.shade900
                                                : Colors.amber.shade900,
                                          ),
                                        ),
                                        if (_matchedProductionProject !=
                                            null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Name: ${_matchedProductionProject!.name}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500),
                                          ),
                                          Text(
                                            'Craftnote-ID: ${_matchedProductionProject!.id}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade700),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Card B: Target Destination & Test Sandbox Safety Guard
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: CraftnoteCredentialsService.isTestMode
                                    ? Colors.blue.shade50
                                    : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: CraftnoteCredentialsService.isTestMode
                                      ? Colors.blue.shade300
                                      : Colors.red.shade300,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        CraftnoteCredentialsService.isTestMode
                                            ? Icons.shield
                                            : Icons.warning_amber_rounded,
                                        color: CraftnoteCredentialsService
                                                .isTestMode
                                            ? Colors.blue.shade800
                                            : Colors.red.shade800,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          CraftnoteCredentialsService.isTestMode
                                              ? 'Test-Modus aktiv (Sandbox-Schutz)'
                                              : 'PRODUKTIV-MODUS AKTIV',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: CraftnoteCredentialsService
                                                    .isTestMode
                                                ? Colors.blue.shade900
                                                : Colors.red.shade900,
                                          ),
                                        ),
                                      ),
                                      Tooltip(
                                        message: CraftnoteCredentialsService
                                                .isTestMode
                                            ? 'Klicken, um in Produktiv-Modus zu wechseln'
                                            : 'Klicken, um in Test-Modus (Sandbox) zu wechseln',
                                        child: Switch(
                                          value: CraftnoteCredentialsService
                                              .isTestMode,
                                          activeThumbColor:
                                              Colors.blue.shade700,
                                          onChanged: (val) {
                                            setState(() {
                                              CraftnoteCredentialsService
                                                  .setTestMode(val);
                                              _loadCraftnoteProjects();
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    CraftnoteCredentialsService.isTestMode
                                        ? 'Upload-Ziel (Sandbox): ${CraftnoteCredentialsService.testProjectName} (#${CraftnoteCredentialsService.testProjectOrderNumber})\n• POST-Schreibzugriffe auf Produktivprojekte sind zum Schutz gesperrt.'
                                        : 'Upload-Ziel: ${_selectedCraftnoteProject?.name ?? "Kein Projekt"}\n• ACHTUNG: Daten werden direkt in das Produktivprojekt übertragen!',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          CraftnoteCredentialsService.isTestMode
                                              ? Colors.blue.shade900
                                              : Colors.red.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            if (!CraftnoteCredentialsService.isTestMode &&
                                _craftnoteProjectsError != null) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  _craftnoteProjectsError!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.amber.shade900),
                                ),
                              ),
                            ],

                            if (!CraftnoteCredentialsService.isTestMode &&
                                _craftnoteProjects.isNotEmpty) ...[
                              DropdownButtonFormField<String>(
                                initialValue: _selectedCraftnoteProject?.id,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Zielprojekt für Upload wählen',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                                items: _craftnoteProjects.map((p) {
                                  return DropdownMenuItem<String>(
                                    value: p.id,
                                    child: Text(
                                        '${p.name} ${p.orderNumber.isNotEmpty ? "(#${p.orderNumber})" : ""}'),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedCraftnoteProject =
                                          _craftnoteProjects
                                              .firstWhere((p) => p.id == val);
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 6),
                            ],
                          ],

                          // Standard Destination Folders Info Card
                          Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: Colors.blueGrey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.auto_awesome,
                                        size: 18,
                                        color: Colors.blueGrey.shade800),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Automatisches Datei-Routing:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.description,
                                        size: 16, color: Colors.blue),
                                    const SizedBox(width: 6),
                                    const Expanded(
                                      child: Text(
                                        'Wartungspaket (.db)  ➔  Ordner "Wartungslisten"',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.photo_library,
                                        size: 16, color: Colors.green),
                                    const SizedBox(width: 6),
                                    const Expanded(
                                      child: Text(
                                        'Mängelfotos (.jpg)  ➔  Ordner "Fotomaterial" (Deduplizierung aktiv)',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Optional Project Chat Message Toggle
                          Material(
                            color: _postChatMessage
                                ? Colors.amber.shade50
                                : Colors.grey.shade50,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: _postChatMessage
                                    ? Colors.amber.shade300
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: SwitchListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 0),
                              title: const Text(
                                'Statusmeldung in Craftnote-Projektchat posten',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                _postChatMessage
                                    ? 'Aktiviert. Hinweis: Erfordert eine "Advanced API"-Lizenz von Craftnote.'
                                    : 'Deaktiviert (Empfohlen). Datei wird ohne Chat-Meldung hochgeladen.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _postChatMessage
                                      ? Colors.amber.shade900
                                      : Colors.grey.shade600,
                                ),
                              ),
                              value: _postChatMessage,
                              activeThumbColor: Colors.amber.shade800,
                              onChanged: (val) {
                                setState(() => _postChatMessage = val);
                              },
                            ),
                          ),
                        ],

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
                                const Icon(Icons.check_circle,
                                    color: Colors.green),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Export erfolgreich erstellt!',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green)),
                                      Text(_exportSuccessPath!,
                                          style: const TextStyle(fontSize: 11),
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                if (!_exportSuccessPath!
                                        .startsWith('craftnote:') &&
                                    !_exportSuccessPath!
                                        .contains('Craftnote übertragen'))
                                  ElevatedButton.icon(
                                    icon:
                                        const Icon(Icons.folder_open, size: 16),
                                    label: const Text('Ordner öffnen'),
                                    onPressed: () =>
                                        _openFileLocation(_exportSuccessPath!),
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
                                const Icon(Icons.error_outline,
                                    color: Colors.red),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(_errorMessage!,
                                      style:
                                          const TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

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
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download),
                    label: Text(
                        _isExporting ? 'Exportiere...' : 'Jetzt Exportieren'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
