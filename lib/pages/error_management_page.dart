import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/services/database_service.dart';
import '../widgets/master_portal_home_button.dart';

class ErrorManagementPage extends StatefulWidget {
  final int doorId;
  final String doorNumber;
  final int inspectionId;
  /// When true, reads/writes use DatabaseService (Master DB) instead of LocalDatabaseService (working.db).
  final bool isManagerMode;

  const ErrorManagementPage({
    super.key,
    required this.doorId,
    required this.doorNumber,
    required this.inspectionId,
    this.isManagerMode = false,
  });

  @override
  _ErrorManagementPageState createState() => _ErrorManagementPageState();
}

class _ErrorManagementPageState extends State<ErrorManagementPage> {
  List<ErrorCatalog> availableErrors = [];
  List<InspectionDoorError> doorErrors = [];
  List<ErrorCatalog> searchResults = [];
  ErrorCatalog? selectedError;
  int? _inspectionDoorId;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Loads data from the correct database based on [widget.isManagerMode].
  /// If [syncWithMain] is true, it attempts to refresh the local catalog from the main DB first.
  Future<void> _loadData({bool syncWithMain = false}) async {
    setState(() => isLoading = true);
    
    try {
      if (widget.isManagerMode) {
        // Manager mode: read from Master DB (DatabaseService)
        final junctions = await DatabaseService.getInspectionDoorsByInspectionId(widget.inspectionId);
        final junction = junctions.where((j) => j['doorId'] == widget.doorId).firstOrNull;
        _inspectionDoorId = junction?['id'] as int?;

        final catalogSuggestions = await DatabaseService.getAllErrorCatalog(status: 'Approved');
        final inspectionErrors = _inspectionDoorId != null
            ? await DatabaseService.getErrorsForInspectionDoor(_inspectionDoorId!)
            : <InspectionDoorError>[];

        print('[Manager] Loaded ${catalogSuggestions.length} catalog errors');
        print('[Manager] Loaded ${inspectionErrors.length} inspection errors for door ${widget.doorId}');

        setState(() {
          availableErrors = catalogSuggestions;
          doorErrors = inspectionErrors;
          isLoading = false;
        });
      } else {
        // Inspector mode: read from local working.db (LocalDatabaseService)
        final junction = await LocalDatabaseService.getInspectionDoor(widget.inspectionId, widget.doorId);
        _inspectionDoorId = junction?['id'];

        if (syncWithMain) {
          try {
            await LocalDatabaseService.refreshLocalCatalogFromMain();
          } catch (e) {
            print('Haupt-Datenbank nicht erreichbar. Fahre mit lokalem Katalog fort: $e');
          }
        }

        final catalogSuggestions = await LocalDatabaseService.searchErrorCatalog('');
        final inspectionErrors = _inspectionDoorId != null
            ? await LocalDatabaseService.getErrorsForInspectionDoor(_inspectionDoorId!)
            : <InspectionDoorError>[];

        print('Loaded ${catalogSuggestions.length} catalog errors');
        print('Loaded ${inspectionErrors.length} inspection errors');

        setState(() {
          availableErrors = catalogSuggestions;
          doorErrors = inspectionErrors;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading data: $e');
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden: $e')),
        );
      }
    }
  }

  

  Future<void> _addCatalogError(ErrorCatalog error, String notes) async {
    if (_inspectionDoorId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler: Keine aktive Inspektions-Sitzung für diese Tür gefunden.')),
        );
      }
      return;
    }

    final inspectionError = InspectionDoorError(
      inspectionDoorId: _inspectionDoorId!,
      errorId: error.errorId ?? 0,
      errorCode: error.code,
      notes: notes,
      quantity: 1,
      severity: error.severity,
    );

