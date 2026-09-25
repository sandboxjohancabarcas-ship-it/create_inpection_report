import 'dart:math';
import '../models/error_catalog.dart';

class SimilarCatalogMatch {
  final ErrorCatalog existing;
  final double similarity;
  final String matchedDescription;

  SimilarCatalogMatch({
    required this.existing,
    required this.similarity,
    required this.matchedDescription,
  });

  int get similarityPercentage => (similarity * 100).round();
}

class CatalogIntegrityService {
  /// Proposes the next available error code for a given category.
  /// E.g., for Category 'Feststellanlagen (FSA)' with existing '11.1'..'11.19', it proposes '11.20'.
  static String proposeNextCodeForCategory(
    String category,
    List<ErrorCatalog> existingCatalog, {
    String? incomingCode,
  }) {
    final officialCatalog = existingCatalog.where(
      (e) => e.category != 'Altdaten' && !e.code.toUpperCase().startsWith('ALT-'),
    ).toList();

    // 1. Determine prefix (e.g. '11.', '0.', '1.', etc.)
    String? prefix;

    // A. Check existing catalog entries in this category
    final itemsInCat = officialCatalog.where(
      (e) => e.category.trim().toLowerCase() == category.trim().toLowerCase(),
    ).toList();

    final prefixCounts = <String, int>{};
    for (final item in itemsInCat) {
      final match = RegExp(r'^(\d+)\.').firstMatch(item.code.trim());
      if (match != null) {
        final p = '${match.group(1)}.';
        prefixCounts[p] = (prefixCounts[p] ?? 0) + 1;
      }
    }

    if (prefixCounts.isNotEmpty) {
      final sorted = prefixCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      prefix = sorted.first.key;
    }

    // B. If not found from existing items, extract leading number from category string
    if (prefix == null) {
      final catMatch = RegExp(r'^(\d+)').firstMatch(category.trim());
      if (catMatch != null) {
        prefix = '${catMatch.group(1)}.';
      } else if (category.toLowerCase().contains('hinweis') || category.toLowerCase().contains('anmerkung')) {
        prefix = '0.';
      } else {
        prefix = '1.';
      }
    }

    // 2. If incoming code already matches this prefix and is not taken, keep it
    if (incomingCode != null && incomingCode.trim().isNotEmpty) {
      final cleanIncoming = incomingCode.trim();
      final codeExists = officialCatalog.any((e) => e.code.toLowerCase() == cleanIncoming.toLowerCase());
      if (!codeExists && cleanIncoming.startsWith(prefix) && RegExp(r'^\d+\.\d+$').hasMatch(cleanIncoming)) {
        return cleanIncoming;
      }
    }

    // 3. Find highest existing secondary number for this prefix
    int maxSecondary = 0;
    final prefixRegex = RegExp('^' + RegExp.escape(prefix) + r'(\d+)$');
    for (final item in officialCatalog) {
      final m = prefixRegex.firstMatch(item.code.trim());
      if (m != null) {
        final num = int.tryParse(m.group(1)!) ?? 0;
        if (num > maxSecondary) {
          maxSecondary = num;
        }
      }
    }

    return '$prefix${maxSecondary + 1}';
  }

  /// Checks if a given code is already used by an official entry in the catalog.
  static ErrorCatalog? findCodeCollision(
    String code,
    List<ErrorCatalog> existingCatalog, {
    int? ignoreErrorId,
  }) {
    final clean = code.trim().toLowerCase();
    if (clean.isEmpty) return null;

    return existingCatalog.where((e) {
      if (e.category == 'Altdaten' || e.code.toUpperCase().startsWith('ALT-')) return false;
      if (ignoreErrorId != null && e.errorId == ignoreErrorId) return false;
      return e.code.trim().toLowerCase() == clean;
    }).firstOrNull;
  }

  /// Calculates the text similarity between two error descriptions (0.0 to 1.0).
  static double calculateDescriptionSimilarity(String text1, String text2) {
    final c1 = _cleanDescription(text1);
    final c2 = _cleanDescription(text2);

    // Substring coverage
    final double subSim = (c1.contains(c2) || c2.contains(c1))
        ? (min(c1.length, c2.length) / max(c1.length, c2.length))
        : 0.0;

    // Token-based Dice Coefficient
    final tokens1 = _tokenize(c1);
    final tokens2 = _tokenize(c2);

    double tokenSimilarity = 0.0;
    if (tokens1.isNotEmpty && tokens2.isNotEmpty) {
      int intersectionCount = 0;
      final set2 = tokens2.toSet();
      for (final t in tokens1) {
        if (set2.contains(t)) {
          intersectionCount++;
        }
      }
      tokenSimilarity = (2.0 * intersectionCount) / (tokens1.length + tokens2.length);
    }

    // Levenshtein distance on characters
    final int levDist = _levenshteinDistance(c1, c2);
    final int maxLen = max(c1.length, c2.length);
    final double charSimilarity = maxLen == 0 ? 1.0 : (1.0 - (levDist / maxLen));

    return max(subSim, max(tokenSimilarity, charSimilarity));
  }

  /// Scans catalog for any existing official entry with description similarity >= threshold (default: 0.75).
  static SimilarCatalogMatch? findSimilarDescription(
    String description,
    List<ErrorCatalog> existingCatalog, {
    double threshold = 0.75,
    int? ignoreErrorId,
  }) {
    final cleanInput = _cleanDescription(description);
    if (cleanInput.length < 3) return null;

    SimilarCatalogMatch? bestMatch;
    double highestScore = 0.0;

    for (final item in existingCatalog) {
      if (item.category == 'Altdaten' || item.code.toUpperCase().startsWith('ALT-')) continue;
      if (ignoreErrorId != null && item.errorId == ignoreErrorId) continue;

      final score = calculateDescriptionSimilarity(description, item.description);
      if (score >= threshold && score > highestScore) {
        highestScore = score;
        bestMatch = SimilarCatalogMatch(
          existing: item,
          similarity: score,
          matchedDescription: item.description,
        );
      }
    }

    return bestMatch;
  }

  static String _cleanDescription(String text) {
    var s = text.trim().toLowerCase();
    // Remove common prefixes
    s = s.replaceFirst(RegExp(r'^(hinweis|mangel|fehler|anmerkung|wartungsmangel):\s*', caseSensitive: false), '');
    // Remove standard code prefixes like "0.32 "
    s = s.replaceFirst(RegExp(r'^\d+(\.\d+)?\s+'), '');
    // Replace punctuation with whitespace
    s = s.replaceAll(RegExp(r'[\.,;:\-_/\\()\[\]"§#+*~!?]'), ' ');
    // Condense whitespace
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static List<String> _tokenize(String text) {
    return text.split(' ').where((token) => token.trim().length > 1).toList();
  }

  static int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.filled(s2.length + 1, 0);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i <= s2.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        final cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[s2.length];
  }
}
