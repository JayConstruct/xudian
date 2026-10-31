import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'daily_date_browsing_test.dart' show sourcePackage, nodes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;

  Future<Map<String, Object?>> command(
    String module,
    String service,
    Map<String, Object?> input,
  ) async {
    final actor = host.instances[module]!.actor;
    final plan = await host.prepare(
      actor,
      ServiceRef(module, service, 1),
      input,
    );
    host.review(plan.id, actor);
    return object(await host.commit(actor, plan.id));
  }

  Future<Map<String, Object?>> render({
    Object? event,
    Object? state,
    String date = '2026-10-30',
  }) async => object(
    await host.invokePage('app.views.today', 'render', {
      'context': {'pageId': 'app.views.today.tasks', 'selectedDate': date},
      'event': event,
      'state': state ?? {},
    }),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('daily-fusion-');
    host = ModuleHost(store: store, directory: directory)
      ..clockNow = () => DateTime.utc(2026, 10, 30, 10, 20);
    await host.initialize();
    for (final id in ['app.tasks', 'app.views.today', 'app.schedule']) {
      await host.install(await sourcePackage(id));
    }
    await command('app.schedule', 'schedule.timetable.save', {
      'timetable': {
        'id': 'table',
        'name': '课程表',
        'firstMonday': '2026-10-26',
        'totalWeeks': 20,
        'timezone': 'UTC',
        'displayWeekStart': 1,
        'periods': [
          {'number': 1, 'start': '10:30', 'end': '12:00'},
        ],
      },
    });
    await command('app.schedule', 'schedule.course.save', {
      'course': {'id': 'course', 'timetableId': 'table', 'name': '交互设计'},
      'meeting': {
        'id': 'meeting',
        'weekday': 5,
        'startPeriod': 1,
        'endPeriod': 1,
        'weeks': [1],
        'location': '工教楼203',
      },
    });
    for (final hour in [14, 9]) {
      await command('app.tasks', 'task.create', {
        'title': '$hour 点任务',
        'plannedStartAt':
            '2026-10-30T${hour.toString().padLeft(2, '0')}:00:00.000Z',
        'plannedEndAt':
            '2026-10-30T${(hour + 1).toString().padLeft(2, '0')}:00:00.000Z',
        'plannedTimezone': 'UTC',
      });
    }
    await command('app.tasks', 'task.create', {
      'title': '待安排任务',
      'plannedDate': '2026-10-30',
    });
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  test('real courses and timed tasks interleave, with one next-course banner and original navigation', () async {
    final page = await render();
    final rows = nodes(page['tree'])
        .where(
          (node) => node['type'] == 'agendaItem' || node['type'] == 'taskItem',
        )
        .toList();
    expect(
      rows.where((row) => row['hideTime'] != true).map((row) => row['title']),
      ['9 点任务', '交互设计', '14 点任务', '待安排任务'],
    );
    expect(
      rows.singleWhere((row) => row['hideTime'] == true)['badge'],
      '还有 10 分钟',
    );
    expect(
      nodes(page['tree'])
          .singleWhere((node) => node['key'] == 'feed:heading')['title'],
      '3 项待办 · 1 节课程',
    );
    final calls = <Map<String, Object?>>[];
    host.interaction = (_, method, args) async {
      calls.add({'method': method, ...args});
      return null;
    };
    await render(
      event: rows.singleWhere(
        (row) => row['type'] == 'agendaItem' && row['hideTime'] != true,
      )['event'],
    );
    expect(calls.single['page'], 'app.schedule.occurrence');
    expect(object(calls.single['context'])['meetingId'], 'meeting');
  });

  test(
    'optional course provider can be disabled without losing tasks',
    () async {
      await host.disable('app.schedule');
      final page = await render();
      expect(host.instances.containsKey('app.views.today'), true);
      expect(
        nodes(page['tree']).where((node) => node['type'] == 'agendaItem'),
        isEmpty,
      );
      expect(
        nodes(page['tree']).where((node) => node['type'] == 'taskItem'),
        hasLength(3),
      );
    },
  );

  test('completion remains reviewed and keeps the task in its time slot exactly once', () async {
    var page = await render();
    final originalKeys = nodes(page['tree'])
        .where(
          (node) => node['type'] == 'taskItem' || node['type'] == 'agendaItem',
        )
        .map((node) => node['key'])
        .toList();
    final row = nodes(page['tree']).singleWhere(
      (node) => node['title'] == '14 点任务' && node['type'] == 'taskItem',
    );
    final task = object(object(row['event'])['task']);
    final event = {...object(row['event']), 'value': true};
    host.interaction = (_, method, _) async =>
        method == 'ui.review' ? false : null;
    await render(event: event);
    var record = object(
      await store.get(
        host.instances['app.tasks']!.actor,
        'tasks',
        task['id'] as String,
      ),
    );
    expect(record['completedAt'], isNull);
    host.interaction = (_, method, _) async =>
        method == 'ui.review' ? true : null;
    page = await render(event: event);
    final rows = nodes(
      page['tree'],
    ).where((node) => node['type'] == 'taskItem' && node['title'] == '14 点任务');
    expect(rows, hasLength(1));
    expect(rows.single['completed'], true);
    expect(rows.single['startTime'], '14:00');
    expect(rows.single['endTime'], '15:00');
    expect(rows.single['colorKey'], row['colorKey']);
    expect(rows.single['subtitle'], contains('已完成'));
    expect(object(page['tree'])['removeKeys'], isEmpty);
    expect(
      nodes(page['tree'])
          .where((node) => node['key'] == 'feed:completed-heading'),
      isEmpty,
    );
    expect(
      nodes(page['tree'])
          .where(
            (node) =>
                node['type'] == 'taskItem' || node['type'] == 'agendaItem',
          )
          .map((node) => node['key']),
      originalKeys,
    );
    page = await render();
    expect(
      nodes(page['tree'])
          .where(
            (node) =>
                node['type'] == 'taskItem' || node['type'] == 'agendaItem',
          )
          .map((node) => node['key']),
      originalKeys,
    );
    final completed = nodes(page['tree'])
        .singleWhere((node) => node['key'] == row['key']);
    page = await render(event: {...object(completed['event']), 'value': false});
    expect(
      nodes(page['tree'])
          .singleWhere((node) => node['key'] == row['key'])['completed'],
      false,
    );
    expect(
      nodes(page['tree'])
          .where(
            (node) =>
                node['type'] == 'taskItem' || node['type'] == 'agendaItem',
          )
          .map((node) => node['key']),
      originalKeys,
    );
  });

  test(
    'untimed completion retains the original group and relative order',
    () async {
      await command('app.tasks', 'task.create', {
        'title': '后面的待安排任务',
        'plannedDate': '2026-10-30',
      });
      var page = await render();
      final children = object(page['tree'])['children'] as List;
      final keys = children.map((node) => object(node)['key']).toList();
      final row = nodes(page['tree']).singleWhere(
        (node) => node['title'] == '待安排任务' && node['type'] == 'taskItem',
      );
      host.interaction = (_, method, _) async =>
          method == 'ui.review' ? true : null;
      page = await render(event: {...object(row['event']), 'value': true});
      expect(
        (object(page['tree'])['children'] as List).map(
          (node) => object(node)['key'],
        ),
        keys,
      );
      expect(
        nodes(page['tree'])
            .singleWhere((node) => node['key'] == row['key'])['completed'],
        true,
      );
      expect(
        nodes(
          page['tree'],
        ).singleWhere((node) => node['key'] == 'feed:pending-heading')['count'],
        2,
      );
    },
  );

  test('completed future plans retain their original day, including overnight time slots', () async {
    final result = await command('app.tasks', 'task.create', {
      'title': '跨夜任务',
      'plannedStartAt': '2026-10-31T23:30:00.000Z',
      'plannedEndAt': '2026-11-01T00:30:00.000Z',
      'plannedTimezone': 'UTC',
    });
    await command('app.tasks', 'task.setCompleted', {
      'id': result['id'],
      'completed': true,
      'completedTimezone': 'UTC',
    });
    final page = await render(date: '2026-10-31');
    final row = nodes(page['tree'])
        .singleWhere((node) => node['key'] == result['id']);
    expect(row['completed'], true);
    expect(row['startTime'], '23:30');
    expect(row['endTime'], '次日 00:30');
    expect(
      nodes(page['tree']).where((node) => node['key'] == 'feed:empty'),
      isEmpty,
    );
    final overview = object(
      await host.invokePage('app.views.today', 'render', {
        'context': {
          'pageId': 'app.views.today.overview',
          'selectedDate': '2026-10-31',
        },
      }),
    );
    expect(object(overview['tree'])['summary'], '0 项待办 · 1 项已完成');
    host.clockNow = () => DateTime.utc(2026, 11, 1, 10);
    final history = await render(date: '2026-10-31');
    expect(
      nodes(history['tree'])
          .singleWhere((node) => node['key'] == result['id'])['startTime'],
      '23:30',
    );
  });
}
