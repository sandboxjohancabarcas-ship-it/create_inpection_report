import 'door_conflict.dart';

class DoorChangeItem {
  final String doorAlias;
  final String doorNumber;
  final String roomDesignation;
  final String floor;
  final String changeType; // 'new' | 'updated'
  final String? status;
  final int errorCount;
  final int? pos;

  DoorChangeItem({
    required this.doorAlias,
    required this.doorNumber,
    required this.roomDesignation,
    this.floor = '',
    required this.changeType,
    this.status,
    this.errorCount = 0,
    this.pos,
  });

  /// Returns true if this door is marked as inspected/processed.
  bool get isProcessed {
    final s = (status ?? '').trim().toLowerCase();
    return s == 'inspected' ||
        s == 'geprüft' ||
        s == 'completed' ||
        s == 'passed' ||
        s == 'failed' ||
        s == 'done' ||
        s == 'bearbeitet';
  }
}

class InspectionFileReportItem {
  final String fileName;
  final String clientName;
  final String objectAddress;
  final String jobNumber;
  final String inspectionDate;
  final int newDoorsCount;
  final int updatedDoorsCount;
  final int defectsRecordedCount;
  final int attachmentsCount;
  final List<DoorChangeItem> doorChanges;
  final String status;

  InspectionFileReportItem({
    required this.fileName,
    this.clientName = '',
    this.objectAddress = '',
    this.jobNumber = '',
    this.inspectionDate = '',
    this.newDoorsCount = 0,
    this.updatedDoorsCount = 0,
    this.defectsRecordedCount = 0,
    this.attachmentsCount = 0,
    this.doorChanges = const [],
    this.status = 'Erfolgreich',
  });

  int get totalDoors => newDoorsCount + updatedDoorsCount;

  List<DoorChangeItem> get unprocessedDoors =>
      doorChanges.where((d) => !d.isProcessed).toList();
}

class LegacyMigrationAudit {
  final String fileName;
  final int packageVersion;
  final int targetVersion;
  final String jobNumber;
  final String clientName;
  final String objectAddress;
  final String defaultOrderType;
  final String? repairDate;
  final List<String> newFeatures;
  final List<String> convertedProperties;
  final Map<String, int> placeholderDoorProperties;
  final List<String> placeholderSampleDoors;
  final List<String> managerActionHints;

  LegacyMigrationAudit({
    required this.fileName,
    required this.packageVersion,
    required this.targetVersion,
    this.jobNumber = '',
    this.clientName = '',
    this.objectAddress = '',
    this.defaultOrderType = 'Wartung',
    this.repairDate,
    this.newFeatures = const [],
    this.convertedProperties = const [],
    this.placeholderDoorProperties = const {},
    this.placeholderSampleDoors = const [],
    this.managerActionHints = const [],
  });

  bool get isLegacyPackage =>
      packageVersion < targetVersion ||
      convertedProperties.isNotEmpty ||
      newFeatures.isNotEmpty ||
      placeholderDoorProperties.isNotEmpty;

  String generateFormattedReportText() {
    final buffer = StringBuffer();
    buffer.writeln('================================================================================');
    buffer.writeln('  ALTDATEN-KOMPATIBILITÄTS- & MIGRATIONSBERICHT (Legacy Package Audit)');
    buffer.writeln('================================================================================');
    buffer.writeln('• Datei: $fileName');
    buffer.writeln('• Paket-Version: v$packageVersion (Legacy) ➔ Ziel-Version: v$targetVersion (Aktuell)');
    if (jobNumber.isNotEmpty) buffer.writeln('• Auftrag: $jobNumber');
    if (clientName.isNotEmpty) buffer.writeln('• Kunde: $clientName');
    if (objectAddress.isNotEmpty) buffer.writeln('• Liegenschaft: $objectAddress');
    buffer.writeln('• Standard-Auftragsphase: $defaultOrderType');
    if (repairDate != null && repairDate!.isNotEmpty) buffer.writeln('• Reparaturdatum: $repairDate');
    buffer.writeln('--------------------------------------------------------------------------------');

    if (newFeatures.isNotEmpty) {
      buffer.writeln('1. NEUE FUNKTIONEN DER AKTUELLEN VERSION (im Altdaten-Paket nicht enthalten):');
      for (final f in newFeatures) {
        buffer.writeln('   • $f');
      }
      buffer.writeln('--------------------------------------------------------------------------------');
    }

    if (convertedProperties.isNotEmpty) {
      buffer.writeln('2. DURCHGEFÜHRTE ATTRIBUT-KONVERTIERUNGEN & WHITELISTING:');
      for (final c in convertedProperties) {
        buffer.writeln('   • $c');
      }
      buffer.writeln('--------------------------------------------------------------------------------');
    }

    if (placeholderDoorProperties.isNotEmpty) {
      buffer.writeln('3. ZUR MANUELLEN PRÜFUNG / ERGÄNZUNG DURCH DEN MANAGER:');
      placeholderDoorProperties.forEach((prop, count) {
        buffer.writeln('   • $count Tür(en) mit Platzhalter/fehlender Angabe in "$prop"');
      });
      if (placeholderSampleDoors.isNotEmpty) {
        buffer.writeln('   • Beispiel betroffene Türen: ${placeholderSampleDoors.join(', ')}');
      }
      buffer.writeln('--------------------------------------------------------------------------------');
    }

    if (managerActionHints.isNotEmpty) {
      buffer.writeln('4. HANDLUNGSEMPFEHLUNGEN FÜR DEN MANAGER IM MASTER-PORTAL:');
      for (final h in managerActionHints) {
        buffer.writeln('   • $h');
      }
      buffer.writeln('================================================================================');
    }

    return buffer.toString();
  }
}

class ImportReport {
  final String packageName;
  final DateTime importedAt;
  final int newDoorsCount;
  final int updatedDoorsCount;
  final int newInspectionsCount;
  final int updatedInspectionsCount;
  final int totalErrorsImported;
  final int totalAttachmentsImported;
  final List<DoorChangeItem> doorChanges;
  final List<String> newCatalogProposals;
  final List<InspectionFileReportItem> fileReports;
  final List<DoorConflict> doorConflicts;
  final List<LegacyMigrationAudit> legacyAudits;

  ImportReport({
    required this.packageName,
    required this.importedAt,
    required this.newDoorsCount,
    required this.updatedDoorsCount,
    required this.newInspectionsCount,
    required this.updatedInspectionsCount,
    required this.totalErrorsImported,
    required this.totalAttachmentsImported,
    required this.doorChanges,
    required this.newCatalogProposals,
    this.fileReports = const [],
    this.doorConflicts = const [],
    this.legacyAudits = const [],
  });

  int get totalDoorsProcessed => newDoorsCount + updatedDoorsCount;

  /// Returns all doors from the imported package that are in an unprocessed/pending status.
  List<DoorChangeItem> get unprocessedDoors =>
      doorChanges.where((d) => !d.isProcessed).toList();

  /// Whether there are any unprocessed doors in the imported package.
  bool get hasUnprocessedDoors => unprocessedDoors.isNotEmpty;

  /// Whether any legacy packages were audited during this import.
  bool get hasLegacyAudit => legacyAudits.isNotEmpty;

  /// Convenient access to the first legacy audit if present.
  LegacyMigrationAudit? get legacyAudit => legacyAudits.firstOrNull;
}
