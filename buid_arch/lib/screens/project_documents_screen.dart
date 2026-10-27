import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/project.dart';
import '../models/project_document.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

const _projectFileSaverChannel =
    MethodChannel('com.example.buid_arch/project_file_saver');

class ProjectDocumentsScreen extends StatefulWidget {
  const ProjectDocumentsScreen({
    super.key,
    required this.project,
    this.category,
  });

  final Project project;
  final String? category;

  @override
  State<ProjectDocumentsScreen> createState() => _ProjectDocumentsScreenState();
}

class _ProjectDocumentsScreenState extends State<ProjectDocumentsScreen> {
  static const _maxFileSize = 100 * 1024 * 1024;

  List<ProjectDocument> _documents = [];
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<String> _requireToken() async {
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthApiException(
          'Your session expired. Please sign in again.');
    }
    return token;
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _loading = _documents.isEmpty;
      _error = null;
    });
    try {
      final token = await _requireToken();
      final documents = await AuthApiService.instance.getProjectDocuments(
        token: token,
        projectId: widget.project.id,
      );
      if (mounted) setState(() => _documents = documents);
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load project files.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadFile() async {
    setState(() => _working = true);
    PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      );
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(
          error.message == null
              ? 'Could not open the file picker (${error.code}).'
              : 'Could not open the file picker: ${error.message}',
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (file == null || !mounted) return;

    setState(() => _working = true);
    try {
      final size = await file.length();
      if (size == null) {
        _showMessage('Could not read the selected file.');
        return;
      }
      if (size > _maxFileSize) {
        _showMessage('Choose a file no larger than 100 MB.');
        return;
      }

      final token = await _requireToken();
      await AuthApiService.instance.uploadProjectDocument(
        token: token,
        projectId: widget.project.id,
        file: file,
      );
      await _loadDocuments();
      if (mounted) _showMessage('File uploaded for the project team.');
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(
          error.message == null
              ? 'Could not read or upload the selected file (${error.code}).'
              : 'Could not read or upload the selected file: ${error.message}',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Could not upload the selected file: $error');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _download(ProjectDocument document) async {
    setState(() => _working = true);
    try {
      final fileName = await _requestSaveFileName(document);
      if (fileName == null || !mounted) return;

      final token = await _requireToken();
      final file = await AuthApiService.instance.downloadProjectDocument(
        token: token,
        projectId: widget.project.id,
        documentId: document.id,
      );
      try {
        final saved = await _projectFileSaverChannel.invokeMethod<bool>(
          'saveDownloadedFile',
          {
            'sourcePath': file.path,
            'fileName': fileName,
            'mimeType': document.mimeType,
          },
        );
        if (mounted) {
          _showMessage(saved == true ? 'File saved.' : 'Save cancelled.');
        }
      } finally {
        if (await file.exists()) await file.delete();
      }
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(error.message ?? 'Could not save this file.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String?> _requestSaveFileName(ProjectDocument document) async {
    final suggestedName = document.name.trim().isNotEmpty
        ? document.name.trim()
        : document.mimeType == 'application/pdf'
            ? 'project-file.pdf'
            : 'project-photo.jpg';
    return showDialog<String>(
      context: context,
      builder: (_) => _SaveFileNameDialog(initialName: suggestedName),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _fileSize(int size) {
    if (size < 1024 * 1024) return '${(size / 1024).ceil()} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _uploadedLabel(ProjectDocument document) {
    final date = document.createdAt;
    final dateLabel = date == null
        ? ''
        : ' · ${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}/${date.year}';
    return '${document.uploadedBy ?? 'Project team'} · '
        '${_fileSize(document.size)}$dateLabel';
  }

  List<ProjectDocument> get _visibleDocuments => widget.category == null
      ? _documents
      : _documents
          .where((document) => document.category == widget.category)
          .toList();

  String get _screenTitle =>
      widget.category == 'drawings' ? 'Drawings' : 'Project files';

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
            Text(_screenTitle),
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
            tooltip: 'Refresh files',
            onPressed: _loading || _working ? null : _loadDocuments,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _working ? null : _uploadFile,
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: AppColors.surface,
        icon: _working
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.surface,
                ),
              )
            : const Icon(Icons.cloud_upload_outlined),
        label: Text(_working ? 'Please wait' : 'Upload file'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _loadDocuments,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : _visibleDocuments.isEmpty
                  ? _emptyState()
                  : RefreshIndicator(
                      onRefresh: _loadDocuments,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                        itemCount: _visibleDocuments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _documentTile(_visibleDocuments[index]),
                      ),
                    ),
    );
  }

  Widget _emptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 110),
        Icon(
          Icons.folder_open_outlined,
          size: 56,
          color: AppColors.outline.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 16),
        Text(
          widget.category == 'drawings'
              ? 'No drawings yet'
              : 'No project files yet',
          textAlign: TextAlign.center,
          style: AppTextStyles.titleMd.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          widget.category == 'drawings'
              ? 'Files uploaded by the project designer will appear here.'
              : 'Upload a photo or PDF to share it with your project team.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _documentTile(ProjectDocument document) {
    final isPdf = document.mimeType == 'application/pdf' ||
        document.name.toLowerCase().endsWith('.pdf');
    return Card(
      color: AppColors.surfaceContainerLow,
      child: ListTile(
        leading: Icon(
          isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
          color: AppColors.secondary,
        ),
        title: Text(
          document.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyMd.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(_uploadedLabel(document)),
        trailing: IconButton(
          tooltip: 'Download ${document.name}',
          onPressed: _working ? null : () => _download(document),
          icon: const Icon(Icons.download_outlined),
        ),
        onTap: _working ? null : () => _download(document),
      ),
    );
  }
}

class _SaveFileNameDialog extends StatefulWidget {
  const _SaveFileNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_SaveFileNameDialog> createState() => _SaveFileNameDialogState();
}

class _SaveFileNameDialogState extends State<_SaveFileNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final fileName = _controller.text.trim();
    if (fileName.isNotEmpty) Navigator.of(context).pop(fileName);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save file as'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'File name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, child) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: child,
          ),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
