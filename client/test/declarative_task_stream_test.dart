import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/contracts/query_bus.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';
import 'package:task_app/core/modules/module_context.dart';
import 'package:task_app/features/declarative_runtime/declarative_task_page.dart';
import 'package:task_app/features/declarative_runtime/declarative_field_editor.dart';
import 'package:task_app/features/tasks/application/providers.dart';

void main() {
  final module = const DeclarativeModuleParser().parse({
    'formatVersion': 1,
    'manifest': {'id': 'app.stream.test', 'version': '1.0.0', 'coreApi': '1'},
    'pages': [
      {'id': 'home', 'title': '任务', 'view': 'tasks'},
    ],
    'views': [
      {
        'id': 'tasks',
        'source': 'task.list',
        'showFields': ['score'],
      },
    ],
    'fields': [
      {'id': 'score', 'type': 'number', 'label': '分数'},
    ],
  });

  testWidgets(
    'one authorized subscription handles updates and restarts on day boundary and resume',
    (tester) async {
      final started = tester.binding.clock.now();
      DateTime now() => DateTime(
        2026,
        10,
        2,
        23,
        59,
        59,
      ).add(tester.binding.clock.now().difference(started));
      var subscriptions = 0;
      var cancellations = 0;
      var executions = 0;
      final streams = <StreamController<Object?>>[];
      final bus = QueryBus()
        ..register(
          'task.list',
          permission: 'tasks.read',
          handler: (_) async {
            executions++;
            return [];
          },
          watchHandler: (_) {
            subscriptions++;
            final stream = StreamController<Object?>(
              onCancel: () => cancellations++,
            );
            streams.add(stream);
            return stream.stream;
          },
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            queryBusProvider.overrideWith((ref) async => bus),
            queryClockProvider.overrideWithValue(now),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DeclarativeTaskPage(
                module: module,
                moduleContext: ModuleContext(
                  moduleId: module.manifest.id,
                  permissions: ['tasks.read'],
                ),
                page: module.pages.single,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(subscriptions, 1);
      final row = <String, Object?>{
        'id': 'task',
        'title': '任务内容',
        'completed': false,
        'fields': {'app.stream.test:score': 1},
      };
      streams.last.add([row]);
      await tester.pumpAndSettle();
      expect(find.text('score: 1'), findsOneWidget);
      streams.last.add([
        {
          ...row,
          'fields': {'app.stream.test:score': 2},
        },
      ]);
      await tester.pumpAndSettle();
      expect(find.text('score: 2'), findsOneWidget);
      expect(subscriptions, 1);
      expect(executions, 0);
      // Advancing the timer needs no task write or navigation to trigger refresh.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(subscriptions, 2);
      expect(cancellations, 1);
      final observer = tester.state(
        find.byType(DeclarativeTaskPage),
      ) as WidgetsBindingObserver;
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(subscriptions, 3);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(cancellations, 3);
      for (final stream in streams) {
        unawaited(stream.close());
      }
      await tester.pump();
    },
  );

  testWidgets(
    'invalid numeric field stays editable instead of becoming a clear',
    (tester) async {
      Map<String, Object?>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await showDeclarativeFieldEditor(
                      context: context,
                      module: module,
                      current: {'app.stream.test:score': 5},
                    ),
                child: const Text('编辑'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'NaN');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('分数请输入有效数字'), findsOneWidget);
      expect(result, isNull);
      await tester.enterText(find.byType(TextField), '6');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(result, {'score': 6});
    },
  );
}
