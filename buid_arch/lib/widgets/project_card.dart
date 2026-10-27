import 'package:flutter/material.dart';

import '../models/project.dart';
import '../models/project_type.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A project preview card used by the owned and joined project lists.
class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.onTap,
    this.joined = false,
  });

  final Project project;
  final VoidCallback onTap;
  final bool joined;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);

    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: radius,
      elevation: 2,
      shadowColor: AppColors.deepBrown.withAlpha(35),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppColors.border.withAlpha(170)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _projectImage(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleMd.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: AppColors.primaryContainer,
                          size: 21,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: AppColors.outline,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            project.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _TypeChip(
                            icon: project.type.icon,
                            label: project.type.label,
                          ),
                        ),
                        if (joined) ...[
                          const SizedBox(width: 8),
                          const _JoinedChip(),
                        ],
                      ],
                    ),
                    if (joined) ...[
                      const SizedBox(height: 10),
                      Text(
                        [
                          _roleName(project.memberRole),
                          if (project.invitedByName?.trim().isNotEmpty == true)
                            'Invited by ${project.invitedByName}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Progress tracking · Coming soon',
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _roleName(String? role) => switch (role) {
        'contractor' => 'Contractor',
        'designer' => 'Designer',
        _ => 'Project member',
      };

  Widget _projectImage() {
    return SizedBox(
      height: 154,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (project.photoUrl != null)
            Image.network(
              project.photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _imagePlaceholder(),
            )
          else
            _imagePlaceholder(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33000000), Color(0x00000000)],
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(235),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(project.type.icon, size: 15, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    joined ? 'TEAM PROJECT' : 'MY PROJECT',
                    style: AppTextStyles.labelTechnical.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surfaceContainer,
            AppColors.creamSand,
            AppColors.surfaceContainerHigh,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          project.type.icon,
          size: 58,
          color: AppColors.primary.withAlpha(150),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.secondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinedChip extends StatelessWidget {
  const _JoinedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3EB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'JOINED',
        style: AppTextStyles.labelTechnical.copyWith(
          color: AppColors.success,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
