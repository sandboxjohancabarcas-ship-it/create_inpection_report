import 'package:flutter/material.dart';
import 'package:wartungstool/models/error_catalog.dart';
import '../services/database_service.dart';
import '../models/models.dart';
import 'error_consolidation_page.dart';
import 'door_options_manager_page.dart';
import '../widgets/batch_migration_dialog.dart';
import '../widgets/export_center_dialog.dart';

class ManagerDashboard extends StatefulWidget {
  const ManagerDashboard({super.key});

  @override
  _ManagerDashboardState createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  List<ErrorCatalog> errors = [];
  List<ErrorCatalog> filteredErrors = [];
  List<String> categories = ['Alle'];
  String selectedCategory = 'Alle';
  int pendingCount = 0;
  bool isLoading = true;
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadErrors();
  }






  Future<void> _loadErrors() async {
    setState(() => isLoading = true);
    try {
      // Only show Approved items in the main management list
      final approved = await DatabaseService.getAllErrorCatalog(status: 'Approved');
      // Check for Pending items to show in the workflow badge
      final pending = await DatabaseService.getAllErrorCatalog(status: 'Pending');
      final dbCategories = await DatabaseService.getErrorCatalogCategories();
      
      setState(() {
        errors = approved;
        filteredErrors = approved;
        categories = ['Alle', ...dbCategories];
        pendingCount = pending.length;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      print('Error loading errors: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Laden: $e')),
      );
    }
  }

  void _filterErrors() {
    setState(() {
      filteredErrors = errors.where((error) {
        final matchesCategory = selectedCategory == 'Alle' || error.category == selectedCategory;
        final matchesSearch = searchController.text.isEmpty ||
            error.description.toLowerCase().contains(searchController.text.toLowerCase()) ||
            error.code.toLowerCase().contains(searchController.text.toLowerCase());
        return matchesCategory && matchesSearch;
      }).toList();
    });
  }

  void _showEditErrorDialog({ErrorCatalog? error}) {
    final codeController = TextEditingController(text: error?.code ?? '');
    final descriptionController = TextEditingController(text: error?.description ?? '');
    final categoryController = TextEditingController(text: error?.category ?? '');
    final validSeverities = ['low', 'medium', 'high', 'critical'];
    final rawSeverity = (error?.severity ?? 'medium').trim().toLowerCase().replaceAll('"', '');
    final initialSeverity = validSeverities.contains(rawSeverity) 
        ? rawSeverity 
        : DatabaseService.normalizeSeverity(rawSeverity);
    final severityController = TextEditingController(text: initialSeverity);
    final recommendationController = TextEditingController(text: error?.recommendation ?? '');
    final normReferenceController = TextEditingController(text: error?.normReference ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(error == null ? 'Neuer Fehler' : 'Fehler bearbeiten'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeController,
                  decoration: InputDecoration(
                    labelText: 'Fehlercode',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Beschreibung',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                SizedBox(height: 16),
                TextField(
                  controller: categoryController,
                  decoration: InputDecoration(
                    labelText: 'Kategorie',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: validSeverities.contains(severityController.text.toLowerCase())
                      ? severityController.text.toLowerCase()
                      : 'medium',
                  decoration: InputDecoration(
                    labelText: 'Schweregrad',
                    border: OutlineInputBorder(),
                  ),
                  items: validSeverities.map((severity) {
                    return DropdownMenuItem<String>(
                      value: severity,
                      child: Text(_getSeverityDisplay(severity)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      severityController.text = value;
                    }
                  },
                ),
                SizedBox(height: 16),
                TextField(
                  controller: recommendationController,
                  decoration: InputDecoration(
                    labelText: 'Empfehlung',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                SizedBox(height: 16),
                TextField(
                  controller: normReferenceController,
                  decoration: InputDecoration(
                    labelText: 'Normreferenz',
                    border: OutlineInputBorder(),
                  ),
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
          ElevatedButton(
            onPressed: () async {
              if (codeController.text.isNotEmpty && descriptionController.text.isNotEmpty) {
                final newError = ErrorCatalog(
                  errorId: error?.errorId,
                  code: codeController.text,
                  description: descriptionController.text,
                  category: categoryController.text.isNotEmpty ? categoryController.text : 'Allgemein',
                  severity: severityController.text,
                  recommendation: recommendationController.text,
                  normReference: normReferenceController.text,
                );

                await DatabaseService.insertErrorCatalog(newError);
                Navigator.pop(context);
                _loadErrors();
              }
            },
            child: Text(error == null ? 'Erstellen' : 'Speichern'),
          ),
        ],
      ),
    );
  }

  void _deleteError(ErrorCatalog error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Fehler löschen'),
        content: Text('Möchten Sie den Fehler "${error.code} - ${error.description}" wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (error.errorId != null) {
                await DatabaseService.deleteErrorCatalog(error.errorId!);
                Navigator.pop(context);
                _loadErrors();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Löschen'),
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
        title: Text('Manager Dashboard - Fehlerkatalog'),
        actions: [
          IconButton(
            icon: const Icon(Icons.drive_file_move_outlined),
            onPressed: () => ExportCenterDialog.show(context),
            tooltip: 'Daten Export & Bericht (Excel/PDF/DB)',
          ),
          IconButton(
            icon: const Icon(Icons.drive_folder_upload),
            onPressed: () => BatchMigrationDialog.show(context, onMigrationCompleted: _loadErrors),
            tooltip: 'Daten-Migration & Import (Dateien/Ordner)',
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadErrors,
            tooltip: 'Aktualisieren',
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DoorOptionsManagerPage()),
              );
            },
            tooltip: 'Stammdaten-Optionen verwalten',
          ),
          IconButton(
            icon: Icon(Icons.storage),
            onPressed: () async {
              await DatabaseService.checkAndInitializeCatalog();
              _loadErrors();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Fehlerkatalog wurde neu geladen')),
              );
            },
            tooltip: 'Fehlerkatalog neu laden',
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search and filter section
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Search bar
                      TextField(
                        controller: searchController,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: 'Suchen',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => _filterErrors(),
                      ),
                      SizedBox(height: 16),
                      // Category filter
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: categories
                              .map((category) => Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: FilterChip(
                                      label: Text(category),
                                      selected: selectedCategory == category,
                                      onSelected: (selected) {
                                        setState(() {
                                          selectedCategory = category;
                                        });
                                        _filterErrors();
                                      },
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Statistics
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem('Gesamt', filteredErrors.length, Colors.blue),
                          _buildStatItem('Offen', pendingCount, Colors.orange),
                          _buildStatItem('Kritisch', 
                              filteredErrors.where((e) => e.severity == 'critical').length, Colors.purple),
                          _buildStatItem('Hoch', 
                              filteredErrors.where((e) => e.severity == 'high').length, Colors.red),
                          _buildStatItem('Mittel', 
                              filteredErrors.where((e) => e.severity == 'medium').length, Colors.orange),
                        ],
                      ),
                    ),
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Error list
                Expanded(
                  child: filteredErrors.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('Keine Fehler gefunden',
                                   style: TextStyle(fontSize: 18)),
                              Text('Passen Sie Ihre Filter an'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredErrors.length,
                          itemBuilder: (context, index) {
                            final error = filteredErrors[index];
                            return Card(
                              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _getSeverityColor(error.severity),
                                  child: Text(
                                    error.code.split('.').first,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  error.code,
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(error.description),
                                    SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[200],
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            error.category,
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _getSeverityColor(error.severity).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            _getSeverityDisplay(error.severity),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: _getSeverityColor(error.severity),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _showEditErrorDialog(error: error);
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
                                onTap: () => _showEditErrorDialog(error: error),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
            FloatingActionButton.extended(
              heroTag: "approval_workflow",
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ErrorConsolidationPage()),
                );
                // Re-load errors if we returned from the consolidation page
                _loadErrors(); // Refresh to update count and list
              },
              // Use a more distinct color to ensure visibility
              backgroundColor: pendingCount > 0 ? Colors.deepOrange : Colors.blueGrey.shade300,
              icon: const Icon(Icons.rule),
              label: Text('$pendingCount Anfragen prüfen'),
            ),

          SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "batch_migration",
            onPressed: () => BatchMigrationDialog.show(context, onMigrationCompleted: _loadErrors),
            backgroundColor: Colors.teal,
            tooltip: 'Daten-Migration & Import',
            child: const Icon(Icons.drive_folder_upload),
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "add_error",
            onPressed: () => _showEditErrorDialog(),
            tooltip: 'Eintrag hinzufügen',
            child: Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
