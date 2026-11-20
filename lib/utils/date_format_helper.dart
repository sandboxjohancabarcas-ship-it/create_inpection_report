import 'package:intl/intl.dart';

class DateFormatHelper {
  /// Formats any date value (DateTime or String in ISO / other formats)
  /// to the standard German Day.Month.Year format (dd.MM.yyyy).
  static String formatDate(dynamic val) {
    if (val == null) return '';
    if (val is DateTime) {
      return DateFormat('dd.MM.yyyy').format(val);
    }
    final s = val.toString().trim();
    if (s.isEmpty || s == '?' || s == '-') return '';

    // If already in dd.MM.yyyy format
    if (RegExp(r'^\d{2}\.\d{2}\.\d{4}').hasMatch(s)) {
      return s;
    }

    // Handle YYYY-MM-DD or YYYY.MM.DD or YYYY/MM/DD
    final isoMatch = RegExp(r'^(\d{4})[-/.](\d{2})[-/.](\d{2})').firstMatch(s);
    if (isoMatch != null) {
      return '${isoMatch.group(3)}.${isoMatch.group(2)}.${isoMatch.group(1)}';
    }

    final parsed = DateTime.tryParse(s);
    if (parsed != null) {
      return DateFormat('dd.MM.yyyy').format(parsed);
    }

    return s;
  }
}
