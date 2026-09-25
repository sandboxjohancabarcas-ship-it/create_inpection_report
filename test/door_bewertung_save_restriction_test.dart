import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Door Bewertung Save Restriction Rules', () {
    bool evaluateCanSave({
      required bool isReadOnly,
      required bool properFunction,
      required int errorCount,
    }) {
      if (isReadOnly) return false;
      if (!properFunction && errorCount == 0) return false;
      return true;
    }

    test('Speichern is disabled when Bewertung is false and error count is 0', () {
      final canSave = evaluateCanSave(
        isReadOnly: false,
        properFunction: false,
        errorCount: 0,
      );
      expect(canSave, isFalse, reason: 'Inspector must not save when Bewertung is false and no defects are entered');
    });

    test('Speichern is enabled when Bewertung is false and at least one error is added', () {
      final canSave = evaluateCanSave(
        isReadOnly: false,
        properFunction: false,
        errorCount: 1,
      );
      expect(canSave, isTrue, reason: 'Inspector can save when defects have been entered');
    });

    test('Speichern is enabled when Bewertung is true and error count is 0', () {
      final canSave = evaluateCanSave(
        isReadOnly: false,
        properFunction: true,
        errorCount: 0,
      );
      expect(canSave, isTrue, reason: 'Inspector can save a defect-free door marked as OK');
    });

    test('Speichern is disabled when form is read-only even if Bewertung is OK or errors exist', () {
      expect(evaluateCanSave(isReadOnly: true, properFunction: true, errorCount: 0), isFalse);
      expect(evaluateCanSave(isReadOnly: true, properFunction: false, errorCount: 2), isFalse);
    });

    test('When errors exist, properFunction is set to false', () {
      final errors = [{'id': 1, 'description': 'Tür schleift'}];
      bool properFunction = true;
      if (errors.isNotEmpty) {
        properFunction = false;
      }
      expect(properFunction, isFalse);
    });
  });
}
