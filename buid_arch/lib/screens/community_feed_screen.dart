import 'package:flutter/material.dart';

import '../models/community.dart';
import '../navigation/community_navigation.dart';
import '../services/auth_api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/community_post_card.dart';
import 'community_create_post_screen.dart';
import 'community_contacts_screen.dart';
import 'community_post_detail_screen.dart';
import 'community_profile_screen.dart';
import 'job_portal_screen.dart';

class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({
    super.key,
    required this.token,
    required this.profile,
    required this.hasMainAppAccess,
    required this.onTabSelected,
    required this.onProfileUpdated,
  });

  final String token;
  final CommunityProfile profile;
  final bool hasMainAppAccess;
  final ValueChanged<AppTab> onTabSelected;
  final ValueChanged<CommunityProfile> onProfileUpdated;

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen> {
  final _scrollController = ScrollController();
  List<CommunityPost> _posts = [];
  List<CommunityCategory> _categories = [];
  String? _selectedCategory;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  int? _likingPostId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFeed();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 500 &&
        !_loading &&
        !_loadingMore &&
        _hasMore) {
      _loadNextPage();
    }
  }

  Future<void> _loadFeed({bool refresh = false}) async {
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
      final result = await AuthApiService.instance.getCommunityFeed(
        token: widget.token,
        page: refresh ? 1 : _page,
        category: _selectedCategory,
      );
      if (!mounted) return;
      setState(() {
        _categories = result.categories;
        _posts = refresh || _page == 1
            ? result.page.items
            : [..._posts, ...result.page.items];
        _page = result.page.currentPage;
        _hasMore = result.page.hasMore;
      });
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load discussions. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadNextPage() async {
    if (!_hasMore || _loadingMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final result = await AuthApiService.instance.getCommunityFeed(
        token: widget.token,
        page: _page + 1,
        category: _selectedCategory,
      );
      if (!mounted) return;
      setState(() {
        _posts = [..._posts, ...result.page.items];
        _page = result.page.currentPage;
        _hasMore = result.page.hasMore;
      });
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load more discussions.');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _createPost() async {
    final post = await Navigator.of(context).push<CommunityPost>(
      MaterialPageRoute(
        builder: (_) => CommunityCreatePostScreen(
          token: widget.token,
          categories: _categories,
        ),
      ),
    );
    if (!mounted || post == null) return;
    setState(() => _posts = [post, ..._posts]);
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

  Future<void> _openComments(CommunityPost post) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CommunityPostDetailScreen(
          token: widget.token,
          post: post,
          currentProfileId: widget.profile.id,
        ),
      ),
    );
    if (changed == true && mounted) await _loadFeed(refresh: true);
  }

  Future<void> _openAuthor(CommunityProfile profile) async {
    final updatedProfile = await Navigator.of(context).push<CommunityProfile>(
      MaterialPageRoute(
        builder: (_) => CommunityProfileScreen(
          token: widget.token,
          profile: profile,
          isCurrentUser: profile.id == widget.profile.id,
          onUpgrade: widget.hasMainAppAccess
              ? null
              : () => CommunityNavigation.startUpgrade(context),
        ),
      ),
    );
    if (updatedProfile != null && updatedProfile.id == widget.profile.id) {
      widget.onProfileUpdated(updatedProfile);
    }
  }

  Future<void> _openContacts() => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CommunityContactsScreen(token: widget.token),
        ),
      );

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
    if (confirmed != true || !mounted) return;
    try {
      await AuthApiService.instance.deleteCommunityPost(
        token: widget.token,
        postId: post.id,
      );
      if (!mounted) return;
      setState(() => _posts.removeWhere((item) => item.id == post.id));
      _showMessage('Post deleted.');
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      } else if (mounted) {
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) _showMessage('Could not delete the post. Please retry.');
    }
  }

  Future<void> _reportPost(CommunityPost post) async {
    const reasons = {
      'spam': 'Spam',
      'harassment': 'Harassment',
      'misinformation': 'Misinformation',
      'inappropriate': 'Inappropriate content',
      'other': 'Other',
    };
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Report post'),
        children: [
          for (final entry in reasons.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await AuthApiService.instance.reportCommunityContent(
        token: widget.token,
        targetType: 'post',
        targetId: post.id,
        reason: reason,
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
      if (mounted) _showMessage('Could not send your report. Please retry.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Build Arch Community'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        actions: [
          IconButton(
            tooltip: 'Community contacts and call requests',
            onPressed: _openContacts,
            icon: const Icon(Icons.people_alt_outlined),
          ),
          IconButton(
            tooltip: 'Construction Jobs',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const JobPortalScreen(),
              ),
            ),
            icon: const Icon(Icons.work_outline),
          ),
          IconButton(
            tooltip: 'My Community profile',
            onPressed: () => _openAuthor(widget.profile),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createPost,
        icon: const Icon(Icons.add),
        label: const Text('Create post'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadFeed(refresh: true),
        child: _loading && _posts.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 220),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null && _posts.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Icon(Icons.cloud_off_outlined, size: 44),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center),
                            TextButton(
                              onPressed: () => _loadFeed(refresh: true),
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : _posts.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        children: [
                          if (!widget.hasMainAppAccess) ...[
                            _ExploreMainAppCard(
                              onPressed: () =>
                                  CommunityNavigation.startUpgrade(context),
                            ),
                            const SizedBox(height: 18),
                          ],
                          _contactsShortcut(),
                          const SizedBox(height: 12),
                          _categoryFilters(),
                          const SizedBox(height: 22),
                          const SizedBox(height: 96),
                          const Icon(
                            Icons.forum_outlined,
                            size: 56,
                            color: AppColors.secondary,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _selectedCategory == null
                                ? 'No discussions yet. Be the first to start a conversation!'
                                : 'No discussions in this category yet.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Center(
                            child: FilledButton.icon(
                              onPressed: _createPost,
                              icon: const Icon(Icons.add),
                              label: const Text('Start a discussion'),
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        children: [
                          if (!widget.hasMainAppAccess) ...[
                            _ExploreMainAppCard(
                              onPressed: () =>
                                  CommunityNavigation.startUpgrade(context),
                            ),
                            const SizedBox(height: 12),
                          ],
                          _contactsShortcut(),
                          _categoryFilters(),
                          if (_error != null) ...[
                            _errorBanner(),
                            const SizedBox(height: 8),
                          ],
                          for (final post in _posts)
                            CommunityPostCard(
                              post: post,
                              currentProfileId: widget.profile.id,
                              onLike: () => _toggleLike(post),
                              onComments: () => _openComments(post),
                              onAuthor: () => _openAuthor(post.author),
                              onReport: () => _reportPost(post),
                              onDelete: () => _deletePost(post),
                            ),
                          if (_loadingMore)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          if (!_hasMore)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'You are all caught up.',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.outline,
                                ),
                              ),
                            ),
                        ],
                      ),
      ),
      bottomNavigationBar: AppBottomNav(
        current: AppTab.community,
        onTap: widget.onTabSelected,
        communityOnly: !widget.hasMainAppAccess,
      ),
    );
  }

  Widget _categoryFilters() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: _selectedCategory == null,
              onSelected: (_) {
                if (_selectedCategory == null) return;
                setState(() => _selectedCategory = null);
                _loadFeed(refresh: true);
              },
            ),
          ),
          for (final category in _categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(category.name),
                selected: _selectedCategory == category.slug,
                onSelected: (_) {
                  if (_selectedCategory == category.slug) return;
                  setState(() => _selectedCategory = category.slug);
                  _loadFeed(refresh: true);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _contactsShortcut() => Card(
        color: AppColors.creamSand,
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: AppColors.surfaceContainerLowest,
            child: Icon(Icons.call_outlined, color: AppColors.primary),
          ),
          title: Text(
            'Community Contacts',
            style: AppTextStyles.titleMd.copyWith(color: AppColors.textPrimary),
          ),
          subtitle: Text(
            'Manage call requests and accepted contacts',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textPrimary),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openContacts,
        ),
      );

  Widget _errorBanner() => Material(
        color: AppColors.error.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          title: Text(_error!),
          trailing: IconButton(
            tooltip: 'Retry',
            onPressed: () => _loadFeed(refresh: true),
            icon: const Icon(Icons.refresh),
          ),
        ),
      );
}

class _ExploreMainAppCard extends StatelessWidget {
  const _ExploreMainAppCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.creamSand,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Build Arch Project Management',
              style: AppTextStyles.titleMd.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Planning to build or renovate your home? Manage your projects '
              'and collaborate with construction professionals.',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Explore Main App'),
            ),
          ],
        ),
      ),
    );
  }
}
