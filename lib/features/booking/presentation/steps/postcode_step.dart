import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/address_repository.dart';
import '../../providers/booking_draft_provider.dart';
import '../booking_shell.dart';
import 'address_step.dart';

class PostcodeStepScreen extends ConsumerStatefulWidget {
  const PostcodeStepScreen({super.key});

  static const routePath = '/booking/postcode';

  @override
  ConsumerState<PostcodeStepScreen> createState() => _PostcodeStepScreenState();
}

class _PostcodeStepScreenState extends ConsumerState<PostcodeStepScreen> {
  final _postcodeController = TextEditingController();
  final _line1Controller = TextEditingController();
  final _cityController = TextEditingController();

  bool _loading = false;
  String? _error;
  PostcodeLookupResult? _result;
  bool _manualMode = false;

  @override
  void dispose() {
    _postcodeController.dispose();
    _line1Controller.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref
          .read(addressRepositoryProvider)
          .lookup(_postcodeController.text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is PostcodeNotFoundException
            ? e.toString()
            : "Couldn't look up that postcode. Check it and try again.";
        _loading = false;
      });
    }
  }

  void _select(AddressSuggestion address) {
    ref.read(bookingDraftProvider.notifier).setGuestAddress(
          addressLine1: address.line1,
          addressCity: address.city,
          postcode: address.postcode,
          // Prefer the address's own precise coordinates (Ideal Postcodes);
          // fall back to the postcode centroid.
          lat: address.lat ?? _result?.centroidLat,
          lng: address.lng ?? _result?.centroidLng,
        );
    context.push(AddressStepScreen.routePath);
  }

  void _useManualAddress() {
    final line1 = _line1Controller.text.trim();
    if (line1.isEmpty) {
      setState(() => _error = 'Enter at least the first line of the address.');
      return;
    }
    ref.read(bookingDraftProvider.notifier).setGuestAddress(
          addressLine1: line1,
          addressCity: _cityController.text.trim(),
          postcode: _postcodeController.text.trim().toUpperCase(),
          lat: _result?.centroidLat,
          lng: _result?.centroidLng,
        );
    context.push(AddressStepScreen.routePath);
  }

  @override
  Widget build(BuildContext context) {
    return BookingShell(
      stepIndex: kStepPostcode,
      stepLabel: 'Address',
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "What's the address?",
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
        ),
        const SizedBox(height: 4),
        Text(
          'Enter your postcode and pick your address from the list.',
          style:
              theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _postcodeController,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _find(),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(8),
                  UpperCaseTextFormatter(),
                ],
                decoration: const InputDecoration(
                  hintText: 'e.g. CM1 1AA',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 104,
              height: 56,
              child: FilledButton(
                onPressed: _loading ? null : _find,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Find'),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
          ),
        ],
        if (_result != null) ...[
          const SizedBox(height: 20),
          if (!_result!.usingRealAddressData) const _SampleDataBanner(),
          if (!_result!.usingRealAddressData) const SizedBox(height: 12),
          Text(
            'Select your address',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          ..._result!.addresses.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AddressCard(address: a, onTap: () => _select(a)),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _manualMode = !_manualMode),
            icon: Icon(_manualMode
                ? Icons.expand_less_rounded
                : Icons.edit_location_alt_outlined),
            label: Text(_manualMode
                ? 'Hide manual entry'
                : "Can't find it? Enter address manually"),
          ),
        ),
        if (_manualMode) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _line1Controller,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Address line 1',
              hintText: 'House number and street',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cityController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Town / city'),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _useManualAddress,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Use this address'),
          ),
        ],
      ],
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address, required this.onTap});

  final AddressSuggestion address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.home_outlined,
                  color: Theme.of(context).colorScheme.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  address.displayLine,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleDataBanner extends StatelessWidget {
  const _SampleDataBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: cs.onSurface),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Showing sample addresses. Add an Ideal Postcodes key to list '
              'real addresses for this postcode.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Forces postcode input to upper case as the user types.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
