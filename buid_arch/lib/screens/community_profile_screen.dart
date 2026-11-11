import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/community.dart';
import '../models/job_portal.dart';
import '../navigation/community_navigation.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../services/current_location_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/community_contact_action.dart';
import 'community_create_post_screen.dart';
import 'community_post_detail_screen.dart';
import 'project_location_picker_screen.dart';

class CommunityProfileScreen extends StatefulWidget {
  const CommunityProfileScreen({
    super.key,
    required this.token,
    required this.profile,
    required this.isCurrentUser,
    this.onUpgrade,
  });

  final String token;
  final CommunityProfile profile;
  final bool isCurrentUser;
  final VoidCallback? onUpgrade;

  @override
  State<CommunityProfileScreen> createState() => _CommunityProfileScreenState();
}

class _CommunityProfileScreenState extends State<CommunityProfileScreen> {
  late CommunityProfile _profile = widget.profile;
  List<CommunityPost> _posts = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _creatingPost = false;
  int? _likingPostId;
  String? _error;
  String? _memberProfileError;
  CommunityContactStatus? _contactStatus;

  @override
  void initState() {
    super.initState();
    _loadPosts();
    if (!widget.isCurrentUser) _loadMemberProfile();
  }

  Future<void> _loadMemberProfile() async {
    try {
      final results = await Future.wait([
        AuthApiService.instance.getCommunityMemberProfile(
          token: widget.token,
          profileId: _profile.id,
        ),
        AuthApiService.instance.getCommunityContactStatus(
          token: widget.token,
          userId: _profile.userId,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as CommunityProfile;
        _contactStatus = results[1] as CommunityContactStatus;
      });
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (mounted) {
        setState(() {
          _memberProfileError = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _memberProfileError = 'Could not load member contact details.';
        });
      }
    }
  }

  Future<void> _refreshContactStatus() async {
    try {
      final status = await AuthApiService.instance.getCommunityContactStatus(
        token: widget.token,
        userId: _profile.userId,
      );
      final profile = await AuthApiService.instance.getCommunityMemberProfile(
        token: widget.token,
        profileId: _profile.id,
      );
      if (!mounted) return;
      setState(() {
        _contactStatus = status;
        _profile = profile;
      });
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not refresh contact permissions.');
    }
  }

  Future<void> _toggleMemberBlock() async {
    final blockedByMe = _contactStatus?.blockedByMe == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(blockedByMe ? 'Unblock member?' : 'Block member?'),
        content: Text(
          blockedByMe
              ? 'This member will be able to request phone contact again.'
              : 'This member will not be able to contact you. Any phone contact permission will be revoked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(blockedByMe ? 'Unblock' : 'Block'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (blockedByMe) {
        await AuthApiService.instance.unblockCommunityMember(
          token: widget.token,
          userId: _profile.userId,
        );
      } else {
        await AuthApiService.instance.blockCommunityMember(
          token: widget.token,
          userId: _profile.userId,
        );
      }
      await _refreshContactStatus();
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not update the member block.');
    }
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (_loadingMore) return;
    setState(() {
      _loading = true;
      _error = null;
      if (refresh) {
        _page = 1;
        _hasMore = true;
      }
    });
    try {
      final result = await AuthApiService.instance.getCommunityMemberPosts(
        token: widget.token,
        profileId: _profile.id,
        page: refresh ? 1 : _page,
      );
      if (!mounted) return;
      setState(() {
        _posts =
            refresh || _page == 1 ? result.items : [..._posts, ...result.items];
        _page = result.currentPage;
        _hasMore = result.hasMore;
      });
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load member posts.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final result = await AuthApiService.instance.getCommunityMemberPosts(
        token: widget.token,
        profileId: _profile.id,
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _posts = [..._posts, ...result.items];
        _page = result.currentPage;
        _hasMore = result.hasMore;
      });
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load more posts.');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _createPost() async {
    if (_creatingPost) return;
    setState(() => _creatingPost = true);
    try {
      final categories = await AuthApiService.instance.getCommunityCategories(
        token: widget.token,
      );
      if (!mounted) return;
      final post = await Navigator.of(context).push<CommunityPost>(
        MaterialPageRoute(
          builder: (_) => CommunityCreatePostScreen(
            token: widget.token,
            categories: categories,
          ),
        ),
      );
      if (post == null || !mounted) return;
      setState(() {
        _posts = [post, ..._posts];
        _profile = _profile.copyWith(postsCount: _profile.postsCount + 1);
      });
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not open the post composer.');
    } finally {
      if (mounted) setState(() => _creatingPost = false);
    }
  }

