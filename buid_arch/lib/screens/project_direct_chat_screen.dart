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

//neethu soman

class ProjectDirectChatScreen extends StatefulWidget {
  const ProjectDirectChatScreen({
    super.key,
    required this.project,
    required this.member,
    required this.conversationMemberUserId,
  });

  final Project project;
  final ProjectMember member;
  final int conversationMemberUserId;

  @override
  State<ProjectDirectChatScreen> createState() =>
      _ProjectDirectChatScreenState();
}

class _ProjectDirectChatScreenState extends State<ProjectDirectChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  final List<ProjectMessage> _messages = [];
  final Map<int, File> _downloadedAttachments = {};
  Timer? _refreshTimer;
  Timer? _recordingTimer;
  ProjectChatRealtimeService? _realtime;
  StreamSubscription<void>? _audioCompleteSubscription;
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
  bool _sending = false;
  bool _recording = false;
  String? _error;
  String? _connectionStatus;

  @override
  void initState() {
    super.initState();
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
    _scrollController.dispose();
    super.dispose();
  }

  Future<String> _requireToken() async {
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthApiException(
          'Your session expired. Please sign in again.');
    }
    return token;
  }

  Future<int> _requireCurrentUserId() async {
    if (_currentUserId case final userId?) return userId;
    final user = await AuthSessionService.instance.readUser();
    final id = user?['id'];
    final userId = id is num ? id.toInt() : int.tryParse(id?.toString() ?? '');
    if (userId == null) {
      throw const AuthApiException(
        'Could not identify your signed-in account. Please sign in again.',
      );
    }
    _currentUserId = userId;
    return userId;
  }

  Future<void> _startRealtime() async {
    try {
      final token = await _requireToken();
      if (!mounted) return;
      final realtime = ProjectChatRealtimeService(
        token: token,
        channelName: 'private-project-chat.direct.'
            '${widget.project.id}.${widget.conversationMemberUserId}',
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
      _upsertMessage(message);
      unawaited(_markRead());
    } on FormatException catch (error) {
      if (mounted) setState(() => _connectionStatus = error.message);
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

  Future<void> _loadMessages({
    bool showErrors = true,
    bool syncRecent = false,
  }) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final token = await _requireToken();
      await _requireCurrentUserId();
      final isInitialLoad = _messages.isEmpty && _lastMessageId == 0;
      var firstPageCount = 0;
      var cursor = _lastMessageId;
      final incoming = <ProjectMessage>[];
      while (true) {
        final page = await AuthApiService.instance.getDirectMessages(
          token: token,
          projectId: widget.project.id,
          memberUserId: widget.conversationMemberUserId,
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
          await AuthApiService.instance.getDirectMessages(
            token: token,
            projectId: widget.project.id,
            memberUserId: widget.conversationMemberUserId,
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
      if (showErrors) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (!mounted) return;
      if (showErrors) {
        setState(() => _error = 'Could not load this conversation.');
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
      final messages = await AuthApiService.instance.getDirectMessages(
        token: token,
        projectId: widget.project.id,
        memberUserId: widget.conversationMemberUserId,
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
      await AuthApiService.instance.markDirectChatRead(
        token: accessToken,
        projectId: widget.project.id,
        memberUserId: widget.conversationMemberUserId,
      );
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _connectionStatus = error.message);
    }
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    if (body.isEmpty || _sending) return;
    if (body.length > 4000) {
      _showMessage('Messages can be up to 4,000 characters.');
      return;
    }
    setState(() => _sending = true);
    try {
      final token = await _requireToken();
      await _requireCurrentUserId();
      final editingId = _editingMessageId;
      final message = editingId == null
          ? await AuthApiService.instance.sendDirectMessage(
              token: token,
              projectId: widget.project.id,
              memberUserId: widget.conversationMemberUserId,
              body: body,
              replyToMessageId: _replyToMessageId,
            )
          : await AuthApiService.instance.updateDirectMessage(
              token: token,
              projectId: widget.project.id,
              memberUserId: widget.conversationMemberUserId,
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
    } on PlatformException {
      if (mounted) _showMessage('Could not send this message.');
    } catch (_) {
      if (mounted) _showMessage('Could not send this message.');
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
              'with this private conversation.'),
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
      final message = await AuthApiService.instance.sendDirectLocation(
        token: token,
        projectId: widget.project.id,
        memberUserId: widget.conversationMemberUserId,
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

  Future<void> _showMessageActions(ProjectMessage message) async {
    if (message.isDeleted) return;
    final isMine = message.senderUserId == _currentUserId;
    final canEdit = isMine && message.messageType == 'text';
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
            if (isMine)
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
          content: const Text('The message will be removed for both people.'),
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
        final deleted = await AuthApiService.instance.deleteDirectMessage(
          token: token,
          projectId: widget.project.id,
          memberUserId: widget.conversationMemberUserId,
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
      final currentConversationId =
          'direct:${widget.project.id}:${widget.conversationMemberUserId}';
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
            sourceType: 'direct',
            sourceMessageId: message.id,
            sourceMemberUserId: widget.conversationMemberUserId,
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

  Future<void> _chooseAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose image'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Choose PDF'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    try {
      if (choice == 'pdf') {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
        );
        if (file == null) return;
        final size = await file.length();
        if (size == null) {
          _showMessage('Could not read the selected PDF.');
          return;
        }
        await _uploadFile(
          fileName: file.name,
          fileSize: size,
          fileBytes: file.readAsByteStream(),
          messageType: 'file',
        );
      } else {
        final image = await ImagePicker().pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        );
        if (image == null) return;
        final size = await image.length();
        await _uploadFile(
          fileName: image.name,
          fileSize: size,
          fileBytes: image.openRead(),
          messageType: 'image',
        );
      }
    } on PlatformException {
      if (mounted) _showMessage('Could not access the selected media.');
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not attach this file.');
    }
  }

  Future<void> _uploadFile({
    required String fileName,
    required int fileSize,
    required Stream<List<int>> fileBytes,
    required String messageType,
  }) async {
    if (fileSize > 25 * 1024 * 1024) {
      _showMessage('Files must be 25 MB or smaller.');
      return;
    }
    setState(() => _sending = true);
    try {
      final token = await _requireToken();
      await _requireCurrentUserId();
      final message = await AuthApiService.instance.sendDirectAttachment(
        token: token,
        projectId: widget.project.id,
        memberUserId: widget.conversationMemberUserId,
        messageType: messageType,
        fileName: fileName,
        fileSize: fileSize,
        fileBytes: fileBytes,
        replyToMessageId: _replyToMessageId,
      );
      if (!mounted) return;
      _upsertMessage(message);
      setState(() => _replyToMessageId = null);
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not upload this attachment.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_sending) return;
    if (_recording) {
      await _stopVoiceRecording(send: true);
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        _showMessage('Microphone permission is needed to record a voice note.');
        return;
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}${Platform.pathSeparator}'
          'voice-note-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordingSeconds = 0;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() => _recordingSeconds++);
        if (_recordingSeconds >= 300) {
          unawaited(_stopVoiceRecording(send: true));
        }
      });
    } on PlatformException {
      if (mounted) _showMessage('Could not start voice recording.');
    } catch (_) {
      if (mounted) _showMessage('Could not start voice recording.');
    }
  }

  Future<void> _stopVoiceRecording({required bool send}) async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      final path = await _recorder.stop();
      if (mounted) setState(() => _recording = false);
      if (!send || path == null) return;
      final file = File(path);
      final size = await file.length();
      await _uploadFile(
        fileName: 'voice-note.m4a',
        fileSize: size,
        fileBytes: file.openRead(),
        messageType: 'voice',
      );
    } on PlatformException {
      if (mounted) {
        setState(() => _recording = false);
        _showMessage('Could not finish the voice recording.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _recording = false);
        _showMessage('Could not send this voice note.');
      }
    }
  }

  Future<File> _getAttachmentFile(ProjectMessage message) async {
    final cached = _downloadedAttachments[message.id];
    if (cached != null && await cached.exists()) return cached;
    final token = await _requireToken();
    final file = await AuthApiService.instance.downloadDirectAttachment(
      token: token,
      projectId: widget.project.id,
      memberUserId: widget.conversationMemberUserId,
      messageId: message.id,
    );
    _downloadedAttachments[message.id] = file;
    return file;
  }

  Future<void> _openImage(ProjectMessage message) async {
    try {
      final file = await _getAttachmentFile(message);
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

  Future<void> _toggleVoicePlayback(ProjectMessage message) async {
    if (_playingMessageId == message.id) {
      await _audioPlayer.pause();
      if (mounted) setState(() => _playingMessageId = null);
      return;
    }
    try {
      final file = await _getAttachmentFile(message);
      await _audioPlayer.play(DeviceFileSource(file.path));
      if (mounted) setState(() => _playingMessageId = message.id);
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not play this voice note.');
    }
  }

  Future<void> _shareAttachment(ProjectMessage message) async {
    try {
      final file = await _getAttachmentFile(message);
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

  String _timeLabel(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.member.name.trim().isEmpty
        ? 'Project member'
        : widget.member.name.trim();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.project.name,
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
            tooltip: 'Refresh conversation',
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
                onPressed: () => _loadMessages(),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) return _emptyState();

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
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
        final message = _messages[_messages.length - 1 - index];
        return _messageBubble(message);
      },
    );
  }

  Widget _emptyState() {
    return Center(
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
            const SizedBox(height: 14),
            Text(
              'Start a conversation',
              style: AppTextStyles.titleMd.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Messages here are private between you and '
              '${widget.member.name}.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBubble(ProjectMessage message) {
    final isMine = message.senderUserId == _currentUserId;
    final color =
        isMine ? AppColors.primaryContainer : AppColors.surfaceContainerLow;
    final textColor = isMine ? Colors.white : AppColors.textPrimary;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: GestureDetector(
          onLongPress: () => _showMessageActions(message),
          onHorizontalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 350) _replyTo(message);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMine ? 18 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (message.forwardedFromName != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Forwarded from ${message.forwardedFromName}',
                        style: AppTextStyles.labelTechnical.copyWith(
                          color: textColor.withValues(alpha: 0.75),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                if (message.replyTo != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 7),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${message.replyTo!.senderName}: '
                        '${message.replyTo!.deletedAt != null ? 'This message was deleted' : message.replyTo!.body ?? message.replyTo!.attachmentName ?? 'Message'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelTechnical.copyWith(
                          color: textColor.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                if (!isMine)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        message.senderName,
                        style: AppTextStyles.labelTechnical.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _messageContent(message, textColor),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${message.editedAt == null ? '' : 'Edited · '}${_timeLabel(message.createdAt)}',
                      style: AppTextStyles.labelTechnical.copyWith(
                        color: isMine ? Colors.white70 : AppColors.outline,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.readByUserIds.isEmpty
                            ? Icons.done_rounded
                            : Icons.done_all_rounded,
                        size: 15,
                        color: message.readByUserIds.isEmpty
                            ? Colors.white70
                            : AppColors.creamSand,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _messageContent(ProjectMessage message, Color textColor) {
    final body = message.body;
    if (message.isDeleted) {
      return Text(
        'This message was deleted',
        style: AppTextStyles.bodyMd.copyWith(
          color: textColor.withValues(alpha: 0.72),
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (message.messageType == 'image') {
      return TextButton.icon(
        onPressed: () => _openImage(message),
        icon: const Icon(Icons.image_outlined),
        label: Text(message.attachmentName ?? 'Photo'),
        style: TextButton.styleFrom(foregroundColor: textColor),
      );
    }
    if (message.messageType == 'file') {
      return TextButton.icon(
        onPressed: () => _shareAttachment(message),
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: Text(message.attachmentName ?? 'PDF'),
        style: TextButton.styleFrom(foregroundColor: textColor),
      );
    }
    if (message.messageType == 'voice') {
      return TextButton.icon(
        onPressed: () => _toggleVoicePlayback(message),
        icon: Icon(
          _playingMessageId == message.id ? Icons.pause : Icons.play_arrow,
        ),
        label: const Text('Voice note'),
        style: TextButton.styleFrom(foregroundColor: textColor),
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
        style: TextButton.styleFrom(foregroundColor: textColor),
      );
    }
    return Text(
      body ?? '',
      style: AppTextStyles.bodyMd.copyWith(color: textColor),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyToMessageId != null || _editingMessageId != null)
              _composerContext(),
            if (_recording)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record,
                        color: Colors.red, size: 14),
                    const SizedBox(width: 8),
                    Text(_recordingLabel),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _stopVoiceRecording(send: false),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Attach photo or PDF',
                  onPressed: _sending || _recording ? null : _chooseAttachment,
                  icon: const Icon(Icons.attach_file),
                ),
                IconButton(
                  tooltip: 'Share current location',
                  onPressed:
                      _sending || _recording ? null : _shareCurrentLocation,
                  icon: const Icon(Icons.location_on_outlined),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4000,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _recording
                      ? 'Stop and send voice note'
                      : 'Record voice note',
                  onPressed: _toggleVoiceRecording,
                  icon: Icon(
                    _recording ? Icons.stop_circle_outlined : Icons.mic_none,
                    color: _recording ? Colors.red : AppColors.secondary,
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Send message',
                  onPressed: _sending || _recording ? null : _sendMessage,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: Colors.white,
                  ),
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 20,
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
    ProjectMessage? reply;
    for (final message in _messages) {
      if (message.id == _replyToMessageId) {
        reply = message;
        break;
      }
    }
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
