import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get parentTaskId => text().nullable()();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get dueDate => text().nullable()();
  TextColumn get plannedDate => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Labels extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  IntColumn get color => integer().withDefault(const Constant(0xFF6750A4))();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskLabels extends Table {
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get labelId => text().references(Labels, #id)();

  @override
  Set<Column> get primaryKey => {taskId, labelId};
}

class ModuleInstallations extends Table {
  TextColumn get id => text()();
  TextColumn get version => text()();
  TextColumn get sourceJson => text()();
  BoolColumn get installed => boolean().withDefault(const Constant(true))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get origin => text().withDefault(const Constant('local'))();
  TextColumn get publisherId => text().nullable()();
  TextColumn get packageDigest => text().nullable()();
  TextColumn get reviewId => text().nullable()();
  TextColumn get signatureKeyId => text().nullable()();
  DateTimeColumn get installedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class ModuleVersions extends Table {
  TextColumn get moduleId => text()();
  TextColumn get version => text()();
  TextColumn get sourceJson => text()();
  TextColumn get origin => text().withDefault(const Constant('local'))();
  TextColumn get publisherId => text().nullable()();
  TextColumn get packageDigest => text().nullable()();
  TextColumn get reviewId => text().nullable()();
  TextColumn get signatureKeyId => text().nullable()();
  DateTimeColumn get installedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {moduleId, version};
}

class FieldDefinitions extends Table {
  TextColumn get key => text()();
  TextColumn get moduleId => text().references(ModuleInstallations, #id)();
  TextColumn get resourceId => text()();
  TextColumn get label => text()();
  TextColumn get type => text()();
  TextColumn get configJson => text().withDefault(const Constant('{}'))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

class FieldValues extends Table {
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get fieldKey => text().references(FieldDefinitions, #key)();
  TextColumn get valueJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {taskId, fieldKey};
}

class RuleExecutions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get moduleId => text()();
  TextColumn get ruleId => text()();
  TextColumn get eventType => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get eventPayloadJson =>
      text().withDefault(const Constant('{}'))();
  IntColumn get sourceExecutionId => integer().nullable()();
  TextColumn get status => text()();
  TextColumn get message => text().nullable()();
  IntColumn get automationDepth => integer().withDefault(const Constant(0))();
  IntColumn get actionCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class ChangeOperations extends Table {
  TextColumn get id => text()();
  TextColumn get deviceId => text()();
  IntColumn get counter => integer()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Projects,
    Tasks,
    Labels,
    TaskLabels,
    ModuleInstallations,
    ModuleVersions,
    FieldDefinitions,
    FieldValues,
    RuleExecutions,
    AppSettings,
    ChangeOperations,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  static Future<AppDatabase> open() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'xudian_v9.sqlite'));
    return AppDatabase(NativeDatabase.createInBackground(file));
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async => migrator.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks (project_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tasks_parent ON tasks (parent_task_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_tasks_dates ON tasks (due_date, planned_date)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_operations_pending ON change_operations (synced, counter)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_modules_active ON module_installations (installed, enabled)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_module_versions_module ON module_versions (module_id, installed_at)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_fields_module ON field_definitions (module_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_field_values_task ON field_values (task_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_rule_runs_module_time ON rule_executions (module_id, created_at)',
      );
    },
  );
}
