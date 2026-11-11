import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/job_portal.dart';
import '../navigation/auth_session_navigation.dart';
import '../services/auth_api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'community_profile_screen.dart';

class JobPortalJobDetailScreen extends StatefulWidget {
  const JobPortalJobDetailScreen({
    super.key,
    required this.token,
    required this.initialJob,
  });

  final String token;
  final ConstructionJob initialJob;

  @override
  State<JobPortalJobDetailScreen> createState() =>
      _JobPortalJobDetailScreenState();
}

class _JobPortalJobDetailScreenState extends State<JobPortalJobDetailScreen> {
  late ConstructionJob _job = widget.initialJob;
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final job = await AuthApiService.instance.getConstructionJob(
        token: widget.token,
        jobId: widget.initialJob.id,
      );
      if (!mounted) return;
      setState(() {
        _job = job;
        _loading = false;
      });
    } on AuthApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        await AuthSessionNavigation.handleUnauthorized(context, error);
      }
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _toggleSaved() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (_job.isSaved) {
        await AuthApiService.instance.unsaveConstructionJob(
          token: widget.token,
          jobId: _job.id,
        );
      } else {
        await AuthApiService.instance.saveConstructionJob(
          token: widget.token,
          jobId: _job.id,
        );
      }
      if (!mounted) return;
      setState(() => _job = ConstructionJob(
            id: _job.id,
            title: _job.title,
            description: _job.description,
            employmentType: _job.employmentType,
            experienceRequired: _job.experienceRequired,
            minSalary: _job.minSalary,
            maxSalary: _job.maxSalary,
            salaryType: _job.salaryType,
            qualifications: _job.qualifications,
            skills: _job.skills,
            vacancies: _job.vacancies,
            locationName: _job.locationName,
            latitude: _job.latitude,
            longitude: _job.longitude,
            distanceKm: _job.distanceKm,
            applicationDeadline: _job.applicationDeadline,
            status: _job.status,
            createdAt: _job.createdAt,
            category: _job.category,
            company: _job.company,
            isSaved: !_job.isSaved,
            applicationStatus: _job.applicationStatus,
            contactEmail: _job.contactEmail,
            contactPhone: _job.contactPhone,
            applicationsCount: _job.applicationsCount,
            otherCategoryDescription: _job.otherCategoryDescription,
            contactPreference: _job.contactPreference,
            additionalInstructions: _job.additionalInstructions,
            workStartDate: _job.workStartDate,
          ));
      _message(_job.isSaved ? 'Job saved.' : 'Job removed from saved jobs.');
    } on AuthApiException catch (error) {
      await _handleError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _viewEmployerProfile() async {
    final company = _job.company;
    if (company == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(company.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (company.employerType != null)
                Text('Profession: ${company.employerType}'),
              if (company.location?.isNotEmpty == true)
                Text('Location: ${company.location}'),
              if (company.description?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(company.description!),
              ],
              if (company.website != null) ...[
                const SizedBox(height: 8),
                Text(company.website!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEmployerCommunityProfile() async {
    final profileId = _job.company?.communityProfileId;
    if (profileId == null) return;
    try {
      final profile = await AuthApiService.instance.getCommunityMemberProfile(
        token: widget.token,
        profileId: profileId,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CommunityProfileScreen(
            token: widget.token,
            profile: profile,
            isCurrentUser: false,
          ),
        ),
      );
    } on AuthApiException catch (error) {
      await _handleError(error);
    } catch (_) {
      if (mounted) _message('Could not open the employer Community profile.');
    }
  }

  Future<void> _apply() async {
    final controller = TextEditingController();
    XFile? resume;
    final apply = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Apply for this job'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 5,
                maxLength: 10000,
                decoration: const InputDecoration(
                  labelText: 'Cover letter (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final result = await FilePicker.pickFile(
                    type: FileType.custom,
                    allowedExtensions: const ['pdf', 'doc', 'docx'],
                  );
                  if (result == null) return;
                  try {
                    resume = await _toXFile(result);
                    setDialogState(() {});
                  } on AuthApiException catch (error) {
                    if (mounted) _message(error.message);
                  }
                },
                icon: const Icon(Icons.attach_file),
                label: Text(resume?.name ?? 'Use another resume (optional)'),
              ),
              const SizedBox(height: 4),
              Text(
                'Without an upload, your profile resume will be used.',
                style: AppTextStyles.bodySm.copyWith(color: AppColors.outline),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Submit application'),
            ),
          ],
        ),
      ),
    );
    final coverLetter = controller.text;
    controller.dispose();
    if (apply != true || !mounted) return;
    setState(() => _working = true);
    try {
      await AuthApiService.instance.applyForConstructionJob(
        token: widget.token,
        jobId: _job.id,
        coverLetter: coverLetter,
        resume: resume,
      );
      if (!mounted) return;
      setState(() => _job = ConstructionJob(
            id: _job.id,
            title: _job.title,
            description: _job.description,
            employmentType: _job.employmentType,
            experienceRequired: _job.experienceRequired,
            minSalary: _job.minSalary,
            maxSalary: _job.maxSalary,
            salaryType: _job.salaryType,
            qualifications: _job.qualifications,
            skills: _job.skills,
            vacancies: _job.vacancies,
            locationName: _job.locationName,
            latitude: _job.latitude,
            longitude: _job.longitude,
            distanceKm: _job.distanceKm,
            applicationDeadline: _job.applicationDeadline,
            status: _job.status,
            createdAt: _job.createdAt,
            category: _job.category,
            company: _job.company,
            isSaved: _job.isSaved,
            applicationStatus: 'pending',
            contactEmail: _job.contactEmail,
            contactPhone: _job.contactPhone,
            applicationsCount: _job.applicationsCount,
            otherCategoryDescription: _job.otherCategoryDescription,
            contactPreference: _job.contactPreference,
            additionalInstructions: _job.additionalInstructions,
            workStartDate: _job.workStartDate,
          ));
      _message('Your application was submitted.');
    } on AuthApiException catch (error) {
      await _handleError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<XFile> _toXFile(PlatformFile file) async {
    final size = await file.length();
    if (size == null || size > 10 * 1024 * 1024) {
      throw const AuthApiException('Choose a resume no larger than 10 MB.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isNotEmpty) return XFile.fromData(bytes, name: file.name);
    final path = file.path;
    if (path == null) {
      throw const AuthApiException('Could not read the selected resume.');
    }
    return XFile(path, name: file.name);
  }

  Future<void> _report() async {
    String reason = 'misleading';
    final details = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report this job'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: reason,
                items: const [
                  DropdownMenuItem(value: 'spam', child: Text('Spam')),
                  DropdownMenuItem(
                      value: 'fraud', child: Text('Suspected fraud')),
                  DropdownMenuItem(
                      value: 'misleading',
                      child: Text('Misleading information')),
                  DropdownMenuItem(
                      value: 'inappropriate', child: Text('Inappropriate')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => reason = value);
                },
              ),
              TextField(
                controller: details,
                maxLength: 500,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Details (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit report'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await AuthApiService.instance.reportConstructionJob(
          token: widget.token,
          jobId: _job.id,
          reason: reason,
          details: details.text,
        );
        _message('Report submitted for review.');
      } on AuthApiException catch (error) {
        await _handleError(error);
      }
    }
    details.dispose();
  }

  void _message(String value) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _handleError(AuthApiException error) async {
    if (!mounted) return;
    if (error.isUnauthorized) {
      await AuthSessionNavigation.handleUnauthorized(context, error);
    }
    if (mounted) _message(error.message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Job details'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            tooltip: 'Report job',
            onPressed: _report,
            icon: const Icon(Icons.flag_outlined),
          ),
        ],
      ),
      body: _loading && _error == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(_job.title, style: AppTextStyles.cardTitle),
                    const SizedBox(height: 7),
                    Text(
                      _job.company?.name ?? 'Employer',
                      style: AppTextStyles.titleMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _viewEmployerProfile,
                        icon: const Icon(Icons.business_outlined, size: 18),
                        label: const Text('View employer profile'),
                      ),
                    ),
                    if (_job.company?.communityProfileId != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _openEmployerCommunityProfile,
                          icon: const Icon(Icons.account_circle_outlined),
                          label: const Text('View Community profile'),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(_job.category?.name ?? 'Construction'),
                        _chip(_job.employmentType),
                        _chip(_job.locationName),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _section('Compensation', _salary()),
                    _section('Experience',
                        _job.experienceRequired ?? 'Not specified'),
                    _section('About the role',
                        _job.description ?? 'No description provided.'),
                    if (_job.qualifications.isNotEmpty)
                      _section(
                          'Qualifications', _job.qualifications.join('\n• ')),
                    if (_job.skills.isNotEmpty)
                      _section('Skills', _job.skills.join(' · ')),
                    if (_job.company?.description != null)
                      _section(
                          'About the employer', _job.company!.description!),
                    if (_job.applicationDeadline != null)
                      _section(
                        'Application deadline',
                        MaterialLocalizations.of(context).formatMediumDate(
                          _job.applicationDeadline!.toLocal(),
                        ),
                      ),
                    if (_job.workStartDate != null)
                      _section(
                        'Work starts',
                        MaterialLocalizations.of(context).formatMediumDate(
                          _job.workStartDate!.toLocal(),
                        ),
                      ),
                    if (_job.otherCategoryDescription?.isNotEmpty == true)
                      _section(
                        'Other construction job',
                        _job.otherCategoryDescription!,
                      ),
                    if (_job.additionalInstructions?.isNotEmpty == true)
                      _section(
                        'Additional instructions',
                        _job.additionalInstructions!,
                      ),
                    if (_job.contactEmail != null)
                      _section(
                        'Contact',
                        _job.contactEmail!,
                      ),
                  ],
                ),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: _job.isSaved ? 'Unsave job' : 'Save job',
                      onPressed: _working ? null : _toggleSaved,
                      icon: Icon(_job.isSaved
                          ? Icons.bookmark
                          : Icons.bookmark_border),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _working ||
                                _job.applicationStatus != null ||
                                _job.status != 'published'
                            ? null
                            : _apply,
                        child: Text(
                          _job.applicationStatus ??
                              (_job.status == 'published'
                                  ? 'Apply now'
                                  : _job.status),
                        ),
                      ),
                    ),
                    if (_working) ...[
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _chip(String text) => Chip(
        label: Text(text),
        visualDensity: VisualDensity.compact,
      );

  Widget _section(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.titleMd),
            const SizedBox(height: 6),
            Text(body, style: AppTextStyles.bodyMd),
          ],
        ),
      );

  String _salary() {
    if (_job.minSalary == null && _job.maxSalary == null) {
      return 'Not provided';
    }
    final amount = _job.minSalary == null
        ? 'Up to ${_job.maxSalary}'
        : _job.maxSalary == null
            ? 'From ${_job.minSalary}'
            : '${_job.minSalary} - ${_job.maxSalary}';
    return _job.salaryType == null ? amount : '$amount / ${_job.salaryType}';
  }
}
