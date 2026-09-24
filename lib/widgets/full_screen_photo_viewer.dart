import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FullScreenPhotoGalleryViewer extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;

  const FullScreenPhotoGalleryViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<FullScreenPhotoGalleryViewer> createState() => _FullScreenPhotoGalleryViewerState();
}

class _FullScreenPhotoGalleryViewerState extends State<FullScreenPhotoGalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;
  final FocusNode _focusNode = FocusNode();

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

            // Top Header: Index Counter & Close Button
            Positioned(
              top: 40,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (hasMultiple)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / ${widget.photos.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
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
