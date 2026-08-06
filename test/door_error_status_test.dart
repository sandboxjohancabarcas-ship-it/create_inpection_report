import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/models/models.dart';

void main() {
  group('DoorErrorSummary Tests', () {
    test('noErrors state when totalErrors is 0', () {
      const summary = DoorErrorSummary(totalErrors: 0, openErrors: 0, resolvedErrors: 0);
      expect(summary.state, equals(DoorErrorState.noErrors));
    });

    test('hasOpenErrors state when openErrors > 0', () {
      const summary = DoorErrorSummary(totalErrors: 2, openErrors: 1, resolvedErrors: 1);
      expect(summary.state, equals(DoorErrorState.hasOpenErrors));
    });

    test('allErrorsResolved state when totalErrors > 0 and openErrors == 0', () {
      const summary = DoorErrorSummary(totalErrors: 2, openErrors: 0, resolvedErrors: 2);
      expect(summary.state, equals(DoorErrorState.allErrorsResolved));
    });
  });
}
