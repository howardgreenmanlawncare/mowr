import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/lawn_area_model.dart';
import '../../providers/booking_draft_provider.dart';
import '../booking_shell.dart';
import 'grass_height_step.dart';
import 'lawn_draw_screen.dart';

/// Lawn "hub": lists the lawns added so far and offers two ways to add another
/// (draw on a full-screen map, or enter the size manually). Continue is enabled
/// once at least one lawn exists.
class LawnStepScreen extends ConsumerWidget {
  const LawnStepScreen({super.key});

  static const routePath = '/booking/lawn';

  void _openManualSheet(BuildContext context, WidgetRef ref) {
    final count = ref.read(bookingDraftProvider).draftLawns.length;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ManualLawnSheet(
          defaultName: 'Lawn ${count + 1}',
          onSave: (name, area, perimeter) {
            ref.read(bookingDraftProvider.notifier).addDraftLawn(
                  LawnArea(
                    id: 'draft-lawn-${DateTime.now().microsecondsSinceEpoch}',
                    name: name,
                    areaSqM: area,
                    perimeter: perimeter,
                    source: LawnMeasurementSource.manual,
                  ),
                );
            Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lawns = ref.watch(bookingDraftProvider.select((d) => d.draftLawns));

    return BookingShell(
      stepIndex: kStepLawn,
      stepLabel: 'Lawn areas',
      bottomBar: _HubBottomBar(
        lawnCount: lawns.length,
        onContinue: lawns.isEmpty
            ? null
            : () => context.push(GrassHeightStepScreen.routePath),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your lawns',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
          ),
          const SizedBox(height: 4),
          Text(
            lawns.isEmpty
                ? 'Add each lawn you want mowed. Draw it on the map for an exact '
                    'measurement, or enter the size yourself.'
                : 'Add more lawns, or continue when you have them all.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 20),
          if (lawns.isEmpty)
            const _EmptyState()
          else
            ...lawns.map(
              (lawn) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SavedLawnCard(
                  lawn: lawn,
                  onRemove: () => ref
                      .read(bookingDraftProvider.notifier)
                      .removeDraftLawn(lawn.id),
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => context.push(LawnDrawScreen.routePath),
            icon: const Icon(Icons.draw_rounded),
            label: Text(lawns.isEmpty ? 'Draw a lawn on the map' : 'Draw another lawn'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _openManualSheet(context, ref),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Enter size manually'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: cs.primaryContainer,
            child: Icon(Icons.grass_rounded,
                size: 28, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 12),
          const Text(
            'No lawns added yet',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap “Draw a lawn on the map” to trace your first one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SavedLawnCard extends StatelessWidget {
  const _SavedLawnCard({required this.lawn, required this.onRemove});

  final LawnArea lawn;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: cs.primaryContainer,
              child: Icon(
                lawn.isDrawn ? Icons.map_rounded : Icons.edit_rounded,
                size: 18,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lawn.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${lawn.areaSqM.toStringAsFixed(0)} m²'
                    '  ·  ${lawn.perimeter.toStringAsFixed(1)} m edge'
                    '${lawn.isDrawn ? '' : '  ·  entered'}',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: Icon(Icons.delete_outline_rounded,
                  color: Colors.grey.shade500),
              tooltip: 'Remove',
            ),
          ],
        ),
      ),
    );
  }
}

class _HubBottomBar extends StatelessWidget {
  const _HubBottomBar({required this.lawnCount, required this.onContinue});

  final int lawnCount;
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
              lawnCount == 0
                  ? 'Add at least one lawn to continue'
                  : '$lawnCount lawn${lawnCount == 1 ? '' : 's'} added',
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

// ---------------------------------------------------------------------------

class _ManualLawnSheet extends StatefulWidget {
  const _ManualLawnSheet({required this.defaultName, required this.onSave});

  final String defaultName;
  final void Function(String name, double area, double perimeter) onSave;

  @override
  State<_ManualLawnSheet> createState() => _ManualLawnSheetState();
}

class _ManualLawnSheetState extends State<_ManualLawnSheet> {
  late final TextEditingController _nameController;
  final _areaController = TextEditingController();
  final _perimeterController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.defaultName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _areaController.dispose();
    _perimeterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final areaValid = (double.tryParse(_areaController.text.trim()) ?? 0) > 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter a lawn manually',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Lawn name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _areaController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Area', suffixText: 'm²'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _perimeterController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Perimeter (optional)',
                helperText: 'Total edge length — used to price edging.',
                suffixText: 'm',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: areaValid
                  ? () {
                      final name = _nameController.text.trim().isEmpty
                          ? widget.defaultName
                          : _nameController.text.trim();
                      final area =
                          double.tryParse(_areaController.text.trim()) ?? 0.0;
                      final perimeter =
                          double.tryParse(_perimeterController.text.trim()) ??
                              0.0;
                      widget.onSave(name, area, perimeter);
                    }
                  : null,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Add lawn'),
            ),
          ],
        ),
      ),
    );
  }
}
