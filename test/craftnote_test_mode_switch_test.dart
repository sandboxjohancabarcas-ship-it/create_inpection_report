import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/services/craftnote_credentials_service.dart';
import 'package:wartungstool/widgets/craftnote_test_mode_switch.dart';

void main() {
  setUp(() {
    CraftnoteCredentialsService.setTestMode(true);
  });

  testWidgets('CraftnoteTestModeSwitch toggles test mode', (tester) async {
    bool? callbackValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CraftnoteTestModeSwitch(
            compact: true,
            onChanged: (val) => callbackValue = val,
          ),
        ),
      ),
    );

    expect(find.text('Test (Sandbox)'), findsOneWidget);
    expect(find.byIcon(Icons.shield), findsOneWidget);
    expect(CraftnoteCredentialsService.isTestMode, isTrue);

    // Tap to toggle
    await tester.tap(find.byType(CraftnoteTestModeSwitch));
    await tester.pumpAndSettle();

    expect(CraftnoteCredentialsService.isTestMode, isFalse);
    expect(callbackValue, isFalse);
    expect(find.text('Live (Produktiv)'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    // Tap again to switch back
    await tester.tap(find.byType(CraftnoteTestModeSwitch));
    await tester.pumpAndSettle();

    expect(CraftnoteCredentialsService.isTestMode, isTrue);
    expect(callbackValue, isTrue);
    expect(find.text('Test (Sandbox)'), findsOneWidget);
  });
}

