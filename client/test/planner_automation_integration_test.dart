import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'planner_task_schedule_test.dart' show sourcePackage, objects;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  late DateTime now;

  final draft = <String, Object?>{
    'title': '自动间隔复习',
    'estimatedMinutes': 30,
    'firstDate': '2026-10-21',
    'timezone': 'UTC',
    'rules': {
      'interval': {'minDays': 4, 'maxDays': 4},
      'timeWindow': {'start': '18:00', 'end': '22:00'},
    },
  };

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('planner-auto-chain-');
    now = DateTime.utc(2026, 10, 21, 8);
    host = ModuleHost(store: store, directory: directory)..clockNow = () => now;
    await host.initialize();
    await host.install(await sourcePackage('app.tasks'));
    await host.install(await sourcePackage('app.planner'));
    await host.drainAutomation();
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<Map<String, Object?>> query(
    String id, [
    Map<String, Object?> input = const {},
  ]) async => object(
    await host.query(
      host.instances['app.planner']!.actor,
      ServiceRef('app.planner', 'planner.$id', 1),
      input,
    ),
  );

  Future<Map<String, Object?>> command(
    String module,
    String id,
    Map<String, Object?> input,
  ) async {
    final actor = host.instances[module]!.actor;
    final plan = await host.prepare(actor, ServiceRef(module, id, 1), input);
    host.review(plan.id, actor);
    return object(await host.commit(actor, plan.id));
  }

  Future<Map<String, Object?>> run(String id, Map<String, Object?> input) =>
      command('app.planner', 'planner.$id', input);

  Future<List<Map<String, Object?>>> tasks() async {
    final rows = objects(
      await host.query(
        host.instances['app.tasks']!.actor,
        const ServiceRef('app.tasks', 'task.list', 1),
        {'view': 'raw', 'limit': 1000},
      ),
    );
    rows.sort(
      (a, b) => (a['plannedStartAt'] as String).compareTo(
        b['plannedStartAt'] as String,
      ),
    );
    return rows;
  }

  Future<void> create(String id, [Map<String, Object?>? value]) async {
    final preview = await query('creation.preview', value ?? draft);
    expect(preview['confirmable'], true);
    await run('creation.apply', {'creationKey': id, 'preview': preview});
  }

  Future<Map<String, Object?>> series(String id) async => object(
    await store.get(host.instances['app.planner']!.actor, 'series', id),
  );

  Future<void> availability(String start, String end) =>
      run('availability.save', {
        'availability': {
          'timezone': 'UTC',
          'weekly': {
            for (var day = 1; day <= 7; day++)
              '$day': [
                {'start': start, 'end': end},
              ],
          },
        },
      });

  void expectNoOverlap(List<Map<String, Object?>> rows) {
    for (var i = 0; i < rows.length; i++) {
      for (var j = i + 1; j < rows.length; j++) {
        if (rows[i]['completedAt'] != null || rows[j]['completedAt'] != null) {
          continue;
        }
        final overlap =
            DateTime.parse(rows[i]['plannedStartAt'] as String)
                .isBefore(DateTime.parse(rows[j]['plannedEndAt'] as String)) &&
            DateTime.parse(rows[j]['plannedStartAt'] as String)
                .isBefore(DateTime.parse(rows[i]['plannedEndAt'] as String));
        expect(
          overlap,
          false,
          reason:
              '${rows[i]['title']} and ${rows[j]['title']} overlap on ${rows[i]['plannedStartAt']}',
        );
      }
    }
  }

  test(
    'confirmed automation extends day ten and preserves manual/completed tasks',
    () async {
      await create('daily-chain');
      final initial = await tasks();
      final edited = initial[2];
      final move = await query('operation.preview', {
        'taskId': edited['id'],
        'date': edited['plannedDate'],
        'start': '19:00',
        'end': '19:30',
        'timezone': 'UTC',
        'scope': 'only',
      });
      expect(move['confirmable'], true);
      await run('operation.apply', {'operationKey': 'manual', 'preview': move});
      await command('app.tasks', 'task.setCompleted', {
        'id': initial.first['id'],
        'completed': true,
      });
      final before = await tasks();
      now = now.add(const Duration(days: 10));
      await host.checkClockAutomation(force: true);
      final after = await tasks();
      expect(after.length, greaterThan(before.length));
      for (final task in before) {
        expect(after.singleWhere((row) => row['id'] == task['id']), task);
      }
      final added = after.where(
        (row) => !before.any((old) => old['id'] == row['id']),
      );
      for (final task in added) {
        expect(
          DateTime.parse(task['plannedDate'] as String).millisecondsSinceEpoch,
          inInclusiveRange(
            DateTime.utc(2026, 10, 31).millisecondsSinceEpoch,
            DateTime.utc(2026, 11, 29).millisecondsSinceEpoch,
          ),
        );
      }
      expect((await series('daily-chain'))['windowThrough'], '2026-11-29');
      final commits = (await store.sql('SELECT * FROM host_commits')).length;
      now = now.add(const Duration(minutes: 1));
      await host.checkClockAutomation();
      await host.checkClockAutomation(force: true);
      expect(await tasks(), after);
      expect(await store.sql('SELECT * FROM host_commits'), hasLength(commits));
    },
  );

  test(
    'multiple series share new occupancy during automatic replenishment',
    () async {
      await create('first');
      await create('second', {...draft, 'title': '另一门复习'});
      expectNoOverlap(await tasks());
      now = now.add(const Duration(days: 10));
      await host.checkClockAutomation(force: true);
      expectNoOverlap(await tasks());
    },
  );

  test('blocked plans retain reasons and retry after capacity returns on the same day', () async {
    await create('late', {
      ...draft,
      'rules': {
        'interval': {'minDays': 4, 'maxDays': 4},
        'timeWindow': {'start': '20:00', 'end': '21:00'},
      },
    });
    await availability('18:00', '19:00');
    final before = await tasks();
    now = now.add(const Duration(days: 10));
    await host.checkClockAutomation(force: true);
    expect((await series('late'))['blocked'], isNotEmpty);
    expect(await tasks(), before);
    await availability('18:00', '22:00');
    now = now.add(const Duration(minutes: 1));
    await host.checkClockAutomation();
    expect((await tasks()).length, greaterThan(before.length));
    expect((await series('late'))['blocked'], isEmpty);
  });

  test(
    'disabled planner stays stopped; enable and cold restore catch up',
    () async {
      await create('lifecycle');
      final before = await tasks();
      await host.disable('app.planner');
      now = now.add(const Duration(days: 10));
      await host.checkClockAutomation(force: true);
      expect(await tasks(), before);
      await host.enable('app.planner');
      await host.drainAutomation();
      final enabled = await tasks();
      expect(enabled.length, greaterThan(before.length));
      await host.close();
      now = now.add(const Duration(days: 10));
      host = ModuleHost(store: store, directory: directory)
        ..clockNow = () => now;
      await host.initialize();
      await host.drainAutomation();
      expect((await tasks()).length, greaterThan(enabled.length));
      for (final task in enabled) {
        expect(
          (await tasks()).singleWhere((row) => row['id'] == task['id']),
          task,
        );
      }
    },
  );

  test(
    'unconfirmed drafts and explicit auto-extend opt-out never replenish',
    () async {
      final preview = await query('creation.preview', draft);
      expect(preview['confirmable'], true);
      await host.checkClockAutomation(force: true);
      expect(await tasks(), isEmpty);
      await create('opt-out', {...draft, 'autoExtend': false});
      final before = await tasks();
      now = now.add(const Duration(days: 10));
      await host.checkClockAutomation(force: true);
      expect(await tasks(), before);
      expect((await series('opt-out'))['windowThrough'], '2026-11-19');
    },
  );

  test(
    'a stale preview and an unreviewed prepared creation cannot write',
    () async {
      final preview = await query('creation.preview', draft);
      final actor = host.instances['app.planner']!.actor;
      final plan = await host.prepare(
        actor,
        const ServiceRef('app.planner', 'planner.creation.apply', 1),
        {'creationKey': 'unreviewed', 'preview': preview},
      );
      await expectLater(host.commit(actor, plan.id), throwsA(anything));
      expect(await tasks(), isEmpty);
      await create('changed');
      await expectLater(
        run('creation.apply', {'creationKey': 'stale', 'preview': preview}),
        throwsA(anything),
      );
      expect(await store.get(actor, 'series', 'stale'), isNull);
    },
  );
}
