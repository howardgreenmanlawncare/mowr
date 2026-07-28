import 'package:flutter_test/flutter_test.dart';
import 'package:mowr/features/mower/domain/mower_job.dart';
import 'package:mowr/features/mower/domain/schedule.dart';

MowerJob job({
  String id = 'j',
  double area = 0,
  int lawns = 1,
  bool asap = false,
  String? window,
  DateTime? date,
  double? lat,
  double? lng,
}) =>
    MowerJob(
      bookingId: id,
      status: 'confirmed',
      asap: asap,
      totalAmount: 0,
      line1: '',
      lawnCount: lawns,
      totalArea: area,
      timeWindow: window,
      scheduledDate: date,
      lat: lat,
      lng: lng,
    );

void main() {
  const engine = SchedulingEngine();
  final monday = DateTime(2026, 8, 3);

  group('duration', () {
    test('scales with area plus per-lawn setup', () {
      // 180 m² at 3 m²/min = 60 min mowing + 10 min setup = 70.
      expect(engine.estimateJobMinutes(areaSqm: 180, lawnCount: 1), 70);
    });

    test('charges setup per lawn', () {
      expect(engine.estimateJobMinutes(areaSqm: 180, lawnCount: 2), 80);
    });

    test('a zero-area job still costs setup', () {
      expect(engine.estimateJobMinutes(areaSqm: 0, lawnCount: 1), 10);
    });
  });

  group('travel', () {
    test('same point is zero', () {
      expect(engine.travelMinutes(51.5, -0.1, 51.5, -0.1), 0);
    });

    test('grows with distance', () {
      final near = engine.travelMinutes(51.50, -0.10, 51.51, -0.10);
      final far = engine.travelMinutes(51.50, -0.10, 51.70, -0.10);
      expect(far, greaterThan(near));
    });
  });

  group('route optimisation', () {
    RouteStop stop(String id, double lat, {String window = 'any', int dur = 30}) =>
        RouteStop(id: id, durationMinutes: dur, window: window, lat: lat, lng: 0);

    test('orders stops to minimise driving', () {
      // Placed out of order along a line; the best route visits them in
      // sequence. Direction is free (travel is symmetric, no fixed start), so
      // either a→b→c or its reverse is optimal — what matters is no zigzag, i.e.
      // 'b' sits in the middle.
      final plan = engine.optimiseDay([
        stop('c', 0.3),
        stop('a', 0.1),
        stop('b', 0.2),
      ]);
      final order = plan.stops.map((p) => p.stop.id).toList();
      expect(order[1], 'b');
      expect(order, anyOf(equals(['a', 'b', 'c']), equals(['c', 'b', 'a'])));
      expect(plan.feasible, isTrue);
    });

    test('empty day is feasible with no travel', () {
      final plan = engine.optimiseDay(const []);
      expect(plan.stops, isEmpty);
      expect(plan.travelMinutes, 0);
      expect(plan.finish, 0);
    });

    test('respects time windows over pure distance', () {
      // The far stop is morning-only; the near stop is any-time. A pure
      // distance ordering might do the near one first, but the plan must still
      // serve the morning job inside its window.
      final plan = engine.optimiseDay([
        stop('near', 0.05, window: 'any', dur: 60),
        stop('morning', 0.30, window: 'morning', dur: 60),
      ]);
      expect(plan.feasible, isTrue);
      final morning = plan.stops.firstWhere((p) => p.stop.id == 'morning');
      final (open, close) = const SchedulingConfig().windowBounds('morning');
      expect(morning.start, greaterThanOrEqualTo(open));
      expect(morning.start, lessThanOrEqualTo(close));
    });
  });

  group('insertion impact', () {
    test('accepting into an empty day is feasible and first', () {
      final r = engine.assessInsertion(
        candidate: job(area: 180, window: 'morning', date: monday),
        committed: const [],
        today: monday,
      );
      expect(r.feasible, isTrue);
      expect(r.candidatePosition, 1);
      expect(r.before.stopCount, 0);
      expect(r.after.stopCount, 1);
    });

    test('reports added driving from the re-optimised route', () {
      final r = engine.assessInsertion(
        candidate: job(
            id: 'new', area: 60, window: 'any', date: monday, lat: 0.2, lng: 0),
        committed: [
          job(id: 'a', area: 60, window: 'any', date: monday, lat: 0.1, lng: 0),
          job(id: 'b', area: 60, window: 'any', date: monday, lat: 0.3, lng: 0),
        ],
        today: monday,
      );
      expect(r.feasible, isTrue);
      // Best insertion is between a and b, so the candidate is 2nd.
      expect(r.candidatePosition, 2);
      expect(r.addedTravel, greaterThanOrEqualTo(0));
      expect(r.after.finish, greaterThan(r.before.finish));
    });

    test('flags when a job would miss its window', () {
      // Three long evening-only jobs can't all fit the 3-hour evening window.
      final committed = [
        job(id: 'a', area: 300, window: 'evening', date: monday), // 110 min
        job(id: 'b', area: 300, window: 'evening', date: monday),
      ];
      final r = engine.assessInsertion(
        candidate: job(id: 'c', area: 300, window: 'evening', date: monday),
        committed: committed,
        today: monday,
      );
      expect(r.feasible, isFalse);
      expect(r.infeasibleReason, isNotNull);
    });

    test('jobs on other days do not affect the plan', () {
      final tuesday = monday.add(const Duration(days: 1));
      final r = engine.assessInsertion(
        candidate: job(area: 180, window: 'morning', date: monday),
        committed: [job(area: 900, window: 'morning', date: tuesday)],
        today: monday,
      );
      expect(r.before.stopCount, 0);
      expect(r.feasible, isTrue);
    });
  });
}
