import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/ui.dart';
import '../../admin/presentation/admin_shell.dart';
import '../../booking/presentation/my_bookings_screen.dart';
import '../../mower/presentation/mower_auth_screen.dart';
import '../../mower/presentation/mower_home_screen.dart';
import '../data/auth_repository.dart';

/// One sign-in for everyone. After authenticating we read the account's role
/// and route to the right side of the app: admins to the admin surface, mowers
/// to the mower app, everyone else to their bookings. A mower therefore signs
/// in "as normal" and lands on the mower side automatically.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  static const routePath = '/sign-in';

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'Please enter your password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = ref.read(authRepositoryProvider);
    try {
      await auth.signIn(email: email, password: _password.text);
      final role = await auth.currentRole();
      if (!mounted) return;
      final destination = switch (role) {
        'admin' => AdminShell.routePath,
        'mower' => MowerHomeScreen.routePath,
        _ => MyBookingsScreen.routePath,
      };
      context.go(destination);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is AuthFailure ? e.message : 'Something went wrong.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Eyebrow('Welcome back'),
              const SizedBox(height: 12),
              Text('Sign in', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Customers and mowers sign in here — we’ll take you to the right '
                'place.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscure,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'Signing in…' : 'Sign in'),
              ),
              const Hairline(),
              Center(
                child: TextButton(
                  onPressed: () => context.push(MowerAuthScreen.routePath),
                  child: const Text('New to MOWR? Become a MOWR'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
