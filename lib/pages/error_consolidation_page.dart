import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database_service.dart';

class ErrorConsolidationPage extends StatefulWidget {
  const ErrorConsolidationPage({super.key});

  @override
  State<ErrorConsolidationPage> createState() => _ErrorConsolidationPageState();
}

class _ErrorConsolidationPageState extends State<ErrorConsolidationPage> {
  late Future<List<ErrorCatalog>> _pendingErrorsFuture;

  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  void _refreshList() {
    setState(() {
      // Logic: Fetch only items with 'Pending' status from the Main DB
      _pendingErrorsFuture = DatabaseService.getAllErrorCatalog(status: 'Pending');
    });
  }

  Future<void> _processApproval(ErrorCatalog error, bool approved) async {
    // If approved, we might want to let the manager edit the code/description first
    final ErrorCatalog finalizedError = approved 
        ? error.copyWith(status: 'Approved') 
        : error.copyWith(status: 'Rejected');

    try {
      // This method should use an UPSERT or UPDATE in DatabaseService
      await DatabaseService.insertErrorCatalog(finalizedError);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approved ? 'Fehler genehmigt!' : 'Fehler archiviert.')),
        );
        _refreshList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler bei der Verarbeitung: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fehler-Katalog Konsolidierung'),
        actions: [
          IconButton(onPressed: _refreshList, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<ErrorCatalog>>(
        future: _pendingErrorsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final pending = snapshot.data ?? [];
          if (pending.isEmpty) {
            return const Center(
              child: Text('Keine neuen Fehler-Anfragen vorhanden.'),
            );
          }

          return ListView.builder(
            itemCount: pending.length,
            itemBuilder: (context, index) {
              final item = pending[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ExpansionTile(
                  leading: const Icon(Icons.pending_actions, color: Colors.orange),
                  title: Text(item.description),
                  subtitle: Text('Kategorie: ${item.category} | Von: ${item.requestedBy ?? "Unbekannt"}'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Vorgeschlagener Code: ${item.code}'),
                          Text('Schweregrad: ${item.severity}'),
                          const SizedBox(height: 10),
                          Text('Empfehlung: ${item.recommendation}'),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => _processApproval(item, false),
                                icon: const Icon(Icons.archive, color: Colors.grey),
                                label: const Text('Ablehnen/Archivieren', style: TextStyle(color: Colors.grey)),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () => _showEditDialog(item),
                                icon: const Icon(Icons.edit),
                                label: const Text('Prüfen & Bearbeiten'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                onPressed: () => _processApproval(item, true),
                                icon: const Icon(Icons.check_circle),
                                label: const Text('Direkt Genehmigen'),
                              ),
                            ],
                          )
                        ],
                      ),
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showEditDialog(ErrorCatalog error) {
    final codeController = TextEditingController(text: error.code);
    final descController = TextEditingController(text: error.description);
    final catController = TextEditingController(text: error.category);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fehler-Anfrage bearbeiten'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Bereinigen Sie den Eintrag, bevor er in den globalen Katalog übernommen wird.'),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'Offizieller Code', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Beschreibung', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: DoorErrorCatalog.getCategories().contains(catController.text) 
                    ? catController.text 
                    : 'Sonstiges',
                items: DoorErrorCatalog.getCategories().map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => catController.text = v ?? 'Sonstiges',
                decoration: const InputDecoration(labelText: 'Kategorie', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              final updated = error.copyWith(
                code: codeController.text,
                description: descController.text,
                category: catController.text,
              );
              _processApproval(updated, true);
              Navigator.pop(context);
            }, 
            child: const Text('Speichern & Genehmigen')
          ),
        ],
      ),
    );
  }
}