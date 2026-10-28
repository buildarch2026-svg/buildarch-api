import 'dart:typed_data' as typed_data;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project.dart';
import '../models/project_invitation.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class ProjectInvitationsScreen extends StatefulWidget {
  const ProjectInvitationsScreen({super.key, required this.project});

  final Project project;

  @override
  State<ProjectInvitationsScreen> createState() =>
      _ProjectInvitationsScreenState();
}

class _ProjectInvitationsScreenState extends State<ProjectInvitationsScreen> {
  List<ProjectInvitation> _invitations = [];
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInvitations();
  }

  Future<String> _requireToken() async {
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthApiException(
          'Your session expired. Please sign in again.');
    }
    return token;
  }

  Future<void> _loadInvitations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _requireToken();
      final invitations = await AuthApiService.instance.getProjectInvitations(
        token: token,
        projectId: widget.project.id,
      );
      if (!mounted) return;
      setState(() => _invitations = invitations);
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load invitations.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createInvitation(String role) async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final token = await _requireToken();
      final invitation = await AuthApiService.instance.createProjectInvitation(
        token: token,
        projectId: widget.project.id,
        role: role,
      );
      if (!mounted) return;
      setState(() => _invitations = [invitation, ..._invitations]);
      await _showInvitationQr(invitation);
    } on AuthApiException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Could not create the invitation. Please try again.');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _revoke(ProjectInvitation invitation) async {
    try {
      final token = await _requireToken();
      await AuthApiService.instance.revokeProjectInvitation(
        token: token,
        projectId: widget.project.id,
        invitationId: invitation.id,
      );
      await _loadInvitations();
    } on AuthApiException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Could not revoke the invitation. Please try again.');
    }
  }

  Future<void> _showInvitationQr(ProjectInvitation invitation) async {
    final token = invitation.token;
    if (token == null) {
      _showMessage('This invitation does not have a shareable link.');
      return;
    }

    final link = invitation.qrLink;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Invite ${_roleName(invitation.role)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 220,
              child: QrImageView(
                data: link.toString(),
                size: 220,
                backgroundColor: Colors.white,
                errorStateBuilder: (context, error) => const Text(
                  'Could not generate the QR code.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Scan this code with Build Arch. The invite expires '
              '${_date(invitation.expiresAt)}.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () => _shareInvitationQr(invitation, link),
            icon: const Icon(Icons.share),
            label: const Text('Share QR code'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareInvitationQr(
    ProjectInvitation invitation,
    Uri link,
  ) async {
    try {
      const imageSize = 800.0;
      const quietZone = 80.0;
      final painter = QrPainter(
        data: link.toString(),
        version: QrVersions.auto,
        gapless: true,
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(Colors.white, ui.BlendMode.src);
      canvas
        ..save()
        ..translate(quietZone, quietZone);
      painter.paint(
        canvas,
        const Size(
          imageSize - quietZone * 2,
          imageSize - quietZone * 2,
        ),
      );
      canvas.restore();

      final picture = recorder.endRecording();
      late final ui.Image image;
      try {
        image = await picture.toImage(
          imageSize.toInt(),
          imageSize.toInt(),
        );
      } finally {
        picture.dispose();
      }
      late final typed_data.ByteData? imageData;
      try {
        imageData = await image.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        image.dispose();
      }
      if (imageData == null) {
        throw const FormatException('Could not encode the invitation QR code.');
      }

      final fileName = 'invitation-${invitation.id}-qr.png';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              imageData.buffer.asUint8List(
                imageData.offsetInBytes,
                imageData.lengthInBytes,
              ),
              mimeType: 'image/png',
              name: fileName,
            ),
          ],
          fileNameOverrides: [fileName],
          text: 'Join ${widget.project.name} as '
              '${_roleName(invitation.role)}: $link',
          subject: 'Project invitation',
        ),
      );
    } on PlatformException {
      if (mounted) _showMessage('Could not share this invitation QR code.');
    } on Exception {
      if (mounted) _showMessage('Could not create the invitation QR image.');
    }
  }

  Future<void> _confirmRevoke(ProjectInvitation invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke invitation?'),
        content: const Text(
          'Anyone with this QR code or link will no longer be able to use it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _revoke(invitation);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _roleName(String role) =>
      role == 'contractor' ? 'Contractor' : 'Designer';

  String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Project invitations'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
      ),
      body: RefreshIndicator(
        onRefresh: _loadInvitations,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.home_work_outlined,
                    color: AppColors.secondary,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleMd.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _roleAction(
                    icon: Icons.engineering_outlined,
                    label: 'Contractor',
                    onPressed: _creating
                        ? null
                        : () => _createInvitation('contractor'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _roleAction(
                    icon: Icons.design_services_outlined,
                    label: 'Designer',
                    onPressed:
                        _creating ? null : () => _createInvitation('designer'),
                  ),
                ),
              ],
            ),
            if (_creating) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(
                  Icons.qr_code_2_rounded,
                  size: 20,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Invitations',
                  style: AppTextStyles.titleMd.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _errorPanel()
            else if (_invitations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No invitations yet.'),
              )
            else
              for (final invitation in _invitations)
                _invitationCard(invitation),
          ],
        ),
      ),
    );
  }

  Widget _roleAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.surfaceContainerLow,
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 25),
          const SizedBox(height: 7),
          Text(label),
        ],
      ),
    );
  }

  Widget _errorPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(_error!, textAlign: TextAlign.center),
          TextButton(onPressed: _loadInvitations, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _invitationCard(ProjectInvitation invitation) {
    final pending = invitation.status == 'pending';
    final roleIcon = invitation.role == 'contractor'
        ? Icons.engineering_outlined
        : Icons.design_services_outlined;
    return Card(
      color: AppColors.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(roleIcon, color: AppColors.secondary, size: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _roleName(invitation.role),
                style: AppTextStyles.bodyMd.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _statusChip(invitation.status),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 14,
                color: AppColors.outline,
              ),
              const SizedBox(width: 5),
              Text(
                'Expires ${_date(invitation.expiresAt)}',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'qr') _showInvitationQr(invitation);
            if (action == 'revoke') _confirmRevoke(invitation);
          },
          itemBuilder: (context) => [
            if (invitation.token != null)
              const PopupMenuItem(value: 'qr', child: Text('View QR code')),
            if (pending)
              const PopupMenuItem(
                value: 'revoke',
                child: Text('Revoke invitation'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final isAccepted = status == 'accepted';
    final color = isAccepted ? AppColors.success : AppColors.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _status(status),
        style: AppTextStyles.bodySm.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _status(String value) => switch (value) {
        'pending' => 'Pending',
        'accepted' => 'Accepted',
        'declined' => 'Declined',
        'expired' => 'Expired',
        'revoked' => 'Revoked',
        _ => value,
      };
}
