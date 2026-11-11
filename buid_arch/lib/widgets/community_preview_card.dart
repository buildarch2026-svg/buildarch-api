import 'package:flutter/material.dart';

import '../models/community.dart';
import '../navigation/community_navigation.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class CommunityPreviewCard extends StatefulWidget {
  const CommunityPreviewCard({super.key});

  @override
  State<CommunityPreviewCard> createState() => _CommunityPreviewCardState();
}

class _CommunityPreviewCardState extends State<CommunityPreviewCard> {
  CommunityPost? _post;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final token = await AuthSessionService.instance.readToken();
      if (token == null || token.isEmpty) {
        if (mounted) setState(() => _error = 'Sign in to explore discussions.');
        return;
      }
      final preview =
          await AuthApiService.instance.getCommunityPreview(token: token);
      if (mounted) setState(() => _post = preview.post);
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Discussion preview is unavailable.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return Card(
      color: AppColors.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => CommunityNavigation.open(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: AppColors.primaryContainer,
                    child: Icon(Icons.groups_outlined, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Build Arch Community',
                          style: AppTextStyles.titleMd.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Connect, discuss, and learn from others.',
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const LinearProgressIndicator(minHeight: 2)
              else if (_error != null)
                Text(
                  _error!,
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                )
              else if (post == null)
                Text(
                  'No discussions yet. Be the first to start a conversation!',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                )
              else ...[
                Text(
                  post.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${post.author.displayName} · ${post.commentsCount} '
                  '${post.commentsCount == 1 ? 'reply' : 'replies'}',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => CommunityNavigation.open(context),
                  icon: const Icon(Icons.forum_outlined, size: 18),
                  label: const Text('Explore Community'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
