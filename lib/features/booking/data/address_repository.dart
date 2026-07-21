import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';

/// A single selectable address for a postcode. Carries its own coordinates
/// when the provider supplies them (Ideal Postcodes does, per address).
class AddressSuggestion {
  const AddressSuggestion({
    required this.line1,
    required this.city,
    required this.postcode,
    this.lat,
    this.lng,
  });

  final String line1;
  final String city;
  final String postcode;
  final double? lat;
  final double? lng;

  String get displayLine =>
      [line1, city].where((s) => s.trim().isNotEmpty).join(', ');
}

/// Result of a postcode lookup: the (normalised) postcode, its centroid
/// coordinates (free, from postcodes.io) used as a fallback map seed, the
/// selectable addresses, and whether those addresses are real or sample.
class PostcodeLookupResult {
  const PostcodeLookupResult({
    required this.postcode,
    required this.addresses,
    required this.usingRealAddressData,
    this.centroidLat,
    this.centroidLng,
  });

  final String postcode;
  final List<AddressSuggestion> addresses;
  final bool usingRealAddressData;
  final double? centroidLat;
  final double? centroidLng;
}

class PostcodeNotFoundException implements Exception {
  const PostcodeNotFoundException(this.postcode);
  final String postcode;

  @override
  String toString() =>
      postcode.isEmpty ? 'Enter a postcode' : 'Postcode "$postcode" not found';
}

/// Looks up UK addresses from a postcode.
///
/// Data sources, layered so the flow works with or without a paid key:
///   1. postcodes.io (free, no key) — validates the postcode and returns its
///      centroid lat/lng, used as a fallback map seed.
///   2. Ideal Postcodes (needs [AppConfig.idealPostcodesKey]) — the house-level
///      address list, each with its own precise lat/lng.
///   3. When no key is configured, a small sample list so the UI is demoable.
class AddressRepository {
  AddressRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<PostcodeLookupResult> lookup(String rawPostcode) async {
    final postcode = rawPostcode.trim().toUpperCase();
    if (postcode.isEmpty) {
      throw const PostcodeNotFoundException('');
    }

    double? lat;
    double? lng;
    var normalised = postcode;

    // 1. Free centroid + validation via postcodes.io.
    try {
      final res = await _client
          .get(
            Uri.parse(
              'https://api.postcodes.io/postcodes/${Uri.encodeComponent(postcode)}',
            ),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final result = body['result'] as Map<String, dynamic>?;
        if (result != null) {
          lat = (result['latitude'] as num?)?.toDouble();
          lng = (result['longitude'] as num?)?.toDouble();
          normalised = (result['postcode'] as String?) ?? postcode;
        }
      } else if (res.statusCode == 404) {
        throw PostcodeNotFoundException(postcode);
      }
    } on PostcodeNotFoundException {
      rethrow;
    } catch (_) {
      // Network/parse issue — continue; the sample fallback keeps the flow
      // usable offline.
    }

    // 2. Real house-level addresses (with per-address coords) via Ideal Postcodes.
    if (AppConfig.hasAddressApi) {
      final addresses = await _fetchIdealPostcodes(normalised);
      return PostcodeLookupResult(
        postcode: normalised,
        addresses: addresses,
        usingRealAddressData: true,
        centroidLat: lat,
        centroidLng: lng,
      );
    }

    // 3. Sample fallback (no key) — clearly flagged in the UI.
    return PostcodeLookupResult(
      postcode: normalised,
      addresses: _sampleAddresses(normalised, lat, lng),
      usingRealAddressData: false,
      centroidLat: lat,
      centroidLng: lng,
    );
  }

  Future<List<AddressSuggestion>> _fetchIdealPostcodes(String postcode) async {
    final uri = Uri.parse(
      'https://api.ideal-postcodes.co.uk/v1/postcodes/'
      '${Uri.encodeComponent(postcode)}'
      '?api_key=${Uri.encodeComponent(AppConfig.idealPostcodesKey)}',
    );
    final res = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode == 404) {
      throw PostcodeNotFoundException(postcode);
    }
    if (res.statusCode != 200) {
      throw PostcodeNotFoundException(postcode);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (body['result'] as List<dynamic>? ?? const []);
    return list.map((entry) {
      final m = entry as Map<String, dynamic>;
      final line1 = (m['line_1'] as String?)?.trim() ?? '';
      final line2 = (m['line_2'] as String?)?.trim() ?? '';
      final town = (m['post_town'] as String?)?.trim() ?? '';
      final composed = [line1, line2].where((s) => s.isNotEmpty).join(', ');
      return AddressSuggestion(
        line1: composed.isEmpty ? postcode : composed,
        city: town,
        postcode: (m['postcode'] as String?)?.trim() ?? postcode,
        lat: (m['latitude'] as num?)?.toDouble(),
        lng: (m['longitude'] as num?)?.toDouble(),
      );
    }).toList();
  }

  List<AddressSuggestion> _sampleAddresses(
      String postcode, double? lat, double? lng) {
    return [
      for (final n in [1, 2, 3, 5, 8, 12])
        AddressSuggestion(
          line1: '$n Sample Street',
          city: 'Your Town',
          postcode: postcode,
          lat: lat,
          lng: lng,
        ),
    ];
  }
}

final addressRepositoryProvider =
    Provider<AddressRepository>((ref) => AddressRepository());
