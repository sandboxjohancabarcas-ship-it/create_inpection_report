import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/services/door_options_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DoorOptionsService CRUD Tests', () {
    setUp(() {
      DoorOptionsService.setMockOptions({
        'manufacturer': {
          'options': ['?', 'Schüco', 'Hörmann'],
          'default': '?'
        },
        'approvalNumber': {
          'options': ['?', 'Z-12345'],
          'default': '?'
        }
      });
    });

    tearDown(() {
      DoorOptionsService.reset();
    });

    test('addOption adds new unique entry correctly', () {
      DoorOptionsService.addOption('manufacturer', 'Teckentrup');
      final options = DoorOptionsService.getStringOptions('manufacturer');
      
      expect(options, contains('Teckentrup'));
      expect(options.length, 4);
    });

    test('addOption ignores duplicate entries case-insensitively', () {
      DoorOptionsService.addOption('manufacturer', 'schüco');
      final options = DoorOptionsService.getStringOptions('manufacturer');
      
      expect(options.length, 3);
    });

    test('updateOption renames existing option value', () {
      final success = DoorOptionsService.updateOption('manufacturer', 'Hörmann', 'Hörmann KG');
      expect(success, isTrue);

      final options = DoorOptionsService.getStringOptions('manufacturer');
      expect(options, contains('Hörmann KG'));
      expect(options, isNot(contains('Hörmann')));
    });

    test('updateOption returns false when target item does not exist', () {
      final success = DoorOptionsService.updateOption('manufacturer', 'NonExistent', 'NewVal');
      expect(success, isFalse);
    });

    test('removeOption deletes existing option value', () {
      final success = DoorOptionsService.removeOption('manufacturer', 'Schüco');
      expect(success, isTrue);

      final options = DoorOptionsService.getStringOptions('manufacturer');
      expect(options, isNot(contains('Schüco')));
      expect(options.length, 2);
    });

    test('removeOption returns false when item to remove is not found', () {
      final success = DoorOptionsService.removeOption('manufacturer', 'UnknownBrand');
      expect(success, isFalse);
    });
  });
}
