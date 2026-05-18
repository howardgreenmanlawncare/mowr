import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/lawn_area_model.dart';
import '../../mock/mock_properties.dart';
import '../../providers/booking_draft_provider.dart';
import '../booking_shell.dart';

class ConditionPhotosStepScreen extends ConsumerWidget {
  const ConditionPhotosStepScreen({super.key});

  static const routePath = '/booking/condition-photos';

  static Future<ImageSource?> _showSourceSheet(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingDraftProvider);
    final property = mockPropertyById(draft.propertyId);
    final selectedLawns = property.lawnAreas
        .where((l) => draft.selectedLawnIds.contains(l.id))
        .toList();

    return BookingShell(
      stepIndex: kStepConditionPhotos,
      stepLabel: 'Condition photos',
      onContinue: () => context.push('/booking/service'),
      body: _ConditionPhotosBody(
        lawns: selectedLawns,
        lawnPhotos: draft.lawnConditionPhotos,
        onAddPhoto: (lawnId) async {
          final source = await _showSourceSheet(context);
          if (source == null || !context.mounted) return;
          final file = await ImagePicker().pickImage(source: source);
          if (file != null) {
            ref
                .read(bookingDraftProvider.notifier)
                .addConditionPhoto(lawnId, file.path);
          }
        },
        onRemovePhoto: (lawnId, path) => ref
            .read(bookingDraftProvider.notifier)
            .removeConditionPhoto(lawnId, path),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ConditionPhotosBody extends StatelessWidget {
  const _ConditionPhotosBody({
    required this.lawns,
    required this.lawnPhotos,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  final List<LawnArea> lawns;
  final Map<String, List<String>> lawnPhotos;
  final void Function(String lawnId) onAddPhoto;
  final void Function(String lawnId, String path) onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Add condition photos',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Optional — show the current state of each lawn. You can skip this.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700,
              ),
        ),
        const SizedBox(height: 20),
        ...lawns.map(
          (lawn) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LawnPhotosCard(
              lawn: lawn,
              photos: lawnPhotos[lawn.id] ?? const [],
              onAddPhoto: () => onAddPhoto(lawn.id),
              onRemovePhoto: (path) => onRemovePhoto(lawn.id, path),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _LawnPhotosCard extends StatelessWidget {
  const _LawnPhotosCard({
    required this.lawn,
    required this.photos,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  final LawnArea lawn;
  final List<String> photos;
  final VoidCallback onAddPhoto;
  final void Function(String path) onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Icon(
                    Icons.grass_rounded,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  lawn.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: photos
                    .map((path) => _PhotoThumbnail(
                          path: path,
                          onRemove: () => onRemovePhoto(path),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAddPhoto,
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text('Add photo'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(path),
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.broken_image_rounded,
                color: Colors.grey.shade400,
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