  Future<void> _editProfile() async {
    final updated = await Navigator.of(context).push<CommunityProfile>(
      MaterialPageRoute(
        builder: (_) => _CommunityProfileEditor(
          token: widget.token,
          profile: _profile,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _profile = updated);
      Navigator.of(context).pop(updated);
    }
  }

  Future<void> _changeProfileImage() async {
    final picker = ImagePicker();
    try {
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      final updated = await AuthApiService.instance.updateCommunityProfileImage(
        token: widget.token,
        image: image,
      );
      if (mounted) setState(() => _profile = updated);
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (mounted) _showMessage(error.message);
    } on Exception catch (_) {
      if (mounted) _showMessage('Could not update your profile image.');
    }
  }

  Future<void> _removeProfileImage() async {
    try {
      final updated = await AuthApiService.instance.removeCommunityProfileImage(
        token: widget.token,
      );
      if (mounted) setState(() => _profile = updated);
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not remove your profile image.');
    }
  }

  Future<void> _toggleLike(CommunityPost post) async {
    if (_likingPostId != null) return;
    setState(() => _likingPostId = post.id);
    try {
      final result = await AuthApiService.instance.toggleCommunityLike(
        token: widget.token,
        postId: post.id,
      );
      if (!mounted) return;
      setState(() {
        _posts = _posts
            .map((item) => item.id == post.id
                ? item.copyWith(
                    likedByMe: result.liked,
                    likesCount: result.likesCount,
                  )
                : item)
            .toList();
      });
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      } else if (mounted) {
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) _showMessage('Could not update your like. Please retry.');
    } finally {
      if (mounted) setState(() => _likingPostId = null);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Community profile'),
        backgroundColor: AppColors.surface,
        leading: BackButton(
          onPressed: () => Navigator.of(context).pop(
            widget.isCurrentUser ? _profile : null,
          ),
        ),
        actions: [
          if (widget.isCurrentUser && widget.onUpgrade != null)
            PopupMenuButton<String>(
              onSelected: (_) => widget.onUpgrade?.call(),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'upgrade',
                  child: Text('Switch to Main App'),
                ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadPosts(refresh: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _profileHeader(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Community Posts',
                    style: AppTextStyles.titleMd,
                  ),
                ),
                Text(
                  'Latest first',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_loading && _posts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _posts.isEmpty)
              Column(
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => _loadPosts(refresh: true),
                    child: const Text('Try again'),
                  ),
                ],
              )
            else if (_posts.isEmpty)
              _emptyPosts()
            else ...[
              for (final post in _posts)
                _CommunityProfilePostTile(
                  post: post,
                  currentProfileId: widget.profile.id,
                  onTap: () => _openPost(post),
                  onLike: () => _toggleLike(post),
                  liking: _likingPostId == post.id,
                  onReport: () => _reportPost(post),
                  onDelete: () => _deletePost(post),
                ),
              if (_hasMore)
                Center(
                  child: TextButton(
                    onPressed: _loadingMore ? null : _loadMore,
                    child: _loadingMore
                        ? const CircularProgressIndicator()
                        : const Text('Load more'),
                  ),
                ),
            ],
          ],
        ),
      ),
      floatingActionButton: widget.isCurrentUser
          ? FloatingActionButton.extended(
              onPressed: _creatingPost ? null : _createPost,
              icon: _creatingPost
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add),
              label: Text(_creatingPost ? 'Loading...' : 'Create post'),
            )
          : null,
    );
  }

  Widget _emptyPosts() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.forum_outlined,
              size: 34,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.isCurrentUser ? 'Start the conversation' : 'No posts yet',
            style: AppTextStyles.titleMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            widget.isCurrentUser
                ? 'Share an idea, ask a question, or tell the community what you’re working on.'
                : 'This member hasn’t shared any posts yet.',
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (widget.isCurrentUser) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _creatingPost ? null : _createPost,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Create your first post'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _profileHeader() {
    final p = _profile;
    final professionLabel =
        p.trade?.isNotEmpty == true && p.trade != p.profession
            ? '${p.trade} · ${p.profession}'
            : p.profession;
    return Card(
      color: AppColors.surfaceContainerLowest,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.border.withAlpha(150)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    _profilePhoto(p),
                    if (widget.isCurrentUser)
                      Positioned(
                        right: 3,
                        bottom: 3,
                        child: PopupMenuButton<String>(
                          tooltip: 'Profile image options',
                          onSelected: (action) => action == 'remove'
                              ? _removeProfileImage()
                              : _changeProfileImage(),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'change',
                              child: Text('Change photo'),
                            ),
                            if (p.profileImageUrl != null)
                              const PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove photo'),
                              ),
                          ],
                          padding: EdgeInsets.zero,
                          child: const CircleAvatar(
                            radius: 15,
                            child: Icon(Icons.camera_alt_outlined, size: 16),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleMd.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          professionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        if (p.location?.isNotEmpty == true) ...[
                          const SizedBox(height: 3),
                          Text(
                            p.location!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (p.bio?.isNotEmpty == true) ...[
                          const SizedBox(height: 6),
                          Text(
                            p.bio!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySm,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _profileStat('${p.postsCount}', 'Posts'),
                _profileStat(
                  p.experienceYears == null ? '—' : '${p.experienceYears}',
                  'Years exp.',
                ),
                _profileStat('${p.skills.length}', 'Skills'),
              ],
            ),
            if (!widget.isCurrentUser && _memberProfileError != null) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: _loadMemberProfile,
                child: const Text('Retry loading profile'),
              ),
            ],
            if (!widget.isCurrentUser) ...[
              const SizedBox(height: 14),
              CommunityContactAction(
                key: ValueKey(_profile.userId),
                token: widget.token,
                userId: _profile.userId,
                initialStatus: _contactStatus,
                showContactActions: false,
                onStatusChanged: (status) {
                  if (mounted) setState(() => _contactStatus = status);
                },
                onMoreOptions: _toggleMemberBlock,
                moreOptionsLabel: _contactStatus?.blockedByMe == true
                    ? 'Unblock member'
                    : 'Block member',
              ),
            ],
            if (widget.isCurrentUser) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _editProfile,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Community profile'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _profilePhoto(CommunityProfile profile) {
    final fallback = Container(
      width: 82,
      height: 82,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        profile.displayName.trim().isEmpty
            ? '?'
            : profile.displayName.trim()[0].toUpperCase(),
        style: AppTextStyles.headlineSm.copyWith(color: AppColors.secondary),
      ),
    );
    if (profile.profileImageUrl == null || profile.profileImageUrl!.isEmpty) {
      return fallback;
    }

    return FutureBuilder<String?>(
      future: AuthSessionService.instance.readToken(),
      builder: (context, snapshot) {
        final token = snapshot.data;
        if (token == null || token.isEmpty) return fallback;
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.network(
            profile.profileImageUrl!,
            width: 82,
            height: 82,
            fit: BoxFit.cover,
            headers: const {'Authorization': '******'},
            errorBuilder: (_, __, ___) => fallback,
          ),
        );
      },
    );
  }

  Widget _profileStat(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTextStyles.headlineSm.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPost(CommunityPost post) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CommunityPostDetailScreen(
          token: widget.token,
          post: post,
          currentProfileId: widget.profile.id,
        ),
      ),
    );
    if (changed == true) _loadPosts(refresh: true);
  }

  Future<void> _reportPost(CommunityPost post) async {
    try {
      await AuthApiService.instance.reportCommunityContent(
        token: widget.token,
        targetType: 'post',
        targetId: post.id,
        reason: 'inappropriate',
      );
      if (mounted) _showMessage('Report sent for review.');
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      } else if (mounted) {
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) _showMessage('Could not send your report.');
    }
  }

  Future<void> _deletePost(CommunityPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This post and its replies will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AuthApiService.instance.deleteCommunityPost(
        token: widget.token,
        postId: post.id,
      );
      if (!mounted) return;
      setState(() {
        _posts.removeWhere((item) => item.id == post.id);
        _profile = _profile.copyWith(
          postsCount: (_profile.postsCount - 1).clamp(0, 1 << 31).toInt(),
        );
      });
      _showMessage('Post deleted.');
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      } else if (mounted) {
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) _showMessage('Could not delete the post.');
    }
  }
}

