import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/community.dart';
import '../navigation/community_navigation.dart';
import '../services/auth_api_service.dart';
import '../services/current_location_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_bottom_nav.dart';
import 'project_location_picker_screen.dart';

class CommunityRegistrationScreen extends StatefulWidget {
  const CommunityRegistrationScreen({
    super.key,
    required this.token,
    required this.user,
    required this.onRegistered,
    required this.onTabSelected,
    this.communityOnly = false,
  });

  final String token;
  final Map<String, dynamic> user;
  final ValueChanged<CommunityProfile> onRegistered;
  final ValueChanged<AppTab> onTabSelected;
  final bool communityOnly;

  @override
  State<CommunityRegistrationScreen> createState() =>
      _CommunityRegistrationScreenState();
}

class _CommunityRegistrationScreenState
    extends State<CommunityRegistrationScreen> {
  static const _professions = [
    'Homeowner',
    'Designer',
    'Contractor',
    'Architect',
    'Civil Engineer',
    'Interior Designer',
    'Student',
    'Other',
  ];

  late final _displayName = TextEditingController(
    text: widget.user['name'] is String ? widget.user['name'] as String : '',
  );
  late final _location = TextEditingController(
    text: widget.user['location'] is String
        ? widget.user['location'] as String
        : '',
  );
  final _otherProfession = TextEditingController();
  final _bio = TextEditingController();
  String? _profession;
  XFile? _profileImage;
  Uint8List? _profileImageBytes;
  bool _guidelinesAccepted = false;
  bool _saving = false;
  bool _choosingLocation = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _profession = switch (widget.user['role']) {
      'homeOwner' || 'homeowner' => 'Homeowner',
      'contractor' => 'Contractor',
      'designer' => 'Designer',
      _ => null,
    };
  }

  @override
  void dispose() {
    _displayName.dispose();
    _location.dispose();
    _otherProfession.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _chooseImage() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1400,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (mounted) {
        setState(() {
          _profileImage = image;
          _profileImageBytes = bytes;
          _error = null;
        });
      }
    } on Exception {
      if (mounted) {
        setState(
            () => _error = 'Could not open your photos. Please try again.');
      }
    }
  }

  Future<void> _chooseLocation() async {
    if (_choosingLocation || _saving) return;
    setState(() => _choosingLocation = true);
    try {
      final location = await Navigator.of(context)
          .push<CurrentDeviceLocation>(MaterialPageRoute(
        builder: (_) => const ProjectLocationPickerScreen(
          title: 'Choose Community Location',
          confirmLabel: 'Use This Location',
          consumeSharedLocation: false,
        ),
      ));
      if (mounted && location != null) {
        setState(() {
          _location.text = location.address;
          _error = null;
        });
      }
    } finally {
      if (mounted) setState(() => _choosingLocation = false);
    }
  }

  Future<void> _showGuidelines() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Community guidelines'),
        content: const SingleChildScrollView(
          child: Text(
            'Keep discussions respectful and useful. Share accurate, '
            'construction-related information; protect personal information; '
            'do not post private project documents, contact details, spam, '
            'harassment, or unlawful content. Report content that needs review.',
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

  Future<void> _register() async {
    final name = _displayName.text.trim();
    if (name.isEmpty || name.length > 80) {
      setState(() => _error = 'Enter a display name of up to 80 characters.');
      return;
    }
    if (_profession == 'Other' && _otherProfession.text.trim().isEmpty) {
      setState(() => _error = 'Enter your profession.');
      return;
    }
    if (!_guidelinesAccepted) {
      setState(() => _error = 'Please accept the Community guidelines.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await AuthApiService.instance.registerCommunityProfile(
        token: widget.token,
        displayName: name,
        profession: _profession,
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        otherProfession:
            _profession == 'Other' ? _otherProfession.text.trim() : null,
        bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        profileImage: _profileImage,
      );
      if (mounted) widget.onRegistered(profile);
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not create your Community profile.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onTabSelected(AppTab tab) {
    widget.onTabSelected(tab);
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.user['email'] as String?;
    final phone = widget.user['phone_number'] as String?;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Join the Community'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Complete your Community profile',
              style: AppTextStyles.cardTitle.copyWith(
                fontSize: 23,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Use your Build Arch account. Your Community profession is '
              'separate from your project role.',
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  _ProfileImagePicker(
                    imageBytes: _profileImageBytes,
                    onTap: _saving ? null : _chooseImage,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _saving ? null : _chooseImage,
                    child: Text(_profileImage == null
                        ? 'Add profile image (optional)'
                        : 'Change profile image'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _displayName,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Community username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _location,
              readOnly: true,
              onTap: _saving ? null : _chooseLocation,
              maxLength: 255,
              decoration: InputDecoration(
                labelText: 'Community location (optional)',
                hintText: 'Choose a location',
                border: const OutlineInputBorder(),
                suffixIcon: _choosingLocation
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Choose location',
                        onPressed: _saving ? null : _chooseLocation,
                        icon: const Icon(Icons.map_outlined),
                      ),
              ),
            ),
            if (email != null && email.isNotEmpty) ...[
              const SizedBox(height: 12),
              _accountValue('Build Arch email', email),
            ],
            if (phone != null && phone.isNotEmpty) ...[
              const SizedBox(height: 12),
              _accountValue('Build Arch phone', phone),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _profession,
              decoration: const InputDecoration(
                labelText: 'Community profession (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final profession in _professions)
                  DropdownMenuItem(
                    value: profession,
                    child: Text(profession),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _profession = value),
            ),
            if (_profession == 'Other') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _otherProfession,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Enter your profession',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _bio,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Bio (optional)',
                hintText: 'Tell the community a little about yourself.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _guidelinesAccepted,
              onChanged: _saving
                  ? null
                  : (value) =>
                      setState(() => _guidelinesAccepted = value ?? false),
              title: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('I agree to the '),
                  InkWell(
                    onTap: _showGuidelines,
                    child: const Text(
                      'Community guidelines',
                      style: TextStyle(
                        color: AppColors.secondary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _register,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Join Community'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        current: AppTab.community,
        onTap: _onTabSelected,
        communityOnly: widget.communityOnly,
      ),
    );
  }

  Widget _accountValue(String label, String value) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
      ),
      child: Text(value),
    );
  }
}

class _ProfileImagePicker extends StatelessWidget {
  const _ProfileImagePicker({
    required this.imageBytes,
    required this.onTap,
  });

  final Uint8List? imageBytes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: CircleAvatar(
        radius: 42,
        backgroundColor: AppColors.primaryContainer.withAlpha(25),
        child: imageBytes != null
            ? ClipOval(
                child: Image.memory(
                  imageBytes!,
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                ),
              )
            : const Icon(
                Icons.add_a_photo_outlined,
                color: AppColors.secondary,
                size: 28,
              ),
      ),
    );
  }
}
