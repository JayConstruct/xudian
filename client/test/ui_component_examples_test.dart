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
import 'package:task_app/core/ui/ui_pack.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

Map<String, Object?> recipe({bool system = false}) => {
  if (!system)
    'propsSchema': {
      'type': 'object',
      'properties': {
        'label': {'type': 'string'},
      },
      'required': ['label'],
      'additionalProperties': false,
    },
  if (!system) 'events': ['press'],
  'tree': {
    'type': 'primitive',
    'name': 'button',
    'props': {
      'label': {
        'bind': ['props', 'label'],
      },
      'variant': 'outlined',
    },
    'event': 'press',
  },
  'example': {
    'category': 'actions',
    'name': system ? 'System override' : 'Custom action',
    'props': {
      'label': system ? 'Provider system action' : 'Provider custom action',
    },
    'events': ['press'],
  },
};

void main() {
  test(
    'registered samples validate contracts and forbid executable slot data',
    () {
      UiPackDefinition parse(Map<String, Object?> value) =>
          UiPackDefinition.parse(
            moduleId: 'test.style',
            version: '1.0.0',
            digest: 'sample',
            source: {
              'contractVersion': 1,
              'components': {'test.style.action@1': value},
            },
          );
      final valid = recipe();
      final sample = parse(valid).components.values.single.example!;
      expect(sample['slots'], isEmpty);
      expect(sample['description'], '');
      for (final unsafe in [
        {'category': 'unknown', 'name': 'Bad'},
        {
          'category': 'actions',
          'name': 'Bad',
          'props': {'label': 3},
        },
        {
          'category': 'actions',
          'name': 'Bad',
          'props': {'label': 'ok'},
          'events': ['navigation'],
        },
        {
          'category': 'actions',
          'name': 'Bad',
          'props': {'label': 'ok'},
          'slots': {
            'content': {
              'type': 'input',
              'event': {'type': 'businessWrite'},
            },
          },
        },
        {
          'category': 'actions',
          'name': 'Bad',
          'props': {'label': 'ok'},
          'slots': {
            'content': {'type': 'component', 'ref': 'other.secret@1'},
          },
        },
      ]) {
        expect(
          () => parse({...valid, 'example': unsafe}),
          throwsFormatException,
        );
      }
      for (final helper in [
        {
          'bind': ['context', 'privateState'],
        },
        {
          'nested': [
            {
              'event': {'type': 'businessWrite'},
            },
          ],
        },
      ]) {
        final system = recipe(system: true);
        final example = Map<String, Object?>.from(system['example'] as Map);
        example['props'] = {'label': 'static', 'helperText': helper};
        system['example'] = example;
        expect(
          () => UiPackDefinition.parse(
            moduleId: 'test.style',
            version: '1.0.0',
            digest: 'unsafe',
            source: {
              'contractVersion': 1,
              'components': {'ui.button@1': system},
            },
          ),
          throwsFormatException,
        );
      }
      expect(
        () => (sample['props'] as Map)['label'] = 'mutated',
        throwsUnsupportedError,
      );
    },
  );

  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('ui-registered-samples-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': {
              'id': 'test.gallery',
              'version': '1.0.0',
              'hostApi': '^1.12.0',
              'dataVersion': 1,
              'permissions': ['ui'],
              'dependencies': [],
            },
            'entryPoint': 'main.js',
            'collections': [],
            'services': [],
            'pages': [],
          },
          {
            'main.js': r'''
import {ui} from '@xudian/sdk';
export async function render({state={},event}) {
  const samples = await ui.examples();
  state={pressed:(state.pressed||0)+(event?.type==='pressed'?1:0)};
  return {state,tree:{type:'column',children:[
    {type:'text',text:'Samples '+samples.length},
    {type:'text',text:'Pressed '+state.pressed},
    ...samples.map(sample=>({type:'componentExample',key:sample.ref,
      providerId:sample.providerId,ref:sample.ref,events:{press:{type:'pressed'}}}))
  ]}};
}
export function unsafe() {
  return {tree:{type:'componentExample',providerId:'test.style',ref:'test.style.action@1',
    props:{label:'Unauthorized override'}}};
}
''',
          },
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
  Future<void> installStyle() async {
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build({
          'formatVersion': 3,
          'manifest': {
            'id': 'test.style',
            'kind': 'uiPack',
            'version': '1.0.0',
            'hostApi': '^1.12.0',
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
              'test.style.action@1': recipe(),
              'ui.button@1': recipe(system: true),
            },
          },
        }, {}),
        allowUnsignedLocal: true,
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> show(WidgetTester tester, {String handler = 'render'}) async {
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
              moduleId: 'test.gallery',
              handler: handler,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'live registry discovery previews actual provider and forwards local events',
    (tester) async {
      await show(tester);
      expect(find.text('Samples 0'), findsOneWidget);
      final baseline = await tester.runAsync(
        () => store.sql('SELECT * FROM host_records'),
      );
      await tester.runAsync(installStyle);
      await settle(tester);
      expect(find.text('Samples 2'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Provider custom action'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Provider system action'),
        findsOneWidget,
      );
      await tester.tap(find.text('Provider custom action'));
      await settle(tester);
      expect(find.text('Pressed 1'), findsOneWidget);
      await tester.tap(find.text('Provider system action'));
      await settle(tester);
      expect(find.text('Pressed 2'), findsOneWidget);
      await tester.runAsync(() => host.disable('test.style'));
      await settle(tester);
      expect(find.text('Samples 0'), findsOneWidget);
      expect(find.text('Provider custom action'), findsNothing);
      await tester.runAsync(() => host.enable('test.style'));
      await settle(tester);
      expect(find.text('Samples 2'), findsOneWidget);
      expect(
        await tester.runAsync(() => store.sql('SELECT * FROM host_records')),
        baseline,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('registered preview cannot override verified props or slots', (
    tester,
  ) async {
    await tester.runAsync(installStyle);
    await show(tester, handler: 'unsafe');
    expect(find.textContaining('cannot be overridden'), findsOneWidget);
    expect(find.text('Unauthorized override'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
