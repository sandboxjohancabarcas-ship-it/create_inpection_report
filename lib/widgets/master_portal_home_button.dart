import 'package:flutter/material.dart';

/// A quick-navigation button that instantly returns the manager to the root
/// Master-Portal view regardless of how deep they are in the navigation tree.
class MasterPortalHomeButton extends StatelessWidget {
  final Color? color;
  final String tooltip;

  const MasterPortalHomeButton({
    super.key,
    this.color,
    this.tooltip = 'Schnell-Navigation: Zum Master-Portal',
  });

  @override
  Widget build(BuildContext context) {
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
