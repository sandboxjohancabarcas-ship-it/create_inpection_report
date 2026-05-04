class ErrorCatalog {
  final int? errorId;       // null before DB insert (AUTOINCREMENT)
  final String code;
  final String description;
  final String category;

  ErrorCatalog({
    this.errorId,
    required this.code,
    required this.description,
    required this.category,
  });

  Map<String, dynamic> toMap() => {
        if (errorId != null) 'errorId': errorId,
        'code': code,
        'description': description,
        'category': category,
      };

  factory ErrorCatalog.fromMap(Map<String, dynamic> map) => ErrorCatalog(
        errorId: map['errorId'],
        code: map['code'] ?? '',
        description: map['description'] ?? '',
        category: map['category'] ?? '',
      );
}
