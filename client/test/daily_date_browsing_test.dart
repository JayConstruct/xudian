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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('daily-dates-');
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
  Future<Map<String, Object?>> command(
    String module,
    String service,
    Map<String, Object?> input,
  ) async {
    final actor = host.instances[module]!.actor,
        plan = await host.prepare(actor, ServiceRef(module, service, 1), input);
    host.review(plan.id, actor);
    return object(await host.commit(actor, plan.id));
  }

  Future<String> task(
    String title, {
    String? planned,
    String? due,
    bool completed = false,
  }) async {
    final result = await command('app.tasks', 'task.create', {
      'title': title,
      'plannedDate': planned,
      'dueDate': due,
    });
    final id = result['id'] as String;
    if (completed) {
      await command('app.tasks', 'task.setCompleted', {
        'id': id,
        'completed': true,
      });
    }
    return id;
  }

  Future<List<Map<String, Object?>>> list(Map<String, Object?> input) async =>
      objects(
        await host.query(
          host.instances['app.tasks']!.actor,
          const ServiceRef('app.tasks', 'task.list', 1),
          input,
        ),
      );
  Future<Map<String, Object?>> page(
    String target, {
    String? selected,
    Object? state,
    Object? event,
    Map<String, Object?> forms = const {},
  }) async => object(
    await host.invokePage('app.views.today', 'render', {
      'context': {
        'pageId': 'app.views.today.$target',
        'selectedDate': ?selected,
      },
      'state': state ?? {},
      'event': event,
      'formValues': forms,
    }),
  );
  Future<List<Map<String, Object?>>> recordSnapshot() => store.sql(
    'SELECT * FROM host_records ORDER BY module_id,space,collection,id',
  );

  test(
    'five-day counts reflect daily task rules without modifying records',
    () async {
      await task('历史已完成', planned: '2026-10-09', completed: true);
      await task('历史待办', planned: '2026-10-09');
      await task('逾期', due: '2026-10-07');
      await task('今天计划和到期', planned: '2026-10-10', due: '2026-10-10');
      await task('明天待办', planned: '2026-10-11');
      await task('未来已完成不计入', planned: '2026-10-11', completed: true);
      final before = await recordSnapshot();
      final result = await page('overview');
      final tree = object(result['tree']);
      final days = objects(tree['days']);
      Map<String, Object?> day(String date) =>
          days.singleWhere((day) => day['date'] == date);
      expect(day('2026-10-09')['pending'], 1);
      expect(day('2026-10-09')['completed'], 1);
      expect(day('2026-10-10')['pending'], 2);
      expect(day('2026-10-10')['overdue'], 1);
      expect(day('2026-10-10')['isToday'], true);
      expect(day('2026-10-11')['pending'], 1);
      expect(day('2026-10-11')['completed'], 0);
      expect(tree['dateControls'], false);
      expect(await recordSnapshot(), before);
      final selected = object(
        (await page('overview', selected: '2026-10-09'))['tree'],
      );
      expect(selected['selectedDate'], '2026-10-09');
      expect(selected['summary'], '1 项待办 · 1 项已完成');
    },
  );

  test('date-container initialization only chooses context without querying task data', () async {
    final reads = <String>{};
    final result = object(
      await host.invokePage('app.views.today', 'render', {
        'context': {'pageId': 'app.views.today.home'},
      }, onReads: reads.addAll),
    );
    expect(object(result['runtimeContextPatch'])['selectedDate'], '2026-10-10');
    expect(objects(object(result['tree'])['children']), isEmpty);
    expect(reads, isNot(contains('app.tasks')));
  });

  test('daily date queries retain today overdue rules and show exact historical completion without future completed tasks', () async {
    await task('旧逾期', due: '2026-10-07');
    await task('当天到期', due: '2026-10-10');
    await task('当天计划', planned: '2026-10-10');
    await task('历史待办', planned: '2026-10-09');
    await task('历史已完成', planned: '2026-10-09', completed: true);
    await task('未来待办', planned: '2026-10-11');
    await task('未来已完成', planned: '2026-10-11', completed: true);
    final before = await recordSnapshot();
    final today = (await list({'view': 'today', 'today': '2026-10-10'}))
        .map((t) => t['title'])
        .toSet();
    expect(today, {'旧逾期', '当天到期', '当天计划'});
    expect(
      (await list({'view': 'daily', 'date': '2026-10-10'}))
          .map((t) => t['title'])
          .toSet(),
      today,
    );
    final history = await list({'view': 'daily', 'date': '2026-10-09'});
    expect(history.map((t) => t['title']).toSet(), {'历史待办', '历史已完成'});
    expect(
      history.singleWhere((t) => t['title'] == '历史已完成')['completed'],
      true,
    );
    expect(
      (await list({'view': 'daily', 'date': '2026-10-11'}))
          .map((t) => t['title']),
      ['未来待办'],
    );
    expect(await recordSnapshot(), before);
    final overview = object(
      (await page('overview', selected: '2026-10-09'))['tree'],
    );
    expect(overview['summary'], '1 项待办 · 1 项已完成');
    expect(
      nodes((await page('tasks', selected: '2026-10-09'))['tree'])
          .where((n) => n['type'] == 'taskItem'),
      hasLength(2),
    );
  });

  test('a historical completed task is reopened only after the existing review succeeds', () async {
    final id = await task('历史完成任务', planned: '2026-10-09', completed: true);
    var result = await page('tasks', selected: '2026-10-09');
    final row = nodes(result['tree'])
        .singleWhere((n) => n['type'] == 'taskItem');
    final event = {...object(row['event']), 'value': false},
        before = await recordSnapshot();
    final calls = <String>[];
    host.interaction = (_, method, args) async {
      calls.add(method);
      return false;
    };
    await page(
      'tasks',
      selected: '2026-10-09',
      state: result['state'],
      event: event,
    );
    expect(calls, ['ui.review']);
    expect(await recordSnapshot(), before);
    host.interaction = (_, method, args) async => method == 'ui.review';
    result = await page(
      'tasks',
      selected: '2026-10-09',
      state: result['state'],
      event: event,
    );
    expect(
      nodes(result['tree'])
          .singleWhere((n) => n['type'] == 'taskItem')['completed'],
      false,
    );
    expect(
      object(
        await store.get(host.instances['app.tasks']!.actor, 'tasks', id),
      )['completedAt'],
      isNull,
    );
    expect(
      object(
        (await page('overview', selected: '2026-10-09'))['tree'],
      )['summary'],
      '1 项待办',
    );
  });

  test('date patches cross month and year and quick creation uses selected civil date with cancellation preserving records', () async {
    var result = await page(
      'overview',
      selected: '2026-12-31',
      event: {'type': 'selectDate', 'value': '2027-01-01'},
    );
    expect(object(result['runtimeContextPatch'])['selectedDate'], '2027-01-01');
    final tree = object(result['tree']);
    expect(tree['date'], '2027-01-01');
    expect(tree['todayDate'], '2026-10-10');
    expect(tree['dateHeading'], false);
    final definition = object(
      jsonDecode(
        await File('../packages/modules/app.views.today/module.json')
            .readAsString(),
      ),
    );
    final manifest = object(definition['manifest']);
    expect(manifest['id'], 'app.views.today');
    expect(manifest['name'], '日程');
    expect(manifest['dataVersion'], 1);
    final home = objects(definition['pages'])
        .singleWhere((page) => page['id'] == 'app.views.today.home');
    expect(home['title'], '日程');
    expect(home['headerMode'], 'date');
    expect(object(home['entry'])['id'], 'app.views.today.home');
    expect(objects(tree['days']).map((d) => d['date']), [
      '2026-12-30',
      '2026-12-31',
      '2027-01-01',
      '2027-01-02',
      '2027-01-03',
    ]);
    result = await page(
      'overview',
      event: {'type': 'selectDate', 'value': '2024-02-29'},
    );
    expect(objects(object(result['tree'])['days']).map((d) => d['date']), [
      '2024-02-27',
      '2024-02-28',
      '2024-02-29',
      '2024-03-01',
      '2024-03-02',
    ]);
    final before = await recordSnapshot();
    host.interaction = (_, method, args) async => false;
    await page(
      'tasks',
      selected: '2027-01-01',
      event: {'type': 'add'},
      forms: {'quickTitle': '元旦计划'},
    );
    expect(await recordSnapshot(), before);
    host.interaction = (_, method, args) async => method == 'ui.review';
    await page(
      'tasks',
      selected: '2027-01-01',
      event: {'type': 'add'},
      forms: {'quickTitle': '元旦计划'},
    );
    final created = (await list({'view': 'daily', 'date': '2027-01-01'}))
        .single;
    expect(created['plannedDate'], '2027-01-01');
    expect(created['title'], '元旦计划');
    expect(
      (await list({'view': 'daily', 'date': '2026-10-10'}))
          .any((t) => t['title'] == '元旦计划'),
      false,
    );
  });

  test('historical overview is bounded and pagination resets when selected date changes while drafts remain', () async {
    final actor = host.instances['app.tasks']!.actor;
    await db.transaction(() async {
      for (var i = 0; i < 56; i++) {
        final id = 'historical-$i';
        await db.customStatement(
          'INSERT INTO host_records(module_id,space,collection,id,value,revision,deleted) VALUES(?,?,?,?,?,1,0)',
          [
            actor.moduleId,
            actor.space,
            'tasks',
            id,
            jsonEncode({
              'id': id,
              'title': '任务 $i',
              'priority': 0,
              'plannedDate': '2026-10-09',
              'createdAt': id,
              'updatedAt': id,
              'completedAt': i.isEven ? '2026-10-10T06:00:00Z' : null,
            }),
          ],
        );
      }
    });
    final overview = object(
      (await page('overview', selected: '2026-10-09'))['tree'],
    );
    expect(overview['summary'], contains('已加载'));
    expect(overview['summary'], contains('还有更多任务'));
    var result = await page(
      'tasks',
      selected: '2026-10-09',
      event: {'type': 'toggleQuick'},
    );
    expect(
      nodes(result['tree']).where((n) => n['type'] == 'taskItem'),
      hasLength(50),
    );
    result = await page(
      'tasks',
      selected: '2026-10-09',
      state: result['state'],
      event: {'type': 'moreTasks'},
    );
    expect(
      nodes(result['tree']).where((n) => n['type'] == 'taskItem'),
      hasLength(56),
    );
    result = await page(
      'tasks',
      selected: '2026-10-11',
      state: result['state'],
      forms: {'quickTitle': '保留草稿'},
    );
    expect(object(result['state'])['taskLimit'], 50);
    expect(object(result['state'])['quickExpanded'], true);
    expect(result['clearForms'], isEmpty);
  });

  test('invalid civil dates are rejected consistently and default date remains real today', () async {
    expect(
      object((await page('overview'))['runtimeContextPatch'])['selectedDate'],
      '2026-10-10',
    );
    for (final date in [
      '2026-02-30',
      '2026-02-29',
      '0000-01-01',
      '10000-01-01',
      '2026-13-01',
    ]) {
      final invalid = throwsA(anyOf(isA<StateError>(), isA<FormatException>()));
      await expectLater(list({'view': 'daily', 'date': date}), invalid);
      await expectLater(
        page('overview', event: {'type': 'selectDate', 'value': date}),
        invalid,
      );
      await expectLater(
        host.query(
          host.instances['app.schedule']!.actor,
          const ServiceRef('app.schedule', 'schedule.query.todayFeed', 1),
          {'date': date},
        ),
        invalid,
      );
    }
  });

  test('selected courses use one civil date across timezones, apply moved/cancelled lessons and avoid future imminent badges', () async {
    await command('app.schedule', 'schedule.demo.create', {});
    final demo = (await store.query(
      host.instances['app.schedule']!.actor,
      'timetables',
      {},
    )).map(object).single;
    final courseId = '${demo['id']}-course-1';
    final meetings =
        (await store.query(
              host.instances['app.schedule']!.actor,
              'meetings',
              {},
            ))
            .map(object)
            .where((m) => m['courseId'] == courseId && m['weekday'] == 6)
            .toList();
    expect(meetings, hasLength(1));
    await command('app.schedule', 'schedule.change.save', {
      'change': {
        'id': 'move',
        'timetableId': demo['id'],
        'kind': 'replace',
        'meetingId': meetings.single['id'],
        'originalDate': '2026-10-10',
        'date': '2026-10-11',
        'startPeriod': 1,
        'endPeriod': 2,
        'location': '调课教室',
      },
    });
    await command('app.schedule', 'schedule.change.save', {
      'change': {
        'id': 'cancel',
        'timetableId': demo['id'],
        'kind': 'cancel',
        'meetingId':
            (await store.query(
                  host.instances['app.schedule']!.actor,
                  'meetings',
                  {},
                ))
                .map(object)
                .singleWhere(
                  (m) => m['courseId'] == courseId && m['weekday'] == 7,
                )['id'],
        'originalDate': '2026-10-11',
      },
    });
    host.clockNow = () => DateTime.utc(2026, 10, 10, 23, 45);
    await command('app.schedule', 'schedule.timetable.save', {
      'timetable': {
        ...demo,
        'id': 'ny',
        'name': '纽约课表',
        'timezone': 'America/New_York',
      },
    });
    await command('app.schedule', 'schedule.course.save', {
      'course': {'id': 'ny-course', 'timetableId': 'ny', 'name': '纽约周日课程'},
      'meeting': {
        'id': 'ny-meeting',
        'weekday': 7,
        'startPeriod': 1,
        'endPeriod': 2,
        'weeks': [1],
      },
    });
    var current = object(
      await host.invokePage('app.schedule', 'renderTodayFeed', {
        'context': {'selectedDate': '2026-10-11'},
      }),
    );
    final compact = nodes(current['tree'])
        .where((node) => node['type'] == 'agendaItem').toList();
    expect(compact, hasLength(1));
    expect(compact.single['title'], '高等数学');
    final expand = nodes(current['tree']).singleWhere((node) => node['text'] == '全部课程（4）');
    current = object(await host.invokePage('app.schedule', 'renderTodayFeed', {
      'context': {'selectedDate': '2026-10-11'},
      'state': current['state'], 'event': expand['event'],
    }));
    final rows = nodes(current['tree'])
        .where((node) => node['type'] == 'agendaItem')
        .toList();
    expect(rows, hasLength(4));
    expect(rows.map((node) => node['title']), ['高等数学', '程序设计', '大学英语', '纽约周日课程']);
    expect(
      rows.singleWhere((n) => n['title'] == '高等数学')['subtitle'],
      contains('调课教室'),
    );
    expect(rows.singleWhere((n) => n['title'] == '高等数学')['badge'], '即将开始');
    expect(rows.singleWhere((n) => n['title'] == '纽约周日课程')['badge'], isNull);
    final sameDay = object(
      await host.query(
        host.instances['app.schedule']!.actor,
        const ServiceRef('app.schedule', 'schedule.query.todayFeed', 1),
        {'date': '2026-10-11'},
      ),
    );
    expect(objects(sameDay['items']).map((i) => i['date']).toSet(), {
      '2026-10-11',
    });
    expect(objects(sameDay['items']).map((i) => i['timezone']).toSet(), {
      'Asia/Shanghai',
      'America/New_York',
    });
    var future = object(
      await host.invokePage('app.schedule', 'renderTodayFeed', {
        'context': {'selectedDate': '2026-10-12'},
        'state': current['state'],
      }),
    );
    expect(
      nodes(future['tree']).where((node) => node['type'] == 'agendaItem'),
      hasLength(1),
    );
    expect(object(future['state'])['coursesExpanded'], false);
    final futureExpand = nodes(future['tree']).singleWhere((node) => node['text'] == '全部课程（3）');
    future = object(await host.invokePage('app.schedule', 'renderTodayFeed', {
      'context': {'selectedDate': '2026-10-12'},
      'state': future['state'], 'event': futureExpand['event'],
    }));
    expect(nodes(future['tree']).where((node) => node['type'] == 'agendaItem'), hasLength(3));
    expect(nodes(future['tree']).any((n) => n['badge'] == '即将开始'), false);
    final outOfTerm = object(
      await host.invokePage('app.schedule', 'renderTodayFeed', {
        'context': {'selectedDate': '2027-12-31'},
      }),
    );
    expect(
      nodes(outOfTerm['tree']).any((n) => n['text'] == '2027-12-31 没有课程'),
      true,
    );
    final before = await recordSnapshot();
    final selected = object(
      await host.query(
        host.instances['app.schedule']!.actor,
        const ServiceRef('app.schedule', 'schedule.query.todayFeed', 1),
        {'date': '2026-10-10'},
      ),
    );
    expect(
      objects(selected['items']).every((i) => i['date'] == '2026-10-10'),
      true,
    );
    expect(await recordSnapshot(), before);
  });
  test('civil year endpoints keep valid date strips and include the final supported year course', () async {
    final min = object(
      (await page('overview', selected: '0001-01-01'))['tree'],
    );
    expect(objects(min['days']).map((d) => d['date']), [
      '0001-01-01',
      '0001-01-02',
      '0001-01-03',
    ]);
    final max = object(
      (await page('overview', selected: '9999-12-31'))['tree'],
    );
    expect(objects(max['days']).map((d) => d['date']), [
      '9999-12-29',
      '9999-12-30',
      '9999-12-31',
    ]);
    await command('app.schedule', 'schedule.timetable.save', {
      'timetable': {
        'id': 'last-year',
        'name': '末年课表',
        'firstMonday': '9999-12-27',
        'totalWeeks': 1,
        'timezone': 'Asia/Shanghai',
        'displayWeekStart': 1,
        'periods': [
          {'number': 1, 'start': '08:00', 'end': '08:45'},
        ],
      },
    });
    await command('app.schedule', 'schedule.course.save', {
      'course': {
        'id': 'last-course',
        'timetableId': 'last-year',
        'name': '末日课程',
      },
      'meeting': {
        'id': 'last-meeting',
        'weekday': 5,
        'startPeriod': 1,
        'endPeriod': 1,
        'weeks': [1],
      },
    });
    final result = object(
      await host.query(
        host.instances['app.schedule']!.actor,
        const ServiceRef('app.schedule', 'schedule.query.todayFeed', 1),
        {'date': '9999-12-31'},
      ),
    );
    expect(objects(result['items']).single['title'], '末日课程');
    expect(objects(result['items']).single['date'], '9999-12-31');
  });
}
