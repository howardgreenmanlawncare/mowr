import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/ui.dart';
import '../../booking/data/booking_repository.dart';
import '../../booking/domain/customer_booking.dart';
import '../../booking/presentation/booking_status_screen.dart';
import '../../booking/presentation/customer_nav_bar.dart';
import '../../booking/presentation/my_bookings_screen.dart'
    show formatMoney, bookingWhenLabel;
import '../../booking/presentation/steps/account_step.dart';
import '../data/payment_repository.dart';

/// Billing & payments: the card MOWR charges after a mow, plus the customer's
/// billing history (each completed mow, tappable through to its price
/// breakdown, which serves as the receipt).
class PaymentMethodsScreen extends ConsumerStatefulWidget {
  const PaymentMethodsScreen({super.key});

  static const routePath = '/payment-methods';

  @override
  ConsumerState<PaymentMethodsScreen> createState() =>
      _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends ConsumerState<PaymentMethodsScreen> {
  bool _busy = false;
  bool _loading = true;
  bool _signedOut = false;
  List<CustomerBooking> _history = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(bookingRepositoryProvider);
      if (!repo.isSignedIn) {
        if (!mounted) return;
        setState(() {
          _signedOut = true;
          _loading = false;
        });
        return;
      }
      final all = await repo.myBookings();
      if (!mounted) return;
      setState(() {
        _signedOut = false;
        // Anything money has actually been taken for — the billing record.
        _history = all
            .where((b) => b.capturedAmount != null || b.status == 'completed')
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addCard() async {
    setState(() => _busy = true);
    try {
      final saved = await ref.read(paymentRepositoryProvider).addCard();
      if (saved) _snack('Card saved.');
    } catch (_) {
      _snack('Sorry, we couldn’t save that card. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Billing')),
      bottomNavigationBar: const CustomerNavBar(current: CustomerTab.payment),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_signedOut) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const Icon(Icons.lock_outline_rounded,
              size: 48, color: AppColors.green),
          const SizedBox(height: 16),
          Text('Sign in to manage billing',
              textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Your card and billing history are tied to your account.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton(
              onPressed: () => context.push(
                  '${AccountStepScreen.routePath}?next=${PaymentMethodsScreen.routePath}'),
              child: const Text('Sign in'),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const Eyebrow('Payment method'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.neutralFill,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Icon(Icons.credit_card_rounded,
                      color: AppColors.textPrimary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Card on file', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Charged securely by Stripe once a mow is completed — '
                        'MOWR never sees your card number.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy ? null : _addCard,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_rounded),
          label: Text(_busy ? 'Opening…' : 'Add a card'),
        ),
        const Hairline(),
        const Eyebrow('Billing history'),
        const SizedBox(height: 4),
        if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No payments yet. Charges appear here once a mow is completed.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          )
        else
          for (var i = 0; i < _history.length; i++)
            _BillingRow(booking: _history[i], topBorder: i > 0),
      ],
    );
  }
}

class _BillingRow extends StatelessWidget {
  const _BillingRow({required this.booking, required this.topBorder});
  final CustomerBooking booking;
  final bool topBorder;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final amount = booking.capturedAmount ?? booking.totalAmount;
    final paid = booking.capturedAmount != null;
    return InkWell(
      onTap: () =>
          context.push('${BookingStatusScreen.routeBase}/${booking.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: topBorder
            ? const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)))
            : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.addressLine.isEmpty
                        ? 'Your property'
                        : booking.addressLine,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(bookingWhenLabel(booking), style: text.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMoney(amount, booking.currency),
                  style: text.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                const SizedBox(height: 4),
                StatusPill(paid ? 'Paid' : 'Due',
                    tone: paid ? PillTone.soft : PillTone.neutral),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
