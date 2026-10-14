import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/performance/ui_load_trace.dart';

void main() {
  test(
    'timing preserves values and errors without recording their contents',
    () async {
      final samples = <UiLoadSample>[];
      await UiLoadTrace.observe(() async {
        expect(await UiLoadTrace.run('ok', () async => 42), 42);
        final error = StateError('private message');
        await expectLater(
          UiLoadTrace.run('fail', () async => throw error),
          throwsA(same(error)),
        );
      }, samples.add);
      expect(samples.map((s) => s.name), ['ok', 'fail']);
      expect(samples.last.arguments, {'outcome': 'error'});
      expect(samples.every((s) => s.elapsed >= Duration.zero), isTrue);
    },
  );

  test('scoped observers stay isolated across concurrent benchmarks', () async {
    final first = <UiLoadSample>[];
    final second = <UiLoadSample>[];
    final gate = Completer<void>();
    final pending = UiLoadTrace.observe(
      () => UiLoadTrace.run('first', () async {
        await gate.future;
      }),
      first.add,
    );
    await UiLoadTrace.observe(
      () => UiLoadTrace.run('second', () async {}),
      second.add,
    );
    gate.complete();
    await pending;
    expect(first.single.name, 'first');
    expect(second.single.name, 'second');
  });

  test(
    'finishing is idempotent and observer failures cannot affect execution',
    () async {
      var calls = 0;
      await UiLoadTrace.observe(
        () async {
          final span = UiLoadTrace.start('manual');
          span?.finish();
          span?.finish();
          expect(await UiLoadTrace.run('result', () async => true), isTrue);
        },
        (_) {
          calls++;
          throw StateError('broken reporter');
        },
      );
      expect(calls, 2);
    },
  );
}
