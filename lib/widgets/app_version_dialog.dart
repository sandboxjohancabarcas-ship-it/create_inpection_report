import 'package:flutter/material.dart';
import '../services/app_version_service.dart';

class AppVersionDialog extends StatelessWidget {
  final bool isManager;

  const AppVersionDialog({
    super.key,
    this.isManager = false,
  });

  static Future<void> show(BuildContext context, {bool isManager = false}) {
    return showDialog(
      context: context,
      builder: (context) => AppVersionDialog(isManager: isManager),
    );
  }

  @override
  Widget build(BuildContext context) {
    final platformName = AppVersionService.getPlatformName(isManager: isManager);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            isManager ? Icons.desktop_windows : Icons.phone_android,
            color: Theme.of(context).colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 12),
          const Text('App-Informationen'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WartungsTool - Türinspektion',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                _buildInfoRow('Anwendung:', isManager ? 'Manager-Portal ($platformName)' : 'Techniker-App ($platformName)'),
                const Divider(height: 16),
                _buildInfoRow('Plattform-Build:', '$platformName Version'),
                const SizedBox(height: 6),
                _buildInfoRow('Version:', 'v${AppVersionService.fullVersion}'),
                const SizedBox(height: 6),
                _buildInfoRow('Build-Datum:', AppVersionService.buildDate),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
      ],
    );
  }
}
