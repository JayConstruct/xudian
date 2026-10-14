import 'dart:async';
import 'dart:collection';

/// One workflow worker stays serial. Foreground calls overtake only queued
/// speculative reads; a running script is never interrupted or re-entered.
class PageWorkflowQueue {
  final _foreground = Queue<_PageWork>();
  final _speculative = Queue<_PageWork>();
  Future<void> _gate = Future.value();
  Completer<void>? _idle;
  bool _draining = false;
  bool _closed = false;

  Future<void> get idle => _idle?.future ?? _gate;

  /// Retains the host's workflow barrier used for deterministic preparation.
  void waitFor(Future<void> gate) => _gate = gate;

  Future<Object?> run(
    Future<Object?> Function() action, {
    bool speculative = false,
  }) {
    if (_closed) return Future.value(null);
    final work = _PageWork(action);
    (speculative ? _speculative : _foreground).add(work);
    _idle ??= Completer<void>();
    if (!_draining) {
      _draining = true;
      scheduleMicrotask(_drain);
    }
    return work.result.future;
  }

  Future<void> _drain() async {
    try {
      while (!_closed && (_foreground.isNotEmpty || _speculative.isNotEmpty)) {
        final gate = _gate;
        try {
          await gate;
        } catch (error, stack) {
          _failPending(error, stack);
          if (identical(gate, _gate)) _gate = Future.value();
          continue;
        }
        if (_closed) break;
        // A newer barrier may have been installed while awaiting this one.
        if (!identical(gate, _gate)) continue;
        final work = (_foreground.isNotEmpty ? _foreground : _speculative)
            .removeFirst();
        try {
          work.result.complete(await work.action());
        } catch (error, stack) {
          work.result.completeError(error, stack);
        }
      }
    } finally {
      _draining = false;
      if (_idle?.isCompleted == false) _idle!.complete();
      _idle = null;
    }
  }

  void _failPending(Object error, StackTrace stack) {
    for (final queue in [_foreground, _speculative]) {
      while (queue.isNotEmpty) {
        queue.removeFirst().result.completeError(error, stack);
      }
    }
  }

  void close() {
    _closed = true;
    if (_idle?.isCompleted == false) _idle!.complete();
    for (final queue in [_foreground, _speculative]) {
      while (queue.isNotEmpty) {
        queue.removeFirst().result.complete(null);
      }
    }
  }
}

class _PageWork {
  _PageWork(this.action);
  final Future<Object?> Function() action;
  final result = Completer<Object?>();
}
