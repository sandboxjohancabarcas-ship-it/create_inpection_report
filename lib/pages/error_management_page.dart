import 'package:flutter/material.dart';
import 'package:create_inpection_report/models/error_catalog.dart';
import 'package:create_inpection_report/models/models.dart';
import 'package:create_inpection_report/services/database_service.dart';

class ErrorManagementPage extends StatefulWidget {
  final int doorId;
  final String doorNumber;

  const ErrorManagementPage({
    super.key,
    required this.doorId,
    required this.doorNumber,
  });

  @override
  _ErrorManagementPageState createState() => _ErrorManagementPageState();
}

class _ErrorManagementPageState extends State<ErrorManagementPage> {
  List<ErrorCatalog> availableErrors = [];
  List<InspectionDoorError> doorErrors = [];
  List<ErrorCatalog> searchResults = [];
  ErrorCatalog? selectedError;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    
    try {
      print('Loading error catalog for door ${widget.doorId}...');
      final errors = await DatabaseService.getAllErrorCatalog();
      final inspectionErrors = await DatabaseService.getInspectionErrorsForDoor(widget.doorId);
      
      print('Loaded ${errors.length} catalog errors');
      print('Loaded ${inspectionErrors.length} inspection errors');
      
      setState(() {
        availableErrors = errors;
        doorErrors = inspectionErrors;
        isLoading = false;
      });
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

  
  Future<void> _searchErrors(String query) async {
    print('Searching for: "$query"');
    if (query.trim().isEmpty) {
      setState(() {
        searchResults = [];
      });
      return;
    }

    try {
      final results = await DatabaseService.searchErrorCatalog(query);
      print('Search results: ${results.length} items found');
      if (mounted) {
        setState(() {
          searchResults = List.from(results); // Create a new list to prevent reference issues
          selectedError = null; // Clear any selected error when new search results come in
        });
        // Force an additional update to ensure UI refreshes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {});
          }
        });
      }
      print('Updated state - searchResults.length: ${searchResults.length}');
    } catch (e) {
      print('Search error: $e');
      if (mounted) {
        setState(() {
          searchResults = [];
        });
      }
    }
  }

  Future<void> _addCatalogError(ErrorCatalog error, String notes) async {
    final inspectionError = InspectionDoorError(
      inspectionDoorId: widget.doorId,
      errorId: error.errorId ?? 0,
      notes: notes,
      quantity: 1,
      severity: error.severity,
    );

    try {
      await DatabaseService.insertInspectionError(inspectionError);
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
            width: 500,
            height: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Toggle between catalog and provisional
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<bool>(
                          title: Text('Aus Katalog wählen'),
                          value: false,
                          groupValue: isProvisional,
                          onChanged: (value) {
                            setState(() => isProvisional = value!);
                          },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<bool>(
                          title: Text('Provisorischen Fehler erstellen'),
                          value: true,
                          groupValue: isProvisional,
                          onChanged: (value) {
                            setState(() => isProvisional = value!);
                          },
                        ),
                      ),
                    ],
                  ),
                  Divider(),
                  
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
                          onChanged: (value) {
                            _searchErrors(value);
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
                      initialValue: severityController.text,
                      items: ['low', 'medium', 'high', 'critical'].map((severity) {
                        return DropdownMenuItem<String>(
                          value: severity,
                          child: Text(_getSeverityDisplay(severity)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => severityController.text = value!);
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
                    category: categoryController.text.trim().isNotEmpty ? categoryController.text.trim() : 'Provisorisch',
                    severity: severityController.text,
                    recommendation: recommendationController.text.trim(),
                    normReference: normReferenceController.text.trim(),
                  );
                  
                  // Insert provisional error into catalog
                  try {
                    await DatabaseService.insertErrorCatalog(provisionalError);
                    
                    // Get the inserted error ID
                    final errors = await DatabaseService.getAllErrorCatalog();
                    final insertedError = errors.firstWhere(
                      (e) => e.code == provisionalError.code,
                      orElse: () => provisionalError,
                    );
                    
                    // Add to inspection
                    final inspectionError = InspectionDoorError(
                      inspectionDoorId: widget.doorId,
                      errorId: insertedError.errorId ?? 0,
                      notes: notesController.text,
                      quantity: 1,
                      severity: insertedError.severity,
                    );
                    
                    await DatabaseService.insertInspectionError(inspectionError);
                    
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
    // Find the error catalog entry
    final errorCatalog = availableErrors.firstWhere(
      (e) => e.errorId == error.errorId,
      orElse: () => ErrorCatalog(
        code: 'Unbekannt',
        description: 'Fehler nicht im Katalog gefunden',
        category: 'Unbekannt',
      ),
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
              Text('Code: ${errorCatalog.code}', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Beschreibung: ${errorCatalog.description}'),
              SizedBox(height: 8),
              Text('Kategorie: ${errorCatalog.category}'),
              SizedBox(height: 8),
              Text('Schweregrad: ${_getSeverityDisplay(errorCatalog.severity)}'),
              if (errorCatalog.recommendation.isNotEmpty) ...[
                SizedBox(height: 8),
                Text('Empfehlung: ${errorCatalog.recommendation}'),
              ],
              if (errorCatalog.normReference.isNotEmpty) ...[
                SizedBox(height: 8),
                Text('Normreferenz: ${errorCatalog.normReference}'),
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
                await DatabaseService.updateInspectionErrorStatus(error.id!, 'resolved');
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
            icon: Icon(Icons.refresh),
            onPressed: _loadData,
          ),
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
                              (e) => e.errorId == error.errorId,
                              orElse: () => ErrorCatalog(
                                code: 'Unbekannt',
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
                                            color: _getSeverityColor(errorCatalog.severity).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            _getSeverityDisplay(errorCatalog.severity),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: _getSeverityColor(errorCatalog.severity),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (error.notes.isNotEmpty) ...[
                                      SizedBox(height: 4),
                                      Text('Notizen: ${error.notes}', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                                    ],
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
        onPressed: _showAddErrorDialog,
        tooltip: 'Fehler hinzufügen',
        child: Icon(Icons.add),
      ),
    );
  }

  void _showEditDialog(InspectionDoorError error) {
    // Find the error catalog entry
    final errorCatalog = availableErrors.firstWhere(
      (e) => e.errorId == error.errorId,
      orElse: () => ErrorCatalog(
        code: 'Unbekannt',
        description: 'Fehler nicht im Katalog gefunden',
        category: 'Unbekannt',
      ),
    );

    final notesController = TextEditingController(text: error.notes);
    String status = error.resolutionStatus ?? 'open';

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
              Text('Code: ${errorCatalog.code}', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Beschreibung: ${errorCatalog.description}'),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: 'Status'),
                initialValue: status,
                items: ['open', 'in_progress', 'resolved'].map((status) {
                  return DropdownMenuItem<String>(
                    value: status,
                    child: Text(_getStatusDisplay(status)),
                  );
                }).toList(),
                onChanged: (value) {
                  status = value!;
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
              await DatabaseService.updateInspectionErrorStatus(error.id!, status);
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
              await DatabaseService.deleteInspectionError(error.id!);
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
}
