// Junction: errors found on a door during a specific inspection
// This class connects a door inspection (InspectionDoor) with one or more errors
// from the ErrorCatalog. It also supports quantities (e.g. Error A x2).
class InspectionDoorError {
  final int id;                   // Primary key for this record
  final int inspectionDoorId;     // Foreign key to InspectionDoor (which door in which inspection)
  final int errorId;              // Foreign key to ErrorCatalog (which error type)
  final int quantity;             // Number of times this error occurs (e.g. 2 hinges loose)
  final String severity;          // Severity level (Minor, Major, Critical)
  final String notes;             // Inspector notes about this error
  final String resolutionStatus;  // Status of resolution (Open, In Progress, Resolved)

  InspectionDoorError({
    required this.id,
    required this.inspectionDoorId,
    required this.errorId,
    required this.quantity,
    required this.severity,
    required this.notes,
    required this.resolutionStatus,
  });

  // Converts the object into a Map for SQLite persistence
  Map<String, dynamic> toMap() => {
        'id': id,
        'inspectionDoorId': inspectionDoorId,
        'errorId': errorId,
        'quantity': quantity,
        'severity': severity,
        'notes': notes,
        'resolutionStatus': resolutionStatus,
      };

  // Factory constructor to create an object from a Map (retrieved from SQLite)
  factory InspectionDoorError.fromMap(Map<String, dynamic> map) => InspectionDoorError(
        id: map['id'],
        inspectionDoorId: map['inspectionDoorId'],
        errorId: map['errorId'],
        quantity: map['quantity'],
        severity: map['severity'],
        notes: map['notes'],
        resolutionStatus: map['resolutionStatus'],
      );
}
