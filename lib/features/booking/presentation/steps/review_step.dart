import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/ui.dart';
import '../../domain/booking_draft.dart';
import '../../domain/discount.dart';
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
    // This booking is occurrence 1 of the series; any discount that targets a
    // later occurrence shows as an incentive below rather than a price cut now.
    final quote = engine.quote(
      lawns: lawns,
      heights: draft.lawnGrassHeights,
      edgedLawnIds: draft.edgedLawnIds,
      discount: DiscountContext(
        isRecurring: draft.recurrence.isRecurring,
        occurrence: 1,
      ),
    );
    final incentive = draft.recurrence.isRecurring
        ? recurringIncentive(ref.watch(discountRulesProvider))
        : null;

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
          if (address.isNotEmpty) ...[
            const Eyebrow('Property'),
            const SizedBox(height: 6),
            Text(address, style: theme.textTheme.titleMedium),
            const Hairline(),
          ],
          const Eyebrow('Lawns & service'),
          const SizedBox(height: 4),
          _PriceSection(
            title: 'Lawn mowing',
            price: quote.money(quote.mowingSubtotal),
            lines: quote.mowLines,
          ),
          if (quote.hasEdging)
            _PriceSection(
              title: 'Lawn edging',
              price: quote.money(quote.edgingSubtotal),
              lines: quote.edgeLines,
              topBorder: true,
            ),
          const Hairline(),
          _RecurrenceRow(recurrence: draft.recurrence),
          if (quote.hasDiscount) ...[
            const SizedBox(height: 8),
            _DiscountRow(quote: quote),
          ],
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(draft.recurrence.isRecurring
                        ? draft.recurrence.label
                        : 'Total'),
                    const SizedBox(height: 8),
                    Text(
                      quote.money(quote.total),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (incentive != null)
                const StatusPill('3rd mow reward', tone: PillTone.soft),
            ],
          ),
          if (incentive != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.greenPale,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'Recurring reward: ${incentive.summary}. It applies '
                'automatically to that mow.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.greenDark),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Prices are based on the grass heights you set. Payment is taken '
            'only after your mow is completed.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RecurrenceRow extends StatelessWidget {
  const _RecurrenceRow({required this.recurrence});
  final RecurrenceInterval recurrence;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        const Icon(Icons.repeat_rounded, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          recurrence.isRecurring
              ? 'Repeats · ${recurrence.label}'
              : 'One-off mow',
          style: text.bodySmall,
        ),
      ],
    );
  }
}

class _DiscountRow extends StatelessWidget {
  const _DiscountRow({required this.quote});
  final BookingQuote quote;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: AppColors.green,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()]);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '${quote.discountLabel ?? 'Discount'} '
          '(−${quote.discountPercent.toStringAsFixed(0)}%)',
          style: style,
        ),
        Text('−${quote.money(quote.discountAmount)}', style: style),
      ],
    );
  }
}

class _PriceSection extends StatelessWidget {
  const _PriceSection({
    required this.title,
    required this.price,
    required this.lines,
    this.topBorder = false,
  });

  final String title;
  final String price;
  final List<PriceLine> lines;
  final bool topBorder;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: topBorder
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: text.titleMedium),
              Text(price,
                  style: text.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 6),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('${line.name}  ·  ${line.detail}',
                  style: text.bodySmall),
            ),
          ),
        ],
      ),
    );
  }
}
