import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/community.dart';
import '../navigation/community_navigation.dart';
import '../services/auth_api_service.dart';
import '../theme/app_colors.dart';

class CommunityCreatePostScreen extends StatefulWidget {
  const CommunityCreatePostScreen({
    super.key,
    required this.token,
    required this.categories,
  });

  final String token;
  final List<CommunityCategory> categories;

  @override
  State<CommunityCreatePostScreen> createState() =>
      _CommunityCreatePostScreenState();
}

class _CommunityCreatePostScreenState extends State<CommunityCreatePostScreen> {
  static const _maxImages = 5;

  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _images = [];
  final List<Uint8List> _imageBytes = [];
  int? _categoryId;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _chooseImages() async {
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) return;
    try {
      final images = await _picker.pickMultiImage(
        maxWidth: 2000,
        imageQuality: 85,
        limit: remaining,
      );
      if (images.isEmpty) return;
      final selected = images.take(remaining).toList(growable: false);
      final bytes =
          await Future.wait(selected.map((image) => image.readAsBytes()));
      if (mounted) {
        setState(() {
          _images.addAll(selected);
          _imageBytes.addAll(bytes);
        });
      }
    } on Exception catch (_) {
      if (mounted) setState(() => _error = 'Could not open your photos.');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final post = await AuthApiService.instance.createCommunityPost(
        token: widget.token,
        content: _contentController.text.trim(),
        categoryId: _categoryId,
        images: _images,
      );
      if (mounted) Navigator.of(context).pop(post);
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        if (!mounted) return;
        await CommunityNavigation.handleUnauthorized(context, error);
      }
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not publish your post. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Create a post'),
        backgroundColor: AppColors.surface,
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Publish'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _contentController,
              autofocus: true,
              minLines: 5,
              maxLines: 12,
              maxLength: 5000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText:
                    'Share your thoughts, ask a question, or discuss something with the community...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Write something before publishing.';
                }
                if (value.trim().length > 5000) {
                  return 'Keep your post under 5,000 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int>(
                  value: null,
                  child: Text('No category'),
                ),
                for (final category in widget.categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Photos (${_images.length}/$_maxImages)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (_images.length < _maxImages)
                  TextButton.icon(
                    onPressed: _saving ? null : _chooseImages,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Add images'),
                  ),
              ],
            ),
            if (_images.isNotEmpty)
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 10.0;
                  const maxTileWidth = 160.0;
                  final columns =
                      (constraints.maxWidth / (maxTileWidth + spacing))
                          .floor()
                          .clamp(2, 4);
                  final tileWidth =
                      ((constraints.maxWidth - spacing * (columns - 1)) /
                              columns)
                          .clamp(0.0, maxTileWidth)
                          .toDouble();
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (var index = 0; index < _images.length; index++)
                        SizedBox(
                          width: tileWidth,
                          height: tileWidth * 0.78,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(
                                  _imageBytes[index],
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Material(
                                    color: Colors.black54,
                                    shape: const CircleBorder(),
                                    child: IconButton(
                                      tooltip: 'Remove image',
                                      onPressed: _saving
                                          ? null
                                          : () => setState(() {
                                                _images.removeAt(index);
                                                _imageBytes.removeAt(index);
                                              }),
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      constraints:
                                          const BoxConstraints.tightFor(
                                        width: 34,
                                        height: 34,
                                      ),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
          ],
        ),
      ),
    );
  }
}
