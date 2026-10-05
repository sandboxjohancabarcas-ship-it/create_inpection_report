import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

class FullScreenPhotoGalleryViewer extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;
  final List<String>? photoNames;

  const FullScreenPhotoGalleryViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.photoNames,
  });

  @override
  State<FullScreenPhotoGalleryViewer> createState() => _FullScreenPhotoGalleryViewerState();
}

class _FullScreenPhotoGalleryViewerState extends State<FullScreenPhotoGalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;
  final FocusNode _focusNode = FocusNode();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.photos.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _currentPhotoName {
    if (widget.photoNames != null &&
        _currentIndex >= 0 &&
        _currentIndex < widget.photoNames!.length) {
      return widget.photoNames![_currentIndex];
    }
    return 'Foto_${_currentIndex + 1}.jpg';
  }

  void _previousPhoto() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextPhoto() {
    if (_currentIndex < widget.photos.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _saveCurrentPhoto() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final fileName = _currentPhotoName;
      final bytes = base64Decode(widget.photos[_currentIndex]);

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Foto speichern unter...',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );

      if (savePath != null) {
        final file = File(savePath);
        await file.writeAsBytes(bytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Foto erfolgreich gespeichert:\n$savePath'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Speichern: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _copyPhotoName() {
    final name = _currentPhotoName;
    Clipboard.setData(ClipboardData(text: name));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Dateiname kopiert: $name'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = widget.photos.length > 1;

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: KeyboardListener(
        focusNode: _focusNode..requestFocus(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _previousPhoto();
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _nextPhoto();
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.pop(context);
            }
          }
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // PageView for swipe & full-screen view
            PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  panEnabled: true,
                  boundaryMargin: const EdgeInsets.all(20),
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.memory(
                      base64Decode(widget.photos[index]),
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),

            // Top Header: Photo Name, Index Counter & Actions
            Positioned(
              top: 30,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    // Index Badge
                    if (hasMultiple)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_currentIndex + 1}/${widget.photos.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                    // Standardized Photo Filename
                    Expanded(
                      child: Tooltip(
                        message: 'Klicken zum Kopieren: $_currentPhotoName',
                        child: InkWell(
                          onTap: _copyPhotoName,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.image, size: 16, color: Colors.lightBlueAccent),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _currentPhotoName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.copy, size: 13, color: Colors.white70),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Download / Save Button
                    IconButton(
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.download, color: Colors.white, size: 22),
                      tooltip: 'Foto als Datei speichern',
                      onPressed: _saveCurrentPhoto,
                    ),

                    // Close Button
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 24),
                      tooltip: 'Schließen',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),

            // Left Navigation Arrow Button
            if (hasMultiple)
              Positioned(
                left: 16,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _currentIndex > 0 ? 1.0 : 0.3,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      iconSize: 32,
                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                      onPressed: _currentIndex > 0 ? _previousPhoto : null,
                    ),
                  ),
                ),
              ),

            // Right Navigation Arrow Button
            if (hasMultiple)
              Positioned(
                right: 16,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _currentIndex < widget.photos.length - 1 ? 1.0 : 0.3,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      iconSize: 32,
                      icon: const Icon(Icons.chevron_right, color: Colors.white),
                      onPressed: _currentIndex < widget.photos.length - 1 ? _nextPhoto : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
