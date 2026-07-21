import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/payment_repository.dart';

/// Add / manage saved cards. For now it's an "add a card" entry point using
/// Stripe's secure sheet; listing saved cards comes next.
class PaymentMethodsScreen extends ConsumerStatefulWidget {
  const PaymentMethodsScreen({super.key});

  static const routePath = '/payment-methods';

  @override
  ConsumerState<PaymentMethodsScreen> createState() =>
      _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends ConsumerState<PaymentMethodsScreen> {
  bool _busy = false;

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.credit_card_rounded,
                    color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 20),
              Text(
                'Your payment card',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Add a card so we can charge you once your mow is completed. '
                'Your details are handled securely by Stripe — MOWR never sees '
                'your card number.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _busy ? null : _addCard,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_card_rounded),
                label: Text(_busy ? 'Opening…' : 'Add a card'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
