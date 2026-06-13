import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/models/door.dart';
import 'package:wartungstool/services/gaeb_export_service.dart';

void main() {
  group('GaebExportService Logic Tests', () {
    final service = GaebExportService(
      customer: 'Test Customer',
      projectName: 'Test Project',
      jobNumber: 'JOB123',
    );

    test('Doors with no errors should be omitted from XML', () {
      final doorWithErrors = Door(
        id: 1,
        pos: 1,
        doorNumber: 'T-01',
        floor: 'EG',
        roomNumber: '101',
        roomDesignation: 'Office',
        doorType: 'T30',
        wingCount: 1,
        material: 'Steel',
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
        fittingType: 'Handle',
        panicFunction: 'E',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: false,
      );

      final doorWithoutErrors = doorWithErrors.copyWith(id: 2, doorNumber: 'T-02');

      final exportData = [
        {
          'door': doorWithErrors,
          'errors': [{'code': '101', 'description': 'Broken Closer'}]
        },
        {
          'door': doorWithoutErrors,
          'errors': [] // No errors
        }
      ];

      final xmlContent = service.generateXmlString(exportData);

      // Assert T-01 is present
      expect(xmlContent, contains('RNoPart="101"'));
      expect(xmlContent, contains('Broken Closer'));
      
      // Assert T-02 is omitted
      expect(xmlContent, isNot(contains('RNoPart="T-02"')));
    });

    test('XML should contain high-impact bold styling for error items', () {
      final exportData = [
        {
          'door': Door(id: 1, pos: 1, doorNumber: 'T-01', floor: 'EG', roomNumber: '101', roomDesignation: 'X', doorType: 'T30', wingCount: 1, material: 'S', manufacturer: 'D', dinConfiguration: 'L', closerType: 'C', closingSequenceSystem: 'N', lockDimensions: 'L', closerOnHingeSide: true, closerOnOppositeSide: false, lintelHeightUnder1m: false, escapeDoorControl: false, accessControl: 'N', escapeRouteSituation: true, escapeRouteSignage: true, blindCylinder: false, pzCylinder: true, fittingType: 'F', panicFunction: 'P', escapeDirectionRespected: true, fullPanicStandWing: false, doorFunctionOK: false),
          'errors': [{'code': 'ERR01', 'description': 'Defect A'}]
        }
      ];

      final xmlContent = service.generateXmlString(exportData);

      expect(xmlContent, contains('<span style="font-weight:bold;">Defect A</span>'));
    });
  });
}
