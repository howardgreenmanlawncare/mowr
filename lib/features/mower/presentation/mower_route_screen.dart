import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/map/map_load_state.dart';
import '../../../core/map/satellite_tiles.dart';
import '../data/mower_repository.dart';
import '../domain/mower_job.dart';
import '../domain/schedule.dart';
import 'mower_job_detail_screen.dart' show openDirections;

/// The mower's day as an optimised route: their accepted jobs sequenced into the
/// least-driving order (honouring time windows), drawn on a map with numbered
/// stops and listed with arrival times. "Take me there" per stop hands the drive
/// off to the phone's maps app.
///
/// Keeps the mower in-app for the valuable part — seeing their day and its
/// order — while the actual turn-by-turn stays with Google/Apple Maps.
class MowerRouteScreen extends ConsumerStatefulWidget {
  const MowerRouteScreen({super.key});

  static const routePath = '/mower/route';

  @override
  ConsumerState<MowerRouteScreen> createState() => _MowerRouteScreenState();
}

class _MowerRouteScreenState extends ConsumerState<MowerRouteScreen> {
  static const _engine = SchedulingEngine();
  final _mapLoad = MapLoadState();

  bool _loading = true;
  String? _error;
  List<MowerJob> _jobs = const [];
  late List<DateTime> _dates;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mapLoad.dispose();
    super.dispose();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Effective date for a job — ASAP jobs count as today.
  DateTime _jobDate(MowerJob j, DateTime today) =>
      (j.asap || j.scheduledDate == null) ? today : _dateOnly(j.scheduledDate!);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jobs = await ref.read(mowerRepositoryProvider).myJobs();
      final today = _dateOnly(DateTime.now());
      final dates = <DateTime>{for (final j in jobs) _jobDate(j, today)}.toList()
        ..sort();
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _dates = dates;
        _selectedDate = dates.isEmpty ? null : dates.first;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your route.';
      });
    }
  }

  List<MowerJob> get _jobsForSelectedDate {
    final date = _selectedDate;
    if (date == null) return const [];
    final today = _dateOnly(DateTime.now());
    return _jobs.where((j) => _jobDate(j, today) == date).toList();
  }

  static String _dur(int m) {
    if (m <= 0) return '0m';
    if (m < 60) return '${m}m';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '${h}h' : '${h}h ${r}m';
  }

  static String _clock(int minutesFromStart, {int dayStartHour = 8}) {
    final total = dayStartHour * 60 + minutesFromStart;
    final h24 = (total ~/ 60) % 24;
    final m = total % 60;
    final ampm = h24 < 12 ? 'am' : 'pm';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h12:${m.toString().padLeft(2, '0')}$ampm';
  }

  String _dateLabel(DateTime d) {
    final today = _dateOnly(DateTime.now());
    if (d == today) return 'Today';
    if (d == today.add(const Duration(days: 1))) return 'Tomorrow';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My route')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    if (_dates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.route_outlined, size: 48, color: cs.primary),
              const SizedBox(height: 16),
              Text('No jobs to route yet',
                  style: text.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('Accept some jobs and your day’s route shows up here.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    final jobs = _jobsForSelectedDate;
    final plan = _engine.optimiseJobs(jobs);
    final byId = {for (final j in jobs) j.bookingId: j};

    return Column(
      children: [
        if (_dates.length > 1) _dateChips(),
        _summary(plan),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _RouteMap(plan: plan, byId: byId, mapLoad: _mapLoad),
              const SizedBox(height: 16),
              for (var i = 0; i < plan.stops.length; i++)
                _stopCard(i + 1, plan.stops[i], byId[plan.stops[i].stop.id]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dateChips() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final d in _dates)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_dateLabel(d)),
                selected: d == _selectedDate,
                onSelected: (_) => setState(() => _selectedDate = d),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summary(RoutePlan plan) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _summaryItem('${plan.stopCount}',
              plan.stopCount == 1 ? 'stop' : 'stops', text, cs),
          _summaryItem(_dur(plan.travelMinutes), 'driving', text, cs),
          _summaryItem(plan.stops.isEmpty ? '—' : _clock(plan.finish),
              'finish', text, cs),
          if (!plan.feasible)
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: cs.error),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text('Tight',
                        style: text.labelMedium?.copyWith(color: cs.error)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryItem(
      String value, String label, TextTheme text, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: text.titleMedium),
          Text(label,
              style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _stopCard(int n, PlannedStop planned, MowerJob? job) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (job == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: cs.primary,
              child: Text('$n',
                  style: TextStyle(
                      color: cs.onPrimary, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.addressLine,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    'Arrive ~${_clock(planned.arrival)} · '
                    '${_dur(planned.stop.durationMinutes)} on site'
                    '${job.timeWindow != null && job.timeWindow != 'any' ? ' · ${job.timeWindow}' : ''}',
                    style:
                        text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Take me there',
              icon: const Icon(Icons.directions_rounded),
              onPressed: () => openDirections(
                lat: job.lat,
                lng: job.lng,
                address: job.addressLine,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteMap extends StatelessWidget {
  const _RouteMap({
    required this.plan,
    required this.byId,
    required this.mapLoad,
  });

  final RoutePlan plan;
  final Map<String, MowerJob> byId;
  final MapLoadState mapLoad;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Ordered points that actually have coordinates.
    final points = <(int, LatLng)>[];
    for (var i = 0; i < plan.stops.length; i++) {
      final job = byId[plan.stops[i].stop.id];
      if (job?.lat != null && job?.lng != null) {
        points.add((i + 1, LatLng(job!.lat!, job.lng!)));
      }
    }

    if (points.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('No map locations for these jobs'),
      );
    }

    final coords = points.map((p) => p.$2).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 280,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCameraFit: CameraFit.coordinates(
                  coordinates: coords,
                  padding: const EdgeInsets.all(56),
                  maxZoom: usingFallbackImagery ? 17 : 18,
                ),
                minZoom: 3,
                maxZoom: usingFallbackImagery ? 19 : 22,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                satelliteTileLayer(loadState: mapLoad),
                if (coords.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: coords,
                        strokeWidth: 4,
                        color: cs.primary,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    for (final (n, p) in points)
                      Marker(
                        point: p,
                        width: 30,
                        height: 30,
                        child: _NumberPin(n: n),
                      ),
                  ],
                ),
              ],
            ),
            Positioned.fill(child: MapLoadingOverlay(state: mapLoad)),
          ],
        ),
      ),
    );
  }
}

class _NumberPin extends StatelessWidget {
  const _NumberPin({required this.n});
  final int n;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: Text('$n',
          style: TextStyle(
              color: cs.onPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }
}
