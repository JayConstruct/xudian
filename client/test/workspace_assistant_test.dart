import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_app_module.dart';
import 'package:task_app/core/module_host/script_launcher.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/core/ui/ui_registry.dart';
import 'package:task_app/core/ui/ui_slot.dart';
import 'package:task_app/data/app_database.dart';

Future<ScriptPackage> package(
  String id, {
  bool tool = false,
  String? slot,
}) async => ScriptPackage.verify(
  await ScriptPackage.build(
    {
      'formatVersion': 3,
      'manifest': {
        'id': id,
        'name': id,
        'version': '1.0.0',
        'hostApi': '^1.18.0',
        'dataVersion': 1,
        'permissions': ['ui'],
        'dependencies': [],
      },
      'entryPoint': 'main.js',
      'collections': [],
      'pages': [],
      'services': [
        {
          'id': 'read',
          'major': 1,
          'handler': 'read',
          'kind': 'query',
          'input': {'type': 'object'},
          'output': {'type': 'object'},
          if (tool) 'tool': {'description': '读取页面内容'},
        },
      ],
      if (slot != null)
        'contributions': [
          {
            'id': '$id.launcher',
            'slot': slot,
            'handler': 'render',
            'label': '助手',
          },
        ],
    },
    {
      'main.js': "export function read(){return {ok:true};} export function render(){return {state:{},tree:{type:'text',text:'助手内容'}};}",
    },
  ),
  allowUnsignedLocal: true,
);

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  Future<void> initialize() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('workspace-assistant-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    addTearDown(() async {
      await host.close();
      await store.close();
      await db.close();
      await directory.delete(recursive: true);
    });
  }

  test(
    'AI contributes a typed workspace entry without a global overlay',
    () async {
      await initialize();
      final source = Directory('../packages/modules/app.ai');
      final definition = jsonDecode(
        await File('${source.path}/module.json').readAsString(),
      ) as Map<String, dynamic>;
      final ai = await ScriptPackage.verify(
        await ScriptPackage.build(definition.cast<String, Object?>(), {
          'main.js': await File('${source.path}/main.js').readAsString(),
          'connection.js': await File('${source.path}/connection.js')
              .readAsString(),
        }),
        allowUnsignedLocal: true,
      );
      expect(ai.version, '1.5.1');
      expect(ai.manifest['hostApi'], '^1.31.0');
      await host.install(ai);
      final registrations = ScriptAppModule(host, ai).ui;
      final page = registrations.whereType<UiPageRegistration>().singleWhere(
        (page) => page.id == 'app.ai.page',
      );
      final pageEntry = registrations
          .whereType<UiEntryRegistration>()
          .singleWhere((entry) => entry.id == 'app.ai.entry');
      expect(page.id, 'app.ai.page');
      expect(pageEntry.id, 'app.ai.entry');
      expect(pageEntry.pageId, page.id);
      expect(pageEntry.defaultMount.placement, UiPlacement.hidden);
      expect(pageEntry.opening, UiOpening.adaptivePanel);
      final settings = registrations
          .whereType<UiEntryRegistration>()
          .singleWhere((entry) => entry.id == 'app.ai.settings.entry');
      expect(settings.pageId, 'app.ai.settings');
      expect(settings.defaultMount.placement, UiPlacement.settings);
      expect(settings.opening, UiOpening.detail);
      final assistant = registrations
          .whereType<WorkspaceAssistantRegistration>()
          .single;
      expect(assistant.slot, UiSlot.workspaceAssistant);
      expect(assistant.id, 'app.ai.launcher');
      expect(assistant.label, 'AI 助手');
      expect(
        registrations.where((entry) => entry.slot == UiSlot.globalOverlay),
        isEmpty,
      );
      expect(assistant.supports({'app.ai'}), isFalse);
      await host.install(await package('private.tools', tool: true));
      await host.install(await package('private.plain'));
      expect(assistant.supports({}), isFalse);
      expect(assistant.supports({'private.plain'}), isFalse);
      expect(assistant.supports({'private.unrelated'}), isFalse);
      // No connection is configured: tool availability still permits settings.
      expect(assistant.supports({'private.plain', 'private.tools'}), isTrue);
      await host.disable('private.tools');
      expect(assistant.supports({'private.tools'}), isFalse);
    },
  );

  test('legacy global overlays retain their widget launcher', () async {
    await initialize();
    final overlay = await package('private.overlay', slot: 'globalOverlay');
    final registration =
        ScriptAppModule(host, overlay).ui.single as WidgetRegistration;
    expect(registration.slot, UiSlot.globalOverlay);
    expect(registration.id, 'private.overlay.launcher');
  });

  test('workspace assistants reject duplicate registration ids', () {
    final registry = UiRegistry();
    WorkspaceAssistantRegistration registration() =>
        WorkspaceAssistantRegistration(
          id: 'assistant',
          label: '助手',
          onOpen: (_, _) async {},
          supports: (_) => true,
        );
    registry.register(registration());
    expect(() => registry.register(registration()), throwsStateError);
  });

  testWidgets(
    'typed opening forwards the workspace context into the shared sheet',
    (tester) async {
      late ScriptPackage assistantPackage;
      await tester.runAsync(() async {
        await initialize();
        assistantPackage = await package(
          'private.assistant',
          slot: 'workspaceAssistant',
        );
        await host.install(assistantPackage);
      });
      final assistant =
          ScriptAppModule(host, assistantPackage).ui.single
              as WorkspaceAssistantRegistration;
      const pageContext = PageContext(
        taskId: 'task-1',
        projectId: 'project-1',
        values: {
          'pageId': 'private.content.page',
          'selectedDate': '2026-10-12',
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => assistant.onOpen(context, pageContext),
                child: const Text('打开助手'),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(ScriptLauncher), findsNothing);
      await tester.tap(find.text('打开助手'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final page = tester.widget<ScriptPage>(find.byType(ScriptPage));
      expect(page.pageContext, {
        ...pageContext.values,
        'taskId': 'task-1',
        'projectId': 'project-1',
      });
      expect(page.moduleId, 'private.assistant');
      expect(page.handler, 'render');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
