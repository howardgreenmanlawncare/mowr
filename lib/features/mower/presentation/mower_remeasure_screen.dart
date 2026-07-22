import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../booking/domain/geo_point.dart';
import '../../booking/domain/lawn_geometry.dart';
import '../data/mower_repository.dart';
import 'mower_lawn_draw_screen.dart';

/// On-site re-measure. The mower re-traces (or hand-enters) each lawn; on submit
/// the server reprices from pricing_rules and tells us whether the change is
/// automatic or needs customer approval.
class MowerRemeasureScreen extends ConsumerStatefulWidget {
  const MowerRemeasureScreen({super.key, required this.bookingId});

  final String bookingId;

  static String routePathFor(String id) => '/mower/job/$id/remeasure';

  @override
  ConsumerState<MowerRemeasureScreen> createState() =>
      _MowerRemeasureScreenState();
}

class _EditableLawn {
  _EditableLawn({
    required this.lawnAreaId,
    required this.name,
    required this.origArea,
    required this.origPerimeter,
    required this.area,
    required this.perimeter,
  });

  final String lawnAreaId;
  final String name;
  final double origArea;
  final double origPerimeter;
  double area;
  double perimeter;

  bool get changed =>
      (area - origArea).abs() > 0.5 || (perimeter - origPerimeter).abs() > 0.5;
}

