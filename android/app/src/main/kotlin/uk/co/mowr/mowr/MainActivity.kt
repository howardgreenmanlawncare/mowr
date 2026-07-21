package uk.co.mowr.mowr

import io.flutter.embedding.android.FlutterFragmentActivity

// flutter_stripe requires FlutterFragmentActivity (not FlutterActivity) so the
// Stripe payment sheet can present its own fragments.
class MainActivity : FlutterFragmentActivity()
