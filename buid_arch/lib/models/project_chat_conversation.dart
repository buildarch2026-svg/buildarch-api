import 'project.dart';
import 'project_member.dart';
import 'project_type.dart';

class ProjectChatConversation {
  const ProjectChatConversation({
    required this.id,
    required this.type,
    required this.projectId,
    required this.projectName,
    required this.projectLocation,
    required this.projectType,
    required this.isOwner,
    required this.name,
    required this.unreadCount,
    this.conversationId,
    this.conversationMemberUserId,
    this.projectLatitude,
    this.projectLongitude,
    this.counterpartUserId,
    this.counterpartRole,
    this.counterpartDesignation,
    this.lastMessage,
    this.lastMessageAt,
  });

  final String id;
  final String type;
  final int? conversationId;
  final int? conversationMemberUserId;
  final String projectId;
  final String projectName;
  final String projectLocation;
  final ProjectType projectType;
  final double? projectLatitude;
  final double? projectLongitude;
  final bool isOwner;
  final String name;
  final int? counterpartUserId;
  final String? counterpartRole;
  final String? counterpartDesignation;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  bool get isGroup => type == 'group';

  Project toProject() => Project(
        id: projectId,
        name: projectName,
        location: projectLocation,
        type: projectType,
        isOwner: isOwner,
        latitude: projectLatitude,
        longitude: projectLongitude,
      );

  ProjectMember toCounterpart() => ProjectMember(
        userId: counterpartUserId!,
        name: name,
        role: counterpartRole ?? 'homeOwner',
        designation: counterpartDesignation,
      );

  factory ProjectChatConversation.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final type = json['type'];
    final projectId = json['project_id'];
    final projectName = json['project_name'];
    final projectLocation = json['project_location'];
    final projectTypeValue = json['project_type'];
    final name = json['name'];
    final projectType = ProjectType.values.where(
      (candidate) => candidate.apiValue == projectTypeValue,
    );
    if (id is! String ||
        (type != 'group' && type != 'direct') ||
        projectId == null ||
        projectName is! String ||
        projectLocation is! String ||
        projectType.isEmpty ||
        name is! String) {
      throw const FormatException('The chat list response was invalid.');
    }

    final conversationId = json['conversation_id'];
    final conversationMemberUserId = json['participant_user_id'];
    final counterpartUserId = json['counterpart_user_id'];
    final lastMessage = json['last_message'];
    final lastMessageText = lastMessage is Map
        ? _previewText(Map<String, dynamic>.from(lastMessage))
        : null;
    final unreadCount = json['unread_count'];

    return ProjectChatConversation(
      id: id,
      type: type as String,
      conversationId: conversationId is num ? conversationId.toInt() : null,
      conversationMemberUserId: conversationMemberUserId is num
          ? conversationMemberUserId.toInt()
          : null,
      projectId: projectId.toString(),
      projectName: projectName,
      projectLocation: projectLocation,
      projectType: projectType.first,
      projectLatitude: _toDouble(json['project_latitude']),
      projectLongitude: _toDouble(json['project_longitude']),
      isOwner: json['is_owner'] == true,
      name: name,
      counterpartUserId:
          counterpartUserId is num ? counterpartUserId.toInt() : null,
      counterpartRole: json['counterpart_role'] is String
          ? json['counterpart_role'] as String
          : null,
      counterpartDesignation: json['counterpart_designation'] is String
          ? json['counterpart_designation'] as String
          : null,
      lastMessage: lastMessageText,
      lastMessageAt:
          DateTime.tryParse(json['last_message_at']?.toString() ?? ''),
      unreadCount: unreadCount is num ? unreadCount.toInt() : 0,
    );
  }

  static String? _previewText(Map<String, dynamic> json) {
    if (json['message_type'] == 'deleted') return 'This message was deleted';
    final body = json['body'];
    if (body is String && body.isNotEmpty) return body;
    return switch (json['message_type']) {
      'image' => 'Photo',
      'file' => 'Document',
      'voice' => 'Voice message',
      'location' => 'Location',
      _ => null,
    };
  }

  static double? _toDouble(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}
