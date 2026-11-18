import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../services/photo_export_service.dart';
import '../services/excel_export_service.dart';
import '../utils/file_export_helper.dart';
import '../utils/inspection_year_utils.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/edit_inspection_dialog.dart';
import '../widgets/master_portal_home_button.dart';
import 'new_window_page.dart';
import 'window_history_page.dart';

enum InspectionWindowFilter {
  all,
  inspected,
  pending,
  openDefects,
  partiallyResolved,
  fullyResolved,
  noticesOnly,
  errorFree,
}

class InspectionWindowsPage extends StatefulWidget {
  final int inspectionId;
  final String title;
  final bool isManagerMode;

  const InspectionWindowsPage({
    super.key,
    required this.inspectionId,
    required this.title,
    this.isManagerMode = false,
  });

  @override
  State<InspectionWindowsPage> createState() => _InspectionWindowsPageState();
}

class _InspectionWindowsPageState extends State<InspectionWindowsPage> {
  List<Window> _windows = [];
  Map<int, DoorErrorSummary> _errorSummaries = {};
  Map<int, String> _windowInspectionStatuses = {};
  InspectionWindowFilter _filter = InspectionWindowFilter.all;
  bool _isLoading = true;
  final Set<int> _selectedWindowIds = {};
  final TextEditingController _searchController = TextEditingController();
  String? _inspectionDate;
  bool _isEditable = true;
  Timer? _snackBarDismissTimer;

  @override
  void initState() {
    super.initState();
    _loadWindows(isInitial: true);
  }

