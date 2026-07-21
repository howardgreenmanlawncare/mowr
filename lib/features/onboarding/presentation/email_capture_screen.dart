import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../booking/presentation/steps/postcode_step.dart';
import '../../booking/providers/booking_draft_provider.dart';

/// Early, low-friction lead capture: grab the email (framed as "save your
/// quote") before the customer builds their booking, so they can be reminded
/// with a link back if they don't finish. Sending that reminder is a Phase-2
/// backend job; here we just capture the address.
class EmailCaptureScreen extends ConsumerStatefulWidget {
  const EmailCaptureScreen({super.key});

  static const routePath = '/get-started';

  @override
  ConsumerState<EmailCaptureScreen> createState() =>
      _EmailCaptureScreenState();
}

class _EmailCaptureScreenState extends ConsumerState<EmailCaptureScreen> {
  final _controller = TextEditingController();
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    _controller.text =
        ref.read(bookingDraftProvider).customerEmail ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid {
    final v = _controller.text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
  }

  void _continue() {
    if (!_valid) {
      setState(() => _showError = true);
      return;
    }
    ref
        .read(bookingDraftProvider.notifier)
        .setContact(email: _controller.text.trim());
    context.push(PostcodeStepScreen.routePath);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.mark_email_read_rounded,
                    color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 20),
              Text(
                'Let’s get your price',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
              ),
              const SizedBox(height: 8),
              Text(
                'Pop in your email and we’ll save your quote — so you can pick '
                'up where you left off, and we can send you a reminder with a '
                'link if you don’t finish.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.go,
                autofocus: true,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                onChanged: (_) {
                  if (_showError) setState(() => _showError = false);
                },
                onSubmitted: (_) => _continue(),
                decoration: InputDecoration(
                  labelText: 'Email address',
                  hintText: 'you@example.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  errorText:
                      _showError ? 'Enter a valid email address' : null,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _continue,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Continue to my price'),
              ),
              const SizedBox(height: 12),
              Text(
                'We’ll only use this to send you your quote and booking '
                'updates.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
