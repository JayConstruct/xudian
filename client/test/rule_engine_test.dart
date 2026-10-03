import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/contracts/command_bus.dart';
import 'package:task_app/core/contracts/query_bus.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';
import 'package:task_app/core/declarative/runtime/field_value_store.dart';
import 'package:task_app/core/declarative/runtime/rules/rule_engine.dart';
import 'package:task_app/core/declarative/runtime/rules/rule_execution_store.dart';
import 'package:task_app/core/events/event_bus.dart';
import 'package:task_app/core/modules/module_context.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/tasks/application/task_command_service.dart';
import 'package:task_app/features/tasks/application/task_query_service.dart';
import 'package:task_app/features/tasks/data/change_journal.dart';
import 'package:task_app/features/tasks/data/task_store.dart';
import 'package:task_app/features/tasks/integration/field_command_bindings.dart';
import 'package:task_app/features/tasks/integration/task_command_bindings.dart';
import 'package:task_app/features/tasks/integration/task_query_bindings.dart';

void main() {
  late AppDatabase db;
  late EventBus events;
  late CommandBus commands;
  late QueryBus queries;
  late RuleEngine engine;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    events = EventBus();
    final store = TaskStore(db);
    final fields = FieldValueStore(db);
    final service = TaskCommandService(
      db: db,
      store: store,
      journal: ChangeJournal(db),
      events: events,
    );
    commands = CommandBus();
    registerTaskCommands(commands, service);
    registerFieldCommands(commands, fields, events: events);
    queries = QueryBus();
    registerTaskQueries(queries, TaskQueryService(store));
    engine = RuleEngine(
      events: events,
      commands: commands,
      queries: queries,
      executions: RuleExecutionStore(db),
    );
  });
  tearDown(() async {
    await engine.close();
    await events.close();
    await db.close();
  });

  test(
    'rule condition reads task snapshot and updates through command bus',
    () async {
      final module = const DeclarativeModuleParser().parse({
        'formatVersion': 1,
        'manifest': {
          'id': 'app.rule.sample',
          'version': '1.0.0',
          'coreApi': '1',
          'requiresCapabilities': ['tasks.command', 'tasks.query'],
          'permissions': ['tasks.read', 'tasks.write'],
        },
        'rules': [
          {
            'id': 'raisePriority',
            'event': 'task.created',
            'condition': {'field': 'task.priority', 'op': 'eq', 'value': 0},
            'actions': [
              {
                'command': 'task.updateFields',
                'payload': {
                  'id': r'$event.entityId',
                  'changes': {'priority': 2},
                },
              },
            ],
          },
        ],
      });
      engine.installModule(module);

      await commands.execute(const ModuleContext.system(), 'task.create', {
        'title': '自动提优',
      });
      await Future<void>.delayed(Duration.zero);
      await engine.drain();

      final tasks = await db.select(db.tasks).get();
      expect(tasks.single.priority, 2);
      final journal = await db.select(db.changeOperations).get();
      expect(journal.map((item) => item.action), ['create', 'update']);
      final logs = await db.select(db.ruleExecutions).get();
      expect(logs.map((item) => item.status), ['triggered', 'success']);
    },
  );
  test('rule execution trace prevents self-triggering loops', () async {
    final module = const DeclarativeModuleParser().parse({
      'formatVersion': 1,
      'manifest': {
        'id': 'app.rule.loop',
        'version': '1.0.0',
        'coreApi': '1',
        'requiresCapabilities': ['tasks.command'],
        'permissions': ['tasks.write'],
      },
      'rules': [
        {
          'id': 'normalize',
          'event': 'task.updated',
          'actions': [
            {
              'command': 'task.updateFields',
              'payload': {
                'id': r'$event.entityId',
                'changes': {'priority': 3},
              },
            },
          ],
        },
      ],
    });
    engine.installModule(module);

    final created = await commands.execute(
      const ModuleContext.system(),
      'task.create',
      {'title': '循环测试'},
    ) as Map;
    await commands.execute(const ModuleContext.system(), 'task.updateFields', {
      'id': created['id'],
      'changes': {'priority': 1},
    });
    await Future<void>.delayed(Duration.zero);
    await engine.drain();
    await Future<void>.delayed(Duration.zero);
    await engine.drain();

    final task = (await db.select(db.tasks).get()).single;
    expect(task.priority, 3);
    final journal = await db.select(db.changeOperations).get();
    expect(journal.length, 3);
    final logs = await db.select(db.ruleExecutions).get();
    expect(logs.map((item) => item.status), [
      'triggered',
      'success',
      'skipped',
    ]);
  });

  test('rule logs skipped conditions and action failures', () async {
    final module = const DeclarativeModuleParser().parse({
      'formatVersion': 1,
      'manifest': {
        'id': 'app.rule.logs',
        'version': '1.0.0',
        'coreApi': '1',
        'requiresCapabilities': ['tasks.command', 'tasks.query'],
        'permissions': ['tasks.read', 'tasks.write'],
      },
      'rules': [
        {
          'id': 'never',
          'event': 'task.created',
          'condition': {'field': 'task.priority', 'op': 'eq', 'value': 3},
          'actions': [
            {
              'command': 'task.setCompleted',
              'payload': {'id': r'$event.entityId', 'completed': true},
            },
          ],
        },
        {
          'id': 'fails',
          'event': 'task.created',
          'actions': [
            {
              'command': 'task.setCompleted',
              'payload': {'id': 'missing-task', 'completed': true},
            },
          ],
        },
      ],
    });
    engine.installModule(module);

    await commands.execute(const ModuleContext.system(), 'task.create', {
      'title': '日志测试',
    });
    await Future<void>.delayed(Duration.zero);
    await engine.drain();

    final logs = await db.select(db.ruleExecutions).get();
    expect(
      logs.where((item) => item.ruleId == 'never').single.status,
      'skipped',
    );
    final failureLogs = logs.where((item) => item.ruleId == 'fails').toList();
    expect(failureLogs.map((item) => item.status), ['triggered', 'failure']);
    expect(failureLogs.last.message, contains('任务不存在'));

    final originalFailure = failureLogs.last;
    expect(originalFailure.eventPayloadJson, isNotEmpty);

    final failureOnly = await RuleExecutionStore(db)
        .listForModule('app.rule.logs', status: 'failure');
    expect(failureOnly, hasLength(1));
    expect(failureOnly.single.id, originalFailure.id);

    await engine.retry(originalFailure);

    final retried = await db.select(db.ruleExecutions).get();
    final retryLogs = retried
        .where((item) => item.sourceExecutionId == originalFailure.id)
        .toList();
    expect(retryLogs.map((item) => item.status), ['triggered', 'failure']);
    expect(retryLogs.every((item) => item.ruleId == 'fails'), isTrue);
  });
}
