import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../domain/property_model.dart';
import '../../mock/mock_properties.dart';
import '../../providers/booking_draft_provider.dart';
import '../booking_shell.dart';
import 'lawn_selection_step.dart';
import 'postcode_step.dart';

class SavedPropertiesStepScreen extends ConsumerWidget {
  const SavedPropertiesStepScreen({super.key});

  static const routePath = '/booking/properties';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BookingShell(
      stepIndex: kStepProperties,
      stepLabel: 'Your properties',
      // No onContinue or bottomBar — tapping a property card is the action.
      body: _SavedPropertiesBody(
        properties: kMockProperties,
        onSelect: (property) {
          ref.read(bookingDraftProvider.notifier).setPropertyId(property.id);
          context.push(LawnSelectionStepScreen.routePath);
        },
        onAddNew: () => context.push(PostcodeStepScreen.routePath),
      ),
    );
  }
}

class _SavedPropertiesBody extends StatelessWidget {
  const _SavedPropertiesBody({
    required this.properties,
    required this.onSelect,
    required this.onAddNew,
  });

  final List<Property> properties;
  final void Function(Property) onSelect;
  final VoidCallback onAddNew;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Which property needs mowing?',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select a saved property or add a new one.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700,
              ),
        ),
        const SizedBox(height: 20),
        ...properties.map(
          (property) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PropertyCard(
              property: property,
              onTap: () => onSelect(property),
            ),
          ),
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: onAddNew,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add a new property'),
        ),
      ],
    );
  }
}

class _PropertyCard extends StatelessWidget {
  const _PropertyCard({
    required this.property,
    required this.onTap,
  });

  final Property property;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(
                  Icons.home_rounded,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.addressLine1,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${property.addressCity}  ·  ${property.postcode}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _LawnCountChip(label: property.lawnCountLabel),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LawnCountChip extends StatelessWidget {
  const _LawnCountChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cs.onPrimaryContainer,
        ),
      ),
    );
  }
}
