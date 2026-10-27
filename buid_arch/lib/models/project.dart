import 'project_type.dart';

class Project {
  Project({
    required this.id,
    required this.name,
    required this.location,
    required this.type,
    this.isOwner = false,
    this.latitude,
    this.longitude,
    this.progress = 0,
    this.photoUrl,
    this.memberRole,
    this.invitedByName,
  });

  final String id;
  final String name;
  final String location;
  final ProjectType type;
  final bool isOwner;
  final double? latitude;
  final double? longitude;

  /// 0.0 - 1.0
  final double progress;
  final String? photoUrl;
  final String? memberRole;
  final String? invitedByName;

  factory Project.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final location = json['location'];
    final typeValue = json['type'];

    if (id == null ||
        name is! String ||
        location is! String ||
        typeValue is! String) {
      throw const FormatException('The project response was invalid.');
    }

    final type = ProjectType.values.where(
      (value) => value.apiValue == typeValue,
    );
    if (type.isEmpty) {
      throw const FormatException('The project type was invalid.');
    }

    final progress = json['progress'];
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    return Project(
      id: id.toString(),
      name: name,
      location: location,
      type: type.first,
      isOwner: json['is_owner'] is bool ? json['is_owner'] as bool : false,
      latitude: latitude is num ? latitude.toDouble() : null,
      longitude: longitude is num ? longitude.toDouble() : null,
      progress: progress is num ? progress.toDouble() : 0,
      photoUrl:
          json['photo_url'] is String ? json['photo_url'] as String : null,
      memberRole:
          json['member_role'] is String ? json['member_role'] as String : null,
      invitedByName: json['invited_by_name'] is String
          ? json['invited_by_name'] as String
          : null,
    );
  }
}
