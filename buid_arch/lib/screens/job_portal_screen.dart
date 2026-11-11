import 'dart:async';

import 'package:flutter/material.dart';

import '../models/job_portal.dart';
import '../navigation/auth_session_navigation.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../services/current_location_service.dart';
import '../models/community.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'job_portal_job_detail_screen.dart';
import 'job_portal_manage_screen.dart';
import 'job_portal_post_job_screen.dart';
import 'community_profile_screen.dart';
import 'project_location_picker_screen.dart';

class JobPortalScreen extends StatefulWidget {
  const JobPortalScreen({super.key});

  @override
  State<JobPortalScreen> createState() => _JobPortalScreenState();
}

class _JobPortalScreenState extends State<JobPortalScreen> {
  final _searchController = TextEditingController();
  final _locationController = TextEditingController();
  final _minSalaryController = TextEditingController();
  final _maxSalaryController = TextEditingController();
  final _experienceController = TextEditingController();
  String? _token;
  String? _error;
  String? _selectedCategory;
  String? _selectedEmployment;
  double? _latitude;
  double? _longitude;
  int? _distanceKm;
  String _sort = 'latest';
  List<JobPortalCategory> _categories = const [];
  List<ConstructionJob> _jobs = const [];
  JobPortalDashboard? _dashboard;
  int _currentPage = 1;
  int _lastPage = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _locationController.dispose();
    _minSalaryController.dispose();
    _maxSalaryController.dispose();
    _experienceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await AuthSessionService.instance.readToken();
      if (token == null || token.isEmpty) {
        throw const AuthApiException(
            'Your session has expired. Please sign in again.',
            statusCode: 401);
      }
      final results = await Future.wait([
        AuthApiService.instance.getJobPortalDashboard(token: token),
        AuthApiService.instance.getJobPortalCategories(token: token),
        AuthApiService.instance.getConstructionJobs(token: token),
      ]);
      if (!mounted) return;
      final page = results[2] as JobPortalPage<ConstructionJob>;
      setState(() {
        _token = token;
        _dashboard = results[0] as JobPortalDashboard;
        _categories = results[1] as List<JobPortalCategory>;
        _jobs = page.items;
        _currentPage = page.currentPage;
        _lastPage = page.lastPage;
        _loading = false;
      });
    } on AuthApiException catch (error) {
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

  Future<void> _search({bool reset = true}) async {
    final token = _token;
    if (token == null || _searching) return;
    if (reset) {
      setState(() {
        _searching = true;
        _error = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final page = await AuthApiService.instance.getConstructionJobs(
        token: token,
        page: reset ? 1 : _currentPage + 1,
        query: _searchController.text,
        category: _selectedCategory,
        employmentType: _selectedEmployment,
        location: _locationController.text,
        latitude: _latitude,
        longitude: _longitude,
        distanceKm: _distanceKm,
        minSalary: double.tryParse(_minSalaryController.text.trim()),
        maxSalary: double.tryParse(_maxSalaryController.text.trim()),
        experience: _experienceController.text,
        sort: _sort,
      );
      if (!mounted) return;
      setState(() {
        _jobs = reset ? page.items : [..._jobs, ...page.items];
        _currentPage = page.currentPage;
        _lastPage = page.lastPage;
        _searching = false;
        _loadingMore = false;
      });
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        await AuthSessionNavigation.handleUnauthorized(context, error);
      }
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _searching = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    final token = _token;
    if (token == null) return _load();
    try {
      final dashboard = await AuthApiService.instance.getJobPortalDashboard(
        token: token,
      );
      if (!mounted) return;
      setState(() => _dashboard = dashboard);
      await _search();
    } on AuthApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        await AuthSessionNavigation.handleUnauthorized(context, error);
      }
      if (mounted) _showMessage(error.message);
    }
  }

  Future<CurrentDeviceLocation?> _pickLocation() {
    return Navigator.of(context).push<CurrentDeviceLocation>(MaterialPageRoute(
      builder: (_) => const ProjectLocationPickerScreen(
        title: 'Choose Job Search Location',
        confirmLabel: 'Search Nearby',
      ),
    ));
  }

  Future<void> _chooseLocation() async {
    final result = await _pickLocation();
    if (result == null || !mounted) return;
    setState(() {
      _latitude = result.latitude;
      _longitude = result.longitude;
      _locationController.text = result.address;
      _distanceKm ??= 25;
    });
    await _search();
  }

  Future<void> _openCommunityProfile() async {
    final token = _token;
    final profile = _dashboard?.communityProfile;
    if (token == null || profile == null) return;
    final updated = await Navigator.of(context).push<CommunityProfile>(
      MaterialPageRoute(
        builder: (_) => CommunityProfileScreen(
          token: token,
          profile: profile,
          isCurrentUser: true,
        ),
      ),
    );
    if (updated != null) await _refresh();
  }

  Future<void> _openPostJob() async {
    final token = _token;
    if (token == null) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => JobPortalPostJobScreen(token: token)),
    );
    if (created == true) await _refresh();
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
        title: const Text('Construction Jobs'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Job portal actions',
            onSelected: (value) async {
              switch (value) {
                case 'nearby':
                  await _searchNearby();
                case 'profile':
                  await _openCommunityProfile();
                case 'applications':
                  await _openActivity(applications: true);
                case 'postings':
                  await _openActivity(applications: false);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'nearby', child: Text('Nearby jobs')),
              const PopupMenuItem(
                  value: 'profile',
                  child: Text('Community profile & job settings')),
              const PopupMenuItem(
                  value: 'applications', child: Text('My applications')),
              const PopupMenuItem(
                  value: 'postings', child: Text('My job postings')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openPostJob,
        icon: const Icon(Icons.add),
        label: const Text('Post a job'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _jobs.isEmpty
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.pixels >=
                              notification.metrics.maxScrollExtent - 300 &&
                          !_loadingMore &&
                          !_searching &&
                          _currentPage < _lastPage) {
                        unawaited(_search(reset: false));
                      }
                      return false;
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _openPostJob,
                                icon: const Icon(Icons.add_business_outlined),
                                label: const Text('Post a Job'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _search(),
                                icon: const Icon(Icons.search),
                                label: const Text('Find Jobs'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                textInputAction: TextInputAction.search,
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) => _search(),
                                decoration: InputDecoration(
                                  hintText: 'Search jobs or skills',
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: _searchController.text.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'Clear search',
                                          onPressed: () {
                                            _searchController.clear();
                                            _search();
                                          },
                                          icon: const Icon(Icons.close),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: _activeFilterCount == 0
                                  ? 'Filter jobs'
                                  : 'Filter jobs ($_activeFilterCount active)',
                              onPressed: _openFilters,
                              icon: Badge(
                                isLabelVisible: _activeFilterCount > 0,
                                label: Text('$_activeFilterCount'),
                                child: const Icon(Icons.tune),
                              ),
                            ),
                          ],
                        ),
                        if (_latitude != null ||
                            _locationController.text.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: InputChip(
                              avatar: const Icon(
                                Icons.location_on_outlined,
                                size: 18,
                              ),
                              label: Text(
                                _locationController.text.isEmpty
                                    ? 'Nearby · ${_distanceKm ?? 25} km'
                                    : _latitude == null
                                        ? _locationController.text
                                        : '${_locationController.text} · ${_distanceKm ?? 25} km',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onDeleted: () {
                                setState(() {
                                  _locationController.clear();
                                  _latitude = null;
                                  _longitude = null;
                                  _distanceKm = null;
                                });
                                _search();
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Text('Explore jobs', style: AppTextStyles.titleMd),
                        const SizedBox(height: 8),
                        if (_searching)
                          const LinearProgressIndicator(minHeight: 2),
                        if (_jobs.isEmpty)
                          _emptyJobs()
                        else
                          for (final job in _jobs) ...[
                            _jobCard(job),
                            const SizedBox(height: 10),
                          ],
                        if (_loadingMore)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        if (_error != null && _jobs.isNotEmpty)
                          TextButton.icon(
                            onPressed: _search,
                            icon: const Icon(Icons.refresh),
                            label: Text(_error!),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }

  int get _activeFilterCount => [
        _selectedCategory != null,
        _selectedEmployment != null,
        _locationController.text.isNotEmpty || _latitude != null,
        _sort != 'latest',
        _minSalaryController.text.isNotEmpty,
        _maxSalaryController.text.isNotEmpty,
        _experienceController.text.isNotEmpty,
      ].where((active) => active).length;

  Future<void> _openFilters() async {
    final location = TextEditingController(text: _locationController.text);
    final minimumSalary =
        TextEditingController(text: _minSalaryController.text);
    final maximumSalary =
        TextEditingController(text: _maxSalaryController.text);
    final experience = TextEditingController(text: _experienceController.text);
    var category = _selectedCategory;
    var employment = _selectedEmployment;
    var sort = _sort;
    var latitude = _latitude;
    var longitude = _longitude;
    var distance = _distanceKm ?? 25;

    try {
      final result = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.outline.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Filter jobs', style: AppTextStyles.titleMd),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    initialValue: category,
                    decoration:
                        const InputDecoration(labelText: 'Job category'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All categories'),
                      ),
                      for (final item in _categories)
                        DropdownMenuItem<String?>(
                          value: item.slug,
                          child: Text(item.name),
                        ),
                    ],
                    onChanged: (value) => setSheetState(() => category = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: employment,
                    decoration:
                        const InputDecoration(labelText: 'Employment type'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Any type'),
                      ),
                      for (final type in const [
                        'Full Time',
                        'Part Time',
                        'Contract',
                        'Temporary',
                        'Daily Wage',
                      ])
                        DropdownMenuItem<String?>(
                          value: type,
                          child: Text(type),
                        ),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => employment = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: location,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setSheetState(() {
                      latitude = null;
                      longitude = null;
                      if (sort == 'nearest') sort = 'latest';
                    }),
                    decoration: InputDecoration(
                      labelText: 'Location',
                      hintText: 'City, area, or site',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      suffixIcon: IconButton(
                        tooltip: 'Choose on map',
                        onPressed: () async {
                          final selected = await _pickLocation();
                          if (selected == null) return;
                          setSheetState(() {
                            latitude = selected.latitude;
                            longitude = selected.longitude;
                            location.text = selected.address;
                          });
                        },
                        icon: const Icon(Icons.map_outlined),
                      ),
                    ),
                  ),
                  if (latitude != null) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: distance,
                      decoration:
                          const InputDecoration(labelText: 'Search radius'),
                      items: [
                        for (final radius in [5, 10, 25, 50, 100])
                          DropdownMenuItem(
                            value: radius,
                            child: Text('$radius km'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => distance = value);
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: sort,
                    decoration: const InputDecoration(labelText: 'Sort by'),
                    items: const [
                      DropdownMenuItem(
                        value: 'latest',
                        child: Text('Newest first'),
                      ),
                      DropdownMenuItem(
                        value: 'nearest',
                        child: Text('Nearest first'),
                      ),
                      DropdownMenuItem(
                        value: 'salary_desc',
                        child: Text('Highest salary'),
                      ),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      if (value == 'nearest' && latitude == null) {
                        final selected = await _pickLocation();
                        if (selected == null) return;
                        setSheetState(() {
                          latitude = selected.latitude;
                          longitude = selected.longitude;
                          location.text = selected.address;
                        });
                      }
                      setSheetState(() => sort = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minimumSalary,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration:
                              const InputDecoration(labelText: 'Min salary'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: maximumSalary,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration:
                              const InputDecoration(labelText: 'Max salary'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: experience,
                    decoration: const InputDecoration(
                      labelText: 'Experience',
                      hintText: 'e.g. 2 years',
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext, 'clear'),
                        child: const Text('Clear all'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(sheetContext, 'apply'),
                        icon: const Icon(Icons.check),
                        label: const Text('Show jobs'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (!mounted || result == null) return;
      if (result == 'clear') {
        setState(() {
          _selectedCategory = null;
          _selectedEmployment = null;
          _locationController.clear();
          _minSalaryController.clear();
          _maxSalaryController.clear();
          _experienceController.clear();
          _latitude = null;
          _longitude = null;
          _distanceKm = null;
          _sort = 'latest';
        });
      } else {
        setState(() {
          _selectedCategory = category;
          _selectedEmployment = employment;
          _locationController.text = location.text.trim();
          _minSalaryController.text = minimumSalary.text.trim();
          _maxSalaryController.text = maximumSalary.text.trim();
          _experienceController.text = experience.text.trim();
          _latitude = latitude;
          _longitude = longitude;
          _distanceKm = latitude == null ? null : distance;
          _sort = sort;
        });
      }
      await _search();
    } finally {
      location.dispose();
      minimumSalary.dispose();
      maximumSalary.dispose();
      experience.dispose();
    }
  }

  Future<void> _searchNearby() async {
    final profile = _dashboard?.communityProfile;
    if (profile?.preferredLatitude != null &&
        profile?.preferredLongitude != null) {
      setState(() {
        _latitude = profile!.preferredLatitude;
        _longitude = profile.preferredLongitude;
        _locationController.text = profile.preferredLocation ?? '';
        _distanceKm = profile.preferredRadiusKm;
        _sort = 'nearest';
      });
      await _search();
      return;
    }
    setState(() => _sort = 'nearest');
    await _chooseLocation();
  }

  Widget _jobCard(ConstructionJob job) => Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => JobPortalJobDetailScreen(
                  token: _token!,
                  initialJob: job,
                ),
              ),
            );
            if (changed == true) await _refresh();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        job.title,
                        style: AppTextStyles.titleMd,
                      ),
                    ),
                    if (job.isSaved)
                      const Icon(Icons.bookmark, color: AppColors.primary),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  job.company?.name ?? 'Employer',
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _detailTag(
                      job.category?.name ?? 'Construction',
                      background: AppColors.surfaceContainerLow,
                    ),
                    _detailTag(
                      job.employmentType,
                      background: AppColors.surfaceContainerLowest,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _metadata(Icons.location_on_outlined, job.locationName),
                if (job.distanceKm != null) ...[
                  const SizedBox(height: 4),
                  _metadata(Icons.near_me_outlined,
                      '${job.distanceKm!.toStringAsFixed(1)} km away'),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        job.minSalary != null || job.maxSalary != null
                            ? _salary(job)
                            : 'Salary not listed',
                        style: AppTextStyles.titleMd.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    _detailTag(
                      'Open',
                      foreground: AppColors.success,
                      background: AppColors.success.withValues(alpha: 0.1),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _metadata(
                  Icons.people_outline,
                  '${job.vacancies ?? 1} ${job.vacancies == 1 ? 'vacancy' : 'vacancies'}'
                  '${job.createdAt == null ? '' : ' · Posted ${MaterialLocalizations.of(context).formatShortDate(job.createdAt!.toLocal())}'}',
                ),
              ],
            ),
          ),
        ),
      );

  Widget _detailTag(
    String label, {
    required Color background,
    Color? foreground,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySm.copyWith(
            color: foreground ?? AppColors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _metadata(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.outline),
          const SizedBox(width: 4),
          Text(text, style: AppTextStyles.bodySm),
        ],
      );

  String _salary(ConstructionJob job) {
    final range = job.minSalary == null
        ? 'Up to ${job.maxSalary}'
        : job.maxSalary == null
            ? 'From ${job.minSalary}'
            : '${job.minSalary} - ${job.maxSalary}';
    return job.salaryType == null ? range : '$range / ${job.salaryType}';
  }

  Widget _emptyJobs() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
        child: Column(
          children: [
            const Icon(Icons.work_off_outlined,
                size: 48, color: AppColors.outline),
            const SizedBox(height: 12),
            Text('No matching jobs yet', style: AppTextStyles.titleMd),
            const SizedBox(height: 5),
            Text(
              'Try changing your search or filters, or check back soon.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.outline),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _openFilters,
              icon: const Icon(Icons.tune),
              label: const Text('Adjust filters'),
            ),
          ],
        ),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 44),
              const SizedBox(height: 12),
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

  Future<void> _openActivity({required bool applications}) async {
    final token = _token;
    if (token == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => JobPortalManageScreen(
          token: token,
          applications: applications,
        ),
      ),
    );
    await _refresh();
  }
}
