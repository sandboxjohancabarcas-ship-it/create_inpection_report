import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';
import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Service to parse PDF OCR data and populate the database for test/real data generation.
/// Aligns real-world PDF reports with the "Door-as-Patient" model and CSV Error Catalog.
class CustomerDataImporter {
  /// Mapping of PDF Error Columns (1-10) to the CSV "Source of Truth" Codes.
  /// Non-mapped columns are skipped unless added to the CSV.
  static const Map<int, String> _pdfColToCatalogCode = {
    1: "3",   // 0.32 (Unzulässige Feststellung) -> CSV 3
    2: "14",  // 0.15 (Kennzeichnungsschild) -> CSV 14
    3: "9",   // 0.20 (Fluchtweg/Schilder) -> CSV 9
    7: "7",   // 7.8 (Rauchschalter/RMZ) -> CSV 7
    10: "1",  // 0.10 (Kein Zugang) -> CSV 1
  };

  // Known static values for normalization to prevent MVP crashes
  static const List<String> _knownManufacturers = ['Dorma', 'Geze', 'Schüco', 'Jeld Wen', 'Schröders', 'Würth', 'Küffner', 'Eco Schulte'];
  static const List<String> _knownMaterials = ['Holz', 'Alu', 'Stahl', 'Rohrrahmen', 'Glas'];
  static const List<String> _knownCloserTypes = ['TS 93', 'TS 5000', 'TS 31', 'TS 2000', 'TS 98', 'RMZ', 'GSR'];

  /// Reads a physical PDF file and extracts text before starting the mapping process.
  static Future<void> importFromPdfFile(File pdfFile) async {
    final List<int> bytes = await pdfFile.readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final String text = PdfTextExtractor(document).extractText();
    document.dispose();
    await importFromOcr(text);
  }

  /// Main entry point to process OCR text from an inspection protocol.
  static Future<void> importFromOcr(String ocrText) async {
    final header = _extractHeader(ocrText);
    
    // 1. Create the Inspection record
    final inspectionId = await DatabaseService.insertInspection({
      'clientName': header['Kunde'] ?? 'Stadt Geesthacht',
      'objectAddress': header['Objekt'] ?? 'Unbekannt',
      'date': header['Datum'] ?? '2025-02-24',
      'contactPerson': header['Ansprechpartner'] ?? 'Herr Basau',
      'inspectorName': header['Monteur'] ?? 'Gert',
      'jobNumber': header['Auftragsnummer'] ?? '25-12115-AB',
    });

    // 2. Parse Rows and generate Doors/Errors
    await _processRows(ocrText, inspectionId, header);
  }

  static Map<String, String> _extractHeader(String ocr) {
    final String firstPage = ocr.contains('==End of OCR for page 1==') ? ocr.split('==End of OCR for page 1==').first : ocr;
    return {
      'Kunde': RegExp(r"Kunde:\s*(.*?)(?=Objekt:|$)").firstMatch(firstPage)?.group(1)?.trim() ?? 'Stadt Geesthacht',
      'Objekt': RegExp(r"Objekt:\s*(.*?)(?=Datum:|$)").firstMatch(firstPage)?.group(1)?.trim() ?? 'Fam. Zentrum Regenbogen',
      'Datum': RegExp(r"Datum:\s*(\d{2}\.\d{2}\.\d{4})").firstMatch(firstPage)?.group(1) ?? '24.02.2025',
      'Ansprechpartner': RegExp(r"Ansprechpartner:\s*(.*?)(?=Monteur:|$)").firstMatch(firstPage)?.group(1)?.trim() ?? 'Herr Basau',
      'Monteur': RegExp(r"Monteur:\s*(.*?)(?=Auftragsnummer:|$)").firstMatch(firstPage)?.group(1)?.trim() ?? 'Gert',
      'Auftragsnummer': RegExp(r"Auftragsnummer:\s*([\w-]+)").firstMatch(firstPage)?.group(1) ?? '25-12115-AB',
    };
  }

  /// Sanitizes string where the OCR might duplicate words (e.g. "Lagerraum Lagerraum")
  static String _sanitizeValue(String value) {
    if (value.isEmpty) return '';
    final parts = value.split(' ');
    if (parts.length >= 2 && parts[0] == parts[1]) {
      return parts[0];
    }
    return value;
  }

