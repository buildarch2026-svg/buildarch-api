import 'package:flutter/material.dart';

import '../models/project_notification.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<ProjectNotification> _notifications = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _loading = _notifications.isEmpty;
      _error = null;
    });
    try {
      final token = await AuthSessionService.instance.readToken();
      if (token == null || token.isEmpty) {
        throw const AuthApiException(
          'Your session expired. Please sign in again.',
        );
      }
      final inbox = await AuthApiService.instance.getNotifications(
        token: token,
      );
      if (!mounted) return;
      setState(() => _notifications = inbox.notifications);
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load notifications. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAsRead(int index) async {
    final notification = _notifications[index];
    if (notification.read) return;
    try {
      final token = await AuthSessionService.instance.readToken();
      if (token == null || token.isEmpty) {
        throw const AuthApiException(
          'Your session expired. Please sign in again.',
        );
      }
      await AuthApiService.instance.markNotificationRead(
        token: token,
        notificationId: notification.id,
      );
      if (mounted) {
        setState(() {
          _notifications[index] = notification.markRead();
        });
      }
    } on AuthApiException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) _showError('Could not update this notification.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        title: Text(
          'Notifications',
          style: AppTextStyles.cardTitle.copyWith(
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null && _notifications.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _loadNotifications,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: _notifications.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 140),
                            Icon(
                              Icons.notifications_none,
                              size: 48,
                              color: AppColors.outline,
                            ),
                            SizedBox(height: 12),
                            Center(child: Text('You are all caught up.')),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _notifications.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 72),
                          itemBuilder: (context, index) {
                            final notification = _notifications[index];
                            return ListTile(
                              onTap: () => _markAsRead(index),
                              leading: CircleAvatar(
                                backgroundColor: notification.read
                                    ? AppColors.surfaceContainerLow
                                    : AppColors.primaryContainer,
                                child: Icon(
                                  notification.event == 'chat_message'
                                      ? Icons.chat_bubble_outline
                                      : Icons.upload_file_outlined,
                                  color: notification.read
                                      ? AppColors.outline
                                      : Colors.white,
                                ),
                              ),
                              title: Text(
                                notification.title,
                                style: AppTextStyles.bodyMd.copyWith(
                                  fontWeight: notification.read
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(notification.message),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${notification.projectName} · '
                                      '${_formatDate(notification.createdAt)}',
                                      style:
                                          AppTextStyles.labelTechnical.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: notification.read
                                  ? null
                                  : const Icon(
                                      Icons.circle,
                                      size: 10,
                                      color: AppColors.primary,
                                    ),
                              isThreeLine: true,
                            );
                          },
                        ),
                ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Recently';
    final local = date.toLocal();
    final now = DateTime.now();
    if (now.difference(local) < const Duration(days: 1) &&
        now.day == local.day) {
      final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
      final minute = local.minute.toString().padLeft(2, '0');
      return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
    }
    return '${local.day}/${local.month}/${local.year}';
  }
}
