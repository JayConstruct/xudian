import '../contracts/json_values.dart';

/// A prepared, event-free page result. Applying this snapshot must still use
/// the page's normal intent/instance checks and preserve live form controllers.
class PreparedDatePage {
  PreparedDatePage({
    required Map<String, Object?> result,
    required Set<String> reads,
  }) : result = freezeJson(result) as Map<String, Object?>,
       reads = Set.unmodifiable(reads);

  final Map<String, Object?> result;
  final Set<String> reads;
}

class _DatePageEntry {
  _DatePageEntry(this.instance, this.snapshot, this.expiresAt);
  final Object instance;
  final PreparedDatePage snapshot;
  final DateTime expiresAt;
}

/// Small per-renderer cache of date page preparations, independent of module
/// identities and business logic. Inputs include all state and drafts; changing
/// either cannot reuse an older preparation. Only one speculative load may run
/// at once so callers can prepare adjacent days in sequence during idle time.
class DatePageCache {
  DatePageCache({
    this.capacity = 5,
    this.maxAge = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : assert(capacity > 0),
       _now = now ?? DateTime.now;

  final int capacity;
  final Duration maxAge;
  final DateTime Function() _now;
  final _entries = <String, _DatePageEntry>{};
  int _revision = 0;
  bool _disposed = false;
  String? _pendingKey;
  Object? _pendingInstance;
  Future<PreparedDatePage?>? _pending;

  String? _key(Map<String, Object?> input) {
    if (_disposed || input['event'] != null) return null;
    final context = input['context'];
    if (context is! Map || context['selectedDate'] is! String) return null;
    return canonicalJson(input);
  }

  PreparedDatePage? lookup(Object instance, Map<String, Object?> input) {
    final key = _key(input);
    if (key == null) return null;
    final entry = _entries.remove(key);
    if (entry == null ||
        !identical(entry.instance, instance) ||
        !entry.expiresAt.isAfter(_now())) {
      return null;
    }
    _entries[key] = entry;
    return entry.snapshot;
  }

  /// Normal event-free reads may seed the cache, but responses that clear or
  /// replace forms, or change the requested context, can never be replayed.
  bool remember(
    Object instance,
    Map<String, Object?> input,
    PreparedDatePage snapshot,
  ) {
    final key = _key(input);
    if (key == null || !_replayable(input, snapshot.result)) return false;
    final now = _now();
    final nextMinute = DateTime.fromMillisecondsSinceEpoch(
      ((now.millisecondsSinceEpoch ~/ 60000) + 1) * 60000,
      isUtc: now.isUtc,
    );
    final ttl = now.add(maxAge);
    _entries.remove(key);
    _entries[key] = _DatePageEntry(
      instance,
      snapshot,
      ttl.isBefore(nextMinute) ? ttl : nextMinute,
    );
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return true;
  }

  bool _replayable(Map<String, Object?> input, Map<String, Object?> result) {
    if (result['tree'] is! Map) return false;
    final clears = result['clearForms'];
    if (clears != null && (clears is! List || clears.isNotEmpty)) return false;
    final replacements = result['replaceForms'];
    if (replacements != null &&
        (replacements is! Map || replacements.isNotEmpty)) {
      return false;
    }
    final patch = result['runtimeContextPatch'];
    if (patch == null) return true;
    if (patch is! Map) return false;
    final context = input['context'] as Map;
    return patch.entries.every(
      (entry) =>
          canonicalJson(context[entry.key]) == canonicalJson(entry.value),
    );
  }

  /// [load] must use ModuleHost.invokePage(readOnly: true, shouldRun: isCurrent).
  /// It must not publish page state or mutate draft controllers. The predicate
  /// is checked again at completion, discarding any invalidated in-flight read.
  Future<PreparedDatePage?> prepare({
    required Object instance,
    required Map<String, Object?> input,
    required Future<PreparedDatePage?> Function(bool Function() isCurrent) load,
    required bool Function() shouldRun,
  }) {
    final key = _key(input);
    if (key == null || !shouldRun()) return Future.value(null);
    final existing = lookup(instance, input);
    if (existing != null) return Future.value(existing);
    if (_pending != null) {
      return key == _pendingKey && identical(instance, _pendingInstance)
          ? _pending!
          : Future.value(null);
    }
    final revision = _revision;
    final request = freezeJson(input) as Map<String, Object?>;
    bool isCurrent() => !_disposed && _revision == revision && shouldRun();
    _pendingKey = key;
    _pendingInstance = instance;
    final future = () async {
      try {
        final snapshot = await load(isCurrent);
        if (snapshot == null ||
            !isCurrent() ||
            !remember(instance, request, snapshot)) {
          return null;
        }
        return snapshot;
      } catch (_) {
        // Preparation is an optimization. Unsupported capabilities and failed
        // reads fall back to the normal foreground render without an error UI.
        return null;
      }
    }();
    _pending = future;
    return future.whenComplete(() {
      if (identical(_pending, future)) {
        _pending = null;
        _pendingKey = null;
        _pendingInstance = null;
      }
    });
  }

  void invalidateModules(Set<String> modules) {
    _revision++;
    _entries.removeWhere(
      (_, entry) => entry.snapshot.reads.any(modules.contains),
    );
  }

  void clear() {
    _revision++;
    _entries.clear();
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}
