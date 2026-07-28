import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Position of each step in the booking flow, used only for the "N of M"
/// progress indicator.
///
/// Both entry paths have the same number of screens, so one index space covers
/// them: steps 0 and 1 are the path-specific entry screens (properties + lawn
/// selection for a returning customer; postcode + lawn creation for a guest),
/// and the two paths converge from [kStepGrassHeight] onward.
///
/// Two constants may share an index ONLY when they are alternative screens at
/// the same position on different paths — never when they are sequential
/// screens on the same path. Getting that wrong makes the counter repeat a
/// number and the progress bar stall, which is what these values did before.
///
/// Full-screen sub-flows that don't use [BookingShell] — confirm-location
/// (`address_step`) and `lawn_draw_screen` — are deliberately not counted.
const int kBookingStepCount = 11;

const int kStepProperties = 0;      // returning-customer entry
const int kStepPostcode = 0;        // guest entry (alternative to properties)
const int kStepLawnSelection = 1;   // returning-customer lawn pick
const int kStepLawn = 1;            // guest lawn creation (alternative)
const int kStepGrassHeight = 2;     // convergence point (both paths)
const int kStepLawnAccess = 3;
const int kStepConditionPhotos = 4;
const int kStepService = 5;
const int kStepSchedule = 6;
const int kStepReview = 7;
const int kStepAccount = 8;
const int kStepPayment = 9;
const int kStepConfirmation = 10;

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
        title: const Text('Book a mow'),
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
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          borderRadius: BorderRadius.circular(999),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ],
    );
  }
}
