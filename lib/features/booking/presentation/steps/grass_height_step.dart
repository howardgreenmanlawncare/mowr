import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../domain/booking_draft.dart';
import '../../domain/lawn_area_model.dart';
import '../../mock/mock_properties.dart';
import '../../providers/booking_draft_provider.dart';
import '../booking_shell.dart';
import 'lawn_access_step.dart';

class GrassHeightStepScreen extends ConsumerStatefulWidget {
  const GrassHeightStepScreen({super.key});

  static const routePath = '/booking/grass-height';

  @override
  ConsumerState<GrassHeightStepScreen> createState() =>
      _GrassHeightStepScreenState();
}

class _GrassHeightStepScreenState
    extends ConsumerState<GrassHeightStepScreen> {
  @override
  void initState() {
    super.initState();
    // Default every selected lawn to Medium on first visit.
    // initGrassHeights is a no-op for any lawn already set, so back-navigation
    // preserves changes the customer made.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selectedIds = ref.read(bookingDraftProvider).selectedLawnIds;
      ref.read(bookingDraftProvider.notifier).initGrassHeights(selectedIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final propertyId =
        ref.watch(bookingDraftProvider.select((d) => d.propertyId));
    final selectedIds =
        ref.watch(bookingDraftProvider.select((d) => d.selectedLawnIds));
    final grassHeights =
        ref.watch(bookingDraftProvider.select((d) => d.lawnGrassHeights));

    final property = mockPropertyById(propertyId);
    final selectedLawns = property.lawnAreas
        .where((l) => selectedIds.contains(l.id))
        .toList();

    return BookingShell(
      stepIndex: kStepGrassHeight,
      stepLabel: 'Grass height',
      onContinue: () => context.push(LawnAccessStepScreen.routePath),
      body: _GrassHeightBody(
        lawns: selectedLawns,
        grassHeights: grassHeights,
        onChanged: (lawnId, height) => ref
            .read(bookingDraftProvider.notifier)
            .setLawnGrassHeight(lawnId, height),
      ),
    );
  }
}

class _GrassHeightBody extends StatelessWidget {
  const _GrassHeightBody({
    required this.lawns,
    required this.grassHeights,
    required this.onChanged,
  });

  final List<LawnArea> lawns;
  final Map<String, GrassLength> grassHeights;
  final void Function(String lawnId, GrassLength height) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How long is the grass?',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          "Each lawn is preset to Medium — adjust any that differ.",
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700,
              ),
        ),
        const SizedBox(height: 16),
        const _ExampleImagesCard(),
        const SizedBox(height: 20),
        ...lawns.map(
          (lawn) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LawnHeightCard(
              lawn: lawn,
              height: grassHeights[lawn.id] ?? GrassLength.medium,
              onChanged: (h) => onChanged(lawn.id, h),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExampleImagesCard extends StatelessWidget {
  const _ExampleImagesCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ExpansionTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        collapsedShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        leading: Icon(Icons.photo_library_outlined, color: cs.primary),
        title: const Text(
          'See height examples',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                _ExampleTile(
                  label: 'Low',
                  color: Colors.green.shade100,
                  iconSize: 24,
                ),
                const SizedBox(width: 8),
                _ExampleTile(
                  label: 'Medium',
                  color: Colors.green.shade300,
                  iconSize: 36,
                ),
                const SizedBox(width: 8),
                _ExampleTile(
                  label: 'High',
                  color: Colors.green.shade600,
                  iconSize: 48,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleTile extends StatelessWidget {
  const _ExampleTile({
    required this.label,
    required this.color,
    required this.iconSize,
  });

  final String label;
  final Color color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 72,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(
                Icons.grass_rounded,
                size: iconSize,
                color: Colors.green.shade900,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _LawnHeightCard extends StatelessWidget {
  const _LawnHeightCard({
    required this.lawn,
    required this.height,
    required this.onChanged,
  });

  final LawnArea lawn;
  final GrassLength height;
  final void Function(GrassLength) onChanged;

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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<GrassLength>(
                segments: const [
                  ButtonSegment(
                    value: GrassLength.low,
                    label: Text('Low'),
                  ),
                  ButtonSegment(
                    value: GrassLength.medium,
                    label: Text('Medium'),
                  ),
                  ButtonSegment(
                    value: GrassLength.high,
                    label: Text('High'),
                  ),
                ],
                selected: {height},
                onSelectionChanged: (values) => onChanged(values.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: cs.primaryContainer,
                  selectedForegroundColor: cs.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
