import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../payment/data/payment_repository.dart';
import '../../data/booking_repository.dart';
import '../../domain/lawn_area_model.dart';
import '../../domain/pricing.dart';
import '../../mock/mock_properties.dart';
import '../../providers/booking_draft_provider.dart';
import '../../providers/pricing_provider.dart';
import '../booking_shell.dart';
import 'confirmation_step.dart';

/// Card + payment hold. The booking is only saved (confirmed) after the hold
/// succeeds — nothing is confirmed on an un-paid booking.
class PaymentStepScreen extends ConsumerStatefulWidget {
  const PaymentStepScreen({super.key});

  static const routePath = '/booking/payment';

  @override
  ConsumerState<PaymentStepScreen> createState() => _PaymentStepScreenState();
}

class _PaymentStepScreenState extends ConsumerState<PaymentStepScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _confirmAndPay(
      BookingQuote quote, List<LawnArea> lawns) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final amountPence = (quote.total * 100).round();
      final paymentIntentId = await ref
          .read(paymentRepositoryProvider)
          .authoriseHold(amountPence: amountPence);

      // Cancelled the card sheet — do nothing, stay here.
      if (paymentIntentId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final draft = ref.read(bookingDraftProvider);
      await ref.read(bookingRepositoryProvider).submit(
            draft: draft,
            lawns: lawns,
            quote: quote,
            paymentIntentId: paymentIntentId,
          );

      if (!mounted) return;
      context.push(ConfirmationStepScreen.routePath);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'We couldn’t take payment or confirm the booking. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
      stepIndex: kStepReview,
      stepLabel: 'Payment',
      bottomBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: FilledButton.icon(
            onPressed: _loading ? null : () => _confirmAndPay(quote, lawns),
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.lock_rounded),
            label: Text(_loading
                ? 'Please wait…'
                : 'Add card & hold ${quote.money(quote.total)}'),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Secure your booking',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your card to confirm. We’ll place a hold for the total — you '
            'are only charged once your mow is completed.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Hold on your card',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text(quote.money(quote.total),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Payments are handled securely by Stripe. MOWR never sees '
                  'your card number.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 18, color: cs.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            color: cs.onErrorContainer, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
