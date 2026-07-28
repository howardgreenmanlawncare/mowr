/// Fleet allocator: assigns a day's jobs across opted-in mowers, most
/// efficiently. This is the "night-before auto-allocation" the product scales
/// on — and it is simply the single-mower [SchedulingEngine.assessInsertion]
/// primitive applied across every mower: score each job against each mower's
/// day, give it to the one it fits best.
///
/// Greedy by design (assign the hardest-to-place jobs first, best mower each
/// time). That's fast, in-house, and good enough to launch; swap the loop for
/// an OR-Tools VRP solver when a globally-optimal fleet plan is worth it —
/// nothing above this changes.
library;

import 'mower_job.dart';
import 'schedule.dart';

/// A mower available to take work on the day, with whatever they're already
/// committed to.
class MowerAvailability {
  const MowerAvailability({required this.mowerId, this.committed = const []});

  final String mowerId;
  final List<MowerJob> committed;
}

/// The outcome for one job.
class JobAllocation {
  const JobAllocation({
    required this.job,
    this.mowerId,
    this.impact,
    this.reason,
  });

  final MowerJob job;

  /// The mower it went to, or null if nobody could fit it.
  final String? mowerId;

  /// How it slots into that mower's re-optimised day.
  final InsertionResult? impact;

  /// Why it couldn't be placed, when [mowerId] is null.
  final String? reason;

  bool get assigned => mowerId != null;
}

/// The whole day's plan.
class FleetPlan {
  const FleetPlan({required this.allocations});

  final List<JobAllocation> allocations;

  List<JobAllocation> get assigned =>
      allocations.where((a) => a.assigned).toList();
  List<JobAllocation> get unassigned =>
      allocations.where((a) => !a.assigned).toList();

  /// Jobs grouped by the mower they went to.
  Map<String, List<MowerJob>> get byMower {
    final map = <String, List<MowerJob>>{};
    for (final a in assigned) {
      (map[a.mowerId!] ??= []).add(a.job);
    }
    return map;
  }
}

class FleetAllocator {
  const FleetAllocator([this.engine = const SchedulingEngine()]);

  final SchedulingEngine engine;

  /// Allocate [jobs] across [mowers] for [day].
  ///
  /// Hardest-to-place jobs go first (tightest time window, then longest), each
  /// to the mower whose day it disturbs least — least extra driving, breaking
  /// ties toward finishing earlier and toward the less-loaded mower so work
  /// spreads.
  FleetPlan allocate({
    required List<MowerJob> jobs,
    required List<MowerAvailability> mowers,
    required DateTime day,
  }) {
    // Mutable working copy of each mower's day; grows as we assign.
    final load = <String, List<MowerJob>>{
      for (final m in mowers) m.mowerId: [...m.committed],
    };

    final queue = [...jobs]..sort(_hardestFirst);
    final out = <JobAllocation>[];

    for (final job in queue) {
      String? bestMower;
      InsertionResult? best;

      for (final m in mowers) {
        final impact = engine.assessInsertion(
          candidate: job,
          committed: load[m.mowerId]!,
          today: day,
        );
        if (!impact.feasible) continue;

        if (best == null ||
            _preferable(
              impact,
              load[m.mowerId]!.length,
              best,
              load[bestMower]!.length,
            )) {
          best = impact;
          bestMower = m.mowerId;
        }
      }

      if (bestMower == null) {
        out.add(JobAllocation(
          job: job,
          reason: 'No available mower can fit it within its time window.',
        ));
      } else {
        load[bestMower]!.add(job);
        out.add(JobAllocation(job: job, mowerId: bestMower, impact: best));
      }
    }

    return FleetPlan(allocations: out);
  }

  /// Tight windows and long jobs are hardest to place, so do them first while
  /// mowers still have room.
  int _hardestFirst(MowerJob a, MowerJob b) {
    int cap(MowerJob j) => engine.config
        .windowBounds((j.asap ? 'any' : j.timeWindow) ?? 'any')
        .$2; // window close time ≈ how much room it allows
    final byWindow = cap(a).compareTo(cap(b));
    if (byWindow != 0) return byWindow; // smaller window first
    // Then longer jobs first.
    return engine
        .estimateJobMinutesFor(b)
        .compareTo(engine.estimateJobMinutesFor(a));
  }

  /// Is candidate [c] a better home than the current [best]?
  bool _preferable(
    InsertionResult c,
    int cLoad,
    InsertionResult best,
    int bestLoad,
  ) {
    if (c.addedTravel != best.addedTravel) {
      return c.addedTravel < best.addedTravel;
    }
    if (c.addedFinish != best.addedFinish) {
      return c.addedFinish < best.addedFinish;
    }
    return cLoad < bestLoad; // spread work toward the emptier day
  }
}
