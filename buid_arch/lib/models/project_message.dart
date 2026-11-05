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
    this.senderDesignation,
    this.replyToMessageId,
    this.replyTo,
    this.forwardedFromName,
    this.editedAt,
    this.deletedAt,
    this.locationLatitude,
    this.locationLongitude,
    this.locationAddress,
    this.readByUserIds = const [],
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
  final String? senderDesignation;
  final int? replyToMessageId;
  final ProjectMessageQuote? replyTo;
  final String? forwardedFromName;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final double? locationLatitude;
  final double? locationLongitude;
  final String? locationAddress;
  final List<int> readByUserIds;
  final DateTime? createdAt;

  bool get isDeleted => deletedAt != null || messageType == 'deleted';

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
    final replyToMessageId = json['reply_to_message_id'];
    final replyTo = json['reply_to'];

    return ProjectMessage(
      id: id.toInt(),
      body: body as String?,
      messageType: json['message_type'] is String
          ? json['message_type'] as String
          : 'text',
      attachmentName: json['attachment_name'] is String
          ? json['attachment_name'] as String
          : null,
      attachmentMimeType: json['attachment_mime_type'] is String
          ? json['attachment_mime_type'] as String
          : null,
      attachmentSize: attachmentSize is num ? attachmentSize.toInt() : null,
      senderUserId: senderUserId.toInt(),
      senderName: senderName,
      senderDesignation: json['sender_designation'] is String
          ? json['sender_designation'] as String
          : null,
      replyToMessageId:
          replyToMessageId is num ? replyToMessageId.toInt() : null,
      replyTo: replyTo is Map
          ? ProjectMessageQuote.fromJson(Map<String, dynamic>.from(replyTo))
          : null,
      forwardedFromName: json['forwarded_from_name'] is String
          ? json['forwarded_from_name'] as String
          : null,
      editedAt: DateTime.tryParse(json['edited_at']?.toString() ?? ''),
      deletedAt: DateTime.tryParse(json['deleted_at']?.toString() ?? ''),
      locationLatitude: _toDouble(json['location_latitude']),
      locationLongitude: _toDouble(json['location_longitude']),
      locationAddress: json['location_address'] is String
          ? json['location_address'] as String
          : null,
      readByUserIds: json['read_by_user_ids'] is List
          ? (json['read_by_user_ids'] as List)
              .whereType<num>()
              .map((userId) => userId.toInt())
              .toList(growable: false)
          : const [],
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  static double? _toDouble(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}

class ProjectMessageQuote {
  const ProjectMessageQuote({
    required this.id,
    this.body,
    required this.messageType,
    this.attachmentName,
    required this.senderName,
    this.deletedAt,
  });

  final int id;
  final String? body;
  final String messageType;
  final String? attachmentName;
  final String senderName;
  final DateTime? deletedAt;

  factory ProjectMessageQuote.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final senderName = json['sender_name'];
    if (id is! num || senderName is! String) {
      throw const FormatException('The reply message response was invalid.');
    }
    return ProjectMessageQuote(
      id: id.toInt(),
      body: json['body'] is String ? json['body'] as String : null,
      messageType: json['message_type'] is String
          ? json['message_type'] as String
          : 'text',
      attachmentName: json['attachment_name'] is String
          ? json['attachment_name'] as String
          : null,
      senderName: senderName,
      deletedAt: DateTime.tryParse(json['deleted_at']?.toString() ?? ''),
    );
  }
}
