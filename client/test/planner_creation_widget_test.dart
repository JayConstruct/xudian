import 'dart:async';
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
import 'package:task_app/core/module_host/ui_preferences.dart';
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

  Future<void> openAdd(WidgetTester tester) =>
      tapVisible(tester, find.text('添加内容或规则'));

  Future<void> openTemplates(WidgetTester tester) async {
    await tester.tap(find.byTooltip('页面菜单'));
    await settle(tester);
    await tapVisible(tester, find.text('从模板新建'));
  }

  Future<void> openMultiple(WidgetTester tester) async {
    await openAdd(tester);
    await tapVisible(tester, find.text('多次任务'));
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

  Future<void> showEchoPage(WidgetTester tester, {bool cache = false}) async {
    await tester.runAsync(
      () async => host.install(
        await ScriptPackage.verify(
          await ScriptPackage.build(
            {
              'formatVersion': 3,
              'manifest': {
                'id': 'test.form-echo',
                'version': '1.0.0',
                'hostApi': '^1.43.0',
                'dataVersion': 1,
                'permissions': ['ui'],
              },
              'entryPoint': 'main.js',
              'collections': [],
              'pages': [],
              'services': [],
            },
            {
              'main.js':
                  '''
import {ui} from '@xudian/sdk';
export async function render(input) {
  const event = input.event || {};
  let text = input.formValues?.name || '';
  if (event.type === 'echo' && typeof event.value === 'string') text = event.value;
  if (event.type === 'replace') text = event.text;
  if (event.type === 'delayedReplace') {
    await ui.dialog({title: '等待回写', fields: []});
    text = event.text;
  }
  if (event.type === 'clearCache') await ui.preferences.set('echo.input.v1', null);
  const button = (label, text, type = 'replace') => ({type: 'button', text: label, event: {type, text}});
  return {replaceForms: {name: text}, tree: {type: 'column',
    formCache: ${cache ? "{preferenceKey:'echo.input.v1',fields:['name']}" : 'null'}, children: [
    {type: 'input', key: 'name', text: '名称', value: text, onChangeEvent: {type: 'echo'}},
    {type: 'input', key: 'uncached', text: '不缓存字段'},
    button('替换后缀', '开始zhongwen资料已更新'),
    button('替换拼音', '开始中文资料已更新'),
    button('缩短文本', '阅读'),
    button('延迟替换', '异步返回的文本', 'delayedReplace'),
    button('保存并清空缓存', '', 'clearCache'),
  ]}};
}
''',
            },
          ),
          allowUnsignedLocal: true,
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((_) async => db),
          moduleHostProvider.overrideWith((_) async => host),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ScriptPage(
              host: host,
              moduleId: 'test.form-echo',
              handler: 'render',
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('planner form echoes preserve caret and Chinese composition', (
    tester,
  ) async {
    await showPanel(tester);
    await tester.showKeyboard(input('任务名称'));
    const editing = TextEditingValue(
      text: '先阅读zhongwen资料',
      selection: TextSelection.collapsed(offset: 7),
      composing: TextRange(start: 3, end: 11),
    );
    tester.testTextInput.updateEditingValue(editing);
    final controller = tester.widget<TextField>(input('任务名称')).controller!;
    var notifications = 0;
    void changed() => notifications++;
    controller.addListener(changed);
    await settle(tester);
    expect(controller.value, editing);
    expect(
      notifications,
      0,
      reason: 'An equal echo must not rewrite the IME value.',
    );
    controller.removeListener(changed);
    expectNoErrors(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'opted-in form cache saves the latest input before debounce and disposal',
    (tester) async {
      await showEchoPage(tester, cache: true);
      await tester.enterText(input('不缓存字段'), '不应持久化的值');
      await tester.showKeyboard(input('名称'));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: '尚未完成'),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: '最后150ms的新输入'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      final saved = await tester.runAsync(
        () =>
            ModuleUiPreferences(store)
                .get(host.instances['test.form-echo']!.actor, 'echo.input.v1'),
      );
      expect(saved, {'name': '最后150ms的新输入'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'form cache failures stay visible and a later successful edit clears them',
    (tester) async {
      await showEchoPage(tester, cache: true);
      await tester.enterText(input('名称'), '字' * 5000);
      await settle(tester);
      expect(find.text('草稿未保存，请保留当前页面并重试。'), findsOneWidget);
      expect(find.textContaining('模块界面无效'), findsNothing);
      await tester.enterText(input('名称'), '已恢复保存');
      await settle(tester);
      expect(find.text('草稿未保存，请保留当前页面并重试。'), findsNothing);
      final saved = await tester.runAsync(
        () =>
            ModuleUiPreferences(store)
                .get(host.instances['test.form-echo']!.actor, 'echo.input.v1'),
      );
      expect(saved, {'name': '已恢复保存'});
      expectNoErrors(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'module cache clearing waits for all earlier native form writes',
    (tester) async {
      await showEchoPage(tester, cache: true);
      await tester.showKeyboard(input('名称'));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: '旧输入'),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: '保存前的新输入'),
      );
      await tester.tap(find.text('保存并清空缓存'));
      await settle(tester);
      final saved = await tester.runAsync(
        () =>
            ModuleUiPreferences(store)
                .get(host.instances['test.form-echo']!.actor, 'echo.input.v1'),
      );
      expect(saved, isNull);
      expectNoErrors(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('waiting for native cache does not rebase an older field echo', (
    tester,
  ) async {
    await showEchoPage(tester, cache: true);
    late Completer<void> gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    late Future<void> lock;
    await tester.runAsync(() async {
      gate = Completer<void>();
      final entered = Completer<void>();
      lock = db.transaction(() async {
        entered.complete();
        await gate.future;
      });
      await entered.future;
    });
    await tester.enterText(input('名称'), '旧字段');
    await tester.pump(const Duration(milliseconds: 180));
    await tester.enterText(input('名称'), '后输入的新字段');
    final controller = tester.widget<TextField>(input('名称')).controller!;
    final echoed = <String>[];
    void changed() => echoed.add(controller.text);
    controller.addListener(changed);
    gate.complete();
    await tester.runAsync(() => lock);
    await settle(tester);
    controller.removeListener(changed);
    expect(echoed, isNot(contains('旧字段')));
    expect(controller.text, '后输入的新字段');
    expectNoErrors(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'changed form echoes retain valid ranges and clamp shorter text',
    (tester) async {
      await showEchoPage(tester);
      await tester.showKeyboard(input('名称'));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '开始zhongwen结束',
          selection: TextSelection(
            baseOffset: 8,
            extentOffset: 4,
            isDirectional: true,
          ),
          composing: TextRange(start: 2, end: 10),
        ),
      );
      await settle(tester);
      final controller = tester.widget<TextField>(input('名称')).controller!;
      await tester.tap(find.text('替换后缀'));
      await settle(tester);
      expect(controller.text, '开始zhongwen资料已更新');
      expect(
        controller.selection,
        const TextSelection(
          baseOffset: 8,
          extentOffset: 4,
          isDirectional: true,
        ),
      );
      expect(controller.value.composing, const TextRange(start: 2, end: 10));
      await tester.tap(find.text('替换拼音'));
      await settle(tester);
      expect(controller.text, '开始中文资料已更新');
      expect(controller.value.composing, TextRange.empty);
      await tester.tap(find.text('缩短文本'));
      await settle(tester);
      expect(controller.text, '阅读');
      expect(
        controller.selection,
        const TextSelection(
          baseOffset: 2,
          extentOffset: 2,
          isDirectional: true,
        ),
      );
      expectNoErrors(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('delayed form replacement keeps a newer local edit', (
    tester,
  ) async {
    await showEchoPage(tester);
    await tester.enterText(input('名称'), '原草稿');
    await settle(tester);
    final dialog = Completer<void>();
    addTearDown(() {
      if (!dialog.isCompleted) dialog.complete();
    });
    var awaitingDialog = false;
    host.interaction = (_, method, args) async {
      if (method == 'ui.dialog') {
        awaitingDialog = true;
        await dialog.future;
      }
      return null;
    };
    await tester.tap(find.text('延迟替换'));
    await settle(tester);
    expect(awaitingDialog, isTrue);
    await tester.showKeyboard(input('名称'));
    const newer = TextEditingValue(
      text: '用户继续输入的新草稿',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 2, end: 6),
    );
    tester.testTextInput.updateEditingValue(newer);
    dialog.complete();
    await settle(tester);
    expect(tester.widget<TextField>(input('名称')).controller!.value, newer);
    expectNoErrors(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'narrow large-text unified pages retain title, staged location and footer',
    (tester) async {
      await showPanel(tester);
      await tester.enterText(input('任务名称'), '窄屏阅读草稿');
      await settle(tester);
      expectFooter(tester, '创建任务');
      expect(find.text('单次'), findsNothing);
      expect(find.text('批量'), findsNothing);
      expect(find.text('＋ 添加描述'), findsNothing);
      expectNoErrors(tester);
      await openAdd(tester);
      expect(find.text('添加内容或规则'), findsOneWidget);
      await tapVisible(tester, find.text('地点'));
      await tester.enterText(input('地点'), '图书馆302');
      await settle(tester);
      expectFooter(tester, '保存地点');
      await tester.tap(find.widgetWithText(FilledButton, '保存地点'));
      await settle(tester);
      expectFooter(tester, '创建任务');
      expect(find.textContaining('图书馆302'), findsOneWidget);
      expectNoErrors(tester);
      await openAdd(tester);
      await tapVisible(tester, find.text('描述'));
      await tester.enterText(input('详细描述'), '未保存的描述');
      await settle(tester);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.text('添加内容或规则'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expectFooter(tester, '创建任务');
      expect(find.text('未保存的描述'), findsNothing);
      expect(find.textContaining('图书馆302'), findsOneWidget);
      await tester.ensureVisible(input('任务名称'));
      expect(
        tester.widget<TextField>(input('任务名称')).controller!.text,
        '窄屏阅读草稿',
      );
      expectNoErrors(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'scheduled range and fixed switch stay editable in a narrow large-text child page',
    (tester) async {
      await showPanel(tester);
      await tester.enterText(input('任务名称'), '固定时间草稿');
      await settle(tester);
      await openAdd(tester);
      await tapVisible(tester, find.text('起止时间'));
      expectFooter(tester, '保存时间');
      await tapVisible(tester, find.text('固定时间'));
      expectNoErrors(tester);
      await tester.tap(find.widgetWithText(FilledButton, '保存时间'));
      await settle(tester);
      expectFooter(tester, '创建任务');
      expect(find.textContaining('已固定'), findsOneWidget);
      await tapVisible(tester, find.text('起止时间'));
      await tapVisible(tester, find.text('固定时间'));
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(
        find.textContaining('已固定'),
        findsOneWidget,
        reason: 'Back must discard an un-applied change to the fixed switch.',
      );
      expectFooter(tester, '创建任务');
      expectNoErrors(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'narrow large-text multiple setup is deeper and template navigation retains its rules',
    (tester) async {
      await showPanel(tester);
      await tester.enterText(input('任务名称'), '窄屏多次草稿');
      await settle(tester);
      await openMultiple(tester);
      expectFooter(tester, '保存多次设置');
      await tester.ensureVisible(input('最少（天）'));
      await tester.enterText(input('最少（天）'), '5');
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, '保存多次设置'));
      await settle(tester);
      expect(find.textContaining('5～6天'), findsOneWidget);
      expectFooter(tester, '预览安排');
      expectNoErrors(tester);
      await openTemplates(tester);
      expect(find.text('选择模板'), findsOneWidget);
      final templateRows = tester.widgetList<ListTile>(find.byType(ListTile));
      expect(templateRows.length, 4);
      expect(templateRows.every((row) => row.leading == null), isTrue);
      expect(
        tester.widget<TextField>(input('搜索模板')).decoration!.prefixIcon,
        isNull,
      );
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expectFooter(tester, '预览安排');
      await tester.ensureVisible(input('任务名称'));
      expect(
        tester.widget<TextField>(input('任务名称')).controller!.text,
        '窄屏多次草稿',
      );
      expect(find.textContaining('5～6天'), findsOneWidget);
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

      await openTemplates(tester);
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
      await openTemplates(tester);
      await tapVisible(tester, find.text('阅读论文'));
      expectFooter(tester, '预览安排');
      await tester.ensureVisible(input('任务名称'));
      expect(tester.widget<TextField>(input('任务名称')).controller!.text, '阅读论文');
      await tester.enterText(input('任务名称'), '模板后的修改');
      await settle(tester);
      expect(find.text('多次任务'), findsOneWidget);
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
      await openMultiple(tester);
      await tester.tap(find.widgetWithText(FilledButton, '保存多次设置'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, '预览安排'));
      await settle(tester);
      // Real module reads can finish near the end of settle on slower runners.
      // Finish the route transition before counting its title and footer.
      await tester.pumpAndSettle();
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
