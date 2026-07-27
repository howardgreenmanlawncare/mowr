import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../data/booking_repository.dart';
import '../domain/customer_booking.dart';
import '../domain/preferred_mowr.dart';
import 'my_bookings_screen.dart' show formatMoney, bookingStatusLabel, bookingWhenLabel;

/// One booking's status, and the place a customer answers a re-measure.
///
/// When a mower corrects the measurements on site and the new price differs by
/// more than the admin threshold, the server parks the booking on
/// `approval_status = 'pending'` and `capture-payment` refuses to take any
/// money. Nothing moves until the customer approves or declines here.
class BookingStatusScreen extends ConsumerStatefulWidget {
  const BookingStatusScreen({super.key, required this.bookingId});

  final String bookingId;

  /// Routes are '$routeBase/:id'.
  static const routeBase = '/bookings';

  @override
  ConsumerState<BookingStatusScreen> createState() =>
      _BookingStatusScreenState();
}

class _BookingStatusScreenState extends ConsumerState<BookingStatusScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  CustomerBooking? _booking;
  Map<String, dynamic>? _eta;
  List<MowrAvailability> _preferred = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(bookingRepositoryProvider);
      final booking = await repo.booking(widget.bookingId);
      // Best-effort rough ETA for active, mower-assigned bookings.
      Map<String, dynamic>? eta;
      const active = {'accepted', 'en_route', 'arrived', 'in_progress'};
      if (active.contains(booking.status)) {
        try {
          eta = await repo.bookingEta(widget.bookingId);
        } catch (_) {}
      }
      // For a reschedulable booking, offer to move it to a preferred mowr's
      // next free date.
      List<MowrAvailability> preferred = const [];
      if (const {'confirmed', 'broadcast', 'accepted'}.contains(booking.status)) {
        try {
          preferred = await repo.preferredMowrAvailability();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _eta = eta;
        _preferred = preferred;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this booking.';
      });
    }
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _respond({required bool approve}) async {
    final booking = _booking;
    if (booking == null) return;

    final confirmed = await _confirm(booking, approve: approve);
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(bookingRepositoryProvider)
          .respondToRevision(booking.id, approve: approve);
      _snack(approve
          ? 'Approved — your mower can finish the job.'
          : 'Declined. We will be in touch about the difference.');
      await _load();
    } catch (e) {
      _snack('Could not send your answer. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitReview(int rating, String? comment) async {
    final booking = _booking;
    if (booking == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(bookingRepositoryProvider)
          .submitReview(booking.id, rating, comment: comment);
      _snack('Thanks for rating your mow!');
      await _load();
    } catch (e) {
      _snack('Could not submit your rating. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPreferred() async {
    final booking = _booking;
    if (booking == null) return;
    setState(() => _busy = true);
    try {
      final name =
          await ref.read(bookingRepositoryProvider).addPreferredMowr(booking.id);
      _snack('$name added to your preferred mowrs.');
    } catch (e) {
      _snack('Could not add to preferred. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rescheduleTo(MowrAvailability m) async {
    final booking = _booking;
    if (booking == null || m.nextAvailable == null) return;
    final when = m.nextAvailable!;
    final label = '${when.day}/${when.month}/${when.year}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move this booking?'),
        content: Text(
          'Reschedule to $label, the next date ${m.fullName} is free. '
          'We\'ll aim to send this job to your preferred mowr.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Move')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(bookingRepositoryProvider)
          .rescheduleBooking(booking.id, when);
      _snack('Moved to $label.');
      await _load();
    } catch (e) {
      _snack('Could not reschedule. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(CustomerBooking booking, {required bool approve}) {
    final revised = formatMoney(booking.revisedTotal, booking.currency);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approve the new price?' : 'Decline the change?'),
        content: Text(
          approve
              ? 'You will be charged $revised instead of the price you booked. '
                  'This happens once your mow is finished.'
              : 'Your mow will not be completed at the new price. We will '
                  'contact you to sort out the difference.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Approve' : 'Decline'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your booking')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final booking = _booking;
    if (booking == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text(
            _error ?? 'Could not load this booking.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton(
              onPressed: _load,
              child: const Text('Try again'),
            ),
          ),
        ],
      );
    }

    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(20),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Text(
          booking.addressLine.isEmpty ? 'Your property' : booking.addressLine,
          style: text.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${bookingStatusLabel(booking.status)} · '
          '${bookingWhenLabel(booking)}',
          style: text.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        if (booking.status != 'cancelled' && booking.status != 'expired') ...[
          if (_eta != null) ...[
            _EtaBanner(eta: _eta!),
            const SizedBox(height: 12),
          ],
          _StatusTimeline(status: booking.status),
          const SizedBox(height: 24),
          if (const {'en_route', 'arrived', 'in_progress'}
              .contains(booking.status)) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/chat/${booking.id}'
                    '?title=${Uri.encodeComponent('Your mower')}'),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Message your mower'),
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (_preferred.isNotEmpty &&
              const {'confirmed', 'broadcast', 'accepted'}
                  .contains(booking.status)) ...[
            _PreferredAvailabilityCard(
              mowrs: _preferred,
              busy: _busy,
              onReschedule: _rescheduleTo,
            ),
            const SizedBox(height: 20),
          ],
        ],
        if (booking.needsResponse) ...[
          _RevisionCard(
            booking: booking,
            busy: _busy,
            onApprove: () => _respond(approve: true),
            onDecline: () => _respond(approve: false),
          ),
          const SizedBox(height: 20),
        ],
        if (booking.isCompleted) ...[
          const SizedBox(height: 20),
          _ReviewCard(
            booking: booking,
            busy: _busy,
            onSubmit: _submitReview,
          ),
          const SizedBox(height: 20),
          _PreferredAddCard(busy: _busy, onAdd: _addPreferred),
        ],
        _PriceCard(booking: booking),
      ],
    );
  }
}

