import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/services/gaeb_export_service.dart';
import 'package:wartungstool/models/models.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Mock class for PathProvider to handle file system access during unit testing.
/// This allows the test to run without actual OS-specific directory access.
class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    // Use the current project directory for generating test output files
    return Directory.current.path;
  }
}

void main() {
  // Initialize Flutter binding for testing
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Redirect path_provider calls to our mock implementation
    PathProviderPlatform.instance = MockPathProviderPlatform();
  });

  group('GAEB Export Verification - Error Inclusion Proof', () {
    const String exportName = 'ProofTest';

    final Door mockDoor = Door(
      id: 1,
      pos: 1,
      doorAlias: 'D-VERIFY-01',
      doorNumber: 'D-VERIFY-01',
      floor: 'Erdgeschoss',
      roomNumber: 'R-0.05',
      roomDesignation: 'Büro',
      doorType: 'Stahlblech T30',
      wingCount: 1,
      material: 'Stahl',
      manufacturer: 'Dorma',
      dinConfiguration: 'DIN L',
      closerType: 'TS93',
      closingSequenceSystem: 'None',
      lockDimensions: '72/8',
      closerOnHingeSide: true,
      closerOnOppositeSide: false,
      lintelHeightUnder1m: false,
      escapeDoorControl: false,
      accessControl: 'None',
      escapeRouteSituation: true,
      escapeRouteSignage: true,
      blindCylinder: false,
      pzCylinder: true,
      fittingType: 'Drücker',
      panicFunction: 'E',
      escapeDirectionRespected: true,
      fullPanicStandWing: false,
      doorFunctionOK: false,
    );

    final List<Map<String, dynamic>> mockExportData = [
      {
        'door': mockDoor,
        'errors': [
          {'description': 'Obentürschließer verliert Öl', 'code': '3', 'quantity': 1},
          {'description': 'Dichtung im Schwellenbereich fehlt', 'code': '14', 'quantity': 1},
          {'description': 'Zarge locker', 'code': '1', 'quantity': 1}
        ]
      }
    ];

    test('Proof: GAEB 90 (.d83) correctly writes door parameters and error lines', () async {
      print('\n[TEST] Generating GAEB 90 file...');
      
      final service = GaebExportService(
        customer: 'Verification Corp',
        projectName: exportName,
        jobNumber: 'TEST-GAEB-001',
      );

      final file = await service.exportToD83(mockExportData);
      expect(file, isNotNull);
      
      final content = await file.readAsString();
      print('[DEBUG] D83 Content Sample:\n$content');

      // Verification of door number
      expect(content, contains('D-VERIFY-01'), reason: 'Door Number missing');

      // Proof of Error inclusion (ZA 26 lines)
      expect(content, contains('Obentürschließer verliert Öl'));
      expect(content, contains('Dichtung im Schwellenbereich fehlt'));
      expect(content, contains('Zarge locker'));

      print('✅ GAEB 90 proof successful: Errors found in ZA 26 rows.');
      
      // Cleanup
      if (await file.exists()) await file.delete();
    });

    test('Proof: GAEB XML (.x83) correctly writes door parameters and error join string', () async {
      print('\n[TEST] Generating GAEB XML file...');

      final service = GaebExportService(
        customer: 'Verification Corp',
        projectName: exportName,
        jobNumber: 'TEST-GAEB-001',
      );

      final file = await service.exportToXml(mockExportData);
      expect(file, isNotNull);

      final content = await file.readAsString();
      print('[DEBUG] XML Content Sample:\n$content');

      // Verification of door number as ID (hyphens are valid in XML NCName)
      expect(content, contains('ID="D-VERIFY-01"'));
      expect(content, contains('Tür: D-VERIFY-01'));

      // Proof of Error inclusion
      expect(content, contains('Obentürschließer verliert Öl'));
      expect(content, contains('Dichtung im Schwellenbereich fehlt'));
      expect(content, contains('Zarge locker'));

      print('✅ GAEB XML proof successful: Errors found.');

      // Cleanup
      if (await file.exists()) await file.delete();
    });
  });
}