import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/door_options_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DoorOptionsService Tests', () {
    setUp(() {
      DoorOptionsService.reset();
    });

    test('Loads hardcoded fallback options by default', () async {
      // By default, if assets/external files are not set up in tests, it will log errors and use hardcoded fallbacks
      await DoorOptionsService.ensureLoaded();

      expect(DoorOptionsService.getStringOptions('doorType'), contains('?'));
      expect(DoorOptionsService.getIntOptions('wingCount'), contains(1));
      expect(DoorOptionsService.getDefault('doorType'), equals('?'));
      expect(DoorOptionsService.getDefault('wingCount'), equals(1));
    });

    test('Supports mocking configuration data', () {
      final mockData = {
        "doorType": {
          "options": ["TypeA", "TypeB"],
          "default": "TypeA"
        },
        "wingCount": {
          "options": [1, 2],
          "default": 2
        },
        "closerType": {
          "options": [
            {"value": "C1", "label": "Closer 1"},
            {"value": "C2", "label": "Closer 2"}
          ],
          "default": "C1"
        }
      };

      DoorOptionsService.setMockOptions(mockData);

      expect(DoorOptionsService.getStringOptions('doorType'), equals(["TypeA", "TypeB"]));
      expect(DoorOptionsService.getDefault('doorType'), equals("TypeA"));

      expect(DoorOptionsService.getIntOptions('wingCount'), equals([1, 2]));
      expect(DoorOptionsService.getDefault('wingCount'), equals(2));

      final closerOptions = DoorOptionsService.getMapOptions('closerType');
      expect(closerOptions.length, equals(2));
      expect(closerOptions[0]['value'], equals('C1'));
      expect(closerOptions[0]['label'], equals('Closer 1'));
      expect(DoorOptionsService.getDefault('closerType'), equals("C1"));
    });

    test('Gracefully handles missing keys', () async {
      await DoorOptionsService.ensureLoaded();
      
      // Requesting a non-existent key shouldn't crash, should return empty/null
      expect(DoorOptionsService.getOptions('nonExistentKey'), isEmpty);
      expect(DoorOptionsService.getDefault('nonExistentKey'), isNull);
    });
  });
}
