// Master catalog of errors
class ErrorCatalog {
  final int errorId;
  final String code;
  final String description;
  final String category;

  ErrorCatalog({
    required this.errorId,
    required this.code,
    required this.description,
    required this.category,
  });

  Map<String, dynamic> toMap() => {
        'errorId': errorId,
        'code': code,
        'description': description,
        'category': category,
      };

  factory ErrorCatalog.fromMap(Map<String, dynamic> map) => ErrorCatalog(
        errorId: map['errorId'],
        code: map['code'],
        description: map['description'],
        category: map['category'],
      );
}