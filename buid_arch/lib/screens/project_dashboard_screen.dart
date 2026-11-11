import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project.dart';
import '../navigation/profile_navigation.dart';
import '../navigation/community_navigation.dart';
import 'project_invitations_screen.dart';
import 'project_documents_screen.dart';
import 'project_chats_screen.dart';
import 'project_transactions_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/dashboard_hero.dart';
import '../widgets/dashboard_quick_action.dart';
import '../widgets/notification_action_button.dart';
import '../widgets/community_preview_card.dart';
import 'all_project_files_screen.dart';
import 'project_members_screen.dart';

/// Per-project dashboard, opened by tapping a project card.
/// Minimal, icon-led layout matching the client's reference.
class ProjectDashboardScreen extends StatelessWidget {
  const ProjectDashboardScreen({super.key, required this.project});

  final Project project;

  Future<void> _shareProjectLocation(BuildContext context) async {
    final destination = project.latitude != null && project.longitude != null
        ? '${project.latitude},${project.longitude}'
        : project.location;
    final directions = Uri.https(
      'www.google.com',
      '/maps/dir/',
      {
        'api': '1',
        'destination': destination,
        'travelmode': 'driving',
      },
    );

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: '${project.name}\n${project.location}\n'
              'Google Maps directions: $directions',
          subject: 'Directions to ${project.name}',
        ),
      );
    } on PlatformException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
              content: Text('Could not share the project location.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
        ),
        title: Text(
          project.name,
          style: AppTextStyles.cardTitle.copyWith(
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        actions: const [NotificationActionButton()],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DashboardHero(project: project),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Card(
                color: AppColors.surfaceContainerLow,
                child: ListTile(
                  dense: true,
                  minVerticalPadding: 4,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on_outlined,
                      color: AppColors.secondary,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    project.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Share directions',
                    onPressed: () => _shareProjectLocation(context),
                    icon: const Icon(Icons.share_outlined),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  DashboardQuickAction(
                    icon: Icons.cloud_upload_outlined,
                    label: 'Upload',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ProjectDocumentsScreen(project: project),
                      ),
                    ),
                  ),
                  DashboardQuickAction(
                    icon: Icons.payments_outlined,
                    label: 'Pay',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ProjectTransactionsScreen(project: project),
                      ),
                    ),
                  ),
                  DashboardQuickAction(
                    icon: Icons.groups_outlined,
                    label: 'Team',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProjectMembersScreen(project: project),
                      ),
                    ),
                  ),
                  if (project.isOwner)
                    DashboardQuickAction(
                      icon: Icons.person_add_alt_1_outlined,
                      label: 'Invite',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ProjectInvitationsScreen(project: project),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: CommunityPreviewCard(),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        current: AppTab.projects,
        onTap: (tab) {
          if (tab == AppTab.chat) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ProjectChatsScreen(),
              ),
            );
          } else if (tab == AppTab.files) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AllProjectFilesScreen(returnProject: project),
              ),
            );
          } else if (tab == AppTab.community) {
            CommunityNavigation.open(context);
          } else if (tab == AppTab.profile) {
            ProfileNavigation.open(context);
          }
        },
      ),
    );
  }
}
