import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/pricing.dart';
import '../../mock/mock_properties.dart';
import '../../providers/booking_draft_provider.dart';
import '../../providers/pricing_provider.dart';
import '../booking_shell.dart';
import 'confirmation_step.dart';

class ReviewStepScreen extends ConsumerWidget {
  const ReviewStepScreen({super.key});

  static const routePath = '/booking/review';

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

    final address = [draft.addressLine1, draft.addressCity, draft.postcode]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(', ');

    return BookingShell(
      stepIndex: kStepReview,
      stepLabel: 'Review & price',
      continueLabel: 'Request booking',
      onContinue: () => context.push(ConfirmationStepScreen.routePath),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your order',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.home_rounded,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    address,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          _Section(
            title: 'Lawn mowing',
            turnUpLabel: 'Call-out',
            turnUp: quote.money(quote.mowTurnUp),
            lines: quote.mowLines,
            subtotal: quote.money(quote.mowingSubtotal),
            minimumNote: quote.mowMinimumApplied
                ? 'Minimum charge of ${quote.money(quote.mowMinimum)} applied'
                : null,
            money: quote.money,
          ),
          if (quote.hasEdging) ...[
            const SizedBox(height: 14),
            _Section(
              title: 'Lawn edging',
              turnUpLabel: 'Call-out',
              turnUp: quote.money(quote.edgeTurnUp),
              lines: quote.edgeLines,
              subtotal: quote.money(quote.edgingSubtotal),
              minimumNote: quote.edgeMinimumApplied
                  ? 'Minimum charge of ${quote.money(quote.edgeMinimum)} applied'
                  : null,
              money: quote.money,
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                Text(quote.money(quote.total),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Prices are based on the grass heights you set. Payment is taken '
            'only after your mow is completed.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.turnUpLabel,
    required this.turnUp,
    required this.lines,
    required this.subtotal,
    required this.minimumNote,
    required this.money,
  });

  final String title;
  final String turnUpLabel;
  final String turnUp;
  final List<PriceLine> lines;
  final String subtotal;
  final String? minimumNote;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 10),
            _lineRow(turnUpLabel, null, turnUp),
            ...lines.map(
              (line) => _lineRow(line.name, line.detail, money(line.amount)),
            ),
            if (minimumNote != null) ...[
              const SizedBox(height: 6),
              Text(
                minimumNote!,
                style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 12,
                    fontStyle: FontStyle.italic),
              ),
            ],
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                Text(subtotal,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineRow(String name, String? detail, String amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail,
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
