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
                host: host,
                moduleId: 'app.ui.examples',
                handler: 'render',
                pageContext: const {'pageId': 'app.ui.examples.page'},
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(ScriptPage)));
  }

  Finder card(String id) => find.byKey(ValueKey('example-$id'));
  Finder inCard(String id, Finder child) =>
      find.descendant(of: card(id), matching: child);
  Future<void> category(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, label).first);
    await tester.tap(find.widgetWithText(ChoiceChip, label).first);
    await settle(tester);
  }

  Future<void> reveal(WidgetTester tester, Finder child) async {
    await tester.ensureVisible(child);
    await tester.pump();
  }

  test('source gallery resets one example and all values without losing browse filters', () async {
    final initial = object(
      await host.invokePage('app.ui.examples', 'render', {
        'context': {'pageId': 'app.ui.examples.page'},
      }),
    );
    var page = object(
      await host.invokePage('app.ui.examples', 'render', {
        'state': initial['state'],
        'event': {'type': 'section', 'section': 'dates'},
      }),
    );
    page = object(
      await host.invokePage('app.ui.examples', 'render', {
        'state': page['state'],
        'event': {'type': 'changeDemo', 'id': 'date', 'value': '2026-10-08'},
      }),
    );
    page = object(
      await host.invokePage('app.ui.examples', 'render', {
        'state': page['state'],
        'event': {
          'type': 'changeDemo',
          'id': 'tags',
          'value': ['工作'],
        },
      }),
    );
    page = object(
      await host.invokePage('app.ui.examples', 'render', {
        'state': page['state'],
        'event': {'type': 'resetOne', 'id': 'date'},
      }),
    );
    expect(object(page['replaceForms']), {'demo.date': null});
    expect(object(object(page['state'])['examples'])['tags'], ['工作']);
    page = object(
      await host.invokePage('app.ui.examples', 'render', {
        'state': page['state'],
        'event': {'type': 'resetAll'},
        'formValues': {'gallery.search': '日期'},
      }),
    );
    expect(object(page['state'])['section'], 'dates');
    expect(object(page['replaceForms']).containsKey('gallery.search'), false);
    expect(await store.sql('SELECT * FROM host_operations'), isEmpty);
  });
  for (final config in [
    (width: 320.0, height: 640.0, scale: 1.0, dark: false),
    (width: 390.0, height: 844.0, scale: 1.5, dark: false),
    (width: 320.0, height: 640.0, scale: 2.0, dark: true),
    (width: 760.0, height: 820.0, scale: 1.0, dark: false),
    (width: 1280.0, height: 900.0, scale: 1.5, dark: true),
  ]) {
    testWidgets(
      'production gallery adapts at ${config.width}px / ${config.scale}x',
      (tester) async {
        tester.view.physicalSize = Size(config.width, config.height);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = config.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await show(
          tester,
          brightness: config.dark ? Brightness.dark : Brightness.light,
        );
        expect(find.textContaining('模块界面无效'), findsNothing);
        await category(tester, '日期与时间');
        final first = card('date'), second = card('time');
        final a = tester.getTopLeft(first), b = tester.getTopLeft(second);
        final twoColumns = config.width - 32 >= 680 * config.scale;
        if (twoColumns) {
          expect(a.dy, b.dy);
          expect(b.dx, greaterThan(a.dx));
        } else {
          expect(b.dy, greaterThan(a.dy));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  testWidgets(
    'date clearing and multi-select sync formValues, drafts survive category and pack changes',
    (tester) async {
      final container = await show(tester);
      await category(tester, '日期与时间');
      final mode = inCard('date', find.widgetWithText(ChoiceChip, '已选'));
      await reveal(tester, mode);
      await tester.tap(mode);
      await settle(tester);
      expect(inCard('date', find.text('当前值：2026-10-08')), findsOneWidget);
      final clear = find.byTooltip('清除日期选择器');
      await reveal(tester, clear);
      await tester.tap(clear);
      await settle(tester);
      expect(inCard('date', find.text('当前值：未选择')), findsOneWidget);
      await category(tester, '选择控件');
      final work = inCard('tags', find.widgetWithText(FilterChip, '工作'));
      await reveal(tester, work);
      await tester.tap(work);
      await settle(tester);
      expect(inCard('tags', find.text('当前值：["学习","工作"]')), findsOneWidget);
      final reset = inCard('tags', find.text('重置此项'));
      await reveal(tester, reset);
      await tester.tap(reset);
      await settle(tester);
      expect(inCard('tags', find.text('当前值：["学习"]')), findsOneWidget);
      await reveal(tester, work);
      await tester.tap(work);
      await settle(tester);
      await category(tester, '输入与表单');
      final title = inCard('title', find.byType(TextField));
      await reveal(tester, title);
      await tester.enterText(title, '本地未提交草稿');
      await settle(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await category(tester, '选择控件');
      await category(tester, '输入与表单');
      expect(tester.widget<TextField>(title).controller!.text, '本地未提交草稿');
      final before = tester.widget<TextField>(title);
      before.controller!.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
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
      await settle(tester);
      await tester.runAsync(
        () => container
            .read(uiSelectionProvider.notifier)
            .save(UiSelection(globalPackId: 'example.ui.compact')),
      );
      await settle(tester);
      final after = tester.widget<TextField>(title);
      expect(identical(before.controller, after.controller), true);
      expect(
        after.controller!.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(tester.takeException(), isNull);
      expect(
        await tester.runAsync(() => store.sql('SELECT * FROM host_operations')),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets(
    'search filters static metadata and can recover from no results',
    (tester) async {
      await show(tester);
      final search = find.byKey(const ValueKey('gallery.search'));
      final field = find.descendant(
        of: search,
        matching: find.byType(TextField),
      );
      await tester.enterText(field, 'dateRangeInput');
      await settle(tester);
      expect(card('range'), findsOneWidget);
      expect(card('date'), findsNothing);
      await tester.enterText(field, '不存在的组件');
      await settle(tester);
      expect(find.text('没有匹配的组件'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.tap(find.text('清除搜索／查看全部'));
      await settle(tester);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(card('date'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
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
