import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/models/error_catalog.dart';
import 'package:wartungstool/services/catalog_integrity_service.dart';

void main() {
  group('CatalogIntegrityService Tests', () {
    final sampleCatalog = [
      ErrorCatalog(
        errorId: 1,
        code: '0.1',
        description: 'Hinweis: Bodenbelag nicht gemäß Brandschutzanforderungen',
        category: 'Hinweise und Anmerkungen',
        severity: 'low',
      ),
      ErrorCatalog(
        errorId: 2,
        code: '0.39',
        description: 'Hinweis: Sonstige Beanstandung',
        category: 'Hinweise und Anmerkungen',
        severity: 'low',
      ),
      ErrorCatalog(
        errorId: 3,
        code: '1.1',
        description: 'Türblatt verzogen / schließt nicht',
        category: 'Türblatt/Zarge',
        severity: 'high',
      ),
      ErrorCatalog(
        errorId: 4,
        code: '1.19',
        description: 'Dichtung im Zargenbereich beschädigt',
        category: 'Türblatt/Zarge',
        severity: 'medium',
      ),
      ErrorCatalog(
        errorId: 5,
        code: '11.1',
        description: 'Rauchmelder verschmutzt',
        category: 'Feststellanlagen (FSA)',
        severity: 'medium',
      ),
      ErrorCatalog(
        errorId: 6,
        code: '11.19',
        description: 'SCU-UP Steuergerät defekt',
        category: 'Feststellanlagen (FSA)',
        severity: 'critical',
      ),
      ErrorCatalog(
        errorId: 7,
        code: 'ALT-001',
        description: 'Historischer Mangel 1',
        category: 'Altdaten',
        status: 'Historical',
      ),
    ];

    test('proposeNextCodeForCategory proposes incremented code fitting category prefix', () {
      // For FSA category, highest is 11.19 -> should propose 11.20
      final fsaNext = CatalogIntegrityService.proposeNextCodeForCategory(
        'Feststellanlagen (FSA)',
        sampleCatalog,
      );
      expect(fsaNext, equals('11.20'));

      // For Hinweise, highest is 0.39 -> should propose 0.40
      final hinweisNext = CatalogIntegrityService.proposeNextCodeForCategory(
        'Hinweise und Anmerkungen',
        sampleCatalog,
      );
      expect(hinweisNext, equals('0.40'));

      // For Türblatt/Zarge, highest is 1.19 -> should propose 1.20
      final tuerblattNext = CatalogIntegrityService.proposeNextCodeForCategory(
        'Türblatt/Zarge',
        sampleCatalog,
      );
      expect(tuerblattNext, equals('1.20'));
    });

    test('proposeNextCodeForCategory preserves valid non-colliding incoming code', () {
      final code = CatalogIntegrityService.proposeNextCodeForCategory(
        'Feststellanlagen (FSA)',
        sampleCatalog,
        incomingCode: '11.25',
      );
      expect(code, equals('11.25'));
    });

    test('findCodeCollision identifies identical code collision with official catalog', () {
      final collision = CatalogIntegrityService.findCodeCollision('11.19', sampleCatalog);
      expect(collision, isNotNull);
      expect(collision!.description, contains('SCU-UP'));

      // Free code should not collide
      final noCollision = CatalogIntegrityService.findCodeCollision('11.20', sampleCatalog);
      expect(noCollision, isNull);

      // Codes in category Altdaten / ALT-* should be ignored for catalog collision
      final altCollision = CatalogIntegrityService.findCodeCollision('ALT-001', sampleCatalog);
      expect(altCollision, isNull);
    });

    test('calculateDescriptionSimilarity accurately scores close wording variations', () {
      // Very close wording
      final sim1 = CatalogIntegrityService.calculateDescriptionSimilarity(
        'Hinweis: SCU-UP Steuergerät defekt',
        'Dormakaba Fehler SCU-UP Steuergerät defekt',
      );
      expect(sim1, greaterThan(0.70));

      // Almost identical
      final sim2 = CatalogIntegrityService.calculateDescriptionSimilarity(
        'Türblatt verzogen / schließt nicht',
        'Türblatt verzogen, schließt nicht vollständig',
      );
      expect(sim2, greaterThan(0.75));

      // Completely unrelated
      final sim3 = CatalogIntegrityService.calculateDescriptionSimilarity(
        'Türblatt verzogen',
        'Rauchmelder verschmutzt',
      );
      expect(sim3, lessThan(0.30));
    });

    test('findSimilarDescription finds highest matching entry above threshold', () {
      final match = CatalogIntegrityService.findSimilarDescription(
        'Fehler SCU-UP Steuergerät defekt',
        sampleCatalog,
        threshold: 0.75,
      );

      expect(match, isNotNull);
      expect(match!.existing.code, equals('11.19'));
      expect(match.similarityPercentage, greaterThanOrEqualTo(75));
    });
  });
}
