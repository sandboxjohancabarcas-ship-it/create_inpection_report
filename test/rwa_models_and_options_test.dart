import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/rwa_options_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RwaSystem Model Tests', () {
    test('RwaSystem toMap and fromMap serialization roundtrip', () {
      final rwa = RwaSystem(
        id: 1,
        systemAlias: 'Anlage 1 - M-PIC-Ost',
        provisionalAlias: 'RWA-26-14517-AB-01',
        projectNumber: '26-14517-AB',
        systemType: 'elektromotorisch / CO2',
        objectAddress: 'Hohe-Schar-Str. 36, 21107 Hamburg',
        building: 'Gebäude G',
        floor: 'Dach',
        room: 'PAE-Labor',
        centralType: 'JET - FIREJET 165J',
        fireButtonSpec: '2 Auslöseeinheiten CO2',
        smokeDetectorSpec: '---',
        actuatorSpec: '2 Stück CO2 Zylinder',
        ventilationButtonSpec: '---',
        emergencyPowerSpec: '---',
        co2BottleSpec: '2 Stück 501.105, CO2 Patrone 45 gr., 1/2" UNF Gew.',
        thermalBottleSpec: '2 Stück 501.513, Thermoflasche 68°C F4',
        rwaFlapSpec: '2 Stück RWA Kuppeln',
        ventilationFlapSpec: '---',
        damperSpec: '---',
        systemFunctionOK: true,
        notes: 'Erstprüfung',
      );

      final map = rwa.toMap();
      expect(map['id'], 1);
      expect(map['systemAlias'], 'Anlage 1 - M-PIC-Ost');
      expect(map['systemType'], 'elektromotorisch / CO2');
      expect(map['systemFunctionOK'], 1);

      final reconstructed = RwaSystem.fromMap(map);
      expect(reconstructed.id, 1);
      expect(reconstructed.systemAlias, 'Anlage 1 - M-PIC-Ost');
      expect(reconstructed.systemType, 'elektromotorisch / CO2');
      expect(reconstructed.co2BottleSpec, contains('501.105'));
      expect(reconstructed.systemFunctionOK, isTrue);
      expect(reconstructed.effectiveAlias, 'Anlage 1 - M-PIC-Ost');
    });

    test('RwaSystem copyWith updates specified fields', () {
      final rwa = RwaSystem(
        projectNumber: 'P-100',
        systemType: 'CO2',
        objectAddress: 'Teststraße 1',
      );

      final updated = rwa.copyWith(systemFunctionOK: false, notes: 'Defekt');
      expect(updated.systemFunctionOK, isFalse);
      expect(updated.notes, 'Defekt');
      expect(updated.systemType, 'CO2');
    });
  });

  group('RwaInspectionSetting Model Tests', () {
    test('RwaInspectionSetting evaluates OK, DEFECT, and NOT_PRESENT', () {
      final setting1 = RwaInspectionSetting(
        inspectionRwaId: 10,
        settingName: 'Feuertaster',
        result: 'DEFECT',
        rawResult: 'X',
        annotation: 'Korrosion außen',
      );
      expect(setting1.isDefect, isTrue);
      expect(setting1.isOk, isFalse);

      final map = setting1.toMap();
      final fromMap = RwaInspectionSetting.fromMap(map);
      expect(fromMap.settingName, 'Feuertaster');
      expect(fromMap.result, 'DEFECT');
      expect(fromMap.rawResult, 'X');
      expect(fromMap.annotation, 'Korrosion außen');
    });
  });

  group('InspectionRwa & InspectionRwaError Model Tests', () {
    test('InspectionRwa serialization', () {
      final junction = InspectionRwa(
        id: 5,
        inspectionId: 100,
        rwaSystemId: 200,
        status: 'Completed',
        notes: 'Wartung 2026',
        attachments: ['photo1.jpg', 'photo2.jpg'],
      );

      final map = junction.toMap();
      expect(map['attachments'], 'photo1.jpg,photo2.jpg');

      final fromMap = InspectionRwa.fromMap(map);
      expect(fromMap.attachments?.length, 2);
      expect(fromMap.attachments?.first, 'photo1.jpg');
    });

    test('InspectionRwaError serialization', () {
      final error = InspectionRwaError(
        id: 1,
        inspectionRwaId: 5,
        settingName: 'Notstrombatterie',
        errorCode: 'RWA-AK-001',
        quantity: 2,
        severity: 'high',
        notes: 'Akkus über 4 Jahre alt',
      );

      final map = error.toMap();
      final fromMap = InspectionRwaError.fromMap(map);
      expect(fromMap.errorCode, 'RWA-AK-001');
      expect(fromMap.settingName, 'Notstrombatterie');
      expect(fromMap.quantity, 2);
      expect(fromMap.severity, 'high');
    });
  });

  group('RwaOptionsService & JSON Asset Tests', () {
    test('rwa_options.json exists and is valid JSON with required keys', () {
      final file = File('rwa_options.json');
      expect(file.existsSync(), isTrue);

      final content = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(content.containsKey('systemType'), isTrue);
      expect(content.containsKey('centralType'), isTrue);
      expect(content.containsKey('fireButton'), isTrue);
      expect(content.containsKey('smokeDetector'), isTrue);
      expect(content.containsKey('actuator'), isTrue);
      expect(content.containsKey('ventilationButton'), isTrue);
      expect(content.containsKey('emergencyPower'), isTrue);
      expect(content.containsKey('co2Bottles'), isTrue);
      expect(content.containsKey('thermalBottle'), isTrue);
      expect(content.containsKey('rwaFlaps'), isTrue);
      expect(content.containsKey('ventilationFlaps'), isTrue);
      expect(content.containsKey('dampers'), isTrue);
      expect(content.containsKey('einrichtungSettings'), isTrue);

      final einrichtung = content['einrichtungSettings'] as List;
      expect(einrichtung.length, 12);
      expect(einrichtung, contains('RWA-Klappen'));
      expect(einrichtung, contains('Feuertaster'));
      expect(einrichtung, contains('Notstrombatterie'));
      expect(einrichtung, contains('Anlage ausgelöst'));
      expect(einrichtung, contains('Anlage geschlossen'));
    });

    test('rwa_error_catalog.json exists and is valid JSON', () {
      final file = File('rwa_error_catalog.json');
      expect(file.existsSync(), isTrue);

      final content = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(content.isNotEmpty, isTrue);

      // Verify structure of first entry
      final firstKey = content.keys.first;
      final firstEntry = content[firstKey] as Map<String, dynamic>;
      expect(firstEntry.containsKey('description'), isTrue);
      expect(firstEntry.containsKey('category'), isTrue);
      expect(firstEntry.containsKey('severity'), isTrue);
      expect(firstEntry['assetType'], 'rwa');
    });

    test('RwaOptionsService defaults and custom option addition', () async {
      RwaOptionsService.setTestMode(true);
      final systemTypes = RwaOptionsService.getOptions('systemType');
      expect(systemTypes, contains('elektromotorisch / CO2'));

      final defaultType = RwaOptionsService.getDefault('systemType');
      expect(defaultType, 'elektromotorisch / CO2');

      final einrichtung = RwaOptionsService.einrichtungSettings;
      expect(einrichtung.length, 12);
    });
  });
}
