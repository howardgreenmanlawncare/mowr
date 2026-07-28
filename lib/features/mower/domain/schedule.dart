/// In-house route optimiser + scheduling engine for a single mower's day.
///
/// Given the jobs a mower has for a day, it finds the best *order* to do them
/// (least driving, while honouring each customer's time window) and produces a
/// timed plan. When a new job is offered, [assessInsertion] re-optimises the day
/// with it included and reports the impact — new finish time, extra driving,
/// where it slots — or why it won't fit.
///
/// Pure and dependency-free on purpose:
///   * No third-party service. Travel is haversine × road-factor ÷ avg speed;
///     swap [travelMinutes] for a self-hosted OSRM / matrix call when you want
///     real road times — nothing else changes.
///   * It's the exact primitive a future **fleet allocator** reuses: score
///     [assessInsertion] for a job across every opted-in mower, assign the best.
///
/// Ordering is solved exactly (all permutations) for a normal day's handful of
/// stops, falling back to nearest-neighbour + 2-opt above [_bruteForceMax] so it
/// still scales. All times are whole minutes measured from the day's start.
library;

import 'dart:math' as math;

import 'mower_job.dart';

class SchedulingConfig {
  const SchedulingConfig({
    this.mowSqmPerMinute = 3.0,
    this.perLawnSetupMinutes = 10,
    this.averageSpeedKmh = 30,
    this.roadFactor = 1.3,
    this.dayStartHour = 8,
    this.dayEndHour = 18,
  });

  /// Square metres a mower clears per minute.
  final double mowSqmPerMinute;

  /// Fixed per-lawn overhead: unloading, edging setup, packing up.
  final int perLawnSetupMinutes;

  final double averageSpeedKmh;

  /// Multiplier turning straight-line distance into rough road distance.
  final double roadFactor;

  final int dayStartHour;
  final int dayEndHour;

  int get workingDayMinutes => (dayEndHour - dayStartHour) * 60;

  /// A time window as [open, close] minutes from the working-day start.
  (int, int) windowBounds(String? window) => switch (window) {
        'morning' => (0, 4 * 60), // 08:00–12:00
        'afternoon' => (4 * 60, 9 * 60), // 12:00–17:00
        'evening' => (9 * 60, 12 * 60), // 17:00–20:00
        _ => (0, workingDayMinutes), // 'any' / null — the whole day
      };
}

/// One job to be scheduled.
class RouteStop {
  const RouteStop({
    required this.id,
    required this.durationMinutes,
    required this.window,
    this.lat,
    this.lng,
  });

  final String id;
  final int durationMinutes;

  /// 'morning' | 'afternoon' | 'evening' | 'any'.
  final String window;
  final double? lat;
  final double? lng;
}

/// A stop placed on the timeline: when the mower arrives, starts and finishes
/// (minutes from day start).
class PlannedStop {
  const PlannedStop({
    required this.stop,
    required this.arrival,
    required this.start,
    required this.end,
  });

  final RouteStop stop;
  final int arrival;
  final int start;
  final int end;
}

/// A fully sequenced, timed day.
class RoutePlan {
  const RoutePlan({
    required this.stops,
    required this.travelMinutes,
    required this.feasible,
  });

  final List<PlannedStop> stops;
  final int travelMinutes;

  /// Every stop starts within its window and the day doesn't overrun.
  final bool feasible;

  /// When the mower finishes the last job (minutes from day start), or 0 for an
  /// empty day.
  int get finish => stops.isEmpty ? 0 : stops.last.end;

  int get stopCount => stops.length;
}

/// What accepting a candidate job does to the day.
class InsertionResult {
  const InsertionResult({
    required this.feasible,
    required this.before,
    required this.after,
    required this.candidatePosition,
    this.infeasibleReason,
  });

  /// The candidate can be slotted in without making any job miss its window.
  final bool feasible;

  /// The optimised day as it stands now.
  final RoutePlan before;

  /// The optimised day including the candidate (best feasible ordering). When
  /// [feasible] is false this is the closest attempt and shouldn't be relied on.
  final RoutePlan after;

  /// 1-based position of the candidate in [after], or 0 if not placed.
  final int candidatePosition;

  /// Why it won't fit, when [feasible] is false.
  final String? infeasibleReason;

  /// Extra driving the candidate adds.
  int get addedTravel => after.travelMinutes - before.travelMinutes;

  /// How much later the day ends.
  int get addedFinish => after.finish - before.finish;
}

class SchedulingEngine {
  const SchedulingEngine([this.config = const SchedulingConfig()]);

  final SchedulingConfig config;

  static const int _bruteForceMax = 8;

  // --- estimates -----------------------------------------------------------

  int estimateJobMinutes({required double areaSqm, required int lawnCount}) {
    final mowing = areaSqm / config.mowSqmPerMinute;
    final setup = config.perLawnSetupMinutes * math.max(1, lawnCount);
    return (mowing + setup).round();
  }

  int estimateJobMinutesFor(MowerJob job) =>
      estimateJobMinutes(areaSqm: job.totalArea, lawnCount: job.lawnCount);

  double haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  int travelMinutes(double lat1, double lng1, double lat2, double lng2) {
    final km = haversineKm(lat1, lng1, lat2, lng2) * config.roadFactor;
    return (km / config.averageSpeedKmh * 60).round();
  }

  int _legTravel(RouteStop a, RouteStop b) {
    if (a.lat == null || a.lng == null || b.lat == null || b.lng == null) {
      return 0;
    }
    return travelMinutes(a.lat!, a.lng!, b.lat!, b.lng!);
  }

  // --- routing -------------------------------------------------------------

