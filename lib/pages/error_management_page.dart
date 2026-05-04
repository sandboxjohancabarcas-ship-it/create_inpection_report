import 'package:flutter/material.dart';
import 'package:create_inpection_report/models/error_catalog.dart';
import 'package:create_inpection_report/models/inspection_error.dart';
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
  List<InspectionError> doorErrors = [];
  List<ErrorCatalog> filteredErrors = [];
  String selectedCategory = 'Alle';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    
    try {
      final errors = await DatabaseService.getAllErrorCatalog();
      final inspectionErrors = await DatabaseService.getInspectionErrorsForDoor(widget.doorId);
      
      print('Loaded ${errors.length} errors for door ${widget.doorId}');
      if (errors.isNotEmpty) {
        print('First error: ${errors.first.code}, errorId: ${errors.first.errorId}');
      }
      
      setState(() {
        availableErrors = errors;
        doorErrors = inspectionErrors;
        filteredErrors = errors;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading data: $e');
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Laden: $e')),
      );
    }
  }

  void _filterErrors(String category) {
    setState(() {
      selectedCategory = category;
      if (category == 'Alle') {
        filteredErrors = availableErrors;
      } else {
        filteredErrors = availableErrors
            .where((error) => error.category == category)
            .toList();
      }
    });
  }

  void _showAddErrorDialog() {
    final notesController = TextEditingController();
    ErrorCatalog? selectedError;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Fehler hinzufügen'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ErrorCatalog>(
                  decoration: InputDecoration(labelText: 'Fehler auswählen'),
                  value: selectedError,
                  items: filteredErrors.map((error) {
                    return DropdownMenuItem<ErrorCatalog>(
                      value: error,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(error.code, style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(error.description, style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedError = value);
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
                if (selectedError != null) {
                  print('Adding error: ${selectedError!.code}, errorId: ${selectedError!.errorId}');
                  
                  final inspectionError = InspectionError(
                    doorId: widget.doorId,
                    errorId: selectedError!.errorId ?? 0, // Use 0 as fallback if null
                    notes: notesController.text,
                    reportedDate: DateTime.now(),
                  );
                  
                  try {
                    await DatabaseService.insertInspectionError(inspectionError);
                    Navigator.pop(context);
                    _loadData(); // Refresh the list
                  } catch (e) {
                    print('Error adding inspection error: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Fehler beim Hinzufügen: $e')),
                    );
                  }
                }
              },
              child: Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorDetails(InspectionError error) async {
    // Find the error catalog entry
    final errorCatalog = availableErrors.firstWhere(
      (e) => e.errorId == error.errorId,
      orElse: () => ErrorCatalog(
        code: 'Unbekannt',
        description: 'Fehler nicht im Katalog gefunden',
        category: 'Unbekannt',
      ),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Fehler Details'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Code: ${errorCatalog.code}', 
                   style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Kategorie: ${errorCatalog.category}'),
              SizedBox(height: 8),
              Text('Beschreibung: ${errorCatalog.description}'),
              SizedBox(height: 8),
              if (errorCatalog.recommendation.isNotEmpty) ...[
                Text('Empfehlung: ${errorCatalog.recommendation}'),
                SizedBox(height: 8),
              ],
              if (errorCatalog.normReference.isNotEmpty) ...[
                Text('Norm: ${errorCatalog.normReference}'),
                SizedBox(height: 8),
              ],
              Text('Status: ${ErrorStatus.getStatusDisplay(error.status)}'),
              SizedBox(height: 8),
              Text('Gemeldet am: ${error.reportedDate.day.toString().padLeft(2, '0')}.${error.reportedDate.month.toString().padLeft(2, '0')}.${error.reportedDate.year}'),
              if (error.notes.isNotEmpty) ...[
                SizedBox(height: 8),
                Text('Notizen: ${error.notes}'),
              ],
            ],
          ),
        ),
        actions: [
          if (error.status != 'resolved') ...[
            TextButton(
              onPressed: () async {
                await DatabaseService.updateInspectionErrorStatus(error.id!, 'resolved');
                Navigator.pop(context);
                _loadData();
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
                // Category filter
                Container(
                  padding: EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['Alle', ...DoorErrorCatalog.getCategories()]
                          .map((category) => Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(category),
                                  selected: selectedCategory == category,
                                  onSelected: (selected) {
                                    _filterErrors(category);
                                  },
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ),
                
                // Error list
                Expanded(
                  child: doorErrors.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, size: 64, color: Colors.green),
                              SizedBox(height: 16),
                              Text('Keine Fehler gefunden',
                                   style: TextStyle(fontSize: 18)),
                              Text('Diese Tür hat keine offenen Fehler'),
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
                                description: 'Fehler nicht gefunden',
                                category: '',
                              ),
                            );
                            
                            return Card(
                              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _getStatusColor(error.status),
                                  child: Icon(
                                    error.status == 'resolved' ? Icons.check : Icons.error,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(errorCatalog.code),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(errorCatalog.description),
                                    SizedBox(height: 4),
                                    Text('Status: ${ErrorStatus.getStatusDisplay(error.status)}',
                                         style: TextStyle(
                                           color: _getStatusColor(error.status),
                                           fontWeight: FontWeight.bold,
                                         )),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (value == 'details') {
                                      _showErrorDetails(error);
                                    } else if (value == 'resolve') {
                                      await DatabaseService.updateInspectionErrorStatus(error.id!, 'resolved');
                                      _loadData();
                                    } else if (value == 'delete') {
                                      await DatabaseService.deleteInspectionError(error.id!);
                                      _loadData();
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'details',
                                      child: Row(
                                        children: [
                                          Icon(Icons.info),
                                          SizedBox(width: 8),
                                          Text('Details'),
                                        ],
                                      ),
                                    ),
                                    if (error.status != 'resolved')
                                      PopupMenuItem(
                                        value: 'resolve',
                                        child: Row(
                                          children: [
                                            Icon(Icons.check_circle),
                                            SizedBox(width: 8),
                                            Text('Als gelöst markieren'),
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
        child: Icon(Icons.add),
        tooltip: 'Fehler hinzufügen',
      ),
    );
  }
}
