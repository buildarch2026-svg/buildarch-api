import 'package:flutter/material.dart';

import '../models/community.dart';
import '../navigation/community_navigation.dart';
import '../services/auth_api_service.dart';
import '../services/phone_call_service.dart';
import '../theme/app_colors.dart';

class CommunityContactAction extends StatefulWidget {
  const CommunityContactAction({
    super.key,
    required this.token,
    required this.userId,
    this.initialStatus,
    this.onStatusChanged,
    this.onMoreOptions,
    this.moreOptionsLabel = 'More options',
    this.showContactActions = true,
  });

  final String token;
  final int userId;
  final CommunityContactStatus? initialStatus;
  final ValueChanged<CommunityContactStatus>? onStatusChanged;
  final VoidCallback? onMoreOptions;
  final String moreOptionsLabel;
  final bool showContactActions;

  @override
  State<CommunityContactAction> createState() => _CommunityContactActionState();
}

class _CommunityContactActionState extends State<CommunityContactAction> {
  CommunityContactStatus? _status;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    if (_status == null) {
      _refresh();
    } else {
      _loading = false;
    }
  }

  @override
  void didUpdateWidget(covariant CommunityContactAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _status = widget.initialStatus;
      _loading = _status == null;
      if (_loading) _refresh();
    } else if (oldWidget.initialStatus?.status !=
            widget.initialStatus?.status ||
        oldWidget.initialStatus?.requestId != widget.initialStatus?.requestId ||
        oldWidget.initialStatus?.blockedByMe !=
            widget.initialStatus?.blockedByMe) {
      _status = widget.initialStatus;
      _loading = false;
    }
  }

  Future<CommunityContactStatus?> _refresh() async {
    try {
      final status = await AuthApiService.instance.getCommunityContactStatus(
        token: widget.token,
        userId: widget.userId,
      );
      if (!mounted) return status;
      setState(() {
        _status = status;
        _loading = false;
      });
      widget.onStatusChanged?.call(status);
      return status;
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (mounted) {
          await CommunityNavigation.handleUnauthorized(context, error);
        }
      }
      if (mounted) {
        setState(() => _loading = false);
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        _showMessage('Could not load call permission. Please retry.');
      }
    }
    return null;
  }

  Future<void> _sendRequest() async {
    await _runAction(() async {
      await AuthApiService.instance.sendCommunityContactRequest(
        token: widget.token,
        receiverId: widget.userId,
      );
      _showMessage('Call request sent.');
    });
  }

  Future<void> _acceptRequest() async {
    final requestId = _status?.requestId;
    if (requestId == null) return;
    await _runAction(() async {
      await AuthApiService.instance.acceptCommunityContactRequest(
        token: widget.token,
        requestId: requestId,
      );
      _showMessage('Call request accepted.');
    });
  }

  Future<void> _call() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final current = await AuthApiService.instance.getCommunityContactStatus(
        token: widget.token,
        userId: widget.userId,
      );
      if (mounted) {
        setState(() => _status = current);
        widget.onStatusChanged?.call(current);
      }
      if (current.status != 'accepted') {
        if (mounted) {
          _showMessage(
            'Call access is not enabled yet. Send a call request to connect.',
          );
        }
        return;
      }
      await PhoneCallService().call(current.phoneNumber);
    } on AuthApiException catch (error) {
      if (error.isUnauthorized && mounted) {
        await CommunityNavigation.handleUnauthorized(context, error);
      } else if (mounted) {
        _showMessage(error.message);
      }
    } on PhoneCallException catch (error) {
      if (!mounted) return;
      final message = switch (error.failure) {
        PhoneCallFailure.phoneUnavailable =>
          'Phone number is not available for this member.',
        PhoneCallFailure.invalidNumber =>
          'This member’s phone number is invalid.',
        PhoneCallFailure.notSupported =>
          'This device does not support opening a phone dialer.',
        PhoneCallFailure.launchFailed =>
          'Could not open the phone dialer. Please try again.',
      };
      _showMessage(message);
    } catch (_) {
      if (mounted) _showMessage('Could not open the phone dialer.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancelRequest() async {
    final confirmed = await _confirm(
      title: 'Cancel call request?',
      message: 'The other member will no longer see your pending request.',
      confirmLabel: 'Cancel request',
    );
    if (confirmed != true) return;
    final requestId = _status?.requestId;
    if (requestId == null) return;
    await _runAction(() async {
      await AuthApiService.instance.cancelCommunityContactRequest(
        token: widget.token,
        requestId: requestId,
      );
      _showMessage('Call request cancelled.');
    });
  }

  Future<void> _rejectRequest() async {
    final confirmed = await _confirm(
      title: 'Decline call request?',
      message: 'This member will not be able to call you through Community.',
      confirmLabel: 'Decline',
    );
    if (confirmed != true) return;
    final requestId = _status?.requestId;
    if (requestId == null) return;
    await _runAction(() async {
      await AuthApiService.instance.rejectCommunityContactRequest(
        token: widget.token,
        requestId: requestId,
      );
      _showMessage('Call request declined.');
    });
  }

  Future<void> _revokePermission() async {
    final confirmed = await _confirm(
      title: 'Revoke call permission?',
      message:
          'Neither of you will be able to call each other through Community.',
      confirmLabel: 'Revoke permission',
    );
    if (confirmed != true) return;
    await _runAction(() async {
      await AuthApiService.instance.revokeCommunityContact(
        token: widget.token,
        userId: widget.userId,
      );
      _showMessage('Call permission revoked.');
    });
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) =>
      showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(message),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(confirmLabel),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep permission'),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _runAction(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
      await _refresh();
    } on AuthApiException catch (error) {
      if (error.isUnauthorized && mounted) {
        await CommunityNavigation.handleUnauthorized(context, error);
      } else if (mounted) {
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) _showMessage('Could not update call permission.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 44,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final status = _status?.status ?? 'none';
    final action = switch (status) {
      'blocked' => null,
      'accepted' => _Action('Call', Icons.call_outlined, _call),
      'incoming_pending' => _Action(
          'Accept Call Request', Icons.check_circle_outline, _acceptRequest),
      'outgoing_pending' =>
        const _Action('Request Pending', Icons.hourglass_top, null),
      'rejected' =>
        const _Action('Request Declined', Icons.call_end_outlined, null),
      _ => _Action('Request Call', Icons.phone_callback_outlined, _sendRequest),
    };

    if (status == 'blocked') {
      return Row(
        children: [
          Text(
            _status?.blockedByMe == true
                ? 'You blocked this member.'
                : 'Member unavailable.',
          ),
          const Spacer(),
          if (widget.onMoreOptions != null) _moreOptions(status),
        ],
      );
    }

    if (!widget.showContactActions) {
      return Align(
        alignment: Alignment.centerRight,
        child: _moreOptions(status),
      );
    }

    final statusLabel = switch (status) {
      'accepted' => _status?.phoneNumber == null
          ? 'Connected, but no phone number is available'
          : 'You can call each other',
      'incoming_pending' => 'This member wants to connect',
      'outgoing_pending' => 'Waiting for their response',
      'rejected' => 'This request was declined',
      'revoked' => 'Call permission was revoked',
      _ => 'Call permission requires both members’ approval',
    };
    final isPending = status == 'outgoing_pending';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _working ? null : action?.onPressed,
                icon: _working
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(action?.icon ?? Icons.phone_disabled_outlined),
                label: Text(action?.label ?? 'Call unavailable'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  backgroundColor: status == 'rejected'
                      ? AppColors.outline
                      : AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _moreOptions(status),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          statusLabel,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
        ),
        if (isPending && status == 'outgoing_pending')
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _working ? null : _cancelRequest,
              child: const Text('Cancel request'),
            ),
          ),
      ],
    );
  }

  Widget _moreOptions(String status) {
    final items = <PopupMenuEntry<String>>[
      if (widget.showContactActions && status == 'incoming_pending')
        const PopupMenuItem(
          value: 'reject',
          child: Text('Reject request'),
        ),
      if (widget.showContactActions && status == 'accepted')
        const PopupMenuItem(
          value: 'revoke',
          child: Text('Revoke call permission'),
        ),
      if (widget.onMoreOptions != null)
        PopupMenuItem(
          value: 'more',
          child: Text(widget.moreOptionsLabel),
        ),
    ];
    if (items.isEmpty) return const SizedBox(width: 8);

    return PopupMenuButton<String>(
      tooltip: 'More options',
      enabled: !_working,
      onSelected: (value) {
        switch (value) {
          case 'reject':
            _rejectRequest();
            break;
          case 'revoke':
            _revokePermission();
            break;
          case 'more':
            widget.onMoreOptions?.call();
            break;
        }
      },
      itemBuilder: (_) => items,
      child: const SizedBox(
        width: 48,
        height: 48,
        child: Icon(Icons.more_horiz),
      ),
    );
  }
}

class _Action {
  const _Action(this.label, this.icon, this.onPressed);

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
}
