class ProjectNotification {
  const ProjectNotification({
    required this.id,
    required this.event,
    required this.title,
    required this.message,
    required this.projectId,
    required this.projectName,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final String event;
  final String title;
  final String message;
  final String projectId;
  final String projectName;
  final bool read;
  final DateTime? createdAt;

  factory ProjectNotification.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final event = json['event'];
    final title = json['title'];
    final message = json['message'];
    final projectId = json['project_id'];
    final projectName = json['project_name'];
    if (id is! String ||
        event is! String ||
        title is! String ||
        message is! String ||
        projectId == null ||
        projectName is! String ||
        json['read'] is! bool) {
      throw const FormatException('The notifications response was invalid.');
    }

    return ProjectNotification(
      id: id,
      event: event,
      title: title,
      message: message,
      projectId: projectId.toString(),
      projectName: projectName,
      read: json['read'] as bool,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  ProjectNotification markRead() => ProjectNotification(
        id: id,
        event: event,
        title: title,
        message: message,
        projectId: projectId,
        projectName: projectName,
        read: true,
        createdAt: createdAt,
      );
}

class ProjectNotificationInbox {
  const ProjectNotificationInbox({
    required this.notifications,
    required this.unreadCount,
  });

  final List<ProjectNotification> notifications;
  final int unreadCount;
}
