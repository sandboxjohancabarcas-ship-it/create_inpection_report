import 'package:wartungstool/models/door.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DOOR CONFLICT MODEL
// Mirrors the ImportConflict / ConflictResolution pattern from error_catalog.dart
// Extended with compliance metadata for German building law fields.
// ─────────────────────────────────────────────────────────────────────────────

/// Categories of door data conflicts, ordered by severity.
enum DoorConflictType {
  /// Same doorAlias generated for two physically different doors.
  /// Must be resolved before import can proceed.
  identityCollision,

  /// A boolean safety/compliance field changed (DIN EN 1125, DIN EN 179, ASR A2.3).
  /// Auto-flagged regardless of whether the Manager requested a review.
  safetyFlagChange,

  /// A technical specification field (doorType, material, wingCount, etc.) changed.
  /// Requires Manager review but does not block import.
  technicalMismatch,

  /// Inspection metadata (jobNumber, clientName, objectAddress) conflict.
  inspectionMetadata,

  /// A field-level logical rule (V01–V13) is violated within the door itself.
  /// No existing DB record involved — just the incoming data is internally inconsistent.
  logicalViolation,

  /// A dropdown property contains a new value introduced by Inspector not in master options.
  newDropdownOption,
}

/// Severity label for display in the UI.
extension DoorConflictTypeLabel on DoorConflictType {
  String get label {
    switch (this) {
      case DoorConflictType.identityCollision:
        return 'Identitätskonflikt';
      case DoorConflictType.safetyFlagChange:
        return 'Sicherheitsrelevant';
      case DoorConflictType.technicalMismatch:
        return 'Technische Abweichung';
      case DoorConflictType.inspectionMetadata:
        return 'Auftragsdaten';
      case DoorConflictType.logicalViolation:
        return 'Logischer Fehler';
      case DoorConflictType.newDropdownOption:
        return 'Neuer Menüeintrag';
    }
  }

  bool get isBlocking => this == DoorConflictType.identityCollision;
  bool get isSafety => this == DoorConflictType.safetyFlagChange;
}

/// Resolution choices the Manager can make per conflict.
enum DoorResolutionAction {
  /// Keep the existing Master DB record unchanged. (Default — safe choice.)
  keepExisting,

  /// Overwrite the Master DB record with incoming data.
  acceptIncoming,

  /// For identity collisions: save incoming door under a new alias.
  keepBoth,

  /// Manager enters a custom free-text value for the conflicting property.
  customInput,

  /// Do not write anything for this door — skip entirely.
  skip,

  /// Add new value to default/master dropdown options in door_options.json.
  addToMasterOptions,
}

/// German compliance norm reference for safety boolean fields.
class ComplianceInfo {
  final String norm;       // e.g. "DIN EN 1125"
  final String riskNote;   // Human-readable risk description in German

  const ComplianceInfo({required this.norm, required this.riskNote});
}

/// A single detected conflict between an incoming door record and the Master DB.
class DoorConflict {
  /// The existing Master DB record. Null for [DoorConflictType.logicalViolation].
  final Door? existingDoor;

  /// The incoming door (from Excel import or inspector sync).
  final Door incomingDoor;

  /// What kind of conflict this is.
  final DoorConflictType type;

  /// The Door model field name that conflicts (e.g. 'doorType', 'escapeDoorControl').
  final String fieldName;

  /// Human-readable field label in German.
  final String fieldLabel;

  /// String representation of the existing value.
  final String existingValue;

  /// String representation of the incoming value.
  final String incomingValue;

  /// Validation rule code (e.g. 'V04') or conflict category ('IDENTITY', 'SAFETY').
  final String ruleCode;

  /// Human-readable explanation of the conflict.
  final String message;

  /// Source context describing file name and worksheet name (e.g. Blatt: "Türlisten 1.OG").
  final String? sourceContext;

  /// Compliance information — only set for [DoorConflictType.safetyFlagChange].
  final ComplianceInfo? compliance;

  /// The Manager's chosen resolution. Defaults to [DoorResolutionAction.keepExisting].
  DoorResolutionAction resolution;

  /// Only used when [resolution] == [DoorResolutionAction.keepBoth].
  /// The Manager-provided new alias for the incoming door.
  String? newAlias;

  /// Only used when [resolution] == [DoorResolutionAction.customInput].
  /// The Manager-provided custom free-text value.
  String? customValue;

  DoorConflict({
    this.existingDoor,
    required this.incomingDoor,
    required this.type,
    required this.fieldName,
    required this.fieldLabel,
    this.existingValue = '',
    this.incomingValue = '',
    required this.ruleCode,
    required this.message,
    this.sourceContext,
    this.compliance,
    this.resolution = DoorResolutionAction.keepExisting,
    this.newAlias,
    this.customValue,
  });

  /// Display title combining the door alias and field label.
  String get displayTitle {
    final alias = incomingDoor.doorAlias ?? incomingDoor.doorNumber;
    return '$alias — $fieldLabel';
  }
}

/// Holds the result of running [DoorValidator.mergeDoors]:
/// doors that passed cleanly + conflicts that need Manager resolution.
class DoorMergeResult {
  /// Doors with no conflicts — already written to DB or ready to write.
  final List<Door> cleanDoors;

  /// Conflicts requiring Manager review.
  final List<DoorConflict> conflicts;

  /// Detailed protocol logs for the migration decision history.
  final List<String> protocolLogs;

  /// Count breakdown by type for the summary chips.
  int get identityCount => conflicts.where((c) => c.type == DoorConflictType.identityCollision).length;
  int get safetyCount => conflicts.where((c) => c.type == DoorConflictType.safetyFlagChange).length;
  int get technicalCount => conflicts.where((c) => c.type == DoorConflictType.technicalMismatch).length;
  int get logicalCount => conflicts.where((c) => c.type == DoorConflictType.logicalViolation).length;

  bool get hasBlockingConflicts => identityCount > 0;
  bool get hasConflicts => conflicts.isNotEmpty;

  const DoorMergeResult({
    required this.cleanDoors,
    required this.conflicts,
    this.protocolLogs = const [],
  });
}
