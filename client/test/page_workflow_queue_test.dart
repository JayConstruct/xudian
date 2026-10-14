import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/page_workflow_queue.dart';

void main() {
  test(
    'foreground overtakes pending speculation without interrupting work',
    () async {
      final queue = PageWorkflowQueue();
      final active = Completer<void>();
      final started = Completer<void>();
      final order = <String>[];
      final first = queue.run(() async {
        order.add('active');
        started.complete();
        await active.future;
        order.add('active finished');
        return 1;
      }, speculative: true);
      await started.future;
      final speculative = queue.run(() async {
        order.add('prefetch');
        return 2;
      }, speculative: true);
      final foreground = queue.run(() async {
        order.add('foreground');
        return 3;
      });
      final next = queue.run(() async {
        order.add('next');
        return 4;
      });
      expect(order, ['active']);
      active.complete();
      expect(await Future.wait([first, speculative, foreground, next]), [
        1,
        2,
        3,
        4,
      ]);
      expect(order, [
        'active',
        'active finished',
        'foreground',
        'next',
        'prefetch',
      ]);
      await queue.idle;
    },
  );

  test(
    'a workflow barrier still lets foreground overtake queued preparation',
    () async {
      final queue = PageWorkflowQueue();
      final gate = Completer<void>();
      final order = <String>[];
      queue.waitFor(gate.future);
      final prepared = queue.run(() async {
        order.add('prepared');
        return null;
      }, speculative: true);
      await Future<void>.delayed(Duration.zero);
      final foreground = queue.run(() async {
        order.add('foreground');
        return null;
      });
      expect(order, isEmpty);
      gate.complete();
      await Future.wait([prepared, foreground]);
      expect(order, ['foreground', 'prepared']);
    },
  );

  test(
    'errors stay with the originating call and do not poison the worker',
    () async {
      final queue = PageWorkflowQueue();
      final failed = queue.run(() async => throw StateError('expected'));
      final good = queue.run(() async => 42);
      await expectLater(failed, throwsStateError);
      expect(await good, 42);
    },
  );

  test(
    'closing skips pending work while the running action can settle',
    () async {
      final queue = PageWorkflowQueue();
      final gate = Completer<void>();
      queue.waitFor(gate.future);
      var called = false;
      final pending = queue.run(() async {
        called = true;
        return null;
      });
      queue.close();
      expect(await pending, isNull);
      gate.complete();
      await queue.idle;
      expect(called, isFalse);
      expect(await queue.run(() async => 1), isNull);
    },
  );
}
