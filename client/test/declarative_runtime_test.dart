import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/contracts/query_bus.dart';
import 'package:task_app/core/events/event_bus.dart';
import 'package:task_app/core/contracts/command_bus.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';
import 'package:task_app/core/declarative/runtime/declarative_module_store.dart';
import 'package:task_app/core/declarative/runtime/field_value_store.dart';
import 'package:task_app/core/declarative/runtime/filter_expression.dart';
import 'package:task_app/core/modules/module_context.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/features/declarative_runtime/declarative_runtime_controller.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/tasks/application/task_query_service.dart';
import 'package:task_app/features/tasks/data/task_store.dart';
import 'package:task_app/features/tasks/integration/task_query_bindings.dart';
import 'package:task_app/features/tasks/integration/field_command_bindings.dart';

void main() {
  late AppDatabase database;
  late DeclarativeModuleStore modules;
  late FieldValueStore fields;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    modules = DeclarativeModuleStore(database);
    fields = FieldValueStore(database);
  });

  tearDown(() => database.close());

  test('module install persists field definitions and enable state', () async {
    const source = <String, Object?>{
      'formatVersion': 1,
      'manifest': {
        'id': 'app.study.module',
        'version': '1.0.0',
        'coreApi': '1',
        'permissions': ['tasks.read'],
      },
      'fields': [
        {'id': 'difficulty', 'label': '难度', 'type': 'number'},
      ],
    };
    final module = const DeclarativeModuleParser().parse(source);

    await modules.install(module, source);

    final installed = await modules.listInstalled();
    expect(installed.single.id, 'app.study.module');
    expect(installed.single.enabled, isTrue);

    final definitions = await database.select(database.fieldDefinitions).get();
    expect(definitions.single.key, 'app.study.module:difficulty');
    expect(definitions.single.label, '难度');

    await modules.setEnabled('app.study.module', false);
    final disabled = await modules.listInstalled();
    expect(disabled.single.enabled, isFalse);
  });

  test('field values are typed and returned through task query DTO', () async {
    const source = <String, Object?>{
      'formatVersion': 1,
      'manifest': {
        'id': 'app.study.module',
        'version': '1.0.0',
        'coreApi': '1',
        'permissions': ['tasks.read'],
      },
      'fields': [
        {'id': 'difficulty', 'label': '难度', 'type': 'number'},
      ],
    };
    final module = const DeclarativeModuleParser().parse(source);
    await modules.install(module, source);

    final now = DateTime(2026, 9, 29);
    await database
        .into(database.tasks)
        .insert(
          Task(
            id: 'task-1',
            projectId: null,
            parentTaskId: null,
            title: '高数复习',
            notes: '',
            priority: 2,
            dueDate: '2026-10-01',
            plannedDate: null,
            completedAt: null,
            archivedAt: null,
            deletedAt: null,
            createdAt: now,
            updatedAt: now,
          ),
        );

    await fields.setValue(
      taskId: 'task-1',
      fieldKey: 'app.study.module:difficulty',
      value: 4,
    );
    await expectLater(
      fields.setValue(
        taskId: 'task-1',
        fieldKey: 'app.study.module:difficulty',
        value: '高',
      ),
      throwsArgumentError,
    );

    final commands = CommandBus();
    final events = EventBus();
    addTearDown(events.close);
    registerFieldCommands(commands, fields, events: events);
    final otherModule = ModuleContext(
      moduleId: 'app.other.module',
      permissions: const ['fields.write'],
    );
    await expectLater(
      commands.execute(otherModule, 'field.set', {
        'taskId': 'task-1',
        'fieldKey': 'app.study.module:difficulty',
        'value': 2,
      }),
      throwsStateError,
    );
    await expectLater(
      commands.execute(otherModule, 'field.clear', {
        'taskId': 'task-1',
        'fieldKey': 'app.study.module:difficulty',
      }),
      throwsStateError,
    );
    expect(
      (await fields.valuesForTask('task-1'))['app.study.module:difficulty'],
      4,
    );

    final bus = QueryBus();
    registerTaskQueries(bus, TaskQueryService(TaskStore(database)));
    final result = await bus.execute(
      ModuleContext(
        moduleId: 'app.study.module',
        permissions: const ['tasks.read'],
      ),
      'task.list',
    ) as List;
    final row = result.single as Map<String, Object?>;
    final values = row['fields'] as Map<String, Object?>;
    expect(values['app.study.module:difficulty'], 4);
  });

  test('runtime install and enable changes registry immediately', () async {
    final registry = ModuleRegistry(
      const [],
      capabilities: CapabilityRegistry(['tasks.query', 'ui.registry']),
    );
    final runtime = DeclarativeRuntimeController(
      store: modules,
      registry: registry,
    );
    final source = <String, Object?>{
      'formatVersion': 1,
      'manifest': {
        'id': 'app.dynamic.sample',
        'version': '1.0.0',
        'coreApi': '1',
        'requiresCapabilities': ['tasks.query', 'ui.registry'],
        'permissions': ['tasks.read', 'ui.register'],
      },
      'pages': [
        {'id': 'home', 'title': '动态页', 'view': 'tasks'},
      ],
      'views': [
        {'id': 'tasks', 'source': 'task.list'},
      ],
    };

    await runtime.install(source);
    expect(registry.ui.primaryDestinations.single.label, '动态页');

    await runtime.setEnabled('app.dynamic.sample', false);
    expect(registry.ui.primaryDestinations, isEmpty);

    await runtime.setEnabled('app.dynamic.sample', true);
    expect(registry.ui.primaryDestinations.single.label, '动态页');
  });

  test('same module version cannot change content', () async {
    final first = <String, Object?>{
      'formatVersion': 1,
      'manifest': {
        'id': 'app.immutable.sample',
        'version': '1.0.0',
        'coreApi': '1',
      },
    };
    final second = <String, Object?>{
      'formatVersion': 1,
      'manifest': {
        'id': 'app.immutable.sample',
        'version': '1.0.0',
        'coreApi': '1',
      },
      'views': [
        {'id': 'newView'},
      ],
    };
    final parser = const DeclarativeModuleParser();
    await modules.install(parser.parse(first), first);
    await expectLater(
      modules.install(parser.parse(second), second),
      throwsStateError,
    );
  });

  test(
    'module rollback restores version UI and previous field values',
    () async {
      final registry = ModuleRegistry(
        const [],
        capabilities: CapabilityRegistry(['tasks.query', 'ui.registry']),
      );
      final runtime = DeclarativeRuntimeController(
        store: modules,
        registry: registry,
      );
      final v1 = <String, Object?>{
        'formatVersion': 1,
        'manifest': {
          'id': 'app.rollback.sample',
          'version': '1.0.0',
          'coreApi': '1',
          'requiresCapabilities': ['tasks.query', 'ui.registry'],
          'permissions': ['tasks.read', 'ui.register'],
        },
        'fields': [
          {'id': 'difficulty', 'label': '难度', 'type': 'number'},
        ],
        'pages': [
          {'id': 'home', 'title': '版本一', 'view': 'tasks'},
        ],
        'views': [
          {'id': 'tasks', 'source': 'task.list'},
        ],
      };
      final v2 = <String, Object?>{
        'formatVersion': 1,
        'manifest': {
          'id': 'app.rollback.sample',
          'version': '2.0.0',
          'coreApi': '1',
          'requiresCapabilities': ['tasks.query', 'ui.registry'],
          'permissions': ['tasks.read', 'ui.register'],
        },
        'fields': [
          {'id': 'subject', 'label': '科目', 'type': 'text'},
        ],
        'pages': [
          {'id': 'home', 'title': '版本二', 'view': 'tasks'},
        ],
        'views': [
          {'id': 'tasks', 'source': 'task.list'},
        ],
      };

      await runtime.install(v1);
      final now = DateTime(2026, 9, 29);
      await database
          .into(database.tasks)
          .insert(
            Task(
              id: 'rollback-task',
              projectId: null,
              parentTaskId: null,
              title: '版本测试',
              notes: '',
              priority: 0,
              dueDate: null,
              plannedDate: null,
              completedAt: null,
              archivedAt: null,
              deletedAt: null,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await fields.setValue(
        taskId: 'rollback-task',
        fieldKey: 'app.rollback.sample:difficulty',
        value: 4,
      );

      await runtime.install(v2);
      expect(registry.ui.primaryDestinations.single.label, '版本二');
      expect((await modules.listVersions('app.rollback.sample')).length, 2);
      expect(await fields.valuesForTask('rollback-task'), isEmpty);

      await runtime.rollback('app.rollback.sample', '1.0.0');
      expect(registry.ui.primaryDestinations.single.label, '版本一');
      final installed = await modules.listInstalled();
      expect(installed.single.version, '1.0.0');
      final restored = await fields.valuesForTask('rollback-task');
      expect(restored['app.rollback.sample:difficulty'], 4);

      final definitions = await database
          .select(database.fieldDefinitions)
          .get();
      final difficulty = definitions.singleWhere(
        (item) => item.key == 'app.rollback.sample:difficulty',
      );
      final subject = definitions.singleWhere(
        (item) => item.key == 'app.rollback.sample:subject',
      );
      expect(difficulty.active, isTrue);
      expect(subject.active, isFalse);
    },
  );

  test('disabling module hides fields and enabling restores them', () async {
    final registry = ModuleRegistry(
      const [],
      capabilities: CapabilityRegistry(const []),
    );
    final runtime = DeclarativeRuntimeController(
      store: modules,
      registry: registry,
    );
    final source = <String, Object?>{
      'formatVersion': 1,
      'manifest': {
        'id': 'app.toggle.sample',
        'version': '1.0.0',
        'coreApi': '1',
      },
      'fields': [
        {'id': 'score', 'label': '分数', 'type': 'number'},
      ],
    };
    await runtime.install(source);

    final now = DateTime(2026, 9, 29);
    await database
        .into(database.tasks)
        .insert(
          Task(
            id: 'toggle-task',
            projectId: null,
            parentTaskId: null,
            title: '启停测试',
            notes: '',
            priority: 0,
            dueDate: null,
            plannedDate: null,
            completedAt: null,
            archivedAt: null,
            deletedAt: null,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await fields.setValue(
      taskId: 'toggle-task',
      fieldKey: 'app.toggle.sample:score',
      value: 88,
    );

    await runtime.setEnabled('app.toggle.sample', false);
    expect(await fields.valuesForTask('toggle-task'), isEmpty);

    await runtime.setEnabled('app.toggle.sample', true);
    expect(
      (await fields.valuesForTask('toggle-task'))['app.toggle.sample:score'],
      88,
    );
  });

  test('uninstall preserves data and reinstall restores it', () async {
    final registry = ModuleRegistry(
      const [],
      capabilities: CapabilityRegistry(const []),
    );
    final runtime = DeclarativeRuntimeController(
      store: modules,
      registry: registry,
    );
    final source = <String, Object?>{
      'formatVersion': 1,
      'manifest': {
        'id': 'app.uninstall.sample',
        'version': '1.0.0',
        'coreApi': '1',
      },
      'fields': [
        {'id': 'score', 'label': '分数', 'type': 'number'},
      ],
    };

    await runtime.install(source);
    final now = DateTime(2026, 9, 29);
    await database
        .into(database.tasks)
        .insert(
          Task(
            id: 'uninstall-task',
            projectId: null,
            parentTaskId: null,
            title: '保留数据',
            notes: '',
            priority: 0,
            dueDate: null,
            plannedDate: null,
            completedAt: null,
            archivedAt: null,
            deletedAt: null,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await fields.setValue(
      taskId: 'uninstall-task',
      fieldKey: 'app.uninstall.sample:score',
      value: 95,
    );

    await runtime.uninstall('app.uninstall.sample');
    final retained = await modules.getInstalled('app.uninstall.sample');
    expect(retained?.installed, isFalse);
    expect(await fields.valuesForTask('uninstall-task'), isEmpty);
    expect(await database.select(database.fieldValues).get(), isNotEmpty);

    final saved = await modules.versionSource('app.uninstall.sample', '1.0.0');
    await runtime.install(saved);
    expect(
      (await fields.valuesForTask(
        'uninstall-task',
      ))['app.uninstall.sample:score'],
      95,
    );

    await runtime.uninstall('app.uninstall.sample', deleteData: true);
    expect(await modules.getInstalled('app.uninstall.sample'), isNull);
    expect(await modules.listVersions('app.uninstall.sample'), isEmpty);
  });

  test('filter expression handles normal and namespaced custom fields', () {
    const row = <String, Object?>{
      'priority': 3,
      'completed': false,
      'fields': <String, Object?>{'app.study.module:difficulty': 4},
    };
    const filter = <String, Object?>{
      'all': [
        {'field': 'priority', 'op': 'gte', 'value': 2},
        {
          'field': 'fields.app.study.module:difficulty',
          'op': 'gte',
          'value': 3,
        },
      ],
    };

    expect(const FilterExpression().evaluate(row, filter), isTrue);

    const localFilter = {'field': 'fields.difficulty', 'op': 'gte', 'value': 3};
    expect(
      const FilterExpression().evaluate(
        row,
        localFilter,
        fieldNamespace: 'app.study.module',
      ),
      isTrue,
    );
  });
}
