import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/app/mobile_bottom_dock.dart';
import 'package:task_app/app/more_workspace_page.dart';
import 'package:task_app/app/workspace_page_transition.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/date_page_cache.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_app_module.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/module_host/time_grid.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/daily_widgets.dart';
import 'package:task_app/core/ui/daily_date_strip.dart';
import 'package:task_app/core/ui/date_reveal.dart';
import 'package:task_app/core/ui/ui_component.dart';
import 'package:task_app/core/ui/ui_page_host.dart';
import 'package:task_app/core/ui/module_detail_page.dart';
import 'package:task_app/core/ui/workspace_typography.dart';
import 'package:task_app/core/ui/workspace_header.dart';
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
  await tester.pumpAndSettle();
}

void _expectCourseSummary(int count) {
  expect(find.byType(AgendaItem), findsOneWidget);
  expect(find.text('全部课程（$count）'), findsOneWidget);
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready, {
  String? reason,
}) async {
  for (var frame = 0; frame < 100 && !ready(); frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: reason);
}

Future<Uint8List> _paintedRegion(
  WidgetTester tester,
  Finder boundaryFinder,
  Rect region,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final result = BytesBuilder(copy: false);
      final left = region.left.floor().clamp(0, image.width);
      final right = region.right.ceil().clamp(0, image.width);
      final top = region.top.floor().clamp(0, image.height);
      final bottom = region.bottom.ceil().clamp(0, image.height);
      for (var row = top; row < bottom; row++) {
        result.add(
          pixels.buffer.asUint8List(
            (row * image.width + left) * 4,
            (right - left) * 4,
          ),
        );
      }
      return result.takeBytes();
    } finally {
      image.dispose();
    }
  }))!;
}

double _paintDifference(Uint8List before, Uint8List after) {
  expect(after.length, before.length);
  var difference = 0;
  for (var i = 0; i < before.length; i++) {
    difference += (before[i] - after[i]).abs();
  }
  return difference / (before.length * 255);
}

bool _hasPreparedDate(WidgetTester tester, ModuleHost host, String date) {
  final renderers = find.byType(ScriptPage).evaluate().where((element) {
    final page = element.widget as ScriptPage;
    return page.embedded && page.pageContext['selectedDate'] is String;
  });
  if (renderers.length < 3) return false;
  return renderers.every((element) {
    final page = element.widget as ScriptPage;
    final dynamic state = (element as StatefulElement).state;
    final cache = state.dateCache as DatePageCache;
    return cache.lookup(host.instances[page.moduleId]!, {
          'state': state.state,
          'context': {...state.pageContext as Map, 'selectedDate': date},
          'event': null,
          'formValues': state.formValues,
        }) !=
        null;
  });
}

void _clearPreparedDates(WidgetTester tester) {
  for (final element in find.byType(ScriptPage).evaluate()) {
    final dynamic state = (element as StatefulElement).state;
    (state.dateCache as DatePageCache).clear();
  }
}

String _hitDiagnostics(WidgetTester tester, Finder record) {
  if (record.evaluate().isEmpty) {
    return 'record missing, overview=${tester.widget<DayOverview>(find.byType(DayOverview)).selectedDate}, '
        'records=${tester.widgetList<DailyTaskItem>(find.byType(DailyTaskItem)).map((item) => item.title).toList()}';
  }
  final renderer = find.ancestor(of: record, matching: find.byType(ScriptPage));
  final dynamic state = tester.state(renderer);
  final ignoring = tester
      .widgetList<IgnorePointer>(
        find.ancestor(of: record, matching: find.byType(IgnorePointer)),
      )
      .map((widget) => widget.ignoring)
      .toList();
  return 'rect=${tester.getRect(record)}, busy=${state.busy}, '
      'dateContentBlocked=${state.dateContentBlocked}, ignoring=$ignoring';
}