/// Rate a finished job. Shows the star picker until the customer has rated,
/// then the rating they left. A mower's average rating feeds their commission
/// tier, so this is where that data comes from.
class _ReviewCard extends StatefulWidget {
  const _ReviewCard({
    required this.booking,
    required this.busy,
    required this.onSubmit,
  });

  final CustomerBooking booking;
  final bool busy;
  final Future<void> Function(int rating, String? comment) onSubmit;

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  int _rating = 0;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final already = widget.booking.myRating;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(already != null ? 'Your rating' : 'How was your mow?',
                style: text.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: List.generate(5, (i) {
                final n = i + 1;
                final filled = already != null ? n <= already : n <= _rating;
                return IconButton(
                  onPressed: already != null || widget.busy
                      ? null
                      : () => setState(() => _rating = n),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: Icon(
                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                    color: filled ? cs.primary : cs.onSurfaceVariant,
                    size: 34,
                  ),
                );
              }),
            ),
            if (already == null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _comment,
                enabled: !widget.busy,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Add a note (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_rating == 0 || widget.busy)
                      ? null
                      : () => widget.onSubmit(
                            _rating,
                            _comment.text.trim().isEmpty
                                ? null
                                : _comment.text.trim(),
                          ),
                  child: Text(widget.busy ? 'Sending…' : 'Submit rating'),
                ),
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text('Thanks for your feedback.',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The approve/decline card. Only shown while the booking is actually waiting
/// — once answered, the price card below reflects the outcome.
class _RevisionCard extends StatelessWidget {
  const _RevisionCard({
    required this.booking,
    required this.busy,
    required this.onApprove,
    required this.onDecline,
  });

  final CustomerBooking booking;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final delta = booking.revisionDelta;
    final costsMore = (delta ?? 0) > 0;

    return Card(
      margin: EdgeInsets.zero,
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.straighten_rounded, color: cs.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your mower re-measured the lawn',
                    style:
                        text.titleMedium?.copyWith(color: cs.onErrorContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              costsMore
                  ? 'The lawn is bigger than the size your price was based on, '
                      'so the job costs more than you booked.'
                  : 'The lawn is smaller than the size your price was based '
                      'on, so the job costs less than you booked.',
              style: text.bodyMedium?.copyWith(color: cs.onErrorContainer),
            ),
            const SizedBox(height: 16),
            _Row(
              label: 'You booked',
              value: formatMoney(booking.totalAmount, booking.currency),
              color: cs.onErrorContainer,
            ),
            _Row(
              label: 'New price',
              value: formatMoney(booking.revisedTotal, booking.currency),
              color: cs.onErrorContainer,
              emphasise: true,
            ),
            if (delta != null)
              _Row(
                label: costsMore ? 'Extra' : 'Saving',
                value: formatMoney(delta.abs(), booking.currency),
                color: cs.onErrorContainer,
              ),
            const SizedBox(height: 16),
            Text(
              'Nothing has been charged yet. Your mower cannot finish the job '
              'until you answer.',
              style: text.bodySmall?.copyWith(color: cs.onErrorContainer),
            ),
            const SizedBox(height: 16),
            if (busy)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDecline,
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onApprove,
                      child: const Text('Approve'),
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

/// A rough arrival estimate, sourced from the day's plan (booking_eta RPC).
class _EtaBanner extends StatelessWidget {
  const _EtaBanner({required this.eta});

  final Map<String, dynamic> eta;

  String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ap = t.hour < 12 ? 'am' : 'pm';
    return '$h:${t.minute.toString().padLeft(2, '0')}$ap';
  }

  String _line() {
    final underway = eta['underway'] == true;
    final mins = (eta['minutes_away'] as num?)?.toInt() ?? 0;
    final iso = eta['eta'] as String?;
    final t = iso != null ? DateTime.tryParse(iso)?.toLocal() : null;
    if (underway) {
      if (mins <= 2) return 'Arriving any moment';
      if (mins < 90) return 'Arriving in about $mins min';
    }
    return t != null ? 'Expected around ${_clock(t)}' : 'On its way';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.greenPale,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 18, color: AppColors.greenDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_line(),
                style: text.titleSmall?.copyWith(color: AppColors.greenDark)),
          ),
          Text('Estimate',
              style: text.labelSmall?.copyWith(color: AppColors.greenDark)),
        ],
      ),
    );
  }
}

