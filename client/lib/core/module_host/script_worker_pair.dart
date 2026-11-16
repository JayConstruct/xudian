import 'package:xquickjs/xquickjs.dart';

import '../performance/ui_load_trace.dart';

/// Owns loading, restart deduplication and shutdown of a module's two engines.
/// Lazy workflow startup is opt-in: existing ESM initialization stays unchanged.
class ScriptWorkerPair {
  ScriptWorkerPair({
    required this.moduleId,
    required this.entryPoint,
    required this.create,
    required this.beforeWorkflowRestart,
  });

  final String moduleId, entryPoint;
  final JavaScriptWorker Function(bool workflow) create;
  final Future<void> Function() beforeWorkflowRestart;
  final _workers = <bool, JavaScriptWorker>{};
  final _loading = <bool, Future<JavaScriptWorker>>{};
  bool _stopped = false;

  bool get hasBoth => _workers.length == 2;
  JavaScriptWorker current({bool workflow = false}) =>
      _workers[workflow] ?? (throw StateError('Worker has not started'));

  Future<void> initialize({required bool lazyWorkflow}) async {
    await Future.wait([ready(), if (!lazyWorkflow) ready(workflow: true)]);
  }

  Future<JavaScriptWorker> ready({bool workflow = false}) {
    if (_stopped) throw StateError('Module stopped');
    final loading = _loading[workflow];
    if (loading != null) return loading;
    final worker = _workers[workflow];
    if (worker != null && !worker.closed) return Future.value(worker);
    final next = _load(workflow);
    _loading[workflow] = next;
    return next;
  }

  Future<JavaScriptWorker> _load(bool workflow) async {
    // Yield before loading so ready() has registered its deduplication future,
    // including when a synchronous factory/load failure occurs.
    await Future<void>.value();
    try {
      if (workflow && _workers.containsKey(true)) {
        await beforeWorkflowRestart();
      }
      if (_stopped) throw StateError('Module stopped');
      final worker = create(workflow);
      _workers[workflow] = worker;
      try {
        await UiLoadTrace.run(
          'host.worker.load',
          () => worker.load(entryPoint),
          arguments: {
            'moduleId': moduleId,
            'worker': workflow ? 'workflow' : 'computation',
          },
        );
        if (_stopped) throw StateError('Module stopped');
        return worker;
      } catch (_) {
        worker.close();
        rethrow;
      }
    } finally {
      _loading.remove(workflow);
    }
  }

  void close() {
    _stopped = true;
    for (final worker in _workers.values) {
      worker.close();
    }
  }
}
