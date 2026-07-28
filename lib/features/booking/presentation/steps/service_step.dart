import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/lawn_area_model.dart';
import '../../domain/pricing.dart';
import '../../mock/mock_properties.dart';
import '../../providers/booking_draft_provider.dart';
import '../../providers/pricing_provider.dart';
import '../booking_shell.dart';
import '../lawn_map_view.dart';
import 'schedule_step.dart';

class ServiceStepScreen extends ConsumerWidget {
  const ServiceStepScreen({super.key});

  static const routePath = '/booking/service';

  /// Lets the customer supply an edge length for a lawn that was entered
  /// without one, so it can be edged. Only draft (guest-entered) lawns can be
  /// updated; a drawn lawn always already has a perimeter.
  Future<void> _addPerimeter(
    BuildContext context,
    WidgetRef ref,
    LawnArea lawn,
  ) async {
    final entered = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _PerimeterSheet(lawnName: lawn.name),
      ),
    );
    if (entered == null || entered <= 0) return;
    ref
        .read(bookingDraftProvider.notifier)
        .updateDraftLawn(lawn.copyWith(perimeter: entered));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final draft = ref.watch(bookingDraftProvider);
    final engine = ref.watch(pricingEngineProvider);

    final lawns = resolveBookingLawns(draft)
        .where((l) => draft.selectedLawnIds.contains(l.id))
        .toList();
    final quote = engine.quote(
      lawns: lawns,
      heights: draft.lawnGrassHeights,
      edgedLawnIds: draft.edgedLawnIds,
    );

    return BookingShell(
      stepIndex: kStepService,
      stepLabel: 'Edging',
      bottomBar: _PriceBottomBar(
        label: 'Total so far',
        amount: quote.money(quote.total),
        onContinue: () => context.push(ScheduleStepScreen.routePath),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add lawn edging?',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
          ),
          const SizedBox(height: 4),
          Text(
            'Edging trims a crisp line around a lawn where it meets paths, beds '
            'or fences. Add it to any lawns you like.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          ...lawns.map((lawn) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _LawnEdgingCard(
                lawn: lawn,
                edged: draft.edgedLawnIds.contains(lawn.id),
                onToggleEdging: () => ref
                    .read(bookingDraftProvider.notifier)
                    .toggleEdging(lawn.id),
                onAddPerimeter: () => _addPerimeter(context, ref, lawn),
              ),
            );
          }),
          const SizedBox(height: 8),
          _SummaryCard(quote: quote),
        ],
      ),
    );
  }
}

class _LawnEdgingCard extends StatelessWidget {
  const _LawnEdgingCard({
    required this.lawn,
    required this.edged,
    required this.onToggleEdging,
    required this.onAddPerimeter,
  });

  final LawnArea lawn;
  final bool edged;
  final VoidCallback onToggleEdging;
  final VoidCallback onAddPerimeter;

  /// Edging is priced per metre of edge, so a lawn with no perimeter can't be
  /// edged until one is supplied. Drawn lawns always have one.
  bool get _hasPerimeter => lawn.perimeter > 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canMap = LawnMapView.canShow(lawn);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: edged ? cs.primary : AppColors.border,
          width: edged ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.content_cut_rounded, size: 20, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lawn.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    _hasPerimeter
                        ? '${lawn.perimeter.toStringAsFixed(1)} m of edge'
                        : 'No edge length yet',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (canMap)
              IconButton(
                onPressed: () => LawnMapView.open(context, lawn),
                icon: const Icon(Icons.map_outlined),
                tooltip: 'View on map',
              ),
            // Only offer the edging toggle once we know the edge length;
            // otherwise prompt to add it, so we never charge edging for 0 m.
            if (_hasPerimeter)
              Switch(value: edged, onChanged: (_) => onToggleEdging())
            else
              TextButton(
                onPressed: onAddPerimeter,
                child: const Text('Add edge'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet to enter a lawn's edge length (perimeter) on the edging step.
class _PerimeterSheet extends StatefulWidget {
  const _PerimeterSheet({required this.lawnName});

  final String lawnName;

  @override
  State<_PerimeterSheet> createState() => _PerimeterSheetState();
}

class _PerimeterSheetState extends State<_PerimeterSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = double.tryParse(_controller.text.trim()) ?? 0;
    final valid = value > 0;
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
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Edge length — ${widget.lawnName}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Total length around the lawn where you want a crisp edge trimmed.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Edge length',
                suffixText: 'm',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: valid ? () => Navigator.pop(context, value) : null,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save edge length'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.quote});

  final BookingQuote quote;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _row(context, 'Mowing', quote.money(quote.mowingSubtotal)),
          if (quote.hasEdging) ...[
            const SizedBox(height: 6),
            _row(context, 'Edging', quote.money(quote.edgingSubtotal)),
          ],
          const Divider(height: 20),
          _row(context, 'Total', quote.money(quote.total), bold: true),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 17 : 14,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }
}

class _PriceBottomBar extends StatelessWidget {
  const _PriceBottomBar({
    required this.label,
    required this.amount,
    required this.onContinue,
  });

  final String label;
  final String amount;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text(amount,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
