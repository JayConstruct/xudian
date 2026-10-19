import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'planner_task_schedule_test.dart'
    show nodes, objects, sourcePackage, table;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('planner-color-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 13);
    await host.initialize();
    for (final id in ['app.tasks', 'app.schedule', 'app.planner']) {
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

  Future<Map<String, Object?>> board() async {
    final rendered = await host.invokePage('app.planner', 'render', {
      'context': {'pageId': 'app.planner.home'},
    });
    return nodes(rendered)
        .singleWhere((node) => node['type'] == 'plannerBoard');
  }

  test('task color identity survives scheduling and drag preview', () async {
    final created = object(
      await command('app.tasks', 'task.create', {'title': '保持颜色的任务'}),
    );
    final candidate = objects((await board())['candidates']).single;
    expect(candidate['colorKey'], created['id']);

    final preview = object(
      await host.query(
        host.instances['app.planner']!.actor,
        const ServiceRef('app.planner', 'planner.operation.inspect', 1),
        {
          'proposal': {
            'intent': 'move',
            'taskId': created['id'],
            'start': '2026-10-13T18:00:00',
            'end': '2026-10-13T18:30:00',
          },
          'timezone': 'Asia/Shanghai',
        },
      ),
    );
    expect(
      objects(preview['previewBlocks']).single['colorKey'],
      candidate['colorKey'],
    );

    await command('app.tasks', 'task.updateFields', {
      'id': created['id'],
      'expectedUpdatedAt': created['updatedAt'],
      'changes': {
        'plannedStartAt': '2026-10-13T10:00:00Z',
        'plannedEndAt': '2026-10-13T10:30:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      },
    });
    final scheduled = objects((await board())['blocks']).single;
    expect(scheduled['colorKey'], candidate['colorKey']);
  });

  test(
    'all meetings keep their course color across schedule and planner',
    () async {
      await command('app.schedule', 'schedule.timetable.save', {
        'timetable': table('color-table'),
      });
      for (final weekday in [2, 3]) {
        await command('app.schedule', 'schedule.course.save', {
          'course': {
            'id': 'color-course',
            'timetableId': 'color-table',
            'name': '颜色课程',
            'color': '#AD71D8',
          },
          'meeting': {
            'id': 'color-meeting-$weekday',
            'weekday': weekday,
            'startPeriod': 1,
            'endPeriod': 1,
            'weeks': [2],
          },
        });
      }
      final feed = object(
        await host.query(
          host.instances['app.planner']!.actor,
          const ServiceRef('app.schedule', 'schedule.query.busy', 1),
          {'startDate': '2026-10-13', 'endDate': '2026-10-14'},
        ),
      );
      final meetings = objects(feed['items']);
      expect(meetings, hasLength(2));
      final blocks = objects((await board())['blocks']);
      expect(blocks, hasLength(2));
      for (final block in blocks) {
        final meeting = meetings.singleWhere(
          (item) => 'course:${item['id']}' == block['id'],
        );
        expect(block['courseId'], 'color-course');
        expect(block['colorKey'], 'color-course');
        expect(block['color'], '#AD71D8');
        expect(block['color'], meeting['color']);
      }
    },
  );
}
