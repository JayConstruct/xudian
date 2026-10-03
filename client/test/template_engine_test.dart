import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/contracts/command_bus.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';
import 'package:task_app/core/declarative/runtime/declarative_module_store.dart';
import 'package:task_app/core/declarative/runtime/field_value_store.dart';
import 'package:task_app/core/declarative/runtime/templates/template_engine.dart';
import 'package:task_app/core/events/event_bus.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/tasks/application/task_command_service.dart';
import 'package:task_app/features/tasks/data/change_journal.dart';
import 'package:task_app/features/tasks/data/task_store.dart';
import 'package:task_app/features/tasks/integration/field_command_bindings.dart';
import 'package:task_app/features/tasks/integration/task_command_bindings.dart';

void main() {
  test('template creates project task tree and custom field values', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final events = EventBus();
    final store = TaskStore(db);
    final fieldValues = FieldValueStore(db);
    final commands = CommandBus();
    final service = TaskCommandService(
      db: db,
      store: store,
      journal: ChangeJournal(db),
      events: events,
    );
    registerTaskCommands(commands, service);
    registerFieldCommands(commands, fieldValues, events: events);
    final engine = TemplateEngine(commands: commands, db: db, events: events);

    final source = <String, Object?>{
      'formatVersion': 1,
      'manifest': {
        'id': 'app.template.sample',
        'version': '1.0.0',
        'coreApi': '1',
        'requiresCapabilities': ['tasks.command'],
        'permissions': ['tasks.write', 'fields.write'],
      },
      'fields': [
        {'id': 'subject', 'label': '科目', 'type': 'text'},
        {
          'id': 'tags',
          'label': '标签',
          'type': 'multiSelect',
          'config': {
            'options': ['重点', '计算'],
          },
        },
        {'id': 'reminder', 'label': '提醒', 'type': 'datetime'},
      ],
      'templates': [
        {
          'id': 'examPlan',
          'title': '考试计划',
          'parameters': [
            {
              'id': 'subject',
              'label': '科目',
              'type': 'select',
              'required': true,
              'options': ['高数', '英语'],
            },
            {
              'id': 'examDate',
              'label': '考试日期',
              'type': 'date',
              'required': true,
            },
            {'id': 'level', 'label': '优先级', 'type': 'number', 'default': 2},
            {
              'id': 'tags',
              'label': '标签',
              'type': 'multiSelect',
              'options': ['重点', '计算'],
              'default': ['重点'],
            },
            {
              'id': 'reminder',
              'label': '提醒',
              'type': 'datetime',
              'required': true,
            },
          ],
          'project': {'name': r'期末复习-$param.subject'},
          'tasks': [
            {
              'key': 'root',
              'title': r'制定$param.subject复习计划',
              'priority': r'$param.level',
              'plannedDate': r'$today',
              'fields': {
                'subject': r'$param.subject',
                'tags': r'$param.tags',
                'reminder': r'$param.reminder',
              },
            },
            {
              'key': 'child',
              'title': '完成第一章',
              'parentKey': 'root',
              'priority': 1,
              'dueDate': r'$param.examDate',
            },
          ],
        },
      ],
    };
    final module = const DeclarativeModuleParser().parse(source);
    await DeclarativeModuleStore(db).install(module, source);
    engine.installModule(module);

    await expectLater(
      engine.apply('app.template.sample', 'examPlan'),
      throwsArgumentError,
    );

    final result = await engine.apply(
      'app.template.sample',
      'examPlan',
      parameters: const {
        'subject': '高数',
        'examDate': '2026-12-20',
        'level': 3,
        'tags': ['重点', '计算'],
        'reminder': '2026-12-19T20:30:00',
      },
    );

    expect(result.createdTasks, 2);
    expect(result.projectId, isNotNull);
    final projects = await db.select(db.projects).get();
    expect(projects.single.name, '期末复习-高数');

    final tasks = await db.select(db.tasks).get();
    final root = tasks.singleWhere((task) => task.title == '制定高数复习计划');
    final child = tasks.singleWhere((task) => task.title == '完成第一章');
    expect(child.parentTaskId, root.id);
    expect(child.projectId, root.projectId);
    expect(root.priority, 3);
    expect(root.plannedDate, isNotNull);
    expect(child.dueDate, '2026-12-20');

    final values = await fieldValues.valuesForTask(root.id);
    expect(values['app.template.sample:subject'], '高数');
    expect(values['app.template.sample:tags'], ['重点', '计算']);
    expect(values['app.template.sample:reminder'], '2026-12-19T20:30:00');

    final invalidSource = <String, Object?>{
      'formatVersion': 1,
      'manifest': {
        'id': 'app.template.failure',
        'version': '1.0.0',
        'coreApi': '1',
        'requiresCapabilities': ['tasks.command'],
        'permissions': ['tasks.write'],
      },
      'templates': [
        {
          'id': 'bad',
          'title': '失败模板',
          'project': {'name': '不应保留'},
          'tasks': [
            {'key': 'first', 'title': '第一步'},
            {'key': 'second', 'title': '第二步', 'priority': 9},
          ],
        },
      ],
    };
    final invalidModule = const DeclarativeModuleParser().parse(invalidSource);
    await DeclarativeModuleStore(db).install(invalidModule, invalidSource);
    engine.installModule(invalidModule);
    final projectCount = (await db.select(db.projects).get()).length;
    final taskCount = (await db.select(db.tasks).get()).length;
    final operationCount = (await db.select(db.changeOperations).get()).length;
    await expectLater(
      engine.apply('app.template.failure', 'bad'),
      throwsArgumentError,
    );
    expect((await db.select(db.projects).get()).length, projectCount);
    expect((await db.select(db.tasks).get()).length, taskCount);
    expect((await db.select(db.changeOperations).get()).length, operationCount);

    await events.close();
    await db.close();
  });
}
