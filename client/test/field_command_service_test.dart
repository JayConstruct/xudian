import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/contracts/command_bus.dart';
import 'package:task_app/core/contracts/query_bus.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';
import 'package:task_app/core/declarative/runtime/declarative_module_store.dart';
import 'package:task_app/core/declarative/runtime/field_value_store.dart';
import 'package:task_app/core/declarative/runtime/rules/rule_engine.dart';
import 'package:task_app/core/declarative/runtime/rules/rule_execution_store.dart';
import 'package:task_app/core/declarative/runtime/templates/template_engine.dart';
import 'package:task_app/core/events/domain_event.dart';
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
  late FieldValueStore fields;
  late CommandBus commands;
  late List<DomainEvent> received;
  final context = ModuleContext(
    moduleId: 'app.fields.test',
    permissions: ['fields.write'],
  );
  const parser = DeclarativeModuleParser();
  final source = <String, Object?>{
    'formatVersion': 1,
    'manifest': {
      'id': 'app.fields.test',
      'version': '1.0.0',
      'coreApi': '1',
      'requiresCapabilities': ['tasks.command', 'tasks.query'],
      'permissions': ['fields.write', 'tasks.write', 'tasks.read'],
    },
    'fields': [
      {'id': 'text', 'label': '文本', 'type': 'text'},
      {'id': 'number', 'label': '数字', 'type': 'number'},
      {'id': 'date', 'label': '日期', 'type': 'date'},
      {'id': 'datetime', 'label': '时间', 'type': 'datetime'},
      {
        'id': 'select',
        'label': '单选',
        'type': 'select',
        'config': {
          'options': ['a', 'b'],
        },
      },
      {
        'id': 'multi',
        'label': '多选',
        'type': 'multiSelect',
        'config': {
          'options': ['a', 'b'],
        },
      },
    ],
  };
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    events = EventBus();
    received = [];
    final subscription = events.events.listen(received.add);
    addTearDown(subscription.cancel);
    fields = FieldValueStore(db);
    commands = CommandBus();
    registerFieldCommands(commands, fields, events: events);
    registerTaskCommands(
      commands,
      TaskCommandService(
        db: db,
        store: TaskStore(db),
        journal: ChangeJournal(db),
        events: events,
      ),
    );
    await DeclarativeModuleStore(db).install(parser.parse(source), source);
    final now = DateTime.now();
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'task',
            title: '任务',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });
  tearDown(() async {
    await events.close();
    await db.close();
  });
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Future<Object?> set(String field, Object value) => commands.execute(
    context,
    'field.set',
    {'taskId': 'task', 'fieldKey': 'app.fields.test:$field', 'value': value},
  );

  test(
    'invalid values and unauthorized batches leave no data, journal or events',
    () async {
      for (final entry in <String, List<Object>>{
        'number': [double.nan, double.infinity],
        'date': ['2026-02-30', '2026-2-03'],
        'datetime': [
          '2026-02-30T10:00:00',
          '2026-10-02',
          '2026-10-02T25:00:00',
        ],
        'select': ['unknown'],
        'multi': [
          ['a', 'a'],
          ['a', 'unknown'],
        ],
      }.entries) {
        for (final value in entry.value) {
          await expectLater(set(entry.key, value), throwsArgumentError);
        }
      }
      await expectLater(
        commands.execute(context, 'field.setMany', {
          'taskId': 'task',
          'values': {
            'app.fields.test:text': '不应提交',
            'app.foreign.module:text': '越权',
          },
        }),
        throwsStateError,
      );
      await flush();
      expect(await fields.valuesForTask('task'), isEmpty);
      expect(await db.select(db.changeOperations).get(), isEmpty);
      expect(received, isEmpty);
    },
  );

  test(
    'batch writes log atomically, emit one event, and skip unchanged values',
    () async {
      final values = {
        'app.fields.test:text': '值',
        'app.fields.test:date': '2028-02-29',
        'app.fields.test:datetime': '2026-10-02T12:30:00.000Z',
        'app.fields.test:multi': ['a', 'b'],
      };
      await commands.execute(context, 'field.setMany', {
        'taskId': 'task',
        'values': values,
      });
      await flush();
      expect(await fields.valuesForTask('task'), values);
      final logs = await db.select(db.changeOperations).get();
      expect(logs.map((row) => row.counter), [1, 2, 3, 4]);
      expect(
        logs.every((row) => row.action == 'field.set' && !row.synced),
        isTrue,
      );
      expect(jsonDecode(logs.first.payload), {
        'fieldKey': 'app.fields.test:text',
        'value': '值',
      });
      expect(received.single.type, 'task.updated');
      expect((received.single.payload['fields'] as List), hasLength(4));
      await commands.execute(context, 'field.setMany', {
        'taskId': 'task',
        'values': values,
      });
      await flush();
      expect(received, hasLength(1));
      expect(await db.select(db.changeOperations).get(), hasLength(4));
      await commands.execute(context, 'field.clear', {
        'taskId': 'task',
        'fieldKey': 'app.fields.test:text',
      });
      await flush();
      expect(
        (await db.select(db.changeOperations).get()).last.action,
        'field.clear',
      );
      expect(received, hasLength(2));
    },
  );

  test(
    'validation and journal failures roll back the complete batch',
    () async {
      await expectLater(
        commands.execute(context, 'field.setMany', {
          'taskId': 'task',
          'values': {
            'app.fields.test:text': '不应提交',
            'app.fields.test:select': 'unknown',
          },
        }),
        throwsArgumentError,
      );
      expect(await fields.valuesForTask('task'), isEmpty);
      expect(await db.select(db.changeOperations).get(), isEmpty);
      await db.customStatement(
        "CREATE TRIGGER reject_log BEFORE INSERT ON change_operations BEGIN SELECT RAISE(ABORT, 'disk failed'); END",
      );
      await expectLater(set('text', '不应提交'), throwsA(anything));
      await flush();
      expect(await fields.valuesForTask('task'), isEmpty);
      expect(await db.select(db.changeOperations).get(), isEmpty);
      expect(received, isEmpty);
    },
  );

  test(
    'template rollback suppresses field events and journal entries',
    () async {
      final templateSource = {
        ...source,
        'templates': [
          {
            'id': 'bad',
            'title': '失败',
            'tasks': [
              {
                'key': 'first',
                'title': '第一步',
                'fields': {'text': '已暂存'},
              },
              {'key': 'last', 'title': '第二步', 'priority': 9},
            ],
          },
        ],
      };
      final engine = TemplateEngine(commands: commands, db: db, events: events);
      engine.installModule(parser.parse(templateSource));
      await expectLater(
        engine.apply('app.fields.test', 'bad'),
        throwsArgumentError,
      );
      await flush();
      expect(await db.select(db.tasks).get(), hasLength(1));
      expect(await db.select(db.fieldValues).get(), isEmpty);
      expect(await db.select(db.changeOperations).get(), isEmpty);
      expect(received, isEmpty);
    },
  );

  test('field events trigger rules with loop protection', () async {
    final queries = QueryBus();
    registerTaskQueries(queries, TaskQueryService(TaskStore(db)));
    final engine = RuleEngine(
      events: events,
      commands: commands,
      queries: queries,
      executions: RuleExecutionStore(db),
    );
    addTearDown(engine.close);
    engine.installModule(
      parser.parse({
        ...source,
        'rules': [
          {
            'id': 'normalize',
            'event': 'task.updated',
            'condition': {'field': 'task.id', 'op': 'eq', 'value': 'task'},
            'actions': [
              {
                'command': 'field.set',
                'payload': {
                  'taskId': r'$event.entityId',
                  'fieldKey': 'app.fields.test:number',
                  'value': 2,
                },
              },
            ],
          },
        ],
      }),
    );
    await set('number', 1);
    await flush();
    await engine.drain();
    await flush();
    await engine.drain();
    expect((await fields.valuesForTask('task'))['app.fields.test:number'], 2);
    final logs = await db.select(db.ruleExecutions).get();
    expect(logs.map((row) => row.status), ['triggered', 'success', 'skipped']);
    expect(await db.select(db.changeOperations).get(), hasLength(2));
  });
}
