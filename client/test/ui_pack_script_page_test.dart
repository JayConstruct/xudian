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

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('ui-page-state-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    final script = await ScriptPackage.build(
      {
        'formatVersion': 3,
        'manifest': {
          'id': 'test.page',
          'version': '1.0.0',
          'hostApi': '^1.6.0',
          'dataVersion': 1,
          'permissions': [],
          'dependencies': [],
        },
        'entryPoint': 'main.js',
        'pages': [],
        'services': [],
        'collections': [
          {
            'id': 'records',
            'schema': {'type': 'object'},
          },
        ],
      },
      {
        'main.js': r'''
import {data,ui} from '@xudian/sdk';
export async function render({state={},event}) {
  await data.query('records',{});
  state={...state,count:(state.count||0)+1};
  const items=[{type:'text',text:'render '+state.count},
    {type:'input',key:'draft',text:'草稿'},
    {type:'button',text:'执行',event:{type:'execute'}},
    ...Array.from({length:1000},(_,i)=>({type:'text',key:'row-'+i,text:'记录 '+i}))];
  return {state,tree:ui.component('ui.page.list@1',{key:'records',slots:{items}})};
}
''',
      },
    );
    await host.install(
      await ScriptPackage.verify(script, allowUnsignedLocal: true),
    );
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<ProviderContainer> show(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((_) async => db),
          moduleHostProvider.overrideWith((_) async => host),
        ],
        child: MaterialApp(
          home: UiPackScope(
            child: Scaffold(
              body: ScriptPage(
                host: host,
                moduleId: 'test.page',
                handler: 'render',
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(ScriptPage)));
  }

  Future<void> installUi(WidgetTester tester) async {
    await tester.runAsync(() async {
      final bytes = await ScriptPackage.build({
        'formatVersion': 3,
        'manifest': {
          'id': 'test.presentation',
          'kind': 'uiPack',
          'version': '1.0.0',
          'hostApi': '^1.6.0',
          'dataVersion': 1,
          'permissions': [],
          'dependencies': [],
        },
        'collections': [],
        'services': [],
        'pages': [],
        'uiPack': {
          'contractVersion': 1,
          'components': {
            'ui.input@1': {
              'tree': {
                'type': 'primitive',
                'name': 'padding',
                'props': {'padding': 20},
                'children': [
                  {'type': 'base'},
                ],
              },
            },
            'ui.button@1': {
              'tree': {
                'type': 'primitive',
                'name': 'button',
                'props': {
                  'variant': 'outlined',
                  'label': {
                    'bind': ['props', 'label'],
                  },
                },
                'event': 'press',
              },
            },
          },
          'templates': {
            'ui.page.list@1': {
              'tree': {
                'type': 'primitive',
                'name': 'card',
                'props': {'padding': 10},
                'children': [
                  {'type': 'base'},
                ],
              },
            },
          },
        },
      }, {});
      await host.install(
        await ScriptPackage.verify(bytes, allowUnsignedLocal: true),
      );
    });
    await settle(tester);
  }

  testWidgets(
    'live recipe switch preserves production input state without executing page scripts',
    (tester) async {
      final container = await show(tester);
      expect(find.text('render 1'), findsOneWidget);
      expect(find.text('记录 999'), findsNothing);
      expect(find.byType(Text).evaluate().length, lessThan(40));
      await tester.enterText(find.byType(TextField), '未提交的草稿');
      final before = tester.widget<TextField>(find.byType(TextField));
      before.controller!.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      await installUi(tester);
      await tester.runAsync(
        () => container
            .read(uiSelectionProvider.notifier)
            .save(UiSelection(globalPackId: 'test.presentation')),
      );
      await settle(tester);
      final after = tester.widget<TextField>(find.byType(TextField));
      expect(identical(before.controller, after.controller), isTrue);
      expect(identical(before.focusNode, after.focusNode), isTrue);
      expect(after.controller!.text, '未提交的草稿');
      expect(
        after.controller!.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(after.focusNode!.hasFocus, isTrue);
      expect(find.text('render 1'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(tester.takeException(), isNull);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'only read module changes refresh a page and template switches preserve scroll position',
    (tester) async {
      final container = await show(tester);
      store.changes.add({'other.module'});
      await settle(tester);
      expect(find.text('render 1'), findsOneWidget);
      store.changes.add({'test.page'});
      await settle(tester);
      expect(find.text('render 2'), findsOneWidget);
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(600);
      await tester.pump();
      await installUi(tester);
      await tester.runAsync(
        () => container
            .read(uiSelectionProvider.notifier)
            .save(UiSelection(globalPackId: 'test.presentation')),
      );
      await settle(tester);
      final after = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(identical(scroll, after), isTrue);
      expect(after.position.pixels, 600);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
