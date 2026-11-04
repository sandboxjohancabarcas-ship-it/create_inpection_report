import 'package:flutter/material.dart';
import 'package:wartungstool/models/craftnote_models.dart';
import 'package:wartungstool/services/craftnote_api_service.dart';
import 'package:wartungstool/services/craftnote_credentials_service.dart';
import 'package:wartungstool/services/craftnote_sync_service.dart';
import 'package:wartungstool/widgets/craftnote_settings_dialog.dart';

/// Modal dialog allowing inspectors and managers to input an Auftragsnummer (OrderNumber),
/// find the corresponding Craftnote project directly without navigating all company projects,
/// and immediately download and import the designated inspection package (.db).
/// In manager mode, it specifically discovers and imports the inspector's result package (*ergebnis*.db)
/// directly into the Master Database.
class CraftnoteJobPickerModal extends StatefulWidget {
  final String? initialOrderNumber;
  final bool isManagerMode;

  const CraftnoteJobPickerModal({
    super.key,
    this.initialOrderNumber,
    this.isManagerMode = false,
  });

  static Future<CraftnoteImportResult?> show(
    BuildContext context, {
    String? initialOrderNumber,
    bool isManagerMode = false,
  }) async {
    return await showDialog<CraftnoteImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CraftnoteJobPickerModal(
        initialOrderNumber: initialOrderNumber,
        isManagerMode: isManagerMode,
      ),
    );
  }

  @override
  State<CraftnoteJobPickerModal> createState() => _CraftnoteJobPickerModalState();
}

class _CraftnoteJobPickerModalState extends State<CraftnoteJobPickerModal> {
  final CraftnoteApiService _apiService = CraftnoteApiService();
  final CraftnoteSyncService _syncService = CraftnoteSyncService();

  late final TextEditingController _orderNumberController;

  CraftnoteProject? _foundProject;
  List<CraftnoteFile> _availablePackages = [];

