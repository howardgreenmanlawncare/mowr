import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../domain/lawn_area_model.dart';
import '../../mock/mock_properties.dart';
import '../../providers/booking_draft_provider.dart';
import '../booking_shell.dart';
import 'grass_height_step.dart';

class LawnSelectionStepScreen extends ConsumerStatefulWidget {
  const LawnSelectionStepScreen({super.key});

  static const routePath = '/booking/lawn-selection';

  @override
  ConsumerState<LawnSelectionStepScreen> createState() =>
      _LawnSelectionStepScreenState();
}

class _LawnSelectionStepScreenState
    extends ConsumerState<LawnSelectionStepScreen> {
  @override
  void initState() {
    super.initState();
    // Default to all of this property's lawns selected on first visit.
    // initLawnSelection is a no-op if the user has already made a selection
    // and navigated back, preserving their choices.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final propertyId = ref.read(bookingDraftProvider).propertyId;
      final lawns = mockPropertyById(propertyId).lawnAreas;
      ref.read(bookingDraftProvider.notifier).initLawnSelection(
            lawns.map((l) => l.id).toList(),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final propertyId = ref.watch(
      bookingDraftProvider.select((d) => d.propertyId),
    );
    final lawns = mockPropertyById(propertyId).lawnAreas;
    final selectedIds = ref.watch(
      bookingDraftProvider.select((d) => d.selectedLawnIds),
    );

    return BookingShell(
      stepIndex: kStepLawnSelection,
      stepLabel: 'Your lawns',
      bottomBar: _LawnSelectionBottomBar(
        selectedCount: selectedIds.length,
        totalCount: lawns.length,
        onContinue: selectedIds.isEmpty
            ? null
            : () {
                ref
                    .read(bookingDraftProvider.notifier)
                    .setSelectedLawnIds(selectedIds);
                context.push(GrassHeightStepScreen.routePath);
              },
      ),
      body: _LawnSelectionBody(
        lawns: lawns,
        selectedIds: selectedIds,
        onToggle: (id) =>
            ref.read(bookingDraftProvider.notifier).toggleLawnSelection(id),
      ),
    );
  }
}

class _LawnSelectionBody extends StatelessWidget {
  const _LawnSelectionBody({
    required this.lawns,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<LawnArea> lawns;
  final List<String> selectedIds;
  final void Function(String id) onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Which areas need mowing?',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap to include or exclude a lawn area from this booking.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700,
              ),
        ),
        const SizedBox(height: 20),
        ...lawns.map(
          (lawn) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LawnCard(
              lawn: lawn,
              selected: selectedIds.contains(lawn.id),
              onTap: () => onToggle(lawn.id),
            ),
          ),
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => context.push('/booking/add-lawn-area'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add another lawn area'),
        ),
      ],
    );
  }
}

class _LawnCard extends StatelessWidget {
  const _LawnCard({
    required this.lawn,
    required this.selected,
    required this.onTap,
  });

  final LawnArea lawn;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: selected ? cs.primaryContainer.withValues(alpha: 0.5) : Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: selected ? cs.primary : Colors.grey.shade200,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PhotoArea(photoUrl: lawn.photoUrl, selected: selected),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lawn.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${lawn.areaSqM.toStringAsFixed(0)} m²'
                          '  ·  '
                          '${lawn.perimeter.toStringAsFixed(1)} m perimeter',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: selected
                        ? Icon(
                            Icons.check_circle_rounded,
                            key: const ValueKey(true),
                            color: cs.primary,
                          )
                        : Icon(
                            Icons.radio_button_unchecked_rounded,
                            key: const ValueKey(false),
                            color: Colors.grey.shade400,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoArea extends StatelessWidget {
  const _PhotoArea({required this.photoUrl, required this.selected});

  final String? photoUrl;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (photoUrl != null) {
      return SizedBox(
        height: 110,
        child: Image.network(photoUrl!, fit: BoxFit.cover),
      );
    }

    return Container(
      height: 110,
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.8)
          : cs.primaryContainer.withValues(alpha: 0.4),
      child: Center(
        child: Icon(
          Icons.grass_rounded,
          size: 40,
          color: cs.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _LawnSelectionBottomBar extends StatelessWidget {
  const _LawnSelectionBottomBar({
    required this.selectedCount,
    required this.totalCount,
    required this.onContinue,
  });

  final int selectedCount;
  final int totalCount;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$selectedCount of $totalCount selected',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
