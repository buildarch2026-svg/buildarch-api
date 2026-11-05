import 'dart:async';

import 'package:flutter/material.dart';

import '../models/project_chat_conversation.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'project_direct_chat_screen.dart';
import 'project_group_voice_chat_screen.dart';

class ProjectChatsScreen extends StatefulWidget {
  const ProjectChatsScreen({super.key});

  @override
  State<ProjectChatsScreen> createState() => _ProjectChatsScreenState();
}

class _ProjectChatsScreenState extends State<ProjectChatsScreen>
    with WidgetsBindingObserver {
  List<ProjectChatConversation> _chats = [];
  Timer? _refreshTimer;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChats();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed) {
          _loadChats(showLoading: false);
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadChats(showLoading: false);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadChats({bool showLoading = true}) async {
    if (_refreshing) return;
    _refreshing = true;
    setState(() {
      if (showLoading && _chats.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final token = await AuthSessionService.instance.readToken();
      if (token == null || token.isEmpty) {
        throw const AuthApiException(
          'Your session expired. Please sign in again.',
        );
      }
      final chats = await AuthApiService.instance.getChats(token: token);
      if (!mounted) return;
      setState(() => _chats = chats);
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your chats.');
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChat(ProjectChatConversation chat) async {
    final project = chat.toProject();
    final screen = chat.isGroup
        ? ProjectGroupVoiceChatScreen(project: project)
        : chat.counterpartUserId == null ||
                chat.conversationMemberUserId == null
            ? null
            : ProjectDirectChatScreen(
                project: project,
                member: chat.toCounterpart(),
                conversationMemberUserId: chat.conversationMemberUserId!,
              );
    if (screen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This conversation is unavailable.')),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) await _loadChats();
  }

  String _timeLabel(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Chats'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        actions: [
          IconButton(
            tooltip: 'Refresh chats',
            onPressed: _loading || _refreshing ? null : _loadChats,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _chats.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _chats.isEmpty
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: _loadChats,
                  child: _chats.isEmpty
                      ? _emptyState()
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (_error != null) ...[
                              _refreshErrorBanner(),
                              const SizedBox(height: 8),
                            ],
                            for (var index = 0; index < _chats.length; index++)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: index == _chats.length - 1 ? 0 : 8,
                                ),
                                child: _chatTile(_chats[index]),
                              ),
                          ],
                        ),
                ),
    );
  }

  Widget _refreshErrorBanner() => Material(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: const Icon(Icons.cloud_off_outlined),
          title: Text(_error!),
          trailing: IconButton(
            tooltip: 'Retry',
            onPressed:
                _refreshing ? null : () => _loadChats(showLoading: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
      );

  Widget _chatTile(ProjectChatConversation chat) {
    final isGroup = chat.isGroup;
    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openChat(chat),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: AppColors.primaryContainer.withAlpha(20),
                child: Icon(
                  isGroup ? Icons.groups_2_outlined : Icons.person_outline,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleMd.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          _timeLabel(chat.lastMessageAt),
                          style: AppTextStyles.labelTechnical.copyWith(
                            color: AppColors.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${chat.projectName} · ${isGroup ? 'Project group' : 'Private chat'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelTechnical.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      chat.lastMessage ?? 'No messages yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (chat.unreadCount > 0) ...[
                const SizedBox(width: 10),
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: const BoxDecoration(
                    color: AppColors.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelTechnical.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 48,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your project chats will appear here',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleMd,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Open a project team chat or message a team member to get started.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loadChats,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
}
