import 'package:flutter/material.dart';

import '../models/community.dart';
import '../navigation/community_navigation.dart';
import '../services/auth_api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/community_avatar.dart';
import '../widgets/community_post_card.dart';

class CommunityPostDetailScreen extends StatefulWidget {
  const CommunityPostDetailScreen({
    super.key,
    required this.token,
    required this.post,
    required this.currentProfileId,
  });

  final String token;
  final CommunityPost post;
  final int currentProfileId;

  @override
  State<CommunityPostDetailScreen> createState() =>
      _CommunityPostDetailScreenState();
}

class _CommunityPostDetailScreenState extends State<CommunityPostDetailScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<CommunityComment> _comments = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  bool _liking = false;
  String? _error;
  int? _replyToId;
  String? _replyToName;
  bool _changed = false;
  int _commentCountDelta = 0;
  late CommunityPost _post = widget.post;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadComments();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 300 &&
        !_loading &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadComments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AuthApiService.instance.getCommunityComments(
        token: widget.token,
        postId: widget.post.id,
        page: 1,
      );
      if (!mounted) return;
      setState(() {
        _comments = result.items;
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
      if (mounted) setState(() => _error = 'Could not load replies.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final result = await AuthApiService.instance.getCommunityComments(
        token: widget.token,
        postId: widget.post.id,
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, ...result.items];
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
      if (mounted) setState(() => _error = 'Could not load more replies.');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _sendComment() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final comment = await AuthApiService.instance.createCommunityComment(
        token: widget.token,
        postId: widget.post.id,
        content: content,
        parentCommentId: _replyToId,
      );
      if (!mounted) return;
      setState(() {
        if (comment.parentCommentId == null) {
          _comments = [comment, ..._comments];
        } else {
          _comments = _comments.map((parent) {
            if (parent.id != comment.parentCommentId) return parent;
            return CommunityComment(
              id: parent.id,
              postId: parent.postId,
              parentCommentId: parent.parentCommentId,
              content: parent.content,
              author: parent.author,
              repliesCount: parent.repliesCount + 1,
              createdAt: parent.createdAt,
              replies: [...parent.replies, comment],
            );
          }).toList();
        }
        _controller.clear();
        _replyToId = null;
        _replyToName = null;
        _changed = true;
        _commentCountDelta++;
      });
      FocusScope.of(context).unfocus();
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      } else if (mounted) {
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) _showMessage('Could not send your reply. Please retry.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleLike() async {
    if (_liking) return;
    setState(() => _liking = true);
    try {
      final result = await AuthApiService.instance.toggleCommunityLike(
        token: widget.token,
        postId: _post.id,
      );
      if (!mounted) return;
      setState(() {
        _post = _post.copyWith(
          likedByMe: result.liked,
          likesCount: result.likesCount,
        );
        _changed = true;
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
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _deleteComment(CommunityComment comment) async {
    try {
      await AuthApiService.instance.deleteCommunityComment(
        token: widget.token,
        postId: widget.post.id,
        commentId: comment.id,
      );
      if (!mounted) return;
      setState(() {
        _comments = _comments
            .where((item) => item.id != comment.id)
            .map((item) => CommunityComment(
                  id: item.id,
                  postId: item.postId,
                  parentCommentId: item.parentCommentId,
                  content: item.content,
                  author: item.author,
                  repliesCount: item.repliesCount,
                  createdAt: item.createdAt,
                  replies: item.replies
                      .where((reply) => reply.id != comment.id)
                      .toList(),
                ))
            .toList();
        _changed = true;
        _commentCountDelta -=
            comment.parentCommentId == null ? 1 + comment.repliesCount : 1;
      });
      _showMessage('Reply deleted.');
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      } else if (mounted) {
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) _showMessage('Could not delete the reply.');
    }
  }

  Future<void> _reportComment(CommunityComment comment) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Report reply'),
        children: [
          for (final entry in const {
            'spam': 'Spam',
            'harassment': 'Harassment',
            'misinformation': 'Misinformation',
            'inappropriate': 'Inappropriate content',
            'other': 'Other',
          }.entries)
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
        targetType: 'comment',
        targetId: comment.id,
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
      if (mounted) _showMessage('Could not send your report.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Discussion'),
        backgroundColor: AppColors.surface,
        leading: BackButton(onPressed: () => Navigator.pop(context, _changed)),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading && _comments.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadComments,
                    child: ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      children: [
                        CommunityPostCard(
                          post: post,
                          currentProfileId: widget.currentProfileId,
                          onLike: () {},
                          onComments: () {},
                          onAuthor: () {},
                          onReport: () {},
                          onDelete: () {},
                          showActions: false,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: post.likedByMe
                                    ? 'Unlike post'
                                    : 'Like post',
                                onPressed: _liking ? null : _toggleLike,
                                icon: _liking
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        post.likedByMe
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: post.likedByMe
                                            ? AppColors.error
                                            : AppColors.outline,
                                      ),
                              ),
                              Text(
                                '${post.likesCount} '
                                '${post.likesCount == 1 ? 'like' : 'likes'}',
                                style: AppTextStyles.bodyMd,
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.mode_comment_outlined,
                                size: 18,
                                color: AppColors.outline,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${post.commentsCount + _commentCountDelta} '
                                '${post.commentsCount + _commentCountDelta == 1 ? 'reply' : 'replies'}',
                                style: AppTextStyles.bodySm,
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                          child: Text(
                            'Replies (${post.commentsCount + _commentCountDelta})',
                            style: AppTextStyles.titleMd,
                          ),
                        ),
                        if (_error != null)
                          ListTile(
                            title: Text(_error!),
                            trailing: IconButton(
                              onPressed: _loadComments,
                              icon: const Icon(Icons.refresh),
                            ),
                          ),
                        if (!_loading && _comments.isEmpty && _error == null)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'No replies yet. Add the first reply.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        for (final comment in _comments) ...[
                          _commentTile(comment),
                          for (final reply in comment.replies)
                            Padding(
                              padding: const EdgeInsets.only(left: 30),
                              child: _commentTile(reply),
                            ),
                        ],
                        if (_loadingMore)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  ),
          ),
          if (_replyToName != null)
            Material(
              color: AppColors.surfaceContainerLow,
              child: ListTile(
                dense: true,
                title: Text('Replying to $_replyToName'),
                trailing: IconButton(
                  onPressed: () => setState(() {
                    _replyToId = null;
                    _replyToName = null;
                  }),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Write a reply...',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _sendComment(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendComment,
                    tooltip: 'Send reply',
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentTile(CommunityComment comment) {
    final isMine = comment.author.id == widget.currentProfileId;
    final time = comment.createdAt?.toLocal();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CommunityAvatar(
                  imageUrl: comment.author.profileImageUrl,
                  displayName: comment.author.displayName,
                  radius: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.author.displayName,
                        style: AppTextStyles.bodySm.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${comment.author.profession}'
                        '${time == null ? '' : ' · ${time.day}/${time.month}/${time.year}'}',
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'reply') {
                      setState(() {
                        _replyToId = comment.parentCommentId ?? comment.id;
                        _replyToName = comment.author.displayName;
                      });
                    } else if (action == 'delete') {
                      _deleteComment(comment);
                    } else {
                      _reportComment(comment);
                    }
                  },
                  itemBuilder: (_) => [
                    if (comment.parentCommentId == null)
                      const PopupMenuItem(
                        value: 'reply',
                        child: Text('Reply'),
                      ),
                    if (isMine)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      )
                    else
                      const PopupMenuItem(
                        value: 'report',
                        child: Text('Report'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(comment.content),
            if (comment.parentCommentId == null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() {
                    _replyToId = comment.id;
                    _replyToName = comment.author.displayName;
                  }),
                  child: const Text('Reply'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
