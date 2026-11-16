import 'package:flutter/material.dart';
import 'door_conflict.dart';

class AssetTypeHelper {
  static String getLabel(String assetType, {bool plural = false}) {
    switch (assetType.toLowerCase()) {
      case 'window':
        return 'Fenster';
      case 'schiebetor':
        return plural ? 'Schiebetore' : 'Schiebetor';
      case 'rwa':
      case 'rwa-anlage':
        return plural ? 'RWA-Anlagen' : 'RWA-Anlage';
      case 'tor':
        return plural ? 'Tore' : 'Tor';
      case 'mixed':
        return plural ? 'Objekte' : 'Objekt';
      case 'door':
      default:
        return plural ? 'Türen' : 'Tür';
    }
  }

  static IconData getIcon(String assetType) {
    switch (assetType.toLowerCase()) {
      case 'window':
        return Icons.window;
      case 'schiebetor':
        return Icons.sensor_door;
      case 'rwa':
      case 'rwa-anlage':
        return Icons.air;
      case 'tor':
        return Icons.garage;
      case 'mixed':
        return Icons.category;
      case 'door':
      default:
        return Icons.door_front_door;
    }
  }
}

class DoorChangeItem {
  final String doorAlias;
  final String doorNumber;
  final String roomDesignation;
  final String floor;
  final String changeType; // 'new' | 'updated'
  final String? status;
  final int errorCount;
  final int? pos;
  final String assetType; // 'door' | 'window' | ...

  DoorChangeItem({
    required this.doorAlias,
    required this.doorNumber,
    required this.roomDesignation,
    this.floor = '',
    this.changeType = 'updated',
    this.status,
    this.errorCount = 0,
    this.pos,
    this.assetType = 'door',
  });

  bool get isWindow => assetType.toLowerCase() == 'window';

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
  final int newWindowsCount;
  final int updatedWindowsCount;
  final String assetType;
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
    this.newWindowsCount = 0,
    this.updatedWindowsCount = 0,
    this.assetType = 'door',
    this.defectsRecordedCount = 0,
    this.attachmentsCount = 0,
    this.doorChanges = const [],
    this.status = 'Erfolgreich',
  });

  int get totalDoors => newDoorsCount + updatedDoorsCount;
  int get totalWindows => newWindowsCount + updatedWindowsCount;
  int get totalItems => isWindow ? (totalWindows > 0 ? totalWindows : totalDoors) : totalDoors;
  int get newItemsCount => isWindow ? (newWindowsCount > 0 ? newWindowsCount : newDoorsCount) : newDoorsCount;
  int get updatedItemsCount => isWindow ? (updatedWindowsCount > 0 ? updatedWindowsCount : updatedDoorsCount) : updatedDoorsCount;
  bool get isWindow => assetType.toLowerCase() == 'window' || (newWindowsCount + updatedWindowsCount > 0 && newDoorsCount + updatedDoorsCount == 0);

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
  final int newWindowsCount;
  final int updatedWindowsCount;
  final int newInspectionsCount;
  final int updatedInspectionsCount;
  final int totalErrorsImported;
  final int totalAttachmentsImported;
  final List<DoorChangeItem> doorChanges;
  final List<String> newCatalogProposals;
  final List<InspectionFileReportItem> fileReports;
  final List<DoorConflict> doorConflicts;
  final List<LegacyMigrationAudit> legacyAudits;
  final String assetType;

  ImportReport({
    required this.packageName,
    required this.importedAt,
    this.newDoorsCount = 0,
    this.updatedDoorsCount = 0,
    this.newWindowsCount = 0,
    this.updatedWindowsCount = 0,
    this.newInspectionsCount = 0,
    this.updatedInspectionsCount = 0,
    this.totalErrorsImported = 0,
    this.totalAttachmentsImported = 0,
    this.doorChanges = const [],
    this.newCatalogProposals = const [],
    this.fileReports = const [],
    this.doorConflicts = const [],
    this.legacyAudits = const [],
    this.assetType = 'door',
  });

  String get effectiveAssetType {
    if (assetType.isNotEmpty && assetType.toLowerCase() != 'door') return assetType;
    final hasWin = (newWindowsCount + updatedWindowsCount > 0) ||
        fileReports.any((f) => f.isWindow) ||
        doorChanges.any((d) => d.isWindow);
    final hasDoor = (newDoorsCount + updatedDoorsCount > 0) ||
        fileReports.any((f) => !f.isWindow) ||
        doorChanges.any((d) => !d.isWindow);

    if (hasWin && !hasDoor) return 'window';
    if (hasWin && hasDoor) return 'mixed';
    return assetType.isNotEmpty ? assetType : 'door';
  }

  bool get isWindowReport => effectiveAssetType == 'window';

  int get totalDoorsProcessed => newDoorsCount + updatedDoorsCount;
  int get totalWindowsProcessed => newWindowsCount + updatedWindowsCount;

  int get totalItemsProcessed {
    if (effectiveAssetType == 'window') {
      return totalWindowsProcessed > 0 ? totalWindowsProcessed : totalDoorsProcessed;
    }
    if (effectiveAssetType == 'mixed') {
      return totalDoorsProcessed + totalWindowsProcessed;
    }
    return totalDoorsProcessed > 0 ? totalDoorsProcessed : totalWindowsProcessed;
  }

  int get newItemsCount {
    if (effectiveAssetType == 'window') {
      return newWindowsCount > 0 ? newWindowsCount : newDoorsCount;
    }
    return newDoorsCount + newWindowsCount;
  }

  int get updatedItemsCount {
    if (effectiveAssetType == 'window') {
      return updatedWindowsCount > 0 ? updatedWindowsCount : updatedDoorsCount;
    }
    return updatedDoorsCount + updatedWindowsCount;
  }

  /// Returns all doors/items from the imported package that are in an unprocessed/pending status.
  List<DoorChangeItem> get unprocessedDoors =>
      doorChanges.where((d) => !d.isProcessed).toList();

  /// Whether there are any unprocessed doors/items in the imported package.
  bool get hasUnprocessedDoors => unprocessedDoors.isNotEmpty;

  /// Whether any legacy packages were audited during this import.
  bool get hasLegacyAudit => legacyAudits.isNotEmpty;

  /// Convenient access to the first legacy audit if present.
  LegacyMigrationAudit? get legacyAudit => legacyAudits.firstOrNull;
}
