import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/models/door.dart';

void main() {
  group('Structured Alias Generation Tests', () {
    test('Standard project number with P- prefix, pos, floor, door number', () {
      final alias = Door.generateAlias(
        projectNumber: 'P-000100',
        pos: 1,
        floor: 'EG',
        doorNumber: '21.2',
      );
      expect(alias, '000100-1-EG-21.2');
    });

    test('Project number without P-, upper floor with dot, door number', () {
      final alias = Door.generateAlias(
        projectNumber: '12345',
        pos: 15,
        floor: '1. OG',
        doorNumber: '104',
      );
      expect(alias, '12345-15-1.OG-104');
    });

    test('Cleaning special characters from floor and door number while preserving dots', () {
      final alias = Door.generateAlias(
        projectNumber: 'P-998877',
        pos: 3,
        floor: '2. OG / Flur',
        doorNumber: '21.2,a',
      );
      expect(alias, '998877-3-2.OGFlur-21.2.a');
    });

    test('Temporary field door alias generation', () {
      final tmpAlias = Door.generateTemporaryAlias('1');
      expect(tmpAlias.startsWith('TMP-'), isTrue);
      expect(tmpAlias.endsWith('-01'), isTrue);
    });
  });
}
