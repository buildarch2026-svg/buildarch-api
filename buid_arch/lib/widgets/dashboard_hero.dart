import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/project.dart';
import '../services/auth_api_service.dart';
import '../services/projects_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Rounded-bottom hero: the project photo when there is one, otherwise a
/// copper gradient with a house icon. Status row sits underneath.
class DashboardHero extends StatefulWidget {
  const DashboardHero({
    super.key,
    required this.project,
    this.statusLabel = 'Active',
    this.updatedLabel = 'Updated 2h ago',
  });

  final Project project;
  final String statusLabel;
  final String updatedLabel;

  @override
  State<DashboardHero> createState() => _DashboardHeroState();
}

class _DashboardHeroState extends State<DashboardHero> {
  final _imagePicker = ImagePicker();
  String? _photoUrl;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _photoUrl = widget.project.photoUrl;
  }

  @override
  void didUpdateWidget(covariant DashboardHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id ||
        oldWidget.project.photoUrl != widget.project.photoUrl) {
      _photoUrl = widget.project.photoUrl;
    }
  }

  Future<void> _updatePhoto() async {
    if (_uploadingPhoto) return;
    setState(() => _uploadingPhoto = true);

    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (photo == null) return;

      final project = await ProjectsStore.instance.updatePhoto(
        projectId: widget.project.id,
        photo: photo,
      );
      if (!mounted) return;
      setState(() => _photoUrl = project.photoUrl);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Project photo updated.')),
        );
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
          const SnackBar(content: Text('Could not update the project photo.')),
        );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photoUrl;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo != null)
              Image.network(
                photo,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _gradient(),
              )
            else
              _gradient(),
            if (photo != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withAlpha(60),
                      Colors.black.withAlpha(120),
                    ],
                  ),
                ),
              ),
            if (widget.project.isOwner)
              Positioned(
                right: 16,
                bottom: 16,
                child: FilledButton.icon(
                  onPressed: _uploadingPhoto ? null : _updatePhoto,
                  icon: _uploadingPhoto
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          photo == null
                              ? Icons.add_a_photo_outlined
                              : Icons.edit_outlined,
                        ),
                  label: Text(
                    _uploadingPhoto
                        ? 'Updating...'
                        : photo == null
                            ? 'Add photo'
                            : 'Update photo',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black.withAlpha(150),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (photo == null) ...[
                    const Icon(Icons.home_outlined,
                        size: 80, color: Colors.white),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.statusLabel,
                        style: AppTextStyles.bodyMd.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '•',
                        style: AppTextStyles.bodySm
                            .copyWith(color: Colors.white54),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.updatedLabel,
                        style: AppTextStyles.bodySm
                            .copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradient() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryContainer,
              AppColors.primary,
              AppColors.tertiary,
            ],
          ),
        ),
      );
}
