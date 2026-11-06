import 'dart:io';
import 'package:flutter/material.dart';

/// A quick-navigation button that instantly returns the manager to the root
/// Master-Portal view regardless of how deep they are in the navigation tree.
class MasterPortalHomeButton extends StatelessWidget {
  final Color? color;
  final String tooltip;
  final bool? isManagerMode;

  const MasterPortalHomeButton({
    super.key,
    this.color,
    this.tooltip = 'Schnell-Navigation: Zum Master-Portal',
    this.isManagerMode,
  });

  @override
  Widget build(BuildContext context) {
    // Hide completely on mobile (Technician app) or when explicitly not in manager mode
    if (Platform.isAndroid || Platform.isIOS) {
      return const SizedBox.shrink();
    }
    if (isManagerMode == false) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: Icon(
        Icons.home_work_outlined,
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
      tooltip: tooltip,
      onPressed: () {
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }
}
