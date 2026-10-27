import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/project_type.dart';
import '../services/auth_api_service.dart';
import '../services/current_location_service.dart';
import '../services/projects_store.dart';
import 'project_location_picker_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/auth_button.dart';
import '../widgets/profile_text_field.dart';
import '../widgets/project_type_grid_tile.dart';

/// Plain, icon-led "Create Project" form - no blueprint texture, minimal.
class CreateProjectScreen extends StatefulWidget {
  const CreateProjectScreen({super.key});

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  ProjectType? _type;
  XFile? _photo;
  Uint8List? _photoBytes;
  bool _saving = false;
  bool _pickingPhoto = false;
  bool _gettingLocation = false;
  bool _settingDeviceLocation = false;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
    _locationController.addListener(_onLocationChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool get _canCreate =>
      _nameController.text.trim().isNotEmpty &&
      _locationController.text.trim().isNotEmpty &&
      _type != null;

  void _onLocationChanged() {
    if (!_settingDeviceLocation) {
      _latitude = null;
      _longitude = null;
    }
    setState(() {});
  }

  Future<void> _useCurrentLocation() async {
    if (_gettingLocation || _saving) return;
    setState(() => _gettingLocation = true);
    try {
      final location =
          await CurrentLocationService.instance.getCurrentLocation();
      if (!mounted) return;
      _settingDeviceLocation = true;
      _locationController.text = location.address;
      _latitude = location.latitude;
      _longitude = location.longitude;
      _settingDeviceLocation = false;
      setState(() {});
    } on CurrentLocationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  Future<void> _chooseLocationOnMap() async {
    if (_gettingLocation || _saving) return;
    final location = await Navigator.of(context).push<CurrentDeviceLocation>(
      MaterialPageRoute(
        builder: (_) => ProjectLocationPickerScreen(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
        ),
      ),
    );
    if (!mounted || location == null) return;
    _settingDeviceLocation = true;
    _locationController.text = location.address;
    _latitude = location.latitude;
    _longitude = location.longitude;
    _settingDeviceLocation = false;
    setState(() {});
  }

  Future<void> _pickPhoto() async {
    if (_pickingPhoto || _saving) return;
    setState(() => _pickingPhoto = true);

    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _photoBytes = bytes;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not select that photo.')),
        );
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<void> _create() async {
    if (!_canCreate || _saving) return;
    setState(() => _saving = true);

    try {
      await ProjectsStore.instance.create(
        name: _nameController.text.trim(),
        location: _locationController.text.trim(),
        type: _type!,
        latitude: _latitude,
        longitude: _longitude,
        photo: _photo,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AuthApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not create project. Try again.')),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
        ),
        title: Text(
          'Create Project',
          style: AppTextStyles.cardTitle.copyWith(
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryContainer,
                ),
                child: const Icon(Icons.person, size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProfileTextField(
                label: 'Project Name',
                icon: Icons.home_outlined,
                controller: _nameController,
                hintText: 'e.g. Menon Residence',
              ),
              const SizedBox(height: 20),
              Text(
                'Project Photo (Optional)',
                style: AppTextStyles.bodySm.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickPhoto,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 156,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _photoBytes != null
                      ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _pickingPhoto
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.add_a_photo_outlined,
                                      size: 30,
                                      color: AppColors.secondary,
                                    ),
                              const SizedBox(height: 8),
                              Text(
                                _pickingPhoto
                                    ? 'Opening photos...'
                                    : 'Tap to add a project photo',
                                style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              if (_photo != null) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _photo = null;
                              _photoBytes = null;
                            }),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Remove photo'),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              ProfileTextField(
                label: 'Location',
                icon: Icons.location_on_outlined,
                controller: _locationController,
                hintText: 'City, State',
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 16,
                children: [
                  TextButton.icon(
                    onPressed: _gettingLocation ? null : _useCurrentLocation,
                    icon: _gettingLocation
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location, size: 16),
                    label: Text(
                      _gettingLocation
                          ? 'Getting location...'
                          : 'Use current location',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _gettingLocation ? null : _chooseLocationOnMap,
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('Choose on map'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Project Type',
                style: AppTextStyles.bodySm.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final type in ProjectType.values) ...[
                    Expanded(
                      child: ProjectTypeGridTile(
                        type: type,
                        selected: _type == type,
                        onTap: () => setState(() => _type = type),
                      ),
                    ),
                    if (type != ProjectType.values.last)
                      const SizedBox(width: 10),
                  ],
                ],
              ),
              const SizedBox(height: 32),
              Opacity(
                opacity: _canCreate ? 1 : 0.4,
                child: IgnorePointer(
                  ignoring: !_canCreate,
                  child: AuthButton(
                    label: _saving ? 'Creating...' : 'Create Project',
                    onPressed: _create,
                    backgroundColor: AppColors.primaryContainer,
                    pressedColor: AppColors.primary.withAlpha(90),
                    textStyle:
                        AppTextStyles.titleMd.copyWith(color: Colors.white),
                    leading: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add, size: 20, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
