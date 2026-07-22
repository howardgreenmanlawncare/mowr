import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../data/mower_repository.dart';

class MowerJobDetailScreen extends ConsumerStatefulWidget {
  const MowerJobDetailScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<MowerJobDetailScreen> createState() =>
      _MowerJobDetailScreenState();
}

class _MowerJobDetailScreenState extends ConsumerState<MowerJobDetailScreen> {
  Map<String, dynamic>? _job;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // Local step flags (the server tracks only accepted/en_route/arrived/
  // in_progress/completed; these drive the photo sub-steps).
  bool _beforeDone = false;
  bool _finishing = false;
  bool _afterDone = false;

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
      final status = job['status'] as String? ?? 'accepted';
      setState(() {
        _job = job;
        _loading = false;
        _busy = false; // clear the action spinner once the new stage is loaded
        // If already working/finished, the before photo is behind us.
        _beforeDone = status == 'in_progress' || status == 'completed';
        _finishing = false;
        _afterDone = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _busy = false;
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

  Future<Uint8List?> _takePhoto() async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 60);
    if (file == null) return null;
    return file.readAsBytes();
  }

  Future<void> _advance(String status) async {
    setState(() => _busy = true);
    try {
      await ref.read(mowerRepositoryProvider).setStatus(widget.bookingId, status);
      await _load();
    } catch (e) {
      _snack('$e');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _takeBeforePhoto() async {
    final bytes = await _takePhoto();
    if (bytes == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(mowerRepositoryProvider).uploadJobPhoto(
          bookingId: widget.bookingId, kind: 'before', bytes: bytes);
      if (mounted) setState(() => _beforeDone = true);
    } catch (e) {
      _snack('Photo failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startJob() => _advance('in_progress');

  void _finish() => setState(() => _finishing = true);

  Future<void> _takeAfterPhoto() async {
    final bytes = await _takePhoto();
    if (bytes == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(mowerRepositoryProvider).uploadJobPhoto(
          bookingId: widget.bookingId, kind: 'after', bytes: bytes);
      if (mounted) setState(() => _afterDone = true);
    } catch (e) {
      _snack('Photo failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _takePayment() async {
    setState(() => _busy = true);
    try {
      await ref.read(mowerRepositoryProvider).capturePayment(widget.bookingId);
      await _load();
      _snack('Payment taken — job complete.');
    } catch (e) {
      _snack('Payment failed: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRemeasure() async {
    await context.push('/mower/job/${widget.bookingId}/remeasure');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final status = _job?['status'] as String? ?? '';
    final canRemeasure = _job != null &&
        const {'accepted', 'en_route', 'arrived', 'in_progress'}
            .contains(status);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job'),
        actions: [
          if (canRemeasure)
            IconButton(
              icon: const Icon(Icons.straighten_rounded),
              tooltip: 'Check / re-measure',
              onPressed: _busy ? null : _openRemeasure,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _job == null
              ? Center(child: Text(_error ?? 'Job not found'))
              : _JobBody(
                  job: _job!,
                  beforeDone: _beforeDone,
                  finishing: _finishing,
                  afterDone: _afterDone,
                ),
      bottomNavigationBar:
          _loading || _job == null ? null : _buildActionBar(),
    );
  }

  Widget _buildActionBar() {
    final status = _job!['status'] as String? ?? 'accepted';
    final original = (_job!['total_amount'] as num?)?.toDouble() ?? 0;
    final revised = (_job!['revised_total'] as num?)?.toDouble();
    final approval = _job!['approval_status'] as String? ?? 'not_required';
    final total = (approval == 'declined' || revised == null) ? original : revised;

    // When a big re-measure needs the customer to sign off, we block capture.
    String? waiting;

    ({String label, IconData icon, VoidCallback onTap})? action;
    switch (status) {
      case 'accepted':
        action = (
          label: 'On my way',
          icon: Icons.directions_car_rounded,
          onTap: () => _advance('en_route'),
        );
      case 'en_route':
        action = (
          label: "I've arrived",
          icon: Icons.location_on_rounded,
          onTap: () => _advance('arrived'),
        );
      case 'arrived':
        action = _beforeDone
            ? (label: 'Start job', icon: Icons.play_arrow_rounded, onTap: _startJob)
            : (
                label: 'Take “before” photo',
                icon: Icons.photo_camera_rounded,
                onTap: _takeBeforePhoto,
              );
      case 'in_progress':
        if (!_finishing) {
          action = (
            label: 'Finish job',
            icon: Icons.flag_rounded,
            onTap: _finish,
          );
        } else if (!_afterDone) {
          action = (
            label: 'Take “after” photo',
            icon: Icons.photo_camera_rounded,
            onTap: _takeAfterPhoto,
          );
        } else if (approval == 'pending') {
          waiting = 'Waiting for customer to approve the new price';
        } else {
          action = (
            label: 'Take payment £${total.toStringAsFixed(2)}',
            icon: Icons.payments_rounded,
            onTap: _takePayment,
          );
        }
      default:
        action = null;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: waiting != null
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hourglass_top_rounded,
                      color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(waiting,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              )
            : action == null
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_rounded,
                          color: Colors.green.shade600),
                      const SizedBox(width: 8),
                      const Text('Job completed & paid',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  )
                : FilledButton.icon(
                onPressed: _busy ? null : action.onTap,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(action.icon),
                label: Text(_busy ? 'Please wait…' : action.label),
              ),
      ),
    );
  }
}

class _JobBody extends StatelessWidget {
  const _JobBody({
    required this.job,
    required this.beforeDone,
    required this.finishing,
    required this.afterDone,
  });

  final Map<String, dynamic> job;
  final bool beforeDone;
  final bool finishing;
  final bool afterDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = [job['line1'], job['city'], job['postcode']]
        .where((s) => (s as String?)?.trim().isNotEmpty ?? false)
        .join(', ');
    final lawns = (job['lawns'] as List?) ?? const [];
    final total = (job['total_amount'] as num?)?.toDouble() ?? 0;
    final revised = (job['revised_total'] as num?)?.toDouble();
    final approval = job['approval_status'] as String? ?? 'not_required';
    final accessNotes = job['access_notes'] as String?;
    final accessProvided = job['access_provided'] as bool?;
    final status = job['status'] as String? ?? 'accepted';

    // Payment + earnings.
    final paymentStatus = job['payment_status'] as String?;
    final isPaid = status == 'completed' || paymentStatus == 'captured';
    final effective = approval == 'declined' ? total : (revised ?? total);
    final captured = (job['captured_amount'] as num?)?.toDouble();
    final chargeAmount = isPaid ? (captured ?? effective) : effective;
    final commissionPct = (job['commission_pct'] as num?)?.toDouble() ?? 15;
    final feeAmount = (job['commission_amount'] as num?)?.toDouble() ??
        (chargeAmount * commissionPct / 100);
    final netAmount = (job['mower_amount'] as num?)?.toDouble() ??
        (chargeAmount - feeAmount);

    final hint = _stepHint(status);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(address,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900, height: 1.1)),
        const SizedBox(height: 6),
        Text(
            isPaid
                ? 'Paid: £${chargeAmount.toStringAsFixed(2)}'
                : 'Payment held: £${total.toStringAsFixed(2)}',
            style: TextStyle(color: Colors.grey.shade700)),
        if (revised != null) ...[
          const SizedBox(height: 2),
          Text(
            approval == 'declined'
                ? 'Re-measured £${revised.toStringAsFixed(2)} — customer declined; '
                    'original price applies'
                : 'Revised total: £${revised.toStringAsFixed(2)}',
            style: TextStyle(
              color: approval == 'pending'
                  ? Colors.orange.shade800
                  : theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 8),
        _StatusChip(status: status),
        const SizedBox(height: 14),
        _EarningsCard(
          jobTotal: chargeAmount,
          fee: feeAmount,
          net: netAmount,
          pct: commissionPct,
          paid: isPaid,
        ),
        if (approval == 'pending') ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.gpp_maybe_rounded,
                    size: 18, color: Colors.orange.shade800),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'The new price is above the auto-approve limit. Waiting for '
                    'the customer to approve before payment can be taken.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (hint != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 18, color: theme.colorScheme.onSurface),
                const SizedBox(width: 10),
                Expanded(child: Text(hint, style: const TextStyle(fontSize: 13))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('Access', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Text(
          accessProvided == true
              ? 'Access provided — you can start without the customer.'
              : 'Customer will be home to give access.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        if (accessNotes != null && accessNotes.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('“$accessNotes”',
              style: TextStyle(
                  color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 20),
        Text('Lawns', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        ...lawns.map((l) {
          final m = Map<String, dynamic>.from(l as Map);
          final area = (m['area_sqm'] as num?)?.toDouble() ?? 0;
          final perim = (m['perimeter'] as num?)?.toDouble() ?? 0;
          final height = m['grass_height'] as String? ?? 'medium';
          final edging = m['edging'] as bool? ?? false;
          return Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m['name'] as String? ?? 'Lawn',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(
                    '${area.toStringAsFixed(0)} m²  ·  '
                    '${perim.toStringAsFixed(1)} m edge  ·  '
                    '$height grass${edging ? '  ·  edging' : ''}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String? _stepHint(String status) {
    if (status == 'arrived') {
      return beforeDone
          ? 'Before photo saved. Tap “Start job” when you begin.'
          : 'Take a “before” photo of the lawn to get started.';
    }
    if (status == 'in_progress') {
      if (!finishing) return 'When you’re done mowing, tap “Finish job”.';
      if (!afterDone) return 'Take an “after” photo showing the finished lawn.';
      return 'All done — take payment to complete the job.';
    }
    return null;
  }
}

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({
    required this.jobTotal,
    required this.fee,
    required this.net,
    required this.pct,
    required this.paid,
  });

  final double jobTotal;
  final double fee;
  final double net;
  final double pct;
  final bool paid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _row(context, 'Job total', '£${jobTotal.toStringAsFixed(2)}'),
          const SizedBox(height: 6),
          _row(context, 'MOWR fee (${pct.toStringAsFixed(0)}%)',
              '−£${fee.toStringAsFixed(2)}'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Colors.grey.shade300),
          ),
          _row(
            context,
            paid ? 'You earned' : 'You’ll earn',
            '£${net.toStringAsFixed(2)}',
            strong: true,
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool strong = false}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: strong ? 15 : 13,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              color: strong ? cs.onSurface : Colors.grey.shade700,
            )),
        Text(value,
            style: TextStyle(
              fontSize: strong ? 16 : 13,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              color: strong ? cs.primary : Colors.grey.shade800,
            )),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = switch (status) {
      'accepted' => 'Accepted',
      'en_route' => 'On the way',
      'arrived' => 'Arrived',
      'in_progress' => 'In progress',
      'completed' => 'Completed',
      _ => status,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
      ),
    );
  }
}
