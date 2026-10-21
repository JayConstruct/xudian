import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'planner_task_schedule_test.dart' show sourcePackage, objects, table;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  final draft = <String, Object?>{
    'title': '间隔复习',
    'notes': '保留说明',
    'estimatedMinutes': 30,
    'firstDate': '2026-10-21',
    'days': 30,
    'timezone': 'UTC',
    'rules': {
      'interval': {'minDays': 4, 'maxDays': 6},
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'timeWindow': {'start': '18:00', 'end': '22:00'},
    },
  };
  Future<Map<String, Object?>> query(
    String service, [
    Map<String, Object?> input = const {},
  ]) async => object(
    await host.query(
      host.instances['app.planner']!.actor,
      ServiceRef('app.planner', 'planner.$service', 1),
      input,
    ),
  );
  Future<Map<String, Object?>> run(
    String service,
    Map<String, Object?> input,
  ) async {
    final actor = host.instances['app.planner']!.actor;
    final p = await host.prepare(
      actor,
      ServiceRef('app.planner', 'planner.$service', 1),
      input,
    );
    host.review(p.id, actor);
    return object(await host.commit(actor, p.id));
  }

  Future<List<Map<String, Object?>>> tasks() async => objects(
    await host.query(
      host.instances['app.tasks']!.actor,
      const ServiceRef('app.tasks', 'task.list', 1),
      {'view': 'raw', 'limit': 1000},
    ),
  );
  Future<void> create(String key, [Map<String, Object?>? input]) async {
    final preview = await query('creation.preview', input ?? draft);
    expect(preview['confirmable'], true);
    await run('creation.apply', {'creationKey': key, 'preview': preview});
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('planner-rolling-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 21, 8);
    await host.initialize();
    await host.install(await sourcePackage('app.tasks'));
    await host.install(await sourcePackage('app.planner'));
  });
  tearDown(() async {
    await host.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'preview is read only, covers 30 civil days and confirm is idempotent',
    () async {
      final preview = await query('creation.preview', draft);
      expect(preview['startDate'], '2026-10-21');
      expect(preview['endDate'], '2026-11-19');
      final planned = objects(preview['assigned']);
      expect(planned.length, greaterThan(4));
      expect(await tasks(), isEmpty);
      for (var i = 1; i < planned.length; i++) {
        final gap = DateTime.parse(planned[i]['date'] as String)
            .difference(DateTime.parse(planned[i - 1]['date'] as String))
            .inDays;
        expect(gap, inInclusiveRange(4, 6));
      }
      await run('creation.apply', {
        'creationKey': 'stable',
        'preview': preview,
      });
      final before = await tasks();
      expect(before.first['notes'], '保留说明');
      expect(
        (await run('creation.apply', {
          'creationKey': 'stable',
          'preview': preview,
        }))['alreadyApplied'],
        true,
      );
      expect((await tasks()).length, before.length);
    },
  );

  test(
    '30-day creation queries the real timetable and includes its final day',
    () async {
      await host.install(await sourcePackage('app.schedule'));
      final daily = {
        ...draft,
        'rules': {
          'interval': {'minDays': 1, 'maxDays': 1},
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
          'timeWindow': {'start': '18:00', 'end': '22:00'},
        },
      };
      final empty = await query('creation.preview', daily);
      expect(empty['confirmable'], true);
      expect(objects(empty['assigned']), hasLength(30));

      Future<void> schedule(String service, Map<String, Object?> input) async {
        final actor = host.instances['app.schedule']!.actor;
        final plan = await host.prepare(
          actor,
          ServiceRef('app.schedule', service, 1),
          input,
        );
        host.review(plan.id, actor);
        await host.commit(actor, plan.id);
      }

      await schedule('schedule.timetable.save', {
        'timetable': table(
          'tail',
          zone: 'UTC',
          monday: '2026-10-19',
          start: '18:00',
          end: '22:00',
        ),
      });
      await schedule('schedule.course.save', {
        'course': {
          'id': 'tail-course',
          'timetableId': 'tail',
          'name': '窗口最后一天的课程',
        },
        'meeting': {
          'id': 'tail-meeting',
          'weekday': 4,
          'startPeriod': 1,
          'endPeriod': 1,
          'weeks': [5],
        },
      });
      final occupied = await query('creation.preview', daily);
      expect(occupied['conflicts'], isEmpty);
      expect(occupied['confirmable'], false);
      expect(objects(occupied['assigned']), hasLength(29));
      expect(
        objects(occupied['unassigned']).single['windowStart'],
        '2026-11-19',
      );
      expect(await tasks(), isEmpty);
    },
  );

  test(
    'day ten extends from today and preserves every existing instance',
    () async {
      await create('rolling');
      final before = await tasks();
      host.clockNow = () => DateTime.utc(2026, 10, 31, 8);
      final preview = await query('rolling.preview');
      final p = object(objects(preview['plans']).single['preview']);
      expect(p['startDate'], '2026-10-31');
      expect(p['endDate'], '2026-11-29');
      expect(objects(p['assigned']), isNotEmpty);
      await run('rolling.apply', {
        'operationKey': 'roll-ten',
        'preview': preview,
      });
      final after = await tasks();
      for (final t in before) {
        expect(after.singleWhere((a) => a['id'] == t['id']), t);
      }
      expect((await query('rolling.preview'))['assignedCount'], 0);
    },
  );

  test(
    'only keeps subsequent dates; following shifts later preview dates',
    () async {
      final initial = await query('creation.preview', draft);
      final planned = objects(initial['assigned']);
      final second = planned[1];
      final date = DateTime.parse(second['date'] as String)
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);
      Future<Map<String, Object?>> adjust(String scope) =>
          query('creation.preview', {
            ...draft,
            'adjustments': [
              {
                'id': second['id'],
                'date': date,
                'start': second['start'],
                'end': second['end'],
                'scope': scope,
              },
            ],
          });
      final only = await adjust('only');
      final onlyRows = objects(only['assigned']);
      if (onlyRows.length > 2) expect(onlyRows[2]['date'], planned[2]['date']);
      expect(
        only['confirmable'],
        false,
      ); // moving one of 6-day gaps earlier makes its successor 7 days away.
      final following = await adjust('following');
      final rows = objects(following['assigned']);
      expect(following['confirmable'], true);
      expect(
        rows[2]['date'],
        DateTime.parse(planned[2]['date'] as String)
            .subtract(const Duration(days: 1))
            .toIso8601String()
            .substring(0, 10),
      );
    },
  );

  test(
    'stale preview is rejected and unresolved required work cannot create',
    () async {
      final preview = await query('creation.preview', draft);
      await create('other');
      await expectLater(
        run('creation.apply', {'creationKey': 'stale', 'preview': preview}),
        throwsA(anything),
      );
      final impossible = await query('creation.preview', {
        ...draft,
        'estimatedMinutes': 300,
      });
      expect(impossible['confirmable'], false);
      expect(objects(impossible['unassigned']), isNotEmpty);
      await expectLater(
        run('creation.apply', {'creationKey': 'bad', 'preview': impossible}),
        throwsA(anything),
      );
    },
  );

  test(
    'automation only replenishes confirmed series and skips repeated ticks',
    () async {
      await create('auto');
      final count = (await tasks()).length;
      host.clockNow = () => DateTime.utc(2026, 10, 31, 8);
      final result = await run('series.replenish', {
        'ruleId': 'rolling-series',
        'event': {'type': 'host.clock.tick', 'at': '2026-10-31T08:00:00Z'},
      });
      expect(result['applied'], greaterThan(0));
      expect((await tasks()).length, greaterThan(count));
      expect(
        (await run('series.replenish', {
          'ruleId': 'rolling-series',
          'event': {'type': 'host.clock.tick', 'at': '2026-10-31T08:01:00Z'},
        }))['skipped'],
        true,
      );
    },
  );

  test(
    'undo creation removes its rolling instruction along with generated tasks',
    () async {
      await create('undo-series');
      await run('batch.undo', {'id': 'undo-series'});
      expect(await tasks(), isEmpty);
      expect((await query('rolling.preview'))['plans'], isEmpty);
    },
  );

  test(
    'real host clock trigger replenishes and repeated ticks keep task count',
    () async {
      await create('clock-chain');
      final count = (await tasks()).length;
      host.clockNow = () => DateTime.utc(2026, 10, 31, 8);
      await host.checkClockAutomation(force: true);
      final after = (await tasks()).length;
      expect(after, greaterThan(count));
      await host.checkClockAutomation(force: true);
      expect((await tasks()).length, after);
    },
  );

  test(
    'long dormant series resumes without rewriting overdue unfinished tasks',
    () async {
      await create('dormant');
      final before = await tasks();
      host.clockNow = () => DateTime.utc(2027, 2, 1, 8);
      final preview = await query('rolling.preview');
      final p = object(objects(preview['plans']).single['preview']);
      expect(p['conflicts'], isEmpty);
      expect(p['warnings'], isNotEmpty);
      expect(objects(p['assigned']), isNotEmpty);
      await run('rolling.apply', {
        'operationKey': 'resume-months',
        'preview': preview,
      });
      final after = await tasks();
      for (final t in before) {
        expect(after.singleWhere((a) => a['id'] == t['id']), t);
      }
    },
  );

  test(
    'one blocked series does not prevent another from replenishing',
    () async {
      await create('good');
      await create('blocked', {
        ...draft,
        'title': '晚间复习',
        'rules': {
          'interval': {'minDays': 4, 'maxDays': 6},
          'timeWindow': {'start': '20:00', 'end': '22:00'},
        },
      });
      await run('availability.save', {
        'availability': {
          'timezone': 'UTC',
          'weekly': {
            for (var i = 1; i <= 7; i++)
              '$i': [
                {'start': '18:00', 'end': '19:00'},
              ],
          },
        },
      });
      host.clockNow = () => DateTime.utc(2026, 10, 31, 8);
      final preview = await query('rolling.preview');
      expect(preview['assignedCount'], greaterThan(0));
      expect(preview['blocked'], isNotEmpty);
      final applied = await run('rolling.apply', {
        'operationKey': 'partial-roll',
        'preview': preview,
      });
      expect(applied['applied'], greaterThan(0));
      expect(applied['blocked'], isNotEmpty);
    },
  );

  test('generated instance supports only/following and protects later manual changes', () async {
    await create('editable');
    final all = await tasks();
    all.sort(
      (a, b) => (a['plannedStartAt'] as String).compareTo(
        b['plannedStartAt'] as String,
      ),
    );
    final second = all[1],
        date = (second['plannedDate'] as String),
        earlier = DateTime.parse(date)
            .subtract(const Duration(days: 1))
            .toIso8601String()
            .substring(0, 10);
    final invalid = await query('operation.preview', {
      'taskId': second['id'],
      'date': earlier,
      'start': '18:00',
      'end': '18:30',
      'timezone': 'UTC',
      'scope': 'only',
    });
    expect(invalid['confirmable'], false);
    final following = await query('operation.preview', {
      'taskId': second['id'],
      'date': earlier,
      'start': '18:00',
      'end': '18:30',
      'timezone': 'UTC',
      'scope': 'following',
    });
    expect(following['confirmable'], true);
    expect(objects(following['changes']).length, all.length - 1);
    await run('operation.apply', {
      'operationKey': 'shift-later',
      'preview': following,
    });
    await expectLater(
      query('operation.preview', {
        'taskId': all.first['id'],
        'date': all.first['plannedDate'],
        'start': '18:05',
        'end': '18:35',
        'timezone': 'UTC',
        'scope': 'following',
      }),
      throwsA(anything),
    );
    final moved = await tasks();
    host.clockNow = () => DateTime.utc(2026, 10, 31, 8);
    final rolling = await query('rolling.preview');
    await run('rolling.apply', {
      'operationKey': 'keep-manual',
      'preview': rolling,
    });
    final after = await tasks();
    for (final t in moved) {
      expect(after.singleWhere((a) => a['id'] == t['id']), t);
    }
  });
  test(
    'multiple series share reserved occupancy in the same rolling preview',
    () async {
      await create('same-window-one');
      await create('same-window-two', {...draft, 'title': '第二系列'});
      host.clockNow = () => DateTime.utc(2026, 10, 31, 8);
      final preview = await query('rolling.preview');
      final reserved = <Map<String, Object?>>[];
      for (final plan in objects(preview['plans'])) {
        reserved.addAll(objects(object(plan['preview'])['assigned']));
      }
      expect(reserved, isNotEmpty);
      for (var i = 0; i < reserved.length; i++) {
        for (var j = i + 1; j < reserved.length; j++) {
          final a = reserved[i], b = reserved[j];
          final overlaps =
              DateTime.parse(a['plannedStartAt'] as String)
                  .isBefore(DateTime.parse(b['plannedEndAt'] as String)) &&
              DateTime.parse(b['plannedStartAt'] as String)
                  .isBefore(DateTime.parse(a['plannedEndAt'] as String));
          expect(
            overlaps,
            false,
            reason: 'two series must not book the same slot',
          );
        }
      }
      await run('rolling.apply', {
        'operationKey': 'shared-reservation',
        'preview': preview,
      });
    },
  );
  test(
    'evening creation searches later today rather than rejecting a past slot',
    () async {
      host.clockNow = () => DateTime.utc(2026, 10, 21, 20);
      final preview = await query('creation.preview', draft);
      expect(preview['confirmable'], true);
      final first = objects(preview['assigned']).first;
      expect(first['date'], '2026-10-21');
      expect((first['start'] as String).compareTo('20:00'), greaterThan(0));
      expect(preview['conflicts'], isEmpty);
    },
  );

  test(
    'after allowed time creation advances to a future allowed day',
    () async {
      host.clockNow = () => DateTime.utc(2026, 10, 21, 23, 30);
      final preview = await query('creation.preview', draft);
      expect(preview['confirmable'], true);
      expect(objects(preview['assigned']).first['date'], '2026-10-22');
      expect(preview['conflicts'], isEmpty);
    },
  );

  test(
    'zero buffer excludes current minute and clock seconds do not stale review',
    () async {
      await run('availability.save', {
        'availability': {'timezone': 'UTC', 'bufferMinutes': 0},
      });
      host.clockNow = () => DateTime.utc(2026, 10, 21, 20, 0, 30);
      final preview = await query('creation.preview', draft);
      expect(preview['confirmable'], true);
      expect(objects(preview['assigned']).first['start'], '20:05');
      host.clockNow = () => DateTime.utc(2026, 10, 21, 20, 0, 50);
      final next = await query('creation.preview', draft);
      expect(next['basis'], preview['basis']);
      expect(next['assigned'], preview['assigned']);
      await run('creation.apply', {
        'creationKey': 'seconds-review',
        'preview': preview,
      });
    },
  );

  test('following moves preserve later actual durations when current duration changes', () async {
    await create('duration-series');
    final all = await tasks();
    all.sort(
      (a, b) => (a['plannedStartAt'] as String).compareTo(
        b['plannedStartAt'] as String,
      ),
    );
    final preview = await query('operation.preview', {
      'taskId': all.first['id'],
      'date': all.first['plannedDate'],
      'start': '18:05',
      'end': '18:50',
      'timezone': 'UTC',
      'scope': 'following',
    });
    expect(preview['confirmable'], true);
    final changes = objects(preview['changes']);
    expect(object(changes.first['fields'])['estimatedMinutes'], 45);
    for (final c in changes.skip(1)) {
      final before = object(c['before']), fields = object(c['fields']);
      final oldDuration = DateTime.parse(before['plannedEndAt'] as String)
          .difference(DateTime.parse(before['plannedStartAt'] as String));
      final newDuration = DateTime.parse(fields['plannedEndAt'] as String)
          .difference(DateTime.parse(fields['plannedStartAt'] as String));
      expect(newDuration, oldDuration);
    }
  });
}
