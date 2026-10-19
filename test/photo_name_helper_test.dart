import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/utils/photo_name_helper.dart';

void main() {
  group('PhotoNameHelper Tests', () {
    test('formatPhotoName correctly constructs [door alias]_Fehler_[error code]_[index].jpg', () {
      final name1 = PhotoNameHelper.formatPhotoName(
        doorAlias: '000100-1-EG-21.2',
        errorCode: '1.1.1',
        photoIndex: 1,
      );
      expect(name1, equals('000100-1-EG-21.2_Fehler_1.1.1_1.jpg'));

      final name2 = PhotoNameHelper.formatPhotoName(
        doorAlias: '000331-2-2.UG-Geb.63-2',
        errorCode: '3.2.1',
        photoIndex: 2,
      );
      expect(name2, equals('000331-2-2.UG-Geb.63-2_Fehler_3.2.1_2.jpg'));

      final name3 = PhotoNameHelper.formatPhotoName(
        doorAlias: '000250-4-1.OG-Tuer12',
        errorCode: 'Hinweis-02',
        photoIndex: 3,
      );
      expect(name3, equals('000250-4-1.OG-Tuer12_Fehler_Hinweis-02_3.jpg'));
    });

    test('formatPhotoNames generates ordered list of names for multiple photos', () {
      final names = PhotoNameHelper.formatPhotoNames(
        doorAlias: '000100-1-EG-21.2',
        errorCode: '1.1.1',
        photoCount: 3,
      );
      expect(names, hasLength(3));
      expect(names[0], equals('000100-1-EG-21.2_Fehler_1.1.1_1.jpg'));
      expect(names[1], equals('000100-1-EG-21.2_Fehler_1.1.1_2.jpg'));
      expect(names[2], equals('000100-1-EG-21.2_Fehler_1.1.1_3.jpg'));
    });

    test('sanitizeForFilename removes invalid characters', () {
      final sanitized = PhotoNameHelper.sanitizeForFilename('Tuer/1:2*3?4"5<6>7|8');
      expect(sanitized, equals('Tuer-1-2-3-4-5-6-7-8'));
    });

    test('formatPropertyPhotoName correctly constructs alias_propertyname_indexNumber.jpg', () {
      final nameZulassung = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: '000100-1-EG-21.2',
        propertyName: 'Zulassungsnummer',
        indexNumber: 1,
      );
      expect(nameZulassung, equals('000100-1-EG-21.2_Zulassungsnummer_1.jpg'));

      final nameHersteller = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: '000100-1-EG-21.2',
        propertyName: 'Hersteller',
        indexNumber: 1,
      );
      expect(nameHersteller, equals('000100-1-EG-21.2_Hersteller_1.jpg'));

      final nameHerstellerNr = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: '000100-1-EG-21.2',
        propertyName: 'Herstellernummer',
        indexNumber: 1,
      );
      expect(nameHerstellerNr, equals('000100-1-EG-21.2_Herstellernummer_1.jpg'));

      // Test with index increment
      final nameIndexed = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: '000100-1-EG-21.2',
        propertyName: 'Zulassungsnummer',
        indexNumber: 2,
      );
      expect(nameIndexed, equals('000100-1-EG-21.2_Zulassungsnummer_2.jpg'));

      // Test with typos or spaced inputs
      final nameWithSpace = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: 'Door-12',
        propertyName: 'Hersteller nummer',
        indexNumber: 1,
      );
      expect(nameWithSpace, equals('Door-12_Herstellernummer_1.jpg'));

      final nameWithTypo = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: 'Door-12',
        propertyName: 'Zulangsnummer',
        indexNumber: 1,
      );
      expect(nameWithTypo, equals('Door-12_Zulassungsnummer_1.jpg'));
    });

    test('formatDoorPhotoName correctly constructs alias_Tuer_indexNumber.jpg', () {
      final doorPhoto1 = PhotoNameHelper.formatDoorPhotoName(
        doorAlias: '000100-1-EG-21.2',
        indexNumber: 1,
      );
      expect(doorPhoto1, equals('000100-1-EG-21.2_Tuer_1.jpg'));

      final doorPhoto2 = PhotoNameHelper.formatDoorPhotoName(
        doorAlias: '000100-1-EG-21.2',
        indexNumber: 2,
      );
      expect(doorPhoto2, equals('000100-1-EG-21.2_Tuer_2.jpg'));

      // Test with formatPropertyPhotoName using "Tür" or "Tuer"
      final propPhotoUmlaut = PhotoNameHelper.formatPropertyPhotoName(
        doorAlias: 'Tuer-05',
        propertyName: 'Tür',
        indexNumber: 1,
      );
      expect(propPhotoUmlaut, equals('Tuer-05_Tuer_1.jpg'));
    });
  });
}
