import 'dart:async';

import 'package:flutter/services.dart';

import 'ui_load_trace.dart';

final startupTraceCapture = StartupTraceCapture();

/// Opt-in, bounded startup aggregates. No record, form or bridge arguments.
class StartupTraceCapture {
  StartupTraceCapture({
    this.enabled = const bool.fromEnvironment('XUDIAN_CAPTURE_STARTUP'),
    Future<void> Function(Map<String, Object>)? report,
  }) : _report = report ?? _reportAndroid;

  final bool enabled;
  final Future<void> Function(Map<String, Object>) _report;
  final _phases = <String, _PhaseTotal>{};
  bool _finished = false;
  static const maximumGroups = 96;
  static const _allowed = {
    'app.firstFrame',
    'app.workspaceReady',
    'database.open',
    'database.ready',
    'host.restore',
    'host.initialize',
    'host.restore.packages',
    'host.defaults.metadata',
    'host.package.verify',
    'host.bundle.verify',
    'host.worker.load',
    'shell.restore',
    'page.queue',
    'page.execute',
    'page.firstFrame',
  };

  T run<T>(T Function() body) =>
      enabled ? UiLoadTrace.observe(body, _observe) : body();

  void _observe(UiLoadSample sample) {
    if (_finished || !_allowed.contains(sample.name)) return;
    final module = sample.arguments['moduleId'];
    final moduleId =
        module is String &&
            RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9_-]*)+$').hasMatch(module)
        ? module
        : '';
    final worker = sample.arguments['worker'];
    final workerId = worker == 'computation' || worker == 'workflow'
        ? worker as String
        : '';
    final key = '${sample.name}|$moduleId|$workerId';
    if (!_phases.containsKey(key) && _phases.length >= maximumGroups) return;
    final total = _phases.putIfAbsent(
      key,
      () => _PhaseTotal(sample.name, moduleId, workerId),
    );
    total.count++;
    total.microseconds += sample.elapsed.inMicroseconds;
  }

  void finish(String outcome) {
    if (!enabled || _finished) return;
    _finished = true;
    final payload = <String, Object>{
      'outcome': {'ready', 'restoreError', 'noWorkspace'}.contains(outcome)
          ? outcome
          : 'unavailable',
      'phases': _phases.values.map((value) => value.toJson()).toList(),
    };
    _phases.clear();
    unawaited(_send(payload));
  }

  Future<void> _send(Map<String, Object> payload) async {
    try {
      await _report(payload);
    } catch (_) {
      // Sampling does not change startup or recovery behavior.
    }
  }

  static Future<void> _reportAndroid(Map<String, Object> payload) =>
      const MethodChannel('xudian.host/startup')
          .invokeMethod<void>('startupTimings', payload);
}

class _PhaseTotal {
  _PhaseTotal(this.name, this.moduleId, this.worker);
  final String name, moduleId, worker;
  int count = 0, microseconds = 0;
  Map<String, Object> toJson() => {
    'name': name,
    'count': count,
    'elapsedUs': microseconds,
    if (moduleId.isNotEmpty) 'moduleId': moduleId,
    if (worker.isNotEmpty) 'worker': worker,
  };
}
