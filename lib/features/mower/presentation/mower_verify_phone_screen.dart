import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../data/mower_repository.dart';

/// Confirms the mower's mobile number by SMS one-time code.
///
/// Two purposes: it's a robustness upgrade on sign-up (a real, reachable
/// number), and it's the account dedup anchor — Supabase enforces one confirmed
/// phone per account, so the same number can't be used to spin up a second
/// mower. Government-ID checks (DBS) are a separate, later layer.
class MowerVerifyPhoneScreen extends ConsumerStatefulWidget {
  const MowerVerifyPhoneScreen({super.key});

  static const routePath = '/mower/verify-phone';

  @override
  ConsumerState<MowerVerifyPhoneScreen> createState() =>
      _MowerVerifyPhoneScreenState();
}

enum _Stage { enterPhone, enterCode, done }

class _MowerVerifyPhoneScreenState
    extends ConsumerState<MowerVerifyPhoneScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  _Stage _stage = _Stage.enterPhone;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final acct = await ref.read(mowerRepositoryProvider).mowerAccount();
      if (!mounted) return;
      setState(() {
        if (acct.phoneVerified) _stage = _Stage.done;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// UK numbers arrive as 07…; Supabase wants E.164 (+44…). Leave anything
  /// already in + form alone.
  String _normalise(String raw) {
    var p = raw.trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (p.startsWith('+')) return p;
    if (p.startsWith('0')) return '+44${p.substring(1)}';
    return '+$p';
  }

  Future<void> _sendCode() async {
    final phone = _normalise(_phoneController.text);
    if (phone.length < 8) {
      setState(() => _error = 'Enter a valid mobile number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPhoneOtp(phone);
      if (!mounted) return;
      setState(() => _stage = _Stage.enterCode);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is AuthFailure ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final phone = _normalise(_phoneController.text);
    final token = _codeController.text.trim();
    if (token.length < 4) {
      setState(() => _error = 'Enter the code we texted you.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyPhone(phone: phone, token: token);
      if (!mounted) return;
      setState(() => _stage = _Stage.done);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is AuthFailure ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your mobile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: switch (_stage) {
                _Stage.enterPhone => _phoneStep(),
                _Stage.enterCode => _codeStep(),
                _Stage.done => _doneStep(),
              },
            ),
    );
  }

  Widget _phoneStep() {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What’s your mobile number?', style: text.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'We’ll text you a code to confirm it. Each number can be linked to '
          'one MOWR account.',
          style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Mobile number',
            prefixIcon: Icon(Icons.phone_outlined),
            hintText: '07…',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: cs.error)),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _sendCode,
          icon: _busy ? _spinner() : const Icon(Icons.sms_outlined),
          label: const Text('Text me a code'),
        ),
      ],
    );
  }

  Widget _codeStep() {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Enter the code', style: text.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'We texted a code to ${_normalise(_phoneController.text)}.',
          style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          autofocus: true,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Code',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: TextStyle(color: cs.error)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _verify,
          icon: _busy ? _spinner() : const Icon(Icons.check_rounded),
          label: const Text('Confirm'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _stage = _Stage.enterPhone;
                    _error = null;
                    _codeController.clear();
                  }),
          child: const Text('Change number / resend'),
        ),
      ],
    );
  }

  Widget _doneStep() {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.check_rounded, size: 36, color: cs.primary),
          ),
          const SizedBox(height: 20),
          Text('Mobile verified', style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Thanks — that’s one step closer to taking jobs.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _spinner() => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
}
