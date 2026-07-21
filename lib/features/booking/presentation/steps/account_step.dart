import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/data/auth_repository.dart';
import '../../providers/booking_draft_provider.dart';
import '../booking_shell.dart';
import 'payment_step.dart';

/// Guest → account (or sign in), then hand off to the payment step. The booking
/// is NOT saved here — it's only confirmed after the card + hold on the next
/// screen.
class AccountStepScreen extends ConsumerStatefulWidget {
  const AccountStepScreen({super.key});

  static const routePath = '/booking/account';

  @override
  ConsumerState<AccountStepScreen> createState() => _AccountStepScreenState();
}

class _AccountStepScreenState extends ConsumerState<AccountStepScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _signInMode = false;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(bookingDraftProvider);
    _nameController.text = draft.customerName ?? '';
    _emailController.text = draft.customerEmail ?? '';
    _mobileController.text = draft.customerMobile ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validate() {
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Please enter a valid email address.';
    }
    if (_passwordController.text.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    if (!_signInMode) {
      if (_nameController.text.trim().isEmpty) return 'Please enter your name.';
      if (_mobileController.text.trim().length < 7) {
        return 'Please enter your mobile number.';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final mobile = _mobileController.text.trim();
    final auth = ref.read(authRepositoryProvider);

    try {
      if (_signInMode) {
        await auth.signIn(email: email, password: _passwordController.text);
        ref.read(bookingDraftProvider.notifier).setContact(email: email);
      } else {
        await auth.signUp(
          email: email,
          password: _passwordController.text,
          name: name,
          phone: mobile,
        );
        ref
            .read(bookingDraftProvider.notifier)
            .setContact(name: name, email: email, mobile: mobile);
      }

      if (!mounted) return;
      context.push(PaymentStepScreen.routePath);
    } catch (e) {
      if (!mounted) return;
      final message = e is AuthFailure ? e.message : 'Something went wrong.';
      final emailTaken = message.toLowerCase().contains('already');
      setState(() {
        _loading = false;
        if (emailTaken && !_signInMode) {
          _signInMode = true;
          _error =
              'That email already has an account — enter your password to sign '
              'in.';
        } else {
          _error = message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BookingShell(
      stepIndex: kStepReview,
      stepLabel: _signInMode ? 'Sign in' : 'Create your account',
      bottomBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.arrow_forward_rounded),
            label: Text(_loading
                ? 'Please wait…'
                : (_signInMode
                    ? 'Sign in & continue'
                    : 'Create account & continue')),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _signInMode ? 'Welcome back' : 'Almost there',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
          ),
          const SizedBox(height: 4),
          Text(
            _signInMode
                ? 'Sign in to confirm your booking.'
                : 'Create your account to confirm the booking — next you’ll add '
                    'a card to secure it.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 20),
          if (!_signInMode) ...[
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          if (!_signInMode) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _signInMode ? 'Password' : 'Create a password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (!_signInMode && _passwordController.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            _PasswordStrengthBar(password: _passwordController.text),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                        _signInMode = !_signInMode;
                        _error = null;
                      }),
              child: Text(_signInMode
                  ? 'Need an account? Create one'
                  : 'Already have an account? Sign in'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple password strength meter: 4 segments + a label.
class _PasswordStrengthBar extends StatelessWidget {
  const _PasswordStrengthBar({required this.password});

  final String password;

  int get _score {
    var score = 0;
    if (password.length >= 6) score++;
    if (password.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    return score.clamp(0, 4);
  }

  @override
  Widget build(BuildContext context) {
    final score = _score;
    final (label, color) = switch (score) {
      <= 1 => ('Weak', Colors.red.shade400),
      2 => ('Fair', Colors.orange.shade600),
      3 => ('Good', Colors.lightGreen.shade700),
      _ => ('Strong', Colors.green.shade600),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) {
            final filled = i < score;
            return Expanded(
              child: Container(
                height: 6,
                margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                decoration: BoxDecoration(
                  color: filled ? color : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Text('Password strength: $label',
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
