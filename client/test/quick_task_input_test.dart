import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/contracts/command_bus.dart';
import 'package:task_app/features/tasks/application/providers.dart';
import 'package:task_app/features/tasks/quick_task_input.dart';

void main() {
  testWidgets('repeated submission writes once and preserves the next draft', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    final calls = <CommandPayload>[];
    final bus = CommandBus()
      ..register(
        'task.create',
        permission: 'tasks.write',
        handler: (payload) {
          calls.add(payload);
          return pending.future;
        },
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [commandBusProvider.overrideWith((ref) async => bus)],
        child: const MaterialApp(
          home: Scaffold(
            body: QuickTaskInput(
              hintText: '添加任务',
              defaults: {'projectId': 'project-a'},
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '第一条');
    await tester.pump();
    await tester.tap(find.byTooltip('添加任务'));
    // Enter can arrive before the disabled button has rebuilt.
    tester.widget<TextField>(find.byType(TextField)).onSubmitted!('第一条');
    await tester.pump();
    expect(calls, hasLength(1));
    expect(calls.single, {'title': '第一条', 'projectId': 'project-a'});
    await tester.enterText(find.byType(TextField), '下一条草稿');
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '下一条草稿',
    );
    expect(calls, hasLength(1));
  });

  testWidgets(
    'failed submission keeps draft and allows retry without overflow',
    (tester) async {
      var attempts = 0;
      final bus = CommandBus()
        ..register(
          'task.create',
          permission: 'tasks.write',
          handler: (_) async {
            if (++attempts == 1) throw StateError('存储暂时不可用');
            return null;
          },
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [commandBusProvider.overrideWith((ref) async => bus)],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 52,
                width: 320,
                child: QuickTaskInput(hintText: '添加任务'),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '保留草稿');
      await tester.pump();
      await tester.tap(find.byTooltip('添加任务'));
      await tester.pumpAndSettle();
      expect(find.textContaining('添加失败'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '保留草稿',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('添加任务'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );
}
