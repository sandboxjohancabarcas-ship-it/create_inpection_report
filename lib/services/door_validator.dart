import 'package:wartungstool/models/door.dart';
import 'package:wartungstool/models/door_conflict.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DOOR VALIDATOR
// Pure Dart — zero DB calls.
// Two responsibilities:
//   1. validateDoor()       — logical cross-field rules within a single door
//   2. detectConflicts()    — compare incoming door vs. existing Master DB record
// ─────────────────────────────────────────────────────────────────────────────

enum ValidationSeverity { info, warning, error, critical }

class DoorValidationIssue {
  final String field;
  final String ruleCode;
  final String message;
  final ValidationSeverity severity;

  const DoorValidationIssue({
    required this.field,
    required this.ruleCode,
    required this.message,
    required this.severity,
  });
}

class DoorValidator {
  // ───────────────────────────────────────────────────────────────
  // COMPLIANCE METADATA
  // Centralised norm references for safety boolean fields.
  // Kept here so the UI (DoorConflictReviewPage) can display them
  // without embedding legal knowledge in the view layer.
  // ───────────────────────────────────────────────────────────────

  static const Map<String, ComplianceInfo> _safetyFieldCompliance = {
    'escapeDoorControl': ComplianceInfo(
      norm: 'DIN EN 1125 / DIN EN 179',
      riskNote:
          'Änderung der Fluchttürsteuerung: Tür kann ihre gesetzliche Fluchtwegklassifizierung verlieren. '
          'Prüfung nach ArbStättV §4 erforderlich.',
    ),
    'escapeRouteSituation': ComplianceInfo(
      norm: 'ASR A2.3',
      riskNote:
          'Änderung der Fluchtwegsituation: Tür kann als Fluchtweg entfallen. '
          'Gefährdungsbeurteilung nach ArbStättV notwendig.',
    ),
    'escapeRouteSignage': ComplianceInfo(
      norm: 'ASR A1.3',
      riskNote:
          'Änderung der Fluchtwegsbeschilderung: Fehlende Kennzeichnung verstößt gegen §4 ArbStättV.',
    ),
    'panicFunction': ComplianceInfo(
      norm: 'DIN EN 1125',
      riskNote:
          'Änderung der Panikfunktion: Türen in Fluchtwegen müssen DIN EN 1125 Panikbeschläge aufweisen.',
    ),
    'escapeDirectionRespected': ComplianceInfo(
      norm: 'DIN EN 179',
      riskNote:
          'Änderung der Fluchtrichtung: Türen müssen in Fluchtrichtung öffnen (LBO §35).',
    ),
    'lintelHeightUnder1m': ComplianceInfo(
      norm: 'DIN 18650-1',
      riskNote:
          'Änderung der Sturzhöhe: Beeinflusst zulässige Türschließer-Montagepositionen nach DIN 18650.',
    ),
    'closerOnHingeSide': ComplianceInfo(
      norm: 'DIN EN 1154',
      riskNote:
          'Änderung Schließerposition: Beeinflusst Wartungsintervalle und Montagenorm DIN EN 1154.',
    ),
    'closerOnOppositeSide': ComplianceInfo(
      norm: 'DIN EN 1154',
      riskNote:
          'Änderung Schließerposition (Bandgegenseite): Beeinflusst Wartungsintervalle und Montagenorm DIN EN 1154.',
    ),
    'blindCylinder': ComplianceInfo(
      norm: 'DIN 18252',
      riskNote:
          'Änderung Blindzylinder: Beeinflusst Sicherheitsklassifizierung der Schließanlage.',
    ),
    'pzCylinder': ComplianceInfo(
      norm: 'DIN 18252',
      riskNote:
          'Änderung PZ-Zylinder: Beeinflusst Sicherheitsklassifizierung und Schließplankompatibilität.',
    ),
    'fullPanicStandWing': ComplianceInfo(
      norm: 'DIN EN 1125',
      riskNote:
          'Änderung Standflügel-Panikfunktion: Zweiflügelige Fluchttüren erfordern Panikbeschlag am Standflügel nach DIN EN 1125.',
    ),
  };

  // ───────────────────────────────────────────────────────────────
  // 1. LOGICAL CROSS-FIELD VALIDATION (V01–V13)
  // Validates a single door's own data for internal consistency.
  // Returns a list of issues; empty = clean.
  // ───────────────────────────────────────────────────────────────

