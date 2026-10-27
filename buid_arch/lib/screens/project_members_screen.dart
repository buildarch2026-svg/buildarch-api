import 'package:flutter/material.dart';

import '../models/project.dart';
import '../models/project_member.dart';
import 'project_direct_chat_screen.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class ProjectMembersScreen extends StatefulWidget {
  const ProjectMembersScreen({super.key, required this.project});

  final Project project;

  @override
  State<ProjectMembersScreen> createState() => _ProjectMembersScreenState();
}

class _ProjectMembersScreenState extends State<ProjectMembersScreen> {
  List<ProjectMember> _members = [];
  int? _currentUserId;
  bool _loading = true;
  String? _error;
  final _searchController = TextEditingController();
  String _selectedRole = 'All';

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = _members.isEmpty;
      _error = null;
    });
    try {
      final token = await AuthSessionService.instance.readToken();
      if (token == null || token.isEmpty) {
        throw const AuthApiException(
          'Your session expired. Please sign in again.',
        );
      }
      final user = await AuthSessionService.instance.readUser();
      final storedUserId = user?['id'];
      final currentUserId = storedUserId is num
          ? storedUserId.toInt()
          : int.tryParse(storedUserId?.toString() ?? '');
      if (currentUserId == null) {
        throw const AuthApiException(
          'Could not identify your signed-in account. Please sign in again.',
        );
      }
      final members = await AuthApiService.instance.getProjectMembers(
        token: token,
        projectId: widget.project.id,
      );
      if (mounted) {
        setState(() {
          _currentUserId = currentUserId;
          _members = members;
        });
      }
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load project members.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _roleName(String role) => switch (role) {
        'homeOwner' => 'Home Owner',
        'contractor' => 'Contractor',
        'designer' => 'Designer',
        _ => role,
      };

  IconData _roleIcon(String role) => switch (role) {
        'homeOwner' => Icons.home_work_outlined,
        'contractor' => Icons.engineering_outlined,
        'designer' => Icons.design_services_outlined,
        _ => Icons.person_outline,
      };

  List<ProjectMember> get _filteredMembers {
    final query = _searchController.text.trim().toLowerCase();
    return _visibleMembers.where((member) {
      final matchesQuery = query.isEmpty ||
          member.name.toLowerCase().contains(query) ||
          _roleName(member.role).toLowerCase().contains(query);
      final matchesRole =
          _selectedRole == 'All' || _roleName(member.role) == _selectedRole;
      return matchesQuery && matchesRole;
    }).toList();
  }

  List<ProjectMember> get _visibleMembers => _members
      .where((member) => member.userId != _currentUserId)
      .toList();

  int _countRole(String role) =>
      _visibleMembers.where((member) => member.role == role).length;

  String _joinedLabel(DateTime? joinedAt) {
    if (joinedAt == null) return 'Project team';
    final date = '${joinedAt.day.toString().padLeft(2, '0')}/'
        '${joinedAt.month.toString().padLeft(2, '0')}/${joinedAt.year}';
    return 'Joined $date';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Project team'),
            Text(
              widget.project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh team',
            onPressed: _loading ? null : _loadMembers,
            icon: const Icon(Icons.refresh),
          ),
        ],
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorPanel()
              : RefreshIndicator(
                  onRefresh: _loadMembers,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      _teamHeader(),
                      const SizedBox(height: 20),
                      _teamSummary(),
                      const SizedBox(height: 26),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'People',
                            style: AppTextStyles.cardTitle.copyWith(
                              fontSize: 19,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${_visibleMembers.length} ${_visibleMembers.length == 1 ? 'person' : 'people'}',
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search people or roles',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLowest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _roleFilters(),
                      const SizedBox(height: 14),
                      if (_filteredMembers.isEmpty)
                        _emptySearchState()
                      else
                        for (final member in _filteredMembers) ...[
                          _memberCard(member),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
    );
  }

  Widget _teamHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.deepBrown, AppColors.primaryContainer],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBrown.withAlpha(35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(28),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.groups_2_outlined,
              size: 30,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your project team',
                  style: AppTextStyles.headlineSm.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Owners and collaborators working together.',
                  style: AppTextStyles.bodySm.copyWith(
                    color: Colors.white.withAlpha(220),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamSummary() {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            icon: Icons.people_alt_outlined,
            label: 'Team members',
            value: '${_visibleMembers.length}',
            accent: AppColors.primaryContainer,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _summaryCard(
            icon: Icons.engineering_outlined,
            label: 'Contractors',
            value: '${_countRole('contractor')}',
            accent: AppColors.secondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _summaryCard(
            icon: Icons.design_services_outlined,
            label: 'Designers',
            value: '${_countRole('designer')}',
            accent: AppColors.tertiary,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: accent),
          const SizedBox(height: 10),
          Text(
            value,
            style: AppTextStyles.cardTitle.copyWith(
              fontSize: 20,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelTechnical.copyWith(
              letterSpacing: 0,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleFilters() {
    const roles = ['All', 'Home Owner', 'Contractor', 'Designer'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final role in roles) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(role),
                selected: _selectedRole == role,
                onSelected: (_) => setState(() => _selectedRole = role),
                selectedColor: AppColors.primaryContainer,
                labelStyle: AppTextStyles.bodySm.copyWith(
                  color: _selectedRole == role
                      ? Colors.white
                      : AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
                side: BorderSide(
                  color: _selectedRole == role
                      ? AppColors.primaryContainer
                      : AppColors.border,
                ),
                backgroundColor: AppColors.surfaceContainerLowest,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _memberCard(ProjectMember member) {
    final isOwner = member.role == 'homeOwner';
    final canChat =
        widget.project.isOwner ? !isOwner : isOwner && _currentUserId != null;
    final conversationMemberUserId =
        widget.project.isOwner ? member.userId : _currentUserId;
    final color = isOwner ? AppColors.primaryContainer : AppColors.secondary;
    final displayName =
        member.name.trim().isEmpty ? 'Unnamed member' : member.name;
    final initials = displayName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    final cardRadius = BorderRadius.circular(18);
    return Material(
      color: Colors.transparent,
      borderRadius: cardRadius,
      child: InkWell(
        onTap: canChat
            ? () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProjectDirectChatScreen(
                      project: widget.project,
                      member: member,
                      conversationMemberUserId: conversationMemberUserId!,
                    ),
                  ),
                )
            : null,
        borderRadius: cardRadius,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: cardRadius,
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBrown.withAlpha(12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: color.withAlpha(28),
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: AppTextStyles.titleMd.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleMd.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (isOwner) ...[
                          const SizedBox(width: 7),
                          _ownerBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _joinedLabel(member.joinedAt),
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_roleIcon(member.role), size: 14, color: color),
                    const SizedBox(width: 5),
                    Text(
                      _roleName(member.role),
                      style: AppTextStyles.labelTechnical.copyWith(
                        letterSpacing: 0,
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (canChat) ...[
                const SizedBox(width: 10),
                const Icon(
                  Icons.chat_bubble_outline,
                  size: 19,
                  color: AppColors.secondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _ownerBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'OWNER',
        style: AppTextStyles.labelTechnical.copyWith(
          fontSize: 8,
          letterSpacing: 0.4,
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _emptySearchState() {
    final isSearchEmpty = _visibleMembers.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            isSearchEmpty
                ? Icons.groups_outlined
                : Icons.person_search_outlined,
            size: 38,
            color: AppColors.outline,
          ),
          const SizedBox(height: 10),
          Text(
            isSearchEmpty ? 'No team members yet' : 'No matching team members',
            style: AppTextStyles.titleMd.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            isSearchEmpty
                ? 'Accepted collaborators will appear here.'
                : 'Try another name or choose a different role filter.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorPanel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 44, color: AppColors.outline),
            const SizedBox(height: 14),
            Text(
              'Could not load the project team',
              style: AppTextStyles.titleMd.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadMembers,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
