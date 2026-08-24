import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/models/door.dart';

void main() {
  group('Intelligent Semantic Alias Generation Tests', () {
    test('Standard German customer & address format', () {
      final alias = Door.generateAlias(
        'Gottsberg GmbH',
        'Ebner-Eschenbach-Weg 43, 21035 Hamburg',
        '1',
        floor: 'EG',
      );
      expect(alias, 'GOTTS-EBN43-EG-01');
    });

    test('Multi-word customer and address with upper floor', () {
      final alias = Door.generateAlias(
        'Konz Schäfer',
        'Hauptstraße 12b',
        '4',
        floor: '1. OG',
      );
      expect(alias, 'KONSC-HA12B-OG1-04');
    });

    test('Customer with Umlaut transliteration and underground floor', () {
      final alias = Door.generateAlias(
        'Bäckerei Müller e.V.',
        'Mühlenweg 7',
        '02',
        floor: 'Untergeschoss',
      );
      expect(alias, 'BAEMU-MUEH7-UG-02');
    });

    test('Industrial complex with building/door code and street stop words', () {
      final alias = Door.generateAlias(
        'Siemens AG',
        'Werner-von-Siemens-Ring 50',
        'T-201',
        floor: '2. Obergeschoss',
      );
      expect(alias, 'SIEME-WER50-OG2-T201');
    });

    test('Temporary field door alias generation', () {
      final tmpAlias = Door.generateTemporaryAlias('1');
      expect(tmpAlias.startsWith('TMP-'), isTrue);
      expect(tmpAlias.endsWith('-01'), isTrue);
      expect(tmpAlias.length, lessThanOrEqualTo(14));
    });
  });
}
