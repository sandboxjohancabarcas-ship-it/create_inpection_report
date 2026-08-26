import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/door.dart';
import '../services/database_service.dart';
import '../widgets/master_portal_home_button.dart';

/// Single Door History View ("Tür-Akte" / Patient Clinical Record)
/// Displays the master technical specs, health status badge,
/// lifetime statistics, and a chronological timeline of all historical inspections & defects.
import '../widgets/export_center_dialog.dart';

class DoorHistoryPage extends StatefulWidget {
  final int? doorId;
  final String? doorAlias;

  const DoorHistoryPage({
    super.key,
    this.doorId,
    this.doorAlias,
  }) : assert(doorId != null || doorAlias != null, 'Either doorId or doorAlias must be provided');

  @override
  State<DoorHistoryPage> createState() => _DoorHistoryPageState();
}

class _DoorHistoryPageState extends State<DoorHistoryPage> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _historyData;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await DatabaseService.getDoorHistoryData(
        doorId: widget.doorId,
        doorAlias: widget.doorAlias,
      );

      if (mounted) {
        setState(() {
          _historyData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Fehler beim Laden der Tür-Akte: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Tür-Akte (Prüfhistorie)'),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Tür-Akte exportieren',
            onPressed: () {
              final door = _historyData?['door'] as Map<String, dynamic>?;
              final alias = door?['doorAlias'] as String? ?? widget.doorAlias;
              ExportCenterDialog.show(context, initialDoorAlias: alias);
            },
          ),
          const MasterPortalHomeButton(color: Colors.white),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadHistory,
                          child: const Text('Erneut versuchen'),
                        ),
                      ],
                    ),
                  ),
                )
              : _historyData == null
                  ? const Center(
                      child: Text('Tür konnte in der Datenbank nicht gefunden werden.'),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadHistory,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Patient Master Header Card
                            _buildHeaderCard(),
                            const SizedBox(height: 16),

                            // 2. Health & Lifetime Stats Cards
                            _buildStatsRow(),
                            const SizedBox(height: 16),

                            // 3. Technical Specs Accordion Card
                            _buildTechnicalSpecsCard(),
                            const SizedBox(height: 24),

                            // 4. Chronological Timeline Header
                            Row(
                              children: [
                                const Icon(Icons.history_edu, color: Colors.blueGrey),
                                const SizedBox(width: 8),
                                Text(
                                  'Prüfungsverlauf & Untersuchungshistorie',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey.shade900,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // 5. Timeline List
                            _buildTimelineList(),
                          ],
                        ),
                      ),
                    ),
    );
  }

  Widget _buildHeaderCard() {
    final Door door = _historyData!['door'] as Door;
    final String healthStatus = _historyData!['healthStatus'] as String;

    Color healthColor;
    String healthLabel;
    IconData healthIcon;

    if (healthStatus == 'red') {
      healthColor = Colors.red;
      healthLabel = 'Kritische Mängel festgestellt';
      healthIcon = Icons.warning_amber_rounded;
    } else if (healthStatus == 'yellow') {
      healthColor = Colors.orange.shade800;
      healthLabel = 'Leichte / Mittlere Mängel';
      healthIcon = Icons.info_outline;
    } else {
      healthColor = Colors.green.shade700;
      healthLabel = 'Mängelfrei / Ordnungsgemäß';
      healthIcon = Icons.check_circle_outline;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: healthColor.withValues(alpha: 0.15),
                  child: Icon(Icons.door_front_door, color: healthColor, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        door.doorNumber.isNotEmpty ? 'Tür ${door.doorNumber}' : 'Tür (ohne Nummer)',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${door.floor.isNotEmpty ? "${door.floor} | " : ""}${door.roomDesignation.isNotEmpty ? door.roomDesignation : "Raum unbenannt"} ${door.roomNumber.isNotEmpty ? "(${door.roomNumber})" : ""}',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                if (door.doorAlias != null && door.doorAlias!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      border: Border.all(color: Colors.blue.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.qr_code, size: 14, color: Colors.blue.shade700),
                            const SizedBox(width: 4),
                            const Text(
                              'Patienten-ID',
                              style: TextStyle(fontSize: 10, color: Colors.blue),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          door.doorAlias!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            // Health Status Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: healthColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: healthColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(healthIcon, color: healthColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Gesundheitsstatus: $healthLabel',
                      style: TextStyle(
                        color: healthColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final int totalInspections = _historyData!['totalInspections'] as int;
    final int currentOpenErrors = _historyData!['currentOpenErrors'] as int;
    final int resolvedErrors = _historyData!['resolvedErrors'] as int;
    final int totalLifetimeErrors = _historyData!['totalLifetimeErrors'] as int;

    return Row(
      children: [
        _buildStatCard('Prüfungen', '$totalInspections', Icons.verified_user, Colors.blue),
        const SizedBox(width: 8),
        _buildStatCard('Offene Mängel', '$currentOpenErrors', Icons.warning_amber, currentOpenErrors > 0 ? Colors.red : Colors.green),
        const SizedBox(width: 8),
        _buildStatCard('Beholfen', '$resolvedErrors', Icons.check_circle, Colors.teal),
        const SizedBox(width: 8),
        _buildStatCard('Gesamt Mängel', '$totalLifetimeErrors', Icons.history, Colors.purple),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalSpecsCard() {
    final Door door = _historyData!['door'] as Door;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: const Icon(Icons.build_circle_outlined, color: Colors.blueGrey),
        title: const Text(
          'Technische Stammdaten',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          'Typ: ${door.doorType} | Material: ${door.material} | Hersteller: ${door.manufacturer}',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _buildSpecItem('Türtyp', door.doorType),
                _buildSpecItem('Material', door.material),
                _buildSpecItem('Hersteller', door.manufacturer),
                _buildSpecItem('Flügelanzahl', '${door.wingCount}'),
                _buildSpecItem('DIN-Richtung', door.dinConfiguration),
                _buildSpecItem('Türschließer', door.closerType),
                _buildSpecItem('Schließfolgeregler', door.closingSequenceSystem),
                _buildSpecItem('Schlossmaße', door.lockDimensions),
                _buildSpecItem('Beschlag', door.fittingType),
                _buildSpecItem('Panikfunktion', door.panicFunction),
                _buildSpecItem('Zutrittskontrolle', door.accessControl),
                _buildSpecItem('Fluchtwegsteuerung', door.escapeDoorControl ? 'Ja' : 'Nein'),
                _buildSpecItem('Fluchtwegbeschilderung', door.escapeRouteSignage ? 'Vorhanden' : 'Nein'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecItem(String label, String value) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          Text(
            value.isNotEmpty ? value : '-',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineList() {
    final List<Map<String, dynamic>> historyItems = _historyData!['historyItems'] as List<Map<String, dynamic>>;

    if (historyItems.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.event_note, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            const Text(
              'Noch keine historischen Prüfprotokolle für diese Tür erfasst.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: historyItems.length,
      itemBuilder: (context, index) {
        final item = historyItems[index];
        final Map<String, dynamic> insp = item['inspection'];
        final List<Map<String, dynamic>> errors = item['errors'];
        final int errorCount = item['errorCount'];

        final String rawDate = insp['date'] ?? '';
        String formattedDate = rawDate;
        try {
          if (rawDate.isNotEmpty) {
            final parsed = DateTime.parse(rawDate);
            formattedDate = DateFormat('dd.MM.yyyy HH:mm').format(parsed);
          }
        } catch (_) {}

        final String inspector = insp['inspectorName'] ?? 'Unbekannt';
        final String client = insp['clientName'] ?? '';
        final String jobNumber = insp['jobNumber'] ?? '';
        final String notes = insp['junctionNotes'] ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header line
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: errorCount > 0 ? Colors.red.shade50 : Colors.green.shade50,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      errorCount > 0 ? Icons.error_outline : Icons.check_circle_outline,
                      color: errorCount > 0 ? Colors.red.shade700 : Colors.green.shade700,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Prüfung am $formattedDate',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.blueGrey.shade900,
                            ),
                          ),
                          Text(
                            'Prüfer: $inspector ${jobNumber.isNotEmpty ? "• Auftrag: $jobNumber" : ""}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                    Chip(
                      backgroundColor: errorCount > 0 ? Colors.red : Colors.green,
                      label: Text(
                        errorCount > 0 ? '$errorCount Mängel' : 'Mängelfrei',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (client.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'Kunde: $client',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),

                    if (notes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.note, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Notiz: $notes',
                                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Defects section
                    if (errors.isNotEmpty) ...[
                      const Text(
                        'Festgestellte Mängel in dieser Prüfung:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      ...errors.map((e) {
                        final String code = e['errorCode'] ?? '';
                        final String desc = e['catalogDescription'] ?? e['notes'] ?? 'Keine Beschreibung';
                        final String severity = (e['severity'] ?? 'medium').toLowerCase();
                        final String resStatus = (e['resolutionStatus'] ?? 'open').toLowerCase();

                        final bool isResolved = resStatus == 'resolved' || resStatus == 'beholfen';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isResolved ? Colors.grey.shade50 : Colors.red.shade50.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isResolved ? Colors.grey.shade300 : Colors.red.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isResolved ? Icons.check_circle : Icons.warning,
                                color: isResolved ? Colors.grey : Colors.red,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (code.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.blueGrey.shade100,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              code,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blueGrey.shade900,
                                              ),
                                            ),
                                          ),
                                        if (code.isNotEmpty) const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            desc,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              decoration: isResolved ? TextDecoration.lineThrough : null,
                                              color: isResolved ? Colors.grey.shade600 : Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (e['catalogRecommendation'] != null && (e['catalogRecommendation'] as String).isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2.0),
                                        child: Text(
                                          'Empfehlung: ${e['catalogRecommendation']}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isResolved ? Colors.grey.shade300 : (severity == 'high' || severity == 'critical' ? Colors.red : Colors.orange),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  isResolved ? 'Beholfen' : severity.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isResolved ? Colors.black87 : Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