  static Future<void> _processRows(String ocr, int inspectionId, Map<String, String> header) async {
    final lines = ocr.split('\n');
    final rowPattern = RegExp(r"^(\d+)\s+(\d+-?)\s+"); 

    final catalog = await DatabaseService.getAllErrorCatalog();
    int doorCount = 0;

    for (var line in lines) {
      final trimmed = line.trim();
      final match = rowPattern.firstMatch(trimmed);
      if (match == null || doorCount >= 10) continue;

      final int pos = int.parse(match.group(1)!);
      final String doorNum = match.group(2)!;
      final tokens = trimmed.split(RegExp(r"\s+"));

      // Pivot Logic: Find the status column 'J' or 'N'
      final pivotIndex = tokens.indexWhere((t) => t == 'J' || t == 'N');
      if (pivotIndex == -1) continue;

      doorCount++;

      // Fallback Search Helpers for robustness
      String findManufacturer(String text) => _knownManufacturers.firstWhere((m) => text.contains(m), orElse: () => "Unbekannt");
      String findMaterial(String text) => _knownMaterials.firstWhere((m) => text.contains(m), orElse: () => "Unbekannt");
      String findCloser(String text) => _knownCloserTypes.firstWhere((c) => text.contains(c), orElse: () => "None");

      // Map properties based on token positions before the pivot
      // Persistent Identity: {Kunde}-{Objekt}-{DoorNumber}
      final door = Door(
        id: null,
        pos: pos,
        doorAlias: Door.generateAlias(header['Kunde'] ?? '', header['Objekt'] ?? '', doorNum),
        doorNumber: doorNum,
        floor: tokens.length > 2 ? tokens[2] : 'EG',
        roomNumber: '',
        roomDesignation: pivotIndex > 4 ? _sanitizeValue(tokens[4]) : 'Raum',
        doorType: trimmed.contains('T30') ? 'T30' : 'MZT',
        wingCount: trimmed.contains(' 2 ') ? 2 : 1,
        material: findMaterial(trimmed),
        manufacturer: findManufacturer(trimmed),
        dinConfiguration: trimmed.contains('DIN L') ? 'DIN L' : 'DIN R',
        closerType: findCloser(trimmed),
        closingSequenceSystem: trimmed.contains('GSR') ? 'GSR' : 'None',
        lockDimensions: 'Standard',
        closerOnHingeSide: trimmed.contains(' X '),
        closerOnOppositeSide: false,
        lintelHeightUnder1m: false,
        escapeDoorControl: false,
        accessControl: 'None',
        escapeRouteSituation: true,
        escapeRouteSignage: trimmed.contains(' X '),
        blindCylinder: false,
        pzCylinder: true,
        fittingType: 'Drücker',
        panicFunction: 'E',
        escapeDirectionRespected: true,
        fullPanicStandWing: false,
        doorFunctionOK: tokens[pivotIndex] == 'J',
      );

      final doorId = await DatabaseService.insertDoor(door);
      
      final junctionId = await DatabaseService.insertInspectionDoor({
        'inspectionId': inspectionId,
        'doorId': doorId,
        'status': door.doorFunctionOK ? 'open' : 'defective', 
        'notes': 'Importiert aus Protokoll Pos $pos',
      });

      // Analyze tokens after the pivot (Error counts)
      final errorTokens = tokens.sublist(pivotIndex + 1);
      await _mapErrorsToJunction(errorTokens, junctionId, catalog);
    }
  }

  static Future<void> _mapErrorsToJunction(List<String> errorTokens, int junctionId, List<ErrorCatalog> catalog) async {
    for (int i = 0; i < errorTokens.length; i++) {
      final int colNum = i + 1;
      final String val = errorTokens[i];

      if (_pdfColToCatalogCode.containsKey(colNum) && (val == '1' || val == '2')) {
        final String csvCode = _pdfColToCatalogCode[colNum]!;
        try {
          final errorItem = catalog.firstWhere((e) => e.code == csvCode);
          await DatabaseService.insertInspectionDoorError(InspectionDoorError(
            inspectionDoorId: junctionId,
            errorId: errorItem.errorId,
            quantity: 1,
            severity: errorItem.severity,
            notes: 'Importiert (PDF Spalte $colNum)',
          ));
        } catch (_) {}
      }
      if (colNum >= 10) break;
    }
  }
}