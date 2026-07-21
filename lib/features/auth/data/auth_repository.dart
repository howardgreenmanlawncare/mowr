import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A user-friendly auth error surfaced to the UI.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Email/password auth via Supabase. The `profiles` row (with role + name +
/// phone) is created automatically by the `handle_new_user` trigger.
class AuthRepository {
  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  Stream<AuthState> authStateChanges() => _client.auth.onAuthStateChange;

  Future<void> signUp({
    required String email,
    required String password,
    String? name,
    String? phone,
  }) async {
    try {
      final res = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          if (name != null && name.isNotEmpty) 'full_name': name,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
      );
      // With email confirmation OFF we get a session immediately. If it's ON,
      // there's no session yet — the booking (which needs auth) can't proceed.
      if (res.session == null) {
        throw const AuthFailure(
          'Account created — please confirm your email, then sign in. '
          '(Tip: turn off "Confirm email" in Supabase for now.)',
        );
      }
    } on AuthException catch (e) {
      throw AuthFailure(_friendly(e.message));
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw AuthFailure(_friendly(e.message));
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  String _friendly(String message) {
    final m = message.toLowerCase();
    if (m.contains('already registered') || m.contains('already been')) {
      return 'That email already has an account — try signing in instead.';
    }
    if (m.contains('password')) {
      return 'Your password needs to be at least 6 characters.';
    }
    if (m.contains('invalid login')) {
      return 'Email or password is incorrect.';
    }
    return message;
  }
}

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository());
