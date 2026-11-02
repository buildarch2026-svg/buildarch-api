import 'package:flutter/material.dart';

import '../models/project_invitation.dart';
import '../services/account_session_service.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../services/pending_invitation_service.dart';
import '../services/projects_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'login_screen.dart';
import 'projects_screen.dart';

class InvitationDetailsScreen extends StatefulWidget {
  const InvitationDetailsScreen({
    super.key,
    required this.invitationToken,
  });

  final String invitationToken;

  @override
  State<InvitationDetailsScreen> createState() =>
      _InvitationDetailsScreenState();
}

class _InvitationDetailsScreenState extends State<InvitationDetailsScreen> {
  ProjectInvitationDetails? _details;
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<String> _requireToken() async {
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthApiException('Please sign in to view this invitation.');
    }
    return token;
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessionToken = await _requireToken();
      final details = await AuthApiService.instance.getInvitationDetails(
        token: sessionToken,
        invitationToken: widget.invitationToken,
      );
      if (!mounted) return;
      setState(() => _details = details);
      if (details.invitation.status != 'pending') {
        await PendingInvitationService.instance.clear();
      }
    } on AuthApiException catch (error) {
      if (error.statusCode == 404) {
        await PendingInvitationService.instance.clear();
      } else if (error.statusCode == 401) {
        await AccountSessionService.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        return;
      }
      if (mounted) setState(() => _error = _invitationError(error));
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load this invitation. It remains saved; check '
              'your connection and tap Retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept() async {
    final details = _details;
    if (details == null || !details.canAccept || _submitting) return;
    setState(() => _submitting = true);
    try {
      final sessionToken = await _requireToken();
      await AuthApiService.instance.acceptProjectInvitation(
        token: sessionToken,
        invitationToken: widget.invitationToken,
      );
      await PendingInvitationService.instance.clear();
      ProjectsStore.instance.clear();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const ProjectsScreen(initialTabIndex: 1),
        ),
        (route) => false,
      );
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(_invitationError(error));
      await _loadDetails();
    } catch (_) {
      if (mounted) {
        _showMessage('Could not accept the invitation. It is still saved; '
            'check your connection and retry.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _decline() async {
    final details = _details;
    if (details == null || !details.canAccept || _submitting) return;
    setState(() => _submitting = true);
    try {
      final sessionToken = await _requireToken();
      await AuthApiService.instance.declineProjectInvitation(
        token: sessionToken,
        invitationToken: widget.invitationToken,
      );
      await PendingInvitationService.instance.clear();
      await _loadDetails();
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(_invitationError(error));
      await _loadDetails();
    } catch (_) {
      if (mounted) {
        _showMessage('Could not decline the invitation. Check your connection '
            'and retry.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _roleName(String? role) => role == 'contractor'
      ? 'Contractor'
      : role == 'designer'
          ? 'Designer'
          : 'General invitation';

  String _invitationError(AuthApiException error) {
    if (error.statusCode == 404) {
      return 'This invitation link is invalid or no longer available. Ask the '
          'project owner to send a new invitation.';
    }
    if (error.statusCode == 410) {
      return 'This invitation has expired. Ask the project owner to send a new '
          'invitation.';
    }
    if (error.statusCode == 409) {
      return 'This invitation can no longer be used. It may have been revoked, '
          'accepted, or declined.';
    }
    if (error.statusCode == null || error.statusCode! >= 500) {
      return 'We could not reach the service. Your invitation is still saved. '
          'Check your connection and tap Retry.';
    }
    return error.message;
  }

  String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _statusText(ProjectInvitationDetails details) {
    switch (details.invitation.status) {
      case 'expired':
        return 'This invitation has expired. Ask the project owner to send a '
            'new invitation.';
      case 'revoked':
        return 'The project owner revoked this invitation. It can no longer be '
            'accepted.';
      case 'declined':
        return 'This invitation was declined and can no longer be accepted.';
      case 'accepted':
        return 'This invitation has already been accepted.';
      case 'pending':
        break;
      default:
        return 'This invitation is no longer available.';
    }
    if (!details.canAccept) {
      return 'Sign in with a Build Arch account that is not already a member '
          'of this project.';
    }
    return 'You have been invited to join this project.';
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Project invitation'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorPanel()
              : details == null
                  ? _errorPanel()
                  : _detailsPanel(details),
    );
  }

  Widget _errorPanel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off, size: 44, color: AppColors.outline),
            const SizedBox(height: 16),
            Text(_error ?? 'Invitation details are unavailable.',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadDetails,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailsPanel(ProjectInvitationDetails details) {
    final invitation = details.invitation;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          color: AppColors.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.group_add_outlined,
                  size: 36,
                  color: AppColors.secondary,
                ),
                const SizedBox(height: 16),
                Text(
                  details.project.name,
                  style: AppTextStyles.cardTitle.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(details.project.location),
                const Divider(height: 28),
                _detailLine('Owner', details.ownerName),
                _detailLine('Invitee', invitation.inviteeName ?? 'Project invitee'),
                _detailLine(
                  'Designation',
                  invitation.inviteeDesignation ?? 'General invite',
                ),
                _detailLine(
                    'Invited by', invitation.inviterName ?? 'Project owner'),
                _detailLine('Invitation date', _date(invitation.createdAt)),
                _detailLine('Expires', _date(invitation.expiresAt)),
                _detailLine('Status', invitation.status),
                const SizedBox(height: 16),
                Text(
                  _statusText(details),
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (details.canAccept) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _accept,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Accept invitation'),
          ),
          OutlinedButton(
            onPressed: _submitting ? null : _decline,
            child: const Text('Decline invitation'),
          ),
        ] else if (invitation.status == 'pending') ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _switchAccount,
            icon: const Icon(Icons.switch_account),
            label: const Text('Switch account'),
          ),
        ],
      ],
    );
  }

  Future<void> _switchAccount() async {
    await AccountSessionService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 122,
            child: Text(
              label,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
