import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../domain/property_access_model.dart';
import '../../providers/booking_draft_provider.dart';
import '../booking_shell.dart';
import 'condition_photos_step.dart';

class LawnAccessStepScreen extends ConsumerStatefulWidget {
  const LawnAccessStepScreen({super.key});

  static const routePath = '/booking/lawn-access';

  @override
  ConsumerState<LawnAccessStepScreen> createState() =>
      _LawnAccessStepScreenState();
}

class _LawnAccessStepScreenState extends ConsumerState<LawnAccessStepScreen> {
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    // Seed controller from any persisted notes (empty string on first visit).
    final draft = ref.read(bookingDraftProvider);
    final initialNotes =
        draft.propertyAccessMap[draft.propertyId]?.notes ?? '';
    _notesController = TextEditingController(text: initialNotes);

    // Push every keystroke into the provider so canContinue stays reactive.
    _notesController.addListener(() {
      ref
          .read(bookingDraftProvider.notifier)
          .updateAccessNotes(_notesController.text);
    });

    // Idempotent init — no-op if an entry for this property already exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bookingDraftProvider.notifier).initPropertyAccess();
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingDraftProvider);
    final access =
        draft.propertyAccessMap[draft.propertyId] ?? const PropertyAccess();

    final requiresNotes = access.notesRequired;
    final canContinue = !requiresNotes || access.notes.isNotEmpty;

    return BookingShell(
      stepIndex: kStepLawnAccess,
      stepLabel: 'Lawn access',
      bottomBar: _AccessBottomBar(
        canContinue: canContinue,
        onContinue: () => context.push(ConditionPhotosStepScreen.routePath),
      ),
      body: _LawnAccessBody(
        access: access,
        notesController: _notesController,
        requiresNotes: requiresNotes,
        onTogglePreset: (preset) =>
            ref.read(bookingDraftProvider.notifier).toggleAccessPreset(preset),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _LawnAccessBody extends StatelessWidget {
  const _LawnAccessBody({
    required this.access,
    required this.notesController,
    required this.requiresNotes,
    required this.onTogglePreset,
  });

  final PropertyAccess access;
  final TextEditingController notesController;
  final bool requiresNotes;
  final void Function(AccessPreset) onTogglePreset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How do we get to the lawn?',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select all that apply.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700,
              ),
        ),
        const SizedBox(height: 20),
        _PresetCard(
          selectedPresets: access.presets,
          onToggle: onTogglePreset,
        ),
        const SizedBox(height: 16),
        _NotesField(
          controller: notesController,
          required: requiresNotes,
          showError: requiresNotes && access.notes.isEmpty,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.selectedPresets,
    required this.onToggle,
  });

  final Set<AccessPreset> selectedPresets;
  final void Function(AccessPreset) onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AccessPreset.values.map((preset) {
            final selected = selectedPresets.contains(preset);
            return FilterChip(
              label: Text(preset.label),
              selected: selected,
              onSelected: (_) => onToggle(preset),
              selectedColor: cs.primaryContainer,
              checkmarkColor: cs.onPrimaryContainer,
              labelStyle: TextStyle(
                color: selected ? cs.onPrimaryContainer : null,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _NotesField extends StatelessWidget {
  const _NotesField({
    required this.controller,
    required this.required,
    required this.showError,
  });

  final TextEditingController controller;
  final bool required;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 3,
      maxLines: 5,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: required ? 'Access notes (required)' : 'Access notes',
        hintText: 'e.g. gate code, dog in garden, parking',
        errorText: showError ? 'Please add notes for this access type' : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AccessBottomBar extends StatelessWidget {
  const _AccessBottomBar({
    required this.canContinue,
    required this.onContinue,
  });

  final bool canContinue;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: FilledButton.icon(
          onPressed: canContinue ? onContinue : null,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Continue'),
        ),
      ),
    );
  }
}
