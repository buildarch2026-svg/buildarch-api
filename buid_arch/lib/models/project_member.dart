class ProjectMember {
  const ProjectMember({
    required this.userId,
    required this.name,
    required this.role,
    this.designation,
    this.joinedAt,
  });

  final int userId;
  final String name;
  final String role;
  final String? designation;
  final DateTime? joinedAt;

  factory ProjectMember.fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'];
    final name = json['name'];
    final role = json['role'];
    if (userId is! num || name is! String || role is! String) {
      throw const FormatException('The project member response was invalid.');
    }

    return ProjectMember(
      userId: userId.toInt(),
      name: name,
      role: role,
      designation:
          json['designation'] is String ? json['designation'] as String : null,
      joinedAt: DateTime.tryParse(json['joined_at']?.toString() ?? ''),
    );
  }
}
