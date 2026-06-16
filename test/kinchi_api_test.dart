import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/services/kinchi_api_service.dart';

void main() {
  group('KinchiApiService Integration Test', () {
    final apiService = KinchiApiService();

    test('Full API Workflow Test (Login and Fetch Directories)', () async {
      print('🚀 Starting Kinchi API Workflow Test...');

      // 1. Test Login
      const String user = "s.bluemel@konzschaefer.de";
      const String pass = "Konz2006";
      
      print('Attempting login for: $user');
      final loginResult = await apiService.login(user, pass);
      
      expect(loginResult, isTrue, reason: 'Login should succeed with production credentials');
      print('✅ Login successful.');

      // 2. Test Fetching Directories
      print('Fetching directory list...');
      try {
        final directories = await apiService.getDirectories();
        
        expect(directories, isNotNull);
        expect(directories, isA<List>());
        print('✅ Successfully fetched ${directories.length} directories.');

        // 3. Verify Standard ID 520 exists
        final hasStandard = directories.any((d) => d['id'] == 520 || d['id'] == "520");
        if (hasStandard) {
          print('✅ Standard Directory ID 520 found in the cloud.');
        } else {
          print('⚠️ Warning: Standard Directory ID 520 not found in the returned list.');
        }

        // 4. Verify Test ID 562 exists (if applicable)
        final hasTestId = directories.any((d) => d['id'] == 562 || d['id'] == "562");
        if (hasTestId) {
          print('✅ Test Directory ID 562 found in the cloud.');
        } else {
          print('⚠️ Warning: Test Directory ID 562 not found in the returned list.');
        }

      } catch (e) {
        fail('Failed to fetch directories: $e');
      }
    });
  });
}
