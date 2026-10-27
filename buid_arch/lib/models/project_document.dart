class ProjectDocument {
  const ProjectDocument({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    this.category = 'general',
    this.uploadedBy,
    this.createdAt,
  });

  final int id;
  final String name;
  final String mimeType;
  final int size;
  final String category;
  final String? uploadedBy;
  final DateTime? createdAt;

  factory ProjectDocument.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final mimeType = json['mime_type'];
    final size = json['size'];
    if (id is! num || name is! String || mimeType is! String || size is! num) {
      throw const FormatException('The uploaded file response was invalid.');
    }

    return ProjectDocument(
      id: id.toInt(),
      name: name,
      mimeType: mimeType,
      size: size.toInt(),
      category: json['category'] is String
          ? json['category'] as String
          : 'general',
      uploadedBy:
          json['uploaded_by'] is String ? json['uploaded_by'] as String : null,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}