class _CommunityProfilePostTile extends StatelessWidget {
  const _CommunityProfilePostTile({
    required this.post,
    required this.currentProfileId,
    required this.onTap,
    required this.onLike,
    required this.liking,
    required this.onReport,
    required this.onDelete,
  });

  final CommunityPost post;
  final int currentProfileId;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final bool liking;
  final VoidCallback onReport;
  final VoidCallback onDelete;

  String get _sharedAt {
    final createdAt = post.createdAt?.toLocal();
    if (createdAt == null) return 'Shared recently';
    final difference = DateTime.now().difference(createdAt);
    if (difference.inMinutes < 1) return 'Shared just now';
    if (difference.inHours < 1) return 'Shared ${difference.inMinutes}m ago';
    if (difference.inDays < 1) return 'Shared ${difference.inHours}h ago';
    if (difference.inDays < 7) return 'Shared ${difference.inDays}d ago';
    return 'Shared ${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        post.imageUrls.isNotEmpty ? post.imageUrls.first : post.imageUrl;
    final isMine = post.author.id == currentProfileId;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border.withAlpha(150)),
        ),
      ),
      child: Row(
        children: [
          _thumbnail(imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMd.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$_sharedAt · ${post.commentsCount} '
                      '${post.commentsCount == 1 ? 'reply' : 'replies'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: post.likedByMe ? 'Unlike post' : 'Like post',
                visualDensity: VisualDensity.compact,
                onPressed: liking ? null : onLike,
                icon: liking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        post.likedByMe ? Icons.favorite : Icons.favorite_border,
                        color: post.likedByMe
                            ? AppColors.error
                            : AppColors.outline,
                        size: 20,
                      ),
              ),
              Text(
                '${post.likesCount}',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
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
    );
  }

  Widget _thumbnail(String? imageUrl) {
    final placeholder = Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(
        Icons.forum_outlined,
        color: AppColors.secondary,
      ),
    );
    if (imageUrl == null || imageUrl.isEmpty) return placeholder;
    return FutureBuilder<String?>(
      future: AuthSessionService.instance.readToken(),
      builder: (context, snapshot) {
        final token = snapshot.data;
        if (token == null || token.isEmpty) return placeholder;
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            imageUrl,
            width: 82,
            height: 82,
            fit: BoxFit.cover,
            headers: const {'Authorization': '******'},
            errorBuilder: (_, __, ___) => placeholder,
          ),
        );
      },
    );
  }
}

