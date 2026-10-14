import 'dart:async';
import 'dart:developer';

/// Local timing only. Arguments must contain identifiers/counters, never page
/// input, record contents, credentials, or exception messages.
class UiLoadSample {
  const UiLoadSample(this.name, this.elapsed, this.arguments);
  final String name;
  final Duration elapsed;
  final Map<String, Object> arguments;
}

class UiLoadTrace {
  static const enabled = bool.fromEnvironment(
    'XUDIAN_TRACE_UI',
    defaultValue: !bool.fromEnvironment('dart.vm.product'),
  );
  static const _observerKey = #uiLoadTimingObserver;

  /// A scoped observer supports repeatable benchmarks without a global buffer.
  static T observe<T>(
    T Function() body,
    void Function(UiLoadSample) onSample,
  ) => runZoned(body, zoneValues: {_observerKey: onSample});

  static UiLoadSpan? start(
    String name, {
    Map<String, Object> arguments = const {},
  }) {
    final observer = Zone.current[_observerKey] as void Function(UiLoadSample)?;
    if (!enabled && observer == null) return null;
    return UiLoadSpan._(name, arguments, observer);
  }

  static Future<T> run<T>(
    String name,
    Future<T> Function() body, {
    Map<String, Object> arguments = const {},
  }) {
    final span = start(name, arguments: arguments);
    if (span == null) return body();
    return _run(body, span);
  }

  static Future<T> _run<T>(Future<T> Function() body, UiLoadSpan span) async {
    var outcome = 'ok';
    try {
      return await body();
    } catch (_) {
      outcome = 'error';
      rethrow;
    } finally {
      span.finish(arguments: {'outcome': outcome});
    }
  }

  static void instant(
    String name, {
    Map<String, Object> arguments = const {},
  }) => start(name, arguments: arguments)?.finish();
}

class UiLoadSpan {
  UiLoadSpan._(this.name, Map<String, Object> arguments, this._observer)
    : _arguments = Map.unmodifiable(arguments),
      _task = UiLoadTrace.enabled
          ? TimelineTask(filterKey: 'xudian.ui')
          : null {
    _task?.start(name, arguments: Map<String, Object>.of(_arguments));
  }

  final String name;
  final Map<String, Object> _arguments;
  final void Function(UiLoadSample)? _observer;
  final TimelineTask? _task;
  final Stopwatch _watch = Stopwatch()..start();
  bool _finished = false;

  void finish({Map<String, Object> arguments = const {}}) {
    if (_finished) return;
    _finished = true;
    _watch.stop();
    final combined = Map<String, Object>.unmodifiable({
      ..._arguments,
      ...arguments,
    });
    // TimelineTask adds its filter key to this map in some Dart runtimes.
    _task?.finish(arguments: Map<String, Object>.of(combined));
    try {
      _observer?.call(UiLoadSample(name, _watch.elapsed, combined));
    } catch (_) {
      // A diagnostic observer must never change application behavior.
    }
  }
}
