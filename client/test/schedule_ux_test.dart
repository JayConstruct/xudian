import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/module_host/time_grid.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

Future<ScriptPackage> _sourcePackage() async {
  final directory = Directory('../packages/modules/app.schedule');
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

List<Map<String, Object?>> _nodes(Object? value) {
  if (value is Map) {
    return [object(value), for (final item in value.values) ..._nodes(item)];
  }
  if (value is List) return [for (final item in value) ..._nodes(item)];
  return [];
}

Map<String, Object?> _table({List<Map<String, Object?>>? periods}) => {
  'id': 'table',
  'name': '自定义旧课表',
  'firstMonday': '2026-09-07',
  'totalWeeks': 20,
  'timezone': 'Asia/Shanghai',
  'displayWeekStart': 1,
  'periods':
      periods ??
      [
        {'number': 1, 'start': '07:50', 'end': '08:35'},
        {'number': 2, 'start': '08:45', 'end': '09:30'},
      ],
};

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  late ModuleActor actor;
  final interactions = <Map<String, Object?>>[];
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('schedule-ux-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 9, 7, 0, 30);
    interactions.clear();
    await host.initialize();
    await host.install(await _sourcePackage());
    actor = host.instances['app.schedule']!.actor;
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<Object?> command(String id, Object? input) async {
    final plan = await host.prepare(
      actor,
      ServiceRef('app.schedule', id, 1),
      input,
    );
    host.review(plan.id, actor);
    return host.commit(actor, plan.id);
  }

  Future<Map<String, Object?>> render(
    String page, {
    Object? state,
    Object? event,
    Map<String, Object?> context = const {},
    Map<String, Object?> forms = const {},
  }) async => object(
    await host.invokePage('app.schedule', 'render', {
      'context': {'pageId': 'app.schedule.$page', ...context},
      'state': state ?? {},
      'event': event,
      'formValues': forms,
    }),
  );
  void mockDialogs() {
    host.interaction = (caller, method, args) async {
      interactions.add({'method': method, ...args});
      if (method == 'ui.review') return true;
      if (method == 'ui.dialog') {
        return {
          for (final field in objects(args['fields']))
            field['key'] as String: field['value'],
        };
      }
      return true;
    };
  }

  test('display height saves per timetable, survives restart and restores defaults', () async {
    await command('schedule.timetable.save', {'timetable': _table()});
    await command('schedule.timetable.save', {
      'timetable': {..._table(), 'id': 'other'},
    });
    mockDialogs();
    var page = await render('display', context: {'timetableId': 'table'});
    final slider = _nodes(page['tree'])
        .singleWhere((n) => n['type'] == 'slider');
    expect(slider['value'], 192); // Fixed 48px date header plus two 72px rows.
    expect(slider['min'], 144);
    expect(slider['max'], 368);
    page = await render(
      'display',
      state: page['state'],
      event: {'type': 'displayHeight', 'value': 240},
    );
    expect(object(object(page['state'])['displayDraft'])['dirty'], true);
    expect(
      object(await store.get(actor, 'timetables', 'table'))
          .containsKey('rowHeight'),
      false,
    );
    // A cancelled review retains the draft without changing saved appearance.
    host.interaction = (_, method, args) async => false;
    await render(
      'display',
      state: page['state'],
      event: {'type': 'saveDisplay'},
    );
    expect(
      object(await store.get(actor, 'timetables', 'table'))
          .containsKey('rowHeight'),
      false,
    );
    mockDialogs();
    page = await render(
      'display',
      state: page['state'],
      event: {'type': 'saveDisplay'},
    );
    expect(object(object(page['state'])['displayDraft'])['dirty'], false);
    final saved = object(await store.get(actor, 'timetables', 'table'));
    expect(saved['rowHeight'], 96);
    expect(saved['periods'], _table()['periods']);
    final backup = object(
      await host.query(
        actor,
        const ServiceRef('app.schedule', 'schedule.backup.export', 1),
        {'timetableId': 'table'},
      ),
    );
    expect(object(backup['timetable'])['rowHeight'], 96);
    await host.close();
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    actor = host.instances['app.schedule']!.actor;
    page = await render('home', context: {'timetableId': 'table'});
    expect(
      object(
        _nodes(page['tree'])
            .singleWhere((n) => n['type'] == 'timeGrid')['options'],
      )['rowHeight'],
      96,
    );
    page = await render('home', context: {'timetableId': 'other'});
    expect(
      object(
        _nodes(page['tree'])
            .singleWhere((n) => n['type'] == 'timeGrid')['options'],
      )['rowHeight'],
      72,
    );
    mockDialogs();
    page = await render(
      'display',
      context: {'timetableId': 'table'},
      event: {'type': 'defaultDisplay'},
    );
    await render(
      'display',
      state: page['state'],
      event: {'type': 'saveDisplay'},
    );
    expect(
      object(await store.get(actor, 'timetables', 'table'))['rowHeight'],
      72,
    );
  });

  test('display draft rejects external changes and invalid heights', () async {
    await command('schedule.timetable.save', {'timetable': _table()});
    mockDialogs();
    var page = await render(
      'display',
      event: {'type': 'displayHeight', 'value': 240},
    );
    await command('schedule.timetable.save', {
      'timetable': {..._table(), 'rowHeight': 120},
    });
    page = await render(
      'display',
      state: page['state'],
      event: {'type': 'saveDisplay'},
    );
    expect(
      object(object(page['state'])['displayDraft'])['error'],
      contains('其他页面修改'),
    );
    expect(
      object(await store.get(actor, 'timetables', 'table'))['rowHeight'],
      120,
    );
    page = await render(
      'display',
      state: page['state'],
      event: {'type': 'resetDisplay'},
    );
    expect(object(object(page['state'])['displayDraft'])['rowHeight'], 120);
    for (final height in [47, 161, '96', null]) {
      await expectLater(
        command('schedule.timetable.save', {
          'timetable': {..._table(), 'rowHeight': height},
        }),
        throwsA(isA<Object>()),
      );
    }
  });

  test(
    'floating height controls preview fine steps, close and respect limits',
    () async {
      final periods = [
        for (var i = 0; i < 12; i++)
          {
            'number': i + 1,
            'start': '${8 + i}:00'.padLeft(5, '0'),
            'end': '${8 + i}:45'.padLeft(5, '0'),
          },
      ];
      await command('schedule.timetable.save', {
        'timetable': _table(periods: periods),
      });
      Map<String, Object?> grid(Map<String, Object?> page) => object(
        _nodes(page['tree'])
            .singleWhere((n) => n['type'] == 'timeGrid')['options'],
      );
      var page = await render('home', event: {'type': 'openDisplay'});
      expect(object(page['tree'])['floatingPanel'], isA<Map>());
      expect(object(page['header'])['autoHideChrome'], false);
      page = await render(
        'home',
        state: page['state'],
        event: {'type': 'stepDisplay', 'delta': 1},
      );
      expect(48 + 12 * (grid(page)['rowHeight'] as num), closeTo(913, .0001));
      expect(
        object(await store.get(actor, 'timetables', 'table'))
            .containsKey('rowHeight'),
        false,
      );
      page = await render(
        'home',
        state: page['state'],
        event: {'type': 'stepDisplay', 'delta': -1},
      );
      expect(grid(page)['rowHeight'], 72);
      page = await render(
        'home',
        state: page['state'],
        event: {'type': 'displayHeight', 'value': 624},
      );
      page = await render(
        'home',
        state: page['state'],
        event: {'type': 'stepDisplay', 'delta': -1},
      );
      expect(grid(page)['rowHeight'], 48);
      expect(
        _nodes(page['tree']).singleWhere((n) => n['text'] == '−1')['disabled'],
        true,
      );
      page = await render(
        'home',
        state: page['state'],
        event: {'type': 'displayHeight', 'value': 1968},
      );
      page = await render(
        'home',
        state: page['state'],
        event: {'type': 'stepDisplay', 'delta': 1},
      );
      expect(grid(page)['rowHeight'], 160);
      expect(
        _nodes(page['tree']).singleWhere((n) => n['text'] == '+1')['disabled'],
        true,
      );
      page = await render(
        'home',
        state: page['state'],
        event: {'type': 'closeDisplay'},
      );
      expect(object(page['tree']).containsKey('floatingPanel'), false);
      expect(grid(page)['rowHeight'], 72);
      expect(object(page['header'])['autoHideChrome'], true);
      page = await render(
        'home',
        state: page['state'],
        event: {'type': 'openDisplay'},
      );
      expect(grid(page)['rowHeight'], 160);
      mockDialogs();
      await render(
        'home',
        state: page['state'],
        event: {'type': 'saveDisplay'},
      );
      page = await render(
        'home',
        state: page['state'],
        event: {'type': 'closeDisplay'},
      );
      expect(grid(page)['rowHeight'], 160);
    },
  );

  for (final size in [const Size(320, 500), const Size(1200, 800)]) {
    testWidgets('floating panel remains usable with large fonts at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await command('schedule.timetable.save', {'timetable': _table()});
      });
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: ScriptPage(
              host: host,
              moduleId: 'app.schedule',
              handler: 'render',
              pageContext: const {'pageId': 'app.schedule.display'},
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.byType(TimeGrid), findsOneWidget);
      final gridRect = tester.getRect(find.byType(TimeGrid));
      final panelRect = tester.getRect(
        find.byKey(const ValueKey('script-floating-panel')),
      );
      expect(panelRect.width, lessThanOrEqualTo(420));
      expect(panelRect.bottom, lessThanOrEqualTo(gridRect.bottom));
      expect(panelRect.top, greaterThan(gridRect.top));
      await tester.ensureVisible(find.text('+1'));
      await tester.tap(find.text('+1'));
      await _settle(tester);
      expect(
        tester.widget<TimeGrid>(find.byType(TimeGrid)).options['rowHeight'],
        72.5,
      );
      expect(tester.getRect(find.byType(TimeGrid)), gridRect);
      await tester.tap(find.byTooltip('关闭高度调整'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('script-floating-panel')), findsNothing);
      expect(
        tester.widget<TimeGrid>(find.byType(TimeGrid)).options['rowHeight'],
        72,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('creating a timetable uses twelve default periods without rewriting existing schedules', () async {
    await command('schedule.timetable.save', {'timetable': _table()});
    mockDialogs();
    await render('timetables', event: {'type': 'newTimetable'});
    final all = await store.query(actor, 'timetables', {});
    expect(all, hasLength(2));
    final existing = object(
      all.singleWhere((value) => object(value)['id'] == 'table'),
    );
    expect(existing['periods'], _table()['periods']);
    final created = object(
      all.singleWhere((value) => object(value)['id'] != 'table'),
    );
    final periods = objects(created['periods']);
    expect(periods, hasLength(12));
    expect(periods.map((p) => p['number']), List.generate(12, (i) => i + 1));
    expect(periods.map((row) => '${row['start']}-${row['end']}'), [
      '08:00-08:45',
      '08:50-09:35',
      '09:50-10:35',
      '10:40-11:25',
      '11:30-12:15',
      '14:00-14:45',
      '14:50-15:35',
      '15:45-16:30',
      '16:35-17:20',
      '18:30-19:15',
      '19:20-20:05',
      '20:10-20:55',
    ]);
    expect(
      interactions.where((value) => value['method'] == 'ui.review'),
      hasLength(1),
    );
  });
  test('grouped settings list learning, schedule configuration, courses and data actions', () async {
    await command('schedule.timetable.save', {'timetable': _table()});
    final page = await render('settings');
    final nodes = _nodes(page['tree']);
    final labels = nodes.map((node) => node['text'] ?? node['title']).toList();
    expect(labels, containsAll(['概览', '课表配置', '课程与调课', '数据管理']));
    for (final destination in ['学期设置', '作息设置', '课程管理', '调课记录', '导入与备份']) {
      expect(
        nodes.where(
          (node) => node['type'] == 'listTile' && node['title'] == destination,
        ),
        hasLength(1),
      );
    }
  });

  test('period edits preserve a dirty draft and reject invalid time without writing', () async {
    await command('schedule.timetable.save', {'timetable': _table()});
    mockDialogs();
    final original = await store.get(actor, 'timetables', 'table');
    var page = await render('periods');
    expect(
      _nodes(page['tree']).where((node) => node['text'] == '保存作息设置'),
      isEmpty,
    );
    page = await render(
      'periods',
      state: page['state'],
      event: {
        'type': 'periodTime',
        'number': 1,
        'part': 'start',
        'value': '08:00',
      },
      forms: {'periods.1.start': '08:00'},
    );
    expect(
      _nodes(object(page['tree'])['footer'])
          .any((node) => node['text'] == '保存作息设置'),
      isTrue,
    );
    // Returning to the page with its retained session restores the unsaved draft.
    page = await render('periods', state: page['state']);
    expect(
      _nodes(page['tree']).any(
        (node) => node['key'] == 'periods.1.start' && node['value'] == '08:00',
      ),
      isTrue,
    );
    expect(await store.get(actor, 'timetables', 'table'), original);
    final invalid = await render(
      'periods',
      state: page['state'],
      event: {
        'type': 'periodTime',
        'number': 1,
        'part': 'end',
        'value': '07:00',
      },
      forms: {'periods.1.start': '08:00', 'periods.1.end': '07:00'},
    );
    await render(
      'periods',
      state: invalid['state'],
      event: {'type': 'savePeriods'},
    );
    expect(await store.get(actor, 'timetables', 'table'), original);
    expect(
      interactions.where((value) => value['method'] == 'ui.review'),
      isEmpty,
    );
    page = await render(
      'periods',
      state: invalid['state'],
      event: {
        'type': 'periodTime',
        'number': 1,
        'part': 'end',
        'value': '08:35',
      },
    );
    final saved = await render(
      'periods',
      state: page['state'],
      event: {'type': 'savePeriods'},
    );
    expect(
      objects(object(await store.get(actor, 'timetables', 'table'))['periods'])
          .first['start'],
      '08:00',
    );
    expect(
      _nodes(object(saved['tree'])['footer'])
          .where((node) => node['text'] == '保存作息设置'),
      isEmpty,
    );
    expect(
      interactions.where((value) => value['method'] == 'ui.review'),
      hasLength(1),
    );
  });

  test('referenced period removal is blocked and appending template preserves existing times and courses', () async {
    await command('schedule.timetable.save', {'timetable': _table()});
    await command('schedule.course.save', {
      'course': {'id': 'course', 'timetableId': 'table', 'name': '保留课程'},
      'meeting': {
        'id': 'meeting',
        'weekday': 1,
        'startPeriod': 1,
        'endPeriod': 2,
        'weeks': [1, 3],
      },
    });
    mockDialogs();
    final courses = await store.query(actor, 'courses', {});
    final meetings = await store.query(actor, 'meetings', {});
    final original = await store.get(actor, 'timetables', 'table');
    var page = await render('periods');
    page = await render(
      'periods',
      state: page['state'],
      event: {'type': 'removePeriod', 'number': 2},
    );
    expect(await store.get(actor, 'timetables', 'table'), original);
    expect(
      _nodes(page['tree']).map((node) => node['text']).join(' '),
      contains('引用'),
    );
    expect(
      interactions.where((value) => value['method'] == 'ui.review'),
      isEmpty,
    );
    await render(
      'periods',
      state: page['state'],
      event: {'type': 'appendPeriods'},
    );
    final periods = objects(
      object(await store.get(actor, 'timetables', 'table'))['periods'],
    );
    expect(periods, hasLength(12));
    expect(periods.take(2), _table()['periods']);
    expect(await store.query(actor, 'courses', {}), courses);
    expect(await store.query(actor, 'meetings', {}), meetings);
    expect(
      interactions.where((value) => value['method'] == 'ui.review'),
      hasLength(1),
    );
  });

  test('template replacement requires approval and cancellation preserves custom times', () async {
    await command('schedule.timetable.save', {'timetable': _table()});
    final original = await store.get(actor, 'timetables', 'table');
    var reviews = 0, approve = false;
    host.interaction = (caller, method, args) async {
      expect(method, 'ui.review');
      reviews++;
      expect(objects(args['writes']).single['collection'], 'timetables');
      return approve;
    };
    var page = await render('periods', event: {'type': 'templatePeriods'});
    expect(reviews, 1);
    expect(await store.get(actor, 'timetables', 'table'), original);
    approve = true;
    page = await render(
      'periods',
      state: page['state'],
      event: {'type': 'templatePeriods'},
    );
    expect(reviews, 2);
    final periods = objects(
      object(await store.get(actor, 'timetables', 'table'))['periods'],
    );
    expect(periods, hasLength(12));
    expect(periods.first['start'], '08:00');
    expect(periods.last['end'], '20:55');
    expect(
      _nodes(object(page['tree'])['footer'])
          .where((node) => node['text'] == '保存作息设置'),
      isEmpty,
    );
  });

  test('template append rejects crossing midnight without changing persisted schedule', () async {
    await command('schedule.timetable.save', {
      'timetable': _table(
        periods: [
          {'number': 1, 'start': '23:00', 'end': '23:45'},
        ],
      ),
    });
    final original = await store.get(actor, 'timetables', 'table');
    mockDialogs();
    final page = await render('periods', event: {'type': 'appendPeriods'});
    expect(await store.get(actor, 'timetables', 'table'), original);
    expect(
      _nodes(page['tree']).map((node) => node['text']).join(' '),
      contains('跨午夜'),
    );
    expect(
      interactions.where((value) => value['method'] == 'ui.review'),
      isEmpty,
    );
  });

  test('import preview summarizes actual changes and leaves storage untouched until confirmation', () async {
    mockDialogs();
    final timetable = {..._table(), 'name': '来源课表'}..remove('id');
    final draft = {
      'draftVersion': 1,
      'scope': 'test/semester',
      'adapterVersion': 'test@1',
      'complete': true,
      'timetable': timetable,
      'courses': [
        {'sourceId': 'course', 'name': '导入数学'},
      ],
      'meetings': [
        {
          'sourceId': 'meeting',
          'courseId': 'course',
          'weekday': 1,
          'startPeriod': 1,
          'endPeriod': 2,
          'weeks': [1, 3],
          'location': 'A101',
        },
      ],
      'occurrenceChanges': [],
      'warnings': ['来自导入适配器的提示'],
    };
    var page = await render('imports', context: {'draft': draft});
    page = await render(
      'imports',
      state: page['state'],
      event: {'type': 'previewImport'},
    );
    expect(await store.query(actor, 'timetables', {}), isEmpty);
    expect(await store.query(actor, 'courses', {}), isEmpty);
    expect(
      interactions.where((value) => value['method'] == 'ui.review'),
      isEmpty,
    );
    final labels = _nodes(page['tree'])
        .map((node) => node['text'] ?? node['title'])
        .join(' ');
    expect(labels, contains('新增'));
    expect(labels, contains('修改'));
    expect(labels, contains('删除'));
    expect(labels, contains('冲突'));
    expect(labels, contains('警告'));
    expect(labels, contains('来自导入适配器的提示'));
    final summary = object(object(page['state'])['importSummary']);
    expect(summary['added'], 3);
    expect(summary['updated'], 0);
    expect(summary['deleted'], 0);
    await render(
      'imports',
      state: page['state'],
      event: {'type': 'confirmImport'},
    );
    expect(await store.query(actor, 'timetables', {}), hasLength(1));
    expect(await store.query(actor, 'courses', {}), hasLength(1));
    expect(await store.query(actor, 'meetings', {}), hasLength(1));
    expect(
      interactions.where((value) => value['method'] == 'ui.review'),
      hasLength(1),
    );
  });

  test('return to this week preserves weekend courses and the menu can reveal their columns', () async {
    await command('schedule.timetable.save', {'timetable': _table()});
    await command('schedule.course.save', {
      'course': {'id': 'weekend', 'timetableId': 'table', 'name': '周日课程'},
      'meeting': {
        'id': 'weekend-meeting',
        'weekday': 7,
        'startPeriod': 1,
        'endPeriod': 2,
        'weeks': [1],
      },
    });
    host.clockNow = () => DateTime.utc(2026, 9, 13, 0, 30);
    var page = await render(
      'home',
      state: {'week': 7},
      event: {'type': 'currentWeek'},
    );
    expect(object(page['state'])['week'], 1);
    expect(object(page['header'])['title'], '第 1 周');
    page = await render(
      'home',
      state: page['state'],
      event: {'type': 'weekend'},
    );
    final grid = _nodes(page['tree'])
        .singleWhere((node) => node['type'] == 'timeGrid');
    expect(objects(grid['blocks']).single['title'], '周日课程');
    expect(object(grid['options'])['scrollToColumn'], '2026-09-12');
    expect(
      objects(grid['columns'])
          .singleWhere((column) => column['id'] == '2026-09-13')['highlight'],
      isTrue,
    );
  });

  for (final width in [420.0, 1200.0]) {
    testWidgets(
      'host header and read-only course panel adapt at $width pixels',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (width == 420) {
          tester.platformDispatcher.textScaleFactorTestValue = 1.6;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        await tester.runAsync(() async {
          await command('schedule.timetable.save', {'timetable': _table()});
          await command('schedule.course.save', {
            'course': {
              'id': 'course',
              'timetableId': 'table',
              'name': '高等数学',
              'code': 'MATH101',
              'notes': '必修',
            },
            'meeting': {
              'id': 'meeting',
              'weekday': 1,
              'startPeriod': 1,
              'endPeriod': 2,
              'weeks': [1, 3],
              'location': 'A101',
              'teacher': '王老师',
            },
          });
        });
        await tester.runAsync(() async {
          await host.install(
            await ScriptPackage.verify(
              await File('../dist/modules/app.ai.xmodule').readAsBytes(),
              allowUnsignedLocal: true,
            ),
          );
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWith((_) async => db),
              moduleHostProvider.overrideWith((_) async => host),
            ],
            child: XudianApp(),
          ),
        );
        await _settle(tester);
        expect(find.text('第 1 周'), findsOneWidget);
        expect(find.byTooltip('打开设置'), findsOneWidget);
        expect(find.byType(TimeGrid), findsOneWidget);
        await tester.tap(find.byTooltip('页面菜单'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(PopupMenuItem<int>),
            matching: find.text('AI 助手'),
          ),
          findsOneWidget,
        );
        await tester.tapAt(const Offset(10, 850));
        await tester.pumpAndSettle();
        final before = await tester.runAsync(
          () => store.query(actor, 'occurrenceChanges', {}),
        );
        await tester.tap(find.text('高等数学'));
        await _settle(tester);
        expect(find.textContaining('A101'), findsWidgets);
        expect(find.textContaining('王老师'), findsWidgets);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('单次调课'), findsOneWidget);
        if (width < 820) {
          expect(find.byType(BottomSheet), findsOneWidget);
        } else {
          expect(find.byType(BottomSheet), findsNothing);
          expect(find.byTooltip('关闭面板'), findsOneWidget);
        }
        expect(
          await tester.runAsync(
            () => store.query(actor, 'occurrenceChanges', {}),
          ),
          before,
        );
        expect(tester.takeException(), isNull);
        if (width < 820) {
          Navigator.of(tester.element(find.byType(BottomSheet))).pop();
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('打开设置'));
          await _settle(tester);
          await tester.ensureVisible(find.text('课表设置'));
          await tester.tap(find.text('课表设置'));
          await _settle(tester);
          await tester.ensureVisible(find.text('作息设置'));
          await tester.tap(find.text('作息设置'));
          await _settle(tester);
          expect(find.text('保存作息设置'), findsNothing);
          await tester.tap(find.text('07:50'));
          await tester.pumpAndSettle();
          final picker = find.byType(TimePickerDialog);
          expect(picker, findsOneWidget);
          final localization = MaterialLocalizations.of(tester.element(picker));
          expect(
            MediaQuery.of(tester.element(picker)).alwaysUse24HourFormat,
            isTrue,
          );
          await tester.tap(
            find.byTooltip(localization.inputTimeModeButtonLabel),
          );
          await tester.pumpAndSettle();
          final fields = find.descendant(
            of: picker,
            matching: find.byType(TextField),
          );
          await tester.enterText(fields.at(0), '08');
          await tester.enterText(fields.at(1), '00');
          await tester.tap(find.text(localization.okButtonLabel));
          await _settle(tester);
          expect(find.text('08:00'), findsOneWidget);
          expect(find.text('保存作息设置'), findsOneWidget);
          expect(
            objects(
              object(
                await tester.runAsync<Object?>(
                  () => store.get(actor, 'timetables', 'table'),
                ),
              )['periods'],
            ).first['start'],
            '07:50',
          );
          await tester.pageBack();
          await _settle(tester);
          await tester.ensureVisible(find.text('作息设置'));
          await tester.tap(find.text('作息设置'));
          await _settle(tester);
          expect(find.text('08:00'), findsOneWidget);
          expect(find.text('保存作息设置'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'script header failure restores the host title and keeps settings and recovery accessible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await host.uninstall('app.schedule');
        await host.install(
          await ScriptPackage.verify(
            await ScriptPackage.build(
              {
                'formatVersion': 3,
                'manifest': {
                  'id': 'private.header',
                  'version': '1.0.0',
                  'hostApi': '^1.2.0',
                  'dataVersion': 1,
                  'permissions': ['ui'],
                  'dependencies': [],
                },
                'entryPoint': 'main.js',
                'collections': [],
                'services': [],
                'pages': [
                  {
                    'id': 'private.header.home',
                    'title': '宿主后备标题',
                    'handler': 'render',
                    'headerMode': 'contributed',
                    'entry': {
                      'id': 'private.header.entry',
                      'placement': 'main',
                      'opening': 'workspace',
                    },
                  },
                ],
              },
              {
                'main.js': "export function render({event}){if(event?.type==='fail')throw new Error('测试渲染失败');return {header:{title:'脚本提供的标题'},state:{},tree:{type:'column',children:[{type:'button',text:'触发渲染故障',event:{type:'fail'}}]}};}",
              },
            ),
            allowUnsignedLocal: true,
          ),
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
          ],
          child: XudianApp(),
        ),
      );
      await _settle(tester);
      expect(find.text('脚本提供的标题'), findsOneWidget);
      expect(find.byTooltip('打开设置'), findsOneWidget);
      await tester.tap(find.text('触发渲染故障'));
      await _settle(tester);
      expect(find.text('脚本提供的标题'), findsNothing);
      expect(find.text('宿主后备标题'), findsWidgets);
      expect(find.textContaining('测试渲染失败'), findsOneWidget);
      await tester.tap(find.byTooltip('打开设置'));
      await _settle(tester);
      expect(find.text('外观主题'), findsOneWidget);
      expect(find.text('模块管理与恢复'), findsOneWidget);
      await tester.pageBack();
      await _settle(tester);
      await tester.runAsync(() => host.disable('private.header'));
      await _settle(tester);
      expect(find.text('没有可用工作区'), findsOneWidget);
      expect(find.text('打开设置并恢复模块'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
