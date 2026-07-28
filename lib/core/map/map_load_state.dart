import 'dart:async';

import 'package:flutter/material.dart';

/// Tracks whether a map's satellite tiles have actually painted.
///
/// `FlutterMap` renders its grey tile grid immediately and fills imagery in
/// asynchronously, so an un-covered map reads as a broken grey box for the
/// second or two before tiles arrive. Screens pair this with
/// [MapLoadingOverlay] to cover that gap.
///
/// Ready-ness is deliberately fuzzy: the first tile to finish starts a short
/// settle timer that each subsequent tile restarts, so the overlay lifts once
/// tiles have *stopped* arriving rather than when the first one lands (which
/// would reveal a half-filled grid).
class MapLoadState extends ChangeNotifier {
  MapLoadState({
    this.settle = const Duration(milliseconds: 400),
    this.timeout = const Duration(seconds: 10),
  }) {
    // A dead network must not trap the user behind a permanent spinner — show
    // them whatever the map managed to render and let them carry on.
    _timeoutTimer = Timer(timeout, () => _markReady(viaTimeout: true));
  }

  /// How long tile loads must be quiet before the map counts as ready.
  final Duration settle;

  /// Hard cap after which the overlay lifts regardless.
  final Duration timeout;

  bool _ready = false;
  bool get ready => _ready;

  /// True once the timeout fired rather than tiles settling — the map may be
  /// partly or entirely blank.
  bool _timedOut = false;
  bool get timedOut => _timedOut;

  Timer? _settleTimer;
  Timer? _timeoutTimer;
  bool _disposed = false;

  /// Called from the tile layer each time a tile finishes loading.
  void reportTileLoaded() {
    if (_ready || _disposed) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(settle, _markReady);
  }

  void _markReady({bool viaTimeout = false}) {
    if (_ready || _disposed) return;
    _timedOut = viaTimeout;
    _ready = true;
    _settleTimer?.cancel();
    _timeoutTimer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _settleTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }
}

/// Covers a map until its tiles have loaded, then fades away.
///
/// Place as the last child of a `Stack` wrapping the `FlutterMap`. Uses
/// [IgnorePointer] once hidden so it never swallows taps meant for the map —
/// which matters on the lawn-drawing screens.
class MapLoadingOverlay extends StatelessWidget {
  const MapLoadingOverlay({
    super.key,
    required this.state,
    this.message = 'Loading map…',
  });

  final MapLoadState state;
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return IgnorePointer(
          ignoring: state.ready,
          child: AnimatedOpacity(
            opacity: state.ready ? 0 : 1,
            duration: const Duration(milliseconds: 250),
            child: ColoredBox(
              // Opaque: the point is to hide the grey tile grid entirely.
              color: cs.surface,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      style: text.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
