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

/// The lookup provider itself failed — bad key, no balance, outage. Distinct
/// from [PostcodeNotFoundException], which means the postcode is genuinely
/// unknown and is the customer's problem to fix.
class AddressLookupException implements Exception {
  const AddressLookupException(this.message);
  final String message;

  @override
  String toString() => message;
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
/// **Ideal Postcodes is the source of truth for both addresses and
/// coordinates** (owner decision, 2026-07-23). When
/// [AppConfig.idealPostcodesKey] is set it does everything: validates the
/// postcode, returns the house-level address list, and supplies the lat/lng —
/// per address, plus the centroid that seeds the confirm-location map.
///
/// postcodes.io is used *only* on the keyless path, so the flow stays demoable
/// without a paid key. It is not consulted when a key is configured.
class AddressRepository {
  AddressRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<PostcodeLookupResult> lookup(String rawPostcode) async {
    final postcode = rawPostcode.trim().toUpperCase();
    if (postcode.isEmpty) {
      throw const PostcodeNotFoundException('');
    }

    // Real path: Ideal Postcodes answers everything — validation, addresses,
    // and coordinates. No postcodes.io call is made.
    if (AppConfig.hasAddressApi) {
      final addresses = await _fetchIdealPostcodes(postcode);
      final centroid = _centroidOf(addresses);
      return PostcodeLookupResult(
        postcode: addresses.isNotEmpty ? addresses.first.postcode : postcode,
        addresses: addresses,
        usingRealAddressData: true,
        centroidLat: centroid?.$1,
        centroidLng: centroid?.$2,
      );
    }

    // Keyless demo path only, from here down.
    double? lat;
    double? lng;
    var normalised = postcode;

    // Free centroid + validation via postcodes.io.
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

    // Sample fallback (no key) — clearly flagged in the UI.
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

    // 404 is the only status that genuinely means "no such postcode". Auth,
    // quota and server errors must not masquerade as that, or a key problem
    // sends you hunting a postcode that was fine all along.
    if (res.statusCode == 404) {
      throw PostcodeNotFoundException(postcode);
    }
    if (res.statusCode == 401 || res.statusCode == 402 || res.statusCode == 403) {
      throw const AddressLookupException(
        'Address lookup rejected the API key (check IDEAL_POSTCODES_API_KEY '
        'and the account balance).',
      );
    }
    if (res.statusCode != 200) {
      throw AddressLookupException(
        'Address lookup failed (HTTP ${res.statusCode}).',
      );
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

  /// Mean of the addresses' own coordinates — the postcode centroid, used to
  /// seed the confirm-location map before the customer picks a specific house.
  /// Null when no address carried coordinates.
  (double, double)? _centroidOf(List<AddressSuggestion> addresses) {
    var sumLat = 0.0;
    var sumLng = 0.0;
    var count = 0;
    for (final a in addresses) {
      if (a.lat != null && a.lng != null) {
        sumLat += a.lat!;
        sumLng += a.lng!;
        count++;
      }
    }
    return count == 0 ? null : (sumLat / count, sumLng / count);
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
