import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/pricing.dart';
import '../../mock/mock_properties.dart';
import '../../providers/booking_draft_provider.dart';
import '../../providers/pricing_provider.dart';
import '../booking_shell.dart';
import 'account_step.dart';

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
      onContinue: () => context.push(AccountStepScreen.routePath),
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
          _PriceSection(
            title: 'Lawn mowing',
            price: quote.money(quote.mowingSubtotal),
            lines: quote.mowLines,
          ),
          if (quote.hasEdging) ...[
            const SizedBox(height: 12),
            _PriceSection(
              title: 'Lawn edging',
              price: quote.money(quote.edgingSubtotal),
              lines: quote.edgeLines,
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

class _PriceSection extends StatelessWidget {
  const _PriceSection({
    required this.title,
    required this.price,
    required this.lines,
  });

  final String title;
  final String price;
  final List<PriceLine> lines;

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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                Text(price,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(Icons.check_rounded,
                        size: 16, color: Colors.grey.shade500),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${line.name}  ·  ${line.detail}',
                        style: TextStyle(
                            color: Colors.grey.shade700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
