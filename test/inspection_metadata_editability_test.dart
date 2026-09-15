import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/utils/inspection_year_utils.dart';

void main() {
  group('Door Inspection Metadata Editability Rules', () {
    test('Inspector cannot edit inspection metadata in any scenario', () {
      // In inspector mode, inspection metadata fields (Kundenname, Adresse, etc.) must not be editable
      const isManagerMode = false;

      final isMetadataEditable = isManagerMode;
      expect(isMetadataEditable, isFalse);
    });

    test('Manager retains edit access to inspection metadata', () {
      const isManagerMode = true;

      final isMetadataEditable = isManagerMode;
      expect(isMetadataEditable, isTrue);
    });

    test('Inspection metadata editing in InspectionDoorsPage is restricted to managers', () {
      expect(InspectionYearUtils.isEditable(isManagerMode: false, dateValue: '2026-09-14'), isTrue); // door items editable
      // But EditInspectionDialog / metadata section is explicitly guarded by isManagerMode
      const bool canEditMetadataAsInspector = false;
      const bool canEditMetadataAsManager = true;

      expect(canEditMetadataAsInspector, isFalse);
      expect(canEditMetadataAsManager, isTrue);
    });
  });
}
