import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/events/event_bus.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/tasks/application/task_command_service.dart';
import 'package:task_app/features/tasks/application/task_query_service.dart';
import 'package:task_app/features/tasks/data/change_journal.dart';
import 'package:task_app/features/tasks/data/task_store.dart';
import 'package:task_app/features/tasks/domain/task_input.dart';

void main() {
  late Directory directory;
  late AppDatabase database;
  late TaskStore store;
  late EventBus events;
  late TaskCommandService commands;
  late TaskQueryService queries;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xudian_v2_test_');
    database = AppDatabase(
      NativeDatabase(File('${directory.path}/tasks.sqlite')),
    );
    store = TaskStore(database);
    events = EventBus();
    commands = TaskCommandService(
      db: database,
      store: store,
      journal: ChangeJournal(database),
      events: events,
    );
    queries = TaskQueryService(store);
  });

  tearDown(() async {
    await events.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  test('commands persist data and append ordered journal entries', () async {
    final project = await commands.createProject('工作');
    final task = await commands.createTask(
      CreateTaskInput(
        title: '准备发布',
        projectId: project.id,
        priority: 3,
        dueDate: '2026-10-01',
      ),
    );
    await commands.setCompleted(task.id, true);

    final tasks = await queries.watchTasks().first;
    expect(tasks.single.id, task.id);
    expect(tasks.single.completedAt, isNotNull);
    final operations = await database.select(database.changeOperations).get();
    expect(operations.map((operation) => operation.counter), [1, 2, 3]);
    expect(operations.map((operation) => operation.action), [
      'create',
      'create',
      'complete',
    ]);
  });

  test('commands publish domain events after successful commits', () async {
    final received = <String>[];
    final subscription = events.events.listen((event) => received.add(event.type));

    final project = await commands.createProject('学习');
    await commands.createTask(
      CreateTaskInput(title: '复习', projectId: project.id),
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, ['project.created', 'task.created']);
    await subscription.cancel();
  });

  test('invalid command leaves no task or task journal entry', () async {
    await expectLater(
      commands.createTask(
        const CreateTaskInput(title: '坏日期', dueDate: '2026-02-30'),
      ),
      throwsArgumentError,
    );
    expect(await database.select(database.tasks).get(), isEmpty);
    expect(await database.select(database.changeOperations).get(), isEmpty);
  });
}