    try {
      if (widget.isManagerMode) {
        await DatabaseService.insertInspectionDoorError(inspectionError);
      } else {
        await LocalDatabaseService.insertInspectionDoorError(inspectionError);
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Hinzufügen: $e')),
        );
      }
    }
  }

  void _showAddErrorDialog() {
    final notesController = TextEditingController();
    final codeController = TextEditingController();
    final descriptionController = TextEditingController();
    final categoryController = TextEditingController();
    final severityController = TextEditingController(text: 'medium');
    final recommendationController = TextEditingController();
    final normReferenceController = TextEditingController();
    final searchController = TextEditingController();
    ErrorCatalog? selectedError;
    bool isProvisional = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Fehler hinzufügen'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width > 600 ? 500 : MediaQuery.of(context).size.width * 0.85,
            height: MediaQuery.of(context).size.height * 0.7,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Toggle between catalog and provisional mode
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RadioListTile<bool>(
                        title: const Text('Aus Katalog wählen'),
                        value: false,
                        groupValue: isProvisional,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          if (value != null) setState(() => isProvisional = value);
                        },
                      ),
                      RadioListTile<bool>(
                        title: const Text('Provisorischen Fehler erstellen'),
                        value: true,
                        groupValue: isProvisional,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          if (value != null) setState(() => isProvisional = value);
                        },
                      ),
                    ],
                  ),
                  const Divider(),
                  
                  if (!isProvisional) ...[
                    // Catalog error selection with search
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fehler aus Katalog auswählen',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Suchen Sie nach Fehlercode oder Beschreibung:',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        SizedBox(height: 8),
                        TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            labelText: 'Fehlercode oder Beschreibung',
                            border: OutlineInputBorder(),
                            hintText: 'z.B. 1.1.1 oder Türbeschlag',
                            suffixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) async {
                            // Perform catalog search locally within the dialog's state
                            if (value.trim().isEmpty) {
                              setState(() {
                                searchResults = [];
                                selectedError = null;
                              });
                              return;
                            }
                            try {
                              final results = widget.isManagerMode
                                  ? await DatabaseService.searchErrorCatalog(value)
                                  : await LocalDatabaseService.searchErrorCatalog(value);
                              setState(() {
                                searchResults = List.from(results);
                                selectedError = null;
                              });
                            } catch (e) {
                              // Log error and clear results
                              print('Search error: $e');
                              setState(() {
                                searchResults = [];
                                selectedError = null;
                              });
                            }
                          },
                        ),
                        SizedBox(height: 12),
                        
                        // Search results or selection display
                        if (selectedError != null) ...[
                          // Show selected error
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              border: Border.all(color: Colors.green.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Ausgewählter Fehler:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Text(
                                  '${selectedError!.code} - ${selectedError!.category}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  selectedError!.description,
                                  style: TextStyle(fontSize: 12),
                                ),
                                SizedBox(height: 8),
                                Row(
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _addCatalogError(selectedError!, notesController.text);
                                      },
                                      icon: Icon(Icons.add),
                                      label: Text('Fehler hinzufügen'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          selectedError = null;
                                          searchController.clear();
                                          searchResults = [];
                                        });
                                      },
                                      icon: Icon(Icons.change_circle),
                                      label: Text('Anderen Fehler wählen'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Always show search results area when no error is selected
                          Container(
                            height: 250,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.blue.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: searchResults.isEmpty && searchController.text.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.search, size: 48, color: Colors.grey),
                                        SizedBox(height: 8),
                                        Text(
                                          'Geben Sie Suchbegriff ein...',
                                          style: TextStyle(color: Colors.grey, fontSize: 14),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'z.B. 1.1.1 oder Türbeschlag',
                                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  )
                                : searchResults.isEmpty && searchController.text.isNotEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.search_off, size: 48, color: Colors.grey),
                                            SizedBox(height: 8),
                                            Text(
                                              'Keine Ergebnisse gefunden',
                                              style: TextStyle(color: Colors.grey, fontSize: 14),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'Versuchen Sie einen anderen Suchbegriff',
                                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Column(
                                        children: [
                                          Container(
                                            width: double.infinity,
                                            padding: EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius: BorderRadius.only(
                                                topLeft: Radius.circular(8),
                                                topRight: Radius.circular(8),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.search, color: Colors.blue, size: 16),
                                                SizedBox(width: 4),
                                                Text(
                                                  '${searchResults.length} Ergebnisse gefunden',
                                                  style: TextStyle(
                                                    color: Colors.blue.shade800,
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: SingleChildScrollView(
                                              child: Column(
                                                children: searchResults.map((error) {
                                                  return Card(
                                                    margin: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                    elevation: 1,
                                                    child: ListTile(
                                                      dense: true,
                                                      leading: CircleAvatar(
                                                        backgroundColor: Colors.blue.shade100,
                                                        radius: 16,
                                                        child: Text(
                                                          error.code.split('.')[0],
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.blue.shade800,
                                                          ),
                                                        ),
                                                      ),
                                                      title: Text(
                                                        error.code,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 13,
                                                          color: Colors.black87,
                                                        ),
                                                      ),
                                                      subtitle: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            error.category,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: Colors.blue.shade600,
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                          ),
                                                          Text(
                                                            error.description,
                                                            style: TextStyle(fontSize: 11, color: Colors.black54),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ],
                                                      ),
                                                      trailing: ElevatedButton(
                                                        onPressed: () {
                                                          setState(() {
                                                            selectedError = error;
                                                            searchController.clear();
                                                            searchResults = [];
                                                          });
                                                        },
                                                        style: ElevatedButton.styleFrom(
                                                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                          textStyle: TextStyle(fontSize: 11),
                                                        ),
                                                        child: Text('Auswählen'),
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                          ),
                        ],
                      ],
                    ),
                  ] else ...[
                    // Provisional error form
                    TextField(
                      controller: codeController,
                      decoration: InputDecoration(
                        labelText: 'Fehlercode *',
                        border: OutlineInputBorder(),
                        hintText: 'z.B. 1.1.1, 2.3.4, etc.',
                      ),
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Beschreibung *',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: categoryController,
                      decoration: InputDecoration(
                        labelText: 'Kategorie *',
                        border: OutlineInputBorder(),
                        hintText: 'z.B. Türbeschlag, Schloss, etc.',
                      ),
                    ),
                    SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(labelText: 'Schweregrad'),
                      value: const ['low', 'medium', 'high', 'critical'].contains(severityController.text.toLowerCase())
                          ? severityController.text.toLowerCase()
                          : 'medium',
                      items: const ['low', 'medium', 'high', 'critical'].map((severity) {
                        return DropdownMenuItem<String>(
                          value: severity,
                          child: Text(_getSeverityDisplay(severity)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => severityController.text = value);
                        }
                      },
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: recommendationController,
                      decoration: InputDecoration(
                        labelText: 'Empfehlung',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: normReferenceController,
                      decoration: InputDecoration(
                        labelText: 'Normreferenz',
                        border: OutlineInputBorder(),
                        hintText: 'z.B. DIN 18095, DIN 18251',
                      ),
                    ),
                  ],
                  
                  SizedBox(height: 16),
                  TextField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: 'Notizen',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Abbrechen'),
            ),
            if (isProvisional)
              ElevatedButton(
                onPressed: () async {
                  // Add provisional error
                  if (codeController.text.trim().isEmpty || descriptionController.text.trim().isEmpty) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Fehlercode und Beschreibung sind erforderlich')),
                      );
                    }
                    return;
                  }
                  
                  // Create provisional error
                  final provisionalError = ErrorCatalog(
                    code: codeController.text.trim(),
                    description: descriptionController.text.trim(),
                    category: categoryController.text.trim().isNotEmpty ? categoryController.text.trim() : 'provisional',
                    severity: severityController.text,
                    recommendation: recommendationController.text.trim(),
                    normReference: normReferenceController.text.trim(),
                    status: 'Pending', // Explicitly set to Pending for manager approval
                  );
                  print('UI: Creating provisional error proposal: ${provisionalError.code} - Status: ${provisionalError.status}');
                  
                  try {
                    ErrorCatalog insertedError;
                    if (widget.isManagerMode) {
                      await DatabaseService.insertErrorCatalog(provisionalError);
                      final errors = await DatabaseService.searchErrorCatalog(provisionalError.code);
                      insertedError = errors.firstWhere(
                        (e) => e.code == provisionalError.code,
                        orElse: () => provisionalError,
                      );
                    } else {
                      // Note: In local-first, we store provisional errors locally
                      // until they are synced and approved by the main DB.
                      await LocalDatabaseService.insertErrorCatalogItems([provisionalError]);
                      final errors = await LocalDatabaseService.searchErrorCatalog(provisionalError.code);
                      insertedError = errors.firstWhere(
                        (e) => e.code == provisionalError.code,
                        orElse: () => provisionalError,
                      );
                    }
                    
                    // Add to inspection using the resolved junction ID
                    if (_inspectionDoorId == null) {
                      throw Exception('Keine Inspektions-Sitzung gefunden');
                    }

                    final inspectionError = InspectionDoorError(
                      inspectionDoorId: _inspectionDoorId!,
                      errorId: insertedError.errorId ?? 0,
                      errorCode: insertedError.code,
                      notes: notesController.text,
                      quantity: 1,
                      severity: insertedError.severity,
                    );
                    
                    if (widget.isManagerMode) {
                      await DatabaseService.insertInspectionDoorError(inspectionError);
                    } else {
                      await LocalDatabaseService.insertInspectionDoorError(inspectionError);
                    }
                    
                    if (mounted) {
                      Navigator.pop(context);
                      _loadData();
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Provisorischer Fehler wurde hinzugefügt und zur Genehmigung eingereicht'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Fehler beim Hinzufügen: $e')),
                      );
                    }
                  }
                },
                child: Text('Provisorisch hinzufügen'),
              ),
          ],
        ),
      ),
    );
  }

  void _showErrorDetails(InspectionDoorError error) async {
    // 1. Try finding from already loaded catalog items in memory
    ErrorCatalog? currentCatalog = availableErrors.where(
      (e) => (error.errorId != null && error.errorId! > 0 && e.errorId == error.errorId) ||
             (error.errorCode.isNotEmpty && e.code == error.errorCode),
    ).firstOrNull;

    // 2. If not found in memory, query the appropriate database
    if (currentCatalog == null) {
      if (widget.isManagerMode) {
        if (error.errorId != null && error.errorId! > 0) {
          currentCatalog = await DatabaseService.getErrorCatalogItemById(error.errorId!);
        }
        if (currentCatalog == null && error.errorCode.isNotEmpty) {
          final results = await DatabaseService.searchErrorCatalog(error.errorCode);
          currentCatalog = results.where((e) => e.code == error.errorCode).firstOrNull ?? results.firstOrNull;
        }
      } else {
        if (error.errorId != null && error.errorId! > 0) {
          currentCatalog = await LocalDatabaseService.getErrorCatalogItemById(error.errorId!);
        }
        if (currentCatalog == null && error.errorCode.isNotEmpty) {
          final results = await LocalDatabaseService.searchErrorCatalog(error.errorCode);
          currentCatalog = results.where((e) => e.code == error.errorCode).firstOrNull ?? results.firstOrNull;
        }
      }
    }

    final ErrorCatalog catalogDetails = currentCatalog ?? ErrorCatalog(
      code: error.errorCode.isNotEmpty ? error.errorCode : 'Unbekannt',
      description: 'Fehler nicht im Katalog gefunden',
      category: 'Unbekannt',
    );

    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Fehler-Details'),
        content: SizedBox(
          width: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Code: ${catalogDetails.code}', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Beschreibung: ${catalogDetails.description}'),
              SizedBox(height: 8),
              Text('Kategorie: ${catalogDetails.category}'),
              SizedBox(height: 8),
              Text('Schweregrad: ${_getSeverityDisplay(catalogDetails.severity)}'),
              if (catalogDetails.recommendation.isNotEmpty) ...[
                SizedBox(height: 8),
                Text('Empfehlung: ${catalogDetails.recommendation}'),
              ],
              if (catalogDetails.normReference.isNotEmpty) ...[
                SizedBox(height: 8),
                Text('Normreferenz: ${catalogDetails.normReference}'),
              ],
              SizedBox(height: 16),
              Text('Notizen: ${error.notes}'),
            ],
          ),
        ),
        actions: [
          if (error.resolutionStatus != 'resolved') ...[
            TextButton(
              onPressed: () async {
                final updatedError = error.copyWith(resolutionStatus: 'resolved');
                if (widget.isManagerMode) {
                  await DatabaseService.insertInspectionDoorError(updatedError);
                } else {
                  await LocalDatabaseService.insertInspectionDoorError(updatedError);
                }
                if (mounted) {
                  Navigator.pop(context);
                  _loadData();
                }
              },
              child: Text('Als gelöst markieren'),
            ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Schließen'),
          ),
        ],
      ),
    );
  }

  String _getSeverityDisplay(String severity) {
    switch (severity) {
      case 'low':
        return 'Niedrig';
      case 'medium':
        return 'Mittel';
      case 'high':
        return 'Hoch';
      case 'critical':
        return 'Kritisch';
      default:
        return severity;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.red;
      case 'in_progress':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getStatusDisplay(String status) {
    switch (status) {
      case 'open':
        return 'Offen';
      case 'in_progress':
        return 'In Bearbeitung';
      case 'resolved':
        return 'Gelöst';
      default:
        return status;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'open':
        return Icons.error;
      case 'in_progress':
        return Icons.pending;
      case 'resolved':
        return Icons.check_circle;
      default:
        return Icons.help;
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      case 'critical':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fehlermanagement - Tür ${widget.doorNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(syncWithMain: true),
          ),
          const MasterPortalHomeButton(),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SizedBox(height: 16),
                
                // Error list
                Expanded(
                  child: doorErrors.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'Keine Fehler für diese Tür',
                                style: TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                              SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _showAddErrorDialog,
                                icon: Icon(Icons.add),
                                label: Text('Fehler hinzufügen'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: doorErrors.length,
                          itemBuilder: (context, index) {
                            final error = doorErrors[index];
                            final errorCatalog = availableErrors.firstWhere(
                              (e) => e.errorId == error.errorId || (error.errorCode.isNotEmpty && e.code == error.errorCode),
                              orElse: () => ErrorCatalog(
                                code: error.errorCode.isNotEmpty ? error.errorCode : 'Unbekannt',
                                description: 'Fehler nicht im Katalog gefunden',
                                category: 'Unbekannt',
                              ),
                            );

                            return Card(
                              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _getStatusColor(error.resolutionStatus ?? 'open'),
                                  child: Icon(
                                    _getStatusIcon(error.resolutionStatus ?? 'open'),
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                              errorCatalog.code,
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(errorCatalog.description),
                                    SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                        errorCatalog.category,
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                        color: _getSeverityColor(error.severity ?? 'medium').withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                        _getSeverityDisplay(error.severity ?? 'medium'),
                                            style: TextStyle(
                                              fontSize: 12,
                                          color: _getSeverityColor(error.severity ?? 'medium'),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                      if (error.notes.isNotEmpty) ...[
                                        SizedBox(height: 4),
                                    Text('Notizen: ${error.notes}', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                                      ],
                                      _buildPhotoGallery(error),
                                    ],
                                  ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                  _showEditDialog(error);
                                    } else if (value == 'delete') {
                                  _deleteError(error);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit),
                                          SizedBox(width: 8),
                                          Text('Bearbeiten'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Löschen'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () => _showErrorDetails(error),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_error_management',
        onPressed: _showAddErrorDialog,
        tooltip: 'Fehler hinzufügen',
        child: Icon(Icons.add),
      ),
    );
  }

  void _showEditDialog(InspectionDoorError error) {
    // Find the error catalog entry
    final errorCatalog = availableErrors.firstWhere(
      (e) => e.errorId == error.errorId || (error.errorCode.isNotEmpty && e.code == error.errorCode),
      orElse: () => ErrorCatalog(
        code: error.errorCode.isNotEmpty ? error.errorCode : 'Unbekannt',
        description: 'Fehler nicht im Katalog gefunden',
        category: 'Unbekannt',
      ),
    );

    final notesController = TextEditingController(text: error.notes);
    final validStatuses = ['open', 'in_progress', 'resolved'];
    String status = validStatuses.contains((error.resolutionStatus ?? 'open').toLowerCase())
        ? (error.resolutionStatus ?? 'open').toLowerCase()
        : 'open';

    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Fehler bearbeiten'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Fehlercode: ${errorCatalog.code}', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Beschreibung:', style: TextStyle(fontWeight: FontWeight.w500)),
              Text(errorCatalog.description),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: 'Status'),
                value: status,
                items: validStatuses.map((s) {
                  return DropdownMenuItem<String>(
                    value: s,
                    child: Text(_getStatusDisplay(s)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    status = value;
                  }
                },
              ),
              SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: 'Notizen',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              final updatedError = error.copyWith(resolutionStatus: status, notes: notesController.text);
              if (widget.isManagerMode) {
                await DatabaseService.insertInspectionDoorError(updatedError);
              } else {
                await LocalDatabaseService.insertInspectionDoorError(updatedError);
              }
              if (mounted) {
                Navigator.pop(context);
                _loadData();
              }
            },
            child: Text('Speichern'),
          ),
        ],
      ),
    );
  }

  void _deleteError(InspectionDoorError error) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Fehler löschen'),
        content: Text('Möchten Sie diesen Fehler wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (widget.isManagerMode) {
                await DatabaseService.deleteInspectionDoorError(error.id!);
              } else {
                await LocalDatabaseService.deleteInspectionDoorError(error.id!);
              }
              if (mounted) {
                Navigator.pop(context);
                _loadData();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Löschen'),
          ),
        ],
      ),
    );
  }

  Future<void> _addPhotoToError(InspectionDoorError error, ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (image == null) return;

      final File file = File(image.path);
      final int sizeInBytes = await file.length();
      const int maxSizeInBytes = 60 * 1024 * 1024; // 60 MB

      if (sizeInBytes > maxSizeInBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Das Bild ist zu groß. Maximale Größe ist 60 MB (Aktuell: \${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB).'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final bytes = await file.readAsBytes();
      final base64Str = base64Encode(bytes);

      // Append base64 string to attachments (comma-separated)
      List<String> currentPhotos = error.attachments.split(',').where((s) => s.isNotEmpty).toList();
      currentPhotos.add(base64Str);
      final newAttachments = currentPhotos.join(',');

      final updatedError = error.copyWith(attachments: newAttachments);
      if (widget.isManagerMode) {
        await DatabaseService.insertInspectionDoorError(updatedError);
      } else {
        await LocalDatabaseService.insertInspectionDoorError(updatedError);
      }
      
      _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto erfolgreich hinzugefügt.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error adding photo: \$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Hinzufügen des Fotos: \$e')),
        );
      }
    }
  }

  Future<void> _deletePhotoFromError(InspectionDoorError error, int photoIndex) async {
    try {
      List<String> currentPhotos = error.attachments.split(',').where((s) => s.isNotEmpty).toList();
      if (photoIndex >= 0 && photoIndex < currentPhotos.length) {
        currentPhotos.removeAt(photoIndex);
      }
      final newAttachments = currentPhotos.join(',');

      final updatedError = error.copyWith(attachments: newAttachments);
      if (widget.isManagerMode) {
        await DatabaseService.insertInspectionDoorError(updatedError);
      } else {
        await LocalDatabaseService.insertInspectionDoorError(updatedError);
      }
      
      _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto gelöscht.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('Error deleting photo: \$e');
    }
  }

  void _viewPhotoFullScreen(String base64Str) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.black,
                child: InteractiveViewer(
                  panEnabled: true,
                  boundaryMargin: EdgeInsets.all(20),
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.memory(
                    base64Decode(base64Str),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPhotoSourceSheet(InspectionDoorError error) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Kamera'),
              onTap: () {
                Navigator.pop(context);
                _addPhotoToError(error, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galerie'),
              onTap: () {
                Navigator.pop(context);
                _addPhotoToError(error, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoGallery(InspectionDoorError error) {
    final photos = error.attachments.split(',').where((s) => s.isNotEmpty).toList();
    
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fotonachweis:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 70,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length + 1,
              itemBuilder: (context, index) {
                if (index == photos.length) {
                  // Add photo button
                  return GestureDetector(
                    onTap: () => _showAddPhotoSourceSheet(error),
                    child: Container(
                      width: 60,
                      height: 60,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade50,
                      ),
                      child: Icon(Icons.add_a_photo, color: Colors.grey.shade600, size: 24),
                    ),
                  );
                }

                final photoBase64 = photos[index];
                return Stack(
                  children: [
                    GestureDetector(
                      onTap: () => _viewPhotoFullScreen(photoBase64),
                      child: Container(
                        width: 60,
                        height: 60,
                        margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            )
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            base64Decode(photoBase64),
                            fit: BoxFit.cover,
                            cacheWidth: 120, // performance optimization
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _deletePhotoFromError(error, index),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
