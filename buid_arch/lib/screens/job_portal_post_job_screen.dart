import 'dart:async';

import 'package:flutter/material.dart';

import '../models/job_portal.dart';
import '../navigation/auth_session_navigation.dart';
import '../services/auth_api_service.dart';
import '../services/current_location_service.dart';
import '../theme/app_colors.dart';
import 'project_location_picker_screen.dart';

class JobPortalPostJobScreen extends StatefulWidget {
  const JobPortalPostJobScreen({
    super.key,
    required this.token,
    this.job,
  });

  final String token;
  final ConstructionJob? job;

  @override
  State<JobPortalPostJobScreen> createState() => _JobPortalPostJobScreenState();
}

class _JobPortalPostJobScreenState extends State<JobPortalPostJobScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _experience = TextEditingController();
  final _minSalary = TextEditingController();
  final _maxSalary = TextEditingController();
  final _qualifications = TextEditingController();
  final _skills = TextEditingController();
  final _vacancies = TextEditingController(text: '1');
  final _location = TextEditingController();
  final _contactEmail = TextEditingController();
  final _contactPhone = TextEditingController();
  final _otherCategoryDescription = TextEditingController();
  final _additionalInstructions = TextEditingController();
  List<JobPortalCategory> _categories = const [];
  int? _categoryId;
  String _employmentType = 'Full Time';
  String? _salaryType;
  String _contactPreference = 'both';
  double? _latitude;
  double? _longitude;
  DateTime? _applicationDeadline;
  DateTime? _workStartDate;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.job != null;

  bool get _isOtherCategory => _categories.any(
        (category) =>
            category.id == _categoryId &&
            category.slug == 'other-construction-jobs',
      );

  @override
  void initState() {
    super.initState();
    _prefill();
    unawaited(_loadCategories());
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _description,
      _experience,
      _minSalary,
      _maxSalary,
      _qualifications,
      _skills,
      _vacancies,
      _location,
      _contactEmail,
      _contactPhone,
      _otherCategoryDescription,
      _additionalInstructions,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _prefill() {
    final job = widget.job;
    if (job == null) return;
    _title.text = job.title;
    _description.text = job.description ?? '';
    _experience.text = job.experienceRequired ?? '';
    _minSalary.text = job.minSalary?.toString() ?? '';
    _maxSalary.text = job.maxSalary?.toString() ?? '';
    _qualifications.text = job.qualifications.join(', ');
    _skills.text = job.skills.join(', ');
    _vacancies.text = '${job.vacancies ?? 1}';
    _location.text = job.locationName;
    _categoryId = job.category?.id;
    _employmentType = job.employmentType;
    _salaryType = job.salaryType;
    _latitude = job.latitude;
    _longitude = job.longitude;
    _applicationDeadline = job.applicationDeadline;
    _contactEmail.text = job.contactEmail ?? '';
    _contactPhone.text = job.contactPhone ?? '';
    _otherCategoryDescription.text = job.otherCategoryDescription ?? '';
    _additionalInstructions.text = job.additionalInstructions ?? '';
    _contactPreference = job.contactPreference;
    _workStartDate = job.workStartDate;
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await AuthApiService.instance.getJobPortalCategories(
        token: widget.token,
      );
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _categoryId ??= categories.isEmpty ? null : categories.first.id;
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

  Future<void> _chooseLocation() async {
    final result = await Navigator.of(context)
        .push<CurrentDeviceLocation>(MaterialPageRoute(
      builder: (_) => const ProjectLocationPickerScreen(
        title: 'Choose Job Location',
        confirmLabel: 'Use This Location',
      ),
    ));
    if (result == null || !mounted) return;
    setState(() {
      _location.text = result.address;
      _latitude = result.latitude;
      _longitude = result.longitude;
    });
  }

  Future<void> _save(String status) async {
    if (!_formKey.currentState!.validate() || _saving) return;
    final minimum = double.tryParse(_minSalary.text.trim());
    final maximum = double.tryParse(_maxSalary.text.trim());
    if (minimum != null && maximum != null && minimum > maximum) {
      setState(
          () => _error = 'Maximum salary must be at least the minimum salary.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final fields = <String, dynamic>{
      if (!_editing || _categoryId != widget.job?.category?.id)
        'category_id': _categoryId,
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'employment_type': _employmentType,
      if (_editing || _otherCategoryDescription.text.trim().isNotEmpty)
        'other_category_description':
            _otherCategoryDescription.text.trim().isEmpty
                ? null
                : _otherCategoryDescription.text.trim(),
      'contact_preference': _contactPreference,
      if (_editing || _additionalInstructions.text.trim().isNotEmpty)
        'additional_instructions': _additionalInstructions.text.trim().isEmpty
            ? null
            : _additionalInstructions.text.trim(),
      if (_editing || _experience.text.trim().isNotEmpty)
        'experience_required':
            _experience.text.trim().isEmpty ? null : _experience.text.trim(),
      if (_editing || minimum != null) 'min_salary': minimum,
      if (_editing || maximum != null) 'max_salary': maximum,
      if (_editing || _salaryType != null) 'salary_type': _salaryType,
      'qualifications': _split(_qualifications.text),
      'skills': _split(_skills.text),
      'vacancies': int.tryParse(_vacancies.text.trim()) ?? 1,
      'location_name': _location.text.trim(),
      if (_editing || (_latitude != null && _longitude != null)) ...{
        'latitude': _latitude,
        'longitude': _longitude,
      },
      if (_editing || _applicationDeadline != null)
        'application_deadline': _applicationDeadline?.toIso8601String(),
      if (_editing || _workStartDate != null)
        'work_start_date': _workStartDate?.toIso8601String(),
      if (_editing || _contactEmail.text.trim().isNotEmpty)
        'contact_email': _contactEmail.text.trim().isEmpty
            ? null
            : _contactEmail.text.trim(),
      if (_editing || _contactPhone.text.trim().isNotEmpty)
        'contact_phone': _contactPhone.text.trim().isEmpty
            ? null
            : _contactPhone.text.trim(),
      if (!_editing) 'status': status,
    };
    try {
      if (_editing) {
        await AuthApiService.instance.updateConstructionJob(
          token: widget.token,
          jobId: widget.job!.id,
          fields: fields,
        );
      } else {
        await AuthApiService.instance.createConstructionJob(
          token: widget.token,
          fields: fields,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AuthApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        await AuthSessionNavigation.handleUnauthorized(context, error);
      }
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _split(String value) => value
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(_editing ? 'Edit job posting' : 'Post a job'),
        backgroundColor: AppColors.surface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _categoryId,
                    decoration:
                        const InputDecoration(labelText: 'Job category'),
                    items: _categories
                        .map((category) => DropdownMenuItem(
                              value: category.id,
                              child: Text(category.name),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() => _categoryId = value),
                    validator: (value) =>
                        value == null ? 'Choose a category.' : null,
                  ),
                  if (_isOtherCategory)
                    TextFormField(
                      controller: _otherCategoryDescription,
                      decoration: const InputDecoration(
                        labelText: 'Describe the construction job',
                      ),
                      maxLength: 160,
                      validator: _required,
                    ),
                  TextFormField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Job title'),
                    maxLength: 160,
                    validator: _required,
                  ),
                  TextFormField(
                    controller: _description,
                    decoration:
                        const InputDecoration(labelText: 'Job description'),
                    minLines: 5,
                    maxLines: 9,
                    maxLength: 20000,
                    validator: _required,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _employmentType,
                    decoration:
                        const InputDecoration(labelText: 'Employment type'),
                    items: const [
                      'Full Time',
                      'Part Time',
                      'Contract',
                      'Temporary',
                      'Daily Wage',
                    ]
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _employmentType = value);
                      }
                    },
                  ),
                  TextFormField(
                    controller: _experience,
                    decoration: const InputDecoration(
                        labelText: 'Experience required (optional)'),
                    maxLength: 120,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _minSalary,
                          decoration: const InputDecoration(
                              labelText: 'Minimum salary'),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: _salaryValidator,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _maxSalary,
                          decoration: const InputDecoration(
                              labelText: 'Maximum salary'),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: _salaryValidator,
                        ),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String?>(
                    initialValue: _salaryType,
                    decoration: const InputDecoration(
                        labelText: 'Salary frequency (optional)'),
                    items: const [
                      DropdownMenuItem<String?>(
                          value: null, child: Text('Not specified')),
                      DropdownMenuItem(
                          value: 'Monthly', child: Text('Monthly')),
                      DropdownMenuItem(value: 'Fixed', child: Text('Fixed')),
                      DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                      DropdownMenuItem(value: 'Hourly', child: Text('Hourly')),
                    ],
                    onChanged: (value) => setState(() => _salaryType = value),
                  ),
                  TextFormField(
                    controller: _qualifications,
                    decoration: const InputDecoration(
                        labelText: 'Qualifications (comma separated)'),
                  ),
                  TextFormField(
                    controller: _skills,
                    decoration: const InputDecoration(
                        labelText: 'Skills (comma separated)'),
                  ),
                  TextFormField(
                    controller: _vacancies,
                    decoration:
                        const InputDecoration(labelText: 'Number of vacancies'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final count = int.tryParse(value ?? '');
                      return count == null || count < 1 || count > 10000
                          ? 'Enter a number from 1 to 10,000.'
                          : null;
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _location,
                          decoration:
                              const InputDecoration(labelText: 'Job location'),
                          maxLength: 255,
                          validator: (value) {
                            final requiredError = _required(value);
                            if (requiredError != null) return requiredError;
                            if (_latitude == null || _longitude == null) {
                              return 'Choose this location on the map.';
                            }
                            return null;
                          },
                          onChanged: (_) {
                            if (_latitude != null || _longitude != null) {
                              setState(() {
                                _latitude = null;
                                _longitude = null;
                              });
                            }
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: 'Choose on map',
                        onPressed: _chooseLocation,
                        icon: const Icon(Icons.map_outlined),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final deadline = await showDatePicker(
                        context: context,
                        initialDate: _applicationDeadline ??
                            DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now().add(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (deadline != null) {
                        setState(() => _applicationDeadline = DateTime(
                              deadline.year,
                              deadline.month,
                              deadline.day,
                              23,
                              59,
                            ));
                      }
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      _applicationDeadline == null
                          ? 'Add job expiry date (optional)'
                          : 'Expires: ${MaterialLocalizations.of(context).formatMediumDate(_applicationDeadline!)}',
                    ),
                  ),
                  if (_applicationDeadline != null && _editing)
                    TextButton(
                      onPressed: () =>
                          setState(() => _applicationDeadline = null),
                      child: const Text('Remove deadline'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _workStartDate ??
                            DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (date != null) setState(() => _workStartDate = date);
                    },
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: Text(_workStartDate == null
                        ? 'Work start date (optional)'
                        : 'Starts: ${MaterialLocalizations.of(context).formatMediumDate(_workStartDate!)}'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _contactPreference,
                    decoration: const InputDecoration(
                      labelText: 'Contact preference',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'phone', child: Text('Phone')),
                      DropdownMenuItem(value: 'email', child: Text('Email')),
                      DropdownMenuItem(
                        value: 'both',
                        child: Text('Phone or email'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _contactPreference = value);
                      }
                    },
                  ),
                  TextFormField(
                    controller: _additionalInstructions,
                    decoration: const InputDecoration(
                      labelText: 'Additional instructions (optional)',
                    ),
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 5000,
                  ),
                  TextFormField(
                    controller: _contactEmail,
                    decoration: const InputDecoration(
                        labelText: 'Contact email (optional)'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(value.trim())
                          ? null
                          : 'Enter a valid email address.';
                    },
                  ),
                  TextFormField(
                    controller: _contactPhone,
                    decoration: const InputDecoration(
                        labelText: 'Contact phone (optional)'),
                    keyboardType: TextInputType.phone,
                    maxLength: 40,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(color: AppColors.error)),
                  ],
                  const SizedBox(height: 20),
                  if (_editing)
                    FilledButton(
                      onPressed: _saving ? null : () => _save('published'),
                      child: _saving
                          ? const CircularProgressIndicator()
                          : const Text('Save changes'),
                    )
                  else ...[
                    OutlinedButton(
                      onPressed: _saving ? null : () => _save('draft'),
                      child: const Text('Save as draft'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _saving ? null : () => _save('published'),
                      child: _saving
                          ? const CircularProgressIndicator()
                          : const Text('Publish job'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  String? _salaryValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final salary = double.tryParse(value);
    return salary == null || salary < 0
        ? 'Enter a valid non-negative salary.'
        : null;
  }
}
