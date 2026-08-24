import '../models/door.dart';

class CustomerNormalizer {
  /// Legal entity suffixes and corporate noise words to strip
  static final RegExp _legalSuffixesRegExp = RegExp(
    r'\b(GmbH\s*&\s*Co\.?\s*KG|GmbH|AG|e\.?V\.?|KG|GbR|OHG|SE|UG|Ltd\.?|Inc\.?|Corp\.?|Holding|Verwaltung|Immobilien|mbH)\b',
    caseSensitive: false,
  );

  /// Transliterates German umlauts and accents into standard ASCII.
  static String transliterate(String input) {
    return input
        .replaceAll('ä', 'ae')
        .replaceAll('Ä', 'AE')
        .replaceAll('ö', 'oe')
        .replaceAll('Ö', 'OE')
        .replaceAll('ü', 'ue')
        .replaceAll('Ü', 'UE')
        .replaceAll('ß', 'ss');
  }

  /// Returns a clean canonical display name (e.g. "Sprinkenhof GmbH" -> "Sprinkenhof")
  static String getCanonicalName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return '';

    String cleaned = trimmed.replaceAll(_legalSuffixesRegExp, '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'[\s\-/,.]+$'), '').trim();

    return cleaned.isNotEmpty ? cleaned : trimmed;
  }

  /// Returns a strict uppercase comparison key (e.g. "Sprinkenhof GmbH" -> "SPRINKENHOF")
  static String getCanonicalKey(String rawName) {
    final cleanDisplay = getCanonicalName(rawName);
    final transliterated = transliterate(cleanDisplay);
    return transliterated
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toUpperCase();
  }

  /// Compares two doors hierarchically by Floor -> Room -> Door Number
  static int compareDoors(Door a, Door b) {
    // 1. Floor ordering
    final floorRankA = _getFloorRank(a.floor);
    final floorRankB = _getFloorRank(b.floor);
    if (floorRankA != floorRankB) {
      return floorRankA.compareTo(floorRankB);
    }

    // 2. Room designation
    final roomComp = a.roomDesignation.toLowerCase().compareTo(b.roomDesignation.toLowerCase());
    if (roomComp != 0) return roomComp;

    // 3. Room number
    final roomNumComp = a.roomNumber.toLowerCase().compareTo(b.roomNumber.toLowerCase());
    if (roomNumComp != 0) return roomNumComp;

    // 4. Door number (numeric order)
    final doorNumA = int.tryParse(a.doorNumber.replaceAll(RegExp(r'\D'), '')) ?? 0;
    final doorNumB = int.tryParse(b.doorNumber.replaceAll(RegExp(r'\D'), '')) ?? 0;
    if (doorNumA != doorNumB) {
      return doorNumA.compareTo(doorNumB);
    }

    // Fallback doorAlias
    return (a.doorAlias ?? '').compareTo(b.doorAlias ?? '');
  }

  static int _getFloorRank(String floorStr) {
    final clean = floorStr.trim().toUpperCase();
    if (clean.contains('UG3')) return 1;
    if (clean.contains('UG2')) return 2;
    if (clean.contains('UG') || clean.contains('KELLER')) return 3;
    if (clean.contains('EG') || clean.contains('ERDGESCHOSS')) return 4;
    if (clean.contains('OG1') || clean.contains('1.OG') || clean.contains('1. OG')) return 5;
    if (clean.contains('OG2') || clean.contains('2.OG') || clean.contains('2. OG')) return 6;
    if (clean.contains('OG3') || clean.contains('3.OG') || clean.contains('3. OG')) return 7;
    if (clean.contains('OG4') || clean.contains('4.OG') || clean.contains('4. OG')) return 8;
    if (clean.contains('OG5') || clean.contains('5.OG') || clean.contains('5. OG')) return 9;
    if (clean.contains('OG')) return 10;
    if (clean.contains('DG') || clean.contains('DACHGESCHOSS')) return 11;
    return 12;
  }
}
