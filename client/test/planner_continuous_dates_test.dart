import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/ui_preferences.dart';
import 'package:task_app/data/app_database.dart';

import 'planner_task_schedule_test.dart' show nodes, objects, sourcePackage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(database);
    directory = await Directory.systemTemp.createTemp('planner-continuous-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 13);
    await host.initialize();
    for (final module in ['app.tasks', 'app.planner']) {
      await host.install(await sourcePackage(module));
    }
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<Map<String, Object?>> page({
    Map<String, Object?> state = const {},
    Map<String, Object?>? event,
  }) async => object(
    await host.invokePage('app.planner', 'render', {
      'context': {'pageId': 'app.planner.home'},
      'state': state,
      'event': event,
    }),
  );

  Map<String, Object?> board(Map<String, Object?> rendered) =>
      nodes(rendered['tree'])
          .singleWhere((node) => node['type'] == 'plannerBoard');
  Map<String, Object?> options(Map<String, Object?> rendered) =>
      object(board(rendered)['options']);
  List<String> dates(Map<String, Object?> rendered) =>
      objects(board(rendered)['days'])
          .map((entry) => entry['date'] as String)
          .toList();

  Future<Map<String, Object?>> command(
    String service,
    Map<String, Object?> input, {
    String module = 'app.planner',
  }) async {
    final actor = host.instances[module]!.actor;
    final prepared = await host.prepare(
      actor,
      ServiceRef(module, service, 1),
      input,
    );
    host.review(prepared.id, actor);
    return object(await host.commit(actor, prepared.id));
  }

  test('default viewport centers today within a 21-day preload', () async {
    final rendered = await page();
    final state = object(rendered['state']);
    final configuration = options(rendered);
    expect(state['startDate'], '2026-10-12');
    expect(state['days'], 3);
    expect(configuration['continuousDates'], true);
    expect(configuration['visibleDays'], 3);
    expect(configuration['initialDate'], state['startDate']);
    expect(configuration['scrollRequest'], 0);
    expect(configuration['viewportEvent'], {'type': 'timelineViewport'});
    expect(configuration['now'], '2026-10-13T08:00:00');
    expect(configuration['today'], '2026-10-13');
    expect(configuration['selectedDate'], '2026-10-13');
    expect(dates(rendered), hasLength(21));
    expect(dates(rendered).first, '2026-10-05');
    expect(dates(rendered).last, '2026-10-25');
    expect(dates(rendered).sublist(7, 10), [
      '2026-10-12',
      '2026-10-13',
      '2026-10-14',
    ]);
    for (final removed in [
      'periodLabel',
      'periodEvent',
      'previousEvent',
      'nextEvent',
    ]) {
      expect(configuration.containsKey(removed), false);
    }
    final header = object(rendered['header']);
    expect(header['compact'], true);
    expect(header['layout'], 'plannerTimeline');
    final create = objects(header['actions'])
        .singleWhere((action) => action['label'] == '新建');
    expect(create['icon'], 'add');
    expect(create['iconOnly'], true);
    expect(create['variant'], isNot('filled'));
    expect(create['event'], {'type': 'add'});
  });

  for (final scenario in <String, List<String>>{
    '2026-05-31': ['2026-05-30', '2026-05-31', '2026-06-01'],
    '2027-01-01': ['2026-12-31', '2027-01-01', '2027-01-02'],
    '2027-01-31': ['2027-01-30', '2027-01-31', '2027-02-01'],
    '2028-03-01': ['2028-02-29', '2028-03-01', '2028-03-02'],
  }.entries) {
    test(
      'continuous dates cross weekends and boundaries ${scenario.key}',
      () async {
        host.clockNow = () => DateTime.parse('${scenario.key}T00:00:00Z');
        final rendered = await page();
        expect(dates(rendered).sublist(7, 10), scenario.value);
        final parsed = dates(rendered).map(DateTime.parse).toList();
        for (var index = 1; index < parsed.length; index++) {
          expect(parsed[index].difference(parsed[index - 1]).inDays, 1);
        }
      },
    );
  }

  test('viewport feedback preloads and remembers position without requesting a jump', () async {
    final first = await page();
    final scrolled = await page(
      state: object(first['state']),
      event: {
        ...object(options(first)['viewportEvent']),
        'startDate': '2026-12-31',
        'visibleDays': 3,
      },
    );
    final state = object(scrolled['state']);
    expect(state['startDate'], '2026-12-31');
    expect(state['days'], 3);
    expect(options(scrolled)['scrollRequest'], options(first)['scrollRequest']);
    expect(dates(scrolled).first, '2026-12-24');
    expect(dates(scrolled).last, '2027-01-13');
    expect(dates(scrolled).sublist(7, 10), [
      '2026-12-31',
      '2027-01-01',
      '2027-01-02',
    ]);
    await host.close();
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 14);
    await host.initialize();
    final reopened = await page();
    expect(options(reopened)['initialDate'], '2026-12-31');
    expect(options(reopened)['visibleDays'], 3);
    expect(options(reopened)['today'], '2026-10-14');
    final explicit = await page(state: {'startDate': '2027-02-01'});
    expect(options(explicit)['initialDate'], '2027-02-01');
  });

  test(
    'date popup only chooses a centered jump and today remains independent',
    () async {
      host.interaction = (_, method, arguments) async {
        expect(method, 'ui.dialog');
        expect(arguments['title'], '跳转日期');
        final fields = objects(arguments['fields']);
        expect(fields, hasLength(1));
        expect(fields.single['type'], 'date');
        expect(fields.single['key'], 'startDate');
        return {'startDate': '2027-01-01'};
      };
      var rendered = await page(event: {'type': 'period'});
      expect(options(rendered)['initialDate'], '2026-12-31');
      expect(options(rendered)['selectedDate'], '2027-01-01');
      expect(options(rendered)['today'], '2026-10-13');
      expect(options(rendered)['scrollRequest'], 1);
      expect(options(await page())['initialDate'], '2026-12-31');
      rendered = await page(
        state: object(rendered['state']),
        event: {'type': 'period'},
      );
      expect(options(rendered)['scrollRequest'], 2);
      rendered = await page(
        state: object(rendered['state']),
        event: {
          'type': 'timelineViewport',
          'startDate': '2027-01-10',
          'visibleDays': 3,
        },
      );
      expect(options(rendered)['selectedDate'], '2027-01-01');
      expect(options(rendered)['today'], '2026-10-13');
      expect(options(rendered)['scrollRequest'], 2);
      rendered = await page(
        state: object(rendered['state']),
        event: {'type': 'today'},
      );
      expect(options(rendered)['initialDate'], '2026-10-12');
      expect(options(rendered)['selectedDate'], '2026-10-13');
      expect(options(rendered)['scrollRequest'], 3);
      expect(options(await page())['initialDate'], '2026-10-12');
    },
  );

  test(
    'cancelled and invalid jumps or viewport events preserve position',
    () async {
      var rendered = await page(state: {'startDate': '2026-11-01'});
      host.interaction = (_, method, arguments) async => null;
      rendered = await page(
        state: object(rendered['state']),
        event: {'type': 'period'},
      );
      expect(options(rendered)['initialDate'], '2026-11-01');
      expect(options(rendered)['scrollRequest'], 0);
      host.interaction = (_, method, arguments) async => {
        'startDate': '2026-02-30',
      };
      for (final event in [
        {'type': 'period'},
        {
          'type': 'timelineViewport',
          'startDate': '2026-02-30',
          'visibleDays': 3,
        },
        {
          'type': 'timelineViewport',
          'startDate': '2026-11-02',
          'visibleDays': 21,
        },
      ]) {
        rendered = await page(state: object(rendered['state']), event: event);
        expect(object(rendered['state'])['error'], isNotNull);
        expect(options(rendered)['initialDate'], '2026-11-01');
        expect(options(rendered)['visibleDays'], 3);
        expect(options(rendered)['scrollRequest'], 0);
      }
      expect(
        await ModuleUiPreferences(store)
            .get(host.instances['app.planner']!.actor, 'board.viewport'),
        isNull,
      );
    },
  );

  test(
    'non-navigation actions preserve the viewport and jump counter',
    () async {
      var rendered = await page(
        state: {'startDate': '2026-11-01', 'scrollRequest': 7},
      );
      for (final event in [
        {'type': 'onlyDeadline', 'value': true},
        {'type': 'zoom', 'delta': 1},
        {'type': 'candidatePage', 'offset': 0},
        {'type': 'select', 'id': 'kept-selection', 'value': true},
        {'type': 'clearSelection'},
        {'type': 'chooseAuto'},
        {'type': 'board'},
        {'type': 'history'},
        {'type': 'board'},
      ]) {
        rendered = await page(state: object(rendered['state']), event: event);
        final state = object(rendered['state']);
        expect(state['startDate'], '2026-11-01');
        expect(state['days'], 3);
        expect(state['scrollRequest'], 7);
        expect(state['error'], isNull);
        expect(
          object(rendered['header'])['layout'],
          ['chooseAuto', 'history'].contains(event['type'])
              ? isNull
              : 'plannerTimeline',
        );
      }
      expect(options(rendered)['initialDate'], '2026-11-01');
    },
  );

  test(
    'column settings do not bound preload or jump until a date is chosen',
    () async {
      var rendered = await page(state: {'startDate': '2026-11-01'});
      for (final count in [1, 3, 5, 7]) {
        rendered = await page(
          state: object(rendered['state']),
          event: {'type': 'periodShortcut', 'days': count},
        );
        expect(options(rendered)['visibleDays'], count);
        expect(dates(rendered), hasLength(21));
        expect(options(rendered)['initialDate'], '2026-11-01');
        expect(options(rendered)['scrollRequest'], 0);
        expect(options(await page())['visibleDays'], count);
      }
      rendered = await page(
        state: object(rendered['state']),
        event: {'type': 'today'},
      );
      expect(options(rendered)['initialDate'], '2026-10-10');
      expect(options(rendered)['scrollRequest'], 1);
    },
  );

  test(
    'preloaded occupancy is bounded but automatic display uses visible days',
    () async {
      for (final date in [
        '2026-10-04',
        '2026-10-05',
        '2026-10-25',
        '2026-10-26',
      ]) {
        await command('task.create', {
          'title': date,
          'plannedStartAt': '${date}T15:00:00Z',
          'plannedEndAt': '${date}T15:30:00Z',
          'plannedTimezone': 'Asia/Shanghai',
        }, module: 'app.tasks');
      }
      final rendered = await page();
      expect(
        objects(board(rendered)['blocks']).map((block) => block['title']),
        unorderedEquals(['2026-10-05', '2026-10-25']),
      );
      expect(options(rendered)['startMinute'], 480);
      expect(options(rendered)['endMinute'], 1320);
    },
  );

  test(
    'automatic planning remains scoped to visible dates, not preload',
    () async {
      await command('planner.availability.save', {
        'availability': {
          'timezone': 'Asia/Shanghai',
          'weekly': {
            for (var weekday = 1; weekday <= 7; weekday++)
              '$weekday': [
                {'start': '09:00', 'end': '12:00'},
              ],
          },
        },
      });
      await command('planner.rules.save', {
        'rules': [
          {
            'id': 'daily-scope',
            'title': '每日可见范围',
            'kind': 'daily',
            'startDate': '2026-10-13',
            'timezone': 'Asia/Shanghai',
          },
        ],
      });
      var rendered = await page();
      expect(objects(board(rendered)['candidates']).length, greaterThan(3));
      for (final viewport in [
        {
          'startDate': '2026-10-12',
          'visibleDays': 3,
          'planStartDate': '2026-10-13',
          'planDays': 2,
        },
        {
          'startDate': '2026-10-16',
          'visibleDays': 5,
          'planStartDate': '2026-10-16',
          'planDays': 5,
        },
      ]) {
        rendered = await page(
          state: object(rendered['state']),
          event: {'type': 'timelineViewport', ...viewport},
        );
        rendered = await page(
          state: object(rendered['state']),
          event: {'type': 'auto'},
        );
        final preview = object(object(rendered['state'])['autoPreview']);
        expect(
          object(preview['input'])['startDate'],
          viewport['planStartDate'],
        );
        expect(object(preview['input'])['days'], viewport['planDays']);
        expect(object(rendered['state'])['startDate'], viewport['startDate']);
        expect(object(rendered['state'])['days'], viewport['visibleDays']);
        final assignedDates = objects(preview['assigned'])
            .map((entry) => entry['date'] as String)
            .toList();
        expect(assignedDates, hasLength(viewport['visibleDays'] == 3 ? 2 : 5));
        expect(
          assignedDates.first,
          viewport['visibleDays'] == 3 ? '2026-10-13' : '2026-10-16',
        );
        expect(
          assignedDates.last,
          viewport['visibleDays'] == 3 ? '2026-10-14' : '2026-10-20',
        );
        rendered = await page(
          state: object(rendered['state']),
          event: {'type': 'dismissAuto'},
        );
        expect(dates(rendered), hasLength(21));
      }
    },
  );

  test(
    'visible automatic preview still applies and opens operation history',
    () async {
      await command('planner.availability.save', {
        'availability': {
          'weekly': {
            for (var weekday = 1; weekday <= 7; weekday++)
              '$weekday': [
                {'start': '09:00', 'end': '17:00'},
              ],
          },
        },
      });
      final task = await command('task.create', {
        'title': '三列内安排',
        'dueDate': '2026-10-17',
      }, module: 'app.tasks');
      host.interaction = (_, method, arguments) async => method == 'ui.review';
      var rendered = await page(event: {'type': 'chooseAuto'});
      rendered = await page(
        state: object(rendered['state']),
        event: {'type': 'select', 'id': 'task:${task['id']}', 'value': true},
      );
      rendered = await page(
        state: object(rendered['state']),
        event: {'type': 'auto'},
      );
      expect(
        objects(object(object(rendered['state'])['autoPreview'])['assigned']),
        hasLength(1),
      );
      rendered = await page(
        state: object(rendered['state']),
        event: {'type': 'confirmAuto'},
      );
      expect(object(rendered['state'])['error'], isNull);
      expect(objects(board(rendered)['blocks']).single['title'], '三列内安排');
      expect(options(rendered)['initialDate'], '2026-10-12');
      rendered = await page(
        state: object(rendered['state']),
        event: {'type': 'history'},
      );
      expect(object(rendered['header'])['title'], '操作历史');
      expect(
        nodes(rendered['tree']).where(
          (node) =>
              node['event'] is Map && object(node['event'])['type'] == 'undo',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'past viewport cannot silently plan outside its visible dates',
    () async {
      final rendered = await page(
        state: {'startDate': '2026-10-01', 'days': 3},
        event: {'type': 'auto'},
      );
      final state = object(rendered['state']);
      expect(state['error'], contains('当前可见日期均已过去'));
      expect(state['autoPreview'], isNull);
      expect(options(rendered)['initialDate'], '2026-10-01');
      expect(options(rendered)['scrollRequest'], 0);
    },
  );

  test(
    'current time uses planning timezone across a UTC date boundary',
    () async {
      host.clockNow = () => DateTime.utc(2026, 12, 31, 23, 30);
      await command('planner.availability.save', {
        'availability': {'timezone': 'America/Los_Angeles'},
      });
      final rendered = await page();
      expect(options(rendered)['now'], '2026-12-31T15:30:00');
      expect(options(rendered)['today'], '2026-12-31');
      expect(options(rendered)['initialDate'], '2026-12-30');
      await command('planner.availability.save', {
        'availability': {'timezone': 'Asia/Shanghai'},
      });
      final shanghai = await page();
      expect(options(shanghai)['now'], '2027-01-01T07:30:00');
      expect(options(shanghai)['today'], '2027-01-01');
      expect(options(shanghai)['initialDate'], '2026-12-31');
    },
  );
}
