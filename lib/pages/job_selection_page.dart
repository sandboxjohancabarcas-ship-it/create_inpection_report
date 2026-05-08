import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import 'door_list_page.dart';

class JobSelectionPage extends StatefulWidget {
  const JobSelectionPage({super.key});

  @override
  State<JobSelectionPage> createState() => _JobSelectionPageState();
}

class _JobSelectionPageState extends State<JobSelectionPage> {
  bool _isDownloading = false;

  Future<void> _handleJobDownload(Map<String, dynamic> job) async {
    setState(() => _isDownloading = true);

    try {
      // Execute the handoff from Main DB to Working DB
      await LocalDatabaseService.downloadJobData(
        clientName: job['clientName'] ?? '',
        jobNumber: job['auftragsnummer'] ?? '',
        date: job['date'] ?? '',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daten erfolgreich synchronisiert!')),
        );
        // Navigate to the list of doors for the downloaded job
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const DoorListPage()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Download: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auftrag auswählen'),
      ),
      body: Stack(
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: DatabaseService.getAllInspections(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                  child: Text('Keine Aufträge in der Hauptdatenbank gefunden.'),
                );
              }

              final inspections = snapshot.data!;

              return ListView.builder(
                itemCount: inspections.length,
                itemBuilder: (context, index) {
                  final job = inspections[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      leading: const Icon(Icons.business, color: Colors.blue),
                      title: Text(job['clientName'] ?? 'Unbekannter Kunde'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Projekt: ${job['auftragsnummer']}'),
                          Text('Datum: ${job['date']}'),
                        ],
                      ),
                      trailing: const Icon(Icons.cloud_download_outlined),
                      onTap: _isDownloading ? null : () => _handleJobDownload(job),
                    ),
                  );
                },
              );
            },
          ),
          if (_isDownloading)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      'Job-Daten werden vorbereitet...',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}