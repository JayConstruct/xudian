import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'schedule_today_feed_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  late ModuleActor actor;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('schedule-colors-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 5, 1);
    await host.initialize();
    await host.install(await fixture.sourcePackage('app.schedule'));
    actor = host.instances['app.schedule']!.actor;
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<Object?> command(String id, Map<String, Object?> input) async {
    final plan = await host.prepare(
      actor,
      ServiceRef('app.schedule', id, 1),
      input,
    );
    host.review(plan.id, actor);
    return host.commit(actor, plan.id);
  }

  Future<Map<String, Object?>> query(
    String id,
    Map<String, Object?> input,
  ) async =>
      object(await host.query(actor, ServiceRef('app.schedule', id, 1), input));
  Future<void> course(String id, {String? color, String? mode}) async {
    await command('schedule.course.save', {
      'course': {
        'id': id,
        'timetableId': 'table',
        'name': '课程 $id',
        'color': ?color,
        'colorMode': ?mode,
      },
      'meeting': {
        'id': 'meeting-$id',
        'weekday': 1,
        'startPeriod': 1,
        'endPeriod': 2,
        'weeks': [1, 2],
      },
    });
  }

  Future<Map<String, String>> weekColors({int week = 1}) async {
    final result = await query('schedule.query.week', {
      'timetableId': 'table',
      'teachingWeek': week,
    });
    return {
      for (final item in fixture.objects(result['items']))
        item['courseId'] as String: item['color'] as String,
    };
  }

  Future<Map<String, Object?>> providerSave(ChangePlan plan) async {
    host.interaction = (reviewActor, method, args) async {
      expect(reviewActor, same(actor));
      expect(method, 'ui.review');
      return true;
    };
    final context = {'pageId': 'app.schedule.imports', 'importPlanId': plan.id};
    final preview = object(
      await host.invokePage('app.schedule', 'render', {'context': context}),
    );
    final saved = object(
      await host.invokePage('app.schedule', 'render', {
        'context': context,
        'state': preview['state'],
        'event': {'type': 'confirmAdapter'},
      }),
    );
    return object(saved['state']);
  }

  test('automatic colors scale beyond a palette and remain stable across feeds without writes', () async {
    await command('schedule.timetable.save', {
      'timetable': fixture.table('table'),
    });
    for (var i = 0; i < 36; i++) {
      await course('course-$i', color: i.isEven ? '#486DA4' : null);
    }
    final before = await store.query(actor, 'courses', {});
    final colors = await weekColors();
    expect(colors.values.toSet(), hasLength(36));
    expect(colors.values, everyElement(matches(RegExp(r'^#[0-9a-f]{6}$'))));
    expect(colors.values, isNot(contains('#486DA4')));
    expect(await weekColors(week: 2), colors);
    for (final service in ['schedule.query.todayFeed', 'schedule.query.busy']) {
      final result = await query(
        service,
        service.endsWith('busy')
            ? {'startDate': '2026-10-05', 'endDate': '2026-10-05'}
            : {'date': '2026-10-05'},
      );
      expect({
        for (final item in fixture.objects(result['items']))
          item['courseId'] as String: item['color'] as String,
      }, colors);
    }
    expect(await store.query(actor, 'courses', {}), before);
    final original = object(await store.get(actor, 'courses', 'course-0'));
    await command('schedule.course.save', {
      'course': {...original, 'name': '重命名课程'},
    });
    await course('new-course');
    final after = await weekColors();
    for (final entry in colors.entries) {
      expect(after[entry.key], entry.value);
    }
  });

  test(
    'explicit choices and imported palette colors survive automatic defaults',
    () async {
      await command('schedule.timetable.save', {
        'timetable': fixture.table('table'),
      });
      await course('custom-blue', color: '#486DA4', mode: 'custom');
      await course('existing-pink', color: '#B05A81');
      await course('auto-blue', color: '#486DA4');
      await course('auto-mode', color: '#B05A81', mode: 'auto');
      await course('invalid', color: 'broken');
      final colors = await weekColors();
      expect(colors['custom-blue'], '#486DA4');
      expect(colors['existing-pink'], '#B05A81');
      expect(colors['auto-blue'], isNot('#486DA4'));
      expect(colors['auto-mode'], isNot('#B05A81'));
      expect(colors['invalid'], matches(RegExp(r'^#[0-9a-f]{6}$')));
      await host.install(await fixture.sourcePackage('app.import.shiguang'));
      final importer = host.instances['app.import.shiguang']!.actor;
      final plan = await host.prepare(
        importer,
        const ServiceRef('app.schedule', 'schedule.import.prepare', 1),
        {
          'draft': {
            'draftVersion': 1,
            'scope': 'palette-source',
            'adapterVersion': 'test@1',
            'complete': true,
            'timetable': fixture.table('ignored'),
            'courses': [
              {'sourceId': 'blue', 'name': '导入蓝色', 'color': '#486DA4'},
            ],
            'meetings': [
              {
                'sourceId': 'meeting',
                'courseId': 'blue',
                'weekday': 1,
                'startPeriod': 1,
                'endPeriod': 2,
                'weeks': [1],
              },
            ],
          },
        },
      );
      final imported = object(
        plan.writes.singleWhere(
          (write) => object(write)['collection'] == 'courses',
        ),
      );
      expect(object(imported['value'])['colorMode'], 'custom');
      final result = await providerSave(plan);
      final week = await query('schedule.query.week', {
        'timetableId': result['timetableId'],
        'teachingWeek': 1,
      });
      expect(fixture.objects(week['items']).single['color'], '#486DA4');
    },
  );
  test(
    'presentation provenance does not duplicate courses across import sources',
    () async {
      await host.install(await fixture.sourcePackage('app.import.shiguang'));
      final importer = host.instances['app.import.shiguang']!.actor;
      Map<String, Object?> draft(String scope) => {
        'draftVersion': 1,
        'scope': scope,
        'adapterVersion': 'test@1',
        'complete': true,
        'timetable': fixture.table('ignored'),
        'courses': [
          {'sourceId': 'blue', 'name': '同一课程', 'color': '#486DA4'},
        ],
        'meetings': [
          {
            'sourceId': 'meeting',
            'courseId': 'blue',
            'weekday': 1,
            'startPeriod': 1,
            'endPeriod': 2,
            'weeks': [1],
          },
        ],
      };
      const service = ServiceRef('app.schedule', 'schedule.import.prepare', 1);
      final first = await host.prepare(importer, service, {
        'draft': draft('source-1'),
      });
      final result = await providerSave(first);
      final coursesBefore = await store.query(actor, 'courses', {});
      final meetingsBefore = await store.query(actor, 'meetings', {});
      expect(coursesBefore, hasLength(1));
      expect(object(coursesBefore.single)['colorMode'], 'custom');
      final second = await host.prepare(importer, service, {
        'draft': draft('source-2'),
        'mode': 'merge',
        'targetTimetableId': result['timetableId'],
      });
      expect(
        second.writes.where(
          (write) =>
              ['courses', 'meetings'].contains(object(write)['collection']),
        ),
        isEmpty,
      );
      await providerSave(second);
      expect(await store.query(actor, 'courses', {}), coursesBefore);
      expect(await store.query(actor, 'meetings', {}), meetingsBefore);
      expect(await store.query(actor, 'importSources', {}), hasLength(2));
    },
  );
}
