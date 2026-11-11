import 'package:flutter/material.dart';

import '../models/community.dart';
import '../services/auth_session_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'community_avatar.dart';

class CommunityPostCard extends StatelessWidget {
  const CommunityPostCard({
    super.key,
    required this.post,
    required this.currentProfileId,
    required this.onLike,
    required this.onComments,
    required this.onAuthor,
    required this.onReport,
    required this.onDelete,
    this.showActions = true,
  });

  final CommunityPost post;
  final int currentProfileId;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final VoidCallback onAuthor;
  final VoidCallback onReport;
  final VoidCallback onDelete;
  final bool showActions;

  String get _dateLabel {
    final date = post.createdAt?.toLocal();
    if (date == null) return 'Recently';
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isMine = post.author.id == currentProfileId;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: onAuthor,
                  customBorder: const CircleBorder(),
                  child: CommunityAvatar(
                    imageUrl: post.author.profileImageUrl,
                    displayName: post.author.displayName,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: onAuthor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                post.author.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodyMd.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (isMine) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Author',
                                  style: AppTextStyles.bodySm.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${post.author.profession} · $_dateLabel',
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (showActions)
                  PopupMenuButton<String>(
                    tooltip: 'Post options',
                    onSelected: (action) =>
                        action == 'delete' ? onDelete() : onReport(),
                    itemBuilder: (_) => [
                      if (isMine)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete post'),
                        )
                      else
                        const PopupMenuItem(
                          value: 'report',
                          child: Text('Report post'),
                        ),
                    ],
                  ),
              ],
            ),
            if (post.category != null) ...[
              const SizedBox(height: 10),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(post.category!.name),
                backgroundColor: AppColors.surfaceContainerLow,
                side: BorderSide.none,
              ),
            ],
            const SizedBox(height: 8),
            SelectableText(
              post.content,
              style: AppTextStyles.bodyMd.copyWith(
                height: 1.45,
                color: AppColors.textPrimary,
              ),
            ),
            if (post.imageUrls.isNotEmpty || post.imageUrl != null) ...[
              const SizedBox(height: 12),
              _PostImages(
                urls: post.imageUrls.isNotEmpty
                    ? post.imageUrls
                    : [post.imageUrl!],
              ),
            ],
            if (showActions) ...[
              const Divider(height: 24),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onLike,
                    icon: Icon(
                      post.likedByMe ? Icons.favorite : Icons.favorite_border,
                      color:
                          post.likedByMe ? AppColors.error : AppColors.outline,
                      size: 19,
                    ),
                    label: Text('${post.likesCount}'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onComments,
                    icon: const Icon(Icons.mode_comment_outlined, size: 18),
                    label: Text('${post.commentsCount}'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onComments,
                    child: const Text('Reply'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PostImages extends StatelessWidget {
  const _PostImages({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final visibleCount = urls.length.clamp(1, 2);
    final remaining = urls.skip(visibleCount).toList(growable: false);
    return Row(
      children: [
        for (var index = 0; index < visibleCount; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1.2,
              child: _PostImage(url: urls[index]),
            ),
          ),
        ],
        if (urls.length == 1) const Spacer(),
        if (remaining.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1.2,
              child: Material(
                color: AppColors.onSurface,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _showRemainingImages(context, remaining),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.photo_library_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '+${remaining.length} more',
                          style: AppTextStyles.bodyMd.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showRemainingImages(
    BuildContext context,
    List<String> remaining,
  ) {
    final size = MediaQuery.sizeOf(context);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('More photos'),
        content: SizedBox(
          width: size.width > 600 ? 520 : size.width * 0.8,
          height: size.height * 0.6,
          child: GridView.builder(
            itemCount: remaining.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) => _PostImage(url: remaining[index]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _PostImage extends StatelessWidget {
  const _PostImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: AuthSessionService.instance.readToken(),
      builder: (context, snapshot) {
        final token = snapshot.data;
        if (token == null || token.isEmpty) {
          return const SizedBox.shrink();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: AppColors.surfaceContainerLow,
            child: Image.network(
              url,
              headers: {'Authorization': 'Bearer $token'},
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.surfaceContainerLow,
                alignment: Alignment.center,
                child: const Text('Image unavailable'),
              ),
            ),
          ),
        );
      },
    );
  }
}
