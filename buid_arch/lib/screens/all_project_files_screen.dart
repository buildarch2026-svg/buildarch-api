import 'package:flutter/material.dart';

import '../models/project.dart';
import '../models/project_document.dart';
import '../models/project_message.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_bottom_nav.dart';
import 'project_documents_screen.dart';
import 'project_group_voice_chat_screen.dart';

class AllProjectFilesScreen extends StatefulWidget {
  const AllProjectFilesScreen({super.key, required this.returnProject});

  final Project returnProject;

  @override
  State<AllProjectFilesScreen> createState() => _AllProjectFilesScreenState();
}

class _AllProjectFilesScreenState extends State<AllProjectFilesScreen> {
  final _searchController = TextEditingController();
  List<_ProjectFile> _files = [];
  String _query = '';
  String? _error;
  int _projectCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadFiles();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _query = _searchController.text.trim().toLowerCase());
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await AuthSessionService.instance.readToken();
      if (token == null || token.isEmpty) {
        throw const AuthApiException(
          'Your session expired. Please sign in again.',
        );
      }
      final projects = await AuthApiService.instance.getProjects(token: token);
      final filesByProject = await Future.wait(
        projects.map((project) async {
          final results = await Future.wait<Object>([
            AuthApiService.instance.getProjectDocuments(
              token: token,
              projectId: project.id,
            ),
            AuthApiService.instance.getProjectGroupFiles(
              token: token,
              projectId: project.id,
            ),
          ]);
          return (
            documents: results[0] as List<ProjectDocument>,
            messages: results[1] as List<ProjectMessage>,
          );
        }),
      );
      if (!mounted) return;
      final files = <_ProjectFile>[];
      for (var index = 0; index < projects.length; index++) {
        files.addAll(
          filesByProject[index].documents.map(
                (document) => _ProjectFile.fromDocument(
                  project: projects[index],
                  document: document,
                ),
              ),
        );
        files.addAll(
          filesByProject[index].messages.map(
                (message) => _ProjectFile.fromGroupMessage(
                  project: projects[index],
                  message: message,
                ),
              ),
        );
      }
      files.sort((a, b) {
        final aDate = a.createdAt;
        final bDate = b.createdAt;
        if (aDate == null) return bDate == null ? 0 : 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
      setState(() {
        _files = files;
        _projectCount = projects.length;
      });
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load your project files.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_ProjectFile> get _visibleFiles {
    if (_query.isEmpty) return _files;
    return _files.where((file) {
      return file.name.toLowerCase().contains(_query) ||
          file.project.name.toLowerCase().contains(_query) ||
          file.uploadedBy.toLowerCase().contains(_query);
    }).toList();
  }

  void _openProjectFiles(Project project) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectDocumentsScreen(project: project),
      ),
    );
  }

  void _openProjectChat(Project project) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectGroupVoiceChatScreen(project: project),
      ),
    );
  }

  void _onTabSelected(AppTab tab) {
    if (tab == AppTab.files) return;
    if (tab == AppTab.chat) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              ProjectGroupVoiceChatScreen(project: widget.returnProject),
        ),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final visibleFiles = _visibleFiles;
    final pdfCount = _files.where((file) => file.isPdf).length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        title: Text(
          'Project files',
          style: AppTextStyles.cardTitle.copyWith(
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh files',
            onPressed: _loading ? null : _loadFiles,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: _loadFiles,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    children: [
                      _summaryCard(pdfCount),
                      const SizedBox(height: 16),
                      _searchField(),
                      const SizedBox(height: 18),
                      if (visibleFiles.isEmpty)
                        _emptyState()
                      else ...[
                        Text(
                          'ALL PROJECTS · ${visibleFiles.length} FILES',
                          style: AppTextStyles.labelTechnical.copyWith(
                            color: AppColors.outline,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final file in visibleFiles) ...[
                          _fileCard(file),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ],
                  ),
                ),
      bottomNavigationBar: AppBottomNav(
        current: AppTab.files,
        onTap: _onTabSelected,
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadFiles,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(int pdfCount) {
    final voiceCount =
        _files.where((file) => file.messageType == 'voice').length;
    final imageCount = _files.length - pdfCount - voiceCount;
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
              const Icon(
                Icons.folder_copy_outlined,
                color: AppColors.secondaryContainer,
                size: 28,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Your shared project library',
                  style: AppTextStyles.titleMd.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Files uploaded to all your projects, together in one place.',
            style: AppTextStyles.bodySm.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summaryChip('${_files.length} files'),
              _summaryChip('$_projectCount projects'),
              _summaryChip('$pdfCount PDFs'),
              _summaryChip('$imageCount images'),
              _summaryChip('$voiceCount voice notes'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySm.copyWith(color: Colors.white),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search files or projects',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: _searchController.clear,
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  Widget _emptyState() {
    final searching = _query.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 36),
      child: Column(
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.folder_open_rounded,
            size: 52,
            color: AppColors.copper,
          ),
          const SizedBox(height: 14),
          Text(
            searching ? 'No matching files' : 'No files uploaded yet',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMd.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 7),
          Text(
            searching
                ? 'Try another file or project name.'
                : 'Files shared through your project file pages will appear here.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileCard(_ProjectFile file) {
    final isPdf = file.isPdf;
    final color = isPdf ? AppColors.tertiary : AppColors.secondary;
    final icon = isPdf
        ? Icons.picture_as_pdf_rounded
        : file.messageType == 'voice'
            ? Icons.graphic_eq_rounded
            : Icons.image_rounded;
    final typeLabel = isPdf
        ? 'PDF'
        : file.messageType == 'voice'
            ? 'VOICE'
            : 'IMAGE';
    final uploadedBy = file.uploadedBy;
    final size = _fileSize(file.size);
    final date = file.createdAt;
    final dateLabel = date == null
        ? ''
        : ' · ${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}/${date.year}';

    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => file.document != null
            ? _openProjectFiles(file.project)
            : _openProjectChat(file.project),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
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
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 25),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMd.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      file.project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$uploadedBy · $size$dateLabel',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelTechnical.copyWith(
                        color: AppColors.outline,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      typeLabel,
                      style: AppTextStyles.labelTechnical.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.outline),
            ],
          ),
        ),
      ),
    );
  }

  String _fileSize(int size) {
    if (size < 1024 * 1024) return '${(size / 1024).ceil()} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ProjectFile {
  _ProjectFile.fromDocument({
    required this.project,
    required ProjectDocument document,
  })  : document = document,
        messageId = null,
        name = document.name,
        size = document.size,
        uploadedBy = document.uploadedBy ?? 'Project team',
        createdAt = document.createdAt,
        messageType = 'document',
        isPdf = document.mimeType == 'application/pdf' ||
            document.name.toLowerCase().endsWith('.pdf');

  _ProjectFile.fromGroupMessage({
    required this.project,
    required ProjectMessage message,
  })  : document = null,
        messageId = message.id,
        name = message.attachmentName ?? 'Attachment',
        size = message.attachmentSize ?? 0,
        uploadedBy = message.senderName,
        createdAt = message.createdAt,
        messageType = message.messageType,
        isPdf = message.attachmentMimeType == 'application/pdf';

  final Project project;
  final ProjectDocument? document;
  final int? messageId;
  final String name;
  final int size;
  final String uploadedBy;
  final DateTime? createdAt;
  final String messageType;
  final bool isPdf;
}