  bool _isSearching = false;
  bool _isImporting = false;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final defaultOrder = widget.initialOrderNumber ??
        (CraftnoteCredentialsService.isTestMode
            ? CraftnoteCredentialsService.testProjectOrderNumber
            : '');
    _orderNumberController = TextEditingController(text: defaultOrder);
  }

  @override
  void dispose() {
    _orderNumberController.dispose();
    super.dispose();
  }

  Future<void> _searchAndImportProject() async {
    final rawInput = _orderNumberController.text.trim();
    final cleanInput = rawInput.replaceAll('#', '').trim();

    if (cleanInput.isEmpty) {
      setState(() {
        _errorMessage = 'Bitte geben Sie eine Auftragsnummer oder einen Projektnamen ein.';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isImporting = false;
      _errorMessage = null;
      _foundProject = null;
      _availablePackages = [];
      _statusMessage = 'Suche Craftnote-Projekt für Auftragsnummer "$rawInput"...';
    });

    try {
      // 1. Search Craftnote for project by orderNumber / query
      List<CraftnoteProject> results = await _apiService.findProjects(
        orderNumber: cleanInput,
        query: cleanInput,
        maxPages: 25,
      );

      CraftnoteProject? matchedProject;
      if (results.isNotEmpty) {
        matchedProject = results.first;
      } else if (CraftnoteCredentialsService.isTestMode &&
          (cleanInput == CraftnoteCredentialsService.testProjectOrderNumber ||
              cleanInput.toLowerCase().contains('industrie') ||
              cleanInput == '26-00251-AN')) {
        // Fallback in Test Mode for sandbox project
        try {
          matchedProject = await _apiService.getProjectById(CraftnoteCredentialsService.testProjectId);
        } catch (_) {}
      }

      if (matchedProject == null) {
        setState(() {
          _errorMessage = 'Kein Craftnote-Projekt mit Auftragsnummer "$rawInput" gefunden.\n'
              'Bitte überprüfen Sie die Nummer oder stellen Sie sicher, dass der Auftrag in Craftnote angelegt wurde.';
        });
        return;
      }

      setState(() {
        _foundProject = matchedProject;
        _statusMessage = widget.isManagerMode
            ? 'Projekt "${matchedProject!.name}" gefunden. Suche Prüfergebnis-Paket (*ergebnis*.db)...'
            : 'Projekt "${matchedProject!.name}" gefunden. Suche Wartungspaket...';
      });

      // 2. Resolve database packages in the project (prioritizing "Wartungslisten")
      // In manager mode, enforce requirement 3: package must contain the word "ergebnis"
      // In inspector mode, target the initial job package and exclude finished "ergebnis" packages
      var packages = await _syncService.getProjectDbPackages(
        matchedProject.id,
        mustContainWord: widget.isManagerMode ? 'ergebnis' : null,
        excludeWord: widget.isManagerMode ? null : 'ergebnis',
      );

      // In Test Mode: The inspector upload was redirected to the sandbox test project.
      // If no package was found in the matched production project, also search the Sandbox Test Project
      // for packages matching the requested Auftragsnummer!
      if (CraftnoteCredentialsService.isTestMode &&
          matchedProject.id != CraftnoteCredentialsService.testProjectId &&
          packages.isEmpty) {
        try {
          final testProjectPackages = await _syncService.getProjectDbPackages(
            CraftnoteCredentialsService.testProjectId,
            mustContainWord: widget.isManagerMode ? 'ergebnis' : null,
            excludeWord: widget.isManagerMode ? null : 'ergebnis',
          );
          final matchingTestPackages = testProjectPackages.where((p) {
            final name = p.name.toLowerCase();
            return name.contains(cleanInput.toLowerCase());
          }).toList();

          if (matchingTestPackages.isNotEmpty) {
            packages = matchingTestPackages;
            final testProj = await _apiService.getProjectById(CraftnoteCredentialsService.testProjectId);
            matchedProject = testProj;
            _foundProject = testProj;
            _statusMessage = '🛡️ Test-Modus: Prüfergebnis für #$cleanInput im Sandbox-Testprojekt gefunden.';
          }
        } catch (_) {}
      }

      // If matchedProject is the test project and user typed a specific order number, filter by it
      if (matchedProject != null &&
          matchedProject.id == CraftnoteCredentialsService.testProjectId &&
          cleanInput != CraftnoteCredentialsService.testProjectOrderNumber &&
          !cleanInput.toLowerCase().contains('industrie')) {
        final filteredByOrder = packages.where((p) => p.name.toLowerCase().contains(cleanInput.toLowerCase())).toList();
        if (filteredByOrder.isNotEmpty) {
          packages = filteredByOrder;
        }
      }

      if (packages.isEmpty) {
        setState(() {
          _errorMessage = widget.isManagerMode
              ? 'Projekt "${matchedProject!.name}" (#${matchedProject.orderNumber}) gefunden, '
                  'aber es wurde noch kein Prüfergebnis-Paket (*ergebnis*.db) vom Techniker in Craftnote hinterlegt.\n'
                  'Bitte stellen Sie sicher, dass der Techniker die Prüfung abgeschlossen und synchronisiert hat.'
              : 'Projekt "${matchedProject!.name}" (#${matchedProject.orderNumber}) gefunden, '
                  'aber es wurde noch kein Wartungspaket (.db) in Craftnote bereitgestellt (z. B. im Ordner "Wartungslisten").\n'
                  'Bitte kontaktieren Sie den Projektleiter oder Manager.';
        });
        return;
      }

      if (packages.length == 1) {
        // Exactly one package: auto-execute download and import
        await _executeImport(matchedProject!, packages.first);
      } else {
        // Multiple packages: let user pick the package version
        setState(() {
          _availablePackages = packages;
          _statusMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Fehler beim Suchen des Projekts in Craftnote:\n$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _executeImport(CraftnoteProject project, CraftnoteFile file) async {
    setState(() {
      _isImporting = true;
      _statusMessage = widget.isManagerMode
          ? 'Lade "${file.name}" herunter und integriere Prüfung in die Master-Datenbank...'
          : 'Lade "${file.name}" herunter und importiere in die lokale Datenbank...';
      _errorMessage = null;
    });

    try {
      final result = await _syncService.downloadAndImportPackage(
        project: project,
        file: file,
        isManagerMode: widget.isManagerMode,
      );

      if (mounted) {
        if (result.success) {
          Navigator.of(context).pop(result);
        } else {
          setState(() {
            _errorMessage = result.message;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Import fehlgeschlagen: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTestMode = CraftnoteCredentialsService.isTestMode;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
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
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.cloud_download, color: Colors.blue.shade700, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isManagerMode
                              ? 'Prüfergebnis aus Craftnote importieren'
                              : 'Auftrag aus Craftnote laden',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.isManagerMode
                              ? 'Gezielter Import des Techniker-Ergebnisses (*ergebnis*.db) in die Master-DB'
                              : 'Gezielter Import über die Auftragsnummer',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, size: 20),
                    tooltip: 'Craftnote-Einstellungen',
                    onPressed: _isSearching || _isImporting
                        ? null
                        : () async {
                            final changed = await CraftnoteSettingsDialog.show(context);
                            if (changed == true && mounted) {
                              setState(() {
                                if (CraftnoteCredentialsService.isTestMode &&
                                    _orderNumberController.text.trim().isEmpty) {
                                  _orderNumberController.text =
                                      CraftnoteCredentialsService.testProjectOrderNumber;
                                }
                              });
                            }
                          },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSearching || _isImporting
                        ? null
                        : () => Navigator.of(context).pop(),
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
                      // Test Sandbox Badge
                      if (isTestMode)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.shield_outlined, color: Colors.amber.shade900, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Testumgebung aktiv: Zugriff auf Sandbox-Projekt #${CraftnoteCredentialsService.testProjectOrderNumber}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Input section for Auftragsnummer
                      Text(
                        '1. Auftragsnummer (Auftragsschlüssel) eingeben:',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _orderNumberController,
                              enabled: !_isSearching && !_isImporting,
                              decoration: InputDecoration(
                                labelText: 'Auftragsnummer / OrderNumber',
                                hintText: 'z. B. 26-00251-AN oder 23-09574-AB',
                                prefixIcon: const Icon(Icons.assignment_outlined),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                suffixIcon: _orderNumberController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: _isSearching || _isImporting
                                            ? null
                                            : () => _orderNumberController.clear(),
                                      )
                                    : null,
                              ),
                              onSubmitted: (_) => _searchAndImportProject(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            onPressed: _isSearching || _isImporting
                                ? null
                                : _searchAndImportProject,
                            icon: const Icon(Icons.search, size: 18),
                            label: const Text('Suchen & Laden'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Progress Spinner Banner
                      if (_isSearching || _isImporting)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  _statusMessage ?? 'Verarbeite...',
                                  style: TextStyle(
                                    color: Colors.blue.shade900,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Error Banner
                      if (_errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Colors.red, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Found Project Card
                      if (_foundProject != null) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Zugehöriges Craftnote-Projekt gefunden:',
                                      style: TextStyle(
                                        color: Colors.green.shade900,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _foundProject!.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              if (_foundProject!.orderNumber.isNotEmpty)
                                Text(
                                  'Auftragsnummer: #${_foundProject!.orderNumber}',
                                  style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
                                ),
                              if (_foundProject!.fullAddress.isNotEmpty)
                                Text(
                                  'Adresse: ${_foundProject!.fullAddress}',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                      ],

                      // Multiple Packages Selection (if >1 package found)
                      if (_availablePackages.length > 1) ...[
                        Text(
                          widget.isManagerMode
                              ? 'Gefundene Prüfergebnis-Pakete (*ergebnis*.db):'
                              : 'Mehrere Wartungspakete in diesem Projekt vorhanden:',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _availablePackages.length,
                          itemBuilder: (context, idx) {
                            final file = _availablePackages[idx];
                            return Card(
                              elevation: 0,
                              color: Colors.white,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: Icon(Icons.storage, color: Colors.green.shade700),
                                title: Text(file.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Größe: ${file.formattedSize} • Ordner: Wartungslisten'),
                                trailing: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _isImporting
                                      ? null
                                      : () => _executeImport(_foundProject!, file),
                                  icon: const Icon(Icons.download, size: 16),
                                  label: const Text('Importieren'),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSearching || _isImporting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Schließen'),
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
