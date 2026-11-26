class RwaInspectionSetting {
  final int? id;
  final int inspectionRwaId;
  final String settingName; // e.g. "RWA-Klappen", "Feuertaster", "Notstrombatterie", etc.
  final String result; // Normalized: 'OK', 'DEFECT', 'NOT_PRESENT'
  final String rawResult; // Original raw text: 'I.O', '√', 'X', 'n.v', '---'
  final String annotation; // Remarks, e.g. "Bj. 12/2019", "Getauscht 01/25"

  RwaInspectionSetting({
    this.id,
    required this.inspectionRwaId,
    required this.settingName,
    required this.result,
    this.rawResult = '',
    this.annotation = '',
  });

  RwaInspectionSetting copyWith({
    int? id,
    int? inspectionRwaId,
    String? settingName,
    String? result,
    String? rawResult,
    String? annotation,
  }) {
    return RwaInspectionSetting(
      id: id ?? this.id,
      inspectionRwaId: inspectionRwaId ?? this.inspectionRwaId,
      settingName: settingName ?? this.settingName,
      result: result ?? this.result,
      rawResult: rawResult ?? this.rawResult,
      annotation: annotation ?? this.annotation,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'inspectionRwaId': inspectionRwaId,
        'settingName': settingName,
        'result': result,
        'rawResult': rawResult,
        'annotation': annotation,
      };

  factory RwaInspectionSetting.fromMap(Map<String, dynamic> map) =>
      RwaInspectionSetting(
        id: map['id'],
        inspectionRwaId: map['inspectionRwaId'],
        settingName: map['settingName'] ?? '',
        result: map['result'] ?? 'OK',
        rawResult: map['rawResult'] ?? '',
        annotation: map['annotation'] ?? '',
      );

  bool get isOk => result == 'OK';
  bool get isDefect => result == 'DEFECT';
  bool get isNotPresent => result == 'NOT_PRESENT';

  @override
  String toString() =>
      'RwaInspectionSetting(id: $id, setting: $settingName, result: $result, annotation: $annotation)';
}
