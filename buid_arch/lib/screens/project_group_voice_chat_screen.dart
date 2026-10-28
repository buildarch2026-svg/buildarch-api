import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/project.dart';
import '../models/project_member.dart';
import '../models/project_message.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

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
  StreamSubscription<void>? _audioCompleteSubscription;
  List<ProjectMember> _members = [];
  int? _currentUserId;
  int _lastMessageId = 0;
  int _recordingSeconds = 0;
  int? _playingMessageId;
  bool _loading = true;
  bool _refreshing = false;
  bool _recording = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadMessages();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadMessages(showErrors: false),
    );
    _audioCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingMessageId = null);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _recordingTimer?.cancel();
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

  Future<void> _loadMessages({bool showErrors = true}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final token = await _requireToken();
      final messages = await AuthApiService.instance.getProjectGroupMessages(
        token: token,
        projectId: widget.project.id,
        afterId: _lastMessageId,
      );
      if (!mounted) return;
      final newMessages =
          messages.where((message) => message.id > _lastMessageId).toList();
      if (newMessages.isNotEmpty) {
        setState(() {
          _messages.addAll(newMessages);
          _lastMessageId = newMessages.last.id;
          _error = null;
        });
      } else if (_error != null) {
        setState(() => _error = null);
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
      final message = await AuthApiService.instance.sendProjectGroupText(
        token: token,
        projectId: widget.project.id,
        body: body,
      );
      if (!mounted) return;
      _messageController.clear();
      setState(() {
        _messages.add(message);
        _lastMessageId = message.id;
        _error = null;
      });
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
      );
      if (!mounted) return;
      setState(() {
        _messages.add(message);
        _lastMessageId = message.id;
        _error = null;
      });
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
      );
      if (!mounted) return;
      setState(() {
        _messages.add(message);
        _lastMessageId = message.id;
        _error = null;
      });
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
            const Text('Project group chat'),
            Text(
              '${_members.length} members · ${widget.project.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _groupChatNotice(),
          Expanded(child: _messageList()),
          _composer(),
        ],
      ),
    );
  }

  Widget _groupChatNotice() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_2_outlined, color: AppColors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _members.isEmpty
                  ? 'Share messages with everyone in this project.'
                  : 'Shared with ${_members.length} project members.',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          const Icon(Icons.forum_outlined,
              size: 18, color: AppColors.secondary),
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
                onPressed: _loadMessages,
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
                Icons.graphic_eq_rounded,
                size: 52,
                color: AppColors.copper,
              ),
              const SizedBox(height: 14),
              Text(
                'Start the group conversation',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMd.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Send a message, share a photo, or record a voice note for the team.',
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

    return RefreshIndicator(
      onRefresh: _loadMessages,
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        itemCount: _messages.length,
        itemBuilder: (context, index) =>
            _messageBubble(_messages[_messages.length - 1 - index]),
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
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(13, 10, 10, 8),
        decoration: BoxDecoration(
          color: bubbleColor,
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
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _timeLabel(message.createdAt),
                style: AppTextStyles.labelTechnical.copyWith(
                  color: isMine ? Colors.white70 : AppColors.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageContent(ProjectMessage message, Color foreground) {
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                IconButton(
                  tooltip: 'Take a photo or choose an image',
                  onPressed: _sending || _recording ? null : _pickImage,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  color: AppColors.secondary,
                ),
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
                      hintText: 'Message the project team...',
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _recording
                      ? 'Stop and send voice note'
                      : 'Record voice note',
                  onPressed: _sending ? null : _toggleRecording,
                  icon: Icon(
                    _recording
                        ? Icons.stop_circle_outlined
                        : Icons.mic_none_rounded,
                    color: _recording ? AppColors.error : AppColors.secondary,
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Send message',
                  onPressed: _sending || _recording ? null : _sendText,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: Colors.white,
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
            const SizedBox(height: 6),
            Text(
              'Text, images, and voice notes',
              style: AppTextStyles.labelTechnical.copyWith(
                color: AppColors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
