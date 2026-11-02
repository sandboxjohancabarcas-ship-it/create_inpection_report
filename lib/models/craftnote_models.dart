/// Status of an inspection job relative to the Craftnote cloud integration.
enum CraftnoteSyncStatus {
  none,              // Not linked to Craftnote
  readyForDownload,  // Available in Craftnote cloud
  downloaded,        // Downloaded and imported into local SQLite DB
  inProgress,        // Inspection currently underway
  pendingUpload,     // Inspection complete, enqueued for upload (e.g. offline)
  uploaded,          // Successfully synced back to Craftnote
}

extension CraftnoteSyncStatusExt on CraftnoteSyncStatus {
  String toDbString() {
    return name;
  }

  static CraftnoteSyncStatus fromDbString(String? val) {
    if (val == null) return CraftnoteSyncStatus.none;
    for (final s in CraftnoteSyncStatus.values) {
      if (s.name == val) return s;
    }
    return CraftnoteSyncStatus.none;
  }
}

/// Represents a Craftnote Project.
class CraftnoteProject {
  final String id;
  final String name;
  final String orderNumber;
  final String street;
  final String zipcode;
  final String city;
  final String country;
  final String clientName;
  final String? clientEmail;
  final String? clientPhone;
  final String? statusId;
  final bool archived;
  final String? noteContent;

  const CraftnoteProject({
    required this.id,
    required this.name,
    this.orderNumber = '',
    this.street = '',
    this.zipcode = '',
    this.city = '',
    this.country = '',
    this.clientName = '',
    this.clientEmail,
    this.clientPhone,
    this.statusId,
    this.archived = false,
    this.noteContent,
  });

  String get fullAddress {
    final parts = [
      street.trim(),
      [zipcode.trim(), city.trim()].where((p) => p.isNotEmpty).join(' '),
      country.trim(),
    ].where((p) => p.isNotEmpty).toList();
    return parts.join(', ');
  }

  factory CraftnoteProject.fromJson(Map<String, dynamic> json) {
    return CraftnoteProject(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      orderNumber: json['orderNumber']?.toString() ?? '',
      street: json['street']?.toString() ?? '',
      zipcode: json['zipcode']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      country: json['country']?.toString() ?? '',
      clientName: json['clientName']?.toString() ?? '',
      clientEmail: json['clientEmail']?.toString(),
      clientPhone: json['clientPhone']?.toString(),
      statusId: json['statusId']?.toString(),
      archived: json['archived'] == true,
      noteContent: json['noteContent']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'orderNumber': orderNumber,
      'street': street,
      'zipcode': zipcode,
      'city': city,
      'country': country,
      'clientName': clientName,
      'clientEmail': clientEmail,
      'clientPhone': clientPhone,
      'statusId': statusId,
      'archived': archived,
      'noteContent': noteContent,
    };
  }
}

/// Represents a file attached to a Craftnote project.
class CraftnoteFile {
  final String id;
  final String name;
  final String type; // e.g., 'DOCUMENT', 'IMAGE'
  final int? size;
  final int? creationTimestamp;
  final String? folderId;
  final String? downloadUrl;

  const CraftnoteFile({
    required this.id,
    required this.name,
    this.type = 'DOCUMENT',
    this.size,
    this.creationTimestamp,
    this.folderId,
    this.downloadUrl,
  });

  bool get isSqliteDatabase => name.toLowerCase().endsWith('.db');
  bool get isPdfReport => name.toLowerCase().endsWith('.pdf');

  String get formattedSize {
    if (size == null || size == 0) return '0 B';
    if (size! < 1024) return '$size B';
    if (size! < 1024 * 1024) return '${(size! / 1024).toStringAsFixed(1)} KB';
    return '${(size! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory CraftnoteFile.fromJson(Map<String, dynamic> json) {
    return CraftnoteFile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'DOCUMENT',
      size: (json['size'] as num?)?.toInt(),
      creationTimestamp: (json['creationTimestamp'] as num?)?.toInt(),
      folderId: json['folderId']?.toString(),
      downloadUrl: json['downloadUrl']?.toString() ?? json['url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'size': size,
      'creationTimestamp': creationTimestamp,
      'folderId': folderId,
      if (downloadUrl != null) 'downloadUrl': downloadUrl,
    };
  }
}

/// Represents the authenticated user profile in Craftnote (/company/members/me).
class CraftnoteMember {
  final String id;
  final String name;
  final String lastname;
  final String email;
  final String? role;

  const CraftnoteMember({
    required this.id,
    required this.name,
    required this.lastname,
    required this.email,
    this.role,
  });

  String get displayName => '$name $lastname'.trim();

  factory CraftnoteMember.fromJson(Map<String, dynamic> json) {
    return CraftnoteMember(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      lastname: json['lastname']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'lastname': lastname,
      'email': email,
      'role': role,
    };
  }
}

/// Represents an item in the offline pending upload queue.
class CraftnoteUploadQueueItem {
  final int? id;
  final int? inspectionId;
  final String craftnoteProjectId;
  final String packageFilePath;
  final String? pdfFilePath;
  final String queuedAt;
  final int attempts;
  final String? lastError;

  const CraftnoteUploadQueueItem({
    this.id,
    this.inspectionId,
    required this.craftnoteProjectId,
    required this.packageFilePath,
    this.pdfFilePath,
    required this.queuedAt,
    this.attempts = 0,
    this.lastError,
  });

  factory CraftnoteUploadQueueItem.fromMap(Map<String, dynamic> map) {
    return CraftnoteUploadQueueItem(
      id: (map['id'] as num?)?.toInt(),
      inspectionId: (map['inspectionId'] as num?)?.toInt(),
      craftnoteProjectId: map['craftnoteProjectId']?.toString() ?? '',
      packageFilePath: map['packageFilePath']?.toString() ?? '',
      pdfFilePath: map['pdfFilePath']?.toString(),
      queuedAt: map['queuedAt']?.toString() ?? DateTime.now().toIso8601String(),
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      lastError: map['lastError']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'inspectionId': inspectionId,
      'craftnoteProjectId': craftnoteProjectId,
      'packageFilePath': packageFilePath,
      'pdfFilePath': pdfFilePath,
      'queuedAt': queuedAt,
      'attempts': attempts,
      'lastError': lastError,
    };
  }

  CraftnoteUploadQueueItem copyWith({
    int? id,
    int? inspectionId,
    String? craftnoteProjectId,
    String? packageFilePath,
    String? pdfFilePath,
    String? queuedAt,
    int? attempts,
    String? lastError,
  }) {
    return CraftnoteUploadQueueItem(
      id: id ?? this.id,
      inspectionId: inspectionId ?? this.inspectionId,
      craftnoteProjectId: craftnoteProjectId ?? this.craftnoteProjectId,
      packageFilePath: packageFilePath ?? this.packageFilePath,
      pdfFilePath: pdfFilePath ?? this.pdfFilePath,
      queuedAt: queuedAt ?? this.queuedAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }
}
