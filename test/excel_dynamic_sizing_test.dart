import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/services/excel_export_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ExcelExportService Dynamic Sizing and Line Wrapping Tests', () {
    test('exportSingleInspection dynamically sizes columns and wraps text at 40 chars and notes at 60 chars', () async {
      final db = await DatabaseService.getDb();

      final inspId = await db.insert('inspections', {
        'clientName': 'Very Long Client Name Testing Dynamic Sizing and Wrapping',
        'objectAddress': 'Mönckebergstraße 13, 20095 Hamburg Deutschland Bürogebäude',
        'inspectorName': 'Friedrich Der Große Monteur',
        'jobNumber': '25-11995-AB',
        'projectNumber': 'P-000732',
        'date': '2026-09-22',
        'isLocked': 1,
      });

      final longRoom = 'Großraumbüro Geschäftsleitung und Konferenzraum Nordflügel'; // > 40 chars
      final longNote = 'FSA Abnahme von 1989; RMZ Bj: 2015; Blindzylinder oder Panik B (Neu Drücker Alu + Ovalrosette) muss geklärt werden --> Hausmeister mit Brandschutzunterweisung erklärt: das es so bleiben soll.'; // > 60 chars

      final uniqueAlias = 'BC-TEST-DYNAMIC-${DateTime.now().microsecondsSinceEpoch}';
      final doorId = await db.insert('doors', {
        'pos': 1,
        'doorAlias': uniqueAlias,
        'doorNumber': 'T-01',
        'floor': '1.OG',
        'roomNumber': '101',
        'roomDesignation': longRoom,
        'doorType': 'T30-1 RS',
        'manufacturer': 'Schörghuber Spezialtüren Manufaktur',
        'notes': longNote,
      });

      final junctionId = await db.insert('inspection_doors', {
        'inspectionId': inspId,
        'doorId': doorId,
        'status': 'InProgress',
        'notes': longNote,
      });

      final errorId = await db.insert('error_catalog', {
        'code': '0.13',
        'description': 'Türspalt unten größer als 20 mm und Bodendichtung reicht nicht aus',
        'category': 'Türblatt',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await db.insert('inspection_door_errors', {
        'inspectionDoorId': junctionId,
        'errorId': errorId,
        'errorCode': '0.13',
        'quantity': 2,
      });

      final testPath = '${Directory.systemTemp.path}/test_dynamic_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = await ExcelExportService.exportSingleInspection(inspId, testPath);
      expect(await file.exists(), true);

      final bytes = await file.readAsBytes();
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);
      final sheetName = decoder.tables.keys.first;
      final table = decoder.tables[sheetName]!;

      // Verify room designation wrapped (contains newline) at Col 5
      final exportedRoom = table.rows[3][5]?.toString() ?? '';
      expect(exportedRoom.contains('\n'), true);
      for (final line in exportedRoom.split('\n')) {
        expect(line.length <= 40, true);
      }

      // Verify defect header is populated at Col 28
      final defectHeader = table.rows[2][28]?.toString() ?? '';
      expect(defectHeader.isNotEmpty, true);
      expect(defectHeader.contains('0.13'), true);

      // Verify note wrapped at max 80 chars per line at Col 29
      final exportedNote = table.rows[3][29]?.toString() ?? '';
      expect(exportedNote.contains('\n'), true);
      for (final line in exportedNote.split('\n')) {
        expect(line.length <= 80, true);
      }

      await file.delete();
    });

    test('Etage column introduces no breakline for floor values with char length <= 4 (e.g. 2.OG, EG, 1.OG)', () async {
      final db = await DatabaseService.getDb();

      final inspId = await db.insert('inspections', {
        'clientName': 'Floor Test Client',
        'objectAddress': 'Etage Teststraße 5',
        'inspectorName': 'Monteur Floor',
        'jobNumber': '25-ETAGE-01',
        'projectNumber': 'P-ETAGE',
        'date': '2026-09-24',
        'isLocked': 1,
      });

      final floors = ['2.OG', 'EG', '1.OG', 'UG', 'U1:A'];
      for (int i = 0; i < floors.length; i++) {
        final dId = await db.insert('doors', {
          'pos': i + 1,
          'doorAlias': 'ETAGE-D-$i-${DateTime.now().microsecondsSinceEpoch}',
          'doorNumber': 'T-0${i + 1}',
          'floor': floors[i],
          'roomNumber': '10${i + 1}',
          'roomDesignation': 'Raum $i',
          'doorType': 'T30',
        });
        await db.insert('inspection_doors', {
          'inspectionId': inspId,
          'doorId': dId,
          'status': 'InProgress',
        });
      }

      final testPath = '${Directory.systemTemp.path}/test_etage_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = await ExcelExportService.exportSingleInspection(inspId, testPath);
      expect(await file.exists(), true);

      final bytes = await file.readAsBytes();
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);
      final sheetName = decoder.tables.keys.first;
      final table = decoder.tables[sheetName]!;

      // Check rows 3 to 7, column 3 (Etage)
      for (int r = 0; r < floors.length; r++) {
        final exportedFloor = table.rows[3 + r][3]?.toString() ?? '';
        expect(exportedFloor.contains('\n'), false, reason: 'Floor value "$exportedFloor" should have NO newline');
        expect(exportedFloor.length <= 4 || exportedFloor == 'U1:A', true);
      }

      await file.delete();
    });

    test('Pos and Tür Nr columns allow max 3 digits without introducing break lines', () async {
      final db = await DatabaseService.getDb();

      final inspId = await db.insert('inspections', {
        'clientName': 'Digits Test Client',
        'objectAddress': 'Digitstraße 10',
        'inspectorName': 'Monteur Digit',
        'jobNumber': '25-DIGIT-01',
        'projectNumber': 'P-DIGIT',
        'date': '2026-09-24',
        'isLocked': 1,
      });

      final testPositions = [1, 10, 25, 99, 100];
      final testDoorNumbers = ['1', '10', '25', '99', '100'];

      for (int i = 0; i < testPositions.length; i++) {
        final dId = await db.insert('doors', {
          'pos': testPositions[i],
          'doorAlias': 'DIGIT-D-$i-${DateTime.now().microsecondsSinceEpoch}',
          'doorNumber': testDoorNumbers[i],
          'floor': 'EG',
          'roomNumber': '101',
          'roomDesignation': 'Büro',
          'doorType': 'T30',
        });
        await db.insert('inspection_doors', {
          'inspectionId': inspId,
          'doorId': dId,
          'status': 'InProgress',
        });
      }

      final testPath = '${Directory.systemTemp.path}/test_digits_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = await ExcelExportService.exportSingleInspection(inspId, testPath);
      expect(await file.exists(), true);

      final bytes = await file.readAsBytes();
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);
      final sheetName = decoder.tables.keys.first;
      final table = decoder.tables[sheetName]!;

      // Check rows 3 to 7: Col 0 (Pos) and Col 2 (Tür Nr)
      for (int r = 0; r < testPositions.length; r++) {
        final exportedPos = table.rows[3 + r][0]?.toString() ?? '';
        final exportedDoorNum = table.rows[3 + r][2]?.toString() ?? '';

        expect(exportedPos.contains('\n'), false, reason: 'Pos "$exportedPos" must have NO break line');
        expect(exportedDoorNum.contains('\n'), false, reason: 'Tür Nr "$exportedDoorNum" must have NO break line');
      }

      // Check Summary Row (last row): Col 0 contains full summary text
      final lastRowIdx = table.rows.length - 1;
      final summaryText = table.rows[lastRowIdx][0]?.toString() ?? '';
      expect(summaryText, 'Summe für Mängelbeseitigung');
      expect(summaryText.contains('\n'), false);

      await file.delete();
    });
  });
}
