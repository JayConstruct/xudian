import 'dart:async';

/// Bounded idle backoff for the message-only native bridge.
/// Every Dart-to-JavaScript message wakes the scheduler, including host replies.
class WorkerPollScheduler {
  WorkerPollScheduler({required this.drain, required this.hasPending});

  final bool Function() drain;
  final bool Function() hasPending;
  // Invocations may post from a different zone than worker construction (for
  // example Flutter's fake widget clock). Keep the native pump in its owner zone.
  final Zone _zone = Zone.current;
  static const minimum = Duration(milliseconds: 8);
  static const maximumBusy = Duration(milliseconds: 32);
  static const maximumIdle = Duration(milliseconds: 64);
  Timer? _timer;
  Duration _delay = minimum;
  bool _closed = false;

  void wake() {
    if (_closed) return;
    // Repeated posts must not postpone an already imminent poll indefinitely.
    if (_timer?.isActive == true && _delay == minimum) return;
    _timer?.cancel();
    _delay = minimum;
    _schedule();
  }

  void _schedule() {
    _timer = _zone.run(
      () => Timer(_delay, () {
        _timer = null;
        final received = drain();
        // A host callback can synchronously post while draining.
        if (_closed || _timer != null) return;
        final maximum = hasPending() ? maximumBusy : maximumIdle;
        _delay = received
            ? minimum
            : Duration(
                microseconds: (_delay.inMicroseconds * 2).clamp(
                  minimum.inMicroseconds,
                  maximum.inMicroseconds,
                ),
              );
        _schedule();
      }),
    );
  }

  void close() {
    _closed = true;
    _timer?.cancel();
  }
}
