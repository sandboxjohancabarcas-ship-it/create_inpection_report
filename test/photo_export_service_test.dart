import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/photo_export_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseService.clearDatabase();
  });

  test('PhotoExportService exports all pictures with [door alias]_Fehler_[error code]_[index].jpg naming', () async {
    final tempDir = Directory.systemTemp.createTempSync('photo_export_test_');

    try {
      // 1. Create an inspection
      final inspId = await DatabaseService.insertInspection({
        'clientName': 'Wentzel Dr',
        'objectAddress': 'Hammerbrookstraße 63',
        'jobNumber': '26-14078-AB',
        'projectNumber': 'P-000331',
        'date': '2026-10-05',
        'orderType': 'Wartung',
      });

      // 2. Insert two doors
      final door1Id = await DatabaseService.insertDoor(Door(
        id: null,
        pos: 1,
        doorAlias: '000331-1-EG-101',
        doorNumber: '101',
        floor: 'EG',
        roomNumber: '1.01',
        roomDesignation: 'Büro',
        doorType: 'T30',
        wingCount: 1,
        material: 'Holz',
        manufacturer: 'Schörghuber',
        dinConfiguration: 'DIN links',
        closerType: 'Obentürschließer',
        closingSequenceSystem: '',
        lockDimensions: '',
        closerOnHingeSide: false,
        closerOnOppositeSide: false,
        lintelHeightInsideOver1m: false,
        lintelHeightOutsideOver1m: false,
        escapeDoorControl: '',
        accessControl: '',
        escapeRouteSituation: false,
        escapeRouteSignage: false,
        blindCylinder: false,
        pzCylinder: false,
        fittingType: '',
        panicFunction: '',
        escapeDirectionRespected: false,
        fullPanicStandWing: false,
        doorFunctionOK: true,
        approvalNumber: '',
        manufacturerNumber: '',
        dopNumber: '',
        manufactureYear: '',
        notes: '',
      ));

      final junction1Id = await DatabaseService.insertInspectionDoor({
        'inspectionId': inspId,
        'doorId': door1Id,
        'status': 'Inspected',
        'notes': '',
      });

      // 3. Create sample base64 images
      final dummyBytes1 = Uint8List.fromList([1, 2, 3, 4, 5]);
      final dummyBytes2 = Uint8List.fromList([6, 7, 8, 9, 10]);
      final b64_1 = base64Encode(dummyBytes1);
      final b64_2 = base64Encode(dummyBytes2);

      // 4. Attach errors with photos
      await DatabaseService.insertInspectionDoorError(InspectionDoorError(
        inspectionDoorId: junction1Id,
        errorId: 1,
        errorCode: '1.1.1',
        quantity: 1,
        severity: 'medium',
        notes: '',
        attachments: '$b64_1,$b64_2',
      ));

      // 5. Run photo export
      final result = await PhotoExportService.exportInspectionPhotos(
        inspectionId: inspId,
        destinationDir: tempDir.path,
        isManagerMode: true,
      );

      expect(result.totalPhotos, equals(2));
      expect(result.exportedFileNames, contains('000331-1-EG-101_Fehler_1.1.1_1.jpg'));
      expect(result.exportedFileNames, contains('000331-1-EG-101_Fehler_1.1.1_2.jpg'));

      final file1 = File('${tempDir.path}/000331-1-EG-101_Fehler_1.1.1_1.jpg');
      final file2 = File('${tempDir.path}/000331-1-EG-101_Fehler_1.1.1_2.jpg');
      expect(file1.existsSync(), isTrue);
      expect(file2.existsSync(), isTrue);
      expect(file1.readAsBytesSync(), equals(dummyBytes1));
      expect(file2.readAsBytesSync(), equals(dummyBytes2));
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  });
}
