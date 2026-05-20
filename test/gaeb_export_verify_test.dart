import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/services/gaeb_export_service.dart';
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
    // 1. Setup mock data with the 5 required parameters and explicit errors
    final List<Map<String, dynamic>> mockExportData = [
      {
        'metadata': {
          'clientName': 'Verification Corp',
          'auftragsnummer': 'TEST-GAEB-001',
          'inspectionId': 101,
        },
        'doors': [
          {
            'doorNumber': 'D-VERIFY-01',
            'material': 'Stahlblech T30',
            'doorFunctionOK': false, // Specifically set to false to check 'Defekt' output
            'floor': 'Erdgeschoss',
            'roomNumber': 'R-0.05',
            'errors': [
              'Obentürschließer verliert Öl',
              'Dichtung im Schwellenbereich fehlt',
              'Zarge locker'
            ],
          }
        ]
      }
    ];

    const String exportName = 'ProofTest';

    test('Proof: GAEB 90 (.d83) correctly writes door parameters and error lines', () async {
      print('\n[TEST] Generating GAEB 90 file...');
      
      final file = await GaebExportService.exportToGaeb90(mockExportData, exportName);
      expect(file, isNotNull);
      
      final content = await file!.readAsString();
      print('[DEBUG] D83 Content Sample:\n$content');

      // Verification of 5 parameters
      expect(content, contains('D-VERIFY-01'), reason: 'Door Number missing');
      expect(content, contains('Stahlblech T30'), reason: 'Material missing');
      expect(content, contains('Erdgeschoss'), reason: 'Floor missing');
      expect(content, contains('R-0.05'), reason: 'Room Number missing');
      expect(content, contains('Status: Defekt'), reason: 'Status mapping incorrect');

      // Proof of Error inclusion (ZA 26 lines)
      expect(content, contains('- Obentürschließer verliert Öl'));
      expect(content, contains('- Dichtung im Schwellenbereich fehlt'));
      expect(content, contains('- Zarge locker'));

      print('✅ GAEB 90 proof successful: Errors found in ZA 26 rows.');
      
      // Cleanup
      if (await file.exists()) await file.delete();
    });

    test('Proof: GAEB XML (.x83) correctly writes door parameters and error join string', () async {
      print('\n[TEST] Generating GAEB XML file...');

      final file = await GaebExportService.exportToGaebXml(mockExportData, exportName);
      expect(file, isNotNull);

      final content = await file!.readAsString();
      print('[DEBUG] XML Content Sample:\n$content');

      // Verification of 5 parameters
      expect(content, contains('RNoPart="D-VERIFY-01"'));
      expect(content, contains('Material: Stahlblech T30'));
      expect(content, contains('Etage: Erdgeschoss'));
      expect(content, contains('Raum: R-0.05'));
      expect(content, contains('<span>Status: Defekt</span>'));

      // Proof of Error inclusion (joined string in XML Text span)
      // The service joins errors with ', '
      expect(content, contains('Obentürschließer verliert Öl, Dichtung im Schwellenbereich fehlt, Zarge locker'),
             reason: 'The joined error string was not found in the XML description block.');

      print('✅ GAEB XML proof successful: Errors found in Description block.');

      // Cleanup
      if (await file.exists()) await file.delete();
    });
  });
}