import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import '../services/catalog_integrity_service.dart';
import '../services/database_service.dart';
import '../services/local_database_service.dart';
import '../widgets/full_screen_photo_viewer.dart';
import '../widgets/master_portal_home_button.dart';
import '../utils/photo_name_helper.dart';

class WindowErrorManagementPage extends StatefulWidget {
  final int windowId;
  final String windowNumber;
  final int inspectionId;
  final bool isManagerMode;
  final bool isReadOnly;

  const WindowErrorManagementPage({
    super.key,
    required this.windowId,
    required this.windowNumber,
    required this.inspectionId,
    this.isManagerMode = false,
    this.isReadOnly = false,
  });

  @override
  State<WindowErrorManagementPage> createState() =>
      _WindowErrorManagementPageState();
}

class _WindowErrorManagementPageState extends State<WindowErrorManagementPage> {
  int? _inspectionWindowId;
  List<InspectionWindowError> _errors = [];
  List<ErrorCatalog> _catalog = [];
  String _windowAlias = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      if (widget.isManagerMode) {
        final junctions =
            await DatabaseService.getInspectionWindowsByInspectionId(
                widget.inspectionId);
        final junction = junctions
            .where((j) => j['windowId'] == widget.windowId)
            .firstOrNull;
        _inspectionWindowId = junction?['id'] as int?;

        _catalog =
            await DatabaseService.getAllErrorCatalog(assetType: 'window');

        if (_inspectionWindowId != null) {
          _errors = await DatabaseService.getInspectionWindowErrors(
              _inspectionWindowId!);
        }

        final win = await DatabaseService.getWindowById(widget.windowId);
        _windowAlias = win?.windowAlias?.trim().isNotEmpty == true
            ? win!.windowAlias!.trim()
            : (win?.provisionalAlias?.trim().isNotEmpty == true
                ? win!.provisionalAlias!.trim()
                : widget.windowNumber);
      } else {
        final junctions =
            await LocalDatabaseService.getInspectionWindowsByInspectionId(
                widget.inspectionId);
        final junction = junctions
            .where((j) => j['windowId'] == widget.windowId)
            .firstOrNull;
        _inspectionWindowId = junction?['id'] as int?;

        _catalog =
            await LocalDatabaseService.getAllErrorCatalog(assetType: 'window');

        if (_inspectionWindowId != null) {
          _errors = await LocalDatabaseService.getInspectionWindowErrors(
              _inspectionWindowId!);
        }

        final win = await LocalDatabaseService.getWindowById(widget.windowId);
        _windowAlias = win?.windowAlias?.trim().isNotEmpty == true
            ? win!.windowAlias!.trim()
            : (win?.provisionalAlias?.trim().isNotEmpty == true
                ? win!.provisionalAlias!.trim()
                : widget.windowNumber);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Fehler beim Laden der Mängel: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Colors.purple;
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.amber.shade800;
      case 'low':
      default:
        return Colors.blue;
    }
  }

  String _getSeverityDisplay(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return 'Kritisch';
      case 'high':
        return 'Hoch';
      case 'medium':
        return 'Mittel';
      case 'low':
      default:
        return 'Niedrig';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return Colors.green;
      case 'in_progress':
      case 'in progress':
        return Colors.orange;
      case 'open':
      default:
        return Colors.red;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return Icons.check_circle;
      case 'in_progress':
      case 'in progress':
        return Icons.pending;
      case 'open':
      default:
        return Icons.warning;
    }
  }

  String _getStatusDisplay(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return 'Gelöst';
      case 'in_progress':
      case 'in progress':
        return 'In Bearbeitung';
      case 'open':
      default:
        return 'Offen';
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
              content: Text(
                  'Das Bild ist zu groß. Maximale Größe ist 60 MB (Aktuell: ${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB).'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }

      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Auswählen des Fotos: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _addPhotoToError(
      InspectionWindowError error, ImageSource source) async {
    try {
      final base64Str = await _pickImageAsBase64(source);
      if (base64Str == null) return;

      List<String> currentPhotos =
          error.attachments.split(',').where((s) => s.isNotEmpty).toList();
      currentPhotos.add(base64Str);
      final newAttachments = currentPhotos.join(',');

      final updatedError = error.copyWith(attachments: newAttachments);
      if (widget.isManagerMode) {
        await DatabaseService.updateInspectionWindowError(updatedError);
      } else {
        await LocalDatabaseService.updateInspectionWindowError(updatedError);
      }

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto erfolgreich hinzugefügt.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Hinzufügen des Fotos: $e')),
        );
      }
    }
  }

  Future<void> _deletePhotoFromError(
      InspectionWindowError error, int photoIndex) async {
    try {
      List<String> currentPhotos =
          error.attachments.split(',').where((s) => s.isNotEmpty).toList();
      if (photoIndex >= 0 && photoIndex < currentPhotos.length) {
        currentPhotos.removeAt(photoIndex);
      }
      final newAttachments = currentPhotos.join(',');

      final updatedError = error.copyWith(attachments: newAttachments);
      if (widget.isManagerMode) {
        await DatabaseService.updateInspectionWindowError(updatedError);
      } else {
        await LocalDatabaseService.updateInspectionWindowError(updatedError);
      }

      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Löschen des Fotos: $e')),
        );
      }
    }
  }

  void _showAddPhotoSourceSheet(InspectionWindowError error) {
    if (widget.isReadOnly) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Foto mit Kamera aufnehmen'),
              onTap: () {
                Navigator.pop(ctx);
                _addPhotoToError(error, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Foto aus Galerie wählen'),
              onTap: () {
                Navigator.pop(ctx);
                _addPhotoToError(error, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _viewPhotoFullScreen(List<String> photos, int index,
      {String? errorCode}) {
    final photoNames = photos.asMap().entries.map((entry) {
      return PhotoNameHelper.formatPhotoName(
        doorAlias: _windowAlias.isNotEmpty ? _windowAlias : widget.windowNumber,
        errorCode: errorCode ?? '',
        photoIndex: entry.key + 1,
      );
    }).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenPhotoGalleryViewer(
          photos: photos,
          initialIndex: index,
          photoNames: photoNames,
        ),
      ),
    );
  }

  Widget _buildPhotoGallery(InspectionWindowError error) {
    final photos =
        error.attachments.split(',').where((s) => s.isNotEmpty).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fotonachweis:',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 70,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length + (widget.isReadOnly ? 0 : 1),
              itemBuilder: (context, index) {
                if (index == photos.length) {
                  return GestureDetector(
                    onTap: () => _showAddPhotoSourceSheet(error),
                    child: Container(
                      width: 60,
                      height: 60,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.grey.shade400,
                            style: BorderStyle.solid),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade50,
                      ),
                      child: Icon(Icons.add_a_photo,
                          color: Colors.grey.shade600, size: 24),
                    ),
                  );
                }

                final photoBase64 = photos[index];
                Uint8List? bytes;
                try {
                  bytes = base64Decode(photoBase64.contains('#')
                      ? photoBase64.split('#').sublist(1).join('#')
                      : photoBase64);
                } catch (_) {}

                final photoName = PhotoNameHelper.formatPhotoName(
                  doorAlias: _windowAlias.isNotEmpty
                      ? _windowAlias
                      : widget.windowNumber,
                  errorCode: error.errorCode,
                  photoIndex: index + 1,
                );

                return Stack(
                  children: [
                    Tooltip(
                      message: photoName,
                      child: GestureDetector(
                        onTap: () => _viewPhotoFullScreen(photos, index,
                            errorCode: error.errorCode),
                        child: Container(
                          width: 60,
                          height: 60,
                          margin: const EdgeInsets.only(
                              right: 8, top: 4, bottom: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: bytes != null
                                ? Image.memory(
                                    bytes,
                                    fit: BoxFit.cover,
                                    cacheWidth: 120,
                                  )
                                : Container(
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.broken_image,
                                        size: 20),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    if (!widget.isReadOnly)
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
                            child: const Icon(Icons.close,
                                size: 14, color: Colors.white),
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

  Future<void> _showAddErrorDialog() async {
    final notesController = TextEditingController();
    final descriptionController = TextEditingController();
    final customCategoryController = TextEditingController();
    final searchController = TextEditingController();
    final List<String> dialogPhotos = [];

    ErrorCatalog? selectedError;
    String? selectedCategory;
    bool isProvisional = false;
    String selectedSeverity = 'medium';
    int selectedQuantity = 1;

    // Extract unique categories from window catalog
    final Set<String> categorySet = {};
    for (final err in _catalog) {
      if (err.category.trim().isNotEmpty && err.category != 'Altdaten') {
        categorySet.add(err.category.trim());
      }
    }
    final List<String> categories = categorySet.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    String? selectedProvisionalCategory =
        categories.isNotEmpty ? categories.first : 'Fenster allgemein';
    bool isCustomProvisionalCategory = categories.isEmpty;

    String proposeNextCode(String category) {
      final allKnownCatalog = <ErrorCatalog>[
        ..._catalog,
        ..._errors.map((e) => ErrorCatalog(
              code: e.errorCode,
              description: e.notes,
              category: category,
              assetType: 'window',
            )),
      ];
      return CatalogIntegrityService.proposeNextCodeForCategory(
          category, allKnownCatalog);
    }

    ErrorCatalog? findCollision(String code) {
      final clean = code.trim().toLowerCase();
      if (clean.isEmpty) return null;
      final fromCatalog =
          CatalogIntegrityService.findCodeCollision(clean, _catalog);
      if (fromCatalog != null) return fromCatalog;
      final fromCurrent = _errors
          .where((e) => e.errorCode.trim().toLowerCase() == clean)
          .firstOrNull;
      if (fromCurrent != null) {
        return ErrorCatalog(
          code: fromCurrent.errorCode,
          description: fromCurrent.notes.isNotEmpty
              ? fromCurrent.notes
              : 'Bereits am aktuellen Fenster erfasst',
          category: 'Aktuelles Fenster',
          assetType: 'window',
        );
      }
      return null;
    }

    final codeController = TextEditingController(
        text: proposeNextCode(selectedProvisionalCategory ?? 'Fenster allgemein'));

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
          final filteredErrors = _catalog.where((error) {
            final matchesCategory = selectedCategory == null ||
                selectedCategory!.isEmpty ||
                error.category.toLowerCase() == selectedCategory!.toLowerCase();
            if (!matchesCategory) return false;

            if (query.isEmpty) return true;

            return error.code.toLowerCase().contains(query) ||
                error.category.toLowerCase().contains(query) ||
                error.description.toLowerCase().contains(query) ||
                error.recommendation.toLowerCase().contains(query);
          }).toList();

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.report_problem,
                    color:
                        isProvisional ? Colors.orange : Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(isProvisional
                    ? 'Provisorischen Mangel erfassen'
                    : 'Mangel hinzufügen'),
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
                    // Mode Toggle (ChoiceChip)
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
                              label: const Center(
                                  child: Text('Aus Katalog wählen')),
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
                              label: const Center(
                                  child: Text('Neuer / Provisorischer Mangel')),
                              selected: isProvisional,
                              onSelected: (selected) {
                                if (selected) {
                                  dialogSetState(() {
                                    isProvisional = true;
                                    final cat = isCustomProvisionalCategory
                                        ? customCategoryController.text.trim()
                                        : (selectedProvisionalCategory ??
                                            'Fenster allgemein');
                                    if (codeController.text.trim().isEmpty) {
                                      codeController.text = proposeNextCode(
                                          cat.isNotEmpty
                                              ? cat
                                              : 'Fenster allgemein');
                                    }
                                  });
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
                          color: Colors.blue.shade50.withValues(alpha: 0.5),
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
                                    const Icon(Icons.category,
                                        size: 18, color: Colors.blue),
                                    const SizedBox(width: 6),
                                    const Text(
                                      '1. Fehlerkategorie wählen:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                    if (selectedCategory != null &&
                                        selectedCategory!.isNotEmpty) ...[
                                      const Spacer(),
                                      TextButton(
                                        onPressed: () => dialogSetState(
                                            () => selectedCategory = null),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text(
                                            'Kategorie zurücksetzen',
                                            style: TextStyle(fontSize: 12)),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String?>(
                                  initialValue: selectedCategory,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                    hintText:
                                        'Alle Kategorien (${_catalog.length} Mängel)',
                                  ),
                                  items: [
                                    DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text(
                                        'Alle Kategorien (${_catalog.length} Mängel)',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    ...categories.map((cat) {
                                      final count = _catalog
                                          .where((e) =>
                                              e.category.toLowerCase() ==
                                              cat.toLowerCase())
                                          .length;
                                      return DropdownMenuItem<String?>(
                                        value: cat,
                                        child: Text('$cat ($count Mängel)'),
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
                                    const Icon(Icons.search,
                                        size: 18, color: Colors.blue),
                                    const SizedBox(width: 6),
                                    const Text(
                                      '2. Suche (nach Code, Kategorie oder Text):',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: searchController,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    labelText: 'Suchbegriff eingeben...',
                                    hintText:
                                        'z. B. 9.1, Dichtung, Griff, Beschlag, Raffstore...',
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
                                  onChanged: (_) => dialogSetState(() {}),
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
                              '${filteredErrors.length} Mängel gefunden',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                                fontSize: 13,
                              ),
                            ),
                            if (selectedCategory != null &&
                                selectedCategory!.isNotEmpty)
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

                        // Error List
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
                                      Icon(Icons.search_off,
                                          size: 48,
                                          color: Colors.grey.shade400),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Keine passenden Mängel gefunden',
                                        style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(6),
                                  itemCount: filteredErrors.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 4),
                                  itemBuilder: (context, index) {
                                    final err = filteredErrors[index];
                                    final isErrNotice = err.isNotice;
                                    return Card(
                                      margin: EdgeInsets.zero,
                                      elevation: 1,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        side: BorderSide(
                                            color: isErrNotice
                                                ? Colors.amber.shade200
                                                : Colors.grey.shade200),
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () {
                                          dialogSetState(() {
                                            selectedError = err;
                                            selectedSeverity =
                                                err.severity.isNotEmpty
                                                    ? err.severity
                                                    : (isErrNotice
                                                        ? 'low'
                                                        : 'medium');
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 8),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              CircleAvatar(
                                                radius: 16,
                                                backgroundColor:
                                                    isErrNotice
                                                        ? Colors.amber.shade100
                                                        : Colors.blue.shade100,
                                                child: Text(
                                                  err.code.isNotEmpty
                                                      ? err.code.split('.')[0]
                                                      : (isErrNotice ? 'H' : 'W'),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: isErrNotice
                                                        ? Colors.amber.shade900
                                                        : Colors.blue.shade900,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Text(
                                                          err.code,
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 13),
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                        if (isErrNotice) ...[
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(
                                                                horizontal: 6, vertical: 1),
                                                            decoration: BoxDecoration(
                                                              color: Colors.amber.shade100,
                                                              borderRadius: BorderRadius.circular(4),
                                                              border: Border.all(
                                                                  color: Colors.amber.shade400),
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
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 1),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: isErrNotice
                                                                ? Colors.amber.shade50
                                                                : Colors.blue.shade50,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                            border: Border.all(
                                                                color: isErrNotice
                                                                    ? Colors.amber.shade300
                                                                    : Colors.blue.shade200),
                                                          ),
                                                          child: Text(
                                                            err.category,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: isErrNotice
                                                                  ? Colors.amber.shade900
                                                                  : Colors.blue.shade800,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 6),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 1),
                                                          decoration:
                                                              BoxDecoration(
                                                            color:
                                                                _getSeverityColor(
                                                                        err.severity)
                                                                    .withValues(
                                                                        alpha:
                                                                            0.15),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                          ),
                                                          child: Text(
                                                            _getSeverityDisplay(
                                                                err.severity),
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color:
                                                                  _getSeverityColor(
                                                                      err.severity),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      err.description,
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              Colors.black87),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton(
                                                onPressed: () {
                                                  dialogSetState(() {
                                                    selectedError = err;
                                                    selectedSeverity =
                                                        err.severity.isNotEmpty
                                                            ? err.severity
                                                            : 'medium';
                                                  });
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  textStyle: const TextStyle(
                                                      fontSize: 11),
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
                        Builder(
                          builder: (context) {
                            final isSelNotice = selectedError!.isNotice;
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelNotice ? Colors.amber.shade50 : Colors.green.shade50,
                                border: Border.all(
                                    color: isSelNotice ? Colors.amber.shade400 : Colors.green.shade300,
                                    width: 1.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        isSelNotice ? Icons.info_outline : Icons.check_circle,
                                        color: isSelNotice ? Colors.amber.shade900 : Colors.green,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isSelNotice ? 'Ausgewählter Hinweis:' : 'Ausgewählter Mangel:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isSelNotice ? Colors.amber.shade900 : Colors.green.shade900,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const Spacer(),
                                      OutlinedButton.icon(
                                        onPressed: () => dialogSetState(
                                            () => selectedError = null),
                                        icon:
                                            const Icon(Icons.swap_horiz, size: 16),
                                        label: Text(isSelNotice ? 'Anderen Hinweis wählen' : 'Anderen Mangel wählen'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Row(
                                children: [
                                  Text(
                                    selectedError!.code,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isSelNotice) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.amber.shade400),
                                      ),
                                      child: Text(
                                        'Hinweis',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.amber.shade900,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isSelNotice ? Colors.amber.shade100 : Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      selectedError!.category,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: isSelNotice ? Colors.amber.shade900 : Colors.blue.shade900,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _getSeverityColor(selectedSeverity)
                                          .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _getSeverityDisplay(selectedSeverity),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            _getSeverityColor(selectedSeverity),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(selectedError!.description,
                                  style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        );
                      },
                    ),
                        const SizedBox(height: 16),

                        // Quantity & Severity Configuration
                        Row(
                          children: [
                            const Text('Anzahl / Menge: ',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                if (selectedQuantity > 1) {
                                  dialogSetState(() => selectedQuantity--);
                                }
                              },
                            ),
                            Text('$selectedQuantity',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () =>
                                  dialogSetState(() => selectedQuantity++),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 170,
                              child: DropdownButtonFormField<String>(
                                initialValue: selectedSeverity,
                                decoration: const InputDecoration(
                                  labelText: 'Schweregrad',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'low', child: Text('Niedrig')),
                                  DropdownMenuItem(
                                      value: 'medium', child: Text('Mittel')),
                                  DropdownMenuItem(
                                      value: 'high', child: Text('Hoch')),
                                  DropdownMenuItem(
                                      value: 'critical',
                                      child: Text('Kritisch')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    dialogSetState(
                                        () => selectedSeverity = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Notes section
                        TextField(
                          controller: notesController,
                          decoration: const InputDecoration(
                            labelText: 'Notizen zum Mangel',
                            hintText:
                                'Detaillierte Beobachtungen, Fundort, Bemerkungen...',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 14),

                        // Photos section in dialog
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Fotonachweis (${dialogPhotos.length} Fotos):',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final photo = await _pickImageAsBase64(
                                        ImageSource.camera);
                                    if (photo != null) {
                                      dialogSetState(
                                          () => dialogPhotos.add(photo));
                                    }
                                  },
                                  icon: const Icon(Icons.camera_alt, size: 16),
                                  label: const Text('Kamera'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final photo = await _pickImageAsBase64(
                                        ImageSource.gallery);
                                    if (photo != null) {
                                      dialogSetState(
                                          () => dialogPhotos.add(photo));
                                    }
                                  },
                                  icon:
                                      const Icon(Icons.photo_library, size: 16),
                                  label: const Text('Galerie'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (dialogPhotos.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 60,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: dialogPhotos.length,
                              itemBuilder: (ctx, idx) {
                                final pData = dialogPhotos[idx];
                                Uint8List? pBytes;
                                try {
                                  pBytes = base64Decode(pData);
                                } catch (_) {}
                                return Stack(
                                  children: [
                                    Container(
                                      width: 60,
                                      height: 60,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: pBytes != null
                                            ? Image.memory(pBytes,
                                                fit: BoxFit.cover)
                                            : const Icon(Icons.image),
                                      ),
                                    ),
                                    Positioned(
                                      top: 2,
                                      right: 10,
                                      child: GestureDetector(
                                        onTap: () => dialogSetState(
                                            () => dialogPhotos.removeAt(idx)),
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle),
                                          child: const Icon(Icons.close,
                                              size: 12, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ] else ...[
                      // Provisional / Custom Defect Mode
                      Card(
                        elevation: 0,
                        color: Colors.orange.shade50.withValues(alpha: 0.4),
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
                                  const Icon(Icons.edit_note,
                                      color: Colors.orange),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Neuen Mangel beschreiben',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade900),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Category Dropdown or Custom Category
                              Row(
                                children: [
                                  Expanded(
                                    child: isCustomProvisionalCategory
                                        ? TextFormField(
                                            controller:
                                                customCategoryController,
                                            decoration: const InputDecoration(
                                              labelText: 'Neue Kategorie *',
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                            onChanged: (val) {
                                              if (val.trim().isNotEmpty) {
                                                codeController.text =
                                                    proposeNextCode(val.trim());
                                                dialogSetState(() {});
                                              }
                                            },
                                          )
                                        : DropdownButtonFormField<String>(
                                            value: selectedProvisionalCategory,
                                            decoration: const InputDecoration(
                                              labelText: 'Kategorie',
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                            items: categories.map((cat) {
                                              return DropdownMenuItem(
                                                  value: cat, child: Text(cat));
                                            }).toList(),
                                            onChanged: (val) {
                                              if (val != null) {
                                                dialogSetState(() {
                                                  selectedProvisionalCategory =
                                                      val;
                                                  codeController.text =
                                                      proposeNextCode(val);
                                                });
                                              }
                                            },
                                          ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(isCustomProvisionalCategory
                                        ? Icons.list
                                        : Icons.add),
                                    tooltip: isCustomProvisionalCategory
                                        ? 'Vorhandene Kategorien wählen'
                                        : 'Neue Kategorie anlegen',
                                    onPressed: () {
                                      dialogSetState(() {
                                        isCustomProvisionalCategory =
                                            !isCustomProvisionalCategory;
                                        final cat = isCustomProvisionalCategory
                                            ? customCategoryController.text.trim()
                                            : (selectedProvisionalCategory ??
                                                'Fenster allgemein');
                                        codeController.text = proposeNextCode(
                                            cat.isNotEmpty
                                                ? cat
                                                : 'Fenster allgemein');
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Code & Recommendation Button
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: codeController,
                                      decoration: InputDecoration(
                                        labelText: 'Mängel-Code *',
                                        hintText: 'z. B. 9.16, 20.10...',
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                        suffixIcon: IconButton(
                                          tooltip:
                                              'Nächsten freien Code berechnen',
                                          icon: const Icon(Icons.auto_awesome,
                                              color: Colors.blue),
                                          onPressed: () {
                                            final cat = isCustomProvisionalCategory
                                                ? customCategoryController.text
                                                    .trim()
                                                : (selectedProvisionalCategory ??
                                                    'Fenster allgemein');
                                            codeController.text =
                                                proposeNextCode(cat.isNotEmpty
                                                    ? cat
                                                    : 'Fenster allgemein');
                                            dialogSetState(() {});
                                          },
                                        ),
                                      ),
                                      onChanged: (_) => dialogSetState(() {}),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 12),
                                    ),
                                    onPressed: () {
                                      final cat = isCustomProvisionalCategory
                                          ? customCategoryController.text.trim()
                                          : (selectedProvisionalCategory ??
                                              'Fenster allgemein');
                                      codeController.text = proposeNextCode(
                                          cat.isNotEmpty
                                              ? cat
                                              : 'Fenster allgemein');
                                      dialogSetState(() {});
                                    },
                                    icon: const Icon(Icons.tag, size: 16),
                                    label: const Text('Code vorschlagen',
                                        style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),

                              // Live Code Collision Warning
                              Builder(builder: (context) {
                                final code = codeController.text.trim();
                                final collision = findCollision(code);
                                if (collision != null) {
                                  return Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: Colors.red.shade300),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.error_outline,
                                            size: 18, color: Colors.red),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Code "$code" ist bereits an "${collision.description}" vergeben!',
                                            style: TextStyle(
                                                color: Colors.red.shade900,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            final cat = isCustomProvisionalCategory
                                                ? customCategoryController.text
                                                    .trim()
                                                : (selectedProvisionalCategory ??
                                                    'Fenster allgemein');
                                            codeController.text =
                                                proposeNextCode(cat.isNotEmpty
                                                    ? cat
                                                    : 'Fenster allgemein');
                                            dialogSetState(() {});
                                          },
                                          child: const Text(
                                              'Freien Code wählen',
                                              style: TextStyle(fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              }),
                              const SizedBox(height: 12),

                              // Severity & Quantity
                              Row(
                                children: [
                                  const Text('Anzahl: ',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon:
                                        const Icon(Icons.remove_circle_outline),
                                    onPressed: () {
                                      if (selectedQuantity > 1) {
                                        dialogSetState(
                                            () => selectedQuantity--);
                                      }
                                    },
                                  ),
                                  Text('$selectedQuantity',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () => dialogSetState(
                                        () => selectedQuantity++),
                                  ),
                                  const Spacer(),
                                  SizedBox(
                                    width: 140,
                                    child: DropdownButtonFormField<String>(
                                      value: selectedSeverity,
                                      decoration: const InputDecoration(
                                        labelText: 'Schweregrad',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'low',
                                            child: Text('Niedrig')),
                                        DropdownMenuItem(
                                            value: 'medium',
                                            child: Text('Mittel')),
                                        DropdownMenuItem(
                                            value: 'high', child: Text('Hoch')),
                                        DropdownMenuItem(
                                            value: 'critical',
                                            child: Text('Kritisch')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          dialogSetState(
                                              () => selectedSeverity = val);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Description
                              TextFormField(
                                controller: descriptionController,
                                decoration: const InputDecoration(
                                  labelText: 'Mängel-Beschreibung *',
                                  hintText:
                                      'Genaue Beschreibung des Schadens / Problems...',
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 2,
                              ),
                              const SizedBox(height: 12),

                              // Quantity & Notes
                              Row(
                                children: [
                                  const Text('Anzahl: ',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon:
                                        const Icon(Icons.remove_circle_outline),
                                    onPressed: () {
                                      if (selectedQuantity > 1) {
                                        dialogSetState(
                                            () => selectedQuantity--);
                                      }
                                    },
                                  ),
                                  Text('$selectedQuantity',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () => dialogSetState(
                                        () => selectedQuantity++),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: notesController,
                                decoration: const InputDecoration(
                                  labelText: 'Zusatznotiz / Details',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Photos
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Fotonachweis (${dialogPhotos.length} Fotos):',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                  Row(
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          final photo =
                                              await _pickImageAsBase64(
                                                  ImageSource.camera);
                                          if (photo != null) {
                                            dialogSetState(
                                                () => dialogPhotos.add(photo));
                                          }
                                        },
                                        icon: const Icon(Icons.camera_alt,
                                            size: 16),
                                        label: const Text('Kamera'),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          final photo =
                                              await _pickImageAsBase64(
                                                  ImageSource.gallery);
                                          if (photo != null) {
                                            dialogSetState(
                                                () => dialogPhotos.add(photo));
                                          }
                                        },
                                        icon: const Icon(Icons.photo_library,
                                            size: 16),
                                        label: const Text('Galerie'),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (dialogPhotos.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 60,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: dialogPhotos.length,
                                    itemBuilder: (ctx, idx) {
                                      final pData = dialogPhotos[idx];
                                      Uint8List? pBytes;
                                      try {
                                        pBytes = base64Decode(pData);
                                      } catch (_) {}
                                      return Stack(
                                        children: [
                                          Container(
                                            width: 60,
                                            height: 60,
                                            margin:
                                                const EdgeInsets.only(right: 8),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: Colors.grey.shade300),
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: pBytes != null
                                                  ? Image.memory(pBytes,
                                                      fit: BoxFit.cover)
                                                  : const Icon(Icons.image),
                                            ),
                                          ),
                                          Positioned(
                                            top: 2,
                                            right: 10,
                                            child: GestureDetector(
                                              onTap: () => dialogSetState(() =>
                                                  dialogPhotos.removeAt(idx)),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(2),
                                                decoration: const BoxDecoration(
                                                    color: Colors.red,
                                                    shape: BoxShape.circle),
                                                child: const Icon(Icons.close,
                                                    size: 12,
                                                    color: Colors.white),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
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
                ElevatedButton(
                  onPressed: () async {
                    if (_inspectionWindowId == null) return;
                    Navigator.pop(context);

                    final newError = InspectionWindowError(
                      inspectionWindowId: _inspectionWindowId!,
                      errorId: selectedError!.errorId,
                      errorCode: selectedError!.code,
                      quantity: selectedQuantity,
                      severity: selectedSeverity,
                      notes: notesController.text.trim(),
                      resolutionStatus: 'Open',
                      attachments: dialogPhotos.join(','),
                    );

                    if (widget.isManagerMode) {
                      await DatabaseService.insertInspectionWindowError(
                          newError);
                    } else {
                      await LocalDatabaseService.insertInspectionWindowError(
                          newError);
                      await _markWindowAsInspectedIfInspector();
                    }

                    await _loadData();
                  },
                  child: Text(selectedError != null && selectedError!.isNotice ? 'Hinweis hinzufügen' : 'Mangel hinzufügen'),
                ),
              if (isProvisional) ...[
                OutlinedButton(
                  onPressed: () async {
                    final desc = descriptionController.text.trim();
                    if (desc.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Bitte geben Sie eine Mängel-Beschreibung ein.')),
                      );
                      return;
                    }
                    final finalCat = isCustomProvisionalCategory
                        ? (customCategoryController.text.trim().isNotEmpty
                            ? customCategoryController.text.trim()
                            : 'Fenster allgemein')
                        : (selectedProvisionalCategory ?? 'Fenster allgemein');

                    final code = codeController.text.trim().isNotEmpty
                        ? codeController.text.trim()
                        : proposeNextCode(finalCat);

                    if (_inspectionWindowId == null) return;
                    Navigator.pop(context);

                    final newError = InspectionWindowError(
                      inspectionWindowId: _inspectionWindowId!,
                      errorId: null,
                      errorCode: code,
                      quantity: selectedQuantity,
                      severity: selectedSeverity,
                      notes: [
                        desc,
                        if (notesController.text.trim().isNotEmpty)
                          notesController.text.trim()
                      ].join(' | '),
                      resolutionStatus: 'Open',
                      attachments: dialogPhotos.join(','),
                    );

                    if (widget.isManagerMode) {
                      await DatabaseService.insertInspectionWindowError(
                          newError);
                    } else {
                      await LocalDatabaseService.insertInspectionWindowError(
                          newError);
                      await _markWindowAsInspectedIfInspector();
                    }

                    await _loadData();
                  },
                  child: const Text('Provisorisch hinzufügen'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final desc = descriptionController.text.trim();
                    if (desc.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Bitte geben Sie eine Mängel-Beschreibung ein.')),
                      );
                      return;
                    }
                    final finalCat = isCustomProvisionalCategory
                        ? (customCategoryController.text.trim().isNotEmpty
                            ? customCategoryController.text.trim()
                            : 'Fenster allgemein')
                        : (selectedProvisionalCategory ?? 'Fenster allgemein');

                    final code = codeController.text.trim().isNotEmpty
                        ? codeController.text.trim()
                        : proposeNextCode(finalCat);

                    final collision = findCollision(code);
                    if (collision != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Code "$code" ist bereits an "${collision.description}" vergeben. Bitte wählen Sie einen freien Code.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    if (_inspectionWindowId == null) return;
                    Navigator.pop(context);

                    final newCatItem = ErrorCatalog(
                      code: code,
                      description: desc,
                      category: finalCat,
                      severity: selectedSeverity,
                      assetType: 'window',
                    );

                    if (widget.isManagerMode) {
                      await DatabaseService.insertErrorCatalog(newCatItem);
                    } else {
                      await LocalDatabaseService.insertErrorCatalog(newCatItem);
                    }

                    final newError = InspectionWindowError(
                      inspectionWindowId: _inspectionWindowId!,
                      errorId: null,
                      errorCode: code,
                      quantity: selectedQuantity,
                      severity: selectedSeverity,
                      notes: notesController.text.trim(),
                      resolutionStatus: 'Open',
                      attachments: dialogPhotos.join(','),
                    );

                    if (widget.isManagerMode) {
                      await DatabaseService.insertInspectionWindowError(
                          newError);
                    } else {
                      await LocalDatabaseService.insertInspectionWindowError(
                          newError);
                      await _markWindowAsInspectedIfInspector();
                    }

                    await _loadData();
                  },
                  child: const Text('In Katalog & hinzufügen'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditDialog(InspectionWindowError error) async {
    final catalogMatch =
        _catalog.firstWhereOrNull((c) => c.code == error.errorCode);
    final notesController = TextEditingController(text: error.notes);
    String status = error.resolutionStatus;
    String severity = error.severity;
    int quantity = error.quantity;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEditState) {
          return AlertDialog(
            title: const Text('Mangel bearbeiten'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mängel-Code: ${error.errorCode}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      catalogMatch?.description ?? error.notes,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      value: status,
                      items: const [
                        DropdownMenuItem(value: 'Open', child: Text('Offen')),
                        DropdownMenuItem(
                            value: 'In Progress', child: Text('In Bearbeitung')),
                        DropdownMenuItem(
                            value: 'Resolved', child: Text('Gelöst')),
                      ],
                      onChanged: (val) {
                        if (val != null) setEditState(() => status = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Anzahl: ',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            if (quantity > 1) {
                              setEditState(() => quantity--);
                            }
                          },
                        ),
                        Text('$quantity',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setEditState(() => quantity++),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: 140,
                          child: DropdownButtonFormField<String>(
                            value: severity,
                            decoration: const InputDecoration(
                              labelText: 'Schweregrad',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'low', child: Text('Niedrig')),
                              DropdownMenuItem(
                                  value: 'medium', child: Text('Mittel')),
                              DropdownMenuItem(
                                  value: 'high', child: Text('Hoch')),
                              DropdownMenuItem(
                                  value: 'critical', child: Text('Kritisch')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setEditState(() => severity = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notizen',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Abbrechen'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final updated = error.copyWith(
                    resolutionStatus: status,
                    severity: severity,
                    quantity: quantity,
                    notes: notesController.text.trim(),
                  );
                  if (widget.isManagerMode) {
                    await DatabaseService.updateInspectionWindowError(updated);
                  } else {
                    await LocalDatabaseService.updateInspectionWindowError(
                        updated);
                    await _markWindowAsInspectedIfInspector();
                  }
                  await _loadData();
                },
                child: const Text('Speichern'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _markWindowAsInspectedIfInspector() async {
    if (!widget.isManagerMode) {
      await LocalDatabaseService.updateInspectionWindowStatus(
        inspectionId: widget.inspectionId,
        windowId: widget.windowId,
        status: 'Inspected',
      );
    }
  }

  bool _isErrorNotice(InspectionWindowError err, [ErrorCatalog? catalog]) {
    final cat = catalog ??
        _catalog.firstWhereOrNull((c) =>
            (err.errorId != null && err.errorId! > 0 && c.errorId == err.errorId) ||
            (err.errorCode.isNotEmpty && c.code == err.errorCode));
    return err.isNotice(cat);
  }

  void _showErrorDetails(InspectionWindowError error) async {
    // 1. Try finding from already loaded catalog items in memory
    ErrorCatalog? currentCatalog = _catalog
        .where(
          (e) =>
              (error.errorId != null &&
                  error.errorId! > 0 &&
                  e.errorId == error.errorId) ||
              (error.errorCode.isNotEmpty && e.code == error.errorCode),
        )
        .firstOrNull;

    // 2. If not found in memory, query the database
    if (currentCatalog == null) {
      if (widget.isManagerMode) {
        if (error.errorId != null && error.errorId! > 0) {
          currentCatalog =
              await DatabaseService.getErrorCatalogItemById(error.errorId!);
        }
        if (currentCatalog == null && error.errorCode.isNotEmpty) {
          final results =
              await DatabaseService.searchErrorCatalog(error.errorCode);
          currentCatalog =
              results.where((e) => e.code == error.errorCode).firstOrNull ??
                  results.firstOrNull;
        }
      } else {
        if (error.errorId != null && error.errorId! > 0) {
          currentCatalog = await LocalDatabaseService.getErrorCatalogItemById(
              error.errorId!);
        }
        if (currentCatalog == null && error.errorCode.isNotEmpty) {
          final results =
              await LocalDatabaseService.searchErrorCatalog(error.errorCode);
          currentCatalog =
              results.where((e) => e.code == error.errorCode).firstOrNull ??
                  results.firstOrNull;
        }
      }
    }

    final isNotice = _isErrorNotice(error, currentCatalog);

    final ErrorCatalog catalogDetails = currentCatalog ??
        ErrorCatalog(
          code: error.errorCode.isNotEmpty ? error.errorCode : 'Unbekannt',
          description: error.notes.isNotEmpty
              ? error.notes
              : 'Fehler nicht im Katalog gefunden',
          category: isNotice ? 'Hinweis' : 'Unbekannt',
          assetType: 'window',
        );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isNotice ? Icons.info_outline : Icons.warning_amber_rounded,
              color: isNotice ? Colors.amber.shade800 : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(isNotice ? 'Hinweis-Details' : 'Mangel-Details'),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Code: ${catalogDetails.code}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(width: 8),
                    if (isNotice)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
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
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Beschreibung: ${catalogDetails.description.isNotEmpty ? catalogDetails.description : (error.notes.isNotEmpty ? error.notes : 'Keine Beschreibung')}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text('Kategorie: ${catalogDetails.category}'),
                const SizedBox(height: 8),
                Text('Schweregrad: ${_getSeverityDisplay(error.severity)}'),
                const SizedBox(height: 8),
                Text('Status: ${_getStatusDisplay(error.resolutionStatus)}'),
                if (error.quantity > 1) ...[
                  const SizedBox(height: 8),
                  Text('Anzahl: ${error.quantity}'),
                ],
                if (catalogDetails.recommendation.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Empfehlung: ${catalogDetails.recommendation}'),
                ],
                if (catalogDetails.normReference.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Normreferenz: ${catalogDetails.normReference}'),
                ],
                if (error.notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Notizen: ${error.notes}',
                      style: const TextStyle(fontStyle: FontStyle.italic)),
                ],
                _buildPhotoGallery(error),
              ],
            ),
          ),
        ),
        actions: [
          if (!widget.isReadOnly) ...[
            if (error.resolutionStatus.toLowerCase() != 'resolved') ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Als gelöst markieren'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final updatedError =
                      error.copyWith(resolutionStatus: 'Resolved');
                  if (widget.isManagerMode) {
                    await DatabaseService.updateInspectionWindowError(
                        updatedError);
                  } else {
                    await LocalDatabaseService.updateInspectionWindowError(
                        updatedError);
                    await _markWindowAsInspectedIfInspector();
                  }
                  if (mounted) {
                    Navigator.pop(context);
                    await _loadData();
                  }
                },
              ),
            ] else ...[
              TextButton.icon(
                icon: const Icon(Icons.replay),
                label: const Text('Als offen markieren'),
                onPressed: () async {
                  final updatedError =
                      error.copyWith(resolutionStatus: 'Open');
                  if (widget.isManagerMode) {
                    await DatabaseService.updateInspectionWindowError(
                        updatedError);
                  } else {
                    await LocalDatabaseService.updateInspectionWindowError(
                        updatedError);
                    await _markWindowAsInspectedIfInspector();
                  }
                  if (mounted) {
                    Navigator.pop(context);
                    await _loadData();
                  }
                },
              ),
            ],
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteError(InspectionWindowError error) async {
    if (error.id == null) return;
    final isNotice = _isErrorNotice(error);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isNotice ? 'Hinweis löschen' : 'Mangel löschen'),
        content: Text(
            'Möchten Sie den Eintrag "${error.errorCode}" wirklich entfernen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trotzdem löschen (Fehleingabe)'),
          ),
          if (error.resolutionStatus.toLowerCase() != 'resolved' &&
              !widget.isReadOnly)
            ElevatedButton.icon(
              onPressed: () async {
                final updatedError =
                    error.copyWith(resolutionStatus: 'Resolved');
                if (widget.isManagerMode) {
                  await DatabaseService.updateInspectionWindowError(
                      updatedError);
                } else {
                  await LocalDatabaseService.updateInspectionWindowError(
                      updatedError);
                  await _markWindowAsInspectedIfInspector();
                }
                if (mounted) {
                  Navigator.pop(ctx, false);
                  await _loadData();
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

    if (confirm == true) {
      if (widget.isManagerMode) {
        await DatabaseService.deleteInspectionWindowError(error.id!);
      } else {
        await LocalDatabaseService.deleteInspectionWindowError(error.id!);
        await _markWindowAsInspectedIfInspector();
      }
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mängel - Fenster ${widget.windowNumber}'),
        actions: [
          if (!widget.isReadOnly)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Mangel hinzufügen',
              onPressed: _showAddErrorDialog,
            ),
          MasterPortalHomeButton(isManagerMode: widget.isManagerMode),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errors.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 64, color: Colors.green),
                      const SizedBox(height: 16),
                      Text(
                        'Keine Mängel für Fenster ${widget.windowNumber} erfasst.',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text('Das Fenster ist in mangelfreiem Zustand.'),
                      const SizedBox(height: 20),
                      if (!widget.isReadOnly)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Mangel hinzufügen'),
                          onPressed: _showAddErrorDialog,
                        ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _errors.length,
                  itemBuilder: (context, index) {
                    final err = _errors[index];
                    final catalogMatch = _catalog.firstWhereOrNull((c) =>
                        (err.errorId != null && err.errorId! > 0 && c.errorId == err.errorId) ||
                        (err.errorCode.isNotEmpty && c.code == err.errorCode));
                    final isNotice = _isErrorNotice(err, catalogMatch);
                    final isResolved =
                        err.resolutionStatus.toLowerCase() == 'resolved';
                    final desc = catalogMatch?.description ??
                        (err.notes.isNotEmpty
                            ? err.notes
                            : 'Mangel ${err.errorCode}');

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: isNotice
                            ? BorderSide(
                                color: Colors.amber.shade300, width: 1.2)
                            : BorderSide(color: Colors.grey.shade200),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _showErrorDetails(err),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: isNotice
                                            ? (isResolved
                                                ? Colors.green
                                                : Colors.amber.shade700)
                                            : (isResolved
                                                ? Colors.green
                                                : _getStatusColor(
                                                    err.resolutionStatus)),
                                        child: Icon(
                                          isNotice
                                              ? (isResolved
                                                  ? Icons.check_circle
                                                  : Icons.info_outline)
                                              : (isResolved
                                                  ? Icons.check_circle
                                                  : _getStatusIcon(
                                                      err.resolutionStatus)),
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (isNotice) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade50,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: Colors.amber.shade400),
                                          ),
                                          child: Text(
                                            'Hinweis',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isNotice
                                              ? Colors.amber.shade50
                                              : Colors.blue.shade50,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: isNotice
                                                ? Colors.amber.shade300
                                                : Colors.blue.shade200,
                                          ),
                                        ),
                                        child: Text(
                                          err.errorCode,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isNotice
                                                ? Colors.amber.shade900
                                                : Colors.blue.shade900,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _getSeverityColor(err.severity)
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: _getSeverityColor(
                                                  err.severity)),
                                        ),
                                        child: Text(
                                          _getSeverityDisplay(err.severity),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: _getSeverityColor(
                                                err.severity),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: widget.isReadOnly
                                            ? null
                                            : () async {
                                                final nextStatus = isResolved
                                                    ? 'Open'
                                                    : 'Resolved';
                                                final updated = err.copyWith(
                                                    resolutionStatus:
                                                        nextStatus);
                                                if (widget.isManagerMode) {
                                                  await DatabaseService
                                                      .updateInspectionWindowError(
                                                          updated);
                                                } else {
                                                  await LocalDatabaseService
                                                      .updateInspectionWindowError(
                                                          updated);
                                                  await _markWindowAsInspectedIfInspector();
                                                }
                                                await _loadData();
                                              },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(
                                                    err.resolutionStatus)
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: _getStatusColor(
                                                    err.resolutionStatus)),
                                          ),
                                          child: Text(
                                            _getStatusDisplay(
                                                err.resolutionStatus),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: _getStatusColor(
                                                  err.resolutionStatus),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!widget.isReadOnly)
                                    PopupMenuButton<String>(
                                      onSelected: (val) async {
                                        if (val == 'toggle_status') {
                                          final nextStatus = isResolved
                                              ? 'Open'
                                              : 'Resolved';
                                          final updated = err.copyWith(
                                              resolutionStatus: nextStatus);
                                          if (widget.isManagerMode) {
                                            await DatabaseService
                                                .updateInspectionWindowError(
                                                    updated);
                                          } else {
                                            await LocalDatabaseService
                                                .updateInspectionWindowError(
                                                    updated);
                                            await _markWindowAsInspectedIfInspector();
                                          }
                                          await _loadData();
                                        } else if (val == 'edit') {
                                          _showEditDialog(err);
                                        } else if (val == 'delete') {
                                          _deleteError(err);
                                        }
                                      },
                                      itemBuilder: (ctx) => [
                                        PopupMenuItem(
                                          value: 'toggle_status',
                                          child: Row(
                                            children: [
                                              Icon(
                                                isResolved
                                                    ? Icons.replay
                                                    : Icons.check_circle,
                                                color: isResolved
                                                    ? Colors.orange
                                                    : Colors.green,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(isResolved
                                                  ? 'Als offen markieren'
                                                  : 'Als gelöst markieren'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit, size: 18),
                                              SizedBox(width: 8),
                                              Text('Bearbeiten'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete,
                                                  color: Colors.red, size: 18),
                                              SizedBox(width: 8),
                                              Text('Löschen',
                                                  style: TextStyle(
                                                      color: Colors.red)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                desc.isNotEmpty
                                    ? desc
                                    : 'Mangel ${err.errorCode}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              if (catalogMatch?.category != null &&
                                  catalogMatch!.category.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isNotice
                                        ? Colors.amber.shade50
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isNotice
                                        ? Border.all(
                                            color: Colors.amber.shade300)
                                        : null,
                                  ),
                                  child: Text(
                                    'Kategorie: ${catalogMatch.category}',
                                    style: TextStyle(
                                      color: isNotice
                                          ? Colors.amber.shade900
                                          : Colors.grey.shade800,
                                      fontWeight: isNotice
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.numbers,
                                      size: 16, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text('Anzahl: ${err.quantity}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                  if (err.notes.isNotEmpty) ...[
                                    const SizedBox(width: 16),
                                    const Icon(Icons.comment_outlined,
                                        size: 16, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        err.notes,
                                        style: const TextStyle(
                                            fontStyle: FontStyle.italic,
                                            fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              _buildPhotoGallery(err),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: (!widget.isReadOnly && _errors.isNotEmpty)
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Weiterer Mangel'),
              onPressed: _showAddErrorDialog,
            )
          : null,
    );
  }
}

extension _FirstWhereOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
  E? firstWhereOrNull(bool Function(E element) test) {
    for (E element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
