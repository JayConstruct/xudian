import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/contracts/query_bus.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';
import 'package:task_app/core/declarative/runtime/declarative_module_store.dart';
import 'package:task_app/core/declarative/runtime/field_value_store.dart';
import 'package:task_app/core/declarative/runtime/filter_expression.dart';
import 'package:task_app/core/modules/module_context.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/declarative_runtime/builtin_declarative_modules.dart';
import 'package:task_app/features/tasks/application/task_query_service.dart';
import 'package:task_app/features/tasks/data/task_snapshot_query.dart';
import 'package:task_app/features/tasks/data/task_store.dart';
import 'package:task_app/features/tasks/integration/task_query_bindings.dart';

class _Reads extends QueryInterceptor {
  final statements = <String>[];
  int rows = 0;
  void reset() {
    statements.clear();
    rows = 0;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    statements.add(statement);
    final results = await executor.runSelect(statement, args);
    rows += results.length;
    return results;
  }
}

void main() {
  late AppDatabase db;
  late TaskSnapshotQuery query;
  late _Reads reads;
  final date = DateTime(2026, 10, 2);
  setUp(() async {
    reads = _Reads();
    db = AppDatabase(NativeDatabase.memory().interceptWith(reads));
    query = TaskSnapshotQuery(db);
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p',
            name: '项目',
            createdAt: date,
            updatedAt: date,
          ),
        );
    await db.batch((batch) {
      for (var i = 0; i < 24; i++) {
        batch.insert(
          db.tasks,
          TasksCompanion.insert(
            id: 'task-$i',
            title: i.isEven ? '任务😀' : '任务\uE000',
            priority: Value(i % 4),
            projectId: Value(i % 3 == 0 ? 'p' : null),
            dueDate: Value(
              i % 4 == 0
                  ? null
                  : i % 4 == 1
                  ? '2026-10-01'
                  : '2026-10-03',
            ),
            plannedDate: Value(i % 3 == 0 ? '2026-10-02' : null),
            completedAt: Value(i % 5 == 0 ? date : null),
            archivedAt: Value(i % 7 == 0 ? date : null),
            deletedAt: Value(i % 11 == 0 ? date : null),
            createdAt: date,
            updatedAt: date,
          ),
        );
      }
    });
  });
  tearDown(() => db.close());

  test(
    'SQL filters match Dart semantics including nulls, not and empty groups',
    () async {
      final all = await query.get(now: date);
      final filters = <Object?>[
        null,
        {'all': []},
        {'any': []},
        for (final op in [
          'eq',
          'ne',
          'isNull',
          'notNull',
          'lt',
          'lte',
          'gt',
          'gte',
        ])
          for (final value in [null, '2026-10-02', r'$today'])
            for (final negate in [false, true])
              if (negate)
                {
                  'not': {'field': 'dueDate', 'op': op, 'value': value},
                }
              else
                {'field': 'dueDate', 'op': op, 'value': value},
        for (final field in ['priority', 'completed', 'projectId'])
          for (final op in ['eq', 'ne', 'isNull', 'notNull'])
            {
              'field': field,
              'op': op,
              'value': field == 'priority'
                  ? 2
                  : field == 'completed'
                  ? true
                  : 'p',
            },
        {'field': 'title', 'op': 'lt', 'value': '任务\uE000'},
        for (final module in buildBuiltinDeclarativeModules())
          module.module.views.single['filter'],
        {
          'any': [
            {'field': 'priority', 'op': 'eq', 'value': 3},
            {'field': 'fields.flag', 'op': 'isNull'},
          ],
        },
      ];
      for (final filter in filters) {
        final expected = all.where(
          (row) => const FilterExpression().evaluate(row, filter, now: date),
        );
        expect(
          (await query.get(filter: filter, now: date)).map((row) => row['id']),
          expected.map((row) => row['id']),
          reason: '$filter',
        );
      }
    },
  );

  test('task.get and inbox SQL return only matching rows with one query at 10000 tasks', () async {
    await db.batch((batch) {
      for (var i = 0; i < 10000; i++) {
        batch.insert(
          db.tasks,
          TasksCompanion.insert(
            id: 'bulk-$i',
            title: '归档任务',
            archivedAt: Value(date),
            createdAt: date,
            updatedAt: date,
          ),
        );
      }
    });
    final bus = QueryBus();
    registerTaskQueries(bus, TaskQueryService(TaskStore(db)));
    reads.reset();
    final task = await bus.execute(const ModuleContext.system(), 'task.get', {
      'id': 'task-1',
    }) as Map;
    expect(task['id'], 'task-1');
    expect(reads.statements, hasLength(1));
    expect(reads.rows, 1);
    reads.reset();
    final filter =
        buildBuiltinDeclarativeModules()[1].module.views.single['filter'];
    final inbox = await query.get(filter: filter, now: date);
    expect(inbox, isNotEmpty);
    expect(reads.rows, inbox.length);
    expect(reads.statements, hasLength(1));
    expect(
      await bus.execute(const ModuleContext.system(), 'task.get', {
        'id': 'missing',
      }),
      isNull,
    );
  });

  test(
    'subscription refreshes on field set, clear, disable and enable',
    () async {
      final source = <String, Object?>{
        'formatVersion': 1,
        'manifest': {
          'id': 'app.query.module',
          'version': '1.0.0',
          'coreApi': '1',
        },
        'fields': [
          {'id': 'flag', 'label': '标记', 'type': 'boolean'},
        ],
      };
      final modules = DeclarativeModuleStore(db);
      final module = const DeclarativeModuleParser().parse(source);
      await modules.install(module, source);
      final fields = FieldValueStore(db);
      final stream = StreamIterator(
        query.watch(
          filter: {'field': 'fields.flag', 'op': 'eq', 'value': true},
          namespace: 'app.query.module',
        ),
      );
      addTearDown(stream.cancel);
      Future<List<TaskSnapshot>> next() async {
        expect(
          await stream.moveNext().timeout(const Duration(seconds: 3)),
          isTrue,
        );
        return stream.current;
      }

      expect(await next(), isEmpty);
      await fields.setValue(
        taskId: 'task-1',
        fieldKey: 'app.query.module:flag',
        value: true,
      );
      expect((await next()).single['id'], 'task-1');
      await modules.setEnabled('app.query.module', false);
      expect(await next(), isEmpty);
      await modules.install(module, source);
      expect((await next()).single['id'], 'task-1');
      await fields.clearValue(
        taskId: 'task-1',
        fieldKey: 'app.query.module:flag',
      );
      expect(await next(), isEmpty);
    },
  );

  test(
    'project subscription excludes other projects and sorts in SQL',
    () async {
      final tasks = await TaskStore(db).watchProjectTasks('p').first;
      expect(
        tasks.every(
          (row) =>
              row.projectId == 'p' &&
              row.archivedAt == null &&
              row.deletedAt == null,
        ),
        isTrue,
      );
      final priorities = tasks
          .where((row) => row.completedAt == null)
          .map((row) => row.priority)
          .toList();
      expect(
        priorities,
        orderedEquals([...priorities]..sort((a, b) => b.compareTo(a))),
      );
    },
  );

  test('watch enforces read permission before starting a query', () async {
    final bus = QueryBus();
    registerTaskQueries(bus, TaskQueryService(TaskStore(db)));
    reads.reset();
    await expectLater(
      bus.watch(
        ModuleContext(moduleId: 'app.no.access', permissions: []),
        'task.list',
      ),
      emitsError(isStateError),
    );
    expect(reads.statements, isEmpty);
  });
}
