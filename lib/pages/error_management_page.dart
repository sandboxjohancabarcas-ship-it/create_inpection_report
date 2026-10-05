import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/catalog_integrity_service.dart';
import '../widgets/master_portal_home_button.dart';
import '../widgets/full_screen_photo_viewer.dart';
import '../utils/photo_name_helper.dart';

class ErrorManagementPage extends StatefulWidget {
  final int doorId;
  final String doorNumber;
  final int inspectionId;
  /// When true, reads/writes use DatabaseService (Master DB) instead of LocalDatabaseService (working.db).
  final bool isManagerMode;
  final bool isReadOnly;

  const ErrorManagementPage({
    super.key,
    required this.doorId,
    required this.doorNumber,
    required this.inspectionId,
    this.isManagerMode = false,
    this.isReadOnly = false,
  });

  @override
  _ErrorManagementPageState createState() => _ErrorManagementPageState();
}

class _ErrorManagementPageState extends State<ErrorManagementPage> {
  List<ErrorCatalog> availableErrors = [];
  List<InspectionDoorError> doorErrors = [];
  List<ErrorCatalog> searchResults = [];
  ErrorCatalog? selectedError;
  int? _inspectionDoorId;
  String _doorAlias = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Loads data from the correct database based on [widget.isManagerMode].
  /// If [syncWithMain] is true, it attempts to refresh the local catalog from the main DB first.
  Future<void> _loadData({bool syncWithMain = false}) async {
    setState(() => isLoading = true);
    
    try {
      if (widget.isManagerMode) {
        // Manager mode: read from Master DB (DatabaseService)
        final junctions = await DatabaseService.getInspectionDoorsByInspectionId(widget.inspectionId);
        final junction = junctions.where((j) => j['doorId'] == widget.doorId).firstOrNull;
        _inspectionDoorId = junction?['id'] as int?;

        final catalogSuggestions = await DatabaseService.getAllErrorCatalog(status: 'Approved');
        final inspectionErrors = _inspectionDoorId != null
            ? await DatabaseService.getErrorsForInspectionDoor(_inspectionDoorId!)
            : <InspectionDoorError>[];

        print('[Manager] Loaded ${catalogSuggestions.length} catalog errors');
        print('[Manager] Loaded ${inspectionErrors.length} inspection errors for door ${widget.doorId}');

        setState(() {
          availableErrors = catalogSuggestions;
          doorErrors = inspectionErrors;
          isLoading = false;
        });
      } else {
        // Inspector mode: read from local working.db (LocalDatabaseService)
        final junction = await LocalDatabaseService.getInspectionDoor(widget.inspectionId, widget.doorId);
        _inspectionDoorId = junction?['id'];

        if (syncWithMain) {
          try {
            await LocalDatabaseService.refreshLocalCatalogFromMain();
          } catch (e) {
            print('Haupt-Datenbank nicht erreichbar. Fahre mit lokalem Katalog fort: $e');
          }
        }

        final catalogSuggestions = await LocalDatabaseService.getAllErrorCatalog();
        final inspectionErrors = _inspectionDoorId != null
            ? await LocalDatabaseService.getErrorsForInspectionDoor(_inspectionDoorId!)
            : <InspectionDoorError>[];

        print('Loaded ${catalogSuggestions.length} catalog errors');
        print('Loaded ${inspectionErrors.length} inspection errors');

        final door = widget.isManagerMode
            ? await DatabaseService.getDoorById(widget.doorId)
            : await LocalDatabaseService.getDoorById(widget.doorId);
        final resolvedAlias = door?.doorAlias?.trim().isNotEmpty == true
            ? door!.doorAlias!.trim()
            : (door?.provisionalAlias?.trim().isNotEmpty == true
                ? door!.provisionalAlias!.trim()
                : widget.doorNumber);

        setState(() {
          availableErrors = catalogSuggestions;
          doorErrors = inspectionErrors;
          _doorAlias = resolvedAlias;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading data: $e');
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden: $e')),
        );
      }
    }
  }

  

  Future<String?> _pickImageAsBase64(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (image == null) return null;

      final File file = File(image.path);
      final int sizeInBytes = await file.length();
      const int maxSizeInBytes = 60 * 1024 * 1024; // 60 MB

      if (sizeInBytes > maxSizeInBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Das Bild ist zu groß. Maximale Größe ist 60 MB (Aktuell: ${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB).'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }

      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Auswählen des Fotos: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _openNotesInputDialog(TextEditingController controller) async {
    final tempController = TextEditingController(text: controller.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: Colors.blue),
            SizedBox(width: 8),
            Text('Notizen zum Fehler'),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width > 600 ? 550 : MediaQuery.of(context).size.width * 0.9,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Geben Sie hier detaillierte Beobachtungen und Notizen zum Fehler ein:',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tempController,
                autofocus: true,
                maxLines: 8,
                minLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Detaillierte Fehlerbeschreibung, Fundort, Ursache, Bemerkungen...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, tempController.text),
            icon: const Icon(Icons.check),
            label: const Text('Übernehmen'),
          ),
        ],
      ),
    );
    if (result != null) {
      controller.text = result;
    }
  }

  Widget _buildDialogPhotoThumbnails(
    List<String> photos,
    void Function(int index) onRemove,
    void Function(int index) onView,
  ) {
    if (photos.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 75,
      margin: const EdgeInsets.only(top: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        itemBuilder: (context, index) {
          final photoBase64 = photos[index];
          return Stack(
            children: [
              GestureDetector(
                onTap: () => onView(index),
                child: Container(
                  width: 65,
                  height: 65,
                  margin: const EdgeInsets.only(right: 10, top: 4, bottom: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      base64Decode(photoBase64),
                      fit: BoxFit.cover,
                      cacheWidth: 130,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 6,
                child: GestureDetector(
                  onTap: () => onRemove(index),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _markDoorAsInspectedIfInspector() async {
    if (!widget.isManagerMode) {
      await LocalDatabaseService.updateInspectionDoorStatus(
        inspectionId: widget.inspectionId,
        doorId: widget.doorId,
        status: 'Inspected',
      );
    }
  }

  Future<void> _addCatalogError(ErrorCatalog error, String notes, {List<String> photos = const []}) async {
    if (_inspectionDoorId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler: Keine aktive Inspektions-Sitzung für diese Tür gefunden.')),
        );
      }
      return;
    }

    final inspectionError = InspectionDoorError(
      inspectionDoorId: _inspectionDoorId!,
      errorId: error.errorId ?? 0,
      errorCode: error.code,
      notes: notes,
      quantity: 1,
      severity: error.severity,
      attachments: photos.where((p) => p.isNotEmpty).join(','),
    );

    try {
      if (widget.isManagerMode) {
        await DatabaseService.insertInspectionDoorError(inspectionError);
      } else {
        await LocalDatabaseService.insertInspectionDoorError(inspectionError);
        await _markDoorAsInspectedIfInspector();
      }
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler wurde erfolgreich hinzugefügt.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Hinzufügen: $e')),
        );
      }
    }
  }

  void _showAddErrorDialog() {
    final notesController = TextEditingController();
    final codeController = TextEditingController();
    final descriptionController = TextEditingController();
    final categoryController = TextEditingController();
    final severityController = TextEditingController(text: 'medium');
    final recommendationController = TextEditingController();
    final normReferenceController = TextEditingController();
    final searchController = TextEditingController();
    final List<String> dialogPhotos = [];
    ErrorCatalog? selectedError;
    String? selectedCategory;
    bool isProvisional = false;

    // Extract unique categories from catalog
    final Set<String> categorySet = {};
    for (final err in availableErrors) {
      if (err.category.trim().isNotEmpty && err.category != 'Altdaten') {
        categorySet.add(err.category.trim());
      }
    }
    final List<String> categories = categorySet.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    String? selectedProvisionalCategory = categories.isNotEmpty ? categories.first : null;
    bool isCustomProvisionalCategory = categories.isEmpty;
    final customCategoryController = TextEditingController();
    if (selectedProvisionalCategory != null) {
      categoryController.text = selectedProvisionalCategory;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) {
          final screenWidth = MediaQuery.of(context).size.width;
          final screenHeight = MediaQuery.of(context).size.height;
          final dialogWidth = screenWidth > 900 ? 820.0 : screenWidth * 0.95;
          final dialogHeight = screenHeight * 0.85;

          // Filter errors based on category and search query
          final query = searchController.text.trim().toLowerCase();
          final filteredErrors = availableErrors.where((error) {
            final matchesCategory = selectedCategory == null ||
                selectedCategory!.isEmpty ||
                error.category.toLowerCase() == selectedCategory!.toLowerCase();
            if (!matchesCategory) return false;

            if (query.isEmpty) return true;

            return error.code.toLowerCase().contains(query) ||
                error.category.toLowerCase().contains(query) ||
                error.description.toLowerCase().contains(query) ||
                error.normReference.toLowerCase().contains(query) ||
                error.recommendation.toLowerCase().contains(query);
          }).toList();

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.report_problem, color: isProvisional ? Colors.orange : Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(isProvisional ? 'Provisorischen Fehler erstellen' : 'Fehler hinzufügen'),
              ],
            ),
            content: SizedBox(
              width: dialogWidth,
              height: dialogHeight,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mode Toggle
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('Aus Katalog wählen')),
                              selected: !isProvisional,
                              onSelected: (selected) {
                                if (selected) {
                                  dialogSetState(() => isProvisional = false);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('Provisorischer Fehler')),
                              selected: isProvisional,
                              onSelected: (selected) {
                                if (selected) {
                                  dialogSetState(() => isProvisional = true);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (!isProvisional) ...[
                      if (selectedError == null) ...[
                        // Category Selection & Search Bar
                        Card(
                          elevation: 0,
                          color: Colors.blue.shade50.withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.blue.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.category, size: 18, color: Colors.blue),
                                    const SizedBox(width: 6),
                                    const Text(
                                      '1. Fehlerkategorie wählen:',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    if (selectedCategory != null && selectedCategory!.isNotEmpty) ...[
                                      const Spacer(),
                                      TextButton(
                                        onPressed: () => dialogSetState(() => selectedCategory = null),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text('Kategorie zurücksetzen', style: TextStyle(fontSize: 12)),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String?>(
                                  value: selectedCategory,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                    hintText: 'Alle Kategorien (${availableErrors.length} Fehler)',
                                  ),
                                  items: [
                                    DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text(
                                        'Alle Kategorien (${availableErrors.length} Fehler)',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    ...categories.map((cat) {
                                      final count = availableErrors
                                          .where((e) => e.category.toLowerCase() == cat.toLowerCase())
                                          .length;
                                      return DropdownMenuItem<String?>(
                                        value: cat,
                                        child: Text('$cat ($count Fehler)'),
                                      );
                                    }),
                                  ],
                                  onChanged: (value) {
                                    dialogSetState(() {
                                      selectedCategory = value;
                                    });
                                  },
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(Icons.search, size: 18, color: Colors.blue),
                                    const SizedBox(width: 6),
                                    const Text(
                                      '2. Suche (nach Kategorie, Code oder Beschreibung):',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: searchController,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    labelText: 'Suchbegriff eingeben...',
                                    hintText: 'z.B. Türschließer, 1.1.1, Schloss, Dichtung...',
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: searchController.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear),
                                            onPressed: () {
                                              searchController.clear();
                                              dialogSetState(() {});
                                            },
                                          )
                                        : null,
                                  ),
                                  onChanged: (value) => dialogSetState(() {}),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Error List View Header
                        Row(
                          children: [
                            Text(
                              '${filteredErrors.length} Fehler gefunden',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                                fontSize: 13,
                              ),
                            ),
                            if (selectedCategory != null && selectedCategory!.isNotEmpty)
                              Text(
                                ' in "$selectedCategory"',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade700,
                                  fontSize: 13,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Error List View
                        Container(
                          height: 320,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade50,
                          ),
                          child: filteredErrors.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Keine passenden Fehler gefunden',
                                        style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Wählen Sie eine andere Kategorie oder ändern Sie den Suchbegriff.',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(6),
                                  itemCount: filteredErrors.length,
                                  separatorBuilder: (context, index) => const SizedBox(height: 4),
                                  itemBuilder: (context, index) {
                                    final err = filteredErrors[index];
                                    return Card(
                                      margin: EdgeInsets.zero,
                                      elevation: 1,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        side: BorderSide(color: Colors.grey.shade200),
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () => dialogSetState(() => selectedError = err),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              CircleAvatar(
                                                radius: 16,
                                                backgroundColor: Colors.blue.shade100,
                                                child: Text(
                                                  err.code.isNotEmpty ? err.code.split('.')[0] : '!',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue.shade900,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Text(
                                                          err.code,
                                                          style: const TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        if (err.isNotice) ...[
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                            decoration: BoxDecoration(
                                                              color: Colors.amber.shade100,
                                                              borderRadius: BorderRadius.circular(4),
                                                              border: Border.all(color: Colors.amber.shade400),
                                                            ),
                                                            child: Text(
                                                              'Hinweis',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                color: Colors.amber.shade900,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 6),
                                                        ],
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: err.isNotice ? Colors.amber.shade50 : Colors.blue.shade50,
                                                            borderRadius: BorderRadius.circular(4),
                                                            border: Border.all(color: err.isNotice ? Colors.amber.shade200 : Colors.blue.shade200),
                                                          ),
                                                          child: Text(
                                                            err.category,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: Colors.blue.shade800,
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: _getSeverityColor(err.severity).withOpacity(0.15),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Text(
                                                            _getSeverityDisplay(err.severity),
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.bold,
                                                              color: _getSeverityColor(err.severity),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      err.description,
                                                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    if (err.recommendation.isNotEmpty || err.normReference.isNotEmpty) ...[
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        [
                                                          if (err.normReference.isNotEmpty) 'Norm: ${err.normReference}',
                                                          if (err.recommendation.isNotEmpty) 'Empfehlung: ${err.recommendation}',
                                                        ].join(' | '),
                                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton(
                                                onPressed: () => dialogSetState(() => selectedError = err),
                                                style: ElevatedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  textStyle: const TextStyle(fontSize: 11),
                                                ),
                                                child: const Text('Auswählen'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ] else ...[
                        // Selected Error Display Card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            border: Border.all(color: Colors.green.shade300, width: 1.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.green, size: 22),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Ausgewählter Fehler:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade900,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const Spacer(),
                                  OutlinedButton.icon(
                                    onPressed: () => dialogSetState(() => selectedError = null),
                                    icon: const Icon(Icons.swap_horiz, size: 16),
                                    label: const Text('Anderen Fehler wählen'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Row(
                                children: [
                                  Text(
                                    selectedError!.code,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      selectedError!.category,
                                      style: TextStyle(fontSize: 12, color: Colors.blue.shade900, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _getSeverityColor(selectedError!.severity).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _getSeverityDisplay(selectedError!.severity),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: _getSeverityColor(selectedError!.severity),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(selectedError!.description, style: const TextStyle(fontSize: 13)),
                              if (selectedError!.recommendation.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('Empfehlung: ${selectedError!.recommendation}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                              ],
                              if (selectedError!.normReference.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text('Norm: ${selectedError!.normReference}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Notes section with Pop-up Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Notizen zum Fehler:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                await _openNotesInputDialog(notesController);
                                dialogSetState(() {});
                              },
                              icon: const Icon(Icons.fullscreen, size: 18),
                              label: const Text('In separatem Fenster bearbeiten'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: notesController,
                          decoration: InputDecoration(
                            labelText: 'Notizen',
                            hintText: 'Detaillierte Beobachtungen, Fundort, Bemerkungen...',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.open_in_new),
                              tooltip: 'Großansicht öffnen',
                              onPressed: () async {
                                await _openNotesInputDialog(notesController);
                                dialogSetState(() {});
                              },
                            ),
                          ),
                          maxLines: 3,
                          onChanged: (v) => dialogSetState(() {}),
                        ),
                        const SizedBox(height: 16),

                        // Photo Attachments Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Fotonachweis (${dialogPhotos.length} Fotos):',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final photo = await _pickImageAsBase64(ImageSource.camera);
                                    if (photo != null) {
                                      dialogSetState(() => dialogPhotos.add(photo));
                                    }
                                  },
                                  icon: const Icon(Icons.camera_alt, size: 16),
                                  label: const Text('Kamera'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final photo = await _pickImageAsBase64(ImageSource.gallery);
                                    if (photo != null) {
                                      dialogSetState(() => dialogPhotos.add(photo));
                                    }
                                  },
                                  icon: const Icon(Icons.photo_library, size: 16),
                                  label: const Text('Galerie'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        _buildDialogPhotoThumbnails(
                          dialogPhotos,
                          (idx) => dialogSetState(() => dialogPhotos.removeAt(idx)),
                          (idx) => _viewPhotoFullScreen(
                            dialogPhotos,
                            idx,
                            errorCode: selectedError?.code ?? 'Fehler',
                          ),
                        ),
                      ],
                    ] else ...[
                      // Dynamic Category Picker for Provisional Error
                      Card(
                        elevation: 0,
                        color: Colors.orange.shade50.withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: Colors.orange.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.category, size: 18, color: Colors.deepOrange),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Kategorie auswählen oder neu erstellen:',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  if (isCustomProvisionalCategory && categories.isNotEmpty) ...[
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: () {
                                        dialogSetState(() {
                                          isCustomProvisionalCategory = false;
                                          selectedProvisionalCategory = categories.first;
                                          categoryController.text = categories.first;
                                        });
                                      },
                                      icon: const Icon(Icons.list, size: 14),
                                      label: const Text('Aus Liste wählen', style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (!isCustomProvisionalCategory && categories.isNotEmpty) ...[
                                DropdownButtonFormField<String>(
                                  value: categories.contains(selectedProvisionalCategory)
                                      ? selectedProvisionalCategory
                                      : categories.first,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                    labelText: 'Bestehende Kategorie',
                                  ),
                                  items: [
                                    ...categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                                    const DropdownMenuItem(
                                      value: '__NEW_CATEGORY__',
                                      child: Row(
                                        children: [
                                          Icon(Icons.add_circle_outline, size: 16, color: Colors.deepOrange),
                                          SizedBox(width: 6),
                                          Text(
                                            '+ Neue Kategorie erstellen...',
                                            style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val == '__NEW_CATEGORY__') {
                                      dialogSetState(() {
                                        isCustomProvisionalCategory = true;
                                        categoryController.clear();
                                      });
                                    } else if (val != null) {
                                      dialogSetState(() {
                                        selectedProvisionalCategory = val;
                                        categoryController.text = val;
                                        if (codeController.text.isEmpty) {
                                          codeController.text = CatalogIntegrityService.proposeNextCodeForCategory(val, availableErrors);
                                        }
                                      });
                                    }
                                  },
                                ),
                              ] else ...[
                                TextField(
                                  controller: customCategoryController,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    labelText: 'Neue Kategorie Bezeichnung *',
                                    hintText: 'z.B. Zarge & Türblatt, Feststellanlage...',
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                    prefixIcon: const Icon(Icons.create_new_folder, color: Colors.deepOrange),
                                    suffixIcon: categories.isNotEmpty
                                        ? IconButton(
                                            tooltip: 'Zurück zur Auswahlliste',
                                            icon: const Icon(Icons.close),
                                            onPressed: () {
                                              dialogSetState(() {
                                                isCustomProvisionalCategory = false;
                                                selectedProvisionalCategory = categories.first;
                                                categoryController.text = categories.first;
                                              });
                                            },
                                          )
                                        : null,
                                  ),
                                  onChanged: (val) {
                                    categoryController.text = val.trim();
                                    dialogSetState(() {});
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Code field with dynamic code generator
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: codeController,
                              decoration: InputDecoration(
                                labelText: 'Fehlercode *',
                                border: const OutlineInputBorder(),
                                hintText: 'z.B. 1.1, 11.20, etc.',
                                suffixIcon: IconButton(
                                  tooltip: 'Nächsten freien Code berechnen',
                                  icon: const Icon(Icons.auto_awesome, color: Colors.blue),
                                  onPressed: () {
                                    final cat = categoryController.text.trim().isNotEmpty
                                        ? categoryController.text.trim()
                                        : (selectedProvisionalCategory ?? 'Allgemein');
                                    final nextCode = CatalogIntegrityService.proposeNextCodeForCategory(cat, availableErrors);
                                    codeController.text = nextCode;
                                    dialogSetState(() {});
                                  },
                                ),
                              ),
                              onChanged: (val) => dialogSetState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                            ),
                            onPressed: () {
                              final cat = categoryController.text.trim().isNotEmpty
                                  ? categoryController.text.trim()
                                  : (selectedProvisionalCategory ?? 'Allgemein');
                              final nextCode = CatalogIntegrityService.proposeNextCodeForCategory(cat, availableErrors);
                              codeController.text = nextCode;
                              dialogSetState(() {});
                            },
                            icon: const Icon(Icons.tag, size: 16),
                            label: const Text('Code vorschlagen', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),

                      // Live Code Collision Warning
                      Builder(builder: (context) {
                        final code = codeController.text.trim();
                        final collision = CatalogIntegrityService.findCodeCollision(code, availableErrors);
                        if (collision != null) {
                          return Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, size: 18, color: Colors.red),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Code "$code" ist bereits an "${collision.description}" vergeben!',
                                    style: TextStyle(color: Colors.red.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    final cat = categoryController.text.trim().isNotEmpty
                                        ? categoryController.text.trim()
                                        : (selectedProvisionalCategory ?? 'Allgemein');
                                    codeController.text = CatalogIntegrityService.proposeNextCodeForCategory(cat, availableErrors);
                                    dialogSetState(() {});
                                  },
                                  child: const Text('Freien Code wählen', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      }),
                      const SizedBox(height: 8),

                      // Description field
                      TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Beschreibung *',
                          border: OutlineInputBorder(),
                          hintText: 'Fehlerbeschreibung eingeben...',
                        ),
                        maxLines: 2,
                        onChanged: (val) => dialogSetState(() {}),
                      ),

                      // Live Description Similarity / Duplicate Warning
                      Builder(builder: (context) {
                        final desc = descriptionController.text.trim();
                        final simMatch = CatalogIntegrityService.findSimilarDescription(desc, availableErrors, threshold: 0.65);
                        if (simMatch != null) {
                          return Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.lightbulb_outline, size: 18, color: Colors.orange),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Ähnlicher Fehler existiert bereits (${simMatch.similarityPercentage}% Ähnlichkeit):',
                                        style: TextStyle(color: Colors.orange.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${simMatch.existing.code} - ${simMatch.existing.description}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      dialogSetState(() {
                                        isProvisional = false;
                                        selectedError = simMatch.existing;
                                      });
                                    },
                                    icon: const Icon(Icons.check, size: 14),
                                    label: const Text('Diesen Katalog-Fehler wählen', style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      }),
                      const SizedBox(height: 8),

                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'Schweregrad'),
                        value: const ['low', 'medium', 'high', 'critical'].contains(severityController.text.toLowerCase())
                            ? severityController.text.toLowerCase()
                            : 'medium',
                        items: const ['low', 'medium', 'high', 'critical'].map((severity) {
                          return DropdownMenuItem<String>(
                            value: severity,
                            child: Text(_getSeverityDisplay(severity)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            dialogSetState(() => severityController.text = value);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: recommendationController,
                        decoration: const InputDecoration(
                          labelText: 'Empfehlung',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: normReferenceController,
                        decoration: const InputDecoration(
                          labelText: 'Normreferenz',
                          border: OutlineInputBorder(),
                          hintText: 'z.B. DIN 18095, DIN 18251',
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Notes section with Pop-up Button for Provisional
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Notizen zum Fehler:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await _openNotesInputDialog(notesController);
                              dialogSetState(() {});
                            },
                            icon: const Icon(Icons.fullscreen, size: 18),
                            label: const Text('In separatem Fenster bearbeiten'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesController,
                        decoration: InputDecoration(
                          labelText: 'Notizen',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.open_in_new),
                            tooltip: 'Großansicht öffnen',
                            onPressed: () async {
                              await _openNotesInputDialog(notesController);
                              dialogSetState(() {});
                            },
                          ),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),

                      // Photo Attachments for Provisional
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Fotonachweis (${dialogPhotos.length} Fotos):',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final photo = await _pickImageAsBase64(ImageSource.camera);
                                  if (photo != null) {
                                    dialogSetState(() => dialogPhotos.add(photo));
                                  }
                                },
                                icon: const Icon(Icons.camera_alt, size: 16),
                                label: const Text('Kamera'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 6),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final photo = await _pickImageAsBase64(ImageSource.gallery);
                                  if (photo != null) {
                                    dialogSetState(() => dialogPhotos.add(photo));
                                  }
                                },
                                icon: const Icon(Icons.photo_library, size: 16),
                                label: const Text('Galerie'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      _buildDialogPhotoThumbnails(
                        dialogPhotos,
                        (idx) => dialogSetState(() => dialogPhotos.removeAt(idx)),
                        (idx) => _viewPhotoFullScreen(
                          dialogPhotos,
                          idx,
                          errorCode: codeController.text.trim().isNotEmpty ? codeController.text.trim() : 'Fehler',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Abbrechen'),
              ),
              if (!isProvisional && selectedError != null)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _addCatalogError(selectedError!, notesController.text, photos: dialogPhotos);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Fehler hinzufügen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              if (isProvisional)
                ElevatedButton.icon(
                  onPressed: () async {
                    // Add provisional error
                    if (codeController.text.trim().isEmpty || descriptionController.text.trim().isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Fehlercode und Beschreibung sind erforderlich')),
                        );
                      }
                      return;
                    }

                    final provisionalError = ErrorCatalog(
                      code: codeController.text.trim(),
                      description: descriptionController.text.trim(),
                      category: categoryController.text.trim().isNotEmpty ? categoryController.text.trim() : 'provisional',
                      severity: severityController.text,
                      recommendation: recommendationController.text.trim(),
                      normReference: normReferenceController.text.trim(),
                      status: 'Pending',
                    );

                    try {
                      ErrorCatalog insertedError;
                      if (widget.isManagerMode) {
                        await DatabaseService.insertErrorCatalog(provisionalError);
                        final errors = await DatabaseService.searchErrorCatalog(provisionalError.code);
                        insertedError = errors.firstWhere(
                          (e) => e.code == provisionalError.code,
                          orElse: () => provisionalError,
                        );
                      } else {
                        await LocalDatabaseService.insertErrorCatalogItems([provisionalError]);
                        final errors = await LocalDatabaseService.searchErrorCatalog(provisionalError.code);
                        insertedError = errors.firstWhere(
                          (e) => e.code == provisionalError.code,
                          orElse: () => provisionalError,
                        );
                      }

                      if (_inspectionDoorId == null) {
                        throw Exception('Keine Inspektions-Sitzung gefunden');
                      }

                      final inspectionError = InspectionDoorError(
                        inspectionDoorId: _inspectionDoorId!,
                        errorId: insertedError.errorId ?? 0,
                        errorCode: insertedError.code,
                        notes: notesController.text,
                        quantity: 1,
                        severity: insertedError.severity,
                        attachments: dialogPhotos.where((p) => p.isNotEmpty).join(','),
                      );

                      if (widget.isManagerMode) {
                        await DatabaseService.insertInspectionDoorError(inspectionError);
                      } else {
                        await LocalDatabaseService.insertInspectionDoorError(inspectionError);
                      }

                      if (mounted) {
                        Navigator.pop(context);
                        _loadData();

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Provisorischer Fehler wurde hinzugefügt und zur Genehmigung eingereicht'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Fehler beim Hinzufügen: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Provisorisch hinzufügen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showErrorDetails(InspectionDoorError error) async {
    // 1. Try finding from already loaded catalog items in memory
    ErrorCatalog? currentCatalog = availableErrors.where(
      (e) => (error.errorId != null && error.errorId! > 0 && e.errorId == error.errorId) ||
             (error.errorCode.isNotEmpty && e.code == error.errorCode),
    ).firstOrNull;

    // 2. If not found in memory, query the appropriate database
    if (currentCatalog == null) {
      if (widget.isManagerMode) {
        if (error.errorId != null && error.errorId! > 0) {
          currentCatalog = await DatabaseService.getErrorCatalogItemById(error.errorId!);
        }
        if (currentCatalog == null && error.errorCode.isNotEmpty) {
          final results = await DatabaseService.searchErrorCatalog(error.errorCode);
          currentCatalog = results.where((e) => e.code == error.errorCode).firstOrNull ?? results.firstOrNull;
        }
      } else {
        if (error.errorId != null && error.errorId! > 0) {
          currentCatalog = await LocalDatabaseService.getErrorCatalogItemById(error.errorId!);
        }
        if (currentCatalog == null && error.errorCode.isNotEmpty) {
          final results = await LocalDatabaseService.searchErrorCatalog(error.errorCode);
          currentCatalog = results.where((e) => e.code == error.errorCode).firstOrNull ?? results.firstOrNull;
        }
      }
    }

    final ErrorCatalog catalogDetails = currentCatalog ?? ErrorCatalog(
      code: error.errorCode.isNotEmpty ? error.errorCode : 'Unbekannt',
      description: 'Fehler nicht im Katalog gefunden',
      category: 'Unbekannt',
    );

    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Fehler-Details'),
        content: SizedBox(
          width: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Code: ${catalogDetails.code}', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Beschreibung: ${catalogDetails.description}'),
              SizedBox(height: 8),
              Text('Kategorie: ${catalogDetails.category}'),
              SizedBox(height: 8),
              Text('Schweregrad: ${_getSeverityDisplay(catalogDetails.severity)}'),
              if (catalogDetails.recommendation.isNotEmpty) ...[
                SizedBox(height: 8),
                Text('Empfehlung: ${catalogDetails.recommendation}'),
              ],
              if (catalogDetails.normReference.isNotEmpty) ...[
                SizedBox(height: 8),
                Text('Normreferenz: ${catalogDetails.normReference}'),
              ],
              SizedBox(height: 16),
              Text('Notizen: ${error.notes}'),
            ],
          ),
        ),
        actions: [
          if (error.resolutionStatus != 'resolved') ...[
            TextButton(
              onPressed: () async {
                final updatedError = error.copyWith(resolutionStatus: 'resolved');
                if (widget.isManagerMode) {
                  await DatabaseService.insertInspectionDoorError(updatedError);
                } else {
                  await LocalDatabaseService.insertInspectionDoorError(updatedError);
                  await _markDoorAsInspectedIfInspector();
                }
                if (mounted) {
                  Navigator.pop(context);
                  _loadData();
                }
              },
              child: Text('Als gelöst markieren'),
            ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Schließen'),
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.red;
      case 'in_progress':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getStatusDisplay(String status) {
    switch (status) {
      case 'open':
        return 'Offen';
      case 'in_progress':
        return 'In Bearbeitung';
      case 'resolved':
        return 'Gelöst';
      default:
        return status;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'open':
        return Icons.error;
      case 'in_progress':
        return Icons.pending;
      case 'resolved':
        return Icons.check_circle;
      default:
        return Icons.help;
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
        title: Text('Fehlermanagement - Tür ${widget.doorNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(syncWithMain: true),
          ),
          const MasterPortalHomeButton(),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (widget.isReadOnly)
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
                            'Vorjahres-Auftrag: Im Lesemodus. Fehler können von Inspektoren nicht hinzugefügt, bearbeitet oder gelöscht werden.',
                            style: TextStyle(fontSize: 13, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(height: 16),
                
                // Error list
                Expanded(
                  child: doorErrors.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'Keine Fehler für diese Tür',
                                style: TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                              SizedBox(height: 16),
                              if (!widget.isReadOnly)
                                ElevatedButton.icon(
                                  onPressed: _showAddErrorDialog,
                                  icon: Icon(Icons.add),
                                  label: Text('Fehler hinzufügen'),
                                ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: doorErrors.length,
                          itemBuilder: (context, index) {
                            final error = doorErrors[index];
                            final errorCatalog = availableErrors.firstWhere(
                              (e) => e.errorId == error.errorId || (error.errorCode.isNotEmpty && e.code == error.errorCode),
                              orElse: () => ErrorCatalog(
                                code: error.errorCode.isNotEmpty ? error.errorCode : 'Unbekannt',
                                description: 'Fehler nicht im Katalog gefunden',
                                category: 'Unbekannt',
                              ),
                            );

                            return Card(
                              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: errorCatalog.isNotice
                                      ? (error.resolutionStatus.toLowerCase() == 'resolved' ? Colors.green : Colors.amber.shade700)
                                      : _getStatusColor(error.resolutionStatus),
                                  child: Icon(
                                    errorCatalog.isNotice
                                        ? (error.resolutionStatus.toLowerCase() == 'resolved' ? Icons.check_circle : Icons.info_outline)
                                        : _getStatusIcon(error.resolutionStatus),
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                              errorCatalog.code,
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(errorCatalog.description),
                                    SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (errorCatalog.isNotice) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade50,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.amber.shade400),
                                            ),
                                            child: Text(
                                              'Hinweis',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.amber.shade900,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: errorCatalog.isNotice ? Colors.amber.shade50 : Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                        errorCatalog.category,
                                            style: TextStyle(fontSize: 12, color: errorCatalog.isNotice ? Colors.amber.shade900 : null),
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
                                      if (error.notes.isNotEmpty) ...[
                                        SizedBox(height: 4),
                                    Text('Notizen: ${error.notes}', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                                      ],
                                      _buildPhotoGallery(error),
                                    ],
                                  ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                  _showEditDialog(error);
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
                                onTap: () => _showErrorDetails(error),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_error_management',
        onPressed: _showAddErrorDialog,
        tooltip: 'Fehler hinzufügen',
        child: Icon(Icons.add),
      ),
    );
  }

  void _showEditDialog(InspectionDoorError error) {
    // Find the error catalog entry
    final errorCatalog = availableErrors.firstWhere(
      (e) => e.errorId == error.errorId || (error.errorCode.isNotEmpty && e.code == error.errorCode),
      orElse: () => ErrorCatalog(
        code: error.errorCode.isNotEmpty ? error.errorCode : 'Unbekannt',
        description: 'Fehler nicht im Katalog gefunden',
        category: 'Unbekannt',
      ),
    );

    final notesController = TextEditingController(text: error.notes);
    final validStatuses = ['open', 'in_progress', 'resolved'];
    String status = validStatuses.contains(error.resolutionStatus.toLowerCase())
        ? error.resolutionStatus.toLowerCase()
        : 'open';

    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, editSetState) => AlertDialog(
          title: const Text('Fehler bearbeiten'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fehlercode: ${errorCatalog.code}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Beschreibung:', style: TextStyle(fontWeight: FontWeight.w500)),
                  Text(errorCatalog.description),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                    value: status,
                    items: validStatuses.map((s) {
                      return DropdownMenuItem<String>(
                        value: s,
                        child: Text(_getStatusDisplay(s)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        editSetState(() => status = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Notizen:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      TextButton.icon(
                        onPressed: () async {
                          await _openNotesInputDialog(notesController);
                          editSetState(() {});
                        },
                        icon: const Icon(Icons.fullscreen, size: 16),
                        label: const Text('Im Großfenster bearbeiten'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: 'Notizen',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.open_in_new),
                        tooltip: 'Großansicht öffnen',
                        onPressed: () async {
                          await _openNotesInputDialog(notesController);
                          editSetState(() {});
                        },
                      ),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                final updatedError = error.copyWith(resolutionStatus: status, notes: notesController.text);
                if (widget.isManagerMode) {
                  await DatabaseService.insertInspectionDoorError(updatedError);
                } else {
                  await LocalDatabaseService.insertInspectionDoorError(updatedError);
                  await _markDoorAsInspectedIfInspector();
                }
                if (mounted) {
                  Navigator.pop(context);
                  _loadData();
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteError(InspectionDoorError error) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Mangel löschen oder lösen?'),
          ],
        ),
        content: const Text(
          'Wichtiger Hinweis zur Dokumentation & Reparatur:\n\n'
          '• Reparierte bzw. behobene Mängel dürfen NICHT gelöscht werden. Bitte markieren Sie diese als "Gelöst", damit die Reparaturhistorie erhalten bleibt.\n\n'
          '• Das Löschen ist ausschließlich für versehentliche Fehleingaben gedacht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          OutlinedButton(
            onPressed: () async {
              if (widget.isManagerMode) {
                await DatabaseService.deleteInspectionDoorError(error.id!);
              } else {
                await LocalDatabaseService.deleteInspectionDoorError(error.id!);
                await _markDoorAsInspectedIfInspector();
              }
              if (mounted) {
                Navigator.pop(context);
                _loadData();
              }
            },
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Trotzdem löschen (Fehleingabe)'),
          ),
          if (error.resolutionStatus != 'resolved')
            ElevatedButton.icon(
              onPressed: () async {
                final updatedError = error.copyWith(resolutionStatus: 'resolved');
                if (widget.isManagerMode) {
                  await DatabaseService.insertInspectionDoorError(updatedError);
                } else {
                  await LocalDatabaseService.insertInspectionDoorError(updatedError);
                  await _markDoorAsInspectedIfInspector();
                }
                if (mounted) {
                  Navigator.pop(context);
                  _loadData();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Als "Gelöst" markieren'),
            ),
        ],
      ),
    );
  }

  Future<void> _addPhotoToError(InspectionDoorError error, ImageSource source) async {
    try {
      final base64Str = await _pickImageAsBase64(source);
      if (base64Str == null) return;

      // Append base64 string to attachments (comma-separated)
      List<String> currentPhotos = error.attachments.split(',').where((s) => s.isNotEmpty).toList();
      currentPhotos.add(base64Str);
      final newAttachments = currentPhotos.join(',');

      final updatedError = error.copyWith(attachments: newAttachments);
      if (widget.isManagerMode) {
        await DatabaseService.insertInspectionDoorError(updatedError);
      } else {
        await LocalDatabaseService.insertInspectionDoorError(updatedError);
        await _markDoorAsInspectedIfInspector();
      }
      
      _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto erfolgreich hinzugefügt.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error adding photo: \$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Hinzufügen des Fotos: \$e')),
        );
      }
    }
  }

  Future<void> _deletePhotoFromError(InspectionDoorError error, int photoIndex) async {
    try {
      List<String> currentPhotos = error.attachments.split(',').where((s) => s.isNotEmpty).toList();
      if (photoIndex >= 0 && photoIndex < currentPhotos.length) {
        currentPhotos.removeAt(photoIndex);
      }
      final newAttachments = currentPhotos.join(',');

      final updatedError = error.copyWith(attachments: newAttachments);
      if (widget.isManagerMode) {
        await DatabaseService.insertInspectionDoorError(updatedError);
      } else {
        await LocalDatabaseService.insertInspectionDoorError(updatedError);
        await _markDoorAsInspectedIfInspector();
      }
      
      _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto gelöscht.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('Error deleting photo: \$e');
    }
  }

  void _viewPhotoFullScreen(List<String> photos, int initialIndex, {String errorCode = ''}) {
    if (photos.isEmpty) return;
    final photoNames = PhotoNameHelper.formatPhotoNames(
      doorAlias: _doorAlias.isNotEmpty ? _doorAlias : widget.doorNumber,
      errorCode: errorCode.isNotEmpty ? errorCode : 'Fehler',
      photoCount: photos.length,
    );
    showDialog(
      context: context,
      builder: (context) => FullScreenPhotoGalleryViewer(
        photos: photos,
        initialIndex: initialIndex,
        photoNames: photoNames,
      ),
    );
  }

  void _showAddPhotoSourceSheet(InspectionDoorError error) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Kamera'),
              onTap: () {
                Navigator.pop(context);
                _addPhotoToError(error, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galerie'),
              onTap: () {
                Navigator.pop(context);
                _addPhotoToError(error, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoGallery(InspectionDoorError error) {
    final photos = error.attachments.split(',').where((s) => s.isNotEmpty).toList();
    
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fotonachweis:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 70,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length + 1,
              itemBuilder: (context, index) {
                if (index == photos.length) {
                  // Add photo button
                  return GestureDetector(
                    onTap: () => _showAddPhotoSourceSheet(error),
                    child: Container(
                      width: 60,
                      height: 60,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade50,
                      ),
                      child: Icon(Icons.add_a_photo, color: Colors.grey.shade600, size: 24),
                    ),
                  );
                }

                final photoBase64 = photos[index];
                final photoName = PhotoNameHelper.formatPhotoName(
                  doorAlias: _doorAlias.isNotEmpty ? _doorAlias : widget.doorNumber,
                  errorCode: error.errorCode,
                  photoIndex: index + 1,
                );

                return Stack(
                  children: [
                    Tooltip(
                      message: photoName,
                      child: GestureDetector(
                        onTap: () => _viewPhotoFullScreen(photos, index, errorCode: error.errorCode),
                        child: Container(
                          width: 60,
                          height: 60,
                          margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              base64Decode(photoBase64),
                              fit: BoxFit.cover,
                              cacheWidth: 120, // performance optimization
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _deletePhotoFromError(error, index),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
