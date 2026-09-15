class InspectionYearUtils {
  /// Extracts the calendar year (e.g. 2026, 2025) from an inspection date string or DateTime.
  static int? extractYear(dynamic dateValue) {
    if (dateValue == null) return null;
    if (dateValue is DateTime) return dateValue.year;

    final dateStr = dateValue.toString().trim();
    if (dateStr.isEmpty) return null;

    final parsed = DateTime.tryParse(dateStr);
    if (parsed != null) return parsed.year;

    final match = RegExp(r'(\d{2})\.(\d{2})\.(\d{4})').firstMatch(dateStr);
    if (match != null) {
      return int.tryParse(match.group(3)!);
    }

    final yearMatch = RegExp(r'\b(20\d{2}|19\d{2})\b').firstMatch(dateStr);
    if (yearMatch != null) {
      return int.tryParse(yearMatch.group(1)!);
    }

    return null;
  }

  /// Determines whether an inspection's door properties and error management can be edited.
  /// - Managers (`isManagerMode == true`) can edit ALL inspections regardless of lock status or year.
  /// - Inspectors (`isManagerMode == false`) can edit when the inspection is UNLOCKED (`isLocked == 0` or `false`).
  /// - If `isLocked` is explicitly provided, it is the sole authority.
  /// - If `isLocked` is null (legacy fallback), previous calendar years are read-only.
  static bool isEditable({
    required bool isManagerMode,
    dynamic dateValue,
    dynamic isLocked,
  }) {
    if (isManagerMode) return true;

    // Explicit lock status takes priority over calendar year calculation
    if (isLocked != null) {
      return !(isLocked == true || isLocked == 1);
    }

    // Fallback ONLY if isLocked is null (legacy records)
    final year = extractYear(dateValue);
    if (year != null && year < DateTime.now().year) {
      return false;
    }

    return true;
  }

  /// Inspection metadata (e.g. clientName, objectAddress, date, etc.) is ALWAYS uneditable for inspectors.
  static bool isMetadataEditable({required bool isManagerMode}) {
    return isManagerMode;
  }

  /// Checks if an inspection is locked for inspector editing.
  /// Explicit isLocked value takes priority over calendar year.
  static bool isInspectionLocked(dynamic isLockedValue, [dynamic dateValue]) {
    if (isLockedValue != null) {
      return isLockedValue == true || isLockedValue == 1;
    }
    if (dateValue != null) {
      return isPreviousYear(dateValue);
    }
    return false;
  }

  /// Checks if an inspection is from a previous calendar year.
  static bool isPreviousYear(dynamic dateValue) {
    final year = extractYear(dateValue);
    if (year == null) return false;
    return year < DateTime.now().year;
  }
}
