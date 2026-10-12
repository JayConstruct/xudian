import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_app_module.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/daily_widgets.dart';
import 'package:task_app/core/ui/ui_component.dart';
import 'package:task_app/core/ui/ui_page_host.dart';
import 'package:task_app/core/ui/module_detail_page.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

Future<ScriptPackage> _source(String id) async {
  final directory = Directory('../packages/modules/$id');
  return ScriptPackage.verify(
    await ScriptPackage.build(
      object(
        jsonDecode(await File('${directory.path}/module.json').readAsString()),
      ),
      {
        for (final file in directory.listSync().whereType<File>())
          if (file.path.endsWith('.js'))
            file.uri.pathSegments.last: await file.readAsString(),
      },
    ),
    allowUnsignedLocal: true,
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late Directory directory;
  late ModuleHost host;
  late ModuleRegistry registry;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('daily-ui-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 6);
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

    await host.initialize();
    for (final id in ['app.tasks', 'app.views.today', 'app.schedule']) {
      await host.install(await _source(id));
    }
    await command('app.schedule', 'schedule.demo.create', {});
    await command('app.schedule', 'schedule.change.save', {
      'change': {
        'timetableId': 'schedule-demo-v1',
        'meetingId': 'schedule-demo-v1-meeting-1-7',
        'kind': 'cancel',
        'originalDate': '2026-10-11',
      },
    });
    await command('app.tasks', 'task.create', {
      'title': '今天的任务',
      'plannedDate': '2026-10-10',
    });
    await command('app.tasks', 'task.create', {
      'title': '明天的任务',
      'plannedDate': '2026-10-11',
    });
    final historical = await command('app.tasks', 'task.create', {
      'title': '昨天已完成的任务',
      'plannedDate': '2026-10-09',
    });
    await command('app.tasks', 'task.setCompleted', {
      'id': historical['id'],
      'completed': true,
    });
    registry = ModuleRegistry([
      for (final instance in host.instances.values)
        ScriptAppModule(host, instance.package),
    ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
  });
  tearDown(() async {
    registry.dispose();
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'real daily date clicks update tasks and courses, preserve drafts and create on the selected day',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reviews = <String>[];
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') {
          reviews.add(args['planId'] as String);
          return true;
        }
        return null;
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
          ],
          child: MaterialApp(
            theme: AppDesign.theme(Brightness.light),
            home: Scaffold(
              body: UiPackScope(
                child: UiPageHost(
                  registry: registry,
                  pageId: 'app.views.today.home',
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(
        tester.widget<DayOverview>(find.byType(DayOverview)).selectedDate,
        '2026-10-10',
      );
      expect(find.text('今天的任务'), findsOneWidget);
      expect(find.text('明天的任务'), findsNothing);
      expect(find.byType(AgendaItem), findsNWidgets(3));
      await tester.ensureVisible(find.byTooltip('添加任务'));
      await tester.tap(find.byTooltip('添加任务'));
      await _settle(tester);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '保留草稿并安排明天');
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller;
      final nextDay = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == '2026-10-11',
      );
      await tester.ensureVisible(nextDay);
      await tester.tap(nextDay);
      await _settle(tester);
      expect(
        tester.widget<DayOverview>(find.byType(DayOverview)).selectedDate,
        '2026-10-11',
      );
      expect(find.text('今天的任务'), findsNothing);
      expect(find.text('明天的任务'), findsOneWidget);
      expect(find.byType(AgendaItem), findsNWidgets(2));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller,
        same(controller),
      );
      expect(controller!.text, '保留草稿并安排明天');
      await tester.ensureVisible(find.widgetWithText(FilledButton, '添加'));
      await tester.tap(find.widgetWithText(FilledButton, '添加'));
      await _settle(tester);
      final tasks = await tester.runAsync(
        () => host.query(
          host.instances['app.tasks']!.actor,
          const ServiceRef('app.tasks', 'task.list', 1),
          {'view': 'daily', 'date': '2026-10-11'},
        ),
      ) as List;
      expect(
        tasks
            .map(object)
            .singleWhere((task) => task['title'] == '保留草稿并安排明天')['plannedDate'],
        '2026-10-11',
      );
      expect(reviews, hasLength(1));
      expect(controller.text, isEmpty);
      await tester.ensureVisible(find.text('回到今天'));
      await tester.tap(find.text('回到今天'));
      await _settle(tester);
      expect(find.text('今天的任务'), findsOneWidget);
      expect(find.text('明天的任务'), findsNothing);
      tester.widget<DayOverview>(find.byType(DayOverview)).onChanged!(
        '2026-10-09',
      );
      await _settle(tester);
      expect(find.text('昨天已完成的任务'), findsOneWidget);
      expect(
        tester.widget<DailyTaskItem>(find.byType(DailyTaskItem)).completed,
        isTrue,
      );
      expect(find.textContaining('1 项已完成'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              {
                AxisDirection.down,
                AxisDirection.up,
              }.contains(widget.axisDirection),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'agenda shell date follows selection and remains isolated from schedule headers',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final header = find.byKey(const ValueKey('workspace-header-region'));
      Finder headerDate(String date) =>
          find.descendant(of: header, matching: find.textContaining(date));
      expect(headerDate('10月10日'), findsOneWidget);
      expect(find.text('日程'), findsOneWidget);
      expect(find.text('2026年10月10日 周六'), findsNothing);
      expect(find.text('选择日期'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('workspace-date-picker')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('取消'));
      await _settle(tester);
      await tester.ensureVisible(find.byTooltip('后一天'));
      await tester.tap(find.byTooltip('后一天'));
      await _settle(tester);
      expect(headerDate('10月11日'), findsOneWidget);
      expect(headerDate('10月10日'), findsNothing);
      expect(find.text('明天的任务'), findsOneWidget);
      await tester.ensureVisible(find.text('查看课表'));
      await tester.tap(find.text('查看课表'));
      await _settle(tester);
      expect(headerDate('10月11日'), findsNothing);
      expect(find.text('第 1 周'), findsOneWidget);
      expect(find.byType(ModuleDetailPage), findsNothing);
      await tester.tap(find.text('日程'));
      await _settle(tester);
      tester.widget<DayOverview>(find.byType(DayOverview)).onChanged!(
        '2027-01-01',
      );
      await _settle(tester);
      expect(headerDate('2027年1月1日'), findsOneWidget);
      tester.view.physicalSize = const Size(320, 1000);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _settle(tester);
      expect(headerDate('2027年1月1日'), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-menu')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
