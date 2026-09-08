import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/models/door.dart';
import 'package:wartungstool/models/door_conflict.dart';
import 'package:wartungstool/services/door_options_service.dart';
import 'package:wartungstool/services/door_validator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Extended Door Properties Tests', () {
    test('Door model defaults and serialization for new properties', () {
      final door = Door(
        id: 1,
        pos: 1,
        doorAlias: 'TEST-ALIAS-01',
        doorNumber: '01',
        floor: 'EG',
        roomNumber: '101',
        roomDesignation: 'Büro',
        doorType: 'T30-1',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Hörmann',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: 'Nein',
        lockDimensions: '35/92/9',
        closerOnHingeSide: true,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: false,
        accessControl: 'Nein',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: true,
        fittingType: 'D-D',
        panicFunction: 'Nein',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
      );

      // Verify default values
      expect(door.approvalNumber, '?');
      expect(door.manufacturerNumber, '?');
      expect(door.dopNumber, '?');
      expect(door.lintelHeightOver1m, false);
      expect(door.lintelHeightValue, isNull);
      expect(door.manufactureYear, '?');

      // Test toMap
      final map = door.toMap();
      expect(map['approvalNumber'], '?');
      expect(map['manufacturerNumber'], '?');
      expect(map['dopNumber'], '?');
      expect(map['lintelHeightOver1m'], 0);
      expect(map['lintelHeightValue'], isNull);
      expect(map['manufactureYear'], '?');

      // Test fromMap
      final restored = Door.fromMap(map);
      expect(restored.approvalNumber, '?');
      expect(restored.manufacturerNumber, '?');
      expect(restored.dopNumber, '?');
      expect(restored.lintelHeightOver1m, false);
      expect(restored.lintelHeightValue, isNull);
      expect(restored.manufactureYear, '?');

      // Test copyWith with custom values
      final updated = door.copyWith(
        approvalNumber: 'Z-6.5-2134',
        manufacturerNumber: 'HERST-9988',
        dopNumber: 'DoP-12345',
        lintelHeightOver1m: true,
        lintelHeightValue: 3,
        manufactureYear: '2022',
      );

      expect(updated.approvalNumber, 'Z-6.5-2134');
      expect(updated.manufacturerNumber, 'HERST-9988');
      expect(updated.dopNumber, 'DoP-12345');
      expect(updated.lintelHeightOver1m, true);
      expect(updated.lintelHeightValue, 3);
      expect(updated.manufactureYear, '2022');
    });

    test('DoorOptionsService addOption and getStringOptions', () async {
      DoorOptionsService.reset();
      DoorOptionsService.setMockOptions({
        'approvalNumber': {
          'options': ['?'],
          'default': '?'
        }
      });

      expect(DoorOptionsService.getStringOptions('approvalNumber'), ['?']);

      DoorOptionsService.addOption('approvalNumber', 'Z-6.5-1234');
      expect(DoorOptionsService.getStringOptions('approvalNumber'), ['?', 'Z-6.5-1234']);

      // Duplicate add should be ignored
      DoorOptionsService.addOption('approvalNumber', 'Z-6.5-1234');
      expect(DoorOptionsService.getStringOptions('approvalNumber'), ['?', 'Z-6.5-1234']);
    });

    test('DoorValidator detectDropdownOptionConflicts for new free-text dropdown values', () {
      DoorOptionsService.setMockOptions({
        'approvalNumber': {'options': ['?'], 'default': '?'},
        'manufacturerNumber': {'options': ['?'], 'default': '?'},
        'dopNumber': {'options': ['?'], 'default': '?'},
        'doorType': {'options': ['?', 'T30-1'], 'default': '?'},
        'material': {'options': ['?', 'Stahl'], 'default': '?'},
        'manufacturer': {'options': ['?', 'Hörmann'], 'default': '?'},
        'dinConfiguration': {'options': ['?', 'DIN L'], 'default': '?'},
        'closingSequenceSystem': {'options': ['?', 'Nein'], 'default': '?'},
        'lockDimensions': {'options': ['?', '35/92/9'], 'default': '?'},
        'accessControl': {'options': ['Nein'], 'default': 'Nein'},
        'fittingType': {'options': ['Nein', 'D-D'], 'default': 'Nein'},
        'panicFunction': {'options': ['Nein', 'B'], 'default': 'Nein'},
      });

      final incoming = Door(
        id: null,
        pos: 1,
        doorAlias: 'TEST-01',
        doorNumber: '01',
        floor: 'EG',
        roomNumber: '101',
        roomDesignation: 'Büro',
        doorType: 'T30-1',
        wingCount: 1,
        material: 'Stahl',
        manufacturer: 'Hörmann',
        dinConfiguration: 'DIN L',
        closerType: 'TS93',
        closingSequenceSystem: 'Nein',
        lockDimensions: '35/92/9',
        closerOnHingeSide: true,
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: false,
        accessControl: 'Nein',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: true,
        fittingType: 'D-D',
        panicFunction: 'Nein',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: true,
        approvalNumber: 'Z-9.1-8888', // NEW custom value!
        manufacturerNumber: 'H-99-CUSTOM', // NEW custom value!
        dopNumber: 'DoP-999', // NEW custom value!
      );

      final conflicts = DoorValidator.detectDropdownOptionConflicts(incoming);

      expect(conflicts.length, 2);
      expect(conflicts.map((c) => c.fieldName), containsAll(['approvalNumber', 'manufacturerNumber']));
      expect(conflicts.every((c) => c.type == DoorConflictType.newDropdownOption), isTrue);
      expect(conflicts.every((c) => c.resolution == DoorResolutionAction.addToMasterOptions), isTrue);
    });
  });
}
