import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

Future<ScriptPackage> loadSource(String id) async {
  final folder = Directory('../packages/modules/$id');
  return ScriptPackage.verify(
    await ScriptPackage.build(
      object(
        jsonDecode(await File('${folder.path}/module.json').readAsString()),
      ),
      {
        for (final file in folder.listSync().whereType<File>())
          if (file.path.endsWith('.js'))
            file.uri.pathSegments.last: await file.readAsString(),
      },
    ),
    allowUnsignedLocal: true,
  );
}

Future<void> settle(WidgetTester tester) async {
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
  late ModuleHost host;
  late Directory directory;
  late ModuleRegistry registry;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('today-style-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 6);
    await host.initialize();
    for (final id in ['app.tasks', 'app.views.today', 'app.schedule']) {
      await host.install(await loadSource(id));
    }
    Future<void> commit(
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
      await host.commit(actor, plan.id);
    }

    await commit('app.schedule', 'schedule.demo.create', {});
    await commit('app.tasks', 'task.create', {
      'title': '完成英语阅读练习',
      'plannedDate': '2026-10-10',
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

  for (final config in [
    (width: 390.0, scale: 1.0, brightness: Brightness.light),
    (width: 320.0, scale: 2.0, brightness: Brightness.dark),
  ]) {
    testWidgets(
      'composed Today is real, extensible and interactive at ${config.width}/${config.scale}',
      (tester) async {
        tester.view.physicalSize = Size(config.width, 950);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = config.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final interactions = <Map<String, Object?>>[];
        host.interaction = (_, method, args) async {
          interactions.add({'method': method, ...args});
          return method == 'ui.review' ? true : null;
        };
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWith((_) async => db),
              moduleHostProvider.overrideWith((_) async => host),
            ],
            child: MaterialApp(
              theme: AppDesign.theme(config.brightness),
              home: Scaffold(
                body: UiPackScope(
                  child: WorkspaceContentInsets(
                    bottom: 90,
                    child: UiPageHost(
                      registry: registry,
                      pageId: 'app.views.today.home',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await settle(tester);
        expect(find.byType(DayOverview), findsOneWidget);
        expect(find.byType(AgendaItem), findsOneWidget);
        expect(find.byType(DailyTaskItem), findsOneWidget);
        expect(
          tester
              .widget<DailySectionHeader>(find.byType(DailySectionHeader).first)
              .count,
          3,
        );
        expect(find.textContaining('1 项待办'), findsOneWidget);
        expect(find.text('程序设计'), findsOneWidget);
        expect(find.text('高等数学'), findsNothing);
        expect(find.text('全部课程（3）'), findsOneWidget);
        if (config.scale == 1) {
          expect(find.text('程序设计').hitTestable(), findsOneWidget);
          expect(find.text('完成英语阅读练习').hitTestable(), findsOneWidget);
        }
        final scrollables = tester.widgetList<Scrollable>(
          find.byType(Scrollable),
        );
        expect(
          scrollables.where(
            (scrollable) =>
                axisDirectionToAxis(scrollable.axisDirection) == Axis.vertical,
          ),
          hasLength(1),
        );
        expect(
          scrollables.where(
            (scrollable) =>
                axisDirectionToAxis(scrollable.axisDirection) ==
                Axis.horizontal,
          ),
          hasLength(config.width == 320 && config.scale == 2 ? 1 : 0),
        );
        await tester.ensureVisible(find.text('全部课程（3）'));
        await tester.tap(find.text('全部课程（3）'));
        await settle(tester);
        expect(find.byType(AgendaItem), findsNWidgets(3));
        expect(find.byType(DailyTaskItem), findsOneWidget);
        expect(find.text('收起课程'), findsOneWidget);
        await tester.ensureVisible(find.text('高等数学'));
        await tester.tap(find.text('高等数学'));
        await settle(tester);
        expect(interactions.last['page'], 'app.schedule.occurrence');
        await tester.ensureVisible(find.text('收起课程'));
        await tester.tap(find.text('收起课程'));
        await settle(tester);
        expect(find.byType(AgendaItem), findsOneWidget);
        expect(find.text('高等数学'), findsNothing);
        await tester.ensureVisible(find.text('完成英语阅读练习'));
        await tester.tap(find.text('完成英语阅读练习'));
        await settle(tester);
        expect(interactions.last['method'], 'ui.dialog');
        expect(interactions.last['title'], '编辑任务');
        await tester.ensureVisible(find.byTooltip('添加任务'));
        await tester.tap(find.byTooltip('添加任务'));
        await settle(tester);
        expect(find.byType(TextField), findsOneWidget);
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), '新的真实任务');
        await tester.ensureVisible(find.widgetWithText(FilledButton, '添加'));
        await tester.tap(find.widgetWithText(FilledButton, '添加'));
        await settle(tester);
        expect(find.text('新的真实任务'), findsOneWidget);
        expect(find.textContaining('2 项待办'), findsOneWidget);
        expect(find.textContaining('模块界面无效'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