  static List<DoorValidationIssue> validateDoor(Door door) {
    final issues = <DoorValidationIssue>[];

    // V01: Panic function set → escapeDoorControl must be true
    if (door.panicFunction.isNotEmpty &&
        door.panicFunction.toLowerCase() != 'keine' &&
        !door.escapeDoorControl) {
      issues.add(const DoorValidationIssue(
        field: 'escapeDoorControl',
        ruleCode: 'V01',
        message:
            'Panikfunktion vorhanden, aber Fluchttürsteuerung nicht aktiviert. '
            'DIN EN 1125 erfordert Panikbeschläge nur an gesteuerten Fluchttüren.',
        severity: ValidationSeverity.warning,
      ));
    }

    // V02: escapeDoorControl → escapeRouteSituation should be true
    if (door.escapeDoorControl && !door.escapeRouteSituation) {
      issues.add(const DoorValidationIssue(
        field: 'escapeRouteSituation',
        ruleCode: 'V02',
        message:
            'Fluchttürsteuerung aktiv, aber Fluchtwegsituation nicht bestätigt. '
            'ASR A2.3: Alle gesteuerten Fluchttüren müssen als Fluchtweg ausgewiesen sein.',
        severity: ValidationSeverity.warning,
      ));
    }

    // V03: escapeRouteSituation → escapeRouteSignage should be true
    if (door.escapeRouteSituation && !door.escapeRouteSignage) {
      issues.add(const DoorValidationIssue(
        field: 'escapeRouteSignage',
        ruleCode: 'V03',
        message:
            'Tür ist Fluchtweg, aber Beschilderung fehlt. '
            'ASR A1.3: Fluchtwege müssen mit Rettungszeichen gekennzeichnet sein.',
        severity: ValidationSeverity.warning,
      ));
    }

    // V04: Two-wing door → closing sequence must be set
    if (door.wingCount >= 2 && door.closingSequenceSystem.trim().isEmpty) {
      issues.add(const DoorValidationIssue(
        field: 'closingSequenceSystem',
        ruleCode: 'V04',
        message:
            'Zweiflügelige Tür ohne Schließfolgesteuerung. '
            'DIN EN 1158: Zweiflügelige Brandschutztüren erfordern eine Schließfolgesteuerung.',
        severity: ValidationSeverity.warning,
      ));
    }

    // V05: Both closer sides true simultaneously → physically impossible
    if (door.closerOnHingeSide && door.closerOnOppositeSide) {
      issues.add(const DoorValidationIssue(
        field: 'closerOnHingeSide',
        ruleCode: 'V05',
        message:
            'Schließer kann nicht gleichzeitig auf Band- und Bandgegenseite montiert sein. '
            'Bitte Montageinformation prüfen.',
        severity: ValidationSeverity.warning,
      ));
    }

    // V06: Both cylinders set → redundant, usually one or the other
    if (door.blindCylinder && door.pzCylinder) {
      issues.add(const DoorValidationIssue(
        field: 'blindCylinder',
        ruleCode: 'V06',
        message:
            'Blind- und PZ-Zylinder gleichzeitig markiert. '
            'In der Regel ist nur eine Zylinderart pro Tür verbaut.',
        severity: ValidationSeverity.warning,
      ));
    }

    // V07: Fire-rated door type → escapeDoorControl should be checked
    final lowerType = door.doorType.toLowerCase();
    if ((lowerType.contains('t30') ||
            lowerType.contains('t60') ||
            lowerType.contains('t90') ||
            lowerType.contains('rs')) &&
        !door.escapeDoorControl) {
      issues.add(DoorValidationIssue(
        field: 'escapeDoorControl',
        ruleCode: 'V07',
        message:
            'Brandschutztür (${door.doorType}) ohne Fluchttürsteuerung. '
            'Brandschutztüren in Rettungswegen müssen nach DIN EN 1125/179 gesteuert sein.',
        severity: ValidationSeverity.warning,
      ));
    }

    // V08: Full panic on stand wing → wing count must be >= 2
    if (door.fullPanicStandWing && door.wingCount < 2) {
      issues.add(const DoorValidationIssue(
        field: 'fullPanicStandWing',
        ruleCode: 'V08',
        message:
            'Standflügel-Panikfunktion aktiviert, aber Türflügelanzahl < 2. '
            'DIN EN 1125: Standflügel-Panik gilt nur für zweiflügelige Türen.',
        severity: ValidationSeverity.warning,
      ));
    }

    // V09: Escape direction NOT respected + panic function present → critical
    if (!door.escapeDirectionRespected &&
        door.panicFunction.isNotEmpty &&
        door.panicFunction.toLowerCase() != 'keine') {
      issues.add(const DoorValidationIssue(
        field: 'escapeDirectionRespected',
        ruleCode: 'V09',
        message:
            'Fluchtrichtung nicht eingehalten bei Tür mit Panikfunktion. '
            'LBO §35 und DIN EN 179: Fluchttüren müssen in Fluchtrichtung öffnen. '
            'Sofortige Prüfung erforderlich.',
        severity: ValidationSeverity.warning,
      ));
    }

    // V10: doorAlias must not be empty
    if (door.doorAlias == null || door.doorAlias!.trim().isEmpty) {
      issues.add(const DoorValidationIssue(
        field: 'doorAlias',
        ruleCode: 'V10',
        message:
            'Tür-Alias fehlt. Ohne Alias kann die Tür nicht eindeutig identifiziert werden.',
        severity: ValidationSeverity.error,
      ));
    }

    // V11: doorNumber must not be empty
    if (door.doorNumber.trim().isEmpty) {
      issues.add(const DoorValidationIssue(
        field: 'doorNumber',
        ruleCode: 'V11',
        message: 'Türnummer fehlt. Pflichtfeld für Identifikation und GAEB-Export.',
        severity: ValidationSeverity.error,
      ));
    }

    // V12: floor must not be empty
    if (door.floor.trim().isEmpty) {
      issues.add(const DoorValidationIssue(
        field: 'floor',
        ruleCode: 'V12',
        message:
            'Geschoss fehlt. Ohne Geschossangabe ist die Tür nicht eindeutig lokalisierbar.',
        severity: ValidationSeverity.warning,
      ));
    }

    // V13: lockDimensions format check — should contain a number (e.g. "PZ 92", "PZ 72", "SKG")
    if (door.lockDimensions.isNotEmpty) {
      final hasDigit = RegExp(r'\d').hasMatch(door.lockDimensions);
      final hasLetters = RegExp(r'[a-zA-Z]').hasMatch(door.lockDimensions);
      if (!hasDigit && !hasLetters) {
        issues.add(DoorValidationIssue(
          field: 'lockDimensions',
          ruleCode: 'V13',
          message:
              'Schlossmaß "${door.lockDimensions}" hat unerwartetes Format. '
              'Erwartet z. B. "PZ 92", "PZ 72" oder "SKG".',
          severity: ValidationSeverity.info,
        ));
      }
    }

    return issues;
  }

