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

  /// Null when Supabase hasn't been initialised (e.g. init failed, or a widget
  /// test that renders the app without calling `main()`). Auth-state reads used
  /// during render degrade to "signed out" rather than throwing.
  SupabaseClient? get _clientOrNull {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  User? get currentUser => _clientOrNull?.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  Stream<AuthState> authStateChanges() =>
      _clientOrNull?.auth.onAuthStateChange ?? const Stream.empty();

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

  /// The signed-in user's role from their `profiles` row — 'admin', 'mower', or
  /// 'customer' (null if signed out or unknown). Used to route a single sign-in
  /// to the right side of the app.
  Future<String?> currentRole() async {
    final client = _clientOrNull;
    final id = client?.auth.currentUser?.id;
    if (client == null || id == null) return null;
    final row = await client
        .from('profiles')
        .select('role')
        .eq('id', id)
        .maybeSingle();
    return row?['role'] as String?;
  }

  /// Attaches [phone] to the signed-in account and triggers an SMS one-time
  /// code. Confirm it with [verifyPhone].
  ///
  /// Doubles as the account dedup step: Supabase enforces one confirmed phone
  /// per user, so a second account trying to verify the same number fails here
  /// — surfaced as [AuthFailure] with a "already in use" message. Requires an
  /// SMS provider configured in the Supabase dashboard.
  Future<void> sendPhoneOtp(String phone) async {
    try {
      await _client.auth.updateUser(UserAttributes(phone: phone));
    } on AuthException catch (e) {
      throw AuthFailure(_friendlyPhone(e.message));
    }
  }

  /// Confirms the SMS code for a phone change, marking the number verified.
  Future<void> verifyPhone({required String phone, required String token}) async {
    try {
      await _client.auth.verifyOTP(
        phone: phone,
        token: token,
        type: OtpType.phoneChange,
      );
    } on AuthException catch (e) {
      throw AuthFailure(_friendlyPhone(e.message));
    }
  }

  String _friendlyPhone(String message) {
    final m = message.toLowerCase();
    if (m.contains('already') && m.contains('registered') ||
        m.contains('already in use') ||
        m.contains('duplicate')) {
      return 'That mobile number is already used by another MOWR account.';
    }
    if (m.contains('token') || m.contains('otp') || m.contains('expired') ||
        m.contains('invalid')) {
      return 'That code isn’t right or has expired. Request a new one.';
    }
    if (m.contains('sms') || m.contains('provider') || m.contains('phone')) {
      return 'Text-message verification isn’t set up yet. Contact support.';
    }
    return message;
  }

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

/// Emits on every sign-in / sign-out. Widgets that must react to auth changes
/// (e.g. the customer nav bar, which only shows when signed in) watch this.
///
/// The stream fires the current session immediately on subscribe, so
/// `isSignedInProvider` is correct on first build without a loading flash.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// Whether someone is signed in right now. Defaults to the synchronous value
/// so there is never an "unknown" first frame.
final isSignedInProvider = Provider<bool>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).isSignedIn;
});
