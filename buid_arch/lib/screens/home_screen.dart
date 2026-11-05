import 'dart:async';

import 'package:flutter/material.dart';

import '../services/pending_invitation_service.dart';
import '../services/push_notification_service.dart';
import 'invitation_details_screen.dart';
import 'projects_screen.dart';

/// Keeps the existing post-login route while opening the projects experience.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _openPendingInvitation());
    unawaited(PushNotificationService.instance.registerDevice());
  }

  Future<void> _openPendingInvitation() async {
    final token = await PendingInvitationService.instance.read();
    if (!mounted || token == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvitationDetailsScreen(invitationToken: token),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const ProjectsScreen();
  }
}
