import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xquickjs/src/worker_poll_scheduler.dart';

void main() {
  testWidgets('posts from another zone retain the worker timer zone', (
    tester,
  ) async {
    var ownerTimers = 0;
    var foreignTimers = 0;
    final owner = Zone.current.fork(
      specification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          ownerTimers++;
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );
    final foreign = Zone.current.fork(
      specification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          foreignTimers++;
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );
    final scheduler = owner.run(
      () =>
          WorkerPollScheduler(drain: () => false, hasPending: () => false)
            ..wake(),
    );
    addTearDown(scheduler.close);
    await tester.pump(const Duration(seconds: 1));
    final before = ownerTimers;
    foreign.run(scheduler.wake);
    expect(ownerTimers, before + 1);
    expect(foreignTimers, 0);
    await tester.pump(const Duration(milliseconds: 8));
    expect(ownerTimers, before + 2);
    scheduler.close();
  });
  testWidgets('idle polling is bounded and a new post wakes within 8ms', (
    tester,
  ) async {
    var polls = 0;
    final scheduler = WorkerPollScheduler(
      drain: () {
        polls++;
        return false;
      },
      hasPending: () => false,
    )..wake();
    addTearDown(scheduler.close);
    await tester.pump(const Duration(seconds: 1));
    expect(polls, 17, reason: 'Periodic 8ms polling would run 125 times');
    scheduler.wake();
    await tester.pump(const Duration(milliseconds: 7));
    expect(polls, 17);
    await tester.pump(const Duration(milliseconds: 1));
    expect(polls, 18);
    scheduler.close();
    await tester.pump(const Duration(seconds: 1));
    expect(polls, 18);
  });

  testWidgets('pending work caps backoff at 32ms and replies restore 8ms', (
    tester,
  ) async {
    var polls = 0;
    var received = false;
    final scheduler = WorkerPollScheduler(
      drain: () {
        polls++;
        return received;
      },
      hasPending: () => true,
    )..wake();
    addTearDown(scheduler.close);
    await tester.pump(const Duration(seconds: 1));
    expect(polls, 32);
    received = true;
    scheduler.wake();
    await tester.pump(const Duration(milliseconds: 16));
    expect(polls, 34);
    scheduler.close();
  });

  testWidgets('repeated posts and reentrant host posts cannot starve polling', (
    tester,
  ) async {
    var polls = 0;
    late WorkerPollScheduler scheduler;
    scheduler = WorkerPollScheduler(
      drain: () {
        polls++;
        if (polls == 1) scheduler.wake();
        return true;
      },
      hasPending: () => false,
    )..wake();
    addTearDown(scheduler.close);
    for (var i = 0; i < 16; i++) {
      scheduler.wake();
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(polls, 2);
    scheduler.close();
    await tester.pump(const Duration(seconds: 1));
    expect(
      polls,
      2,
      reason: 'Only one timer should exist after reentrant wake',
    );
  });
}
