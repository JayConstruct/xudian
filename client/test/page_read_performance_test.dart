import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/clock_conversion.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/performance/ui_load_trace.dart';
import 'package:task_app/data/app_database.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:xquickjs/xquickjs.dart';

Future<Map<String, String>> _sources(String moduleId) async {
  final folder = Directory('../packages/modules/$moduleId');
  final files = <String, String>{};
  await for (final file in folder.list(recursive: true)) {
    if (file is File && file.path.endsWith('.js')) {
      files[file.path.substring(folder.path.length + 1)] = await file.readAsString();
    }
  }
  return files;
}

void main() {
  setUpAll(zones.initializeTimeZones);

  test('production today page makes one traced host batch for 50 plans', () async {
    final samples = <UiLoadSample>[];
    await UiLoadTrace.observe(() async {
      final db = AppDatabase(NativeDatabase.memory());
      final store = CollectionStore(db);
      final directory = await Directory.systemTemp.createTemp('today-read-perf-');
      final host = ModuleHost(store: store, directory: directory);
      host.clockNow = () => DateTime.utc(2026, 11, 1, 12);
      try {
        await host.initialize();
        for (final id in ['app.tasks', 'app.views.today']) {
          final definition = object(jsonDecode(await File('../packages/modules/$id/module.json').readAsString()));
          await host.install(await ScriptPackage.verify(
            await ScriptPackage.build(definition, await _sources(id)),
            allowUnsignedLocal: true,
          ));
        }
        final actor = host.instances['app.tasks']!.actor;
        final session = SnapshotSession(actor, 'seed-50-precise-plans');
        await store.stage(session, actor, {
          'writes': [
            for (var index = 0; index < 50; index++)
              {
                'collection': 'tasks',
                'id': 'task-${index.toString().padLeft(2, '0')}',
                'value': {
                  'id': 'task-${index.toString().padLeft(2, '0')}',
                  'title': '任务 $index',
                  'priority': 0,
                  'plannedDate': '2026-11-01',
                  'plannedStartAt': '2026-11-01T05:30:00Z',
                  'plannedEndAt': '2026-11-01T06:30:00Z',
                  'plannedTimezone': 'America/New_York',
                  'createdAt': '2026-10-31T00:00:00Z',
                  'updatedAt': '2026-10-31T00:00:00Z',
                },
              },
          ],
        });
        await store.commit(store.seal(session).id, actor, authorize: (_) {}, audit: false);
        samples.clear();
        final rendered = object(await host.invokePage('app.views.today', 'render', {
          'context': {'pageId': 'app.views.today.tasks', 'selectedDate': '2026-11-01'},
        }, readOnly: true));
        final rows = (object(rendered['tree'])['children'] as List)
            .where((node) => object(node)['type'] == 'taskItem')
            .map(object)
            .toList();
        expect(rows, hasLength(50));
        expect(rows.every((row) => row['subtitle'] == '计划 01:30–01:30 (America/New_York)'), isTrue);
        final bridges = samples.where((sample) => sample.name == 'page.bridge');
        expect(bridges.where((sample) => sample.arguments['method'] == 'clock.toLocalMany'), hasLength(1));
        expect(bridges.where((sample) => sample.arguments['method'] == 'clock.toLocal'), isEmpty);
        for (final sample in bridges) {
          expect(sample.arguments.keys.toSet(), {'moduleId', 'method', 'outcome'});
        }
      } finally {
        await host.close();
        await store.close();
        await db.close();
        await directory.delete(recursive: true);
      }
    }, samples.add);
  });

  for (final count in [0, 50, 129]) {
    test('real today script batches $count precise plans with equal labels', () async {
      final tasks = List.generate(count, (index) => <String, Object?>{
        'id': 'task-$index',
        'title': '任务 $index',
        'plannedStartAt': '2026-11-01T05:30:00Z',
        'plannedEndAt': '2026-11-01T06:30:00Z',
        'plannedTimezone': index.isEven ? 'America/New_York' : 'Asia/Shanghai',
        'plannedDate': '2026-11-01',
      });
      tasks.add({'id': 'date-only', 'title': '按日安排', 'plannedDate': '2026-11-01'});
      var batchCalls = 0;
      var singleCalls = 0;
      final sizes = <int>[];
      final worker = JavaScriptWorker(await _sources('app.views.today'), host: (method, raw) async {
        final args = object(raw);
        switch (method) {
          case 'clock.today':
            return '2026-11-01';
          case 'services.query':
            return object(args['ref'])['serviceId'] == 'task.list' ? tasks : [];
          case 'clock.toLocalMany':
            batchCalls++;
            sizes.add((args['items'] as List).length);
            return clockToLocalMany(args);
          case 'clock.toLocal':
            singleCalls++;
            return clockToLocal(args);
          default:
            throw StateError('Unexpected bridge request: $method');
        }
      });
      addTearDown(worker.close);
      await worker.load('main.js');
      final rendered = object(await worker.invoke('render', {
        'context': {'pageId': 'app.views.today.tasks', 'selectedDate': '2026-11-01'},
        'state': {'selectedDate': '2026-11-01', 'taskLimit': 150},
      }));
      final rows = (object(rendered['tree'])['children'] as List)
          .where((node) => object(node)['type'] == 'taskItem')
          .map(object)
          .toList();
      expect(rows, hasLength(tasks.length));
      for (var index = 0; index < count; index++) {
        final task = tasks[index];
        final start = clockToLocal({'utc': task['plannedStartAt'], 'zone': task['plannedTimezone']});
        final end = clockToLocal({'utc': task['plannedEndAt'], 'zone': task['plannedTimezone']});
        expect(start['date'], '2026-11-01');
        expect(end['date'], start['date']);
        expect(rows[index]['subtitle'], '计划 ${start['time']}–${end['time']} (${task['plannedTimezone']})');
      }
      expect(rows.last['subtitle'], '计划 当天');
      expect(singleCalls, 0);
      expect(batchCalls, (count / 128).ceil());
      expect(sizes, count == 0 ? [] : count == 50 ? [100] : [256, 2]);
    });
  }

  test('real schedule feed reuses timetables and dispatches independent reads', () async {
    final tables = [
      for (final zone in ['America/New_York', 'Asia/Shanghai'])
        <String, Object?>{
          'id': zone,
          'name': zone,
          'firstMonday': '2026-10-26',
          'totalWeeks': 2,
          'timezone': zone,
          'periods': [{'number': 1, 'start': '09:00', 'end': '10:00'}],
        },
    ];
    final collections = <String>[];
    final outstanding = <String, Completer<Object?>>{};
    var gets = 0;
    var zonedTodayCalls = 0;
    var localCalls = 0;
    final worker = JavaScriptWorker(await _sources('app.schedule'), host: (method, raw) async {
      final args = object(raw);
      switch (method) {
        case 'clock.today':
          if (args['zone'] != null) zonedTodayCalls++;
          return '2026-11-01';
        case 'clock.local':
          localCalls++;
          return clockToLocal({'utc': '2026-11-01T03:00:00Z', 'zone': args['zone']});
        case 'data.get':
          gets++;
          return tables.firstWhere((table) => table['id'] == args['id']);
        case 'data.query':
          final collection = args['collection'] as String;
          collections.add(collection);
          if (collection == 'timetables') return tables;
          final tableId = object(args['filter'])['value'];
          final reply = Completer<Object?>();
          outstanding[collection] = reply;
          // No reply until all three requests arrive. A serialized script
          // cannot finish this fixture; this checks actual QuickJS dispatch.
          if (outstanding.length == 3) {
            outstanding['courses']!.complete([
              {'id': 'course', 'timetableId': tableId, 'name': '数学'},
            ]);
            outstanding['meetings']!.complete([
              {'id': 'meeting', 'courseId': 'course', 'timetableId': tableId,
                'weeks': [1], 'weekday': tableId == 'America/New_York' ? 6 : 7,
                'startPeriod': 1, 'endPeriod': 1},
            ]);
            outstanding['occurrenceChanges']!.complete([]);
            outstanding.clear();
          }
          return reply.future;
        default:
          throw StateError('Unexpected bridge request: $method');
      }
    });
    addTearDown(worker.close);
    await worker.load('main.js');
    final result = object(await worker.invoke('queryTodayFeed', {}));
    final items = (result['items'] as List).map(object).toList();
    expect(result['date'], '2026-11-01');
    expect(items.map((item) => item['date']), ['2026-10-31', '2026-11-01']);
    expect(items.map((item) => item['timezone']), ['America/New_York', 'Asia/Shanghai']);
    expect(items.map((item) => item['startOffset']), [-840, -120]);
    expect(items.every((item) => item['isLocalToday'] == true), isTrue);
    expect(gets, 0);
    expect(zonedTodayCalls, 0);
    expect(localCalls, 2);
    expect(collections.where((name) => name == 'timetables'), hasLength(1));
    for (final collection in ['courses', 'meetings', 'occurrenceChanges']) {
      expect(collections.where((name) => name == collection), hasLength(2));
    }
  });
}
