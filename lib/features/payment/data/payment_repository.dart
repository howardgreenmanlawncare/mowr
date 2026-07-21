import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Default billing details — pre-selects the UK so customers don't have to pick
/// their country each time.
final _ukBilling = BillingDetails(
  address: Address(
    country: 'GB',
    city: null,
    line1: null,
    line2: null,
    postalCode: null,
    state: null,
  ),
);

/// Handles cards + payment holds via Stripe. Card details are entered inside
/// Stripe's own PaymentSheet and never touch our app or servers; the secret key
/// lives only in the Edge Functions.
class PaymentRepository {
  final _client = Supabase.instance.client;

  /// Add/save a card (no charge). Returns true if saved, false if cancelled.
  Future<bool> addCard() async {
    final data = await _invoke('create-setup-intent');
    if (data['setupIntentClientSecret'] == null) {
      throw Exception(data['error']?.toString() ?? 'Could not start card setup.');
    }
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        merchantDisplayName: 'MOWR',
        customerId: data['customerId'] as String,
        customerEphemeralKeySecret: data['ephemeralKey'] as String,
        setupIntentClientSecret: data['setupIntentClientSecret'] as String,
        billingDetails: _ukBilling,
      ),
    );
    return _present();
  }

  /// Authorises (holds) [amountPence] on the card and saves the card. Returns
  /// the PaymentIntent id on success, or null if the customer cancelled. The
  /// money is captured later, when the mow is completed.
  Future<String?> authoriseHold({
    required int amountPence,
    String currency = 'gbp',
  }) async {
    final data = await _invoke(
      'create-payment-intent',
      body: {'amount': amountPence, 'currency': currency},
    );
    if (data['paymentIntentClientSecret'] == null) {
      throw Exception(data['error']?.toString() ?? 'Could not start payment.');
    }
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        merchantDisplayName: 'MOWR',
        customerId: data['customerId'] as String,
        customerEphemeralKeySecret: data['ephemeralKey'] as String,
        paymentIntentClientSecret: data['paymentIntentClientSecret'] as String,
        billingDetails: _ukBilling,
      ),
    );
    final ok = await _present();
    return ok ? data['paymentIntentId'] as String : null;
  }

  Future<Map<String, dynamic>> _invoke(String fn,
      {Map<String, dynamic>? body}) async {
    final res = await _client.functions.invoke(fn, body: body);
    final data = res.data;
    if (data is! Map) throw Exception('Unexpected response from $fn.');
    return Map<String, dynamic>.from(data);
  }

  /// Presents the sheet. Returns true on success, false if cancelled.
  Future<bool> _present() async {
    try {
      await Stripe.instance.presentPaymentSheet();
      return true;
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return false;
      rethrow;
    }
  }
}

final paymentRepositoryProvider =
    Provider<PaymentRepository>((ref) => PaymentRepository());
