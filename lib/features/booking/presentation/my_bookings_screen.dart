import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/booking_repository.dart';
import '../domain/customer_booking.dart';
import 'booking_status_screen.dart';
import 'customer_nav_bar.dart';
import 'steps/account_step.dart';

/// The customer's post-booking home: every mow they've booked, newest first.
///
/// This is the entry point to [BookingStatusScreen], which is where a mower's
/// on-site re-measure gets approved. Anything awaiting a response is pulled to
/// the top and badged, because until it's answered the job cannot complete and
/// the mower cannot be paid.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  static const routePath = '/bookings';

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen> {
  bool _loading = true;
  bool _signedOut = false;
  String? _error;
  List<CustomerBooking> _bookings = const [];

  /// Top segment: 0 = Active, 1 = Completed, 2 = Cancelled.
  int _segment = 0;

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
      // RLS hides everything from a signed-out visitor, so an empty list would
      // otherwise render as "No bookings yet" — telling a returning customer
      // their bookings don't exist when they simply aren't signed in.
      if (!repo.isSignedIn) {
        if (!mounted) return;
        setState(() {
          _signedOut = true;
          _bookings = const [];
          _loading = false;
        });
        return;
      }
      final bookings = await repo.myBookings();
      if (!mounted) return;
      setState(() {
        _signedOut = false;
        _bookings = bookings;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your bookings.';
      });
    }
  }

  static const _cancelledStatuses = {'cancelled', 'expired'};

  /// The bookings for the selected segment. Within Active, anything needing a
  /// response is pulled to the top; the rest keep the server order (newest
  /// first).
  List<CustomerBooking> get _filtered {
    bool inSegment(CustomerBooking b) => switch (_segment) {
          1 => b.status == 'completed',
          2 => _cancelledStatuses.contains(b.status),
          _ => b.status != 'completed' && !_cancelledStatuses.contains(b.status),
        };
    final items = _bookings.where(inSegment).toList();
    if (_segment != 0) return items;
    final needs = items.where((b) => b.needsResponse).toList();
    final rest = items.where((b) => !b.needsResponse).toList();
    return [...needs, ...rest];
  }

  String get _emptyForSegment => switch (_segment) {
        1 => 'No completed mows yet.',
        2 => 'No cancelled bookings.',
        _ => 'Nothing active right now.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No explicit leading: when reached via `go` (confirmation, sign-in)
      // there's nothing to pop so no arrow shows, and the nav bar is the way
      // out; when reached via `push` ("Track an existing booking") the back
      // arrow appears automatically. Either way there's always an exit.
      appBar: AppBar(title: const Text('Your bookings')),
      bottomNavigationBar: const CustomerNavBar(current: CustomerTab.bookings),
      body: Column(
        children: [
          // The same segmented top menu the mower has, for Active / Completed /
          // Cancelled. Only shown once there are bookings to filter.
          if (!_loading && !_signedOut && _error == null && _bookings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Active')),
                    ButtonSegment(value: 1, label: Text('Completed')),
                    ButtonSegment(value: 2, label: Text('Cancelled')),
                  ],
                  selected: {_segment},
                  onSelectionChanged: (s) =>
                      setState(() => _segment = s.first),
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }

    if (_signedOut) {
      return _Message(
        icon: Icons.lock_outline_rounded,
        title: 'Sign in to see your bookings',
        subtitle: 'Your bookings are tied to the account you booked with. '
            'Sign in with that email to track them.',
        action: FilledButton(
          onPressed: () => context.push(
            '${AccountStepScreen.routePath}?next=${MyBookingsScreen.routePath}',
          ),
          child: const Text('Sign in'),
        ),
      );
    }

    if (_bookings.isEmpty) {
      return _Message(
        icon: Icons.grass_rounded,
        title: 'No bookings yet',
        subtitle: 'Once you book a mow it will show up here.',
        action: FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Book a mow'),
        ),
      );
    }

    final items = _filtered;
    if (items.isEmpty) {
      return _Message(
        icon: Icons.inbox_outlined,
        title: _emptyForSegment,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _BookingCard(
        booking: items[i],
        onTap: () async {
          await context.push('${BookingStatusScreen.routeBase}/${items[i].id}');
          // The detail screen may have answered a revision; refresh so the
          // badge here matches what the customer just did.
          if (mounted) _load();
        },
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.onTap});

  final CustomerBooking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final needs = booking.needsResponse;

    return Card(
      margin: EdgeInsets.zero,
      color: needs ? cs.errorContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      booking.addressLine.isEmpty
                          ? 'Your property'
                          : booking.addressLine,
                      style: text.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${bookingStatusLabel(booking.status)} · '
                '${bookingWhenLabel(booking)}',
                style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (booking.totalAmount != null) ...[
                const SizedBox(height: 4),
                Text(
                  formatMoney(booking.totalAmount, booking.currency),
                  style: text.titleMedium,
                ),
              ],
              if (needs) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.priority_high_rounded,
                        size: 20, color: cs.onErrorContainer),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Needs your approval before the mow can finish',
                        style: text.labelLarge
                            ?.copyWith(color: cs.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Inside a RefreshIndicator, so it must stay scrollable to be pullable.
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Icon(icon, size: 56, color: cs.primary),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: text.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: 24),
          Center(child: action!),
        ],
      ],
    );
  }
}

String formatMoney(double? amount, String currency) {
  if (amount == null) return '—';
  final symbol = currency == 'GBP' ? '£' : '$currency ';
  return '$symbol${amount.toStringAsFixed(2)}';
}

/// Mirrors the `bookings.status` check constraint. Keep in step with it — an
/// unmapped status falls through to the raw database string, which is not
/// something a customer should ever be shown.
String bookingStatusLabel(String status) => switch (status) {
      'draft' => 'Draft',
      'confirmed' => 'Booked',
      'broadcast' => 'Finding a mower',
      'accepted' => 'Mower assigned',
      'en_route' => 'Mower on the way',
      'arrived' => 'Mower has arrived',
      'in_progress' => 'Mowing in progress',
      'completed' => 'Completed',
      'cancelled' => 'Cancelled',
      'expired' => 'Expired',
      _ => status,
    };

String bookingWhenLabel(CustomerBooking booking) {
  if (booking.asap || booking.scheduledDate == null) return 'As soon as possible';
  final d = booking.scheduledDate!;
  final date = '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
  final window = booking.timeWindow;
  if (window == null || window == 'any') return date;
  return '$date · $window';
}
