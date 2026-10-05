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
  });
}