  @override
  void dispose() {
    _snackBarDismissTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _showDismissibleSnackBar(SnackBar snackBar) {
    if (!mounted) return;
    _snackBarDismissTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(snackBar);
    _snackBarDismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        messenger.hideCurrentSnackBar();
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) {
            messenger.clearSnackBars();
          }
        });
      }
    });
  }

  Future<void> _loadWindows({bool isInitial = false}) async {
    if (isInitial || _windows.isEmpty) {
      setState(() => _isLoading = true);
    }
    List<Window> windows;
    Map<int, DoorErrorSummary> errorSummaries;
    Map<int, String> statuses;
    _selectedWindowIds.clear();

    final Map<String, dynamic>? inspData = widget.isManagerMode
        ? await DatabaseService.getInspectionById(widget.inspectionId)
        : await LocalDatabaseService.getInspectionById(widget.inspectionId);

    _inspectionDate = inspData?['date']?.toString();
    final isLocked = inspData?['isLocked'];
    _isEditable = InspectionYearUtils.isEditable(
      isManagerMode: widget.isManagerMode,
      dateValue: _inspectionDate,
      isLocked: isLocked,
    );

    if (widget.isManagerMode) {
      windows = await DatabaseService.getWindowsByInspectionIds(
        [widget.inspectionId],
        query: _searchController.text,
      );
      errorSummaries = await DatabaseService.getWindowErrorSummariesForInspection(widget.inspectionId);
      statuses = await DatabaseService.getWindowInspectionStatuses(widget.inspectionId);
    } else {
      windows = await LocalDatabaseService.getWindowsByInspectionIds(
        [widget.inspectionId],
        query: _searchController.text,
      );
      errorSummaries = await LocalDatabaseService.getWindowErrorSummariesForInspection(widget.inspectionId);
      statuses = await LocalDatabaseService.getWindowInspectionStatuses(widget.inspectionId);
    }

    if (mounted) {
      setState(() {
        _windows = windows;
        _errorSummaries = errorSummaries;
        _windowInspectionStatuses = statuses;
        _isLoading = false;
      });
    }
  }

  bool _isWindowInspected(Window window) {
    if (window.id == null) return false;
    final status = (_windowInspectionStatuses[window.id] ?? '').trim().toLowerCase();
    return status == 'inspected' ||
        status == 'geprüft' ||
        status == 'completed' ||
        status == 'passed' ||
        status == 'failed' ||
        status == 'done' ||
        status == 'bearbeitet';
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedWindowIds.contains(id)) {
        _selectedWindowIds.remove(id);
      } else {
        _selectedWindowIds.add(id);
      }
    });
  }

  Future<void> _handleDeleteWindows() async {
    if (_selectedWindowIds.isEmpty) return;
    if (!_isEditable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fenster in gesperrten Aufträgen können nicht gelöscht werden.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final bool confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Löschen bestätigen'),
        content: Text('${_selectedWindowIds.length} Fenster unwiderruflich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (!confirm) return;
    if (widget.isManagerMode) {
      await DatabaseService.deleteWindows(_selectedWindowIds.toList());
    } else {
      await LocalDatabaseService.deleteWindows(_selectedWindowIds.toList());
    }
    _loadWindows();
  }

  Future<void> _toggleWindowInspectionStatus(Window window) async {
    if (window.id == null || !_isEditable) return;
    final isCurrentlyInspected = _isWindowInspected(window);
    final newStatus = isCurrentlyInspected ? 'Pending' : 'Inspected';

    if (widget.isManagerMode) {
      await DatabaseService.setWindowInspectionStatus(
        inspectionId: widget.inspectionId,
        windowId: window.id!,
        status: newStatus,
      );
    } else {
      await LocalDatabaseService.setWindowInspectionStatus(
        inspectionId: widget.inspectionId,
        windowId: window.id!,
        status: newStatus,
      );
    }

    if (mounted) {
      _showDismissibleSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          persist: false,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          content: Text(
            isCurrentlyInspected
                ? 'Fenster ${window.windowNumber} als "Offen" (nicht geprüft) markiert.'
                : 'Fenster ${window.windowNumber} als "Geprüft" markiert.',
          ),
          backgroundColor: isCurrentlyInspected ? Colors.orange.shade800 : Colors.teal.shade700,
          action: SnackBarAction(
            label: 'Rückgängig',
            textColor: Colors.white,
            onPressed: () {
              _snackBarDismissTimer?.cancel();
              _toggleWindowInspectionStatus(window);
            },
          ),
        ),
      );
      await _loadWindows();
    }
  }

  Future<void> _handleBatchSetStatus(String newStatus) async {
    if (_selectedWindowIds.isEmpty || !_isEditable) return;
    final count = _selectedWindowIds.length;
    for (final winId in _selectedWindowIds) {
      if (widget.isManagerMode) {
        await DatabaseService.setWindowInspectionStatus(
          inspectionId: widget.inspectionId,
          windowId: winId,
          status: newStatus,
        );
      } else {
        await LocalDatabaseService.setWindowInspectionStatus(
          inspectionId: widget.inspectionId,
          windowId: winId,
          status: newStatus,
        );
      }
    }
    if (mounted) {
      final isInspected = newStatus.toLowerCase() == 'inspected';
      _showDismissibleSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          persist: false,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          content: Text(
            isInspected
                ? '$count Fenster als "Geprüft" markiert.'
                : '$count Fenster als "Offen" (nicht geprüft) markiert.',
          ),
          backgroundColor: isInspected ? Colors.teal.shade700 : Colors.orange.shade800,
        ),
      );
      setState(() => _selectedWindowIds.clear());
      _loadWindows();
    }
  }

  Future<void> _handleScanBarcode() async {
    final scanned = await BarcodeScannerDialog.show(context, title: 'Barcode / QR-Code scannen');
    if (scanned == null || scanned.trim().isEmpty) return;

    final token = scanned.trim().toLowerCase();
    final match = _windows.where((w) {
      final aliasMatch = w.windowAlias?.toLowerCase() == token || w.provisionalAlias?.toLowerCase() == token;
      final numMatch = w.windowNumber.toLowerCase() == token;
      return aliasMatch || numMatch;
    }).firstOrNull;

    if (match != null) {
      _openWindowDetails(match);
    } else {
      if (!mounted) return;
      if (!_isEditable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kein Fenster mit Barcode/Nummer "$scanned" in diesem Auftrag gefunden.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Barcode nicht zugeordnet'),
          content: Text('Der gescannte Barcode "$scanned" konnte keinem Fenster in diesem Auftrag zugeordnet werden.\n\nWas möchten Sie tun?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'assign'),
              icon: const Icon(Icons.link),
              label: const Text('Bestehendem Fenster zuweisen'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'create'),
              icon: const Icon(Icons.add),
              label: const Text('Neu anlegen'),
            ),
          ],
        ),
      );

      if (action == 'assign' && mounted) {
        _showAssignBarcodeDialog(scanned.trim());
      } else if (action == 'create' && mounted) {
        final newWin = Window(
          windowNumber: scanned.trim(),
          floor: '',
          roomNumber: '',
          windowType: '',
          material: '',
          windowAlias: scanned.trim(),
        );
        _openWindowDetails(newWin);
      }
    }
  }

  void _showAssignBarcodeDialog(String scannedAlias) {
    if (!_isEditable) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fenster für Barcode-Zuweisung wählen'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _windows.length,
            itemBuilder: (context, index) {
              final window = _windows[index];
              return ListTile(
                leading: const Icon(Icons.window_outlined, color: Colors.teal),
                title: Text('Fenster ${window.windowNumber}'),
                subtitle: Text('Aktueller Alias: ${window.windowAlias ?? "Keiner"}\n${window.floor} | ${window.roomDesignation}'),
                onTap: () async {
                  Navigator.pop(context);
                  await _updateWindowAlias(window, scannedAlias);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        ],
      ),
    );
  }

  Future<void> _updateWindowAlias(Window window, String newAlias) async {
    final cleanAlias = newAlias.trim();
    if (window.id == null || !_isEditable || cleanAlias.isEmpty) return;

    final existingWindow = widget.isManagerMode
        ? await DatabaseService.findWindowByBarcode(cleanAlias, excludeWindowId: window.id)
        : await LocalDatabaseService.findWindowByBarcode(cleanAlias, excludeWindowId: window.id);

    if (existingWindow != null) {
      if (mounted) {
        final winDesc = existingWindow.windowNumber.isNotEmpty ? existingWindow.windowNumber : 'ID ${existingWindow.id}';
        final locationInfo = [
          if (existingWindow.floor.isNotEmpty) existingWindow.floor,
          if (existingWindow.roomDesignation.isNotEmpty) existingWindow.roomDesignation,
        ].join(', ');
        final locationText = locationInfo.isNotEmpty ? ' ($locationInfo)' : '';

        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                SizedBox(width: 8),
                Text('Barcode bereits vergeben'),
              ],
            ),
            content: Text(
              'Der Barcode "$cleanAlias" wird bereits für Fenster "$winDesc"$locationText verwendet.\n\n'
              'Ein Barcode darf nicht mehrfach vergeben werden.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (widget.isManagerMode) {
      await DatabaseService.updateWindowAlias(window.id!, cleanAlias);
    } else {
      await LocalDatabaseService.updateWindowAlias(window.id!, cleanAlias);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Neuer Barcode "$cleanAlias" für Fenster ${window.windowNumber} gespeichert.'),
          backgroundColor: Colors.green,
        ),
      );
      _loadWindows();
    }
  }

  void _showWindowNotesPopUp(Window window) {
    final notesText = window.notes.isNotEmpty ? window.notes : '(Keine Notizen erfasst)';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.note_alt_outlined, color: Colors.teal.shade800, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fenster ${window.windowNumber} - Notizen & Mängel',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Barcode: ${window.windowAlias ?? "Kein Alias"}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Text(notesText, style: const TextStyle(fontSize: 14)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Future<void> _openWindowDetails(Window? window) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewWindowPage(
          window: window,
          inspectionId: widget.inspectionId,
          isManagerMode: widget.isManagerMode,
          isReadOnly: !_isEditable,
        ),
      ),
    );

    if (result == true) {
      await _loadWindows();
    }
  }

  Future<void> _exportToExcel() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Excel-Export wird erstellt...')),
      );

      final tempDir = Directory.systemTemp;
      final fileName = 'Fensterliste_${widget.title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final outputPath = '${tempDir.path}/$fileName';

      final exportedFile = await ExcelExportService.exportSingleWindowInspection(
        widget.inspectionId,
        outputPath,
      );

      final savedPath = await FileExportHelper.saveFileSafely(
        defaultFileName: fileName,
        dialogTitle: 'Fensterliste exportieren',
        sourceFile: exportedFile,
        allowedExtensions: ['xlsx'],
      );

      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel erfolgreich exportiert: $savedPath'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Excel-Export: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildErrorStatusBadge(DoorErrorSummary summary, Window window) {
    final List<Widget> badges = [];

    // Raffstore badge if applicable (only if Raffstore is present and evaluated)
    if (window.hasRaffstore && window.raffstoreOK != null) {
      final raffstoreOk = window.raffstoreOK == true;
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: raffstoreOk ? Colors.blue.shade50 : Colors.deepOrange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: raffstoreOk ? Colors.blue.shade300 : Colors.deepOrange.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                raffstoreOk ? Icons.blinds_closed : Icons.blinds_closed_outlined,
                size: 13,
                color: raffstoreOk ? Colors.blue.shade800 : Colors.deepOrange.shade800,
              ),
              const SizedBox(width: 4),
              Text(
                raffstoreOk ? 'Raffstore i.O.' : 'Raffstore Defekt',
                style: TextStyle(
                  color: raffstoreOk ? Colors.blue.shade800 : Colors.deepOrange.shade800,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 1. Defect Badges
    if (summary.openDefects > 0 && summary.resolvedDefects == 0) {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 14, color: Colors.red.shade800),
              const SizedBox(width: 4),
              Text(
                summary.openDefects > 1
                    ? '${summary.openDefects} offene Mängel'
                    : 'Offener Mangel',
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    } else if (summary.openDefects > 0 && summary.resolvedDefects > 0) {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.published_with_changes, size: 14, color: Colors.orange.shade800),
              const SizedBox(width: 4),
              Text(
                'Teilweise behoben (${summary.resolvedDefects}/${summary.defectCount})',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    } else if (summary.resolvedDefects > 0) {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 14, color: Colors.teal.shade800),
              const SizedBox(width: 4),
              Text(
                'Fehler gelöst',
                style: TextStyle(
                  color: Colors.teal.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Notice Badge (Amber / Yellow)
    if (summary.noticeCount > 0) {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade600),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.amber.shade900),
              const SizedBox(width: 4),
              Text(
                summary.noticeCount > 1
                    ? '${summary.noticeCount} Hinweise'
                    : 'Hinweis',
                style: TextStyle(
                  color: Colors.amber.shade900,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: badges,
    );
  }

  Widget _buildInspectionStatusBadge(Window window, bool isInspected) {
    return Tooltip(
      message: _isEditable
          ? (isInspected ? 'Klicken: Status auf "Offen" (nicht geprüft) zurücksetzen' : 'Klicken: Als "Geprüft" markieren')
          : (isInspected ? 'Geprüft' : 'Offen'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _isEditable ? () => _toggleWindowInspectionStatus(window) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isInspected ? Colors.teal.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isInspected ? Colors.teal.shade400 : Colors.orange.shade300,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isInspected ? Icons.check_circle : Icons.hourglass_top,
                  size: 12,
                  color: isInspected ? Colors.teal.shade800 : Colors.orange.shade900,
                ),
                const SizedBox(width: 4),
                Text(
                  isInspected ? 'Geprüft' : 'Offen',
                  style: TextStyle(
                    color: isInspected ? Colors.teal.shade800 : Colors.orange.shade900,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_isEditable) ...[
                  const SizedBox(width: 3),
                  Icon(
                    Icons.sync_alt,
                    size: 10,
                    color: isInspected ? Colors.teal.shade700 : Colors.orange.shade800,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingIcon(Window window, DoorErrorSummary summary, bool isSelected, bool isSelectionMode, int windowId) {
    if (isSelectionMode) {
      return Checkbox(
        value: isSelected,
        onChanged: (_) => _toggleSelection(windowId),
      );
    }

    if (!widget.isManagerMode) {
      final isInspected = _isWindowInspected(window);
      if (!isInspected) {
        return CircleAvatar(
          backgroundColor: Colors.grey.shade100,
          child: Icon(Icons.hourglass_empty, color: Colors.grey.shade600, size: 20),
        );
      }
    }

    Color iconColor;
    Color avatarBg;
    IconData icon;

    if (summary.openDefects > 0) {
      iconColor = Colors.red.shade700;
      avatarBg = Colors.red.shade50;
      icon = Icons.error;
    } else if (summary.resolvedDefects > 0) {
      iconColor = Colors.teal.shade700;
      avatarBg = Colors.teal.shade50;
      icon = Icons.check_circle;
    } else if (summary.noticeCount > 0) {
      iconColor = Colors.amber.shade900;
      avatarBg = Colors.amber.shade50;
      icon = Icons.info_outline;
    } else {
      iconColor = Colors.teal.shade700;
      avatarBg = Colors.teal.shade50;
      icon = widget.isManagerMode ? Icons.window_outlined : Icons.task_alt;
    }

    return CircleAvatar(
      backgroundColor: avatarBg,
      child: Icon(icon, color: iconColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isSelectionMode = _selectedWindowIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: isSelectionMode
            ? Text('${_selectedWindowIds.length} ausgewählt')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(widget.title, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _isEditable ? Colors.green.shade50 : Colors.red.shade50,
                          border: Border.all(color: _isEditable ? Colors.green.shade300 : Colors.red.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isEditable ? Icons.lock_open : Icons.lock,
                              size: 10,
                              color: _isEditable ? Colors.green.shade900 : Colors.red.shade900,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isEditable ? 'Freigegeben' : 'Gesperrt',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _isEditable ? Colors.green.shade900 : Colors.red.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'ID: ${widget.inspectionId} • ${_windows.length} Fenster',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                  ),
                ],
              ),
        actions: isSelectionMode
            ? [
                IconButton(
                  icon: Icon(_selectedWindowIds.length == _windows.length
                      ? Icons.check_box
                      : Icons.check_box_outline_blank),
                  onPressed: () {
                    setState(() {
                      if (_selectedWindowIds.length == _windows.length) {
                        _selectedWindowIds.clear();
                      } else {
                        _selectedWindowIds.addAll(_windows.map((w) => w.id!));
                      }
                    });
                  },
                ),
              ]
            : [
                if (widget.isManagerMode)
                  IconButton(
                    icon: Icon(
                      _isEditable ? Icons.lock_open : Icons.lock,
                      color: _isEditable ? Colors.green : Colors.red,
                    ),
                    tooltip: _isEditable
                        ? 'Auftrag sperren (für Inspektor sperren)'
                        : 'Auftrag entsperren (für Inspektor freigeben)',
                    onPressed: () async {
                      await DatabaseService.setInspectionLockStatus(widget.inspectionId, _isEditable);
                      _loadWindows();
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner, color: Colors.teal),
                  tooltip: 'Barcode / QR-Code scannen',
                  onPressed: _handleScanBarcode,
                ),
                if (widget.isManagerMode)
                  IconButton(
                    icon: const Icon(Icons.edit_note),
                    tooltip: 'Auftrags-Metadaten & Sperrstatus bearbeiten',
                    onPressed: () async {
                      final updated = await EditInspectionDialog.show(
                        context,
                        inspectionId: widget.inspectionId,
                        isManagerMode: widget.isManagerMode,
                      );
                      if (updated == true && mounted) {
                        _loadWindows();
                      }
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.photo_library_outlined, color: Colors.teal),
                  tooltip: 'Alle Fotos dieses Auftrags exportieren',
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Fotos werden vorbereitet und exportiert...')),
                      );
                      final result = await PhotoExportService.exportInspectionPhotos(
                        inspectionId: widget.inspectionId,
                        isManagerMode: widget.isManagerMode,
                      );
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              result.totalPhotos > 0
                                  ? '${result.totalPhotos} Foto(s) exportiert nach:\n${result.outputDirectory}'
                                  : 'Keine Fotos in diesem Auftrag vorhanden.',
                            ),
                            backgroundColor: result.totalPhotos > 0 ? Colors.green : Colors.orange,
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Fehler beim Foto-Export: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.table_chart_outlined, color: Colors.teal),
                  tooltip: 'Excel exportieren',
                  onPressed: _exportToExcel,
                ),
                MasterPortalHomeButton(isManagerMode: widget.isManagerMode),
              ],
        leading: isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedWindowIds.clear()),
              )
            : null,
      ),
      body: Column(
        children: [
          if (!_isEditable)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_clock, color: Colors.orange.shade900),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Gesperrte Inspektion: Im Lesemodus. Inspektoren können gesperrte Inspektionen nicht bearbeiten.',
                      style: TextStyle(fontSize: 13, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          if (!isSelectionMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 6.0),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Fenster durchsuchen',
                  hintText: 'Fensternummer, Raum, Bezeichnung oder Fehler...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _loadWindows();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (value) => _loadWindows(),
              ),
            ),

          // Progress & Filter Header Card (Inspector & Manager)
          if (!_isLoading && _windows.isNotEmpty && !isSelectionMode) ...[
            Builder(
              builder: (context) {
                final totalCount = _windows.length;
                final inspectedCount = _windows.where((w) => _isWindowInspected(w)).length;
                final pendingCount = totalCount - inspectedCount;

                int totalJobDefects = 0;
                int resolvedJobDefects = 0;
                int totalJobNotices = 0;

                int windowsWithOpenDefects = 0;
                int windowsPartiallyResolved = 0;
                int windowsFullyResolved = 0;
                int windowsNoticesOnly = 0;
                int windowsErrorFreeCount = 0;

                for (final w in _windows) {
                  final s = _errorSummaries[w.id] ??
                      const DoorErrorSummary(totalErrors: 0, openErrors: 0, resolvedErrors: 0);
                  totalJobDefects += s.defectCount;
                  resolvedJobDefects += s.resolvedDefects;
                  totalJobNotices += s.noticeCount;

                  if (s.openDefects > 0 && s.resolvedDefects == 0) {
                    windowsWithOpenDefects++;
                  } else if (s.openDefects > 0 && s.resolvedDefects > 0) {
                    windowsPartiallyResolved++;
                  } else if (s.openDefects == 0 && s.resolvedDefects > 0) {
                    windowsFullyResolved++;
                  } else if (s.defectCount == 0 && s.noticeCount > 0) {
                    windowsNoticesOnly++;
                  } else if (_isWindowInspected(w) && s.totalErrors == 0) {
                    windowsErrorFreeCount++;
                  }
                }

                final openJobDefects = totalJobDefects - resolvedJobDefects;
                final progress = totalCount > 0 ? (inspectedCount / totalCount) : 0.0;

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Window Progress Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                inspectedCount == totalCount ? Icons.task_alt : Icons.pending_actions,
                                size: 18,
                                color: inspectedCount == totalCount ? Colors.teal.shade700 : Colors.teal.shade900,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Prüffortschritt: $inspectedCount von $totalCount Fenstern geprüft (${(progress * 100).toInt()}%)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: pendingCount == 0 ? Colors.teal.shade50 : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: pendingCount == 0 ? Colors.teal.shade300 : Colors.orange.shade300,
                              ),
                            ),
                            child: Text(
                              pendingCount == 0 ? 'Alle geprüft' : '$pendingCount ungeprüft',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: pendingCount == 0 ? Colors.teal.shade900 : Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            inspectedCount == totalCount ? Colors.teal : Colors.teal.shade600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 2. Global Defect Summary (Mängel gesamt: Behoben, Offen, Hinweise)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blueGrey.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.build_circle_outlined, size: 13, color: Colors.blueGrey.shade800),
                                const SizedBox(width: 4),
                                Text(
                                  'Mängel gesamt: $totalJobDefects',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey.shade900),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.teal.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 13, color: Colors.teal.shade800),
                                const SizedBox(width: 4),
                                Text(
                                  'Behoben: $resolvedJobDefects',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal.shade900),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: openJobDefects > 0 ? Colors.red.shade50 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: openJobDefects > 0 ? Colors.red.shade300 : Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline,
                                    size: 13,
                                    color: openJobDefects > 0 ? Colors.red.shade800 : Colors.grey.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  'Offen: $openJobDefects',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: openJobDefects > 0 ? Colors.red.shade900 : Colors.grey.shade800),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade400),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline, size: 13, color: Colors.amber.shade900),
                                const SizedBox(width: 4),
                                Text(
                                  'Hinweise: $totalJobNotices',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 3. Mutually Exclusive Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: Text('Fenster gesamt ($totalCount)'),
                              selected: _filter == InspectionWindowFilter.all,
                              onSelected: (_) => setState(() => _filter = InspectionWindowFilter.all),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              avatar: Icon(Icons.check_circle,
                                  size: 14,
                                  color: _filter == InspectionWindowFilter.inspected
                                      ? Colors.white
                                      : Colors.teal.shade700),
                              label: Text('Geprüft ($inspectedCount)'),
                              selected: _filter == InspectionWindowFilter.inspected,
                              selectedColor: Colors.teal.shade700,
                              onSelected: (_) => setState(() => _filter = InspectionWindowFilter.inspected),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              avatar: Icon(Icons.hourglass_top,
                                  size: 14,
                                  color: _filter == InspectionWindowFilter.pending
                                      ? Colors.white
                                      : Colors.orange.shade800),
                              label: Text('Ungeprüft ($pendingCount)'),
                              selected: _filter == InspectionWindowFilter.pending,
                              selectedColor: Colors.orange.shade800,
                              onSelected: (_) => setState(() => _filter = InspectionWindowFilter.pending),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              avatar: Icon(Icons.error,
                                  size: 14,
                                  color: _filter == InspectionWindowFilter.openDefects
                                      ? Colors.white
                                      : Colors.red.shade700),
                              label: Text('Offene Mängel ($windowsWithOpenDefects)'),
                              selected: _filter == InspectionWindowFilter.openDefects,
                              selectedColor: Colors.red.shade700,
                              onSelected: (_) => setState(() => _filter = InspectionWindowFilter.openDefects),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              avatar: Icon(Icons.published_with_changes,
                                  size: 14,
                                  color: _filter == InspectionWindowFilter.partiallyResolved
                                      ? Colors.white
                                      : Colors.orange.shade800),
                              label: Text('Teil-behoben ($windowsPartiallyResolved)'),
                              selected: _filter == InspectionWindowFilter.partiallyResolved,
                              selectedColor: Colors.orange.shade800,
                              onSelected: (_) =>
                                  setState(() => _filter = InspectionWindowFilter.partiallyResolved),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              avatar: Icon(Icons.task_alt,
                                  size: 14,
                                  color: _filter == InspectionWindowFilter.fullyResolved
                                      ? Colors.white
                                      : Colors.teal.shade700),
                              label: Text('Behoben ($windowsFullyResolved)'),
                              selected: _filter == InspectionWindowFilter.fullyResolved,
                              selectedColor: Colors.teal.shade700,
                              onSelected: (_) => setState(() => _filter = InspectionWindowFilter.fullyResolved),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              avatar: Icon(Icons.info_outline,
                                  size: 14,
                                  color: _filter == InspectionWindowFilter.noticesOnly
                                      ? Colors.white
                                      : Colors.amber.shade900),
                              label: Text('Nur Hinweise ($windowsNoticesOnly)'),
                              selected: _filter == InspectionWindowFilter.noticesOnly,
                              selectedColor: Colors.amber.shade900,
                              onSelected: (_) => setState(() => _filter = InspectionWindowFilter.noticesOnly),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              avatar: Icon(Icons.check_circle_outline,
                                  size: 14,
                                  color: _filter == InspectionWindowFilter.errorFree
                                      ? Colors.white
                                      : Colors.teal.shade800),
                              label: Text('Mängelfrei ($windowsErrorFreeCount)'),
                              selected: _filter == InspectionWindowFilter.errorFree,
                              selectedColor: Colors.teal.shade800,
                              onSelected: (_) => setState(() => _filter = InspectionWindowFilter.errorFree),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (context) {
                      final displayWindows = _windows.where((window) {
                        if (_filter == InspectionWindowFilter.inspected && !_isWindowInspected(window)) {
                          return false;
                        }
                        if (_filter == InspectionWindowFilter.pending && _isWindowInspected(window)) {
                          return false;
                        }
                        final summary = _errorSummaries[window.id] ??
                            const DoorErrorSummary(totalErrors: 0, openErrors: 0, resolvedErrors: 0);
                        if (_filter == InspectionWindowFilter.openDefects) {
                          if (!(summary.openDefects > 0 && summary.resolvedDefects == 0)) return false;
                        }
                        if (_filter == InspectionWindowFilter.partiallyResolved) {
                          if (!(summary.openDefects > 0 && summary.resolvedDefects > 0)) return false;
                        }
                        if (_filter == InspectionWindowFilter.fullyResolved) {
                          if (!(summary.openDefects == 0 && summary.resolvedDefects > 0)) return false;
                        }
                        if (_filter == InspectionWindowFilter.noticesOnly) {
                          if (!(summary.defectCount == 0 && summary.noticeCount > 0)) return false;
                        }
                        if (_filter == InspectionWindowFilter.errorFree) {
                          if (!_isWindowInspected(window) || summary.totalErrors > 0) return false;
                        }
                        return true;
                      }).toList();

                      if (displayWindows.isEmpty) {
                        return Center(
                          child: Text(
                            _searchController.text.isNotEmpty || _filter != InspectionWindowFilter.all
                                ? 'Keine passenden Fenster gefunden'
                                : 'Keine Fenster in diesem Auftrag gefunden',
                            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                          ),
                        );
                      }

                      return ListView.builder(
                        key: PageStorageKey('inspection_windows_${widget.inspectionId}'),
                        itemCount: displayWindows.length,
                        itemBuilder: (context, index) {
                          final window = displayWindows[index];
                          final isSelected = _selectedWindowIds.contains(window.id);
                          final isInspected = !widget.isManagerMode && _isWindowInspected(window);
                          final summary = _errorSummaries[window.id] ??
                              const DoorErrorSummary(totalErrors: 0, openErrors: 0, resolvedErrors: 0);

                          return Card(
                            color: isSelected
                                ? Colors.teal.shade50
                                : (isInspected ? Colors.teal.shade50.withValues(alpha: 0.15) : null),
                            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            elevation: isInspected ? 2 : 1,
                            shape: RoundedRectangleBorder(
                              side: BorderSide(
                                color: isSelected
                                    ? Colors.teal.shade400
                                    : (isInspected ? Colors.teal.shade300 : Colors.grey.shade200),
                                width: isSelected ? 2.0 : (isInspected ? 1.5 : 1.0),
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              leading: _buildLeadingIcon(
                                  window, summary, isSelected, isSelectionMode, window.id!),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Fenster ${window.windowNumber}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        if (!widget.isManagerMode) ...[
                                          const SizedBox(width: 8),
                                          _buildInspectionStatusBadge(window, isInspected),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (!isSelectionMode) _buildErrorStatusBadge(summary, window),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  'ID: ${window.windowAlias ?? "Kein Alias"}\n${window.floor} | ${window.roomDesignation}',
                                ),
                              ),
                              trailing: isSelectionMode
                                  ? null
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!widget.isManagerMode && _isEditable)
                                          IconButton(
                                            icon: Icon(
                                              isInspected ? Icons.check_circle : Icons.radio_button_unchecked,
                                              color: isInspected
                                                  ? Colors.teal.shade700
                                                  : Colors.orange.shade800,
                                              size: 22,
                                            ),
                                            tooltip: isInspected
                                                ? 'Als "Offen" (nicht geprüft) markieren'
                                                : 'Als "Geprüft" markieren',
                                            onPressed: () => _toggleWindowInspectionStatus(window),
                                          ),
                                        if (window.notes.isNotEmpty)
                                          IconButton(
                                            icon: const Icon(Icons.note_alt_outlined,
                                                color: Colors.teal, size: 20),
                                            tooltip: 'Notizen & Mängel anzeigen',
                                            onPressed: () => _showWindowNotesPopUp(window),
                                          ),
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                                          tooltip: 'Weitere Optionen',
                                          onSelected: (value) async {
                                            if (value == 'history') {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => WindowHistoryPage(
                                                    windowId: window.id,
                                                    windowAlias: window.windowAlias,
                                                    isManagerMode: widget.isManagerMode,
                                                  ),
                                                ),
                                              );
                                            } else if (value == 'barcode' && _isEditable) {
                                              final scanned = await BarcodeScannerDialog.show(
                                                context,
                                                title: 'Neuen Barcode für Fenster ${window.windowNumber} scannen',
                                              );
                                              if (scanned != null && scanned.isNotEmpty && mounted) {
                                                await _updateWindowAlias(window, scanned);
                                              }
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            const PopupMenuItem(
                                              value: 'history',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.history_edu, color: Colors.blueGrey, size: 18),
                                                  SizedBox(width: 8),
                                                  Text('Fenster-Akte & Historie'),
                                                ],
                                              ),
                                            ),
                                            if (_isEditable)
                                              const PopupMenuItem(
                                                value: 'barcode',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.qr_code_scanner,
                                                        color: Colors.teal, size: 18),
                                                    SizedBox(width: 8),
                                                    Text('Barcode scannen & zuweisen'),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                        const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                                      ],
                                    ),
                              onTap: () async {
                                if (isSelectionMode) {
                                  _toggleSelection(window.id!);
                                } else {
                                  await _openWindowDetails(window);
                                }
                              },
                              onLongPress: () => _toggleSelection(window.id!),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: (!isSelectionMode || widget.isManagerMode)
          ? null
          : BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    onPressed: (!_isEditable) ? null : _handleDeleteWindows,
                    icon: Icon(Icons.delete_outline, color: _isEditable ? Colors.red : Colors.grey),
                    tooltip: 'Löschen',
                  ),
                  if (_isEditable) ...[
                    const VerticalDivider(),
                    TextButton.icon(
                      onPressed: () => _handleBatchSetStatus('Inspected'),
                      icon: const Icon(Icons.check_circle, color: Colors.teal),
                      label: const Text('Als Geprüft', style: TextStyle(color: Colors.teal)),
                    ),
                    const VerticalDivider(),
                    TextButton.icon(
                      onPressed: () => _handleBatchSetStatus('Pending'),
                      icon: const Icon(Icons.hourglass_empty, color: Colors.orange),
                      label: const Text('Als Offen', style: TextStyle(color: Colors.orange)),
                    ),
                  ],
                ],
              ),
            ),
      floatingActionButton: (widget.isManagerMode || isSelectionMode || !_isEditable)
          ? null
          : FloatingActionButton(
              heroTag: 'fab_inspection_windows',
              tooltip: 'Neues Fenster hinzufügen',
              backgroundColor: Colors.teal,
              onPressed: () => _openWindowDetails(null),
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }
}
