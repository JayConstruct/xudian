import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_app_module.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_layout_resolver.dart';
import 'package:task_app/data/app_database.dart';

Future<ScriptPackage> sourcePackage(String id) async {
  final directory = Directory('../packages/modules/$id');
  final sources = <String, String>{};
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.js')) {
      sources[entity.path.substring(directory.path.length + 1)] = await entity
          .readAsString();
    }
  }
  return ScriptPackage.verify(
    await ScriptPackage.build(
      object(
        jsonDecode(await File('${directory.path}/module.json').readAsString()),
      ),
      sources,
    ),
    allowUnsignedLocal: true,
  );
}

List<Map<String, Object?>> nodes(Object? value) {
  if (value is Map) {
    return [object(value), for (final child in value.values) ...nodes(child)];
  }
  if (value is List) return [for (final child in value) ...nodes(child)];
  return [];
}

List<Map<String, Object?>> objects(Object? value) =>
    (value as List).map((item) => object(item)).toList();

Map<String, Object?> table(String id, {String zone = 'Asia/Shanghai'}) => {
  'id': id,
  'name': '我的课表 $id',
  'firstMonday': '2026-10-05',
  'totalWeeks': 20,
  'timezone': zone,
  'displayWeekStart': 1,
  'periods': [
    {'number': 1, 'start': '08:00', 'end': '08:45'},
    {'number': 2, 'start': '08:50', 'end': '09:35'},
    {'number': 3, 'start': '09:50', 'end': '10:35'},
    {'number': 4, 'start': '10:40', 'end': '11:25'},
  ],
};

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
    directory = await Directory.systemTemp.createTemp('schedule-today-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 6);
    await host.initialize();
    for (final id in ['app.tasks', 'app.views.today', 'app.schedule']) {
      await host.install(await sourcePackage(id));
    }
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

  Future<Map<String, Object?>> feed() async => object(
    await host.query(
      actor,
      const ServiceRef('app.schedule', 'schedule.query.todayFeed', 1),
      {},
    ),
  );
  Future<void> course(
    String timetableId,
    String id,
    int weekday,
    int start,
  ) async {
    await command('schedule.course.save', {
      'course': {'id': id, 'timetableId': timetableId, 'name': id},
      'meeting': {
        'id': '$id-meeting',
        'weekday': weekday,
        'startPeriod': start,
        'endPeriod': start + 1,
        'weeks': [1],
        'location': '真实教室',
        'teacher': '真实教师',
      },
    });
  }

  test(
    'example is reviewed, date-relative, idempotent and preserves user data',
    () async {
      await command('schedule.timetable.save', {'timetable': table('real')});
      await course('real', '真实课程', 6, 3);
      final original = {
        for (final collection in ['timetables', 'courses', 'meetings'])
          collection: await store.query(actor, collection, {}),
      };
      final proposal = await host.prepare(
        actor,
        const ServiceRef('app.schedule', 'schedule.demo.create', 1),
        {},
      );
      expect(proposal.writes, hasLength(25));
      expect(
        await store.query(actor, 'timetables', {}),
        original['timetables'],
      );
      host.review(proposal.id, actor);
      final result = object(await host.commit(actor, proposal.id));
      final demoId = result['timetableId'] as String;
      final demo = object(await store.get(actor, 'timetables', demoId));
      expect(demo['firstMonday'], '2026-10-05');
      expect(demo['showWeekends'], true);
      expect(demo['periods'], hasLength(12));
      final today = object(
        await host.query(
          actor,
          const ServiceRef('app.schedule', 'schedule.query.today', 1),
          {'timetableId': demoId},
        ),
      );
      expect(today['date'], '2026-10-10');
      expect(objects(today['items']).map((item) => item['title']), [
        '高等数学',
        '程序设计',
        '大学英语',
      ]);
      for (final entry in original.entries) {
        final records = await store.query(actor, entry.key, {});
        for (final before in entry.value) {
          expect(
            records.singleWhere(
              (item) => object(item)['id'] == object(before)['id'],
            ),
            before,
          );
        }
      }
      final demoCourse = object(
        await store.get(actor, 'courses', '$demoId-course-1'),
      );
      await command('schedule.course.save', {
        'course': {...demoCourse, 'name': '我编辑的示例'},
      });
      final beforeRepeat = {
        for (final collection in ['timetables', 'courses', 'meetings'])
          collection: await store.query(actor, collection, {}),
      };
      final repeated = await host.prepare(
        actor,
        const ServiceRef('app.schedule', 'schedule.demo.create', 1),
        {},
      );
      expect(repeated.writes, isEmpty);
      expect(object(repeated.result)['alreadyExists'], true);
      host.review(repeated.id, actor);
      await host.commit(actor, repeated.id);
      for (final entry in beforeRepeat.entries) {
        expect(await store.query(actor, entry.key, {}), entry.value);
      }
    },
  );

  test('all timetables merge by time, honor cancellation/movement and open original details', () async {
    final demoId =
        object(await command('schedule.demo.create', {}))['timetableId']
            as String;
    await command('schedule.timetable.save', {'timetable': table('real')});
    await course('real', '真实课程', 7, 3);
    await command('schedule.change.save', {
      'change': {
        'timetableId': demoId,
        'kind': 'cancel',
        'meetingId': '$demoId-meeting-1-6',
        'originalDate': '2026-10-10',
      },
    });
    await command('schedule.change.save', {
      'change': {
        'timetableId': 'real',
        'kind': 'replace',
        'meetingId': '真实课程-meeting',
        'originalDate': '2026-10-11',
        'date': '2026-10-10',
        'startPeriod': 3,
        'endPeriod': 4,
        'location': '调课教室',
      },
    });
    final items = objects((await feed())['items']);
    expect(items.map((item) => item['title']), ['真实课程', '程序设计', '大学英语']);
    expect(items.map((item) => item['startTime']), ['09:50', '14:00', '18:30']);
    expect(items.first['location'], '调课教室');
    final page = object(
      await host.invokePage('app.schedule', 'renderTodayFeed', {
        'state': {'feedDate': '2026-10-10', 'coursesExpanded': true},
      }),
    );
    final tile = nodes(page['tree'])
        .singleWhere((node) => node['title'] == '真实课程');
    expect(tile['type'], 'agendaItem');
    expect(tile['startTime'], '09:50');
    expect(tile['endTime'], '11:25');
    expect(tile['subtitle'], contains('第 3–4 节'));
    expect(tile['badge'], isNull);
    expect(tile['subtitle'], contains('我的课表 real'));
    final interactions = <Map<String, Object?>>[];
    host.interaction = (_, method, args) async {
      interactions.add({'method': method, ...args});
      return null;
    };
    await host.invokePage('app.schedule', 'renderTodayFeed', {
      'event': tile['event'],
    });
    expect(interactions.single['method'], 'ui.navigate');
    expect(interactions.single['page'], 'app.schedule.occurrence');
    final context = object(interactions.single['context']);
    expect(context['timetableId'], 'real');
    expect(context['originalDate'], '2026-10-11');
    final detail = object(
      await host.invokePage('app.schedule', 'render', {
        'context': {...context, 'pageId': 'app.schedule.occurrence'},
      }),
    );
    expect(
      nodes(detail['tree']).any((node) => node['subtitle'] == '调课教室'),
      true,
    );
  });

  test('today uses each timetable timezone across midnight and empty feed remains clear', () async {
    expect(objects((await feed())['items']), isEmpty);
    final empty = object(
      await host.invokePage('app.schedule', 'renderTodayFeed', {}),
    );
    expect(nodes(empty['tree']).any((node) => node['text'] == '今天没有课程'), true);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 20);
    await command('schedule.timetable.save', {'timetable': table('china')});
    await command('schedule.timetable.save', {
      'timetable': table('new-york', zone: 'America/New_York'),
    });
    await course('china', '中国周日课程', 7, 1);
    await course('new-york', '纽约周六课程', 6, 1);
    final items = objects((await feed())['items']);
    expect(items.map((item) => item['title']), ['纽约周六课程', '中国周日课程']);
    expect(items.map((item) => item['date']), ['2026-10-10', '2026-10-11']);
  });

  test(
    'course section navigation and imminent badges reflect actual clock',
    () async {
      await command('schedule.demo.create', {});
      host.clockNow = () => DateTime.utc(2026, 10, 10, 5, 45);
      var page = object(
        await host.invokePage('app.schedule', 'renderTodayFeed', {}),
      );
      var agenda = nodes(page['tree'])
          .where((node) => node['type'] == 'agendaItem')
          .toList();
      expect(
        agenda.singleWhere((node) => node['title'] == '程序设计')['badge'],
        '即将开始',
      );
      expect(agenda, hasLength(1));
      expect(agenda.single['title'], '程序设计');
      final header = nodes(page['tree'])
          .singleWhere((node) => node['type'] == 'sectionHeader');
      expect(header['count'], 3);
      final calls = <Map<String, Object?>>[];
      host.interaction = (_, method, args) async {
        calls.add({'method': method, ...args});
        return null;
      };
      await host.invokePage('app.schedule', 'renderTodayFeed', {
        'event': object(header['action'])['event'],
      });
      expect(calls.single['page'], 'app.schedule.home');
      host.clockNow = () => DateTime.utc(2026, 10, 10, 6, 15);
      page = object(
        await host.invokePage('app.schedule', 'renderTodayFeed', {}),
      );
      agenda = nodes(page['tree'])
          .where((node) => node['type'] == 'agendaItem')
          .toList();
      expect(agenda.any((node) => node['badge'] == '即将开始'), false);
      expect(agenda.single['title'], '程序设计');
      expect(agenda.single['badge'], '正在上课');
    },
  );

  for (final count in [0, 1, 4, 10]) {
    test(
      '$count courses stay compact with scoped expand and collapse state',
      () async {
        await command('schedule.timetable.save', {'timetable': table('real')});
        for (var index = 0; index < count; index++) {
          await course('real', '课程 $index', 6, 1);
        }
        var page = object(
          await host.invokePage('app.schedule', 'renderTodayFeed', {}),
        );
        List<Map<String, Object?>> agenda() =>
            nodes(page['tree'])
                .where((node) => node['type'] == 'agendaItem')
                .toList();
        expect(agenda(), hasLength(count == 0 ? 0 : 1));
        expect(
          nodes(page['tree'])
              .singleWhere((node) => node['type'] == 'sectionHeader')['count'],
          count,
        );
        if (count == 0) {
          expect(
            nodes(page['tree']).where((node) => node['type'] == 'button'),
            isEmpty,
          );
          return;
        }
        final expand = nodes(page['tree'])
            .singleWhere((node) => node['text'] == '全部课程（$count）');
        page = object(
          await host.invokePage('app.schedule', 'renderTodayFeed', {
            'state': page['state'],
            'event': expand['event'],
          }),
        );
        expect(agenda(), hasLength(count));
        page = object(
          await host.invokePage('app.schedule', 'renderTodayFeed', {
            'state': page['state'],
          }),
        );
        expect(agenda(), hasLength(count));
        final collapse = nodes(page['tree'])
            .singleWhere((node) => node['text'] == '收起课程');
        page = object(
          await host.invokePage('app.schedule', 'renderTodayFeed', {
            'state': page['state'],
            'event': collapse['event'],
          }),
        );
        expect(agenda(), hasLength(1));
        expect(agenda().single['badge'], '已结束');
        page = object(
          await host.invokePage('app.schedule', 'renderTodayFeed', {
            'state': page['state'],
            'event': expand['event'],
          }),
        );
        page = object(
          await host.invokePage('app.schedule', 'renderTodayFeed', {
            'state': page['state'],
            'context': {'selectedDate': '2026-10-11'},
            'event': expand['event'],
          }),
        );
        expect(object(page['state'])['coursesExpanded'], false);
        expect(agenda(), isEmpty);
      },
    );
  }

  test('focus follows start/end boundaries, last-ended summary, history and future', () async {
    await command('schedule.demo.create', {});
    Future<Map<String, Object?>> focused({String? date}) async {
      final page = object(
        await host.invokePage('app.schedule', 'renderTodayFeed', {
          'context': {'selectedDate': ?date},
        }),
      );
      expect(
        nodes(page['tree']).any((node) => node['text'] == '全部课程（3）'),
        true,
      );
      return nodes(page['tree'])
          .singleWhere((node) => node['type'] == 'agendaItem');
    }

    host.clockNow = () => DateTime.utc(2026, 10, 9, 23);
    expect((await focused(date: '2026-10-10'))['title'], '高等数学');
    host.clockNow = () => DateTime.utc(2026, 10, 10, 0);
    expect((await focused())['badge'], '正在上课');
    host.clockNow = () => DateTime.utc(2026, 10, 10, 1, 40);
    final between = await focused();
    expect(between['title'], '程序设计');
    expect(between['badge'], '下一节');
    host.clockNow = () => DateTime.utc(2026, 10, 10, 14);
    final ended = await focused();
    expect(ended['title'], '大学英语');
    expect(ended['badge'], '已结束');
    host.clockNow = () => DateTime.utc(2026, 10, 11, 6);
    final history = await focused(date: '2026-10-10');
    expect(history['title'], '大学英语');
    expect(history['badge'], '当日最后一节');
    expect((await focused(date: '2026-10-12'))['badge'], '当日首节');
  });

  test('selected-date mixed timezones sort by relative instant and keep source identities when expanded', () async {
    await command('schedule.timetable.save', {
      'timetable': {
        ...table('china'),
        'periods': [
          {'number': 1, 'start': '14:00', 'end': '14:45'},
          {'number': 2, 'start': '14:50', 'end': '15:35'},
        ],
      },
    });
    await command('schedule.timetable.save', {
      'timetable': table('new-york', zone: 'America/New_York'),
    });
    await course('china', '中国课程', 6, 1);
    await course('new-york', '纽约课程', 6, 1);
    for (final courseId in ['中国课程', '纽约课程']) {
      await command('schedule.course.save', {
        'course': {
          ...object(await store.get(actor, 'courses', courseId)),
          'name': '同名课程',
        },
      });
    }
    final selected = object(
      await host.query(
        actor,
        const ServiceRef('app.schedule', 'schedule.query.todayFeed', 1),
        {'date': '2026-10-10'},
      ),
    );
    final items = objects(selected['items']);
    expect(items.map((item) => item['timetableId']), ['china', 'new-york']);
    expect(items.map((item) => item['startTime']), ['14:00', '08:00']);
    var page = object(
      await host.invokePage('app.schedule', 'renderTodayFeed', {
        'context': {'selectedDate': '2026-10-10'},
      }),
    );
    final compact = nodes(page['tree'])
        .singleWhere((node) => node['type'] == 'agendaItem');
    expect(object(compact['event'])['timetableId'], 'china');
    final expand = nodes(page['tree'])
        .singleWhere((node) => node['type'] == 'button');
    page = object(
      await host.invokePage('app.schedule', 'renderTodayFeed', {
        'state': page['state'],
        'context': {'selectedDate': '2026-10-10'},
        'event': expand['event'],
      }),
    );
    final agenda = nodes(page['tree'])
        .where((node) => node['type'] == 'agendaItem')
        .toList();
    expect(agenda, hasLength(2));
    expect(agenda.map((node) => node['key']).toSet(), hasLength(2));
    expect(agenda.first['subtitle'], contains('Asia/Shanghai'));
    expect(agenda.last['subtitle'], contains('America/New_York'));
    expect(object(agenda.last['event'])['timetableId'], 'new-york');
  });

  test(
    'selected mixed-zone courses use date-specific UTC offsets across DST',
    () async {
      await command('schedule.timetable.save', {
        'timetable': {
          ...table('utc', zone: 'UTC'),
          'firstMonday': '2026-11-02',
          'periods': [
            {'number': 1, 'start': '12:30', 'end': '13:15'},
            {'number': 2, 'start': '13:20', 'end': '14:05'},
          ],
        },
      });
      await command('schedule.timetable.save', {
        'timetable': {
          ...table('new-york', zone: 'America/New_York'),
          'firstMonday': '2026-11-02',
        },
      });
      await course('utc', 'UTC课程', 7, 1);
      await course('new-york', '纽约课程', 7, 1);
      final result = object(
        await host.query(
          actor,
          const ServiceRef('app.schedule', 'schedule.query.todayFeed', 1),
          {'date': '2026-11-08'},
        ),
      );
      final items = objects(result['items']);
      expect(items.map((item) => item['title']), ['UTC课程', '纽约课程']);
      expect(
        (items.last['startOffset'] as num) -
            (items.first['startOffset'] as num),
        30,
      );
      host.clockNow = () => DateTime.utc(2026, 11, 8, 15);
      final past = object(
        await host.query(
          actor,
          const ServiceRef('app.schedule', 'schedule.query.todayFeed', 1),
          {'date': '2026-11-08'},
        ),
      );
      expect(objects(past['items']).map((item) => item['title']), [
        'UTC课程',
        '纽约课程',
      ]);
    },
  );

  test(
    'historical courses expand fully and collapse back to the last lesson',
    () async {
      await command('schedule.demo.create', {});
      host.clockNow = () => DateTime.utc(2026, 10, 11, 6);
      var page = object(
        await host.invokePage('app.schedule', 'renderTodayFeed', {
          'context': {'selectedDate': '2026-10-10'},
        }),
      );
      final expand = nodes(page['tree'])
          .singleWhere((node) => node['text'] == '全部课程（3）');
      page = object(
        await host.invokePage('app.schedule', 'renderTodayFeed', {
          'context': {'selectedDate': '2026-10-10'},
          'state': page['state'],
          'event': expand['event'],
        }),
      );
      final agenda = nodes(page['tree'])
          .where((node) => node['type'] == 'agendaItem')
          .toList();
      expect(agenda.map((node) => node['title']), ['高等数学', '程序设计', '大学英语']);
      expect(agenda.any((node) => node['badge'] == '即将开始'), false);
      final collapse = nodes(page['tree'])
          .singleWhere((node) => node['text'] == '收起课程');
      page = object(
        await host.invokePage('app.schedule', 'renderTodayFeed', {
          'context': {'selectedDate': '2026-10-10'},
          'state': page['state'],
          'event': collapse['event'],
        }),
      );
      expect(
        nodes(page['tree'])
            .singleWhere((node) => node['type'] == 'agendaItem')['title'],
        '大学英语',
      );
    },
  );

  test(
    'selected courses never guess nonexistent or ambiguous DST boundaries',
    () async {
      for (final fixture in [
        (
          monday: '2026-03-02',
          date: '2026-03-08',
          start: '02:00',
          end: '02:30',
        ),
        (
          monday: '2026-10-26',
          date: '2026-11-01',
          start: '01:00',
          end: '01:30',
        ),
      ]) {
        await command('schedule.timetable.save', {
          'timetable': {
            ...table('dst', zone: 'America/New_York'),
            'firstMonday': fixture.monday,
            'periods': [
              {'number': 1, 'start': fixture.start, 'end': fixture.end},
              {'number': 2, 'start': '03:00', 'end': '03:30'},
            ],
          },
        });
        await course('dst', 'DST课程', 7, 1);
        await expectLater(
          host.query(
            actor,
            const ServiceRef('app.schedule', 'schedule.query.todayFeed', 1),
            {'date': fixture.date},
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('夏令时歧义或不存在'),
            ),
          ),
        );
      }
    },
  );

  test('overview uses real counts, interactive centered dates, optional schedule and bounded task summary', () async {
    await command('schedule.demo.create', {});
    Future<Map<String, Object?>> overview() async => object(
      await host.invokePage('app.views.today', 'render', {
        'context': {'pageId': 'app.views.today.overview'},
      }),
    );
    var page = await overview(), tree = object(page['tree']);
    expect(tree['type'], 'dayOverview');
    expect(tree['dateHeading'], false);
    expect(tree['date'], '2026-10-10');
    expect(tree['summary'], '0 项待办');
    final days = objects(tree['days']);
    expect(days.map((day) => day['date']), [
      '2026-10-08',
      '2026-10-09',
      '2026-10-10',
      '2026-10-11',
      '2026-10-12',
    ]);
    expect(days.map((day) => day['label']), ['周四', '周五', '周六', '周日', '周一']);
    expect(object(tree['event'])['type'], 'selectDate');
    expect(object(page['runtimeContextPatch'])['selectedDate'], '2026-10-10');
    await host.disable('app.schedule');
    expect(host.instances.containsKey('app.views.today'), true);
    tree = object((await overview())['tree']);
    expect(tree['summary'], '0 项待办');
    final taskActor = host.instances['app.tasks']!.actor;
    for (var i = 0; i < 51; i++) {
      final plan = await host.prepare(
        taskActor,
        const ServiceRef('app.tasks', 'task.create', 1),
        {'title': '今日任务 $i', 'plannedDate': '2026-10-10'},
      );
      host.review(plan.id, taskActor);
      await host.commit(taskActor, plan.id);
    }
    tree = object((await overview())['tree']);
    expect(tree['summary'], '50+ 项待办');
    host.clockNow = () => DateTime.utc(2026, 10, 31, 6);
    tree = object((await overview())['tree']);
    expect(objects(tree['days']).map((day) => day['date']), [
      '2026-10-29',
      '2026-10-30',
      '2026-10-31',
      '2026-11-01',
      '2026-11-02',
    ]);
  });

  test('today exposes one shared extensible slot while tasks retain editing and quick add', () async {
    final registry = ModuleRegistry([
      for (final instance in host.instances.values)
        ScriptAppModule(host, instance.package),
    ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
    addTearDown(registry.dispose);
    final today = registry.ui.page('app.views.today.home')!;
    expect(today.container, true);
    expect(today.slots.single.id, 'daily');
    expect(today.slots.single.kind, PageSlotKind.sections);
    expect(today.slots.single.inline, true);
    expect(today.slots.single.isPublic, true);
    for (final id in [
      'app.views.today.overview.feed',
      'app.schedule.today.feed',
      'app.views.today.tasks.feed',
    ]) {
      final entry = registry.ui.entries.singleWhere((entry) => entry.id == id);
      expect(mountDiagnostic(registry.ui, entry, entry.defaultMount), isNull);
    }
    final entries =
        registry.ui.entries
            .where(
              (entry) => entry.defaultMount.pageId == 'app.views.today.home',
            )
            .toList()
          ..sort(
            (a, b) => a.defaultMount.order.compareTo(b.defaultMount.order),
          );
    expect(entries.map((entry) => entry.id), [
      'app.views.today.overview.feed',
      'app.schedule.today.feed',
      'app.views.today.tasks.feed',
    ]);
    host.interaction = (_, method, _) async =>
        method == 'ui.review' ? true : null;
    var page = object(
      await host.invokePage('app.views.today', 'render', {
        'context': {'pageId': 'app.views.today.tasks'},
        'state': {'quickExpanded': true},
        'event': {'type': 'add'},
        'formValues': {'quickTitle': '今天的新任务'},
      }),
    );
    expect(page['clearForms'], ['quickTitle']);
    expect(object(page['tree'])['type'], 'keyedList');
    var checkbox = nodes(page['tree'])
        .singleWhere((node) => node['type'] == 'taskItem');
    expect(checkbox['title'], '今天的新任务');
    expect(object(checkbox['openEvent'])['type'], 'edit');
    expect(checkbox['subtitle'], contains('计划 当天'));
    var collapsed = object(
      await host.invokePage('app.views.today', 'render', {
        'context': {'pageId': 'app.views.today.tasks'},
      }),
    );
    var quickGroup = nodes(collapsed['tree'])
        .singleWhere((node) => node['key'] == 'quick-add');
    expect(quickGroup['collapse'], true);
    expect(quickGroup['visible'], false);
    expect(
      nodes(quickGroup['child']).any((node) => node['key'] == 'quickTitle'),
      true,
      reason: 'Hidden quick input stays mounted so its draft survives',
    );
    final header = nodes(collapsed['tree'])
        .singleWhere((node) => node['type'] == 'sectionHeader');
    expect(header['title'], '待办事项');
    collapsed = object(
      await host.invokePage('app.views.today', 'render', {
        'context': {'pageId': 'app.views.today.tasks'},
        'state': collapsed['state'],
        'event': object(header['action'])['event'],
      }),
    );
    quickGroup = nodes(collapsed['tree'])
        .singleWhere((node) => node['key'] == 'quick-add');
    expect(quickGroup['collapse'], true);
    expect(quickGroup['visible'], true);
    expect(
      nodes(quickGroup['child']).any((node) => node['key'] == 'quickTitle'),
      true,
    );
    host.interaction = (_, method, args) async {
      if (method == 'ui.review') return true;
      if (method == 'ui.dialog') {
        return {
          'title': '点击正文修改后的任务',
          'priority': '2',
          'dueDate': '2026-10-11',
          'plannedDate': '2026-10-10',
        };
      }
      return null;
    };
    page = object(
      await host.invokePage('app.views.today', 'render', {
        'context': {'pageId': 'app.views.today.tasks'},
        'state': page['state'],
        'event': checkbox['openEvent'],
      }),
    );
    checkbox = nodes(page['tree'])
        .singleWhere((node) => node['type'] == 'taskItem');
    expect(checkbox['title'], '点击正文修改后的任务');
    expect(checkbox['subtitle'], contains('优先级 2'));
    expect(checkbox['subtitle'], contains('10/11截止'));
    page = object(
      await host.invokePage('app.views.today', 'render', {
        'context': {'pageId': 'app.views.today.tasks'},
        'state': page['state'],
        'event': {...object(checkbox['event']), 'value': true},
      }),
    );
    expect(
      nodes(page['tree']).where((node) => node['type'] == 'taskItem'),
      isEmpty,
    );
    expect(
      nodes(page['tree']).any((node) => node['key'] == 'quickTitle'),
      true,
    );
  });
}
