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
import 'package:task_app/core/module_host/time_grid.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

Future<void> _settleNative(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

// Exercise the editable module source, independently of distribution rebuilds.
Future<ScriptPackage> _scheduleSource() async {
  final directory = Directory('../packages/modules/app.schedule');
  final definition = object(
    jsonDecode(await File('${directory.path}/module.json').readAsString()),
  );
  final files = <String, String>{};
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.js')) {
      files[entity.path.substring(directory.path.length + 1)] = await entity
          .readAsString();
    }
  }
  return ScriptPackage.verify(
    await ScriptPackage.build(definition, files),
    allowUnsignedLocal: true,
  );
}

Map<String, Object?> _timetable({String zone = 'Asia/Shanghai'}) => {
  'id': 'table',
  'name': '测试课表',
  'firstMonday': '2026-09-07',
  'totalWeeks': 20,
  'timezone': zone,
  'displayWeekStart': 1,
  'periods': [
    {'number': 1, 'start': '08:00', 'end': '08:45'},
    {'number': 2, 'start': '16:00', 'end': '18:00'},
  ],
};

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;

  Future<void> setup() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('schedule-layout-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 9, 7, 0, 30);
    addTearDown(() async {
      await host.close();
      await store.close();
      await db.close();
      await directory.delete(recursive: true);
    });
    await host.initialize();
    await host.install(await _scheduleSource());
  }

  Future<void> saveTable(Map<String, Object?> timetable) async {
    final actor = host.instances['app.schedule']!.actor;
    final plan = await host.prepare(
      actor,
      const ServiceRef('app.schedule', 'schedule.timetable.save', 1),
      {'timetable': timetable},
    );
    host.review(plan.id, actor);
    await host.commit(actor, plan.id);
  }

  testWidgets(
    'week grid remains the primary view while settings subpages use host navigation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await setup();
        await saveTable(_timetable());
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
      await _settleNative(tester);
      expect(find.byType(TimeGrid), findsOneWidget);
      expect(find.text('第 1 周'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        final weekButton = tester.getSemantics(find.bySemanticsLabel('第 1 周'));
        expect(weekButton.rect.height, lessThan(120));
        expect(weekButton.rect.width, lessThan(420));
      } finally {
        semantics.dispose();
      }
      for (final label in ['学期设置', '作息设置', '添加课程', 'JSON 导入', 'JSON 导出']) {
        expect(find.text(label), findsNothing);
      }
      final originalDates = tester
          .widget<TimeGrid>(find.byType(TimeGrid))
          .columns
          .map((column) => column['id'])
          .toList();
      await tester.tap(find.byTooltip('打开设置'));
      await _settleNative(tester);
      expect(find.text('外观主题'), findsOneWidget);
      await tester.ensureVisible(find.text('课表设置'));
      await tester.tap(find.text('课表设置'));
      await _settleNative(tester);
      expect(find.text('概览'), findsOneWidget);
      expect(find.text('课表配置'), findsOneWidget);

      await tester.tap(find.text('学期设置'));
      await _settleNative(tester);
      final name = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '课表名称',
      );
      await tester.enterText(name, '更新后的学期');
      await _settleNative(tester);
      await tester.ensureVisible(find.text('保存学期设置'));
      await tester.tap(find.text('保存学期设置'));
      await _settleNative(tester);
      expect(find.text('确认实际数据变更'), findsOneWidget);
      await tester.tap(find.text('确认'));
      await _settleNative(tester);
      final saved = await tester.runAsync(
        () => store.get(
          host.instances['app.schedule']!.actor,
          'timetables',
          'table',
        ),
      );
      expect(object(saved)['name'], '更新后的学期');
      await tester.pageBack();
      await _settleNative(tester);

      for (final destination in <String, String>{
        '显示设置': '课表总高度',
        '作息设置': '节次与模板',
        '课程管理': '添加课程',
        '调课记录': '临时加课',
        '导入与备份': 'JSON 导入',
      }.entries) {
        await tester.ensureVisible(find.text(destination.key));
        await tester.tap(find.text(destination.key));
        await _settleNative(tester);
        expect(find.text(destination.value), findsOneWidget);
        if (destination.key == '显示设置') {
          expect(find.byType(TimeGrid), findsOneWidget);
          final gridSize = tester.getSize(find.byType(TimeGrid));
          final heightBefore =
              tester
                      .widget<TimeGrid>(find.byType(TimeGrid))
                      .options['rowHeight']
                  as num;
          await tester.tap(find.text('+1'));
          await _settleNative(tester);
          expect(
            tester.widget<TimeGrid>(find.byType(TimeGrid)).options['rowHeight'],
            heightBefore + .5,
          );
          expect(tester.getSize(find.byType(TimeGrid)), gridSize);
          await tester.tap(find.text('−1'));
          await _settleNative(tester);
          expect(
            tester.widget<TimeGrid>(find.byType(TimeGrid)).options['rowHeight'],
            heightBefore,
          );
          expect(find.byType(Slider), findsOneWidget);
          await tester.drag(find.byType(Slider), const Offset(80, 0));
          await _settleNative(tester);
          expect(find.text('保存显示设置'), findsOneWidget);
          await tester.tap(find.text('保存显示设置'));
          await _settleNative(tester);
          await tester.tap(find.text('确认'));
          await _settleNative(tester);
          expect(find.text('显示设置已保存'), findsOneWidget);
          await tester.tap(find.byTooltip('关闭高度调整'));
          await _settleNative(tester);
          expect(find.byType(Slider), findsNothing);
          expect(find.byType(TimeGrid), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await _settleNative(tester);
      }
      await tester.pageBack();
      await _settleNative(tester);
      await tester.pageBack();
      await _settleNative(tester);
      expect(find.byType(TimeGrid), findsOneWidget);
      expect(
        tester.widget<TimeGrid>(find.byType(TimeGrid)).options['rowHeight'],
        greaterThan(72),
      );
      expect(
        tester
            .widget<TimeGrid>(find.byType(TimeGrid))
            .columns
            .map((column) => column['id'])
            .toList(),
        originalDates,
      );
      expect(find.text('第 1 周'), findsOneWidget);
      await tester.tap(find.byTooltip('页面菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('调整课表高度'));
      await _settleNative(tester);
      expect(find.byType(Slider), findsOneWidget);
      await tester.tap(find.byTooltip('关闭高度调整'));
      await _settleNative(tester);
      expect(find.byType(Slider), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'current-day and active-period emphasis use timetable local date and time',
    () async {
      await setup();
      Future<Map<String, Object?>> grid(String zone) async {
        await saveTable(_timetable(zone: zone));
        final page = object(
          await host.invokePage('app.schedule', 'render', {
            'state': {},
            'context': {'pageId': 'app.schedule.home'},
          }),
        );
        return objects(object(page['tree'])['children'])
            .singleWhere((child) => child['type'] == 'timeGrid');
      }

      final shanghai = await grid('Asia/Shanghai');
      expect(
        objects(shanghai['columns'])
            .where((column) => column['highlight'] == true)
            .map((column) => column['id']),
        ['2026-09-07'],
      );
      expect(
        objects(shanghai['rows'])
            .where((row) => row['highlight'] == true)
            .map((row) => row['id']),
        ['1'],
      );
      final losAngeles = await grid('America/Los_Angeles');
      // The same instant is Sunday 17:30, outside this Monday-start display.
      expect(
        objects(losAngeles['columns'])
            .where((column) => column['highlight'] == true),
        isEmpty,
      );
      expect(
        objects(losAngeles['rows'])
            .where((row) => row['highlight'] == true)
            .map((row) => row['id']),
        ['2'],
      );
    },
  );

  test('selection follows settings pages and supersedes retained legacy home state', () async {
    await setup();
    await saveTable(_timetable());
    await saveTable({
      ..._timetable(),
      'id': 'other',
      'name': '第二课表',
      'firstMonday': '2026-08-31',
    });
    Future<Map<String, Object?>> render(Map<String, Object?> input) async =>
        object(await host.invokePage('app.schedule', 'render', input));
    final first = await render({
      'state': {'tab': 'courses', 'week': 7},
      'context': {'pageId': 'app.schedule.home', 'timetableId': 'table'},
    });
    expect(object(first['state']).containsKey('tab'), isFalse);
    expect(objects(object(first['tree'])['children']).last['type'], 'timeGrid');
    final selected = await render({
      'state': first['state'],
      'context': {'pageId': 'app.schedule.home', 'timetableId': 'table'},
      'event': {'type': 'select', 'id': 'other'},
    });
    expect(object(selected['state'])['week'], 2);
    // Host settings has no timetable context: the module must retain selection.
    final settings = await render({
      'context': {'pageId': 'app.schedule.settings'},
    });
    expect(
      objects(object(settings['tree'])['children'])
          .expand((group) => objects(group['children']))
          .any((child) => child['title'] == '第二课表'),
      isTrue,
    );
    final resumed = await render({
      'state': first['state'],
      'context': {
        'pageId': 'app.schedule.home',
        'timetableId': 'table',
        'week': 7,
      },
    });
    expect(object(resumed['state'])['timetableId'], 'other');
    expect(object(resumed['state'])['week'], 2);
    expect(object(resumed['state']).containsKey('tab'), isFalse);
    // A choice made on a settings child page also updates a retained home.
    await render({
      'state': settings['state'],
      'context': {'pageId': 'app.schedule.timetables'},
      'event': {'type': 'select', 'id': 'table'},
    });
    final returned = await render({
      'state': selected['state'],
      'context': {'pageId': 'app.schedule.home'},
    });
    expect(object(returned['state'])['timetableId'], 'table');
    expect(object(returned['state'])['week'], 1);
  });

  testWidgets(
    'compact single-period blocks keep long course text within their height',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final height in [48, 72, 160]) {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: TimeGrid(
                columns: const [
                  {'id': 'day', 'title': '一'},
                ],
                rows: const [
                  {'id': '1', 'title': '1', 'subtitle': '08:00\n08:45'},
                ],
                blocks: const [
                  {
                    'id': 'course',
                    'column': 'day',
                    'start': 0,
                    'end': 1,
                    'title': '非常长的课程名称用于紧凑课表显示验证',
                    'subtitle': '教学楼101\n授课教师',
                    'event': {'type': 'course'},
                  },
                ],
                options: {'fillWidth': true, 'rowHeight': height},
                onEvent: (_) {},
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final card = find.ancestor(
          of: find.text('非常长的课程名称用于紧凑课表显示验证'),
          matching: find.byType(InkWell),
        );
        expect(tester.getSize(card).height, height - 4);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'phone horizontal scrolling keeps period labels fixed and aligns day headings with blocks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(325, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeGrid(
              columns: [
                for (var i = 1; i <= 7; i++)
                  {
                    'id': 'day$i',
                    'title': ['', '一', '二', '三', '四', '五', '六', '日'][i],
                    'subtitle': '09-$i',
                  },
              ],
              rows: const [
                {'id': '1', 'title': '1', 'subtitle': '08:00\n08:45'},
                {'id': '2', 'title': '2', 'subtitle': '16:00\n18:00'},
              ],
              blocks: const [
                {
                  'id': 'last',
                  'column': 'day7',
                  'start': 0,
                  'end': 1,
                  'title': 'Sunday course',
                  'event': {'id': 'last'},
                },
              ],
              corner: const {'title': '2026', 'subtitle': '1周'},
              options: const {
                'fillWidth': true,
                'labelWidth': 42,
                'minColumnWidth': 68,
              },
              onEvent: (_) {},
            ),
          ),
        ),
      );
      final labelBefore = tester.getRect(find.text('1'));
      final headingBefore = tester.getRect(find.text('日'));
      final courseBefore = tester.getRect(find.text('Sunday course'));
      final horizontal = find.byKey(
        const PageStorageKey('time-grid-horizontal'),
      );
      await tester.drag(horizontal, const Offset(-450, 0));
      await tester.pumpAndSettle();
      final labelAfter = tester.getRect(find.text('1'));
      final headingAfter = tester.getRect(find.text('日'));
      final courseAfter = tester.getRect(find.text('Sunday course'));
      expect(labelAfter.left, labelBefore.left);
      expect(headingAfter.left, lessThan(headingBefore.left));
      expect(headingAfter.right, lessThanOrEqualTo(325));
      expect(
        headingBefore.left - headingAfter.left,
        closeTo(courseBefore.left - courseAfter.left, .01),
      );
      expect(courseAfter.left, greaterThanOrEqualTo(42));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
