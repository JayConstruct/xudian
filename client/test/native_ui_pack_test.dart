import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_dialogs.dart';
import 'package:task_app/app/app_toast.dart';
import 'package:task_app/app/app_ui_feedback.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/ui/native_ui.dart';
import 'package:task_app/core/ui/ui_component.dart';
import 'package:task_app/core/ui/ui_pack.dart';
import 'package:task_app/core/ui/ui_pack_providers.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

Map<String, Object?> marker(String text) => {
  'type': 'primitive',
  'name': 'text',
  'props': {'text': text},
};
Map<String, Object?> slot(String name) => {'type': 'slot', 'name': name};
Map<String, Object?> column(List<Map<String, Object?>> children) => {
  'type': 'primitive',
  'name': 'column',
  'children': children,
};

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('native-pack-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    for (final id in ['first', 'second']) {
      final bytes = await ScriptPackage.build({
        'formatVersion': 3,
        'manifest': {
          'id': 'test.$id',
          'kind': 'uiPack',
          'version': '1.0.0',
          'hostApi': '^1.15.0',
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
            'ui.button@1': {
              'tree': {
                'type': 'primitive',
                'name': 'button',
                'props': {
                  'variant': id == 'first' ? 'text' : 'outlined',
                  'label': {
                    'bind': ['props', 'label'],
                  },
                },
                'event': 'press',
              },
            },
            'ui.input@1': {
              'tree': {
                'type': 'primitive',
                'name': 'padding',
                'props': {'padding': id == 'first' ? 4 : 12},
                'children': [
                  {'type': 'base'},
                ],
              },
            },
            'ui.nativeControl@1': {
              'tree': column([marker('$id composite'), slot('control')]),
            },
            'ui.nativeTile@1': {
              'tree': column([marker('$id tile'), slot('control')]),
            },
            'ui.notification@1': {
              'tree': column([marker('$id notice'), slot('content')]),
            },
            'ui.nativeFeedback@1': {
              'tree': column([marker('$id feedback'), slot('control')]),
            },
            'ui.nativeDialog@1': {
              'tree': column([marker('$id dialog'), slot('control')]),
            },
          },
          'templates': {
            'ui.page.native@1': {
              'tree': {
                'type': 'primitive',
                'name': 'card',
                'children': [
                  column([marker('$id page'), slot('body')]),
                ],
              },
            },
          },
        },
      }, {});
      await host.install(
        await ScriptPackage.verify(bytes, allowUnsignedLocal: true),
      );
    }
    final bytes = await ScriptPackage.build(
      {
        'formatVersion': 3,
        'manifest': {
          'id': 'test.consumer',
          'version': '1.0.0',
          'hostApi': '^1.15.0',
          'dataVersion': 1,
          'permissions': [],
          'dependencies': [],
        },
        'entryPoint': 'main.js',
        'pages': [],
        'services': [],
        'collections': [],
      },
      {
        'main.js': r'''
import {ui} from '@xudian/sdk';
export function render({state={},event}) {
  if(event?.type==='press') state={...state,count:(state.count||0)+1};
  return {state,tree:{type:'column',children:[
    {type:'text',text:'script presses '+(state.count||0)},
    {type:'input',key:'draft',text:'Script draft'},
    ui.component('ui.button@1',{props:{label:'Script action'},events:{press:{type:'press'}}})
  ]}};
}
''',
      },
    );
    await host.install(
      await ScriptPackage.verify(bytes, allowUnsignedLocal: true),
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

  testWidgets(
    'installed packs alter native pages and ScriptPage while retaining controls and data',
    (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      var presses = 0;
      var iconPresses = 0;
      final navigator = GlobalKey<NavigatorState>();
      final records = await store.sql('SELECT * FROM host_records');
      final operations = await store.sql('SELECT * FROM host_operations');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            builder: (_, child) => UiPackScope(child: child!),
            home: NativeUi(
              child: Scaffold(
                appBar: AppBar(title: const Text('Native settings')),
                body: ListView(
                  children: [
                    NativeUi(
                      child: TextField(
                        controller: controller,
                        focusNode: focus,
                        decoration: const InputDecoration(
                          labelText: 'Native draft',
                        ),
                      ),
                    ),
                    NativeUi(
                      child: FilledButton(
                        onPressed: () => presses++,
                        child: const Text('Native action'),
                      ),
                    ),
                    for (final button in [
                      FilledButton.icon(
                        onPressed: () => iconPresses++,
                        icon: const Icon(Icons.add),
                        label: const Text('Filled icon'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => iconPresses++,
                        icon: const Icon(Icons.add),
                        label: const Text('Outlined icon'),
                      ),
                      TextButton.icon(
                        onPressed: () => iconPresses++,
                        icon: const Icon(Icons.add),
                        label: const Text('Text icon'),
                      ),
                    ])
                      NativeUi(child: button),
                    NativeUi(
                      child: ListTile(
                        title: const Text('Native details'),
                        onTap: () => presses++,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NativeUi).first),
      );
      Future<void> select(String id) async {
        await tester.runAsync(
          () => container
              .read(uiSelectionProvider.notifier)
              .save(UiSelection(globalPackId: 'test.$id')),
        );
        await settle(tester);
      }

      expect(
        UiScopeData.maybeOf(tester.element(find.byType(TextField)))!.registry
            .implementationProvider('ui.button@1'),
        defaultUiPackId,
      );
      await tester.enterText(find.byType(TextField), 'native unsaved draft');
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 5,
      );
      await select('first');
      expect(find.text('first page'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Native action'), findsOneWidget);
      await select('second');
      expect(find.text('second page'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Native action'),
        findsOneWidget,
      );
      expect(controller.text, 'native unsaved draft');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 5),
      );
      expect(focus.hasFocus, isTrue);
      focus.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Native action'));
      await tester.tap(find.text('Native details'));
      for (final label in ['Filled icon', 'Outlined icon', 'Text icon']) {
        await tester.tap(find.text(label));
      }
      expect(presses, 2);
      expect(iconPresses, 3);
      expect(find.text('second composite'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: ScriptPage(
              host: host,
              moduleId: 'test.consumer',
              handler: 'render',
            ),
          ),
        ),
      );
      await settle(tester);
      expect(
        find.widgetWithText(OutlinedButton, 'Script action'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField).last,
        'script unsaved draft',
      );
      final field = tester.widget<TextField>(find.byType(TextField).last);
      await select('first');
      expect(find.widgetWithText(TextButton, 'Script action'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller,
        same(field.controller),
      );
      expect(field.controller!.text, 'script unsaved draft');
      expect(find.text('script presses 0'), findsOneWidget);
      await tester.tap(find.text('Script action'));
      await settle(tester);
      expect(find.text('script presses 1'), findsOneWidget);
      expect(
        await tester.runAsync(() => store.sql('SELECT * FROM host_records')),
        records,
      );
      expect(
        await tester.runAsync(() => store.sql('SELECT * FROM host_operations')),
        operations,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'typed dropdowns retain selection and disabled behavior under an installed pack',
    (tester) async {
      var word = 'one';
      var number = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
          ],
          child: MaterialApp(
            builder: (_, child) => UiPackScope(child: child!),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (_, update) => Column(
                  children: [
                    NativeUi(
                      child: DropdownButtonFormField<String>(
                        initialValue: word,
                        decoration: const InputDecoration(labelText: 'Words'),
                        items: const [
                          DropdownMenuItem(value: 'one', child: Text('One')),
                          DropdownMenuItem(value: 'two', child: Text('Two')),
                        ],
                        onChanged: (value) => update(() => word = value!),
                      ),
                    ),
                    NativeUi(
                      child: DropdownButtonFormField<int>(
                        initialValue: number,
                        decoration: const InputDecoration(labelText: 'Numbers'),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('Number one')),
                          DropdownMenuItem(value: 2, child: Text('Number two')),
                        ],
                        onChanged: (value) => update(() => number = value!),
                      ),
                    ),
                    NativeUi(
                      child: DropdownButtonFormField<String>(
                        initialValue: 'locked',
                        decoration: const InputDecoration(
                          labelText: 'Disabled',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'locked',
                            child: Text('Locked'),
                          ),
                        ],
                        onChanged: null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NativeUi).first),
      );
      await tester.runAsync(
        () => container
            .read(uiSelectionProvider.notifier)
            .save(UiSelection(globalPackId: 'test.second')),
      );
      await settle(tester);
      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Two').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Number one'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Number two').last);
      await tester.pumpAndSettle();
      expect(word, 'two');
      expect(number, 2);
      final barriers = find.byType(ModalBarrier).evaluate().length;
      await tester.tap(find.text('Locked'));
      await tester.pumpAndSettle();
      expect(find.byType(ModalBarrier).evaluate().length, barriers);
      final disabled = tester.widget<DropdownButton<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButton<String> && widget.value == 'locked',
        ),
      );
      expect(disabled.onChanged, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'feedback and overlay use caller pack while review keeps default actions',
    (tester) async {
      late BuildContext source;
      var retries = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
          ],
          child: MaterialApp(
            builder: (_, child) => UiPackScope(child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  source = context;
                  return SingleChildScrollView(
                    child: AppErrorState(
                      message: 'Native error',
                      onRetry: () => retries++,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      final container = ProviderScope.containerOf(source);
      await tester.runAsync(
        () => container
            .read(uiSelectionProvider.notifier)
            .save(UiSelection(globalPackId: 'test.second')),
      );
      await settle(tester);
      expect(find.text('second feedback'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retries, 1);
      AppToast.show(source, message: 'Native notice');
      await tester.pumpAndSettle();
      expect(find.text('second notice'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pumpAndSettle();
      expect(find.text('Native notice'), findsNothing);
      final reviewed = reviewDialog(source, 'Permission review', {
        'permission': 'records.write',
      });
      await tester.pumpAndSettle();
      expect(find.text('second dialog'), findsNothing);
      expect(find.text('Permission review'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '确认'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await reviewed, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('bounded native page rejects card siblings and nested scrolling but permits explicit column', () {
    UiPackDefinition parse(Object tree) => UiPackDefinition.parse(
      moduleId: 'test.bounded',
      version: '1.0.0',
      digest: 'x',
      source: {
        'contractVersion': 1,
        'templates': {
          'ui.page.native@1': {'tree': tree},
        },
      },
    );
    expect(
      () => parse({
        'type': 'primitive',
        'name': 'card',
        'children': [marker('heading'), slot('body')],
      }),
      throwsFormatException,
    );
    expect(
      () => parse({
        'type': 'primitive',
        'name': 'scroll',
        'children': [slot('body')],
      }),
      throwsFormatException,
    );
    expect(
      () => parse({
        'type': 'primitive',
        'name': 'card',
        'children': [
          column([marker('heading'), slot('body')]),
        ],
      }),
      returnsNormally,
    );
  });
}
