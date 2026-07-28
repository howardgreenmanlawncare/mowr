import 'package:flutter_test/flutter_test.dart';
import 'package:mowr/features/mower/domain/fleet.dart';
import 'package:mowr/features/mower/domain/mower_job.dart';

MowerJob job({
  required String id,
  double area = 120,
  int lawns = 1,
  String? window,
  DateTime? date,
  double? lat,
  double? lng,
}) =>
    MowerJob(
      bookingId: id,
      status: 'confirmed',
      asap: false,
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
  const allocator = FleetAllocator();
  final day = DateTime(2026, 8, 3);

  test('assigns a job to the only available mower', () {
    final plan = allocator.allocate(
      jobs: [job(id: 'j1', window: 'morning', date: day)],
      mowers: const [MowerAvailability(mowerId: 'm1')],
      day: day,
    );
    expect(plan.assigned.length, 1);
    expect(plan.allocations.first.mowerId, 'm1');
  });

  test('prefers the nearer mower (least added driving)', () {
    // Job sits next to m2's existing job and far from m1's.
    final plan = allocator.allocate(
      jobs: [job(id: 'j', window: 'any', date: day, lat: 51.90, lng: 0)],
      mowers: [
        MowerAvailability(mowerId: 'm1', committed: [
          job(id: 'm1a', window: 'any', date: day, lat: 51.50, lng: 0),
        ]),
        MowerAvailability(mowerId: 'm2', committed: [
          job(id: 'm2a', window: 'any', date: day, lat: 51.91, lng: 0),
        ]),
      ],
      day: day,
    );
    expect(plan.allocations.first.mowerId, 'm2');
  });

  test('spreads work when mowers are otherwise equal', () {
    // Two identical empty mowers, two jobs → one each.
    final plan = allocator.allocate(
      jobs: [
        job(id: 'j1', window: 'any', date: day),
        job(id: 'j2', window: 'any', date: day),
      ],
      mowers: const [
        MowerAvailability(mowerId: 'm1'),
        MowerAvailability(mowerId: 'm2'),
      ],
      day: day,
    );
    expect(plan.byMower.keys.toSet(), {'m1', 'm2'});
    expect(plan.byMower['m1']!.length, 1);
    expect(plan.byMower['m2']!.length, 1);
  });

  test('leaves a job unassigned when nobody can fit its window', () {
    // Evening window holds ~3h; three ~110-min evening jobs can't all fit one
    // mower, and there's only one mower.
    final committed = [
      job(id: 'e1', area: 300, window: 'evening', date: day),
      job(id: 'e2', area: 300, window: 'evening', date: day),
    ];
    final plan = allocator.allocate(
      jobs: [job(id: 'e3', area: 300, window: 'evening', date: day)],
      mowers: [MowerAvailability(mowerId: 'm1', committed: committed)],
      day: day,
    );
    expect(plan.unassigned.length, 1);
    expect(plan.unassigned.first.reason, isNotNull);
  });

  test('reports the insertion impact for each assignment', () {
    final plan = allocator.allocate(
      jobs: [job(id: 'j', window: 'morning', date: day)],
      mowers: const [MowerAvailability(mowerId: 'm1')],
      day: day,
    );
    final a = plan.allocations.first;
    expect(a.impact, isNotNull);
    expect(a.impact!.feasible, isTrue);
  });
}
