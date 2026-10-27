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
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

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
  StreamSubscription<void>? _audioCompleteSubscription;
  int? _currentUserId;
  int _lastMessageId = 0;
  int _recordingSeconds = 0;
  int? _playingMessageId;
  bool _loading = true;
  bool _refreshing = false;
  bool _sending = false;
  bool _recording = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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

  Future<void> _loadMessages({bool showErrors = true}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final token = await _requireToken();
      await _requireCurrentUserId();
      final messages = await AuthApiService.instance.getDirectMessages(
        token: token,
        projectId: widget.project.id,
        memberUserId: widget.conversationMemberUserId,
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
      final message = await AuthApiService.instance.sendDirectMessage(
        token: token,
        projectId: widget.project.id,
        memberUserId: widget.conversationMemberUserId,
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
    } on PlatformException {
      if (mounted) _showMessage('Could not send this message.');
    } catch (_) {
      if (mounted) _showMessage('Could not send this message.');
    } finally {
      if (mounted) setState(() => _sending = false);
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
      );
      if (!mounted) return;
      setState(() {
        _messages.add(message);
        _lastMessageId = message.id;
        _error = null;
      });
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
      ),
      body: Column(
        children: [
          Expanded(child: _messageList()),
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
      itemCount: _messages.length,
      itemBuilder: (context, index) {
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
              Text(
                _timeLabel(message.createdAt),
                style: AppTextStyles.labelTechnical.copyWith(
                  color: isMine ? Colors.white70 : AppColors.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageContent(ProjectMessage message, Color textColor) {
    final body = message.body;
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
}
