import 'package:flutter/material.dart';

import '../services/auth_session_service.dart';
import '../theme/app_colors.dart';

class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({
    super.key,
    required this.imageUrl,
    required this.displayName,
    this.radius = 22,
  });

  final String? imageUrl;
  final String displayName;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primaryContainer.withAlpha(25),
      child: Text(
        _initials(displayName),
        style: TextStyle(
          color: AppColors.secondary,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.62,
        ),
      ),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return fallback;

    return FutureBuilder<String?>(
      future: AuthSessionService.instance.readToken(),
      builder: (context, snapshot) {
        final token = snapshot.data;
        if (token == null || token.isEmpty) return fallback;
        return CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.primaryContainer.withAlpha(25),
          child: ClipOval(
            child: Image.network(
              imageUrl!,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              headers: {'Authorization': 'Bearer $token'},
              errorBuilder: (_, __, ___) => fallback,
            ),
          ),
        );
      },
    );
  }

  String _initials(String value) {
    final words = value.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return '${words.first.substring(0, 1)}${words[1].substring(0, 1)}'
        .toUpperCase();
  }
}
