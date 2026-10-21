import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/data_change_review.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_app_module.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/module_detail_page.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;
  late ModuleRegistry registry;

  Map<String, Object?> object(Object? value) =>
      Map<String, Object?>.from(value as Map);

  Future<void> install(String id) async {
    final directory = Directory('../packages/modules/$id');
    final scripts = <String, String>{};
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.js')) {
        scripts[file.path.substring(directory.path.length + 1)] = file
            .readAsStringSync();
      }
    }
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          object(
            jsonDecode(
              File('${directory.path}/module.json').readAsStringSync(),
            ),
          ),
          scripts,
        ),
        allowUnsignedLocal: true,
      ),
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('planner-creation-widget-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    host.clockNow = () => DateTime.utc(2026, 10, 21, 0);
    await install('app.tasks');
    await install('app.planner');
    registry = ModuleRegistry([
      for (final instance in host.instances.values)
        ScriptAppModule(host, instance.package),
    ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
    host.interaction = (_, method, args) async => method == 'ui.review';
  });
  tearDown(() async {
    registry.dispose();
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> showPanel(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((_) async => db),
          moduleHostProvider.overrideWith((_) async => host),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: ModuleDetailPage(
              registry: registry,
              pageId: 'app.planner.quickAdd',
              panel: true,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.byType(ScriptPage), findsOneWidget);
  }

  Finder input(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pump();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await settle(tester);
  }

  void expectNoErrors(WidgetTester tester) {
    expect(find.textContaining('模块界面无效'), findsNothing);
    expect(find.textContaining('不支持的组件'), findsNothing);
    expect(tester.takeException(), isNull);
  }

  void expectFooter(WidgetTester tester, String label) {
    final button = find.widgetWithText(FilledButton, label);
    expect(button.hitTestable(), findsOneWidget);
    final bounds = tester.getRect(button);
    expect(bounds.bottom, lessThanOrEqualTo(640));
    expect(bounds.width, greaterThan(280));
  }

  testWidgets(
    'narrow large-text batch, rule and template pages retain the draft and visible footer',
    (tester) async {
      await showPanel(tester);
      await tester.enterText(input('任务名称'), '窄屏阅读草稿');
      await settle(tester);
      await tapVisible(tester, find.text('批量'));
      expectFooter(tester, '预览安排');
      expectNoErrors(tester);

      await tapVisible(tester, find.text('3项 · 编辑'));
      expect(find.text('任务规则'), findsOneWidget);
      expectFooter(tester, '应用3项规则');
      await tester.ensureVisible(input('最少（天）'));
      await tester.enterText(input('最少（天）'), '5');
      await settle(tester);
      expectNoErrors(tester);
      expect(
        find.widgetWithText(FilledButton, '应用3项规则'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | '),
      );
      await tester.tap(find.widgetWithText(FilledButton, '应用3项规则'));
      await settle(tester);
      expect(find.text('5～6天'), findsOneWidget);
      expectFooter(tester, '预览安排');
      expectNoErrors(tester);

      await tapVisible(tester, find.text('从模板新建'));
      expect(find.text('选择模板'), findsOneWidget);
      final templateRows = tester.widgetList<ListTile>(find.byType(ListTile));
      expect(templateRows.length, 4);
      expect(templateRows.every((row) => row.leading == null), isTrue);
      expect(
        tester.widget<TextField>(input('搜索模板')).decoration!.prefixIcon,
        isNull,
      );
      expectNoErrors(tester);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expectFooter(tester, '预览安排');
      await tester.ensureVisible(input('任务名称'));
      expect(
        tester.widget<TextField>(input('任务名称')).controller!.text,
        '窄屏阅读草稿',
      );
      expect(find.text('5～6天'), findsOneWidget);
      expectNoErrors(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'panel header menu saves a template and inline management action works',
    (tester) async {
      final dialogs = <Map<String, Object?>>[];
      host.interaction = (_, method, args) async {
        if (method == 'ui.dialog') {
          dialogs.add(args);
          return {'name': '窄屏模板'};
        }
        return method == 'ui.review';
      };
      await showPanel(tester);
      await tester.enterText(input('任务名称'), '模板任务');
      await settle(tester);
      await tester.tap(find.byTooltip('页面菜单'));
      await settle(tester);
      expect(find.text('存为模板'), findsOneWidget);
      await tester.tap(find.text('存为模板'));
      await settle(tester);
      expect(dialogs.single['title'], '存为模板');
      expect(find.text('已保存到我的模板'), findsOneWidget);
      expectNoErrors(tester);

      await tapVisible(tester, find.text('从模板新建'));
      expect(find.text('管理').hitTestable(), findsOneWidget);
      await tester.tap(find.text('管理'));
      await settle(tester);
      expect(find.text('窄屏模板'), findsOneWidget);
      expect(find.text('删除此模板'), findsOneWidget);
      expect(find.text('完成管理'), findsOneWidget);
      expectNoErrors(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'template replacement updates mounted controllers without losing batch rules',
    (tester) async {
      host.interaction = (_, method, args) async =>
          method == 'ui.dialog' ? {'replace': true} : true;
      await showPanel(tester);
      await tester.enterText(input('任务名称'), '套用前的草稿');
      await settle(tester);
      await tapVisible(tester, find.text('从模板新建'));
      await tapVisible(tester, find.text('阅读论文'));
      expectFooter(tester, '预览安排');
      await tester.ensureVisible(input('任务名称'));
      expect(tester.widget<TextField>(input('任务名称')).controller!.text, '阅读论文');
      await tester.enterText(input('任务名称'), '模板后的修改');
      await settle(tester);
      expect(find.text('3项 · 编辑'), findsOneWidget);
      expect(
        tester.widget<TextField>(input('任务名称')).controller!.text,
        '模板后的修改',
      );
      expectNoErrors(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'batch preview confirms the frozen native plan once and starts an active rolling series',
    (tester) async {
      var externalReviews = 0;
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') {
          externalReviews++;
          return false;
        }
        return null;
      };
      Future<List<Object?>> tasks() async => (await tester.runAsync(
        () async => await host.query(
          host.instances['app.tasks']!.actor,
          const ServiceRef('app.tasks', 'task.list', 1),
          {'view': 'raw'},
        ) as List<Object?>,
      ))!;
      Future<List<Object?>> seriesRows() async => (await tester.runAsync(
        () => store.query(host.instances['app.planner']!.actor, 'series', {}),
      ))!;
      await showPanel(tester);
      await tester.enterText(input('任务名称'), '一次确认的批量任务');
      await settle(tester);
      await tapVisible(tester, find.text('批量'));
      await tester.tap(find.widgetWithText(FilledButton, '预览安排'));
      await settle(tester);
      expect(find.text('预览安排'), findsOneWidget);
      expect(await tasks(), isEmpty);
      expect(await seriesRows(), isEmpty);
      expect(externalReviews, 0);
      expect(find.textContaining('实际变更：新增'), findsOneWidget);
      final button = find.byWidgetPredicate(
        (widget) =>
            widget is FilledButton &&
            widget.child is Text &&
            RegExp(r'^确认生成\d+次$').hasMatch((widget.child as Text).data ?? ''),
      );
      expect(button.hitTestable(), findsOneWidget);
      final label = (tester.widget<FilledButton>(button).child as Text).data!;
      final count = int.parse(RegExp(r'\d+').firstMatch(label)!.group(0)!);
      expect(count, greaterThan(1));
      expectFooter(tester, label);
      expectNoErrors(tester);
      await tester.tap(find.byTooltip('查看实际变更详情'));
      await settle(tester);
      expect(find.byType(DataChangeReview), findsOneWidget);
      expect(await tasks(), isEmpty);
      Navigator.of(tester.element(find.byType(DataChangeReview))).pop();
      await settle(tester);
      await tester.tap(button);
      await settle(tester);
      expect(
        externalReviews,
        0,
        reason: 'The native footer authorizes the same frozen plan without a second external review.',
      );
      expect((await tasks()).length, count);
      final series = await seriesRows();
      expect(series.length, 1);
      final saved = object(series.single);
      expect(saved['status'], 'active');
      expect(object(saved['draft'])['autoExtend'], isTrue);
      expect(saved['windowThrough'], '2026-11-19');
      expectNoErrors(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
