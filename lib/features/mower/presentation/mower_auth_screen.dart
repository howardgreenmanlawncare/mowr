import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../data/mower_repository.dart';
import 'mower_home_screen.dart';

/// Mower sign up / sign in. New mowers are created with the `mower` role and
/// start pending approval.
class MowerAuthScreen extends ConsumerStatefulWidget {
  const MowerAuthScreen({super.key});

  static const routePath = '/mower';

  @override
  ConsumerState<MowerAuthScreen> createState() => _MowerAuthScreenState();
}

class _MowerAuthScreenState extends ConsumerState<MowerAuthScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _signInMode = false;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

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

    final email = _emailController.text.trim();
    final auth = ref.read(authRepositoryProvider);
    final mower = ref.read(mowerRepositoryProvider);

    try {
      if (_signInMode) {
        await auth.signIn(email: email, password: _passwordController.text);
      } else {
        await auth.signUp(
          email: email,
          password: _passwordController.text,
          name: _nameController.text.trim(),
          phone: _mobileController.text.trim(),
        );
        await mower.registerAsMower();
      }
      if (!mounted) return;
      context.go(MowerHomeScreen.routePath);
    } catch (e) {
      if (!mounted) return;
      final message = e is AuthFailure ? e.message : 'Something went wrong.';
      final emailTaken = message.toLowerCase().contains('already');
      setState(() {
        _loading = false;
        if (emailTaken && !_signInMode) {
          _signInMode = true;
          _error = 'That email already has an account — sign in instead.';
        } else {
          _error = message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Mowers')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.agriculture_rounded,
                    color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 20),
              Text(
                _signInMode ? 'Mower sign in' : 'Become a MOWR',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                _signInMode
                    ? 'Sign in to see and accept jobs near you.'
                    : 'Sign up to pick up lawn-mowing jobs near you. New '
                        'mowers are checked before their first job.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 20),
              if (!_signInMode) ...[
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
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
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!,
                    style: TextStyle(color: cs.error, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
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
                    : (_signInMode ? 'Sign in' : 'Create mower account')),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                            _signInMode = !_signInMode;
                            _error = null;
                          }),
                  child: Text(_signInMode
                      ? 'New here? Create a mower account'
                      : 'Already a mower? Sign in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
