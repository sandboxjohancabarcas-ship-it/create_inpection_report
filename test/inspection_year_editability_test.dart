import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/utils/inspection_year_utils.dart';

void main() {
  group('InspectionYearUtils - Date Parsing & Editability Tests', () {
    final currentYear = DateTime.now().year;
    final previousYear = currentYear - 1;
    final olderYear = currentYear - 2;

    test('extractYear correctly parses various date formats', () {
      expect(InspectionYearUtils.extractYear('$currentYear-05-15'), equals(currentYear));
      expect(InspectionYearUtils.extractYear('15.05.$previousYear'), equals(previousYear));
      expect(InspectionYearUtils.extractYear(DateTime(olderYear, 10, 20)), equals(olderYear));
      expect(InspectionYearUtils.extractYear('Project $previousYear Audit'), equals(previousYear));
      expect(InspectionYearUtils.extractYear(''), isNull);
      expect(InspectionYearUtils.extractYear(null), isNull);
    });

    test('isPreviousYear correctly detects previous calendar years', () {
      expect(InspectionYearUtils.isPreviousYear('$currentYear-01-01'), isFalse);
      expect(InspectionYearUtils.isPreviousYear('$previousYear-12-31'), isTrue);
      expect(InspectionYearUtils.isPreviousYear('$olderYear-06-15'), isTrue);
    });

    test('Inspector Mode: Only current year inspections are editable', () {
      // Current year -> Editable for inspector
      expect(
        InspectionYearUtils.isEditable(
          isManagerMode: false,
          dateValue: '$currentYear-09-14',
        ),
        isTrue,
      );

      // Previous year -> NOT editable for inspector (read-only)
      expect(
        InspectionYearUtils.isEditable(
          isManagerMode: false,
          dateValue: '$previousYear-11-20',
        ),
        isFalse,
      );

      // Older year -> NOT editable for inspector (read-only)
      expect(
        InspectionYearUtils.isEditable(
          isManagerMode: false,
          dateValue: '10.05.$olderYear',
        ),
        isFalse,
      );
    });

    test('Manager Mode: All inspections are editable regardless of year', () {
      // Manager can edit current year
      expect(
        InspectionYearUtils.isEditable(
          isManagerMode: true,
          dateValue: '$currentYear-09-14',
        ),
        isTrue,
      );

      // Manager can edit previous year
      expect(
        InspectionYearUtils.isEditable(
          isManagerMode: true,
          dateValue: '$previousYear-11-20',
        ),
        isTrue,
      );

      // Manager can edit older year
      expect(
        InspectionYearUtils.isEditable(
          isManagerMode: true,
          dateValue: '10.05.$olderYear',
        ),
        isTrue,
      );
    });
  });
}
