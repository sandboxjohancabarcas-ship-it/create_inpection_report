import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/services/customer_normalizer.dart';
import 'package:wartungstool/models/door.dart';

void main() {
  group('CustomerNormalizer Tests', () {
    test('getCanonicalKey matches variations of same customer', () {
      final key1 = CustomerNormalizer.getCanonicalKey('Sprinkenhof GmbH');
      final key2 = CustomerNormalizer.getCanonicalKey('Sprinkenhof');
      final key3 = CustomerNormalizer.getCanonicalKey('Sprinkenhof mbH');

      expect(key1, equals(key2));
      expect(key2, equals(key3));
      expect(key1, equals('SPRINKENHOF'));
    });

    test('getCanonicalName cleans legal entity suffixes', () {
      expect(CustomerNormalizer.getCanonicalName('Sprinkenhof GmbH'), equals('Sprinkenhof'));
      expect(CustomerNormalizer.getCanonicalName('GA-Tec GmbH'), equals('GA-Tec'));
      expect(CustomerNormalizer.getCanonicalName('EEW Energy from Waste GmbH'), equals('EEW Energy from Waste'));
    });

    test('compareDoors sorts by Floor -> Room -> Door Number', () {
      final doorUG = Door(
        id: 1,
        pos: 1,
        doorAlias: 'A1',
        doorNumber: '1',
        floor: 'UG1',
        roomNumber: '10',
        roomDesignation: 'Lager',
        doorType: 'T30',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Hörmann',
        dinConfiguration: 'DIN L',
        closerType: 'Obentürschließer',
        closingSequenceSystem: 'Nein',
        lockDimensions: '55/72',
        closerOnHingeSide: true,
        closerOnOppositeSide: false,
        escapeDoorControl: false,
        accessControl: '',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: true,
        fittingType: 'Drücker',
        panicFunction: 'Nein',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
      );

      final doorEG = doorUG.copyWith(id: 2, floor: 'EG');
      final doorOG = doorUG.copyWith(id: 3, floor: '1.OG');

      final List<Door> doors = [doorOG, doorUG, doorEG];
      doors.sort(CustomerNormalizer.compareDoors);

      expect(doors[0].floor, equals('UG1'));
      expect(doors[1].floor, equals('EG'));
      expect(doors[2].floor, equals('1.OG'));
    });
  });
}
