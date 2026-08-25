class IntegrityReport {
  final int totalInspections;
  final int totalDoors;
  final int totalJunctions;
  final int totalErrors;
  final int orphanedJunctionsRemoved;
  final int orphanedErrorsRemoved;
  final int missingAliasesRepaired;
  final List<String> repairLogs;
  final DateTime timestamp;

  IntegrityReport({
    required this.totalInspections,
    required this.totalDoors,
    required this.totalJunctions,
    required this.totalErrors,
    required this.orphanedJunctionsRemoved,
    required this.orphanedErrorsRemoved,
    required this.missingAliasesRepaired,
    required this.repairLogs,
    required this.timestamp,
  });

  bool get isHealthy =>
      orphanedJunctionsRemoved == 0 &&
      orphanedErrorsRemoved == 0 &&
      missingAliasesRepaired == 0;
}
