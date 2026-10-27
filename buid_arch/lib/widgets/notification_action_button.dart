import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../screens/notifications_screen.dart';

class NotificationActionButton extends StatefulWidget {
  const NotificationActionButton({super.key});

  @override
  State<NotificationActionButton> createState() =>
      _NotificationActionButtonState();
}

class _NotificationActionButtonState extends State<NotificationActionButton> {
  Timer? _refreshTimer;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadUnreadCount(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final token = await AuthSessionService.instance.readToken();
      if (token == null || token.isEmpty) return;
      final inbox = await AuthApiService.instance.getNotifications(
        token: token,
      );
      if (mounted) setState(() => _unreadCount = inbox.unreadCount);
    } on AuthApiException {
      // The full notification screen presents request errors and retry actions.
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (mounted) _loadUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _unreadCount == 0
          ? 'Notifications'
          : 'Notifications ($_unreadCount unread)',
      onPressed: _openNotifications,
      icon: Badge(
        isLabelVisible: _unreadCount > 0,
        label: Text(_unreadCount > 99 ? '99+' : '$_unreadCount'),
        child: const Icon(Icons.notifications_none),
      ),
    );
  }
}
