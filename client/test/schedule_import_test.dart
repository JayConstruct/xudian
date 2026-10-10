import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';

Map<String, Object?> draft({
  String name = '数学',
  bool complete = true,
  bool empty = false,
}) => {
  'draftVersion': 1,
  'scope': 'school/student/2026-autumn',
  'adapterVersion': 'test@1',
  'complete': complete,
  'timetable': {
    'name': '导入课表',
    'firstMonday': '2026-09-07',
    'totalWeeks': 20,
    'timezone': 'Asia/Shanghai',
    'displayWeekStart': 1,
    'periods': [
      {'number': 1, 'start': '08:00', 'end': '08:45'},
      {'number': 2, 'start': '08:55', 'end': '09:40'},
    ],
  },
  'courses': empty
      ? []
      : [
          {'sourceId': 'course-1', 'name': name, 'color': '#486DA4'},
        ],
  'meetings': empty
      ? []
      : [
          {
            'sourceId': 'meeting-1',
            'courseId': 'course-1',
            'weekday': 1,
            'startPeriod': 1,
            'endPeriod': 2,
            'weeks': [1, 3, 5],
            'location': '教室',
          },
        ],
  'occurrenceChanges': [],
  'warnings': [],
};
void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory dir;
  late ModuleActor actor;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    dir = await Directory.systemTemp.createTemp('schedule-import-');
    host = ModuleHost(store: store, directory: dir);
    await host.initialize();
    await host.install(
      await ScriptPackage.verify(
        await File('../dist/modules/app.schedule.xmodule').readAsBytes(),
        allowUnsignedLocal: true,
      ),
    );
    actor = host.instances['app.schedule']!.actor;
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<ChangePlan> prepare(
    Map<String, Object?> d, {
    String? target,
    String mode = 'new',
    Map<String, String> choices = const {},
  }) => host.prepare(
    actor,
    const ServiceRef('app.schedule', 'schedule.import.prepare', 1),
    {'draft': d, 'targetTimetableId': target, 'mode': mode, 'choices': choices},
  );
  Future<Object?> save(ChangePlan plan) async {
    host.review(plan.id, actor);
    return host.commit(actor, plan.id);
  }

  test('repeated merge preserves stable ids and local deletions', () async {
    final first = object(await save(await prepare(draft()))),
        tid = first['timetableId'] as String;
    final courses = await store.query(actor, 'courses', {}),
        meetings = await store.query(actor, 'meetings', {});
    await save(await prepare(draft(), target: tid, mode: 'merge'));
    expect(await store.query(actor, 'courses', {}), courses);
    expect(await store.query(actor, 'meetings', {}), meetings);
    final p = await host.prepare(
      actor,
      const ServiceRef('app.schedule', 'schedule.entity.delete', 1),
      {'collection': 'courses', 'id': object(courses.single)['id']},
    );
    await save(p);
    await save(await prepare(draft(), target: tid, mode: 'merge'));
    expect(await store.query(actor, 'courses', {}), isEmpty);
    expect(await store.query(actor, 'meetings', {}), isEmpty);
  });
  test('three-way conflict is blocked until explicit choice, preserves local changes', () async {
    final tid =
        object(await save(await prepare(draft())))['timetableId'] as String;
    final course = object((await store.query(actor, 'courses', {})).single);
    await save(
      await host.prepare(
        actor,
        const ServiceRef('app.schedule', 'schedule.course.save', 1),
        {
          'course': {...course, 'name': '本地数学'},
        },
      ),
    );
    final conflict = await prepare(
      draft(name: '来源数学'),
      target: tid,
      mode: 'merge',
    );
    expect(object(conflict.result)['blocked'], true);
    expect(conflict.writes, isEmpty);
    final key =
        object((object(conflict.result)['conflicts'] as List).single)['key']
            as String;
    await save(
      await prepare(
        draft(name: '来源数学'),
        target: tid,
        mode: 'merge',
        choices: {key: 'local'},
      ),
    );
    expect(
      object((await store.query(actor, 'courses', {})).single)['name'],
      '本地数学',
    );
    await save(
      await prepare(
        draft(name: '来源再次变更'),
        target: tid,
        mode: 'merge',
        choices: {key: 'source'},
      ),
    );
    expect(
      object((await store.query(actor, 'courses', {})).single)['name'],
      '来源再次变更',
    );
  });
  test(
    'empty complete replacement and partial results never clear data',
    () async {
      final tid =
          object(await save(await prepare(draft())))['timetableId'] as String;
      await save(
        await prepare(draft(empty: true), target: tid, mode: 'replaceSource'),
      );
      expect(await store.query(actor, 'courses', {}), hasLength(1));
      expect(await store.query(actor, 'meetings', {}), hasLength(1));
      await save(
        await prepare(
          {...draft(complete: false), 'meetings': []},
          target: tid,
          mode: 'replaceSource',
        ),
      );
      expect(await store.query(actor, 'meetings', {}), hasLength(1));
    },
  );
  test(
    'JSON backup round-trip assigns fresh local ids and retains recurrence',
    () async {
      final tid =
          object(await save(await prepare(draft())))['timetableId'] as String;
      final backup = object(
        await host.query(
          actor,
          const ServiceRef('app.schedule', 'schedule.backup.export', 1),
          {'timetableId': tid},
        ),
      );
      final backupDraft = {
        'draftVersion': 1,
        'scope': 'json:${backup['datasetId']}',
        'adapterVersion': 'json@1',
        'complete': true,
        'timetable': backup['timetable'],
        'courses': [
          for (final c in backup['courses'] as List)
            {...object(c), 'sourceId': object(c)['id']},
        ],
        'meetings': [
          for (final c in backup['meetings'] as List)
            {...object(c), 'sourceId': object(c)['id']},
        ],
        'occurrenceChanges': backup['occurrenceChanges'],
        'warnings': [],
      };
      final result = object(await save(await prepare(backupDraft)));
      expect(result['timetableId'], isNot(tid));
      expect(await store.query(actor, 'courses', {}), hasLength(2));
      expect(
        (await store.query(
          actor,
          'meetings',
          {},
        )).map((m) => jsonEncode(object(m)['weeks'])).toSet(),
        {'[1,3,5]'},
      );
    },
  );
  test('recurrence import requires explicit handling for a locally moved occurrence', () async {
    final tid =
        object(await save(await prepare(draft())))['timetableId'] as String;
    final meeting = object((await store.query(actor, 'meetings', {})).single);
    await save(
      await host.prepare(
        actor,
        const ServiceRef('app.schedule', 'schedule.change.save', 1),
        {
          'change': {
            'id': 'local-change',
            'timetableId': tid,
            'meetingId': meeting['id'],
            'originalDate': '2026-09-07',
            'kind': 'replace',
            'date': '2026-09-08',
            'startPeriod': 1,
            'endPeriod': 2,
            'location': '调课教室',
          },
        },
      ),
    );
    final next = draft();
    next['meetings'] = [
      {
        ...object((next['meetings'] as List).single),
        'weeks': [3, 5],
      },
    ];
    final blocked = await prepare(next, target: tid, mode: 'merge');
    expect(object(blocked.result)['blocked'], true);
    expect(blocked.writes, isEmpty);
    final conflict = object(
      (object(blocked.result)['conflicts'] as List).single,
    );
    expect(conflict['options'], ['discard', 'extra']);
    await save(
      await prepare(
        next,
        target: tid,
        mode: 'merge',
        choices: {conflict['key'] as String: 'extra'},
      ),
    );
    final change = object(
      (await store.query(actor, 'occurrenceChanges', {})).single,
    );
    expect(change['kind'], 'extra');
    expect(change['meetingId'], isNull);
    expect(change['location'], '调课教室');
  });
  test(
    'timetable configuration participates in three-way conflict choices',
    () async {
      final tid =
          object(await save(await prepare(draft())))['timetableId'] as String;
      final table = object(await store.get(actor, 'timetables', tid));
      await save(
        await host.prepare(
          actor,
          const ServiceRef('app.schedule', 'schedule.timetable.save', 1),
          {
            'timetable': {...table, 'name': '本地名称'},
          },
        ),
      );
      final next = draft();
      next['timetable'] = {...object(next['timetable']), 'name': '来源名称'};
      final blocked = await prepare(next, target: tid, mode: 'merge');
      expect(object(blocked.result)['blocked'], true);
      await save(
        await prepare(
          next,
          target: tid,
          mode: 'merge',
          choices: {'timetable:name': 'local'},
        ),
      );
      expect(object(await store.get(actor, 'timetables', tid))['name'], '本地名称');
    },
  );
  test('import preview is invalidated by unrelated range write', () async {
    final p = await prepare(draft());
    await save(await prepare({...draft(), 'scope': 'another-source'}));
    host.review(p.id, actor);
    await expectLater(host.commit(actor, p.id), throwsStateError);
  });
}
