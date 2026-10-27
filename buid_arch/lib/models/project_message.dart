class ProjectMessage {
  const ProjectMessage({
    required this.id,
    this.body,
    this.messageType = 'text',
    this.attachmentName,
    this.attachmentMimeType,
    this.attachmentSize,
    required this.senderUserId,
    required this.senderName,
    required this.createdAt,
  });

  final int id;
  final String? body;
  final String messageType;
  final String? attachmentName;
  final String? attachmentMimeType;
  final int? attachmentSize;
  final int senderUserId;
  final String senderName;
  final DateTime? createdAt;

  factory ProjectMessage.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final body = json['body'];
    final senderUserId = json['sender_user_id'];
    final senderName = json['sender_name'];
    if (id is! num ||
        (body != null && body is! String) ||
        senderUserId is! num ||
        senderName is! String) {
      throw const FormatException('The chat message response was invalid.');
    }
    final attachmentSize = json['attachment_size'];

    return ProjectMessage(
      id: id.toInt(),
      body: body as String?,
      messageType:
          json['message_type'] is String ? json['message_type'] as String : 'text',
      attachmentName: json['attachment_name'] is String
          ? json['attachment_name'] as String
          : null,
      attachmentMimeType: json['attachment_mime_type'] is String
          ? json['attachment_mime_type'] as String
          : null,
      attachmentSize: attachmentSize is num ? attachmentSize.toInt() : null,
      senderUserId: senderUserId.toInt(),
      senderName: senderName,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}
