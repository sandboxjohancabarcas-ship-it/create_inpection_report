import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';

class JobSelectionPage extends StatefulWidget {
  /// This page allows inspectors to view available jobs from the Main DB
  /// and download them to the Local DB for offline use.
  /// It is the starting point of the inspector workflow.
  const JobSelectionPage({super.key});

  @override
  State<JobSelectionPage> createState() => _JobSelectionPageState();
}

class _JobSelectionPageState extends State<JobSelectionPage> {
  // State variable to track if a job is currently being transferred between databases
  bool _isDownloading = false;
  late Future<List<Map<String, dynamic>>> _inspectionsFuture;

  @override
  void initState() {
    super.initState();
    // Initialize the future once to prevent re-fetching on every rebuild
    _inspectionsFuture = DatabaseService.getAllInspections();
  }

  /// Orchestrates the data handoff from Main DB to Working DB.
  /// Called when a user selects a job from the list.
  Future<void> _handleJobDownload(Map<String, dynamic> job) async {
    // Show the modal loading overlay
    setState(() => _isDownloading = true);

    try {
      // Logic: Orchestrates the handoff from Main DB to Working DB.
      // It fetches main DB records and performs a batch insert into the local SQLite file.
      await LocalDatabaseService.downloadJobData( 
        clientName: job['clientName'] ?? '',
        jobNumber: job['auftragsnummer'] ?? '',
        date: job['date'] ?? '',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daten erfolgreich synchronisiert!')),
        );
        // Navigation: Handoff successful. Return to the previous screen (DoorListPage)
        // with a success result so it can refresh the list.
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Download: $e')),
        );
      }
    } finally {
      // Hide the modal loading overlay regardless of success or failure
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
        // Stack allows the 'Downloading' indicator to appear on top of the list
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            // Logic: Asynchronously fetches all available inspections from the Main Database
            future: _inspectionsFuture,
            builder: (context, snapshot) {
              // UI: Show a loader while the database is being queried
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // UI: Error handling / Empty state
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                  child: Text('Keine Aufträge in der Hauptdatenbank gefunden.'),
                );
              }

              final inspections = snapshot.data!;

              // UI: Render the list of jobs
              return ListView.builder(
                itemCount: inspections.length,
                itemBuilder: (context, index) {
                  final job = inspections[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    // ListTile provides a standard row with leading icon and multi-line text
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
                      // Logic: If already downloading, disable interactions to prevent duplicate calls
                      onTap: _isDownloading ? null : () => _handleJobDownload(job),
                    ),
                  );
                },
              );
            },
          ),
          // UI: Conditional overlay that covers the UI during the sync process
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