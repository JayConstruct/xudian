import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xquickjs/src/worker_poll_scheduler.dart';

void main() {
  testWidgets('explicit owner zone survives a temporary construction zone', (
    tester,
  ) async {
    final owner = Zone.current;
    const transactionKey = #temporaryTransaction;
    final temporary = owner.fork(zoneValues: {transactionKey: true});
    final seen = <bool>[];
    final scheduler = temporary.run(
      () => WorkerPollScheduler(
        ownerZone: owner,
        drain: () {
          seen.add(Zone.current[transactionKey] == true);
          return false;
        },
        hasPending: () => false,
      )..wake(),
    );
    addTearDown(scheduler.close);
    await tester.pump(const Duration(milliseconds: 1));
    expect(seen, [false]);
    temporary.run(scheduler.wake);
    await tester.pump(const Duration(milliseconds: 1));
    expect(seen, [false, false]);
    scheduler.close();
  });
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
    await tester.pump(const Duration(milliseconds: 1));
    expect(ownerTimers, before + 2);
    scheduler.close();
  });
  testWidgets('idle polling remains bounded and a new post wakes within 1ms', (
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
    expect(
      polls,
      lessThanOrEqualTo(24),
      reason: 'Idle workers must not poll at the active 1ms rate',
    );
    final idlePolls = polls;
    scheduler.wake();
    expect(polls, idlePolls);
    await tester.pump(const Duration(milliseconds: 1));
    expect(polls, idlePolls + 1);
    scheduler.close();
    await tester.pump(const Duration(seconds: 1));
    expect(polls, idlePolls + 1);
  });

  testWidgets('pending work backs off and replies restore 1ms responsiveness', (
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
    expect(polls, inInclusiveRange(31, 36));
    final quietPolls = polls;
    received = true;
    scheduler.wake();
    await tester.pump(const Duration(milliseconds: 2));
    expect(polls, quietPolls + 2);
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
    expect(polls, 16);
    scheduler.close();
    await tester.pump(const Duration(seconds: 1));
    expect(
      polls,
      16,
      reason: 'Only one timer should exist after reentrant wake',
    );
  });

  testWidgets('a short chain of immediate host replies fits in one frame', (
    tester,
  ) async {
    var remaining = 12;
    final scheduler = WorkerPollScheduler(
      drain: () {
        if (remaining == 0) return false;
        remaining--;
        return true;
      },
      hasPending: () => remaining > 0,
    )..wake();
    addTearDown(scheduler.close);
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      remaining,
      0,
      reason: 'Fast bridge replies must not each add an 8ms frame delay',
    );
    scheduler.close();
  });
}
