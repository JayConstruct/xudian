import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';

Future<ScriptPackage> package(String name) async => ScriptPackage.verify(
  await File('../dist/modules/$name.xmodule').readAsBytes(),
  allowUnsignedLocal: true,
);
Map<String, Object?> timetable({
  String first = '2026-09-07',
  int start = 1,
  String zone = 'Asia/Shanghai',
}) => {
  'id': 't',
  'datasetId': 'dataset',
  'name': '课表',
  'firstMonday': first,
  'totalWeeks': 20,
  'timezone': zone,
  'displayWeekStart': start,
  'periods': [
    {'number': 1, 'start': '08:00', 'end': '08:45'},
    {'number': 2, 'start': '08:55', 'end': '09:40'},
    {'number': 3, 'start': '10:00', 'end': '10:45'},
  ],
};
ServiceRef schedule(String id) => ServiceRef('app.schedule', id, 1);
void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('xudian-host-test-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });
  Future<Object?> run(String id, Object? args) async {
    final caller = host.instances['app.schedule']!.actor;
    final p = await host.prepare(caller, schedule(id), args);
    host.review(p.id, caller);
    return host.commit(caller, p.id);
  }

  Future<void> setupSchedule() async {
    await host.install(await package('app.schedule'));
    await run('schedule.timetable.save', {'timetable': timetable()});
    await run('schedule.course.save', {
      'course': {
        'id': 'c',
        'timetableId': 't',
        'name': '中文课程',
        'color': '#486DA4',
      },
      'meeting': {
        'id': 'm',
        'weekday': 1,
        'startPeriod': 1,
        'endPeriod': 2,
        'weeks': [1, 3, 7],
        'teacher': '老师',
        'location': '教室',
      },
    });
  }

  test('today uses timetable IANA zone rather than the device date', () async {
    await setupSchedule();
    host.clockNow = () => DateTime.utc(2026, 9, 6, 16, 30);
    final actor = host.instances['app.schedule']!.actor;
    var today = object(
      await host.query(actor, schedule('schedule.query.today'), {
        'timetableId': 't',
      }),
    );
    expect(today['date'], '2026-09-07');
    expect(today['items'], hasLength(1));
    await run('schedule.timetable.save', {
      'timetable': timetable(zone: 'America/New_York'),
    });
    today = object(
      await host.query(actor, schedule('schedule.query.today'), {
        'timetableId': 't',
      }),
    );
    expect(today['date'], '2026-09-06');
    expect(today['items'], isEmpty);
  });
  test('schedule installs and executes without task or AI packages', () async {
    await setupSchedule();
    final actor = host.instances['app.schedule']!.actor;
    final week = object(
      await host.query(actor, schedule('schedule.query.week'), {
        'timetableId': 't',
        'teachingWeek': 1,
      }),
    );
    expect((week['items'] as List).length, 1);
    expect(object((week['blocks'] as List).single)['start'], 0);
    expect(object((week['blocks'] as List).single)['end'], 2);
    final absent = object(
      await host.query(actor, schedule('schedule.query.week'), {
        'timetableId': 't',
        'teachingWeek': 2,
      }),
    );
    expect(absent['items'], isEmpty);
    final result = object(
      await host.invokePage('app.schedule', 'render', {
        'state': {},
        'context': {},
      }),
    );
    expect(object(result['tree'])['type'], 'column');
    expect(host.instances.keys, ['app.schedule']);
  });
  test('cross-week occurrence move includes incoming and excludes outgoing instance', () async {
    await setupSchedule();
    await run('schedule.change.save', {
      'change': {
        'id': 'change',
        'timetableId': 't',
        'meetingId': 'm',
        'originalDate': '2026-09-07',
        'kind': 'replace',
        'date': '2026-09-15',
        'startPeriod': 2,
        'endPeriod': 3,
        'location': '新教室',
      },
    });
    final actor = host.instances['app.schedule']!.actor;
    final old = object(
      await host.query(actor, schedule('schedule.query.week'), {
        'timetableId': 't',
        'teachingWeek': 1,
      }),
    );
    expect(old['items'], isEmpty);
    final moved = object(
      await host.query(actor, schedule('schedule.query.week'), {
        'timetableId': 't',
        'teachingWeek': 2,
      }),
    );
    expect(object((moved['items'] as List).single)['location'], '新教室');
    expect(
      object((moved['items'] as List).single)['originalDate'],
      '2026-09-07',
    );
  });
  test(
    'Sunday start and year boundary use actual dates and teaching week',
    () async {
      await host.install(await package('app.schedule'));
      await run('schedule.timetable.save', {
        'timetable': timetable(
          first: '2026-12-28',
          start: 7,
          zone: 'America/New_York',
        ),
      });
      final actor = host.instances['app.schedule']!.actor;
      final week = object(
        await host.query(actor, schedule('schedule.query.week'), {
          'timetableId': 't',
          'teachingWeek': 2,
        }),
      );
      expect(object((week['columns'] as List).first)['id'], '2027-01-03');
      expect(object((week['columns'] as List).last)['id'], '2027-01-09');
    },
  );
  test('record and collection conflicts reject commits, repeated commit emits once', () async {
    await setupSchedule();
    final actor = host.instances['app.schedule']!.actor;
    final before = await store.sql(
      'SELECT COUNT(*) AS count FROM host_operations',
    );
    final p = await host.prepare(actor, schedule('schedule.timetable.save'), {
      'timetable': {...timetable(), 'name': '第一次'},
    });
    host.review(p.id, actor);
    await host.commit(actor, p.id);
    await host.commit(actor, p.id);
    final after = await store.sql(
      'SELECT COUNT(*) AS count FROM host_operations',
    );
    expect((after.single['count'] as int) - (before.single['count'] as int), 1);
    final stale = await host.prepare(actor, schedule('schedule.course.save'), {
      'course': {'id': 'c', 'timetableId': 't', 'name': '修改'},
      'meeting': null,
    });
    await run('schedule.course.save', {
      'course': {'id': 'c2', 'timetableId': 't', 'name': '另一门课'},
    });
    host.review(stale.id, actor);
    await expectLater(host.commit(actor, stale.id), throwsStateError);
  });
  test(
    'disabled module invalidates old plans and can restore retained data',
    () async {
      await setupSchedule();
      final actor = host.instances['app.schedule']!.actor;
      final p = await host.prepare(actor, schedule('schedule.timetable.save'), {
        'timetable': timetable(),
      });
      host.review(p.id, actor);
      await host.disable('app.schedule');
      await expectLater(host.commit(actor, p.id), throwsStateError);
      await host.enable('app.schedule');
      expect(
        await store.get(host.instances['app.schedule']!.actor, 'courses', 'c'),
        isNotNull,
      );
      await host.uninstall('app.schedule');
      expect(host.instances, isEmpty);
      await host.initialize();
      expect(host.instances, isEmpty);
    },
  );
  test('module script update changes behavior without changing host', () async {
    await setupSchedule();
    final original = await package('app.schedule');
    final definition =
        jsonDecode(jsonEncode(original.definition)) as Map<String, dynamic>;
    object(definition['manifest'])['version'] = '1.9.1';
    final scripts = {...original.scripts};
    scripts['main.js'] = scripts['main.js']!.replaceFirst(
      "export async function queryToday({timetableId}) {",
      "export async function queryToday({timetableId}) { return {date:'2030-01-01', teachingWeek:99, items:[]};",
    );
    final bytes = await ScriptPackage.build(definition, scripts);
    await host.install(
      await ScriptPackage.verify(bytes, allowUnsignedLocal: true),
    );
    final actor = host.instances['app.schedule']!.actor;
    expect(
      object(
        await host.query(actor, schedule('schedule.query.today'), {
          'timetableId': 't',
        }),
      )['teachingWeek'],
      99,
    );
    await host.rollback('app.schedule', original.version);
    expect(
      object(
        await host.query(
          host.instances['app.schedule']!.actor,
          schedule('schedule.query.today'),
          {'timetableId': 't'},
        ),
      )['teachingWeek'],
      isNot(99),
    );
  });
  test(
    'recurrence edit requires explicit handling of orphaned changes',
    () async {
      await setupSchedule();
      await run('schedule.change.save', {
        'change': {
          'id': 'cancel',
          'timetableId': 't',
          'meetingId': 'm',
          'originalDate': '2026-09-07',
          'kind': 'cancel',
        },
      });
      await expectLater(
        run('schedule.course.save', {
          'course': {'id': 'c', 'timetableId': 't', 'name': '修改'},
          'meeting': {
            'id': 'm',
            'weekday': 2,
            'startPeriod': 1,
            'endPeriod': 2,
            'weeks': [1, 3, 7],
          },
        }),
        throwsStateError,
      );
    },
  );
}
