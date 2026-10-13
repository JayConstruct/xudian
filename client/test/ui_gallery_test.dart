import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/ui/ui_component.dart';
import 'package:task_app/core/ui/ui_pack.dart';
import 'package:task_app/core/ui/ui_pack_providers.dart';
import 'package:task_app/core/ui/script_transition.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

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
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('ui-gallery-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 6);
    await host.initialize();
    final folder = Directory('../packages/modules/app.ui.examples');
    final files = <String, String>{};
    for (final file in folder.listSync().whereType<File>()) {
      if (file.path.endsWith('.js')) {
        files[file.uri.pathSegments.last] = await file.readAsString();
      }
    }
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          object(
            jsonDecode(await File('${folder.path}/module.json').readAsString()),
          ),
          files,
        ),
        allowUnsignedLocal: true,
      ),
    );
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<ProviderContainer> show(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    String? demo,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((_) async => db),
          moduleHostProvider.overrideWith((_) async => host),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: UiPackScope(
            child: Scaffold(
              body: ScriptPage(
                key: ValueKey('gallery-${demo ?? 'home'}'),
                host: host,
                moduleId: 'app.ui.examples',
                handler: 'render',
                pageContext: {
                  'pageId': demo == null
                      ? 'app.ui.examples.page'
                      : 'app.ui.examples.demo.$demo',
                },
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(ScriptPage)));
  }

  Future<void> reveal(WidgetTester tester, Finder child) async {
    if (child.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        child,
        250,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 60,
      );
    }
    await tester.ensureVisible(child);
    await tester.pump();
  }

  testWidgets(
    'button events preserve sibling appearance and reject repeat clicks while busy',
    (tester) async {
      await show(tester, demo: 'button');
      final filled = find.widgetWithText(FilledButton, '填充按钮');
      final outlined = find.widgetWithText(OutlinedButton, '描边按钮');
      final before = tester.state(filled);
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      host.instances['app.ui.examples']!.workflowTail = gate.future;
      await tester.tap(outlined);
      await tester.pump();
      final button = tester.widget<FilledButton>(filled);
      expect(
        button.onPressed,
        isNotNull,
        reason: 'Refreshing another action must not switch this button to disabled colors',
      );
      expect(identical(tester.state(filled), before), isTrue);
      await tester.tap(filled);
      await tester.tap(outlined);
      await tester.pump();
      gate.complete();
      await settle(tester);
      expect(find.text('已执行：outlined'), findsOneWidget);
      expect(find.text('已执行：filled'), findsNothing);
      expect(identical(tester.state(filled), before), isTrue);
      await tester.tap(filled);
      await settle(tester);
      expect(find.text('已执行：filled'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '禁用'));
      await tester.tap(find.widgetWithText(ChoiceChip, '禁用'));
      await settle(tester);
      expect(
        tester.widget<FilledButton>(filled).onPressed,
        isNull,
        reason: 'Explicitly disabled buttons must still be disabled',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  for (final config in [
    (width: 320.0, scale: 1.5, brightness: Brightness.light),
    (width: 390.0, scale: 1.0, brightness: Brightness.light),
    (width: 1280.0, scale: 1.5, brightness: Brightness.dark),
  ]) {
    testWidgets(
      'settings catalog and date demo adapt at ${config.width}px / ${config.scale}x',
      (tester) async {
        tester.view.physicalSize = Size(config.width, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = config.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await show(tester, brightness: config.brightness);
        expect(find.text('基础操作'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('38 个基础演示 · 0 个模块注册 UI'), findsOneWidget);
        expect(find.byType(ListView), findsOneWidget);
        expect(find.byType(ListTile).evaluate().length, lessThan(38));
        final calls = <Map<String, Object?>>[];
        host.interaction = (_, method, args) async {
          calls.add({'method': method, ...args});
          return null;
        };
        await reveal(tester, find.widgetWithText(ListTile, '日期选择器'));
        await tester.tap(find.widgetWithText(ListTile, '日期选择器'));
        await settle(tester);
        expect(calls.single['page'], 'app.ui.examples.demo.date');
        await show(tester, demo: 'date', brightness: config.brightness);
        expect(find.text('查看调用方式'), findsOneWidget);
        expect(find.byType(ExpansionTile), findsNothing);
        await reveal(tester, find.widgetWithText(ChoiceChip, '已选'));
        await tester.tap(find.widgetWithText(ChoiceChip, '已选'));
        await settle(tester);
        expect(find.text('当前值：2026-10-10'), findsOneWidget);
        await reveal(tester, find.text('查看调用方式'));
        await tester.tap(find.text('查看调用方式'));
        await settle(tester);
        expect(
          (calls.last['sections'] as List)
              .map((value) => object(value)['code'])
              .join('\n'),
          contains("ui.component('ui.dateInput@1'"),
        );
        expect(calls.last['method'], 'ui.showCode');
        expect(find.textContaining('模块界面无效'), findsNothing);
        expect(tester.takeException(), isNull);
        await show(tester, demo: 'notification', brightness: config.brightness);
        await reveal(tester, find.text('长时提示 · 10 秒'));
        await tester.tap(find.text('长时提示 · 10 秒'));
        await settle(tester);
        expect(calls.last['duration'], 10000);
        await reveal(tester, find.text('打开面板并显示提示'));
        expect(find.textContaining('不支持的组件'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets(
    'real date clearing, multi-select, drafts and selected UI stay synchronized',
    (tester) async {
      await show(tester, demo: 'date');
      await tester.tap(find.widgetWithText(ChoiceChip, '已选'));
      await settle(tester);
      await tester.tap(find.byTooltip('清除日期选择器'));
      await settle(tester);
      expect(find.text('当前值：未选择'), findsOneWidget);
      await show(tester, demo: 'tags');
      await tester.tap(find.widgetWithText(FilterChip, '工作'));
      await settle(tester);
      expect(find.text('当前值：["学习","工作"]'), findsOneWidget);
      await tester.tap(find.text('重置此项'));
      await settle(tester);
      expect(find.text('当前值：["学习"]'), findsOneWidget);
      await show(tester, demo: 'title');
      await tester.enterText(find.byType(TextField), '本地未提交草稿');
      await settle(tester);
      await show(tester, demo: 'tags');
      await show(tester, demo: 'title');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '本地未提交草稿',
      );
      await tester.runAsync(() async {
        await host.install(
          await ScriptPackage.verify(
            await File('../dist/modules/example.ui.compact.xmodule')
                .readAsBytes(),
            allowUnsignedLocal: true,
          ),
        );
      });
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ScriptPage)),
      );
      await tester.runAsync(
        () => container
            .read(uiSelectionProvider.notifier)
            .save(UiSelection(globalPackId: 'example.ui.compact')),
      );
      await settle(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '本地未提交草稿',
      );
      expect(
        await tester.runAsync(() => store.sql('SELECT * FROM host_operations')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'buttons in one row, real error retry, loading and floating close remain interactive',
    (tester) async {
      await show(tester, demo: 'notification');
      final calls = <Map<String, Object?>>[];
      host.interaction = (_, method, args) async {
        calls.add({'method': method, ...args});
        return null;
      };
      await tester.tap(find.text('成功提示'));
      await settle(tester);
      expect(calls.single['method'], 'ui.notify');
      expect(calls.single['kind'], 'success');
      expect(
        tester.takeException(),
        isNull,
        reason: 'Multiple public buttons need independent keys',
      );
      await show(tester, demo: 'error');
      await tester.tap(find.text('重试'));
      await settle(tester);
      expect(find.text('重试成功，已恢复示例内容'), findsOneWidget);
      await show(tester, demo: 'loading');
      await tester.tap(find.text('开始加载'));
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('停止加载'));
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await show(tester, demo: 'floating');
      final before = tester.getRect(find.text('显示悬浮窗'));
      await tester.tap(find.text('显示悬浮窗'));
      await settle(tester);
      expect(find.text('悬浮窗示例'), findsOneWidget);
      expect(tester.getRect(find.text('显示悬浮窗')), before);
      await tester.tap(find.byTooltip('关闭悬浮窗'));
      await settle(tester);
      expect(find.text('悬浮窗示例'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  test(
    'notification examples use valid real calls and retain panel context',
    () async {
      final calls = <Map<String, Object?>>[];
      host.interaction = (_, method, args) async {
        calls.add({'method': method, ...args});
        return null;
      };
      Future<void> invoke(
        Map<String, Object?> event, {
        Map<String, Object?> context = const {
          'pageId': 'app.ui.examples.demo.notification',
        },
      }) async {
        await host.invokePage('app.ui.examples', 'render', {
          'event': event,
          'context': context,
        });
      }

      for (final kind in ['info', 'success', 'error']) {
        await invoke({'type': 'notify', 'kind': kind});
      }
      expect(calls.map((call) => call['kind']), ['info', 'success', 'error']);
      expect(calls.every((call) => call['duration'] == 3000), isTrue);
      calls.clear();

      for (final sample in ['long', 'short', 'extended']) {
        await invoke({'type': 'notify', 'sample': sample});
      }
      expect(calls.map((call) => call['duration']), [8000, 1000, 10000]);
      final longMessage = calls.first['message'] as String;
      expect(longMessage.length, inInclusiveRange(50, 200));
      calls.clear();

      await invoke({'type': 'notifySequence'});
      expect(calls.map((call) => call['kind']), ['info', 'success', 'error']);
      expect(calls.map((call) => call['message']).toSet(), hasLength(3));
      calls.clear();

      await invoke({'type': 'notifyDuplicate'});
      expect(calls, hasLength(3));
      expect(calls[0], calls[1]);
      expect(calls[1], calls[2]);
      calls.clear();

      await invoke({'type': 'panel', 'notification': true});
      expect(calls.single['method'], 'ui.panel');
      expect(calls.single['context'], {'notification': true});
      calls.clear();
      await invoke(
        {'type': 'notify', 'sample': 'panel'},
        context: {'pageId': 'app.ui.examples.local', 'notification': true},
      );
      expect(calls.single['method'], 'ui.notify');
      expect(calls.single['kind'], 'success');
    },
  );

  testWidgets(
    'script animation page accepts JS durations, changes effect and replays',
    (tester) async {
      await show(tester, demo: 'animation');
      expect(find.byType(ScriptTransition), findsOneWidget);
      expect(find.textContaining('Invalid transition node'), findsNothing);
      final transition = tester.widget<ScriptTransition>(
        find.byType(ScriptTransition),
      );
      expect(transition.duration, const Duration(milliseconds: 350));
      for (final label in ['缩放', '滑动', '淡入']) {
        await tester.tap(find.widgetWithText(ChoiceChip, label));
        await settle(tester);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('重播动画'));
      await settle(tester);
      expect(
        tester
            .widget<ScriptTransition>(find.byType(ScriptTransition))
            .replayKey,
        1,
      );
      await tester.tap(find.text('隐藏'));
      await settle(tester);
      expect(
        tester.widget<ScriptTransition>(find.byType(ScriptTransition)).visible,
        false,
      );
      await tester.tap(find.text('显示'));
      await settle(tester);
      expect(
        tester.widget<ScriptTransition>(find.byType(ScriptTransition)).visible,
        true,
      );
      expect(find.textContaining('Invalid transition node'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('home search filters metadata and recovers from no results', (
    tester,
  ) async {
    await show(tester);
    final field = find.byType(TextField);
    await tester.enterText(field, 'dateRangeInput');
    await settle(tester);
    expect(find.widgetWithText(ListTile, '起止日期'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '日期选择器'), findsNothing);
    await tester.enterText(field, '不存在的组件');
    await settle(tester);
    expect(find.text('没有匹配的示例'), findsOneWidget);
    await tester.tap(find.text('清除搜索'));
    await settle(tester);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await reveal(tester, find.widgetWithText(ListTile, '日期选择器'));
    expect(find.widgetWithText(ListTile, '日期选择器'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets(
    'pinning and unpinning in a detail refresh the retained home immediately',
    (tester) async {
      final navigation = GlobalKey<NavigatorState>();
      final homeKey = GlobalKey();
      final interactions = <String>[];
      host.interaction = (_, method, args) async {
        interactions.add(method);
        if (method == 'ui.navigate') {
          unawaited(
            navigation.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('日期演示')),
                  body: ScriptPage(
                    host: host,
                    moduleId: 'app.ui.examples',
                    handler: 'render',
                    pageContext: {
                      'pageId': args['page'],
                      ...object(args['context']),
                    },
                  ),
                ),
              ),
            ),
          );
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
            navigatorKey: navigation,
            home: Scaffold(
              body: ScriptPage(
                key: homeKey,
                host: host,
                moduleId: 'app.ui.examples',
                handler: 'render',
                pageContext: const {'pageId': 'app.ui.examples.page'},
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      final retained = homeKey.currentState;
      await tester.enterText(find.byType(TextField), '日期选择器');
      await settle(tester);
      await tester.tap(find.widgetWithText(ListTile, '日期选择器'));
      await settle(tester);
      await tester.tap(find.text('固定到首页'));
      await settle(tester);
      expect(find.text('取消固定'), findsOneWidget);
      navigation.currentState!.pop();
      await settle(tester);
      expect(homeKey.currentState, same(retained));
      expect(find.text('已固定'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '日期选择器'), findsNWidgets(2));
      await tester.tap(find.widgetWithText(ListTile, '日期选择器').first);
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(ScriptPage).last,
          matching: find.text('取消固定'),
        ),
      );
      await settle(tester);
      navigation.currentState!.pop();
      await settle(tester);
      expect(homeKey.currentState, same(retained));
      expect(find.text('已固定'), findsNothing);
      expect(find.widgetWithText(ListTile, '日期选择器'), findsOneWidget);
      expect(interactions, ['ui.navigate', 'ui.navigate']);
      expect(
        await tester.runAsync(() => store.sql('SELECT * FROM host_operations')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('every built-in example renders supported interactive controls', (
    tester,
  ) async {
    final initial = object(
      await tester.runAsync(
        () async => object(
          await host.invokePage('app.ui.examples', 'render', {
            'context': {'pageId': 'app.ui.examples.page'},
          }),
        ),
      ),
    );
    List<Map<String, Object?>> all(Object? value) {
      if (value is Map) {
        return [object(value), for (final child in value.values) ...all(child)];
      }
      if (value is List) {
        return [for (final child in value) ...all(child)];
      }
      return [];
    }

    final ids = all(initial['tree'])
        .where((node) => node['type'] == 'listTile')
        .map((node) => object(node['event'])['id'] as String)
        .toList();
    expect(ids, hasLength(38));
    for (final id in ids) {
      await show(tester, demo: id);
      expect(find.textContaining('模块界面无效'), findsNothing, reason: id);
      expect(find.textContaining('不支持的组件'), findsNothing, reason: id);
      expect(tester.takeException(), isNull, reason: id);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'reset respects edits during execution, including text changed back to its old value',
    (tester) async {
      final gate = Completer<Object?>();
      host.interaction = (_, method, args) async =>
          method == 'ui.dialog' ? gate.future : null;
      await tester.runAsync(() async {
        await host.install(
          await ScriptPackage.verify(
            await ScriptPackage.build(
              {
                'formatVersion': 3,
                'manifest': {
                  'id': 'test.form.race',
                  'version': '1.0.0',
                  'hostApi': '^1.7.0',
                  'dataVersion': 1,
                  'permissions': ['ui'],
                  'dependencies': [],
                },
                'entryPoint': 'main.js',
                'collections': [],
                'pages': [],
                'services': [],
              },
              {
                'main.js': r"""
import {ui} from '@xudian/sdk';
export async function render({event}) {
  if(event?.type==='reset')await ui.dialog({title:'等待',fields:[]});
  return {...(event?.type==='reset'?{replaceForms:{draft:'reset',tags:['学习']}}:{}),tree:{type:'column',children:[
    {type:'input',key:'draft',text:'草稿',value:'original'},
    ui.component('ui.multiSelect@1',{key:'tags',props:{label:'标签',value:['工作'],items:[{value:'学习',label:'学习'},{value:'工作',label:'工作'}]}}),
    {type:'button',text:'延迟重置',event:{type:'reset'}},
  ]}};
}
""",
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
          child: MaterialApp(
            home: Scaffold(
              body: ScriptPage(
                host: host,
                moduleId: 'test.form.race',
                handler: 'render',
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('延迟重置'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'new');
      await tester.enterText(find.byType(TextField), 'original');
      gate.complete({});
      await settle(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'original',
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '学习'))
            .selected,
        true,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '工作'))
            .selected,
        false,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets(
    'external selection updates refresh time and multi-select controls',
    (tester) async {
      await tester.runAsync(() async {
        await host.install(
          await ScriptPackage.verify(
            await ScriptPackage.build(
              {
                'formatVersion': 3,
                'manifest': {
                  'id': 'test.control.refresh',
                  'version': '1.0.0',
                  'hostApi': '^1.7.0',
                  'dataVersion': 1,
                  'permissions': [],
                  'dependencies': [],
                },
                'entryPoint': 'main.js',
                'collections': [],
                'pages': [],
                'services': [],
              },
              {
                'main.js': r"""
import {ui} from '@xudian/sdk';
export function render({state={},event}) {
  const changed=state.changed || event?.type==='change';
  return {state:{changed},tree:{type:'column',children:[
    {type:'timeInput',key:'time',text:'时间',value:changed?'10:45':'08:00'},
    ui.component('ui.multiSelect@1',{key:'tags',props:{label:'标签',value:changed?['学习']:['工作'],items:[{value:'学习',label:'学习'},{value:'工作',label:'工作'}]}}),
    {type:'button',text:'切换配置',event:{type:'change'}},
  ]}};
}
""",
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
          child: MaterialApp(
            home: Scaffold(
              body: ScriptPage(
                host: host,
                moduleId: 'test.control.refresh',
                handler: 'render',
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '08:00',
      );
      await tester.tap(find.text('切换配置'));
      await settle(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '10:45',
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '学习'))
            .selected,
        true,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '工作'))
            .selected,
        false,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
