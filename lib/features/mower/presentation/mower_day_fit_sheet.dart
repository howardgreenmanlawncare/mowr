import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

import '../domain/mower_job.dart';
import '../domain/schedule.dart';

/// Confirmation sheet shown when a mower taps Accept. The route optimiser has
/// already re-planned their day with this job included; this sheet reports the
/// impact — where it slots in the sequence, the new finish time, extra driving,
/// or why it won't fit — before they commit.
///
/// Advisory, not a gate: even a job that doesn't cleanly fit can be accepted;
/// the mower decides. Returns true if they confirm.
class MowerDayFitSheet extends StatelessWidget {
  const MowerDayFitSheet({
    super.key,
    required this.job,
    required this.fit,
    this.dayStartHour = 8,
  });

  final MowerJob job;
  final InsertionResult fit;
  final int dayStartHour;

  static Future<bool?> show(
    BuildContext context, {
    required MowerJob job,
    required InsertionResult fit,
  }) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => MowerDayFitSheet(job: job, fit: fit),
      );

  static String _dur(int m) {
    if (m <= 0) return '0m';
    if (m < 60) return '${m}m';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '${h}h' : '${h}h ${r}m';
  }

  /// Minutes-from-day-start → clock time like "3:40pm".
  String _clock(int minutesFromStart) {
    final total = dayStartHour * 60 + minutesFromStart;
    final h24 = (total ~/ 60) % 24;
    final m = total % 60;
    final ampm = h24 < 12 ? 'am' : 'pm';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h12:${m.toString().padLeft(2, '0')}$ampm';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final feasible = fit.feasible;

    // The candidate's own on-site time, pulled from the re-planned route.
    final placed = fit.after.stops
        .where((p) => p.stop.id == job.bookingId)
        .map((p) => p.stop.durationMinutes);
    final onSiteMinutes = placed.isEmpty ? 0 : placed.first;

    final (Color bg, Color fg, IconData icon, String headline) = feasible
        ? (
            cs.primaryContainer,
            cs.onPrimaryContainer,
            Icons.route_rounded,
            fit.before.stopCount == 0
                ? 'Fits your day'
                : 'Slots in as stop ${fit.candidatePosition} of '
                    '${fit.after.stopCount}',
          )
        : (
            cs.errorContainer,
            cs.onErrorContainer,
            Icons.warning_amber_rounded,
            'Tight fit for your day',
          );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(job.addressLine, style: text.titleMedium),
            const SizedBox(height: 2),
            Text(job.whenLabel,
                style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),

            // Impact banner.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(icon, color: fg),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(headline,
                            style: text.titleSmall?.copyWith(color: fg)),
                        if (!feasible && fit.infeasibleReason != null) ...[
                          const SizedBox(height: 2),
                          Text(fit.infeasibleReason!,
                              style: text.bodySmall?.copyWith(color: fg)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _Row(label: 'Time on site', value: '~${_dur(onSiteMinutes)}'),
            _Row(
              label: 'Extra driving',
              value: fit.addedTravel <= 0 ? '—' : '+${_dur(fit.addedTravel)}',
            ),
            if (fit.before.stopCount > 0)
              _Row(
                label: 'Day now finishes',
                value: '${_clock(fit.after.finish)}'
                    '${fit.addedFinish > 0 ? '  (+${_dur(fit.addedFinish)})' : ''}',
                emphasise: true,
              )
            else
              _Row(
                label: 'You’d finish around',
                value: _clock(fit.after.finish),
                emphasise: true,
              ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(feasible ? 'Accept job' : 'Accept anyway'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = emphasise ? text.titleSmall : text.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: text.bodyMedium),
          Text(value, style: style),
        ],
      ),
    );
  }
}