Future<Map<String, Object?>> _commit(
  ModuleHost host,
  String module,
  String service,
  Map<String, Object?> input,
) async {
  final actor = host.instances[module]!.actor;
  final plan = await host.prepare(actor, ServiceRef(module, service, 1), input);
  host.review(plan.id, actor);
  return object(await host.commit(actor, plan.id));
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
    'real daily date clicks preserve drafts and native create and complete save once without a second review',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      host.systemTimezoneResolver = () async => 'Asia/Shanghai';
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
      _expectCourseSummary(3);
      await tester.tap(find.text('全部课程（3）'));
      await _settle(tester);
      expect(find.byType(AgendaItem), findsNWidgets(3));
      await tester.ensureVisible(find.text('收起课程'));
      await tester.tap(find.text('收起课程'));
      await _settle(tester);
      _expectCourseSummary(3);
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
      _expectCourseSummary(2);
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
      final createdTasks = tasks
          .map(object)
          .where((task) => task['title'] == '保留草稿并安排明天')
          .toList();
      expect(createdTasks, hasLength(1));
      final created = createdTasks.single;
      expect(created['plannedDate'], '2026-10-11');
      expect(created['completedAt'], isNull);
      expect(created['actualCompletedOn'], isNull);
      expect(
        reviews,
        isEmpty,
        reason: 'The native add click already authorizes this exact single task creation.',
      );
      expect(controller.text, isEmpty);
      final createdRow = find.widgetWithText(DailyTaskItem, '保留草稿并安排明天');
      expect(createdRow, findsOneWidget);
      expect(tester.widget<DailyTaskItem>(createdRow).completed, isFalse);
      final complete = find.descendant(
        of: createdRow,
        matching: find.byType(Checkbox),
      );
      await tester.ensureVisible(complete);
      await tester.tap(complete);
      await _settle(tester);
      final saved = object(
        await tester.runAsync<Object?>(
          () => host.query(
            host.instances['app.tasks']!.actor,
            const ServiceRef('app.tasks', 'task.get', 1),
            {'id': created['id']},
          ),
        ),
      );
      expect(saved['completedAt'], '2026-10-10T06:00:00.000Z');
      expect(saved['actualCompletedOn'], '2026-10-10');
      expect(saved['completedTimezone'], 'Asia/Shanghai');
      expect(saved['plannedDate'], '2026-10-11');
      expect(saved['dueDate'], created['dueDate']);
      expect(saved['updatedAt'], isNot(created['updatedAt']));
      expect(
        createdRow,
        findsNothing,
        reason: 'The selected future date only shows pending tasks after the saved completion.',
      );
      expect(find.text('明天的任务'), findsOneWidget);
      expect(
        reviews,
        isEmpty,
        reason: 'The native checkbox click authorizes completion without another review.',
      );
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
      final dateTitleStyle = tester.widget<Text>(headerDate('10月10日')).style!;
      expect(
        dateTitleStyle,
        WorkspaceTypography.titleStyle(
          Theme.of(tester.element(headerDate('10月10日'))).textTheme,
        ),
      );
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
      expect(find.text('回到今天'), findsNothing);
      await tester.tap(find.byTooltip('页面菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PopupMenuItem<int>, '回到今天'));
      await _settle(tester);
      expect(headerDate('10月10日'), findsOneWidget);
      expect(find.text('今天的任务'), findsOneWidget);
      await tester.tap(find.byTooltip('页面菜单'));
      await tester.pumpAndSettle();
      expect(find.text('回到今天'), findsNothing);
      await tester.tapAt(const Offset(10, 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('后一天'));
      await _settle(tester);

      await tester.ensureVisible(find.text('查看课表'));
      await tester.tap(find.text('查看课表'));
      await _settle(tester);
      expect(headerDate('10月11日'), findsNothing);
      expect(find.text('第 1 周'), findsOneWidget);
      expect(tester.widget<Text>(find.text('第 1 周')).style, dateTitleStyle);
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
      expect(
        tester.widget<Text>(headerDate('2027年1月1日')).style,
        dateTitleStyle,
      );
      expect(
        tester.getRect(headerDate('2027年1月1日')).bottom,
        lessThanOrEqualTo(tester.getRect(header).bottom),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'real dock revisits ready agenda and schedule without loading or losing drafts and header leases',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await host.install(await _source('app.ai'));
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
      Finder dockLabel(String label) => find.descendant(
        of: find.byType(MobileBottomDock),
        matching: find.text(label),
      );
      final header = find.byKey(const ValueKey('workspace-header-region'));
      Finder headerDate(String date) =>
          find.descendant(of: header, matching: find.textContaining(date));
      final viewport = const Rect.fromLTWH(0, 0, 390, 1000);
      void expectReadyContentOnScreen() {
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('正在加载页面…'), findsNothing);
        final content = [
          ...find.byType(DayOverview).evaluate(),
          ...find.byType(TimeGrid).evaluate(),
          ...find.byType(MoreWorkspacePage).evaluate(),
        ];
        expect(
          content.any(
            (element) => tester
                .getRect(
                  find.byElementPredicate(
                    (candidate) => identical(candidate, element),
                  ),
                )
                .overlaps(viewport),
          ),
          isTrue,
          reason:
              'At least one real ready page must remain inside the viewport.',
        );
      }

      Finder dailyRenderer({bool skipOffstage = true}) => find
          .ancestor(
            of: find.byType(DayOverview, skipOffstage: skipOffstage),
            matching: find.byType(ScriptPage, skipOffstage: skipOffstage),
          )
          .first;
      expect(
        tester
            .widget<WorkspacePageTransition>(
              find.byType(WorkspacePageTransition),
            )
            .maxRetainedPages,
        4,
      );
      await tester.tap(find.byTooltip('后一天'));
      await _settle(tester);
      expect(headerDate('10月11日'), findsOneWidget);
      expect(find.text('明天的任务'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('添加任务'));
      await tester.tap(find.byTooltip('添加任务'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), '跨页面保留的草稿');
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(tester);
      final draft = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      final dailyState = tester.state(dailyRenderer());
      final dailyScope = WorkspaceHeaderScope.read(
        tester.element(find.byType(DayOverview)),
      )!;
      final oldLease = dailyScope.lease!;
      final oldDateContent = dailyScope.controller.content!;
      expectReadyContentOnScreen();

      // A first visit prepares its real script frame offstage. The ready agenda
      // remains painted instead of a spinner while the schedule is initialized.
      await tester.tap(dockLabel('课表'));
      await tester.pump();
      expect(find.text('明天的任务'), findsOneWidget);
      expectReadyContentOnScreen();
      await _settle(tester);
      expect(find.byType(TimeGrid), findsOneWidget);
      expect(find.text('第 1 周'), findsOneWidget);
      expect(headerDate('10月11日'), findsNothing);
      final gridState = tester.state(find.byType(TimeGrid));
      final hiddenDaily = dailyRenderer(skipOffstage: false);
      expect(tester.state(hiddenDaily), same(dailyState));
      expect(TickerMode.valuesOf(tester.element(hiddenDaily)).enabled, isFalse);
      expect(find.semantics.byLabel('10月11日 周日'), findsNothing);
      final currentLease = dailyScope.controller.lease!;
      expect(currentLease.moduleId, 'app.schedule');
      expect(currentLease, isNot(same(oldLease)));
      // Simulate an already queued date callback and publication after exit.
      await oldDateContent.dispatch('date.next');
      dailyScope.controller.publishDate(
        oldLease,
        oldDateContent.owner,
        '2027-01-01',
      );
      await tester.pump();
      expect(find.text('第 1 周'), findsOneWidget);
      expect(headerDate('2027年1月1日'), findsNothing);
      expectReadyContentOnScreen();

      // Revisits expose the existing real tree on the first frame. Compare the
      // renderer and field controller before yielding to asynchronous work.
      for (var visit = 0; visit < 3; visit++) {
        await tester.tap(dockLabel('日程'));
        await tester.pump();
        expect(tester.state(dailyRenderer()), same(dailyState));
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller,
          same(draft),
        );
        expect(draft.text, '跨页面保留的草稿');
        expectReadyContentOnScreen();
        await tester.pump(const Duration(milliseconds: 120));
        expectReadyContentOnScreen();
        await _settle(tester);
        expect(headerDate('10月11日'), findsOneWidget);
        expect(find.text('第 1 周'), findsNothing);
        expect(
          tester.widget<DayOverview>(find.byType(DayOverview)).selectedDate,
          '2026-10-11',
        );
        await tester.tap(dockLabel('课表'));
        await tester.pump();
        expect(tester.state(find.byType(TimeGrid)), same(gridState));
        expectReadyContentOnScreen();
        await tester.pump(const Duration(milliseconds: 120));
        expectReadyContentOnScreen();
        await _settle(tester);
        expect(find.text('第 1 周'), findsOneWidget);
        expect(headerDate('10月11日'), findsNothing);
      }
      await tester.tap(dockLabel('日程'));
      await _settle(tester);
      final assistant = find.byKey(
        const ValueKey('mobile-navigation-assistant'),
      );
      expect(assistant, findsOneWidget);
      await tester.tap(dockLabel('更多'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final retreatingWidth = tester.getSize(assistant).width;
      expect(retreatingWidth, lessThan(62));
      expect(find.semantics.byLabel('AI'), findsNothing);
      expectReadyContentOnScreen();
      await tester.tap(dockLabel('日程'));
      await tester.pump();
      expect(tester.getSize(assistant).width, closeTo(retreatingWidth, .01));
      expect(tester.state(dailyRenderer()), same(dailyState));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller,
        same(draft),
      );
      expectReadyContentOnScreen();
      await _settle(tester);
      expect(tester.getSize(assistant).width, 62);
      expect(headerDate('10月11日'), findsOneWidget);
      expect(draft.text, '跨页面保留的草稿');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'real date strip drag keeps header tasks and courses aligned and rejects a delayed rapid reversal',
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
      final workspaceState = tester.state(find.byType(WorkspacePageTransition));
      final destination = tester
          .widget<WorkspacePageTransition>(find.byType(WorkspacePageTransition))
          .destinationId;
      await tester.ensureVisible(find.byTooltip('添加任务'));
      await tester.tap(find.byTooltip('添加任务'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), '滑动日期保留草稿');
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(tester);
      final draft = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      final rendererStates = find
          .byType(ScriptPage)
          .evaluate()
          .map((element) => (element as StatefulElement).state)
          .toList();
      final strip = find.byType(DailyDateStrip);
      final stripState = tester.state(strip);
      Future<void> swipe(double dx) async {
        final reveal = DateRevealScope.read(
          tester.element(find.byType(DayOverview)),
        )!;
        await _until(tester, () => !reveal.isTransitioning);
        await tester.ensureVisible(strip);
        await tester.drag(strip, Offset(dx, 0));
        await tester.pump();
        await tester.pump();
      }

      void expectWorkspaceAndDraft() {
        final transition = tester.widget<WorkspacePageTransition>(
          find.byType(WorkspacePageTransition),
        );
        expect(transition.destinationId, destination);
        expect(
          tester.state(find.byType(WorkspacePageTransition)),
          same(workspaceState),
        );
        expect(tester.state(strip), same(stripState));
        expect(find.byType(ModuleDetailPage), findsNothing);
        expect(find.byType(TimeGrid), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byType(TextField, skipOffstage: false))
              .controller,
          same(draft),
        );
        expect(draft.text, '滑动日期保留草稿');
      }

      expect(headerDate('10月10日'), findsOneWidget);
      expect(find.text('今天的任务'), findsOneWidget);
      _expectCourseSummary(3);
      await swipe(-60);
      expect(headerDate('10月11日'), findsOneWidget);
      expectWorkspaceAndDraft();
      await _settle(tester);
      expect(
        tester.widget<DayOverview>(find.byType(DayOverview)).selectedDate,
        '2026-10-11',
      );
      expect(find.text('明天的任务'), findsOneWidget);
      expect(find.text('今天的任务'), findsNothing);
      _expectCourseSummary(2);
      expectWorkspaceAndDraft();
      await swipe(60);
      expect(headerDate('10月10日'), findsOneWidget);
      await _settle(tester);
      expect(find.text('今天的任务'), findsOneWidget);
      expect(find.text('明天的任务'), findsNothing);
      _expectCourseSummary(3);
      expectWorkspaceAndDraft();

      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      // The real overview query cannot complete until after the opposite intent.
      _clearPreparedDates(tester);
      host.instances['app.views.today']!.workflowTail = gate.future;
      await swipe(-60);
      expect(headerDate('10月11日'), findsOneWidget);
      expectWorkspaceAndDraft();
      expect(strip.hitTestable(), findsNothing);
      await tester.tap(find.byTooltip('前一天'));
      await tester.pump();
      await tester.pump();
      expect(headerDate('10月10日'), findsOneWidget);
      expectWorkspaceAndDraft();
      gate.complete();
      for (var frame = 0; frame < 25; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(headerDate('10月11日'), findsNothing);
        expect(headerDate('10月10日'), findsOneWidget);
        expect(find.text('明天的任务'), findsNothing);
        expect(
          tester
              .widget<WorkspacePageTransition>(
                find.byType(WorkspacePageTransition),
              )
              .destinationId,
          destination,
        );
      }
      await _settle(tester);
      expect(
        tester.widget<DayOverview>(find.byType(DayOverview)).selectedDate,
        '2026-10-10',
      );
      expect(find.text('今天的任务'), findsOneWidget);
      _expectCourseSummary(3);
      expectWorkspaceAndDraft();
      final finalStates = find
          .byType(ScriptPage)
          .evaluate()
          .map((element) => (element as StatefulElement).state)
          .toList();
      expect(finalStates, orderedEquals(rendererStates));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'header controls stay usable while the date band and business records are blocked during a delayed reveal',
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
      final strip = find.byType(DailyDateStrip);
      final stripState = tester.state(strip);
      final header = find.byKey(const ValueKey('workspace-header-region'));
      Finder headerDate(String date) =>
          find.descendant(of: header, matching: find.textContaining(date));
      expect(find.text('今天的任务'), findsOneWidget);
      _expectCourseSummary(3);
      final courseWidgets = tester
          .widgetList<AgendaItem>(find.byType(AgendaItem))
          .toList();
      final beforeStates = find
          .byType(ScriptPage)
          .evaluate()
          .map((element) => (element as StatefulElement).state)
          .toList();
      _clearPreparedDates(tester);
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      host.instances['app.views.today']!.workflowTail = gate.future;
      host.instances['app.schedule']!.workflowTail = gate.future;
      await tester.tap(find.byTooltip('后一天'));
      await tester.pump();
      await tester.pump();
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(headerDate('10月11日'), findsOneWidget);
        expect(strip.hitTestable(), findsNothing);
        expect(find.byTooltip('前一天').hitTestable(), findsOneWidget);
        expect(find.byTooltip('后一天').hitTestable(), findsOneWidget);
        expect(find.semantics.byLabel('2026-10-11'), findsNothing);
        expect(tester.state(strip), same(stripState));
        expect(find.text('今天的任务').hitTestable(), findsNothing);
        expect(find.byType(AgendaItem).hitTestable(), findsNothing);
        expect(find.text('今天的任务', skipOffstage: false), findsOneWidget);
        expect(find.byType(AgendaItem, skipOffstage: false), findsOneWidget);
        expect(find.semantics.byLabel('今天的任务'), findsNothing);
      }
      // The header permits an ABA reversal while the wave's date band is inert.
      // Snapshot positions must never activate a different underlying date.
      await tester.tap(find.byTooltip('前一天'));
      await tester.pump();
      await tester.pump();
      expect(headerDate('10月10日'), findsOneWidget);
      expect(strip.hitTestable(), findsNothing);
      expect(tester.state(strip), same(stripState));
      await tester.tap(find.byTooltip('后一天'));
      await tester.pump();
      await tester.pump();
      expect(headerDate('10月11日'), findsOneWidget);
      expect(strip.hitTestable(), findsNothing);
      expect(find.byType(AgendaItem).hitTestable(), findsNothing);
      expect(find.text('今天的任务').hitTestable(), findsNothing);
      gate.complete();
      await _settle(tester);
      expect(
        tester.widget<DayOverview>(find.byType(DayOverview)).selectedDate,
        '2026-10-11',
        reason: 'The last header intent must supersede the queued return to October 10.',
      );
      expect(headerDate('10月11日'), findsOneWidget);
      expect(
        tester.widget<DayOverview>(find.byType(DayOverview)).selectedDate,
        '2026-10-11',
      );
      expect(strip.hitTestable(), findsOneWidget);
      expect(tester.state(strip), same(stripState));
      expect(find.text('今天的任务'), findsNothing);
      expect(find.text('明天的任务'), findsOneWidget);
      _expectCourseSummary(2);
      expect(
        tester.widgetList<AgendaItem>(find.byType(AgendaItem)).toList(),
        isNot(equals(courseWidgets)),
      );
      final afterStates = find
          .byType(ScriptPage)
          .evaluate()
          .map((element) => (element as StatefulElement).state)
          .toList();
      expect(afterStates, orderedEquals(beforeStates));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'date refresh fades old paint while waiting for every contribution without exposing unready records',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const screenKey = ValueKey('date-refresh-screen');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
          ],
          child: RepaintBoundary(key: screenKey, child: XudianApp()),
        ),
      );
      await _settle(tester);
      final strip = find.byType(DailyDateStrip);
      final taskRect = tester.getRect(find.text('今天的任务'));
      final sampleRect = taskRect.intersect(
        const Rect.fromLTWH(0, 0, 390, 1000),
      );
      expect(sampleRect.isEmpty, isFalse);
      final stripRect = tester.getRect(strip);
      final oldDatePaint = await _paintedRegion(
        tester,
        find.byKey(screenKey),
        stripRect,
      );
      final background = Theme.of(tester.element(find.byType(DateReveal)))
          .scaffoldBackgroundColor;
      final backgroundPixel = [
        (background.r * 255).round(),
        (background.g * 255).round(),
        (background.b * 255).round(),
        (background.a * 255).round(),
      ];
      Uint8List backgroundRegion(Uint8List region) => Uint8List.fromList([
        for (var i = 0; i < region.length ~/ 4; i++) ...backgroundPixel,
      ]);
      final courseGate = Completer<void>();
      addTearDown(() {
        if (!courseGate.isCompleted) courseGate.complete();
      });
      host.instances['app.schedule']!.workflowTail = courseGate.future;
      tester.widget<DayOverview>(find.byType(DayOverview)).onChanged!(
        '2026-10-13',
      );
      await _until(
        tester,
        () => find
            .text('2026-10-13 没有安排任务', skipOffstage: false)
            .evaluate()
            .isNotEmpty,
        reason: 'The task query should finish while the course query is held.',
      );
      expect(strip.hitTestable(), findsNothing);
      expect(find.byTooltip('前一天').hitTestable(), findsOneWidget);
      expect(find.byTooltip('后一天').hitTestable(), findsOneWidget);
      expect(find.text('今天的任务').hitTestable(), findsNothing);
      expect(find.byType(AgendaItem).hitTestable(), findsNothing);
      expect(
        find.text('2026-10-13 没有安排任务').hitTestable(),
        findsNothing,
        reason: 'Ready task content must wait for the course contribution.',
      );
      expect(find.semantics.byLabel('今天的任务'), findsNothing);
      expect(find.semantics.byLabel('2026-10-13'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final dynamic revealState = tester.state(find.byType(DateReveal));
      expect(revealState.snapshot, isA<ui.Image>());
      expect(
        revealState.animation.value,
        0,
        reason: 'The ready task contribution cannot start a partial page fade.',
      );
      // Old content leaves in 120ms; the decorative wave finishes at 480ms.
      // A slow contribution must keep the business area blank after both,
      // rather than display old records or prematurely expose ready sections.
      await tester.pump(const Duration(milliseconds: 500));
      expect(revealState.oldOpacity, 0);
      expect(revealState.waves, isEmpty);
      final waitingTaskPaint = await _paintedRegion(
        tester,
        find.byKey(screenKey),
        sampleRect,
      );
      final waitingDatePaint = await _paintedRegion(
        tester,
        find.byKey(screenKey),
        stripRect,
      );
      expect(
        _paintDifference(backgroundRegion(waitingTaskPaint), waitingTaskPaint),
        lessThan(.005),
        reason: 'Old task text and unready replacement text must be absent from paint.',
      );
      expect(
        _paintDifference(backgroundRegion(waitingDatePaint), waitingDatePaint),
        lessThan(.005),
        reason:
            'The business date band fades away while the course query is held.',
      );
      expect(strip.hitTestable(), findsNothing);
      expect(find.byType(AgendaItem).hitTestable(), findsNothing);
      expect(find.byTooltip('前一天').hitTestable(), findsOneWidget);
      expect(find.byTooltip('后一天').hitTestable(), findsOneWidget);
      courseGate.complete();
      await _settle(tester);
      expect(find.text('今天的任务'), findsNothing);
      expect(find.text('2026-10-13 没有安排任务'), findsOneWidget);
      expect(
        tester.widget<DayOverview>(find.byType(DayOverview)).selectedDate,
        '2026-10-13',
      );
      expect(strip.hitTestable(), findsOneWidget);
      expect(
        _paintDifference(
          oldDatePaint,
          await _paintedRegion(tester, find.byKey(screenKey), stripRect),
        ),
        greaterThan(.01),
        reason: 'After the shared reveal the five-day band shows the new date.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'prepared adjacent dates open behind blocked workflows and keep drafts without speculative interactions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final interactions = <String>[];
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
      // AppShell installs its host bridge during restoration. Observe the
      // subsequent speculative work after that bridge has been attached.
      host.interaction = (_, method, args) async {
        interactions.add(method);
        return null;
      };
      await tester.ensureVisible(find.byTooltip('添加任务'));
      await tester.tap(find.byTooltip('添加任务'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), '预取不会修改的草稿');
      FocusManager.instance.primaryFocus?.unfocus();
      await _until(
        tester,
        () => _hasPreparedDate(tester, host, '2026-10-11'),
        reason: 'All real date contributions should prepare their next day.',
      );
      final draft = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      expect(draft.text, '预取不会修改的草稿');
      final inputFocus = tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode;
      inputFocus.requestFocus();
      await tester.pump();
      expect(inputFocus.hasFocus, isTrue);
      expect(interactions, isEmpty);
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      host.instances['app.views.today']!.workflowTail = gate.future;
      host.instances['app.schedule']!.workflowTail = gate.future;
      await tester.tap(find.byTooltip('后一天'));
      await _until(
        tester,
        () => find.text('明天的任务').evaluate().isNotEmpty,
        reason: 'A prepared date must not wait for another JS workflow.',
      );
      final reveal = DateRevealScope.read(
        tester.element(find.byType(DayOverview)),
      )!;
      await _until(
        tester,
        () => reveal.isTransitioning && !reveal.isPreparing,
        reason: 'The prepared composition should start its reveal together.',
      );
      expect(
        find.text('明天的任务').hitTestable(),
        findsNothing,
        reason: 'A new record beneath the old snapshot is not clickable yet.',
      );
      expect(find.semantics.byLabel('明天的任务'), findsNothing);
      expect(find.byType(DailyDateStrip).hitTestable(), findsNothing);
      expect(inputFocus.hasFocus, isFalse);
      final revealedFocus = tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode;
      expect(revealedFocus.canRequestFocus, isFalse);
      revealedFocus.requestFocus();
      await tester.pump();
      expect(revealedFocus.hasFocus, isFalse);
      expect(find.byTooltip('前一天').hitTestable(), findsOneWidget);
      expect(find.byTooltip('后一天').hitTestable(), findsOneWidget);
      await tester.pump();
      await _until(
        tester,
        () => !reveal.isTransitioning,
        reason: 'Business interaction resumes when the reveal finishes.',
      );
      expect(reveal.isTransitioning, isFalse);
      expect(find.text('今天的任务'), findsNothing);
      expect(
        find.text('明天的任务').hitTestable(),
        findsOneWidget,
        reason: _hitDiagnostics(tester, find.text('明天的任务')),
      );
      _expectCourseSummary(2);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller,
        same(draft),
      );
      expect(draft.text, '预取不会修改的草稿');
      expect(revealedFocus.canRequestFocus, isTrue);
      revealedFocus.requestFocus();
      await tester.pump();
      expect(revealedFocus.hasFocus, isTrue);
      expect(interactions, isEmpty);
      gate.complete();
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'a committed task invalidates an adjacent date before cached records can be replayed',
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
      await _until(tester, () => _hasPreparedDate(tester, host, '2026-10-11'));
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      host.instances['app.views.today']!.workflowTail = gate.future;
      host.instances['app.schedule']!.workflowTail = gate.future;
      await tester.runAsync(
        () => _commit(host, 'app.tasks', 'task.create', {
          'title': '预取后新增的明天任务',
          'plannedDate': '2026-10-11',
        }),
      );
      await tester.tap(find.byTooltip('后一天'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('明天的任务', skipOffstage: false),
        findsNothing,
        reason: 'The old prepared result must not enter the live tree.',
      );
      expect(find.byType(DailyDateStrip).hitTestable(), findsNothing);
      expect(find.byTooltip('前一天').hitTestable(), findsOneWidget);
      expect(find.byTooltip('后一天').hitTestable(), findsOneWidget);
      gate.complete();
      await _settle(tester);
      expect(find.text('明天的任务'), findsOneWidget);
      expect(find.text('预取后新增的明天任务'), findsOneWidget);
      _expectCourseSummary(2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'disabling a contribution during date preparation does not strand the reveal or replay its cached courses',
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
      _clearPreparedDates(tester);
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      host.instances['app.schedule']!.workflowTail = gate.future;
      await tester.tap(find.byTooltip('后一天'));
      await _until(
        tester,
        () => find.text('明天的任务', skipOffstage: false).evaluate().isNotEmpty,
      );
      final reveal = DateRevealScope.read(
        tester.element(find.byType(DayOverview)),
      )!;
      expect(reveal.isPreparing, isTrue);
      await tester.runAsync(() => host.disable('app.schedule'));
      gate.complete();
      await _settle(tester);
      expect(reveal.isTransitioning, isFalse);
      expect(find.byType(AgendaItem, skipOffstage: false), findsNothing);
      // Changing the module inventory may replace the workspace generation.
      // Exercise its current controller, not the retired preparation owner.
      final currentReveal = DateRevealScope.read(
        tester.element(find.byType(DayOverview)),
      )!;
      tester.widget<DayOverview>(find.byType(DayOverview)).onChanged!(
        '2026-10-13',
      );
      await _settle(tester);
      expect(currentReveal.isTransitioning, isFalse);
      expect(
        tester.widget<DayOverview>(find.byType(DayOverview)).selectedDate,
        '2026-10-13',
      );
      expect(find.text('2026-10-13 没有安排任务').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('前一天'));
      await _settle(tester);
      expect(currentReveal.isTransitioning, isFalse);
      expect(
        tester.widget<DayOverview>(find.byType(DayOverview)).selectedDate,
        '2026-10-12',
      );
      expect(find.text('2026-10-12 没有安排任务').hitTestable(), findsOneWidget);
      expect(find.byType(AgendaItem, skipOffstage: false), findsNothing);
      expect(find.byType(DailyDateStrip).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
