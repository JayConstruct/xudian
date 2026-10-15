import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

Future<ScriptPackage> sourcePackage(String id) async {
  final folder = Directory('../packages/modules/$id');
  final files = <String, String>{};
  await for (final file in folder.list(recursive: true)) {
    if (file is File && file.path.endsWith('.js')) {
      files[file.path.substring(folder.path.length + 1)] = await file
          .readAsString();
    }
  }
  return ScriptPackage.verify(
    await ScriptPackage.build(
      object(
        jsonDecode(await File('${folder.path}/module.json').readAsString()),
      ),
      files,
    ),
    allowUnsignedLocal: true,
  );
}

List<Map<String, Object?>> objects(Object? value) =>
    (value as List).map(object).toList();
List<Map<String, Object?>> nodes(Object? value) => value is Map
    ? [object(value), for (final child in value.values) ...nodes(child)]
    : value is List
    ? [for (final child in value) ...nodes(child)]
    : [];

Map<String, Object?> table(
  String id, {
  String zone = 'Asia/Shanghai',
  String monday = '2026-10-05',
  String start = '08:00',
  String end = '09:00',
}) => {
  'id': id,
  'name': id,
  'firstMonday': monday,
  'totalWeeks': 20,
  'timezone': zone,
  'displayWeekStart': 1,
  'periods': [
    {'number': 1, 'start': start, 'end': end},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('planner-task-schedule-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 6);
    await host.initialize();
    for (final id in ['app.tasks', 'app.views.today', 'app.schedule']) {
      await host.install(await sourcePackage(id));
    }
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<Object?> command(
    String module,
    String id,
    Map<String, Object?> input,
  ) async {
    final actor = host.instances[module]!.actor;
    final plan = await host.prepare(actor, ServiceRef(module, id, 1), input);
    host.review(plan.id, actor);
    return host.commit(actor, plan.id);
  }

  Future<Object?> query(String module, String id, Map<String, Object?> input) =>
      host.query(
        host.instances[module]!.actor,
        ServiceRef(module, id, 1),
        input,
      );
  Future<Map<String, Object?>> task(Map<String, Object?> input) async => object(
    await command('app.tasks', 'task.create', {'title': 'task', ...input}),
  );
  Future<Map<String, Object?>> raw(Object? id) async =>
      object(await query('app.tasks', 'task.get', {'id': id}));
  const precise = {
    'plannedStartAt': '2026-10-10T18:00:00Z',
    'plannedEndAt': '2026-10-10T19:00:00Z',
    'plannedTimezone': 'Asia/Shanghai',
    'estimatedMinutes': 60,
  };

  test(
    'precise UTC tasks normalize their civil date and render their local times',
    () async {
      final created = await task({...precise, 'plannedDate': '2026-10-09'});
      expect(created['plannedDate'], '2026-10-11');
      expect(created['plannedStartAt'], '2026-10-10T18:00:00.000Z');
      expect(created, await raw(created['id']));
      final page = object(
        await host.invokePage('app.views.today', 'render', {
          'context': {
            'pageId': 'app.views.today.tasks',
            'selectedDate': '2026-10-11',
          },
        }),
      );
      expect(
        nodes(page['tree'])
            .singleWhere((n) => n['type'] == 'taskItem')['subtitle'],
        contains('2026-10-11 02:00–03:00 (Asia/Shanghai)'),
      );
      await command('app.tasks', 'task.updateFields', {
        'id': created['id'],
        'changes': {'plannedDate': '2026-10-12'},
      });
      final changed = await raw(created['id']);
      expect(changed['plannedDate'], '2026-10-12');
      for (final field in [
        'plannedStartAt',
        'plannedEndAt',
        'plannedTimezone',
      ]) {
        expect(changed[field], isNull);
      }
      expect(changed['estimatedMinutes'], 60);
    },
  );

  test('precise tasks reject invalid instants and partial ranges', () async {
    for (final changes in [
      {'plannedStartAt': '2026-10-10T18:00:00+00:00'},
      {'plannedStartAt': '2026-02-30T18:00:00Z'},
      {'plannedStartAt': '2026-10-10T19:00:00Z'},
      {'plannedTimezone': 'Invalid/Zone'},
      {'estimatedMinutes': 0},
      {'executionExpiresOn': '2026-02-30'},
    ]) {
      await expectLater(
        task({...precise, ...changes}),
        throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
      );
    }
    await expectLater(
      task({'plannedStartAt': precise['plannedStartAt']}),
      throwsA(isA<StateError>()),
    );
    expect(await query('app.tasks', 'task.list', {'view': 'raw'}), isEmpty);
  });

  test('completion correction preserves audit time, associates history and reopening clears actual date', () async {
    final created = await task({'plannedDate': '2026-10-07'});
    final completed = object(
      await command('app.tasks', 'task.setCompleted', {
        'id': created['id'],
        'completed': true,
        'actualCompletedOn': '2026-10-08',
        'completedTimezone': 'Asia/Shanghai',
      }),
    );
    host.clockNow = () => DateTime.utc(2026, 10, 10, 7);
    final corrected = object(
      await command('app.tasks', 'task.setCompleted', {
        'id': created['id'],
        'completed': true,
        'actualCompletedOn': '2026-10-09',
        'expectedValues': completed,
      }),
    );
    expect(corrected['completedAt'], completed['completedAt']);
    expect(corrected['updatedAt'], isNot(completed['updatedAt']));
    expect(corrected['completedTimezone'], 'Asia/Shanghai');
    expect(
      objects(
        await query('app.tasks', 'task.list', {
          'view': 'daily',
          'date': '2026-10-09',
        }),
      ),
      hasLength(1),
    );
    expect(
      await query('app.tasks', 'task.list', {
        'view': 'daily',
        'date': '2026-10-08',
      }),
      isEmpty,
    );
    final reopened = object(
      await command('app.tasks', 'task.setCompleted', {
        'id': created['id'],
        'completed': false,
      }),
    );
    expect(reopened['completedAt'], isNull);
    expect(reopened['actualCompletedOn'], isNull);
    expect(reopened['completedTimezone'], isNull);
    final defaultCompleted = object(
      await command('app.tasks', 'task.setCompleted', {
        'id': created['id'],
        'completed': true,
      }),
    );
    expect(defaultCompleted['actualCompletedOn'], '2026-10-10');
    expect(defaultCompleted['completedTimezone'], 'UTC');
  });

  test('expiry and completion membership match dayCounts for historical, today and future dates', () async {
    await task({
      'title': 'expired',
      'dueDate': '2026-10-08',
      'executionExpiresOn': '2026-10-09',
    });
    await task({
      'title': 'ends today',
      'dueDate': '2026-10-08',
      'plannedDate': '2026-10-11',
      'executionExpiresOn': '2026-10-10',
    });
    await task({
      'title': 'future',
      'plannedDate': '2026-10-11',
      'executionExpiresOn': '2026-10-11',
    });
    final done = await task({
      'title': 'done',
      'plannedDate': '2026-10-08',
      'executionExpiresOn': '2026-10-08',
    });
    await command('app.tasks', 'task.setCompleted', {
      'id': done['id'],
      'completed': true,
      'actualCompletedOn': '2026-10-09',
    });
    final dates = ['2026-10-08', '2026-10-09', '2026-10-10', '2026-10-11'];
    final counts = object(
      await query('app.tasks', 'task.dayCounts', {'dates': dates}),
    );
    for (final day in objects(counts['days'])) {
      final listed = objects(
        await query('app.tasks', 'task.list', {
          'view': 'daily',
          'date': day['date'],
        }),
      );
      expect(
        day['pending'],
        listed.where((t) => t['completed'] == false).length,
      );
      expect(
        day['completed'],
        listed.where((t) => t['completed'] == true).length,
      );
    }
    expect(
      objects(await query('app.tasks', 'task.list', {'view': 'today'}))
          .map((t) => t['title']),
      ['ends today'],
    );
    expect(
      objects(
        await query('app.tasks', 'task.list', {
          'view': 'daily',
          'date': '2026-10-11',
        }),
      ).map((t) => t['title']),
      ['future'],
    );
  });

  test('range is half-open and includes all nondeleted precise tasks; restore is conditional and exact', () async {
    final created = await task(precise);
    final archived = {
      ...created,
      'archivedAt': '2026-10-10T06:00:00.000Z',
      'notes': 'preserve exact raw fields',
    };
    await command('app.tasks', 'task.restore', {
      'id': created['id'],
      'expected': created,
      'value': archived,
    });
    expect(
      await query('app.tasks', 'task.range', {
        'startAt': '2026-10-10T19:00:00Z',
        'endAt': '2026-10-10T20:00:00Z',
      }),
      isEmpty,
    );
    expect(
      await query('app.tasks', 'task.range', {
        'startAt': '2026-10-10T17:00:00Z',
        'endAt': '2026-10-10T18:00:00Z',
      }),
      isEmpty,
    );
    expect(
      objects(
        await query('app.tasks', 'task.range', {
          'startAt': '2026-10-10T18:30:00Z',
          'endAt': '2026-10-10T19:30:00Z',
        }),
      ),
      [archived],
    );
    await expectLater(
      command('app.tasks', 'task.restore', {
        'id': created['id'],
        'expected': created,
        'value': null,
      }),
      throwsA(isA<StateError>()),
    );
    expect(await raw(created['id']), archived);
    await command('app.tasks', 'task.restore', {
      'id': created['id'],
      'expected': archived,
      'value': created,
    });
    expect(await raw(created['id']), created);
    await command('app.tasks', 'task.restore', {
      'id': created['id'],
      'expected': created,
      'value': null,
    });
    expect(await query('app.tasks', 'task.get', {'id': created['id']}), isNull);
  });

  test(
    'old expectedValues snapshots remain valid and detect changed values',
    () async {
      final created = await task({'plannedDate': '2026-10-10'});
      final oldSnapshot = {
        for (final field in [
          'id',
          'title',
          'priority',
          'dueDate',
          'plannedDate',
          'projectId',
          'parentTaskId',
          'completedAt',
          'archivedAt',
          'deletedAt',
          'updatedAt',
        ])
          field: created[field],
      };
      await command('app.tasks', 'task.updateFields', {
        'id': created['id'],
        'expectedValues': oldSnapshot,
        'changes': {'title': 'edited'},
      });
      await expectLater(
        command('app.tasks', 'task.updateFields', {
          'id': created['id'],
          'expectedValues': oldSnapshot,
          'changes': {'title': 'stale'},
        }),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('busy merges every timetable and honors cancellation, replacement and extra occurrences', () async {
    for (final id in ['shanghai', 'utc']) {
      await command('app.schedule', 'schedule.timetable.save', {
        'timetable': table(id, zone: id == 'utc' ? 'UTC' : 'Asia/Shanghai'),
      });
      await command('app.schedule', 'schedule.course.save', {
        'course': {'id': '$id-course', 'timetableId': id, 'name': id},
        'meeting': {
          'id': '$id-meeting',
          'weekday': 6,
          'startPeriod': 1,
          'endPeriod': 1,
          'weeks': [1],
        },
      });
    }
    await command('app.schedule', 'schedule.change.save', {
      'change': {
        'id': 'cancelled',
        'timetableId': 'shanghai',
        'kind': 'cancel',
        'meetingId': 'shanghai-meeting',
        'originalDate': '2026-10-10',
      },
    });
    await command('app.schedule', 'schedule.change.save', {
      'change': {
        'id': 'replaced',
        'timetableId': 'utc',
        'kind': 'replace',
        'meetingId': 'utc-meeting',
        'originalDate': '2026-10-10',
        'date': '2026-10-11',
        'startPeriod': 1,
        'endPeriod': 1,
      },
    });
    await command('app.schedule', 'schedule.change.save', {
      'change': {
        'id': 'extra',
        'timetableId': 'shanghai',
        'kind': 'extra',
        'courseId': 'shanghai-course',
        'originalDate': '2026-10-10',
        'date': '2026-10-11',
        'startPeriod': 1,
        'endPeriod': 1,
      },
    });
    final before = await store.sql(
      'SELECT * FROM host_records ORDER BY module_id,collection,id',
    );
    final busy = object(
      await query('app.schedule', 'schedule.query.busy', {
        'startDate': '2026-10-10',
        'endDate': '2026-10-11',
      }),
    );
    final items = objects(busy['items']);
    expect(items.map((item) => item['id']), [
      'shanghai|extra',
      'utc|utc-meeting:2026-10-10',
    ]);
    expect(
      DateTime.parse(items[0]['startAt'] as String),
      DateTime.utc(2026, 10, 11),
    );
    expect(
      DateTime.parse(items[1]['startAt'] as String),
      DateTime.utc(2026, 10, 11, 8),
    );
    expect(
      await store.sql(
        'SELECT * FROM host_records ORDER BY module_id,collection,id',
      ),
      before,
    );
    for (final range in [
      {'startDate': '2026-10-12', 'endDate': '2026-10-11'},
      {'startDate': '2026-10-01', 'endDate': '2026-10-31'},
      {'startDate': '2026-02-30', 'endDate': '2026-03-01'},
    ]) {
      await expectLater(
        query('app.schedule', 'schedule.query.busy', range),
        throwsA(isA<StateError>()),
      );
    }
  });

  test(
    'busy rejects ambiguous and nonexistent DST period boundaries',
    () async {
      for (final scenario in [
        {
          'id': 'gap',
          'monday': '2026-03-02',
          'date': '2026-03-08',
          'start': '02:15',
          'end': '03:15',
        },
        {
          'id': 'fold',
          'monday': '2026-10-26',
          'date': '2026-11-01',
          'start': '01:15',
          'end': '02:15',
        },
      ]) {
        final id = scenario['id']!;
        await command('app.schedule', 'schedule.timetable.save', {
          'timetable': table(
            id,
            zone: 'America/New_York',
            monday: scenario['monday']!,
            start: scenario['start']!,
            end: scenario['end']!,
          ),
        });
        await command('app.schedule', 'schedule.course.save', {
          'course': {'id': '$id-course', 'timetableId': id, 'name': id},
          'meeting': {
            'id': '$id-meeting',
            'weekday': 7,
            'startPeriod': 1,
            'endPeriod': 1,
            'weeks': [1],
          },
        });
        await expectLater(
          query('app.schedule', 'schedule.query.busy', {
            'startDate': scenario['date'],
            'endDate': scenario['date'],
          }),
          throwsA(isA<StateError>()),
        );
      }
    },
  );
}
