import 'dart:math';
import 'package:wartungstool/models/models.dart';
import 'package:wartungstool/services/database_service.dart';

class TestDataGenerator {
  static final Random _random = Random();

  /// Generates a comprehensive set of test data.
  /// [numCustomers] - Number of different physical locations.
  /// [numObjectsPerCustomer] - Number of different physical addresses per client.
  /// [numDoorsPerObject] - Global pool of physical doors per location.
  /// [numInspectionsPerObject] - Number of job runs (points in time) per location.
  static Future<void> generate({
    int numCustomers = 2,
    int numObjectsPerCustomer = 2,
    int numDoorsPerObject = 5,
    int numInspectionsPerObject = 2,
  }) async {
    // Ensure DB is initialized in the current context
    final db = await DatabaseService.getDb();
    print('--- STARTING GENERATION IN DB: ${db.path} ---');

    for (int c = 1; c <= numCustomers; c++) {
      final String clientName = "Industrie GmbH Unit $c";
      for (int o = 1; o <= numObjectsPerCustomer; o++) {
        final String address = "Gewerbestraße $c-$o, 21073 Hamburg";
        print('Creating physical door pool for: $clientName at $address');
        List<int> physicalDoorIds = [];

        // 1. Create the persistent physical Door objects (Physical Reality)
        for (int d = 1; d <= numDoorsPerObject; d++) {
          final String doorNum = "T-0$c-0$o-0$d";
        final door = Door(
          id: null,
          pos: d,
          doorAlias: "$clientName-$address-$doorNum",
          doorNumber: doorNum,
          floor: "EG",
          roomNumber: "R-${100 + d}",
          roomDesignation: d % 2 == 0 ? "Bürotrakt" : "Produktion",
          doorType: "T30",
          wingCount: 1,
          material: "Stahl",
          manufacturer: "Dorma",
          dinConfiguration: "DIN L",
          closerType: "TS93",
          closingSequenceSystem: "None",
          lockDimensions: "72/8",
          closerOnHingeSide: true,
          closerOnOppositeSide: false,
          lintelHeightUnder1m: false,
          escapeDoorControl: false,
          accessControl: "None",
          escapeRouteSituation: true,
          escapeRouteSignage: true,
          blindCylinder: false,
          pzCylinder: true,
          fittingType: "Drücker",
          panicFunction: "E",
          escapeDirectionRespected: true,
          fullPanicStandWing: false,
          doorFunctionOK: true,
        );
        
        final id = await DatabaseService.insertDoor(door);
        physicalDoorIds.add(id);
      }

        // 2. Create historical inspections (Temporal Snapshots)
        for (int i = 1; i <= numInspectionsPerObject; i++) {
          final String jobNum = "AUFTRAG-202$i-C$c-O$o";
          final String date = "202$i-05-20"; // Every May for the last years

          final inspectionId = await DatabaseService.insertInspection({
            'clientName': clientName,
            'objectAddress': address,
            'date': date,
            'contactPerson': "Herr Schmidt",
            'inspectorName': "Prüfingenieur $i",
            'jobNumber': jobNum,
          });

          print('  Generating Job: $jobNum (Historical Date: $date)');

          // 3. Link the same physical doors to this specific job run
          final allCatalog = await DatabaseService.getAllErrorCatalog(status: 'Approved');
          
          for (int doorId in physicalDoorIds) {
            // Simulate different outcomes over time
            final bool isDefective = _random.nextDouble() > 0.6; 
            final String status = isDefective ? 'defective' : 'open';

            final junctionId = await DatabaseService.insertInspectionDoor({
              'inspectionId': inspectionId,
              'doorId': doorId,
              'status': status,
              'notes': isDefective ? "Mangel bei Prüfung am $date festgestellt." : "Funktion geprüft.",
              'attachments': '',
            });

            // 4. Add specific errors for defective doors
            if (isDefective && allCatalog.isNotEmpty) {
              // Link to seeded Error Catalog items (assuming IDs 1-10 exist from seed)
              int errorsToGenerate = _random.nextInt(2) + 1;
              for (int e = 0; e < errorsToGenerate; e++) {
                final randomError = allCatalog[_random.nextInt(allCatalog.length)];
                await DatabaseService.insertInspectionDoorError(InspectionDoorError(
                  id: null,
                  inspectionDoorId: junctionId,
                  errorId: randomError.errorId!, 
                  quantity: 1,
                  severity: 'medium',
                  notes: "Standard-Verschleißprüfung",
                  resolutionStatus: 'open',
                ));
              }
            }
          }
        }
      }
    }

    print('--- TEST DATA GENERATION COMPLETE ---');
  }
}
