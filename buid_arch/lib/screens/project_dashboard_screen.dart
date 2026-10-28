import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project.dart';
import 'project_invitations_screen.dart';
import 'project_documents_screen.dart';
import 'project_group_voice_chat_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/dashboard_hero.dart';
import '../widgets/dashboard_quick_action.dart';
import '../widgets/dashboard_section_grid.dart';
import '../widgets/notification_action_button.dart';
import 'all_project_files_screen.dart';
import 'project_members_screen.dart';

/// Per-project dashboard, opened by tapping a project card.
/// Minimal, icon-led layout matching the client's reference.
class ProjectDashboardScreen extends StatelessWidget {
  const ProjectDashboardScreen({super.key, required this.project});

  final Project project;

  void _comingSoon(BuildContext context, String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what - coming soon')));
  }

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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Card(
                color: AppColors.surfaceContainerLow,
                child: ListTile(
                  leading: const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.secondary,
                  ),
                  title: Text(
                    project.location,
                    style: AppTextStyles.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: const Text('Project location'),
                  trailing: IconButton(
                    tooltip: 'Share directions',
                    onPressed: () => _shareProjectLocation(context),
                    icon: const Icon(Icons.share_outlined),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Progress
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress & stages',
                        style: AppTextStyles.bodyMd.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        'Coming soon',
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Quick actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  const DashboardQuickAction(
                    icon: Icons.document_scanner_outlined,
                    label: 'Scan',
                  ),
                  const DashboardQuickAction(
                    icon: Icons.payments_outlined,
                    label: 'Pay',
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
                  const DashboardQuickAction(
                    icon: Icons.more_horiz,
                    label: 'More',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Project members are loaded from the authenticated API.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                color: AppColors.surfaceContainerLow,
                child: ListTile(
                  leading: const Icon(
                    Icons.groups_outlined,
                    color: AppColors.secondary,
                  ),
                  title: Text(
                    'Project team',
                    style: AppTextStyles.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProjectMembersScreen(project: project),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Documents
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: DashboardSectionGrid(
                title: 'Documents',
                tiles: [
                  DashboardTileSpec(
                    icon: Icons.architecture,
                    label: 'Drawings',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProjectDocumentsScreen(
                          project: project,
                          category: 'drawings',
                        ),
                      ),
                    ),
                  ),
                  const DashboardTileSpec(
                      icon: Icons.verified_outlined,
                      label: 'Approvals',
                      iconColor: AppColors.secondary),
                  const DashboardTileSpec(
                      icon: Icons.calculate_outlined, label: 'Estimates'),
                  const DashboardTileSpec(
                      icon: Icons.photo_camera_outlined,
                      label: 'Photos',
                      iconColor: AppColors.secondary),
                  const DashboardTileSpec(
                      icon: Icons.receipt_long_outlined, label: 'Invoices'),
                  DashboardTileSpec(
                      icon: Icons.folder_outlined,
                      label: 'All Files',
                      iconColor: AppColors.secondary,
                      onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProjectDocumentsScreen(project: project),
                            ),
                          )),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        current: AppTab.projects,
        onTap: (tab) {
          if (tab == AppTab.chat) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProjectGroupVoiceChatScreen(project: project),
              ),
            );
          } else if (tab == AppTab.files) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AllProjectFilesScreen(returnProject: project),
              ),
            );
          } else if (tab != AppTab.projects) {
            _comingSoon(context, tab.name);
          }
        },
      ),
    );
  }
}
