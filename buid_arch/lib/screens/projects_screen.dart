import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../services/auth_session_service.dart';
import '../services/projects_store.dart';
import '../services/user_role_service.dart';
import '../navigation/profile_navigation.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/project_card.dart';
import '../widgets/notification_action_button.dart';
import 'create_project_screen.dart';
import 'project_dashboard_screen.dart';

/// "Your Projects" - the home owner's landing screen after login/unlock.
/// Shows an empty state until the first project is created.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, this.initialTabIndex = 0})
      : assert(initialTabIndex >= 0 && initialTabIndex < 2);

  final int initialTabIndex;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  AppRole? _userRole;
  bool _isLoadingRole = true;
  bool _roleLoadFailed = false;

  @override
  void initState() {
    super.initState();
    ProjectsStore.instance.addListener(_onStoreChanged);
    ProjectsStore.instance.load(refresh: true);
    _loadUserRole();
  }

  @override
  void dispose() {
    ProjectsStore.instance.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() => setState(() {});

  Future<void> _loadUserRole() async {
    try {
      var role = await UserRoleService.instance.read();
      if (role == null) {
        final user = await AuthSessionService.instance.readUser();
        final savedRole = user?['role'];
        for (final candidate in AppRole.values) {
          if (candidate.name == savedRole) {
            role = candidate;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _userRole = role;
        _isLoadingRole = false;
        _roleLoadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingRole = false;
        _roleLoadFailed = true;
      });
    }
  }

  void _openCreateProject() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateProjectScreen()),
    );
  }

  Future<void> _openProfile() async {
    await ProfileNavigation.open(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = ProjectsStore.instance;

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          surfaceTintColor: AppColors.surface,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            'Projects',
            style: AppTextStyles.cardTitle.copyWith(
              fontSize: 18,
              color: AppColors.textPrimary,
            ),
          ),
          actions: [
            const NotificationActionButton(),
            Padding(
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: IconButton(
                tooltip: 'View profile',
                onPressed: _openProfile,
                icon: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryContainer,
                  ),
                  child:
                      const Icon(Icons.person, size: 18, color: Colors.white),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My Projects'),
              Tab(text: 'Joined Projects'),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: store.isLoading || _isLoadingRole
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : _roleLoadFailed
                  ? _buildRoleLoadError()
                  : store.errorMessage != null
                      ? _buildLoadError(store.errorMessage!)
                      : TabBarView(
                          children: [
                            _buildMyProjectsTab(store),
                            _buildJoinedProjectsTab(store),
                          ],
                        ),
        ),
      ),
    );
  }

  Widget _buildLoadError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 44, color: AppColors.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => ProjectsStore.instance.load(refresh: true),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: AppColors.outline),
            const SizedBox(height: 12),
            Text(
              'Could not determine your account type. Please try again.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() => _isLoadingRole = true);
                _loadUserRole();
              },
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyProjectsTab(ProjectsStore store) {
    if (_userRole == AppRole.contractor || _userRole == AppRole.designer) {
      return _buildRoleProjectsComingSoon();
    }

    final ownedProjects =
        store.projects.where((project) => project.isOwner).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Projects you own',
                  style: AppTextStyles.cardTitle.copyWith(
                    fontSize: 25,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${ownedProjects.length} '
                  '${ownedProjects.length == 1 ? 'project' : 'projects'}',
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.outline,
                  ),
                ),
              ],
            ),
            IconButton.filled(
              tooltip: 'Add project',
              onPressed: _openCreateProject,
              icon: const Icon(Icons.add_home_work_outlined),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (ownedProjects.isEmpty)
          _buildNoOwnedProjects()
        else
          for (final project in ownedProjects) ...[
            ProjectCard(
              project: project,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProjectDashboardScreen(project: project),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _buildRoleProjectsComingSoon() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Text(
          'Coming soon',
          style: AppTextStyles.cardTitle.copyWith(
            fontSize: 25,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          color: AppColors.surfaceContainerLow,
          child: ListTile(
            leading: const Icon(Icons.upcoming_outlined),
            title: const Text('My Projects'),
            subtitle: Text(
              'Creating and managing projects for '
              '${_userRole!.label.toLowerCase()} accounts is coming soon. '
              'Use Joined Projects to open projects shared with you.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoOwnedProjects() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.apartment_rounded,
                  size: 32,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Start your first project',
                textAlign: TextAlign.center,
                style: AppTextStyles.cardTitle.copyWith(
                  fontSize: 18,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a project to organize your plans, invite your team, '
                'and keep everything together.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _openCreateProject,
                icon: const Icon(Icons.add),
                label: const Text('Create your first project'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildJoinedProjectsTab(ProjectsStore store) {
    final joinedProjects =
        store.projects.where((project) => !project.isOwner).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Text(
          'Projects you joined',
          style: AppTextStyles.cardTitle.copyWith(
            fontSize: 25,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Projects owned by someone else that you joined after accepting '
          'their invitation.',
          style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        _summaryCard(
          icon: Icons.groups_2_outlined,
          label: 'Projects you have joined',
          value: '${joinedProjects.length}',
          expanded: true,
        ),
        const SizedBox(height: 24),
        if (joinedProjects.isEmpty)
          _buildNoJoinedProjects()
        else ...[
          Text(
            'Projects shared with you',
            style: AppTextStyles.cardTitle.copyWith(
              fontSize: 18,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          for (final project in joinedProjects) ...[
            ProjectCard(
              project: project,
              joined: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProjectDashboardScreen(project: project),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ],
    );
  }

  Widget _buildNoJoinedProjects() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.group_add_outlined,
              size: 34,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Projects you join will appear here',
            textAlign: TextAlign.center,
            style: AppTextStyles.cardTitle.copyWith(
              fontSize: 18,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Accept an invitation from a project owner to see that project, '
            'its team, and shared details here.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String label,
    required String value,
    bool expanded = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withAlpha(180)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.secondary, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTextStyles.cardTitle.copyWith(
                    fontSize: 19,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  maxLines: expanded ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
