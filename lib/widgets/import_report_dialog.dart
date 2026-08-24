import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/import_report.dart';

class ImportReportDialog extends StatelessWidget {
  final ImportReport report;

  const ImportReportDialog({
    super.key,
    required this.report,
  });

  static Future<void> show(BuildContext context, ImportReport report) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => ImportReportDialog(report: report),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedDate = DateFormat('dd.MM.yyyy HH:mm').format(report.importedAt);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 620,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
                  child: const Icon(Icons.analytics_outlined, color: Colors.blue, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Import-Zusammenfassung',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Paket: ${report.packageName} • $formattedDate',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
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
            const SizedBox(height: 20),

            // Overview Metric Chips / Cards
            Row(
              children: [
                _buildStatCard(
                  context,
                  title: 'Verarbeitete Türen',
                  value: '${report.totalDoorsProcessed}',
                  subtitle: '+${report.newDoorsCount} neu, ${report.updatedDoorsCount} aktualisiert',
                  icon: Icons.door_front_door,
                  color: Colors.indigo,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  context,
                  title: 'Mängel / Fehler',
                  value: '${report.totalErrorsImported}',
                  subtitle: 'Erfasste Fehlerdaten',
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  context,
                  title: 'Fotos / Dateianhänge',
                  value: '${report.totalAttachmentsImported}',
                  subtitle: 'Importierte Anhänge',
                  icon: Icons.photo_library,
                  color: Colors.teal,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Tabbed / Section Details
            DefaultTabController(
              length: report.newCatalogProposals.isNotEmpty ? 2 : 1,
              child: Expanded(
                child: Column(
                  children: [
                    TabBar(
                      labelColor: theme.primaryColor,
                      unselectedLabelColor: Colors.grey.shade600,
                      indicatorColor: theme.primaryColor,
                      tabs: [
                        Tab(text: 'Türen (${report.doorChanges.length})'),
                        if (report.newCatalogProposals.isNotEmpty)
                          Tab(text: 'Katalog-Vorschläge (${report.newCatalogProposals.length})'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Doors Tab
                          report.doorChanges.isEmpty
                              ? const Center(child: Text('Keine Tür-Details vorhanden.'))
                              : ListView.separated(
                                  itemCount: report.doorChanges.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final door = report.doorChanges[index];
                                    final isNew = door.changeType == 'new';
                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      leading: CircleAvatar(
                                        backgroundColor: isNew ? Colors.green.shade50 : Colors.blue.shade50,
                                        child: Icon(
                                          isNew ? Icons.add_business : Icons.sync,
                                          color: isNew ? Colors.green : Colors.blue,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        'Tür ${door.doorNumber.isNotEmpty ? door.doorNumber : door.doorAlias}',
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                      ),
                                      subtitle: Text(
                                        '${door.roomDesignation.isNotEmpty ? door.roomDesignation : "Ohne Raumbeschreibung"} • Alias: ${door.doorAlias}',
                                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (door.errorCount > 0)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              margin: const EdgeInsets.only(right: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade50,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.orange.shade200),
                                              ),
                                              child: Text(
                                                '${door.errorCount} Mängel',
                                                style: const TextStyle(
                                                    color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isNew ? Colors.green.shade100 : Colors.blue.shade100,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              isNew ? 'Neu' : 'Aktualisiert',
                                              style: TextStyle(
                                                color: isNew ? Colors.green.shade900 : Colors.blue.shade900,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                          // Catalog Proposals Tab
                          if (report.newCatalogProposals.isNotEmpty)
                            ListView.separated(
                              itemCount: report.newCatalogProposals.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final prop = report.newCatalogProposals[index];
                                return ListTile(
                                  leading: const Icon(Icons.new_releases_outlined, color: Colors.purple),
                                  title: Text(prop, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                  subtitle: const Text('Neuer Fehlercode vom Techniker vorgeschlagen'),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Footer Action
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check),
                label: const Text('Fertig'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade800, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
