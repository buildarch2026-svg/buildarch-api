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
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadDocuments();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
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

  List<ProjectDocument> get _visibleDocuments {
    final categoryDocuments = widget.category == null
        ? _documents
        : _documents
            .where((document) => document.category == widget.category)
            .toList();
    if (_searchQuery.isEmpty) return categoryDocuments;
    return categoryDocuments
        .where((document) =>
            document.name.toLowerCase().contains(_searchQuery) ||
            (document.uploadedBy?.toLowerCase().contains(_searchQuery) ??
                false))
        .toList();
  }

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
                  ? _fileList()
                  : RefreshIndicator(
                      onRefresh: _loadDocuments,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                        itemCount: _visibleDocuments.length + 2,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == 0) return _libraryHeader();
                          if (index == 1) return _searchField();
                          return _documentTile(_visibleDocuments[index - 2]);
                        },
                      ),
                    ),
    );
  }

  Widget _fileList() {
    final noSearchResults = _documents.isNotEmpty && _searchQuery.isNotEmpty;
    return RefreshIndicator(
      onRefresh: _loadDocuments,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          _libraryHeader(),
          const SizedBox(height: 12),
          _searchField(),
          const SizedBox(height: 28),
          Icon(
            noSearchResults
                ? Icons.search_off_rounded
                : Icons.folder_open_rounded,
            size: 52,
            color: AppColors.copper,
          ),
          const SizedBox(height: 14),
          Text(
            noSearchResults
                ? 'No matching files'
                : widget.category == 'drawings'
                    ? 'No drawings yet'
                    : 'Your project library is empty',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMd.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            noSearchResults
                ? 'Try another file name or uploader.'
                : widget.category == 'drawings'
                    ? 'Drawings uploaded by your project team will show up here.'
                    : 'Upload a photo or PDF to keep important project files '
                        'in one place.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          if (noSearchResults)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(
                child: TextButton(
                  onPressed: _searchController.clear,
                  child: const Text('Clear search'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _libraryHeader() {
    final pdfCount = _documents.where(_isPdf).length;
    final photoCount = _documents.length - pdfCount;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.darkBrown, AppColors.deepBrown, AppColors.primary],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.folder_copy_outlined,
                  color: AppColors.secondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PROJECT LIBRARY',
                      style: AppTextStyles.labelTechnical.copyWith(
                        color: AppColors.secondaryContainer,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_documents.length} '
                      '${_documents.length == 1 ? 'file' : 'files'} shared',
                      style: AppTextStyles.titleMd.copyWith(
                        color: Colors.white,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Keep drawings, photos, and project documents together.',
            style: AppTextStyles.bodySm.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summaryChip(Icons.picture_as_pdf_outlined, 'PDFs', pdfCount),
              _summaryChip(Icons.image_outlined, 'Photos', photoCount),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.secondaryContainer),
          const SizedBox(width: 6),
          Text(
            '$count $label',
            style: AppTextStyles.bodySm.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search files or people',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: _searchController.clear,
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.secondary, width: 1.5),
        ),
      ),
    );
  }

  Widget _documentTile(ProjectDocument document) {
    final isPdf = _isPdf(document);
    final iconColor = isPdf ? AppColors.tertiary : AppColors.secondary;
    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _working ? null : () => _download(document),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 52,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                  color: iconColor,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMd.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _uploadedLabel(document),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isPdf ? 'PDF' : 'IMAGE',
                        style: AppTextStyles.labelTechnical.copyWith(
                          color: iconColor,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Download ${document.name}',
                onPressed: _working ? null : () => _download(document),
                icon: const Icon(
                  Icons.download_rounded,
                  color: AppColors.primaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isPdf(ProjectDocument document) =>
      document.mimeType == 'application/pdf' ||
      document.name.toLowerCase().endsWith('.pdf');
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
