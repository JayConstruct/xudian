import 'dart:async';

const _depthKey = #xudianAutomationDepth;
const _traceKey = #xudianAutomationTrace;

int get currentAutomationDepth =>
    Zone.current[_depthKey] as int? ?? 0;

Set<String> get currentAutomationTrace {
  final value = Zone.current[_traceKey];
  if (value is Set<String>) return Set.unmodifiable(value);
  return const {};
}

Future<T> runAutomationStep<T>({
  required String ruleKey,
  required int parentDepth,
  required Set<String> parentTrace,
  required Future<T> Function() action,
}) {
  return runZoned(
    action,
    zoneValues: {
      _depthKey: parentDepth + 1,
      _traceKey: {...parentTrace, ruleKey},
    },
  );
}
