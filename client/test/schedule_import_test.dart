import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';

Future<ScriptPackage> scheduleImportSource() async {
  final folder = Directory('../packages/modules/app.schedule');
  return ScriptPackage.verify(
    await ScriptPackage.build(
      object(
        jsonDecode(await File('${folder.path}/module.json').readAsString()),
      ),
      {
        for (final file in folder.listSync().whereType<File>())
          if (file.path.endsWith('.js'))
            file.uri.pathSegments.last: await file.readAsString(),
      },
    ),
    allowUnsignedLocal: true,
  );
}

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
    await host.install(await scheduleImportSource());
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

  Future<String> targetTable(Map<String, Object?> configuration) async {
    final result = object(
      await save(
        await host.prepare(
          actor,
          const ServiceRef('app.schedule', 'schedule.timetable.save', 1),
          {'timetable': configuration},
        ),
      ),
    );
    return result['id'] as String;
  }

  test('first same-basis merge keeps target settings and repeats without entity writes', () async {
    final incoming = draft();
    final target = await targetTable({
      ...object(incoming['timetable']),
      'name': '保留目标名称',
      'displayWeekStart': 7,
    });
    final before = await store.get(actor, 'timetables', target);
    final first = await prepare(incoming, target: target, mode: 'merge');
    expect(object(first.result)['blocked'], false);
    expect(
      first.writes.where(
        (write) => object(write)['collection'] == 'timetables',
      ),
      isEmpty,
    );
    await save(first);
    expect(await store.get(actor, 'timetables', target), before);
    final source = object(
      (await store.query(actor, 'importSources', {})).single,
    );
    expect(source['callerModuleId'], 'app.schedule');
    expect(source['scope'], incoming['scope']);
    expect(object(source['timetableBaseline'])['name'], '导入课表');
    final repeated = await prepare(incoming, target: target, mode: 'merge');
    expect(object(repeated.result)['blocked'], false);
    expect(
      repeated.writes.where(
        (write) => [
          'timetables',
          'courses',
          'meetings',
          'occurrenceChanges',
        ].contains(object(write)['collection']),
      ),
      isEmpty,
    );
    await save(repeated);
    expect(await store.query(actor, 'importSources', {}), [source]);
  });

  final differentBases = <String, Map<String, Object?>>{
    'semester': {'firstMonday': '2026-09-14'},
    'weeks': {'totalWeeks': 18},
    'timezone': {'timezone': 'America/New_York'},
    'periods': {
      'periods': [
        {'number': 1, 'start': '09:00', 'end': '09:45'},
        {'number': 2, 'start': '09:55', 'end': '10:40'},
      ],
    },
  };
  for (final difference in differentBases.entries) {
    for (final choice in ['local', 'source']) {
      test(
        'first ${difference.key} mismatch requires explicit $choice and retains baseline on repeat',
        () async {
          final incoming = draft();
          final target = await targetTable({
            ...object(incoming['timetable']),
            ...difference.value,
            'name': '目标名称',
          });
          final original = object(await store.get(actor, 'timetables', target));
          await save(
            await host.prepare(
              actor,
              const ServiceRef('app.schedule', 'schedule.course.save', 1),
              {
                'course': {
                  'id': 'local-course',
                  'timetableId': target,
                  'name': '本地课程',
                },
                'meeting': {
                  'id': 'local-meeting',
                  'weekday': 2,
                  'startPeriod': 1,
                  'endPeriod': 2,
                  'weeks': [1],
                },
              },
            ),
          );
          final localMeeting = await store.get(
            actor,
            'meetings',
            'local-meeting',
          );
          for (final mode in ['merge', 'replaceSource']) {
            final blocked = await prepare(incoming, target: target, mode: mode);
            expect(object(blocked.result)['blocked'], true);
            expect(blocked.writes, isEmpty);
            expect(blocked.content['events'], isEmpty);
            final conflict = object(
              (object(blocked.result)['conflicts'] as List).single,
            );
            expect(conflict['key'], 'timetable:timeBasis');
            expect(conflict['field'], contains('新建课表'));
            expect(
              object(conflict['source'])['example'],
              contains('2026-09-07 08:00–09:40'),
            );
            expect(
              object(blocked.result)['warnings'].toString(),
              contains('不转换'),
            );
          }
          final invalid = await prepare(
            incoming,
            target: target,
            mode: 'merge',
            choices: {'timetable:timeBasis': 'auto'},
          );
          expect(object(invalid.result)['blocked'], true);
          expect(await store.get(actor, 'timetables', target), original);
          expect(await store.query(actor, 'importSources', {}), isEmpty);
          final approved = await prepare(
            incoming,
            target: target,
            mode: 'merge',
            choices: {'timetable:timeBasis': choice},
          );
          expect(object(approved.result)['blocked'], false);
          expect(
            object(approved.result)['warnings'].toString(),
            contains('已明确选择'),
          );
          await save(approved);
          final updated = object(await store.get(actor, 'timetables', target));
          final expected = choice == 'local'
              ? original
              : object(incoming['timetable']);
          for (final field in [
            'firstMonday',
            'totalWeeks',
            'timezone',
            'periods',
          ]) {
            expect(updated[field], expected[field]);
          }
          expect(updated['name'], '目标名称');
          expect(updated['datasetId'], original['datasetId']);
          expect(
            await store.get(actor, 'meetings', 'local-meeting'),
            localMeeting,
          );
          final source = object(
            (await store.query(actor, 'importSources', {})).single,
          );
          expect(
            object(source['timetableBaseline']),
            object(incoming['timetable']),
          );
          final repeated = await prepare(
            incoming,
            target: target,
            mode: 'merge',
          );
          expect(object(repeated.result)['blocked'], false);
          expect(
            repeated.writes.where(
              (write) => [
                'timetables',
                'courses',
                'meetings',
              ].contains(object(write)['collection']),
            ),
            isEmpty,
          );
          await save(repeated);
          expect(await store.query(actor, 'importSources', {}), [source]);
          expect(await store.query(actor, 'courses', {}), hasLength(2));
          expect(await store.query(actor, 'meetings', {}), hasLength(2));
        },
      );
    }
  }

  test('source choice cannot invalidate existing meetings and new mode preserves both bases', () async {
    final incoming = draft();
    final target = await targetTable(object(incoming['timetable']));
    await save(
      await host.prepare(
        actor,
        const ServiceRef('app.schedule', 'schedule.course.save', 1),
        {
          'course': {
            'id': 'local-course',
            'timetableId': target,
            'name': '本地课程',
          },
          'meeting': {
            'id': 'local-meeting',
            'weekday': 2,
            'startPeriod': 1,
            'endPeriod': 2,
            'weeks': [20],
          },
        },
      ),
    );
    incoming['timetable'] = {
      ...object(incoming['timetable']),
      'totalWeeks': 18,
    };
    final original = await store.get(actor, 'timetables', target);
    await expectLater(
      prepare(
        incoming,
        target: target,
        mode: 'merge',
        choices: {'timetable:timeBasis': 'source'},
      ),
      throwsStateError,
    );
    expect(await store.get(actor, 'timetables', target), original);
    expect(await store.query(actor, 'importSources', {}), isEmpty);
    final separate = object(await save(await prepare(incoming)));
    expect(separate['timetableId'], isNot(target));
    expect(await store.get(actor, 'timetables', target), original);
    expect(
      object(
        await store.get(actor, 'timetables', separate['timetableId'] as String),
      )['totalWeeks'],
      18,
    );
  });

  for (final choice in ['local', 'source']) {
    test(
      '$choice basis with fewer periods rejects out-of-range imported or existing meetings',
      () async {
        final incoming = draft();
        final shortTable = {
          ...object(incoming['timetable']),
          'periods': [
            {'number': 1, 'start': '08:00', 'end': '08:45'},
          ],
        };
        final target = await targetTable(
          choice == 'local' ? shortTable : object(incoming['timetable']),
        );
        if (choice == 'source') {
          await save(
            await host.prepare(
              actor,
              const ServiceRef('app.schedule', 'schedule.course.save', 1),
              {
                'course': {
                  'id': 'local-course',
                  'timetableId': target,
                  'name': '本地课程',
                },
                'meeting': {
                  'id': 'local-meeting',
                  'weekday': 1,
                  'startPeriod': 1,
                  'endPeriod': 2,
                  'weeks': [1],
                },
              },
            ),
          );
          incoming['timetable'] = shortTable;
          incoming['meetings'] = [
            {...object((incoming['meetings'] as List).single), 'endPeriod': 1},
          ];
        }
        final original = await store.get(actor, 'timetables', target);
        final blocked = await prepare(incoming, target: target, mode: 'merge');
        expect(object(blocked.result)['blocked'], true);
        expect(blocked.writes, isEmpty);
        await expectLater(
          prepare(
            incoming,
            target: target,
            mode: 'merge',
            choices: {'timetable:timeBasis': choice},
          ),
          throwsStateError,
        );
        expect(await store.get(actor, 'timetables', target), original);
        expect(await store.query(actor, 'importSources', {}), isEmpty);
      },
    );
  }

  test(
    'source basis validates existing single-occurrence period references',
    () async {
      final incoming = draft();
      final target = await targetTable(object(incoming['timetable']));
      await save(
        await host.prepare(
          actor,
          const ServiceRef('app.schedule', 'schedule.course.save', 1),
          {
            'course': {
              'id': 'local-course',
              'timetableId': target,
              'name': '本地课程',
            },
            'meeting': {
              'id': 'local-meeting',
              'weekday': 1,
              'startPeriod': 1,
              'endPeriod': 1,
              'weeks': [1],
            },
          },
        ),
      );
      await save(
        await host.prepare(
          actor,
          const ServiceRef('app.schedule', 'schedule.change.save', 1),
          {
            'change': {
              'id': 'local-change',
              'timetableId': target,
              'kind': 'replace',
              'meetingId': 'local-meeting',
              'originalDate': '2026-09-07',
              'date': '2026-09-08',
              'startPeriod': 1,
              'endPeriod': 2,
            },
          },
        ),
      );
      incoming['timetable'] = {
        ...object(incoming['timetable']),
        'periods': [
          {'number': 1, 'start': '08:00', 'end': '08:45'},
        ],
      };
      incoming['meetings'] = [
        {...object((incoming['meetings'] as List).single), 'endPeriod': 1},
      ];
      final original = await store.get(actor, 'timetables', target);
      await expectLater(
        prepare(
          incoming,
          target: target,
          mode: 'merge',
          choices: {'timetable:timeBasis': 'source'},
        ),
        throwsStateError,
      );
      expect(await store.get(actor, 'timetables', target), original);
      expect(await store.query(actor, 'importSources', {}), isEmpty);
    },
  );

  test('basis dialog requires a choice and subsequent orphan resolution retains it', () async {
    final incoming = draft();
    final target = await targetTable(object(incoming['timetable']));
    await save(
      await host.prepare(
        actor,
        const ServiceRef('app.schedule', 'schedule.course.save', 1),
        {
          'course': {
            'id': 'local-course',
            'timetableId': target,
            'name': '本地课程',
          },
          'meeting': {
            'id': 'local-meeting',
            'weekday': 1,
            'startPeriod': 1,
            'endPeriod': 2,
            'weeks': [1],
          },
        },
      ),
    );
    await save(
      await host.prepare(
        actor,
        const ServiceRef('app.schedule', 'schedule.change.save', 1),
        {
          'change': {
            'id': 'local-change',
            'timetableId': target,
            'kind': 'replace',
            'meetingId': 'local-meeting',
            'originalDate': '2026-09-07',
            'date': '2026-09-08',
            'startPeriod': 1,
            'endPeriod': 2,
          },
        },
      ),
    );
    incoming['timetable'] = {
      ...object(incoming['timetable']),
      'firstMonday': '2026-09-14',
    };
    final dialogs = <Map<String, Object?>>[];
    Object? answer = {'mode': 'merge'};
    host.interaction = (_, method, arguments) async {
      if (method == 'ui.dialog') {
        dialogs.add(arguments);
        return answer;
      }
      return method == 'ui.review' ? true : null;
    };
    final context = {
      'pageId': 'app.schedule.imports',
      'timetableId': target,
      'draft': incoming,
    };
    var page = object(
      await host.invokePage('app.schedule', 'render', {
        'context': context,
        'event': {'type': 'saveImport'},
      }),
    );
    expect(
      object(object(page['state'])['importPlan'])['result'],
      containsPair('blocked', true),
    );
    answer = null;
    page = object(
      await host.invokePage('app.schedule', 'render', {
        'context': context,
        'state': page['state'],
        'event': {'type': 'resolveImport'},
      }),
    );
    final basisField = object((dialogs.last['fields'] as List).single);
    expect(basisField['key'], 'timetable:timeBasis');
    expect(basisField['value'], '');
    expect(basisField['required'], true);
    expect(await store.query(actor, 'importSources', {}), isEmpty);
    answer = {'timetable:timeBasis': 'source'};
    page = object(
      await host.invokePage('app.schedule', 'render', {
        'context': context,
        'state': page['state'],
        'event': {'type': 'resolveImport'},
      }),
    );
    final conflicts =
        object(
              object(object(page['state'])['importPlan'])['result'],
            )['conflicts']
            as List;
    final orphan = object(conflicts.single);
    expect(orphan['field'], '失效调课');
    answer = {orphan['key'] as String: 'extra'};
    page = object(
      await host.invokePage('app.schedule', 'render', {
        'context': context,
        'state': page['state'],
        'event': {'type': 'resolveImport'},
      }),
    );
    final state = object(page['state']);
    expect(object(object(state['importInput'])['choices']), {
      'timetable:timeBasis': 'source',
      orphan['key'] as String: 'extra',
    });
    expect(object(object(state['importPlan'])['result'])['blocked'], false);
    answer = null;
    await host.invokePage('app.schedule', 'render', {
      'context': context,
      'state': state,
      'event': {'type': 'confirmImport'},
    });
    expect(
      object(await store.get(actor, 'timetables', target))['firstMonday'],
      '2026-09-14',
    );
    expect(
      object(
        await store.get(actor, 'occurrenceChanges', 'local-change'),
      )['kind'],
      'extra',
    );
    expect(
      object(
        (await prepare(incoming, target: target, mode: 'merge')).result,
      )['blocked'],
      false,
    );
  });

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
