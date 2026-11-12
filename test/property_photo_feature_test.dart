import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/utils/photo_name_helper.dart';
import 'package:wartungstool/widgets/editable_dropdown_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Property Photo Naming Tests', () {
    test('PhotoNameHelper formats photo names as alias_propertyname_indexNumber.jpg', () {
      final nameZulassung = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: 'Tuer-01',
        propertyName: 'Zulassungsnummer',
        indexNumber: 1,
      );
      expect(nameZulassung, equals('Tuer-01_Zulassungsnummer_1.jpg'));

      final nameHersteller = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: 'Tuer-01',
        propertyName: 'Hersteller',
        indexNumber: 1,
      );
      expect(nameHersteller, equals('Tuer-01_Hersteller_1.jpg'));

      final nameHerstellerNr = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: 'Tuer-01',
        propertyName: 'Herstellernummer',
        indexNumber: 1,
      );
      expect(nameHerstellerNr, equals('Tuer-01_Herstellernummer_1.jpg'));
    });

    test('PhotoNameHelper increments indexNumber sequentially', () {
      final p1 = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: 'D-100',
        propertyName: 'Zulassungsnummer',
        indexNumber: 1,
      );
      final p2 = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: 'D-100',
        propertyName: 'Zulassungsnummer',
        indexNumber: 2,
      );
      final p3 = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: 'D-100',
        propertyName: 'Zulassungsnummer',
        indexNumber: 3,
      );

      expect(p1, equals('D-100_Zulassungsnummer_1.jpg'));
      expect(p2, equals('D-100_Zulassungsnummer_2.jpg'));
      expect(p3, equals('D-100_Zulassungsnummer_3.jpg'));
    });

    test('PhotoNameHelper normalizes property names with spaces or typos', () {
      final pSpaced = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: 'D-100',
        propertyName: 'Hersteller nummer',
        indexNumber: 1,
      );
      expect(pSpaced, equals('D-100_Herstellernummer_1.jpg'));

      final pTypo = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: 'D-100',
        propertyName: 'Zulangsnummer',
        indexNumber: 1,
      );
      expect(pTypo, equals('D-100_Zulassungsnummer_1.jpg'));
    });

    test('PhotoNameHelper sanitizes invalid filesystem characters in doorAlias', () {
      final pSanitized = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: '001/EG:Tuer*01?special"name<1>2|3',
        propertyName: 'Zulassungsnummer',
        indexNumber: 1,
      );
      expect(pSanitized, equals('001-EG-Tuer-01-special-name-1-2-3_Zulassungsnummer_1.jpg'));
    });
  });

  group('EditableDropdownField Photo Feature Widget Tests', () {
    testWidgets('Renders camera icon when onTakePhoto is provided and invokes callback on tap', (WidgetTester tester) async {
      bool photoCallbackInvoked = false;
      String selectedValue = '?';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return EditableDropdownField(
                  label: 'Zulassungsnummer',
                  currentValue: selectedValue,
                  options: const ['?', 'Z-6.20-1234'],
                  onChanged: (val) => setState(() => selectedValue = val),
                  onTakePhoto: () {
                    photoCallbackInvoked = true;
                    setState(() => selectedValue = 'Foto');
                  },
                );
              },
            ),
          ),
        ),
      );

      // Verify the camera icon button is displayed
      final cameraIconFinder = find.byIcon(Icons.camera_alt);
      expect(cameraIconFinder, findsOneWidget);

      // Tap the camera button
      await tester.tap(cameraIconFinder);
      await tester.pumpAndSettle();

      // Verify callback was triggered and value changed to "Foto"
      expect(photoCallbackInvoked, isTrue);
      expect(selectedValue, equals('Foto'));

      // Verify the TextField now contains "Foto"
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);
      final TextField textField = tester.widget(textFieldFinder);
      expect(textField.controller?.text, equals('Foto'));
    });

    testWidgets('Does not render camera icon when onTakePhoto is null', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditableDropdownField(
              label: 'DoorType',
              currentValue: '?',
              options: const ['?', 'T30-1', 'T30-2'],
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.camera_alt), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    });

    testWidgets('Does not include "Foto" in dropdown popup menu options even if in options list', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditableDropdownField(
              label: 'Hersteller',
              currentValue: '?',
              options: const ['?', 'Hörmann', 'Schüco', 'Foto'],
              onChanged: (_) {},
              onTakePhoto: () {},
            ),
          ),
        ),
      );

      // Open the popup menu
      final dropdownArrowFinder = find.byIcon(Icons.arrow_drop_down);
      await tester.tap(dropdownArrowFinder);
      await tester.pumpAndSettle();

      // Verify "Foto" is NOT an option in the menu
      expect(find.text('Foto'), findsNothing);
    });

    test('formatDoorPhotoName constructs alias_Tuer_indexNumber.jpg correctly', () {
      final name1 = PhotoNameHelper.formatDoorPhotoName(
        doorAlias: '000100-1-EG-21.2',
        indexNumber: 1,
      );
      expect(name1, equals('000100-1-EG-21.2_Tuer_1.jpg'));

      final name2 = PhotoNameHelper.formatDoorPhotoName(
        doorAlias: '000100-1-EG-21.2',
        indexNumber: 2,
      );
      expect(name2, equals('000100-1-EG-21.2_Tuer_2.jpg'));
    });
  });
}
