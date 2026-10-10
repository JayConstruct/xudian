import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';
import 'package:task_app/core/declarative/runtime/declarative_module_store.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/module_manager/module_manager_page.dart';
import 'package:task_app/features/tasks/application/providers.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 820)]) {
    testWidgets('module actions explain their effects at ${size.width}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final registry = ModuleRegistry(
        [],
        capabilities: CapabilityRegistry(['tasks.command']),
      );
      addTearDown(registry.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
      final store = DeclarativeModuleStore(db);
      const parser = DeclarativeModuleParser();
      Map<String, Object?> source(String version) => {
        'formatVersion': 1,
        'manifest': {
          'id': 'app.copy.sample',
          'version': version,
          'coreApi': '1',
          'requiresCapabilities': ['tasks.command'],
          'permissions': ['tasks.write'],
        },
        'templates': [
          {
            'id': 'routine',
            'title': '日常任务',
            'parameters': [
              {
                'id': 'note',
                'label': '准备事项',
                'type': 'text',
                'default': '准备材料',
              },
            ],
            'tasks': [
              {'key': 'first', 'title': r'$param.note'},
            ],
          },
        ],
      };
      final previous = source('1.0.0');
      final current = source('1.1.0');
      await store.install(parser.parse(previous), previous);
      await store.install(parser.parse(current), current);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) async => db)],
          child: MaterialApp(
            home: Scaffold(body: ModuleManagerPage(registry: registry)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ModuleManagerPage)),
      );
      final templates = await container.read(templateEngineProvider.future);
      templates.installModule(parser.parse(current));

      expect(find.text('导入模块包'), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从模板创建任务'));
      await tester.pumpAndSettle();
      expect(find.text('根据模板创建任务；模板包含项目时，也会创建项目。'), findsOneWidget);
      expect(find.text('创建任务'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('创建任务'));
      await tester.pumpAndSettle();
      expect(find.text('准备事项'), findsOneWidget);
      expect(find.text('创建任务'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('版本历史'));
      await tester.pumpAndSettle();
      expect(find.text('恢复所选版本的模块配置，不会撤销已创建的任务或已执行的自动化操作。'), findsOneWidget);
      expect(find.text('恢复配置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('彻底删除'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '将删除 app.copy.sample 的安装记录、版本历史、自定义字段定义和字段值，'
          '以及规则运行记录。任务和项目会保留。此操作不可撤销。',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect((await store.getInstalled('app.copy.sample'))!.version, '1.1.0');
      expect(await db.select(db.tasks).get(), isEmpty);
    });
  }
}