class _MowerRemeasureScreenState extends ConsumerState<MowerRemeasureScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  double? _lat;
  double? _lng;
  List<_EditableLawn> _lawns = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final job =
          await ref.read(mowerRepositoryProvider).jobDetail(widget.bookingId);
      if (!mounted) return;
      double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
      final rawLawns = (job['lawns'] as List?) ?? const [];
      final lawns = rawLawns.map((l) {
        final m = Map<String, dynamic>.from(l as Map);
        final origArea = d(m['area_sqm']);
        final origPerim = d(m['perimeter']);
        return _EditableLawn(
          lawnAreaId: m['lawn_area_id'] as String,
          name: m['name'] as String? ?? 'Lawn',
          origArea: origArea,
          origPerimeter: origPerim,
          // Seed from any existing revision so a re-open shows prior edits.
          area: m['revised_area_sqm'] == null ? origArea : d(m['revised_area_sqm']),
          perimeter: m['revised_perimeter'] == null
              ? origPerim
              : d(m['revised_perimeter']),
        );
      }).toList();
      setState(() {
        _lat = (job['lat'] as num?)?.toDouble();
        _lng = (job['lng'] as num?)?.toDouble();
        _lawns = lawns;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this job.';
      });
    }
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _redraw(_EditableLawn lawn) async {
    final centre = GeoPoint(_lat ?? 52.5, _lng ?? -1.5);
    final boundary = await Navigator.of(context).push<List<GeoPoint>>(
      MaterialPageRoute(
        builder: (_) => MowerLawnDrawScreen(centre: centre, lawnName: lawn.name),
      ),
    );
    if (boundary == null || boundary.length < 3 || !mounted) return;
    setState(() {
      lawn.area = areaSquareMetres(boundary);
      lawn.perimeter = perimeterMetres(boundary);
    });
  }

  Future<void> _enterManually(_EditableLawn lawn) async {
    final result = await showDialog<(double, double)>(
      context: context,
      builder: (ctx) => _ManualEntryDialog(
        name: lawn.name,
        area: lawn.area,
        perimeter: lawn.perimeter,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      lawn.area = result.$1;
      lawn.perimeter = result.$2;
    });
  }

  Future<void> _submit({required String mode}) async {
    setState(() => _busy = true);
    try {
      final payload = _lawns
          .map((l) => {
                'lawn_area_id': l.lawnAreaId,
                'area_sqm': double.parse(l.area.toStringAsFixed(2)),
                'perimeter': double.parse(l.perimeter.toStringAsFixed(2)),
              })
          .toList();
      final res = await ref
          .read(mowerRepositoryProvider)
          .reviseMeasurements(widget.bookingId, payload, mode: mode);
      if (!mounted) return;
      await _showResult(res);
      if (mounted) context.pop();
    } catch (e) {
      _snack('Could not save: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showResult(Map<String, dynamic> res) async {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    final mode = res['mode'] as String? ?? 'reprice';
    final original = d(res['original_total']);
    final revised = d(res['revised_total']);
    final delta = d(res['delta']);
    final pct = d(res['pct']);
    final threshold = d(res['threshold_pct']);
    final status = res['approval_status'] as String? ?? 'not_required';
    final pending = status == 'pending';

    String money(double v) => '£${v.toStringAsFixed(2)}';

    final IconData icon;
    final Color color;
    final String title;
    final String bodyText;
    if (mode == 'next_time') {
      icon = Icons.event_repeat_rounded;
      color = Colors.green.shade600;
      title = 'Saved for next time';
      bodyText = 'This visit stays at ${money(original)} as booked. The '
          'corrected size is saved to the property, so future bookings will '
          'price at about ${money(revised)}.';
    } else if (pending) {
      icon = Icons.gpp_maybe_rounded;
      color = Colors.orange.shade700;
      title = 'Customer approval needed';
      bodyText = 'The new price ${money(revised)} is ${money(delta)} '
          '(${pct.toStringAsFixed(1)}%) more than the ${money(original)} '
          'held — above the ${threshold.toStringAsFixed(0)}% limit. '
          'The customer will be asked to approve before you can take payment.';
    } else if (delta <= 0) {
      icon = Icons.check_circle_rounded;
      color = Colors.green.shade600;
      title = 'Price updated';
      bodyText = 'New price ${money(revised)} (was ${money(original)}). '
          'The customer will be charged the lower amount.';
    } else {
      icon = Icons.check_circle_rounded;
      color = Colors.green.shade600;
      title = 'Price updated';
      bodyText = 'New price ${money(revised)} (+${money(delta)}, '
          '${pct.toStringAsFixed(1)}%). Within the '
          '${threshold.toStringAsFixed(0)}% limit — the extra will be added '
          'automatically when you take payment.';
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 40),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 8),
              Text(bodyText, style: TextStyle(color: Colors.grey.shade800)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final anyChanged = _lawns.any((l) => l.changed);
    return Scaffold(
      appBar: AppBar(title: const Text('Check / re-measure')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lawns.isEmpty
              ? Center(child: Text(_error ?? 'No lawns to measure'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Text(
                      'Re-trace any lawn that doesn’t match what’s on '
                      'the ground. The price is recalculated when you submit.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),
                    for (final lawn in _lawns) _LawnEditCard(
                      lawn: lawn,
                      onRedraw: () => _redraw(lawn),
                      onManual: () => _enterManually(lawn),
                    ),
                  ],
                ),
      bottomNavigationBar: _loading || _lawns.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _submit(mode: 'reprice'),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.calculate_rounded),
                      label: Text(_busy
                          ? 'Saving…'
                          : anyChanged
                              ? 'Update price for this visit'
                              : 'Confirm measurements'),
                    ),
                    if (anyChanged && !_busy) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: () => _submit(mode: 'next_time'),
                        icon: const Icon(Icons.event_repeat_rounded, size: 18),
                        label: const Text('Charge as booked · fix for next time'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _LawnEditCard extends StatelessWidget {
  const _LawnEditCard({
    required this.lawn,
    required this.onRedraw,
    required this.onManual,
  });

  final _EditableLawn lawn;
  final VoidCallback onRedraw;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(lawn.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                if (lawn.changed)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Changed',
                        style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                            fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _row('Booked', lawn.origArea, lawn.origPerimeter, Colors.grey.shade600),
            const SizedBox(height: 2),
            _row(
              'Now',
              lawn.area,
              lawn.perimeter,
              lawn.changed ? cs.primary : Colors.grey.shade600,
              bold: lawn.changed,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRedraw,
                    icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
                    label: const Text('Re-draw'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onManual,
                    icon: const Icon(Icons.keyboard_rounded, size: 18),
                    label: const Text('Type in'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, double area, double perim, Color color,
      {bool bold = false}) {
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ),
        Text(
          '${area.toStringAsFixed(0)} m²  ·  '
          '${perim.toStringAsFixed(1)} m edge',
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ManualEntryDialog extends StatefulWidget {
  const _ManualEntryDialog({
    required this.name,
    required this.area,
    required this.perimeter,
  });

  final String name;
  final double area;
  final double perimeter;

  @override
  State<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<_ManualEntryDialog> {
  late final TextEditingController _area =
      TextEditingController(text: widget.area.toStringAsFixed(0));
  late final TextEditingController _perim =
      TextEditingController(text: widget.perimeter.toStringAsFixed(1));

  @override
  void dispose() {
    _area.dispose();
    _perim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Measurements — ${widget.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _area,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Area',
              suffixText: 'm²',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _perim,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Perimeter (edge)',
              suffixText: 'm',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final a = double.tryParse(_area.text.trim());
            final p = double.tryParse(_perim.text.trim());
            if (a == null || a <= 0 || p == null || p < 0) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Enter a valid area and perimeter.'),
              ));
              return;
            }
            Navigator.pop(context, (a, p));
          },
          child: const Text('Use these'),
        ),
      ],
    );
  }
}
