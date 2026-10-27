import 'project.dart';

class ProjectInvitation {
  const ProjectInvitation({
    required this.id,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.token,
    this.acceptedAt,
    this.declinedAt,
    this.revokedAt,
    this.inviterName,
  });

  final int id;
  final String role;
  final String status;
  final String? token;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final DateTime? declinedAt;
  final DateTime? revokedAt;
  final String? inviterName;

  Uri get qrLink => Uri(
        scheme: 'buildarch',
        host: 'invite',
        pathSegments: [token!],
      );

  factory ProjectInvitation.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final role = json['role'];
    final status = json['status'];
    final createdAt = DateTime.tryParse(json['created_at']?.toString() ?? '');
    final expiresAt = DateTime.tryParse(json['expires_at']?.toString() ?? '');

    if (id is! num ||
        role is! String ||
        status is! String ||
        createdAt == null ||
        expiresAt == null) {
      throw const FormatException('The invitation response was invalid.');
    }

    return ProjectInvitation(
      id: id.toInt(),
      role: role,
      status: status,
      token: json['token'] is String ? json['token'] as String : null,
      createdAt: createdAt,
      expiresAt: expiresAt,
      acceptedAt: DateTime.tryParse(json['accepted_at']?.toString() ?? ''),
      declinedAt: DateTime.tryParse(json['declined_at']?.toString() ?? ''),
      revokedAt: DateTime.tryParse(json['revoked_at']?.toString() ?? ''),
      inviterName: json['inviter_name'] is String
          ? json['inviter_name'] as String
          : null,
    );
  }
}

class ProjectInvitationDetails {
  const ProjectInvitationDetails({
    required this.invitation,
    required this.project,
    required this.ownerName,
    required this.canAccept,
  });

  final ProjectInvitation invitation;
  final Project project;
  final String ownerName;
  final bool canAccept;

  factory ProjectInvitationDetails.fromJson(Map<String, dynamic> json) {
    final invitationJson = json['invitation'];
    if (invitationJson is! Map) {
      throw const FormatException('The invitation response was invalid.');
    }
    final invitation = Map<String, dynamic>.from(invitationJson);
    final projectJson = invitation['project'];
    if (projectJson is! Map) {
      throw const FormatException('The invited project response was invalid.');
    }
    final projectData = Map<String, dynamic>.from(projectJson);
    final ownerName = projectData['owner_name'];
    final canAccept = invitation['can_accept'];
    if (ownerName is! String || canAccept is! bool) {
      throw const FormatException('The invitation response was invalid.');
    }
    invitation.remove('project');

    return ProjectInvitationDetails(
      invitation: ProjectInvitation.fromJson(invitation),
      project: Project.fromJson(projectData),
      ownerName: ownerName,
      canAccept: canAccept,
    );
  }
}
