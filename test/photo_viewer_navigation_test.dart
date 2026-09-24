import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/widgets/full_screen_photo_viewer.dart';

// Valid 1x1 PNG base64 strings
const samplePhoto1 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const samplePhoto2 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

void main() {
  testWidgets('Full-screen photo gallery viewer navigates with left and right arrows', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const FullScreenPhotoGalleryViewer(
                    photos: [samplePhoto1, samplePhoto2],
                    initialIndex: 0,
                  ),
                );
              },
              child: const Text('Open Viewer'),
            );
          },
        ),
      ),
    );

    // Tap to open viewer dialog
    await tester.tap(find.text('Open Viewer'));
    await tester.pumpAndSettle();

    // Verify index counter initially shows "1 / 2"
    expect(find.text('1 / 2'), findsOneWidget);

    // Verify left and right chevron icons exist
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    // Tap right arrow to move to next photo
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    // Counter updated to "2 / 2"
    expect(find.text('2 / 2'), findsOneWidget);

    // Tap left arrow to move back to first photo
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    // Counter updated to "1 / 2"
    expect(find.text('1 / 2'), findsOneWidget);

    // Close viewer by tapping close button
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Viewer is dismissed
    expect(find.byType(FullScreenPhotoGalleryViewer), findsNothing);
  });
}