/// A delivery-style vertical tracker of the job's live stage, driven by the
/// booking status. Gives the customer the "your mower is on the way" feel.
class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status});

  final String status;

  static const _stages = [
    'Booked',
    'Mower assigned',
    'On the way',
    'Arrived',
    'Mowing',
    'Done',
  ];

  int get _active => switch (status) {
        'accepted' => 1,
        'en_route' => 2,
        'arrived' => 3,
        'in_progress' => 4,
        'completed' => 5,
        _ => 0, // draft / confirmed / broadcast
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _stages.length; i++) _row(context, i),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int i) {
    final text = Theme.of(context).textTheme;
    final complete = _active == 5;
    final done = i < _active || complete;
    final current = i == _active && !complete;
    final isLast = i == _stages.length - 1;
    final on = done || current;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? AppColors.green : AppColors.surface,
                  border: Border.all(
                      color: on ? AppColors.green : AppColors.border, width: 2),
                ),
                child: done
                    ? const Icon(Icons.check, size: 11, color: Colors.white)
                    : current
                        ? Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                  color: AppColors.green,
                                  shape: BoxShape.circle),
                            ),
                          )
                        : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: i < _active ? AppColors.green : AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Padding(
            padding: EdgeInsets.only(bottom: isLast ? 12 : 18, top: 0),
            child: Text(
              _stages[i],
              style: on
                  ? text.titleSmall
                  : text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.booking});

  final CustomerBooking booking;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    // Once the job is done the captured amount is the truth; before that, an
    // approved revision is what will be charged, otherwise the booked price.
    final settled = booking.capturedAmount;
    final approved = booking.approvalStatus == RevisionApproval.approved
        ? booking.revisedTotal
        : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Price', style: text.titleMedium),
            const SizedBox(height: 12),
            _Row(
              label: 'Booked',
              value: formatMoney(booking.totalAmount, booking.currency),
            ),
            if (approved != null)
              _Row(
                label: 'Approved after re-measure',
                value: formatMoney(approved, booking.currency),
              ),
            if (booking.approvalStatus == RevisionApproval.declined)
              _Row(
                label: 'Re-measure declined',
                value: formatMoney(booking.revisedTotal, booking.currency),
              ),
            if (settled != null) ...[
              const Divider(height: 24),
              _Row(
                label: 'Charged',
                value: formatMoney(settled, booking.currency),
                emphasise: true,
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                'Payment is taken only after your mow is completed.',
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
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
    this.color,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final Color? color;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = emphasise ? text.titleMedium : text.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style?.copyWith(color: color)),
          Text(value, style: style?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Shown on a completed booking — add the mowr who did it to the preferred list.
class _PreferredAddCard extends StatelessWidget {
  const _PreferredAddCard({required this.busy, required this.onAdd});

  final bool busy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Liked your mowr?', style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Add them to your preferred list and we\'ll prioritise them for '
              'your future bookings.',
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onAdd,
                icon: const Icon(Icons.favorite_border_rounded),
                label: const Text('Add to preferred mowrs'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown on an upcoming booking — each preferred mowr's next free date, with a
/// one-tap reschedule onto it.
class _PreferredAvailabilityCard extends StatelessWidget {
  const _PreferredAvailabilityCard({
    required this.mowrs,
    required this.busy,
    required this.onReschedule,
  });

  final List<MowrAvailability> mowrs;
  final bool busy;
  final void Function(MowrAvailability) onReschedule;

  static const _mon = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String _d(DateTime x) => '${x.day} ${_mon[x.month - 1]}';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your preferred mowrs', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'We aim to send this job to a preferred mowr. Here\'s when each is '
              'next free — move your booking to suit.',
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            ...mowrs.map((m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.fullName, style: text.bodyLarge),
                            Text(
                              m.nextAvailable == null
                                  ? 'No free date in the next few weeks'
                                  : 'Next free: ${_d(m.nextAvailable!)}',
                              style: text.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (m.nextAvailable != null)
                        TextButton(
                          onPressed: busy ? null : () => onReschedule(m),
                          child: const Text('Move here'),
                        ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
