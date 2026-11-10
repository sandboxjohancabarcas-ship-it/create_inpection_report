import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/services/craftnote_sync_service.dart';

void main() {
  testWidgets('Craftnote export feedback dialog renders matching Techniker role', (tester) async {
    final successResult = const CraftnoteSyncResult(
      success: true,
      message: 'Auftrag erfolgreich nach Craftnote exportiert.\n• Job-Paket abgelegt in: Wartungslisten',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Row(
                      children: [
                        Icon(
                          successResult.isQueuedOffline
                              ? Icons.cloud_queue
                              : (successResult.success ? Icons.cloud_done : Icons.error_outline),
                          color: successResult.isQueuedOffline
                              ? Colors.orange
                              : (successResult.success ? Colors.green : Colors.red),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          successResult.isQueuedOffline
                              ? 'Offline eingereiht'
                              : (successResult.success ? 'Export erfolgreich' : 'Export fehlgeschlagen'),
                        ),
                      ],
                    ),
                    content: SelectableText(successResult.message),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Show Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Export erfolgreich'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done), findsOneWidget);
    expect(find.textContaining('Auftrag erfolgreich nach Craftnote exportiert'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Export erfolgreich'), findsNothing);
  });
}