  /// Simulate a given order into a timed plan. Travel is only counted between
  /// consecutive stops (the mower's start location is unknown, so there's no
  /// leg to the first job). A stop that would start after its window closes
  /// makes the plan infeasible.
  RoutePlan _simulate(List<RouteStop> order) {
    if (order.isEmpty) {
      return const RoutePlan(stops: [], travelMinutes: 0, feasible: true);
    }
    final planned = <PlannedStop>[];
    var t = 0;
    var travel = 0;
    var feasible = true;

    for (var i = 0; i < order.length; i++) {
      final s = order[i];
      if (i > 0) {
        final leg = _legTravel(order[i - 1], s);
        travel += leg;
        t += leg;
      }
      final (open, close) = config.windowBounds(s.window);
      final arrival = t;
      if (t < open) t = open; // wait for the window to open
      final start = t;
      if (start > close || start + s.durationMinutes > config.workingDayMinutes) {
        feasible = false;
      }
      final end = start + s.durationMinutes;
      planned.add(PlannedStop(stop: s, arrival: arrival, start: start, end: end));
      t = end;
    }
    return RoutePlan(stops: planned, travelMinutes: travel, feasible: feasible);
  }

  /// Best ordering of [stops]: least driving among feasible orders (tie-break:
  /// earliest finish). Exact for small days, heuristic above [_bruteForceMax].
  RoutePlan optimiseDay(List<RouteStop> stops) {
    if (stops.length <= 1) return _simulate(stops);
    final orders = stops.length <= _bruteForceMax
        ? _permutations(stops)
        : [_twoOpt(_nearestNeighbour(stops))];

    RoutePlan? best;
    for (final order in orders) {
      final plan = _simulate(order);
      if (best == null || _better(plan, best)) best = plan;
    }
    return best ?? _simulate(stops);
  }

  /// Prefer feasible plans; then least travel; then earliest finish.
  bool _better(RoutePlan a, RoutePlan b) {
    if (a.feasible != b.feasible) return a.feasible;
    if (a.travelMinutes != b.travelMinutes) {
      return a.travelMinutes < b.travelMinutes;
    }
    return a.finish < b.finish;
  }

  /// Re-optimise the day with [candidate] added and report the impact.
  InsertionResult assessInsertion({
    required MowerJob candidate,
    required List<MowerJob> committed,
    required DateTime today,
  }) {
    final date = _jobDate(candidate, today);
    final committedStops = committed
        .where((j) => _sameDay(_jobDate(j, today), date))
        .map(_toStop)
        .toList();
    final candidateStop = _toStop(candidate);

    final before = optimiseDay(committedStops);
    final after = optimiseDay([...committedStops, candidateStop]);

    final position = after.stops.indexWhere((p) => p.stop.id == candidateStop.id);

    return InsertionResult(
      feasible: after.feasible,
      before: before,
      after: after,
      candidatePosition: position < 0 ? 0 : position + 1,
      infeasibleReason: after.feasible
          ? null
          : 'It can’t be slotted in without making another job miss its '
              'time window.',
    );
  }

  RouteStop _toStop(MowerJob job) => RouteStop(
        id: job.bookingId,
        durationMinutes: estimateJobMinutesFor(job),
        window: (job.asap ? 'any' : job.timeWindow) ?? 'any',
        lat: job.lat,
        lng: job.lng,
      );

  /// A schedulable stop for a job. Public so screens/allocators can build a plan
  /// and map its stops back to jobs by [RouteStop.id] (== bookingId).
  RouteStop stopFor(MowerJob job) => _toStop(job);

  /// Optimise a set of jobs directly into a timed, ordered plan.
  RoutePlan optimiseJobs(List<MowerJob> jobs) =>
      optimiseDay(jobs.map(_toStop).toList());

  // --- ordering helpers ----------------------------------------------------

  List<List<RouteStop>> _permutations(List<RouteStop> items) {
    final out = <List<RouteStop>>[];
    void permute(List<RouteStop> current, List<RouteStop> remaining) {
      if (remaining.isEmpty) {
        out.add(current);
        return;
      }
      for (var i = 0; i < remaining.length; i++) {
        final next = [...remaining]..removeAt(i);
        permute([...current, remaining[i]], next);
      }
    }

    permute([], items);
    return out;
  }

  List<RouteStop> _nearestNeighbour(List<RouteStop> stops) {
    final remaining = [...stops];
    final route = <RouteStop>[remaining.removeAt(0)];
    while (remaining.isNotEmpty) {
      final last = route.last;
      var bestIdx = 0;
      var bestCost = _legTravel(last, remaining[0]);
      for (var i = 1; i < remaining.length; i++) {
        final c = _legTravel(last, remaining[i]);
        if (c < bestCost) {
          bestCost = c;
          bestIdx = i;
        }
      }
      route.add(remaining.removeAt(bestIdx));
    }
    return route;
  }

  List<RouteStop> _twoOpt(List<RouteStop> route) {
    var best = route;
    var improved = true;
    while (improved) {
      improved = false;
      for (var i = 0; i < best.length - 1; i++) {
        for (var k = i + 1; k < best.length; k++) {
          final candidate = [
            ...best.sublist(0, i),
            ...best.sublist(i, k + 1).reversed,
            ...best.sublist(k + 1),
          ];
          if (_routeTravel(candidate) < _routeTravel(best)) {
            best = candidate;
            improved = true;
          }
        }
      }
    }
    return best;
  }

  int _routeTravel(List<RouteStop> order) {
    var t = 0;
    for (var i = 1; i < order.length; i++) {
      t += _legTravel(order[i - 1], order[i]);
    }
    return t;
  }

  // --- dates ---------------------------------------------------------------

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _jobDate(MowerJob job, DateTime today) =>
      (job.asap || job.scheduledDate == null) ? today : job.scheduledDate!;
}