  // ───────────────────────────────────────────────────────────────
  // 2. CONFLICT DETECTION (incoming vs. existing Master DB record)
  // Returns a list of DoorConflict objects.
  // If the list is empty, the incoming door can be written safely.
  // ───────────────────────────────────────────────────────────────

  static List<DoorConflict> detectConflicts(Door incoming, Door existing) {
    final conflicts = <DoorConflict>[];

    // ── Safety boolean fields (compliance-relevant) ──────────────
    void checkSafety(String field, String label, bool inVal, bool exVal) {
      if (inVal == exVal) return;
      conflicts.add(DoorConflict(
        existingDoor: existing,
        incomingDoor: incoming,
        type: DoorConflictType.safetyFlagChange,
        fieldName: field,
        fieldLabel: label,
        existingValue: exVal ? 'Ja ✓' : 'Nein ✗',
        incomingValue: inVal ? 'Ja ✓' : 'Nein ✗',
        ruleCode: 'SAFETY',
        message:
            'Sicherheitsrelevantes Feld geändert. ${_safetyFieldCompliance[field]?.riskNote ?? ''}',
        compliance: _safetyFieldCompliance[field],
        resolution: DoorResolutionAction.keepExisting, // Always default to safe
      ));
    }

    checkSafety('escapeDoorControl', 'Fluchttürsteuerung',
        incoming.escapeDoorControl, existing.escapeDoorControl);
    checkSafety('escapeRouteSituation', 'Fluchtwegsituation',
        incoming.escapeRouteSituation, existing.escapeRouteSituation);
    checkSafety('escapeRouteSignage', 'Fluchtwegsbeschilderung',
        incoming.escapeRouteSignage, existing.escapeRouteSignage);
    checkSafety('escapeDirectionRespected', 'Fluchtrichtung eingehalten',
        incoming.escapeDirectionRespected, existing.escapeDirectionRespected);
    checkSafety('lintelHeightUnder1m', 'Sturzhöhe < 1 m',
        incoming.lintelHeightUnder1m, existing.lintelHeightUnder1m);
    checkSafety('closerOnHingeSide', 'Schließer Bandseite',
        incoming.closerOnHingeSide, existing.closerOnHingeSide);
    checkSafety('closerOnOppositeSide', 'Schließer Bandgegenseite',
        incoming.closerOnOppositeSide, existing.closerOnOppositeSide);
    checkSafety('blindCylinder', 'Blindzylinder',
        incoming.blindCylinder, existing.blindCylinder);
    checkSafety('pzCylinder', 'PZ-Zylinder',
        incoming.pzCylinder, existing.pzCylinder);
    checkSafety('fullPanicStandWing', 'Panik Standflügel vollständig',
        incoming.fullPanicStandWing, existing.fullPanicStandWing);

    // ── Technical mismatch fields ────────────────────────────────
    void checkTech(String field, String label, String inVal, String exVal) {
      if (inVal.trim() == exVal.trim()) return;
      if (inVal.trim().isEmpty) return; // Don't flag empty incoming as mismatch
      conflicts.add(DoorConflict(
        existingDoor: existing,
        incomingDoor: incoming,
        type: DoorConflictType.technicalMismatch,
        fieldName: field,
        fieldLabel: label,
        existingValue: exVal.isEmpty ? '(leer)' : exVal,
        incomingValue: inVal.isEmpty ? '(leer)' : inVal,
        ruleCode: 'TECH',
        message: 'Technisches Feld "$label" weicht vom Stammdatensatz ab.',
      ));
    }

    void checkTechInt(String field, String label, int inVal, int exVal) {
      if (inVal == exVal) return;
      checkTech(field, label, inVal.toString(), exVal.toString());
    }

    checkTech('doorType', 'Türtyp', incoming.doorType, existing.doorType);
    checkTechInt('wingCount', 'Türflügel', incoming.wingCount, existing.wingCount);
    checkTech('material', 'Material', incoming.material, existing.material);
    checkTech('manufacturer', 'Hersteller', incoming.manufacturer, existing.manufacturer);
    checkTech('dinConfiguration', 'DIN-Anschlag', incoming.dinConfiguration, existing.dinConfiguration);
    checkTech('closerType', 'Türschließer Typ', incoming.closerType, existing.closerType);
    checkTech('closingSequenceSystem', 'Schließfolgesteuerung',
        incoming.closingSequenceSystem, existing.closingSequenceSystem);
    checkTech('lockDimensions', 'Schlossmaß', incoming.lockDimensions, existing.lockDimensions);
    checkTech('floor', 'Geschoss', incoming.floor, existing.floor);
    checkTech('roomNumber', 'Raumnummer', incoming.roomNumber, existing.roomNumber);
    checkTech('roomDesignation', 'Raumbezeichnung',
        incoming.roomDesignation, existing.roomDesignation);
    checkTech('fittingType', 'Beschlagstyp', incoming.fittingType, existing.fittingType);
    checkTech('panicFunction', 'Panikfunktion', incoming.panicFunction, existing.panicFunction);
    checkTech('accessControl', 'Zutrittskontrolle',
        incoming.accessControl, existing.accessControl);

    return conflicts;
  }

  /// Converts logical validation issues (from [validateDoor]) into
  /// [DoorConflict] objects of type [DoorConflictType.logicalViolation]
  /// so they can be displayed in the same [DoorConflictReviewPage].
  static List<DoorConflict> issuesAsConflicts(
      Door door, List<DoorValidationIssue> issues) {
    return issues.map((issue) {
      return DoorConflict(
        existingDoor: null,
        incomingDoor: door,
        type: DoorConflictType.logicalViolation,
        fieldName: issue.field,
        fieldLabel: issue.field,
        existingValue: '',
        incomingValue: '',
        ruleCode: issue.ruleCode,
        message: issue.message,
        // Logical violations default to skip (don't import broken data)
        resolution: DoorResolutionAction.skip,
      );
    }).toList();
  }
}
