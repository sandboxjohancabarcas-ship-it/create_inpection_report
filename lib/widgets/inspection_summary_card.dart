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
  final int? doorCount;
  final dynamic isLocked;
  final VoidCallback? onEdit;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
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
    this.doorCount,
    this.isLocked,
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: ListTile(
        leading: const Icon(Icons.business, color: Colors.blue),
        title: Row(
          children: [
            Expanded(child: Text(clientName, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
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
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Auftrag: $jobNumber'),
            if (projectNumber != null && projectNumber!.isNotEmpty)
              Text('Projekt: $projectNumber'),
            Text('Datum: $formattedDate'),
            if (doorCount != null) Text('Türen gesamt: $doorCount'),
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