import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/inspection_year_utils.dart';

/// A reusable widget to display a summary of an inspection.
/// Tapping on it will trigger the provided [onTap] callback.
class InspectionSummaryCard extends StatelessWidget {
  final int inspectionId;
  final String clientName;
  final String jobNumber;
  final String? projectNumber;
  final String date;
  final String orderType;
  final String? repairDate;
  final int? doorCount;
  final String? assetType;
  final int? windowCount;
  final dynamic isLocked;
  final VoidCallback? onEdit;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? craftnoteSyncStatus;
  final VoidCallback? onToggleLock;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectionChanged;

  const InspectionSummaryCard({
    super.key,
    required this.inspectionId,
    required this.clientName,
    required this.jobNumber,
    this.projectNumber,
    required this.date,
    this.orderType = 'Wartung',
    this.repairDate,
    this.doorCount,
    this.assetType,
    this.windowCount,
    this.isLocked,
    this.craftnoteSyncStatus,
    this.onEdit,
    this.onTap,
    this.onLongPress,
    this.onToggleLock,
    this.isSelected = false,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Format the date for consistent display
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(date);
    } catch (e) {
      parsedDate = DateTime.now(); 
    }
    final formattedDate = DateFormat('dd.MM.yyyy').format(parsedDate);
    final bool locked = InspectionYearUtils.isInspectionLocked(isLocked, date);
    final bool isReparatur = orderType == 'Reparatur';
    final bool isErledigt = orderType == 'Erledigt';
    final bool isWindow = assetType?.toLowerCase() == 'window' ||
        (windowCount != null && windowCount! > 0 && (doorCount == null || doorCount == 0));

    final Color badgeBg = isErledigt
        ? Colors.green.shade50
        : (isReparatur ? Colors.orange.shade100 : Colors.blue.shade50);
    final Color badgeBorder = isErledigt
        ? Colors.green.shade400
        : (isReparatur ? Colors.orange.shade400 : Colors.blue.shade300);
    final Color badgeTextColor = isErledigt
        ? Colors.green.shade900
        : (isReparatur ? Colors.orange.shade900 : Colors.blue.shade800);
    final IconData badgeIcon = isErledigt
        ? Icons.task_alt
        : (isReparatur ? Icons.handyman_outlined : Icons.build_circle_outlined);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: ListTile(
        leading: Icon(
          isErledigt
              ? Icons.check_circle_outline
              : (isReparatur
                  ? Icons.handyman_outlined
                  : (isWindow ? Icons.window : Icons.business)),
          color: isErledigt
              ? Colors.green.shade700
              : (isReparatur
                  ? Colors.orange.shade800
                  : (isWindow ? Colors.teal.shade700 : Colors.blue)),
        ),
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Text(clientName, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (isWindow)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.teal.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.window,
                      size: 11,
                      color: Colors.teal.shade900,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Fenster',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: badgeBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    badgeIcon,
                    size: 11,
                    color: badgeTextColor,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    orderType,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: badgeTextColor,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onToggleLock,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: locked ? Colors.red.shade50 : Colors.green.shade50,
                  border: Border.all(color: locked ? Colors.red.shade300 : Colors.green.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      locked ? Icons.lock : Icons.lock_open,
                      size: 12,
                      color: locked ? Colors.red.shade900 : Colors.green.shade900,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      locked ? 'Gesperrt' : 'Freigegeben',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: locked ? Colors.red.shade900 : Colors.green.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (craftnoteSyncStatus != null && craftnoteSyncStatus != 'none')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: craftnoteSyncStatus == 'synced'
                      ? Colors.green.shade50
                      : (craftnoteSyncStatus == 'queued'
                          ? Colors.orange.shade50
                          : Colors.blue.shade50),
                  border: Border.all(
                    color: craftnoteSyncStatus == 'synced'
                        ? Colors.green.shade300
                        : (craftnoteSyncStatus == 'queued'
                            ? Colors.orange.shade300
                            : Colors.blue.shade300),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      craftnoteSyncStatus == 'synced'
                          ? Icons.cloud_done
                          : (craftnoteSyncStatus == 'queued'
                              ? Icons.cloud_queue
                              : Icons.cloud_download),
                      size: 12,
                      color: craftnoteSyncStatus == 'synced'
                          ? Colors.green.shade900
                          : (craftnoteSyncStatus == 'queued'
                              ? Colors.orange.shade900
                              : Colors.blue.shade900),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      craftnoteSyncStatus == 'synced'
                          ? 'Craftnote'
                          : (craftnoteSyncStatus == 'queued'
                              ? 'Warteschlange'
                              : 'Importiert'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: craftnoteSyncStatus == 'synced'
                            ? Colors.green.shade900
                            : (craftnoteSyncStatus == 'queued'
                                ? Colors.orange.shade900
                                : Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text('Auftrag: $jobNumber'),
            if (projectNumber != null && projectNumber!.isNotEmpty)
              Text('Projekt: $projectNumber'),
            if (isReparatur || (isErledigt && repairDate != null && repairDate!.isNotEmpty))
              Text(
                'Reparaturdatum: ${repairDate ?? formattedDate}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isErledigt ? Colors.green.shade900 : Colors.orange.shade900,
                ),
              )
            else
              Text('Prüfdatum: $formattedDate'),
            if (isWindow && windowCount != null)
              Text('Fenster gesamt: $windowCount')
            else if (doorCount != null)
              Text('Türen gesamt: $doorCount'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onToggleLock != null)
              IconButton(
                icon: Icon(locked ? Icons.lock : Icons.lock_open, color: locked ? Colors.red : Colors.green),
                tooltip: locked ? 'Sperre aufheben (Manager)' : 'Inspektion sperren (Manager)',
                onPressed: onToggleLock,
              ),
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit_note, color: Colors.blue),
                tooltip: 'Metadaten bearbeiten',
                onPressed: onEdit,
              ),
            if (onSelectionChanged != null)
              Checkbox(
                value: isSelected,
                onChanged: onSelectionChanged,
              ),
          ],
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}