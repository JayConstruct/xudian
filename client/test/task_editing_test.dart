import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/legacy_app.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';
import 'package:task_app/core/declarative/runtime/declarative_module_store.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/tasks/application/providers.dart';
import 'package:task_app/features/tasks/task_editor.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> openApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
        child: XudianApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('保存修改'));
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(390, 844), const Size(1280, 820)]) {
    testWidgets(
      'project tasks can be created and edited at width ${size.width}',
      (tester) async {
        await openApp(tester, size);
        await tester.tap(find.text('项目').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('新建项目'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '学习计划');
        await tester.tap(find.text('创建'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('学习计划'));
        await tester.pumpAndSettle();
        expect(
          tester
              .getRect(find.byKey(const ValueKey('assistant-bubble')))
              .overlaps(tester.getRect(find.byTooltip('添加任务'))),
          isFalse,
        );
        await tester.enterText(find.byType(TextField), '阅读第一章');
        await tester.pump();
        expect(
          tester
              .getRect(find.byKey(const ValueKey('assistant-bubble')))
              .overlaps(tester.getRect(find.byTooltip('添加任务'))),
          isFalse,
        );
        await tester.tap(find.byTooltip('添加任务'));
        await tester.pumpAndSettle();
        final created = (await db.select(db.tasks).get()).single;
        final project = (await db.select(db.projects).get()).single;
        expect(created.projectId, project.id);
        expect(find.text('阅读第一章'), findsOneWidget);
        await tester.tap(find.text('阅读第一章'));
        await tester.pumpAndSettle();
        expect(find.byType(TaskEditor), findsOneWidget);
        await tester.enterText(find.byType(TextFormField).at(0), '阅读第二章');
        await tester.enterText(find.byType(TextFormField).at(1), '2026-10-03');
        await tester.enterText(find.byType(TextFormField).at(2), '2026-10-08');
        await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('高').last);
        await tester.pumpAndSettle();
        await save(tester);
        final edited = (await db.select(db.tasks).get()).single;
        expect(edited.title, '阅读第二章');
        expect(edited.priority, 3);
        expect(edited.plannedDate, '2026-10-03');
        expect(edited.dueDate, '2026-10-08');
        expect(edited.projectId, project.id);
        expect(find.text('阅读第二章'), findsOneWidget);
        final journal = await db.select(db.changeOperations).get();
        expect(journal.where((row) => row.action == 'update'), hasLength(1));
        await tester.tap(find.text('阅读第二章'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('清除计划日'));
        await tester.tap(find.byTooltip('清除截止日'));
        await save(tester);
        final cleared = (await db.select(db.tasks).get()).single;
        expect(cleared.plannedDate, isNull);
        expect(cleared.dueDate, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'declarative task editor validates dates and leaves cancelled or unchanged edits unwritten',
    (tester) async {
      final now = DateTime.now();
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'task-a',
              title: '收件箱任务',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await openApp(tester, const Size(320, 640));
      await tester.tap(find.text('收件箱').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('收件箱任务'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(2), '2026-02-30');
      await save(tester);
      expect(find.textContaining('请输入有效日期'), findsOneWidget);
      expect(await db.select(db.changeOperations).get(), isEmpty);
      await tester.ensureVisible(find.byTooltip('关闭详情'));
      await tester.tap(find.byTooltip('关闭详情'));
      await tester.pumpAndSettle();
      expect((await db.select(db.tasks).get()).single.dueDate, isNull);
      await tester.tap(find.text('收件箱任务'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(await db.select(db.changeOperations).get(), isEmpty);
      await tester.tap(find.text('收件箱任务'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '已更新任务');
      await save(tester);
      expect(find.text('已更新任务'), findsOneWidget);
      expect((await db.select(db.tasks).get()).single.title, '已更新任务');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'failed module recovery explains the failure while tasks remain usable',
    (tester) async {
      final source = <String, Object?>{
        'formatVersion': 1,
        'manifest': {
          'id': 'app.missing.module',
          'version': '1.0.0',
          'coreApi': '1',
          'dependencies': ['app.absent.module'],
        },
      };
      await DeclarativeModuleStore(db)
          .install(const DeclarativeModuleParser().parse(source), source);
      await openApp(tester, const Size(390, 844));
      expect(find.textContaining('1 个扩展模块恢复失败'), findsOneWidget);
      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();
      expect(find.textContaining('app.absent.module'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '正常创建任务');
      await tester.pump();
      await tester.tap(find.byTooltip('添加任务'));
      await tester.pumpAndSettle();
      expect((await db.select(db.tasks).get()).single.title, '正常创建任务');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
