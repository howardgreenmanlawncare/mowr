import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/lawn_area_model.dart';
import '../../domain/pricing.dart';
import '../../mock/mock_properties.dart';
import '../../providers/booking_draft_provider.dart';
import '../../providers/pricing_provider.dart';
import '../booking_shell.dart';
import 'schedule_step.dart';

class ServiceStepScreen extends ConsumerWidget {
  const ServiceStepScreen({super.key});

  static const routePath = '/booking/service';

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
                ?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
          ),
          const SizedBox(height: 4),
          Text(
            'Edging trims a crisp line around a lawn where it meets paths, beds '
            'or fences. Add it to any lawns you like.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: Colors.grey.shade700),
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
  });

  final LawnArea lawn;
  final bool edged;
  final VoidCallback onToggleEdging;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: edged ? cs.primary : Colors.grey.shade200,
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
                    '${lawn.perimeter.toStringAsFixed(1)} m of edge',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch(value: edged, onChanged: (_) => onToggleEdging()),
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
        borderRadius: BorderRadius.circular(20),
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
      fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
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
                        fontSize: 12, color: Colors.grey.shade600)),
                Text(amount,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900)),
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