class _CommunityProfileEditor extends StatefulWidget {
  const _CommunityProfileEditor({
    required this.token,
    required this.profile,
  });

  final String token;
  final CommunityProfile profile;

  @override
  State<_CommunityProfileEditor> createState() =>
      _CommunityProfileEditorState();
}

class _CommunityProfileEditorState extends State<_CommunityProfileEditor> {
  static const _professions = [
    'Homeowner',
    'Designer',
    'Contractor',
    'Architect',
    'Civil Engineer',
    'Interior Designer',
    'Student',
    'Other',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final TextEditingController _bioController;
  late final TextEditingController _otherProfessionController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _tradeController;
  late final TextEditingController _skillsController;
  late final TextEditingController _experienceController;
  late final TextEditingController _preferredLocationController;
  late String _profession;
  double? _latitude;
  double? _longitude;
  double? _preferredLatitude;
  double? _preferredLongitude;
  List<JobPortalCategory> _jobCategories = const [];
  final Set<int> _preferredCategories = {};
  late int _preferredRadiusKm;
  late bool _jobNotificationsEnabled;
  String? _error;
  bool _saving = false;
  bool _choosingLocation = false;
  bool _choosingPreferredLocation = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName);
    _locationController =
        TextEditingController(text: widget.profile.location ?? '');
    _bioController = TextEditingController(text: widget.profile.bio ?? '');
    _otherProfessionController =
        TextEditingController(text: widget.profile.otherProfession ?? '');
    _emailController = TextEditingController(text: widget.profile.email ?? '');
    _phoneController =
        TextEditingController(text: widget.profile.phoneNumber ?? '');
    _tradeController = TextEditingController(text: widget.profile.trade ?? '');
    _skillsController =
        TextEditingController(text: widget.profile.skills.join(', '));
    _experienceController = TextEditingController(
      text: widget.profile.experienceYears?.toString() ?? '',
    );
    _preferredLocationController =
        TextEditingController(text: widget.profile.preferredLocation ?? '');
    _latitude = widget.profile.latitude;
    _longitude = widget.profile.longitude;
    _preferredLatitude = widget.profile.preferredLatitude;
    _preferredLongitude = widget.profile.preferredLongitude;
    _profession = widget.profile.professionType ?? 'not_specified';
    _preferredRadiusKm = widget.profile.preferredRadiusKm;
    _jobNotificationsEnabled = widget.profile.jobNotificationsEnabled;
    _preferredCategories.addAll(widget.profile.preferredCategories);
    unawaited(_loadJobCategories());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _bioController.dispose();
    _otherProfessionController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _tradeController.dispose();
    _skillsController.dispose();
    _experienceController.dispose();
    _preferredLocationController.dispose();
    super.dispose();
  }

  Future<void> _chooseLocation() async {
    if (_choosingLocation || _saving) return;
    setState(() {
      _choosingLocation = true;
      _error = null;
    });
    try {
      final location = await Navigator.of(context)
          .push<CurrentDeviceLocation>(MaterialPageRoute(
        builder: (_) => const ProjectLocationPickerScreen(
          title: 'Choose Community Location',
          confirmLabel: 'Use This Location',
          consumeSharedLocation: false,
        ),
      ));
      if (mounted && location != null) {
        setState(() {
          _locationController.text = location.address;
          _latitude = location.latitude;
          _longitude = location.longitude;
        });
      }
    } finally {
      if (mounted) setState(() => _choosingLocation = false);
    }
  }

  Future<void> _choosePreferredLocation() async {
    if (_choosingPreferredLocation || _saving) return;
    setState(() {
      _choosingPreferredLocation = true;
      _error = null;
    });
    try {
      final location = await Navigator.of(context)
          .push<CurrentDeviceLocation>(MaterialPageRoute(
        builder: (_) => const ProjectLocationPickerScreen(
          title: 'Choose Preferred Job Location',
          confirmLabel: 'Use This Location',
          consumeSharedLocation: false,
        ),
      ));
      if (mounted && location != null) {
        setState(() {
          _preferredLocationController.text = location.address;
          _preferredLatitude = location.latitude;
          _preferredLongitude = location.longitude;
        });
      }
    } finally {
      if (mounted) setState(() => _choosingPreferredLocation = false);
    }
  }

  Future<void> _loadJobCategories() async {
    try {
      final categories = await AuthApiService.instance.getJobPortalCategories(
        token: widget.token,
      );
      if (mounted) setState(() => _jobCategories = categories);
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a display name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await AuthApiService.instance.updateCommunityProfile(
        token: widget.token,
        displayName: _nameController.text.trim(),
        profession: _profession == 'not_specified' ? null : _profession,
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        otherProfession: _profession == 'Other'
            ? _otherProfessionController.text.trim()
            : null,
        bio: _bioController.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
        trade: _tradeController.text.trim(),
        skills: _skillsController.text
            .split(',')
            .map((skill) => skill.trim())
            .where((skill) => skill.isNotEmpty)
            .toList(),
        experienceYears: int.tryParse(_experienceController.text.trim()),
        preferredLocation: _preferredLocationController.text.trim().isEmpty
            ? null
            : _preferredLocationController.text.trim(),
        preferredLatitude: _preferredLatitude,
        preferredLongitude: _preferredLongitude,
        preferredCategories: _preferredCategories.toList(),
        preferredRadiusKm: _preferredRadiusKm,
        jobNotificationsEnabled: _jobNotificationsEnabled,
      );
      if (mounted) Navigator.of(context).pop(updated);
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save your profile.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Community profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Email address',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              helperText: 'Managed by your Build Arch account.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            readOnly: true,
            onTap: _saving ? null : _chooseLocation,
            maxLength: 255,
            decoration: InputDecoration(
              labelText: 'Community location (optional)',
              hintText: 'Choose a location',
              border: const OutlineInputBorder(),
              suffixIcon: _choosingLocation
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Choose location',
                      onPressed: _saving ? null : _chooseLocation,
                      icon: const Icon(Icons.map_outlined),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _profession,
            decoration: const InputDecoration(
              labelText: 'Profession',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                value: 'not_specified',
                child: Text('Prefer not to say'),
              ),
              for (final profession in _professions)
                DropdownMenuItem(
                  value: profession,
                  child: Text(profession),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) setState(() => _profession = value);
                  },
          ),
          if (_profession == 'Other') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _otherProfessionController,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Your profession',
                border: OutlineInputBorder(),
              ),
              enabled: !_saving,
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _tradeController,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Profession / trade',
              hintText: 'For example, Electrician or Site Supervisor',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _skillsController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Skills',
              hintText: 'Separate skills with commas',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _experienceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Years of experience',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bioController,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Bio (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 22),
          Text('Job preferences', style: AppTextStyles.titleMd),
          const SizedBox(height: 8),
          Text(
            'Choose job categories and a preferred location to receive nearby opportunities.',
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _preferredLocationController,
            readOnly: true,
            onTap: _saving ? null : _choosePreferredLocation,
            decoration: InputDecoration(
              labelText: 'Preferred job location',
              border: const OutlineInputBorder(),
              suffixIcon: _choosingPreferredLocation
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Choose preferred location',
                      onPressed: _saving ? null : _choosePreferredLocation,
                      icon: const Icon(Icons.map_outlined),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (_jobCategories.isEmpty)
            Text(
              'Job categories are unavailable right now.',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.outline),
            )
          else
            Wrap(
              spacing: 6,
              children: [
                for (final category in _jobCategories)
                  FilterChip(
                    label: Text(category.name),
                    selected: _preferredCategories.contains(category.id),
                    onSelected: _saving
                        ? null
                        : (selected) => setState(() {
                              if (selected) {
                                _preferredCategories.add(category.id);
                              } else {
                                _preferredCategories.remove(category.id);
                              }
                            }),
                  ),
              ],
            ),
          DropdownButtonFormField<int>(
            initialValue: _preferredRadiusKm,
            decoration: const InputDecoration(
              labelText: 'Nearby job notification radius',
            ),
            items: const [5, 10, 25, 50, 100]
                .map((radius) => DropdownMenuItem(
                      value: radius,
                      child: Text('$radius km'),
                    ))
                .toList(),
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _preferredRadiusKm = value);
                    }
                  },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notify me about nearby jobs'),
            value: _jobNotificationsEnabled,
            onChanged: _saving
                ? null
                : (enabled) =>
                    setState(() => _jobNotificationsEnabled = enabled),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          if (_saving) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
