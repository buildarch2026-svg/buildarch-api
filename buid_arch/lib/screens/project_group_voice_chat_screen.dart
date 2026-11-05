import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project.dart';
import '../models/project_member.dart';
import '../models/project_message.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../services/current_location_service.dart';
import '../services/project_chat_realtime_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/project_chat_forward_dialog.dart';

class ProjectGroupVoiceChatScreen extends StatefulWidget {
  const ProjectGroupVoiceChatScreen({super.key, required this.project});

  final Project project;

  @override
  State<ProjectGroupVoiceChatScreen> createState() =>
      _ProjectGroupVoiceChatScreenState();
}

class _ProjectGroupVoiceChatScreenState
    extends State<ProjectGroupVoiceChatScreen> {
  final _recorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  final _messageController = TextEditingController();
  final _messages = <ProjectMessage>[];
  final _downloadedAttachments = <int, File>{};
  Timer? _refreshTimer;
  Timer? _recordingTimer;
  ProjectChatRealtimeService? _realtime;
  StreamSubscription<void>? _audioCompleteSubscription;
  List<ProjectMember> _members = [];
  int? _currentUserId;
  int _lastMessageId = 0;
  int _recordingSeconds = 0;
  int? _playingMessageId;
  int? _replyToMessageId;
  int? _editingMessageId;
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingOlder = false;
  bool _hasMoreMessages = true;
  bool _recording = false;
  bool _sending = false;
  String? _error;
  String? _connectionStatus;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadMessages();
    _startRealtime();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadMessages(showErrors: false, syncRecent: true),
    );
    _audioCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingMessageId = null);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _recordingTimer?.cancel();
    unawaited(_realtime?.dispose());
    _audioCompleteSubscription?.cancel();
    unawaited(_recorder.dispose());
    unawaited(_audioPlayer.dispose());
    _messageController.dispose();
    super.dispose();
  }

  Future<String> _requireToken() async {
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthApiException(
        'Your session expired. Please sign in again.',
      );
    }
    return token;
  }

  Future<void> _loadMembers() async {
    try {
      final token = await _requireToken();
      final members = await AuthApiService.instance.getProjectMembers(
        token: token,
        projectId: widget.project.id,
      );
      final user = await AuthSessionService.instance.readUser();
      final rawId = user?['id'];
      final currentUserId =
          rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '');
      if (!mounted) return;
      setState(() {
        _members = members;
        _currentUserId = currentUserId;
      });
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not load the project members.');
    }
  }

  Future<void> _startRealtime() async {
    try {
      final token = await _requireToken();
      if (!mounted) return;
      final realtime = ProjectChatRealtimeService(
        token: token,
        channelName: 'private-project-chat.group.${widget.project.id}',
        onMessage: _onRealtimeMessage,
        onStatusChanged: (status) {
          if (mounted && _connectionStatus != status) {
            setState(() => _connectionStatus = status);
          }
        },
      );
      _realtime = realtime;
      await realtime.connect();
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _connectionStatus = error.message);
    }
  }

  void _onRealtimeMessage(Map<String, dynamic> json) {
    try {
      final message = ProjectMessage.fromJson(json);
      if (!mounted) return;
      final index = _messages.indexWhere((item) => item.id == message.id);
      setState(() {
        if (index >= 0) {
          _messages[index] = message;
        } else {
          _messages.add(message);
          _messages.sort((a, b) => a.id.compareTo(b.id));
        }
        if (message.id > _lastMessageId) _lastMessageId = message.id;
      });
      unawaited(_markRead());
    } on FormatException catch (error) {
      if (mounted) setState(() => _connectionStatus = error.message);
    }
  }

  Future<void> _loadMessages({
    bool showErrors = true,
    bool syncRecent = false,
  }) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final token = await _requireToken();
      final isInitialLoad = _messages.isEmpty && _lastMessageId == 0;
      var firstPageCount = 0;
      var cursor = _lastMessageId;
      final incoming = <ProjectMessage>[];
      while (true) {
        final page = await AuthApiService.instance.getProjectGroupMessages(
          token: token,
          projectId: widget.project.id,
          afterId: isInitialLoad ? 0 : cursor,
        );
        if (isInitialLoad) firstPageCount = page.length;
        incoming.addAll(page);
        if (isInitialLoad || page.length < 100 || page.isEmpty) break;
        final nextCursor = page.last.id;
        if (nextCursor <= cursor) break;
        cursor = nextCursor;
      }
      if (syncRecent && !isInitialLoad) {
        incoming.addAll(
          await AuthApiService.instance.getProjectGroupMessages(
            token: token,
            projectId: widget.project.id,
          ),
        );
      }
      if (!mounted) return;
      final oldLastMessageId = _lastMessageId;
      final merged = {for (final message in _messages) message.id: message};
      for (final message in incoming) {
        merged[message.id] = message;
        if (message.id > _lastMessageId) _lastMessageId = message.id;
      }
      setState(() {
        _messages
          ..clear()
          ..addAll(merged.values)
          ..sort((a, b) => a.id.compareTo(b.id));
        if (isInitialLoad) _hasMoreMessages = firstPageCount == 100;
        _error = null;
      });
      if (incoming.any((message) => message.id > oldLastMessageId) ||
          isInitialLoad) {
        unawaited(_markRead(token: token));
      }
    } on AuthApiException catch (error) {
      if (!mounted) return;
      if (showErrors) setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      if (showErrors) {
        setState(() => _error = 'Could not load the project voice chat.');
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || !_hasMoreMessages || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      final token = await _requireToken();
      final messages = await AuthApiService.instance.getProjectGroupMessages(
        token: token,
        projectId: widget.project.id,
        beforeId: _messages.first.id,
      );
      if (!mounted) return;
      final currentIds = _messages.map((message) => message.id).toSet();
      final olderMessages = messages
          .where((message) => !currentIds.contains(message.id))
          .toList();
      setState(() {
        _messages.insertAll(0, olderMessages);
        _hasMoreMessages = messages.length == 100;
      });
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not load older messages.');
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _markRead({String? token}) async {
    try {
      final accessToken = token ?? await _requireToken();
      await AuthApiService.instance.markProjectGroupChatRead(
        token: accessToken,
        projectId: widget.project.id,
      );
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _connectionStatus = error.message);
    }
  }

  Future<void> _toggleRecording() async {
    if (_sending) return;
    if (_recording) {
      await _stopRecording(send: true);
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        _showMessage('Microphone permission is needed to record a voice note.');
        return;
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}${Platform.pathSeparator}'
          'group-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordingSeconds = 0;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordingSeconds++);
        if (_recordingSeconds >= 300) {
          unawaited(_stopRecording(send: true));
        }
      });
    } on PlatformException {
      if (mounted) _showMessage('Could not start voice recording.');
    } catch (_) {
      if (mounted) _showMessage('Could not start voice recording.');
    }
  }

  Future<void> _sendText() async {
    final body = _messageController.text.trim();
    if (body.isEmpty || _sending || _recording) return;
    if (body.length > 4000) {
      _showMessage('Messages can be up to 4,000 characters.');
      return;
    }
    setState(() => _sending = true);
    try {
      final token = await _requireToken();
      final editingId = _editingMessageId;
      final message = editingId == null
          ? await AuthApiService.instance.sendProjectGroupText(
              token: token,
              projectId: widget.project.id,
              body: body,
              replyToMessageId: _replyToMessageId,
            )
          : await AuthApiService.instance.updateProjectGroupMessage(
              token: token,
              projectId: widget.project.id,
              messageId: editingId,
              body: body,
            );
      if (!mounted) return;
      _messageController.clear();
      setState(() {
        _replyToMessageId = null;
        _editingMessageId = null;
        _error = null;
      });
      _upsertMessage(message);
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not send this message.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    if (_sending || _recording) return;
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (!mounted || source == null) return;

      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (image == null) return;
      setState(() => _sending = true);
      final token = await _requireToken();
      final message = await AuthApiService.instance.sendProjectGroupAttachment(
        token: token,
        projectId: widget.project.id,
        file: image,
        messageType: 'image',
        replyToMessageId: _replyToMessageId,
      );
      if (!mounted) return;
      _upsertMessage(message);
      setState(() => _replyToMessageId = null);
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } on PlatformException {
      if (mounted) _showMessage('Could not capture or select that image.');
    } catch (_) {
      if (mounted) _showMessage('Could not capture or send that image.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickPdf() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (file == null) return;
      final size = await file.length();
      final path = file.path;
      if (size == null || path == null) {
        _showMessage('Could not read the selected PDF.');
        return;
      }
      if (size > 25 * 1024 * 1024) {
        _showMessage('Files must be 25 MB or smaller.');
        return;
      }
      setState(() => _sending = true);
      final token = await _requireToken();
      final message = await AuthApiService.instance.sendProjectGroupAttachment(
        token: token,
        projectId: widget.project.id,
        file: XFile(path, name: file.name),
        messageType: 'file',
        replyToMessageId: _replyToMessageId,
      );
      if (!mounted) return;
      _upsertMessage(message);
      setState(() => _replyToMessageId = null);
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } on PlatformException {
      if (mounted) _showMessage('Could not access the selected PDF.');
    } catch (_) {
      if (mounted) _showMessage('Could not upload this PDF.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _shareCurrentLocation() async {
    try {
      final location =
          await CurrentLocationService.instance.getCurrentLocation();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Share your location?'),
          content: Text(
              '${location.address}\n\nYour current location will be shared '
              'with this project conversation.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Share location'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final token = await _requireToken();
      final message = await AuthApiService.instance.sendProjectGroupLocation(
        token: token,
        projectId: widget.project.id,
        latitude: location.latitude,
        longitude: location.longitude,
        address: location.address,
        replyToMessageId: _replyToMessageId,
      );
      _upsertMessage(message);
      setState(() => _replyToMessageId = null);
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } on CurrentLocationException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not share your current location.');
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      final path = await _recorder.stop();
      if (mounted) setState(() => _recording = false);
      if (path == null) return;
      final file = File(path);
      if (!send) {
        if (await file.exists()) await file.delete();
        return;
      }
      setState(() => _sending = true);
      final token = await _requireToken();
      final message = await AuthApiService.instance.sendProjectGroupVoice(
        token: token,
        projectId: widget.project.id,
        file: file,
        replyToMessageId: _replyToMessageId,
      );
      if (!mounted) return;
      _upsertMessage(message);
      setState(() => _replyToMessageId = null);
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } on PlatformException {
      if (mounted) _showMessage('Could not finish the voice recording.');
    } catch (_) {
      if (mounted) _showMessage('Could not send this voice message.');
    } finally {
      if (mounted) {
        setState(() {
          _recording = false;
          _sending = false;
        });
      }
    }
  }

  void _upsertMessage(ProjectMessage message) {
    if (!mounted) return;
    final index = _messages.indexWhere((item) => item.id == message.id);
    setState(() {
      if (index >= 0) {
        _messages[index] = message;
      } else {
        _messages.add(message);
        _messages.sort((a, b) => a.id.compareTo(b.id));
      }
      if (message.id > _lastMessageId) _lastMessageId = message.id;
      _error = null;
    });
  }

  Future<File> _attachmentFile(ProjectMessage message) async {
    final cached = _downloadedAttachments[message.id];
    if (cached != null && await cached.exists()) return cached;
    final token = await _requireToken();
    final file = await AuthApiService.instance.downloadProjectGroupVoice(
      token: token,
      projectId: widget.project.id,
      messageId: message.id,
    );
    _downloadedAttachments[message.id] = file;
    return file;
  }

  Future<void> _togglePlayback(ProjectMessage message) async {
    if (_playingMessageId == message.id) {
      await _audioPlayer.pause();
      if (mounted) setState(() => _playingMessageId = null);
      return;
    }
    try {
      final file = await _attachmentFile(message);
      await _audioPlayer.play(DeviceFileSource(file.path));
      if (mounted) setState(() => _playingMessageId = message.id);
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not play this voice message.');
    }
  }

  Future<void> _showMessageActions(ProjectMessage message) async {
    if (message.isDeleted) return;
    final isMine = message.senderUserId == _currentUserId;
    final canEdit = isMine && message.messageType == 'text';
    final canDelete = isMine || widget.project.isOwner;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('Forward'),
              onTap: () => Navigator.pop(context, 'forward'),
            ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit message'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete message'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'reply') {
      _replyTo(message);
    } else if (action == 'forward') {
      await _forwardMessage(message);
    } else if (action == 'edit') {
      setState(() {
        _replyToMessageId = null;
        _editingMessageId = message.id;
        _messageController.text = message.body ?? '';
      });
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete message?'),
          content: const Text('The message will be removed for everyone.'),
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
        final token = await _requireToken();
        final deleted = await AuthApiService.instance.deleteProjectGroupMessage(
          token: token,
          projectId: widget.project.id,
          messageId: message.id,
        );
        _upsertMessage(deleted);
      } on AuthApiException catch (error) {
        if (mounted) _showMessage(error.message);
      } catch (_) {
        if (mounted) _showMessage('Could not delete this message.');
      }
    }
  }

  void _replyTo(ProjectMessage message) {
    HapticFeedback.selectionClick();
    setState(() {
      _editingMessageId = null;
      _replyToMessageId = message.id;
    });
  }

  Future<void> _forwardMessage(ProjectMessage message) async {
    try {
      final token = await _requireToken();
      final currentConversationId = 'group:${widget.project.id}:group';
      final conversations = (await AuthApiService.instance.getChats(
        token: token,
      ))
          .where(
            (chat) =>
                chat.projectId == widget.project.id &&
                chat.id != currentConversationId,
          )
          .toList(growable: false);
      if (!mounted) return;
      if (conversations.isEmpty) {
        _showMessage('There are no other project chats to forward to.');
        return;
      }

      final targets = await showProjectChatForwardDialog(
        context: context,
        conversations: conversations,
      );
      if (targets == null || targets.isEmpty || !mounted) return;

      var forwardedCount = 0;
      String? failure;
      for (final target in targets) {
        try {
          await AuthApiService.instance.forwardChatMessage(
            token: token,
            projectId: widget.project.id,
            sourceType: 'group',
            sourceMessageId: message.id,
            targetType: target.type,
            targetMemberUserId: target.conversationMemberUserId,
          );
          forwardedCount++;
        } on AuthApiException catch (error) {
          failure ??= error.message;
        }
      }

      if (!mounted) return;
      if (failure != null) {
        _showMessage(forwardedCount == 0
            ? failure
            : 'Forwarded to $forwardedCount chats. $failure');
      } else {
        _showMessage(
          'Forwarded to $forwardedCount '
          '${forwardedCount == 1 ? 'chat' : 'chats'}.',
        );
      }
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not forward this message.');
    }
  }

  Future<void> _shareLocationMessage(ProjectMessage message) async {
    final latitude = message.locationLatitude;
    final longitude = message.locationLongitude;
    if (latitude == null || longitude == null) {
      _showMessage('This location is unavailable.');
      return;
    }
    final mapUrl = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$latitude,$longitude',
    });
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: '${message.locationAddress ?? 'Shared location'}\n$mapUrl',
        ),
      );
    } on PlatformException {
      if (mounted) _showMessage('Could not share this location.');
    }
  }

  Future<void> _shareAttachment(ProjectMessage message) async {
    try {
      final file = await _attachmentFile(message);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(file.path, name: message.attachmentName ?? 'attachment'),
          ],
        ),
      );
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not download this attachment.');
    }
  }

  Future<void> _openImage(ProjectMessage message) async {
    try {
      final file = await _attachmentFile(message);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: InteractiveViewer(
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
      );
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not open this image.');
    }
  }

  String _timeLabel(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
  }

  String get _recordingLabel {
    final minutes = (_recordingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordingSeconds % 60).toString().padLeft(2, '0');
    return 'Recording $minutes:$seconds / 05:00';
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
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${_members.length} members',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh chat',
            onPressed: () => _loadMessages(syncRecent: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _messageList()),
          if (_connectionStatus != null)
            Container(
              width: double.infinity,
              color: AppColors.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Text(
                _connectionStatus!,
                style: AppTextStyles.labelTechnical.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          _composer(),
        ],
      ),
    );
  }

  Widget _messageList() {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _loadMessages(syncRecent: true),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.forum_outlined,
                size: 48,
                color: AppColors.copper,
              ),
              const SizedBox(height: 12),
              Text(
                'No messages yet',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMd.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadMessages(syncRecent: true),
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        itemCount: _messages.length + (_hasMoreMessages ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _messages.length) {
            return Center(
              child: TextButton(
                onPressed: _loadingOlder ? null : _loadOlderMessages,
                child: _loadingOlder
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Load older messages'),
              ),
            );
          }
          return _messageBubble(_messages[_messages.length - 1 - index]);
        },
      ),
    );
  }

  Widget _messageBubble(ProjectMessage message) {
    final isMine = message.senderUserId == _currentUserId;
    final bubbleColor =
        isMine ? AppColors.primaryContainer : AppColors.surfaceContainerLow;
    final foreground = isMine ? Colors.white : AppColors.textPrimary;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageActions(message),
        onHorizontalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 350) _replyTo(message);
        },
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 11, 12, 8),
          decoration: BoxDecoration(
            color: isMine ? bubbleColor : AppColors.surfaceContainerLowest,
            border: isMine ? null : Border.all(color: AppColors.border),
            boxShadow: isMine
                ? null
                : [
                    BoxShadow(
                      color: AppColors.deepBrown.withAlpha(12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMine ? 18 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.forwardedFromName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Forwarded from ${message.forwardedFromName}',
                    style: AppTextStyles.labelTechnical.copyWith(
                      color: foreground.withValues(alpha: 0.75),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (message.replyTo != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${message.replyTo!.senderName}: '
                    '${message.replyTo!.deletedAt != null ? 'This message was deleted' : message.replyTo!.body ?? message.replyTo!.attachmentName ?? 'Message'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelTechnical.copyWith(
                      color: foreground.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              if (!isMine) ...[
                Text(
                  message.senderName,
                  style: AppTextStyles.labelTechnical.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              _messageContent(message, foreground),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${message.editedAt == null ? '' : 'Edited · '}${_timeLabel(message.createdAt)}',
                    style: AppTextStyles.labelTechnical.copyWith(
                      color: isMine ? Colors.white70 : AppColors.outline,
                    ),
                  ),
                  if (isMine && message.readByUserIds.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      'Read by ${message.readByUserIds.length}',
                      style: AppTextStyles.labelTechnical.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageContent(ProjectMessage message, Color foreground) {
    if (message.isDeleted) {
      return Text(
        'This message was deleted',
        style: AppTextStyles.bodyMd.copyWith(
          color: foreground.withValues(alpha: 0.72),
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (message.messageType == 'text') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Text(
          message.body ?? '',
          style: AppTextStyles.bodyMd.copyWith(color: foreground),
        ),
      );
    }
    if (message.messageType == 'image') {
      return InkWell(
        onTap: () => _openImage(message),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 220,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: foreground.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined, color: foreground),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  message.attachmentName ?? 'Photo',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMd.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (message.messageType == 'file') {
      return TextButton.icon(
        onPressed: () => _shareAttachment(message),
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: Text(message.attachmentName ?? 'Document'),
        style: TextButton.styleFrom(foregroundColor: foreground),
      );
    }
    if (message.messageType == 'location') {
      return TextButton.icon(
        onPressed: () => _shareLocationMessage(message),
        icon: const Icon(Icons.location_on_outlined),
        label: Flexible(
          child: Text(
            message.locationAddress ?? 'Shared location',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        style: TextButton.styleFrom(foregroundColor: foreground),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: _playingMessageId == message.id
              ? 'Pause voice message'
              : 'Play voice message',
          onPressed: () => _togglePlayback(message),
          icon: Icon(
            _playingMessageId == message.id
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_fill_rounded,
            size: 38,
            color: foreground,
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.graphic_eq_rounded, color: foreground),
        const SizedBox(width: 8),
        Text(
          'Voice note',
          style: AppTextStyles.bodyMd.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyToMessageId != null || _editingMessageId != null)
              _composerContext(),
            if (_recording) ...[
              Row(
                children: [
                  const Icon(Icons.fiber_manual_record,
                      color: Colors.red, size: 14),
                  const SizedBox(width: 8),
                  Text(_recordingLabel, style: AppTextStyles.bodySm),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _stopRecording(send: false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Take a photo or choose an image',
                  onPressed: _sending || _recording ? null : _pickImage,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    backgroundColor: AppColors.surfaceContainerLow,
                    fixedSize: const Size(44, 44),
                  ),
                ),
                IconButton(
                  tooltip: 'Attach a PDF',
                  onPressed: _sending || _recording ? null : _pickPdf,
                  icon: const Icon(Icons.attach_file),
                ),
                IconButton(
                  tooltip: 'Share current location',
                  onPressed:
                      _sending || _recording ? null : _shareCurrentLocation,
                  icon: const Icon(Icons.location_on_outlined),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 4000,
                    textCapitalization: TextCapitalization.sentences,
                    enabled: !_sending && !_recording,
                    onSubmitted: (_) => _sendText(),
                    decoration: InputDecoration(
                      hintText: 'Message',
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.surfaceContainerLowest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(
                          color: AppColors.secondary,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: _recording
                      ? 'Stop and send voice note'
                      : 'Record voice note',
                  onPressed: _sending ? null : _toggleRecording,
                  icon: Icon(
                    _recording
                        ? Icons.stop_circle_outlined
                        : Icons.mic_none_rounded,
                    size: 24,
                    color: _recording ? AppColors.error : AppColors.secondary,
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Send message',
                  onPressed: _sending || _recording ? null : _sendText,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: Colors.white,
                    fixedSize: const Size(48, 48),
                  ),
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _composerContext() {
    final reply = _messages
        .where((message) => message.id == _replyToMessageId)
        .firstOrNull;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            _editingMessageId == null ? Icons.reply : Icons.edit_outlined,
            size: 18,
            color: AppColors.secondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _editingMessageId != null
                  ? 'Editing message'
                  : 'Replying to ${reply?.senderName ?? 'message'}: '
                      '${reply?.body ?? reply?.attachmentName ?? 'Message'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySm,
            ),
          ),
          IconButton(
            tooltip: 'Cancel',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _replyToMessageId = null;
                _editingMessageId = null;
                _messageController.clear();
              });
            },
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
