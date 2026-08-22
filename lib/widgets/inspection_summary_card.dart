import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A reusable widget to display a summary of an inspection.
/// Tapping on it will trigger the provided [onTap] callback.
class InspectionSummaryCard extends StatelessWidget {
  final int inspectionId;
  final String clientName;
  final String jobNumber;
  final String? projectNumber;
  final String date;
  final int? doorCount;
  final VoidCallback? onEdit;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
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
    this.onEdit,
    this.onTap,
    this.onLongPress,
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
      // Fallback to current date or a placeholder if the date string is invalid
      parsedDate = DateTime.now(); 
    }
    final formattedDate = DateFormat('dd.MM.yyyy').format(parsedDate);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: ListTile(
        leading: const Icon(Icons.business, color: Colors.blue),
        title: Text(clientName),
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