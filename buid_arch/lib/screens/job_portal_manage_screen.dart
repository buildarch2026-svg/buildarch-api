import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/job_portal.dart';
import '../navigation/auth_session_navigation.dart';
import '../services/auth_api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/community_contact_action.dart';
import 'community_profile_screen.dart';
import 'job_portal_post_job_screen.dart';

class JobPortalManageScreen extends StatefulWidget {
  const JobPortalManageScreen({
    super.key,
    required this.token,
    required this.applications,
    this.jobId,
    this.jobTitle,
  });

  final String token;
  final bool applications;
  final int? jobId;
  final String? jobTitle;

  @override
  State<JobPortalManageScreen> createState() => _JobPortalManageScreenState();
}

class _JobPortalManageScreenState extends State<JobPortalManageScreen> {
  List<ConstructionJob> _jobs = const [];
  List<JobPortalApplication> _applications = const [];
  bool _loading = true;
  bool _loadingMore = false;
  int _currentPage = 1;
  int _lastPage = 1;
  String? _error;

  bool get _showApplications => widget.applications;
  bool get _employerApplications => widget.jobId != null;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool nextPage = false}) async {
    if (nextPage) {
      if (_loadingMore || _currentPage >= _lastPage) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (_showApplications) {
        final page = _employerApplications
            ? await AuthApiService.instance.getJobApplicants(
                token: widget.token,
                jobId: widget.jobId!,
                page: nextPage ? _currentPage + 1 : 1,
              )
            : await AuthApiService.instance.getMyJobApplications(
                token: widget.token,
                page: nextPage ? _currentPage + 1 : 1,
              );
        if (!mounted) return;
        setState(() {
          _applications =
              nextPage ? [..._applications, ...page.items] : page.items;
          _currentPage = page.currentPage;
          _lastPage = page.lastPage;
          _loading = false;
          _loadingMore = false;
        });
      } else {
        final page = await AuthApiService.instance.getMyJobPostings(
          token: widget.token,
          page: nextPage ? _currentPage + 1 : 1,
        );
        if (!mounted) return;
        setState(() {
          _jobs = nextPage ? [..._jobs, ...page.items] : page.items;
          _currentPage = page.currentPage;
          _lastPage = page.lastPage;
          _loading = false;
          _loadingMore = false;
        });
      }
    } on AuthApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        await AuthSessionNavigation.handleUnauthorized(context, error);
      }
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _edit(ConstructionJob job) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => JobPortalPostJobScreen(
          token: widget.token,
          job: job,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _updateStatus(ConstructionJob job, String status) async {
    try {
      await AuthApiService.instance.updateConstructionJobStatus(
        token: widget.token,
        jobId: job.id,
        status: status,
      );
      await _load();
    } on AuthApiException catch (error) {
      await _handleError(error);
    }
  }

  Future<void> _deleteJob(ConstructionJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove job posting?'),
        content: const Text(
          'The posting will no longer appear in search. Existing applications are retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AuthApiService.instance.deleteConstructionJob(
        token: widget.token,
        jobId: job.id,
      );
      _message('Job posting removed.');
      await _load();
    } on AuthApiException catch (error) {
      await _handleError(error);
    }
  }

  Future<void> _reviewApplication(JobPortalApplication application) async {
    var status = switch (application.status) {
      'shortlisted' => 'shortlisted',
      'accepted' || 'selected' => 'accepted',
      'rejected' => 'rejected',
      _ => 'pending',
    };
    DateTime? interviewAt;
    final note = TextEditingController();
    final update = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Update application', style: AppTextStyles.titleMd),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(
                      value: 'shortlisted', child: Text('Shortlisted')),
                  DropdownMenuItem(value: 'accepted', child: Text('Accepted')),
                  DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                ],
                onChanged: (value) {
                  if (value != null) setSheetState(() => status = value);
                },
              ),
              if (status == 'interview_scheduled')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(interviewAt == null
                      ? 'Choose interview date and time'
                      : '${MaterialLocalizations.of(context).formatMediumDate(interviewAt!)} '
                          '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(interviewAt!))}'),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(
                        DateTime.now().add(const Duration(hours: 1)),
                      ),
                    );
                    if (time == null) return;
                    setSheetState(() {
                      interviewAt = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  },
                ),
              TextField(
                controller: note,
                maxLength: 5000,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Note to candidate (optional)'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save update'),
              ),
            ],
          ),
        ),
      ),
    );
    final employerNote = note.text;
    note.dispose();
    if (update != true) return;
    if (status == 'interview_scheduled' && interviewAt == null) {
      _message('Choose a date and time for the interview.');
      return;
    }
    try {
      await AuthApiService.instance.updateJobApplication(
        token: widget.token,
        applicationId: application.id,
        status: status,
        interviewAt: interviewAt?.toIso8601String(),
        employerNote: employerNote,
      );
      _message('Application status updated.');
      await _load();
    } on AuthApiException catch (error) {
      await _handleError(error);
    }
  }

  Future<void> _withdraw(JobPortalApplication application) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw application?'),
        content: const Text('The employer will be notified that you withdrew.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AuthApiService.instance.withdrawJobApplication(
        token: widget.token,
        applicationId: application.id,
      );
      _message('Application withdrawn.');
      await _load();
    } on AuthApiException catch (error) {
      await _handleError(error);
    }
  }

  Future<void> _openCandidateProfile(int profileId) async {
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
      if (mounted) await _load();
    } on AuthApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        await AuthSessionNavigation.handleUnauthorized(context, error);
      } else {
        _message(error.message);
      }
    } catch (_) {
      if (mounted) _message('Could not open this Community profile.');
    }
  }

  Future<void> _shareResume(JobPortalApplication application) async {
    try {
      final file = await AuthApiService.instance.downloadJobApplicationResume(
        token: widget.token,
        applicationId: application.id,
        fileName: application.resumeName,
      );
      await SharePlus.instance.share(ShareParams(files: [file]));
    } on AuthApiException catch (error) {
      await _handleError(error);
    }
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
    final title = _employerApplications
        ? 'Applicants'
        : _showApplications
            ? 'My applications'
            : 'My job postings';
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
            widget.jobTitle == null ? title : '$title · ${widget.jobTitle}'),
        backgroundColor: AppColors.surface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _jobs.isEmpty && _applications.isEmpty
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.pixels >=
                              notification.metrics.maxScrollExtent - 300 &&
                          !_loadingMore &&
                          _currentPage < _lastPage) {
                        unawaited(_load(nextPage: true));
                      }
                      return false;
                    },
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_showApplications && _applications.isEmpty)
                          _empty('No applications to show yet.')
                        else if (!_showApplications && _jobs.isEmpty)
                          _empty('You have not posted a job yet.')
                        else if (_showApplications)
                          for (final application in _applications)
                            _applicationCard(application)
                        else
                          for (final job in _jobs) _jobCard(job),
                        if (_loadingMore)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _jobCard(ConstructionJob job) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(job.title, style: AppTextStyles.titleMd),
              const SizedBox(height: 5),
              Text('${job.locationName} · ${job.status}'),
              Text('${job.applicationsCount ?? 0} applicants'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _edit(job),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => JobPortalManageScreen(
                          token: widget.token,
                          applications: true,
                          jobId: job.id,
                          jobTitle: job.title,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.people_outline),
                    label: const Text('Applicants'),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Change posting status',
                    onSelected: (status) {
                      if (status == 'delete') {
                        _deleteJob(job);
                      } else {
                        _updateStatus(job, status);
                      }
                    },
                    itemBuilder: (_) => [
                      if (job.status != 'published')
                        const PopupMenuItem(
                            value: 'published',
                            child: Text('Publish / reopen')),
                      if (job.status != 'paused')
                        const PopupMenuItem(
                            value: 'paused', child: Text('Pause')),
                      if (job.status != 'closed')
                        const PopupMenuItem(
                            value: 'closed', child: Text('Close')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Remove posting'),
                      ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.more_vert),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _applicationCard(JobPortalApplication application) {
    final candidate = application.candidate;
    final job = application.job;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _employerApplications
                  ? (candidate?['full_name']?.toString() ?? 'Candidate')
                  : (job?.title ?? 'Job application'),
              style: AppTextStyles.titleMd,
            ),
            const SizedBox(height: 5),
            Text(
              _employerApplications
                  ? 'Status: ${application.status.replaceAll('_', ' ')}'
                  : '${job?.company?.name ?? ''} · ${application.status.replaceAll('_', ' ')}',
            ),
            if (application.appliedAt != null)
              Text(
                'Applied ${MaterialLocalizations.of(context).formatMediumDate(application.appliedAt!.toLocal())}',
                style: AppTextStyles.bodySm,
              ),
            if (_employerApplications && candidate != null) ...[
              const Divider(height: 20),
              if (candidate['community_profile_id'] is num)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(
                      (candidate['full_name']?.toString().isNotEmpty == true)
                          ? candidate['full_name']
                              .toString()
                              .substring(0, 1)
                              .toUpperCase()
                          : '?',
                    ),
                  ),
                  title:
                      Text(candidate['full_name']?.toString() ?? 'Candidate'),
                  subtitle: const Text('View Community profile'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openCandidateProfile(
                    (candidate['community_profile_id'] as num).toInt(),
                  ),
                ),
              if (candidate['profession'] != null)
                Text('Profession: ${candidate['profession']}'),
              if (candidate['email'] != null)
                Text('Email: ${candidate['email']}'),
              if (candidate['user_id'] is num) ...[
                const SizedBox(height: 8),
                CommunityContactAction(
                  token: widget.token,
                  userId: (candidate['user_id'] as num).toInt(),
                ),
              ],
              if (candidate['skills'] is List)
                Text('Skills: ${(candidate['skills'] as List).join(', ')}'),
              if (application.coverLetter?.isNotEmpty == true)
                Text('Cover letter: ${application.coverLetter}'),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _shareResume(application),
                    icon: const Icon(Icons.download_outlined),
                    label: Text(application.resumeName.isEmpty
                        ? 'Resume'
                        : application.resumeName),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _reviewApplication(application),
                    child: const Text('Review'),
                  ),
                ],
              ),
            ] else if (!_employerApplications) ...[
              if (application.interviewAt != null)
                Text('Interview: ${application.interviewAt!.toLocal()}'),
              if (application.employerNote?.isNotEmpty == true)
                Text('Employer note: ${application.employerNote}'),
              if (!['accepted', 'selected', 'rejected', 'withdrawn']
                  .contains(application.status))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _withdraw(application),
                    child: const Text('Withdraw'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _empty(String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 90, horizontal: 20),
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
}
