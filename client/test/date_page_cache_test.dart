import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/date_page_cache.dart';

Map<String, Object?> input({
  String date = '2026-10-12',
  String draft = 'unfinished task',
  bool expanded = true,
  Object? event,
}) => {
  'context': {'pageId': 'some.daily.feed', 'selectedDate': date},
  'state': {'quickExpanded': expanded},
  'formValues': {'quickTitle': draft},
  'event': event,
};

PreparedDatePage snapshot({Map<String, Object?> extra = const {}}) =>
    PreparedDatePage(
      result: {
        'state': {'selectedDate': '2026-10-12'},
        'tree': {'type': 'text', 'text': 'ready'},
        ...extra,
      },
      reads: {'tasks', 'extensions'},
    );

void main() {
  test('cache keys preserve drafts, state, context and instance identity', () {
    final cache = DatePageCache();
    final instance = Object();
    expect(cache.remember(instance, input(), snapshot()), isTrue);
    expect(cache.lookup(instance, input(draft: 'new draft')), isNull);
    expect(cache.lookup(instance, input(expanded: false)), isNull);
    expect(cache.lookup(instance, input(date: '2026-10-13')), isNull);
    expect(cache.lookup(instance, input()), isNotNull);
    expect(cache.lookup(Object(), input()), isNull);
  });

  test('events and form replacement or context changes cannot be replayed', () {
    final cache = DatePageCache();
    final instance = Object();
    expect(
      cache.remember(instance, input(event: {'type': 'add'}), snapshot()),
      isFalse,
    );
    for (final unsafe in <Map<String, Object?>>[
      {
        'clearForms': ['quickTitle'],
      },
      {
        'replaceForms': {'quickTitle': ''},
      },
      {
        'runtimeContextPatch': {'selectedDate': '2026-10-13'},
      },
      {'tree': null},
    ]) {
      expect(
        cache.remember(instance, input(), snapshot(extra: unsafe)),
        isFalse,
      );
    }
    expect(
      cache.remember(
        instance,
        input(),
        snapshot(
          extra: {
            'clearForms': [],
            'replaceForms': {},
            'runtimeContextPatch': {'selectedDate': '2026-10-12'},
          },
        ),
      ),
      isTrue,
    );
  });

  test('cache expires at the next minute for time-sensitive course badges', () {
    var now = DateTime.utc(2026, 10, 12, 8, 59, 55);
    final cache = DatePageCache(now: () => now);
    final instance = Object();
    cache.remember(instance, input(), snapshot());
    now = now.add(const Duration(seconds: 4));
    expect(cache.lookup(instance, input()), isNotNull);
    now = now.add(const Duration(seconds: 1));
    expect(cache.lookup(instance, input()), isNull);
    cache.remember(instance, input(), snapshot());
    now = now.add(const Duration(seconds: 30));
    expect(cache.lookup(instance, input()), isNull);
  });

  test('bounded cache evicts least recently viewed date', () {
    final cache = DatePageCache(capacity: 2);
    final instance = Object();
    cache.remember(instance, input(date: '2026-10-11'), snapshot());
    cache.remember(instance, input(date: '2026-10-12'), snapshot());
    cache.lookup(instance, input(date: '2026-10-11'));
    cache.remember(instance, input(date: '2026-10-13'), snapshot());
    expect(cache.lookup(instance, input(date: '2026-10-12')), isNull);
    expect(cache.lookup(instance, input(date: '2026-10-11')), isNotNull);
  });

  test('only actual data dependencies invalidate stored preparations', () {
    final cache = DatePageCache();
    final instance = Object();
    cache.remember(instance, input(), snapshot());
    cache.invalidateModules({'unrelated'});
    expect(cache.lookup(instance, input()), isNotNull);
    cache.invalidateModules({'extensions'});
    expect(cache.lookup(instance, input()), isNull);
  });

  test('synchronous module revisions close the notification gap', () {
    final cache = DatePageCache();
    final instance = Object();
    cache.synchronizeDataRevision(0, {});
    cache.remember(instance, input(), snapshot());
    cache.synchronizeDataRevision(1, {'unrelated': 1});
    expect(cache.lookup(instance, input()), isNotNull);
    // Several commits can complete before this renderer checks again. Compare
    // the whole detached snapshot, not merely the most recently changed module.
    cache.synchronizeDataRevision(3, {'unrelated': 3, 'tasks': 2});
    expect(cache.lookup(instance, input()), isNull);
  });

  test('untracked global revision changes retain the full-clear fallback', () {
    final cache = DatePageCache();
    final instance = Object();
    cache.synchronizeDataRevision(0, {});
    cache.remember(instance, input(), snapshot());
    cache.synchronizeDataRevision(1, {});
    expect(cache.lookup(instance, input()), isNull);
  });

  test('a result begun in the previous minute is never cached', () async {
    var now = DateTime.utc(2026, 10, 12, 8, 59, 59);
    final cache = DatePageCache(now: () => now);
    final instance = Object();
    final startedAt = now;
    final done = Completer<PreparedDatePage?>();
    final pending = cache.prepare(
      instance: instance,
      input: input(),
      load: (_) => done.future,
      shouldRun: () => true,
    );
    now = now.add(const Duration(seconds: 2));
    done.complete(snapshot());
    expect(await pending, isNull);
    expect(
      cache.remember(instance, input(), snapshot(), startedAt: startedAt),
      isFalse,
    );
    expect(cache.lookup(instance, input()), isNull);
  });

  test('request latency consumes TTL and clock rollback discards results', () {
    var now = DateTime.utc(2026, 10, 12, 8, 59, 1);
    final cache = DatePageCache(now: () => now);
    final instance = Object();
    final startedAt = now;
    now = now.add(const Duration(seconds: 20));
    expect(
      cache.remember(instance, input(), snapshot(), startedAt: startedAt),
      isTrue,
    );
    now = startedAt.add(const Duration(seconds: 30));
    expect(cache.lookup(instance, input()), isNull);
    expect(
      cache.remember(instance, input(), snapshot(), startedAt: startedAt),
      isFalse,
    );
    cache.remember(instance, input(), snapshot());
    now = startedAt;
    expect(cache.lookup(instance, input()), isNull);
  });

  test('a synchronous unrelated write cancels pending unknown reads', () async {
    final cache = DatePageCache();
    final instance = Object();
    cache.synchronizeDataRevision(0, {});
    final done = Completer<PreparedDatePage?>();
    late bool Function() current;
    final pending = cache.prepare(
      instance: instance,
      input: input(),
      load: (predicate) {
        current = predicate;
        return done.future;
      },
      shouldRun: () => true,
    );
    cache.synchronizeDataRevision(1, {'unrelated': 1});
    expect(current(), isFalse);
    done.complete(snapshot());
    expect(await pending, isNull);
    expect(cache.lookup(instance, input()), isNull);
  });

  test(
    'one speculative read at a time and identical reads are shared',
    () async {
      final cache = DatePageCache();
      final instance = Object();
      final done = Completer<PreparedDatePage?>();
      var calls = 0;
      Future<PreparedDatePage?> load(bool Function() current) {
        calls++;
        expect(current(), isTrue);
        return done.future;
      }

      final first = cache.prepare(
        instance: instance,
        input: input(),
        load: load,
        shouldRun: () => true,
      );
      final duplicate = cache.prepare(
        instance: instance,
        input: input(),
        load: load,
        shouldRun: () => true,
      );
      expect(
        await cache.prepare(
          instance: instance,
          input: input(date: '2026-10-13'),
          load: load,
          shouldRun: () => true,
        ),
        isNull,
      );
      expect(calls, 1);
      done.complete(snapshot());
      expect(await first, isNotNull);
      expect(await duplicate, isNotNull);
      expect(cache.lookup(instance, input()), isNotNull);
    },
  );

  test('in-flight preparations are discarded after data changes', () async {
    final cache = DatePageCache();
    final instance = Object();
    final done = Completer<PreparedDatePage?>();
    late bool Function() current;
    final pending = cache.prepare(
      instance: instance,
      input: input(),
      load: (predicate) {
        current = predicate;
        return done.future;
      },
      shouldRun: () => true,
    );
    cache.invalidateModules({'tasks'});
    expect(current(), isFalse);
    done.complete(snapshot());
    expect(await pending, isNull);
    expect(cache.lookup(instance, input()), isNull);
  });

  test('draft and date intent changes cancel a queued preparation', () async {
    final cache = DatePageCache();
    final instance = Object();
    var needed = true;
    final done = Completer<PreparedDatePage?>();
    final pending = cache.prepare(
      instance: instance,
      input: input(),
      load: (_) => done.future,
      shouldRun: () => needed,
    );
    needed = false;
    done.complete(snapshot());
    expect(await pending, isNull);
    expect(cache.lookup(instance, input()), isNull);
  });

  test('failed preparation falls back and allows another idle read', () async {
    final cache = DatePageCache();
    final instance = Object();
    expect(
      await cache.prepare(
        instance: instance,
        input: input(),
        load: (_) => Future.error(StateError('side effect refused')),
        shouldRun: () => true,
      ),
      isNull,
    );
    expect(
      await cache.prepare(
        instance: instance,
        input: input(),
        load: (_) async => snapshot(),
        shouldRun: () => true,
      ),
      isNotNull,
    );
  });
}
