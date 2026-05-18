import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const int kBookingStepCount = 8;

const int kStepProperties = 0;    // returning-customer path first screen
const int kStepPostcode = 0;      // guest path first screen
const int kStepAddress = 1;
const int kStepLawnSelection = 2; // returning-customer path
const int kStepLawn = 3;          // guest path: lawn creation
const int kStepGrassHeight = 3;   // convergence point (both paths)
const int kStepService = 4;
const int kStepSchedule = 5;
const int kStepReview = 6;
const int kStepConfirmation = 7;

/// Shared scaffold for every booking step.
///
/// [bottomBar] overrides the default [FilledButton] footer — use it when a
/// step needs a custom bottom widget (e.g. "X of Y selected" + Continue).
/// Set [onContinue] to null to suppress the default footer entirely.
class BookingShell extends StatelessWidget {
  const BookingShell({
    super.key,
    required this.stepIndex,
    required this.stepLabel,
    required this.body,
    this.onContinue,
    this.continueLabel = 'Continue',
    this.bottomBar,
  });

  final int stepIndex;
  final String stepLabel;
  final Widget body;
  final VoidCallback? onContinue;
  final String continueLabel;

  /// When non-null, replaces the default FilledButton footer completely.
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFirst = stepIndex == 0; // covers both kStepProperties and kStepPostcode

    Widget? resolvedBottom;
    if (bottomBar != null) {
      resolvedBottom = bottomBar;
    } else if (onContinue != null) {
      resolvedBottom = SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: FilledButton.icon(
            onPressed: onContinue,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(continueLabel),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: isFirst
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'MOWR',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                fontSize: 14,
              ),
            ),
            Text(
              'Book a lawn mow',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.grass_rounded, color: cs.onPrimaryContainer),
            ),
          ),
        ],
      ),
      bottomNavigationBar: resolvedBottom,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: _BookingProgressBar(
                stepIndex: stepIndex,
                label: stepLabel,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingProgressBar extends StatelessWidget {
  const _BookingProgressBar({
    required this.stepIndex,
    required this.label,
  });

  final int stepIndex;
  final String label;

  @override
  Widget build(BuildContext context) {
    final displayStep = stepIndex.clamp(0, kBookingStepCount - 1);
    final progress = (displayStep + 1) / kBookingStepCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            Text(
              '${displayStep + 1} of $kBookingStepCount',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(999),
          backgroundColor: Colors.grey.shade200,
        ),
      ],
    );
  }
}
