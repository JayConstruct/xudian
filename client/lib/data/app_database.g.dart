// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ProjectsTable extends Projects with TableInfo<$ProjectsTable, Project> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 120,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    createdAt,
    updatedAt,
    archivedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'projects';
  @override
  VerificationContext validateIntegrity(
    Insertable<Project> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Project map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Project(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
    );
  }

  @override
  $ProjectsTable createAlias(String alias) {
    return $ProjectsTable(attachedDatabase, alias);
  }
}

class Project extends DataClass implements Insertable<Project> {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    return map;
  }

  ProjectsCompanion toCompanion(bool nullToAbsent) {
    return ProjectsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
    );
  }

  factory Project.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Project(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
    };
  }

  Project copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> archivedAt = const Value.absent(),
  }) => Project(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
  );
  Project copyWithCompanion(ProjectsCompanion data) {
    return Project(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Project(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archivedAt: $archivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt, updatedAt, archivedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Project &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.archivedAt == this.archivedAt);
}

class ProjectsCompanion extends UpdateCompanion<Project> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> archivedAt;
  final Value<int> rowid;
  const ProjectsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectsCompanion.insert({
    required String id,
    required String name,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Project> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? archivedAt,
    Value<int>? rowid,
  }) {
    return ProjectsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES projects (id)',
    ),
  );
  static const VerificationMeta _parentTaskIdMeta = const VerificationMeta(
    'parentTaskId',
  );
  @override
  late final GeneratedColumn<String> parentTaskId = GeneratedColumn<String>(
    'parent_task_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 300,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<String> dueDate = GeneratedColumn<String>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plannedDateMeta = const VerificationMeta(
    'plannedDate',
  );
  @override
  late final GeneratedColumn<String> plannedDate = GeneratedColumn<String>(
    'planned_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectId,
    parentTaskId,
    title,
    notes,
    priority,
    dueDate,
    plannedDate,
    completedAt,
    archivedAt,
    deletedAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Task> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    }
    if (data.containsKey('parent_task_id')) {
      context.handle(
        _parentTaskIdMeta,
        parentTaskId.isAcceptableOrUnknown(
          data['parent_task_id']!,
          _parentTaskIdMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('planned_date')) {
      context.handle(
        _plannedDateMeta,
        plannedDate.isAcceptableOrUnknown(
          data['planned_date']!,
          _plannedDateMeta,
        ),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Task(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      ),
      parentTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_task_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}due_date'],
      ),
      plannedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}planned_date'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class Task extends DataClass implements Insertable<Task> {
  final String id;
  final String? projectId;
  final String? parentTaskId;
  final String title;
  final String notes;
  final int priority;
  final String? dueDate;
  final String? plannedDate;
  final DateTime? completedAt;
  final DateTime? archivedAt;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Task({
    required this.id,
    this.projectId,
    this.parentTaskId,
    required this.title,
    required this.notes,
    required this.priority,
    this.dueDate,
    this.plannedDate,
    this.completedAt,
    this.archivedAt,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || projectId != null) {
      map['project_id'] = Variable<String>(projectId);
    }
    if (!nullToAbsent || parentTaskId != null) {
      map['parent_task_id'] = Variable<String>(parentTaskId);
    }
    map['title'] = Variable<String>(title);
    map['notes'] = Variable<String>(notes);
    map['priority'] = Variable<int>(priority);
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<String>(dueDate);
    }
    if (!nullToAbsent || plannedDate != null) {
      map['planned_date'] = Variable<String>(plannedDate);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      projectId: projectId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectId),
      parentTaskId: parentTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentTaskId),
      title: Value(title),
      notes: Value(notes),
      priority: Value(priority),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      plannedDate: plannedDate == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedDate),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Task.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Task(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String?>(json['projectId']),
      parentTaskId: serializer.fromJson<String?>(json['parentTaskId']),
      title: serializer.fromJson<String>(json['title']),
      notes: serializer.fromJson<String>(json['notes']),
      priority: serializer.fromJson<int>(json['priority']),
      dueDate: serializer.fromJson<String?>(json['dueDate']),
      plannedDate: serializer.fromJson<String?>(json['plannedDate']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String?>(projectId),
      'parentTaskId': serializer.toJson<String?>(parentTaskId),
      'title': serializer.toJson<String>(title),
      'notes': serializer.toJson<String>(notes),
      'priority': serializer.toJson<int>(priority),
      'dueDate': serializer.toJson<String?>(dueDate),
      'plannedDate': serializer.toJson<String?>(plannedDate),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Task copyWith({
    String? id,
    Value<String?> projectId = const Value.absent(),
    Value<String?> parentTaskId = const Value.absent(),
    String? title,
    String? notes,
    int? priority,
    Value<String?> dueDate = const Value.absent(),
    Value<String?> plannedDate = const Value.absent(),
    Value<DateTime?> completedAt = const Value.absent(),
    Value<DateTime?> archivedAt = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Task(
    id: id ?? this.id,
    projectId: projectId.present ? projectId.value : this.projectId,
    parentTaskId: parentTaskId.present ? parentTaskId.value : this.parentTaskId,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    priority: priority ?? this.priority,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    plannedDate: plannedDate.present ? plannedDate.value : this.plannedDate,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Task copyWithCompanion(TasksCompanion data) {
    return Task(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      parentTaskId: data.parentTaskId.present
          ? data.parentTaskId.value
          : this.parentTaskId,
      title: data.title.present ? data.title.value : this.title,
      notes: data.notes.present ? data.notes.value : this.notes,
      priority: data.priority.present ? data.priority.value : this.priority,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      plannedDate: data.plannedDate.present
          ? data.plannedDate.value
          : this.plannedDate,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Task(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('parentTaskId: $parentTaskId, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('priority: $priority, ')
          ..write('dueDate: $dueDate, ')
          ..write('plannedDate: $plannedDate, ')
          ..write('completedAt: $completedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    projectId,
    parentTaskId,
    title,
    notes,
    priority,
    dueDate,
    plannedDate,
    completedAt,
    archivedAt,
    deletedAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Task &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.parentTaskId == this.parentTaskId &&
          other.title == this.title &&
          other.notes == this.notes &&
          other.priority == this.priority &&
          other.dueDate == this.dueDate &&
          other.plannedDate == this.plannedDate &&
          other.completedAt == this.completedAt &&
          other.archivedAt == this.archivedAt &&
          other.deletedAt == this.deletedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TasksCompanion extends UpdateCompanion<Task> {
  final Value<String> id;
  final Value<String?> projectId;
  final Value<String?> parentTaskId;
  final Value<String> title;
  final Value<String> notes;
  final Value<int> priority;
  final Value<String?> dueDate;
  final Value<String?> plannedDate;
  final Value<DateTime?> completedAt;
  final Value<DateTime?> archivedAt;
  final Value<DateTime?> deletedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.parentTaskId = const Value.absent(),
    this.title = const Value.absent(),
    this.notes = const Value.absent(),
    this.priority = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.plannedDate = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    this.projectId = const Value.absent(),
    this.parentTaskId = const Value.absent(),
    required String title,
    this.notes = const Value.absent(),
    this.priority = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.plannedDate = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Task> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<String>? parentTaskId,
    Expression<String>? title,
    Expression<String>? notes,
    Expression<int>? priority,
    Expression<String>? dueDate,
    Expression<String>? plannedDate,
    Expression<DateTime>? completedAt,
    Expression<DateTime>? archivedAt,
    Expression<DateTime>? deletedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (parentTaskId != null) 'parent_task_id': parentTaskId,
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
      if (priority != null) 'priority': priority,
      if (dueDate != null) 'due_date': dueDate,
      if (plannedDate != null) 'planned_date': plannedDate,
      if (completedAt != null) 'completed_at': completedAt,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith({
    Value<String>? id,
    Value<String?>? projectId,
    Value<String?>? parentTaskId,
    Value<String>? title,
    Value<String>? notes,
    Value<int>? priority,
    Value<String?>? dueDate,
    Value<String?>? plannedDate,
    Value<DateTime?>? completedAt,
    Value<DateTime?>? archivedAt,
    Value<DateTime?>? deletedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      parentTaskId: parentTaskId ?? this.parentTaskId,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      plannedDate: plannedDate ?? this.plannedDate,
      completedAt: completedAt ?? this.completedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (parentTaskId.present) {
      map['parent_task_id'] = Variable<String>(parentTaskId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(dueDate.value);
    }
    if (plannedDate.present) {
      map['planned_date'] = Variable<String>(plannedDate.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('parentTaskId: $parentTaskId, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('priority: $priority, ')
          ..write('dueDate: $dueDate, ')
          ..write('plannedDate: $plannedDate, ')
          ..write('completedAt: $completedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LabelsTable extends Labels with TableInfo<$LabelsTable, Label> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LabelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0xFF6750A4),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, color];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'labels';
  @override
  VerificationContext validateIntegrity(
    Insertable<Label> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Label map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Label(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
    );
  }

  @override
  $LabelsTable createAlias(String alias) {
    return $LabelsTable(attachedDatabase, alias);
  }
}

class Label extends DataClass implements Insertable<Label> {
  final String id;
  final String name;
  final int color;
  const Label({required this.id, required this.name, required this.color});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<int>(color);
    return map;
  }

  LabelsCompanion toCompanion(bool nullToAbsent) {
    return LabelsCompanion(
      id: Value(id),
      name: Value(name),
      color: Value(color),
    );
  }

  factory Label.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Label(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<int>(json['color']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<int>(color),
    };
  }

  Label copyWith({String? id, String? name, int? color}) => Label(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
  );
  Label copyWithCompanion(LabelsCompanion data) {
    return Label(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Label(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, color);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Label &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color);
}

class LabelsCompanion extends UpdateCompanion<Label> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> color;
  final Value<int> rowid;
  const LabelsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LabelsCompanion.insert({
    required String id,
    required String name,
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Label> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? color,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LabelsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? color,
    Value<int>? rowid,
  }) {
    return LabelsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LabelsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskLabelsTable extends TaskLabels
    with TableInfo<$TaskLabelsTable, TaskLabel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskLabelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id)',
    ),
  );
  static const VerificationMeta _labelIdMeta = const VerificationMeta(
    'labelId',
  );
  @override
  late final GeneratedColumn<String> labelId = GeneratedColumn<String>(
    'label_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES labels (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [taskId, labelId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_labels';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskLabel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('label_id')) {
      context.handle(
        _labelIdMeta,
        labelId.isAcceptableOrUnknown(data['label_id']!, _labelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_labelIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {taskId, labelId};
  @override
  TaskLabel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskLabel(
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      labelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label_id'],
      )!,
    );
  }

  @override
  $TaskLabelsTable createAlias(String alias) {
    return $TaskLabelsTable(attachedDatabase, alias);
  }
}

class TaskLabel extends DataClass implements Insertable<TaskLabel> {
  final String taskId;
  final String labelId;
  const TaskLabel({required this.taskId, required this.labelId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['task_id'] = Variable<String>(taskId);
    map['label_id'] = Variable<String>(labelId);
    return map;
  }

  TaskLabelsCompanion toCompanion(bool nullToAbsent) {
    return TaskLabelsCompanion(taskId: Value(taskId), labelId: Value(labelId));
  }

  factory TaskLabel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskLabel(
      taskId: serializer.fromJson<String>(json['taskId']),
      labelId: serializer.fromJson<String>(json['labelId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'taskId': serializer.toJson<String>(taskId),
      'labelId': serializer.toJson<String>(labelId),
    };
  }

  TaskLabel copyWith({String? taskId, String? labelId}) => TaskLabel(
    taskId: taskId ?? this.taskId,
    labelId: labelId ?? this.labelId,
  );
  TaskLabel copyWithCompanion(TaskLabelsCompanion data) {
    return TaskLabel(
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      labelId: data.labelId.present ? data.labelId.value : this.labelId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskLabel(')
          ..write('taskId: $taskId, ')
          ..write('labelId: $labelId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(taskId, labelId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskLabel &&
          other.taskId == this.taskId &&
          other.labelId == this.labelId);
}

class TaskLabelsCompanion extends UpdateCompanion<TaskLabel> {
  final Value<String> taskId;
  final Value<String> labelId;
  final Value<int> rowid;
  const TaskLabelsCompanion({
    this.taskId = const Value.absent(),
    this.labelId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskLabelsCompanion.insert({
    required String taskId,
    required String labelId,
    this.rowid = const Value.absent(),
  }) : taskId = Value(taskId),
       labelId = Value(labelId);
  static Insertable<TaskLabel> custom({
    Expression<String>? taskId,
    Expression<String>? labelId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (taskId != null) 'task_id': taskId,
      if (labelId != null) 'label_id': labelId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskLabelsCompanion copyWith({
    Value<String>? taskId,
    Value<String>? labelId,
    Value<int>? rowid,
  }) {
    return TaskLabelsCompanion(
      taskId: taskId ?? this.taskId,
      labelId: labelId ?? this.labelId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (labelId.present) {
      map['label_id'] = Variable<String>(labelId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskLabelsCompanion(')
          ..write('taskId: $taskId, ')
          ..write('labelId: $labelId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ModuleInstallationsTable extends ModuleInstallations
    with TableInfo<$ModuleInstallationsTable, ModuleInstallation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ModuleInstallationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceJsonMeta = const VerificationMeta(
    'sourceJson',
  );
  @override
  late final GeneratedColumn<String> sourceJson = GeneratedColumn<String>(
    'source_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _installedMeta = const VerificationMeta(
    'installed',
  );
  @override
  late final GeneratedColumn<bool> installed = GeneratedColumn<bool>(
    'installed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("installed" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local'),
  );
  static const VerificationMeta _publisherIdMeta = const VerificationMeta(
    'publisherId',
  );
  @override
  late final GeneratedColumn<String> publisherId = GeneratedColumn<String>(
    'publisher_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _packageDigestMeta = const VerificationMeta(
    'packageDigest',
  );
  @override
  late final GeneratedColumn<String> packageDigest = GeneratedColumn<String>(
    'package_digest',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reviewIdMeta = const VerificationMeta(
    'reviewId',
  );
  @override
  late final GeneratedColumn<String> reviewId = GeneratedColumn<String>(
    'review_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _signatureKeyIdMeta = const VerificationMeta(
    'signatureKeyId',
  );
  @override
  late final GeneratedColumn<String> signatureKeyId = GeneratedColumn<String>(
    'signature_key_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _installedAtMeta = const VerificationMeta(
    'installedAt',
  );
  @override
  late final GeneratedColumn<DateTime> installedAt = GeneratedColumn<DateTime>(
    'installed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    sourceJson,
    installed,
    enabled,
    origin,
    publisherId,
    packageDigest,
    reviewId,
    signatureKeyId,
    installedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'module_installations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ModuleInstallation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('source_json')) {
      context.handle(
        _sourceJsonMeta,
        sourceJson.isAcceptableOrUnknown(data['source_json']!, _sourceJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceJsonMeta);
    }
    if (data.containsKey('installed')) {
      context.handle(
        _installedMeta,
        installed.isAcceptableOrUnknown(data['installed']!, _installedMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    }
    if (data.containsKey('publisher_id')) {
      context.handle(
        _publisherIdMeta,
        publisherId.isAcceptableOrUnknown(
          data['publisher_id']!,
          _publisherIdMeta,
        ),
      );
    }
    if (data.containsKey('package_digest')) {
      context.handle(
        _packageDigestMeta,
        packageDigest.isAcceptableOrUnknown(
          data['package_digest']!,
          _packageDigestMeta,
        ),
      );
    }
    if (data.containsKey('review_id')) {
      context.handle(
        _reviewIdMeta,
        reviewId.isAcceptableOrUnknown(data['review_id']!, _reviewIdMeta),
      );
    }
    if (data.containsKey('signature_key_id')) {
      context.handle(
        _signatureKeyIdMeta,
        signatureKeyId.isAcceptableOrUnknown(
          data['signature_key_id']!,
          _signatureKeyIdMeta,
        ),
      );
    }
    if (data.containsKey('installed_at')) {
      context.handle(
        _installedAtMeta,
        installedAt.isAcceptableOrUnknown(
          data['installed_at']!,
          _installedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_installedAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ModuleInstallation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ModuleInstallation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      sourceJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_json'],
      )!,
      installed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}installed'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      publisherId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}publisher_id'],
      ),
      packageDigest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}package_digest'],
      ),
      reviewId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_id'],
      ),
      signatureKeyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signature_key_id'],
      ),
      installedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}installed_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ModuleInstallationsTable createAlias(String alias) {
    return $ModuleInstallationsTable(attachedDatabase, alias);
  }
}

class ModuleInstallation extends DataClass
    implements Insertable<ModuleInstallation> {
  final String id;
  final String version;
  final String sourceJson;
  final bool installed;
  final bool enabled;
  final String origin;
  final String? publisherId;
  final String? packageDigest;
  final String? reviewId;
  final String? signatureKeyId;
  final DateTime installedAt;
  final DateTime updatedAt;
  const ModuleInstallation({
    required this.id,
    required this.version,
    required this.sourceJson,
    required this.installed,
    required this.enabled,
    required this.origin,
    this.publisherId,
    this.packageDigest,
    this.reviewId,
    this.signatureKeyId,
    required this.installedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version'] = Variable<String>(version);
    map['source_json'] = Variable<String>(sourceJson);
    map['installed'] = Variable<bool>(installed);
    map['enabled'] = Variable<bool>(enabled);
    map['origin'] = Variable<String>(origin);
    if (!nullToAbsent || publisherId != null) {
      map['publisher_id'] = Variable<String>(publisherId);
    }
    if (!nullToAbsent || packageDigest != null) {
      map['package_digest'] = Variable<String>(packageDigest);
    }
    if (!nullToAbsent || reviewId != null) {
      map['review_id'] = Variable<String>(reviewId);
    }
    if (!nullToAbsent || signatureKeyId != null) {
      map['signature_key_id'] = Variable<String>(signatureKeyId);
    }
    map['installed_at'] = Variable<DateTime>(installedAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ModuleInstallationsCompanion toCompanion(bool nullToAbsent) {
    return ModuleInstallationsCompanion(
      id: Value(id),
      version: Value(version),
      sourceJson: Value(sourceJson),
      installed: Value(installed),
      enabled: Value(enabled),
      origin: Value(origin),
      publisherId: publisherId == null && nullToAbsent
          ? const Value.absent()
          : Value(publisherId),
      packageDigest: packageDigest == null && nullToAbsent
          ? const Value.absent()
          : Value(packageDigest),
      reviewId: reviewId == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewId),
      signatureKeyId: signatureKeyId == null && nullToAbsent
          ? const Value.absent()
          : Value(signatureKeyId),
      installedAt: Value(installedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ModuleInstallation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ModuleInstallation(
      id: serializer.fromJson<String>(json['id']),
      version: serializer.fromJson<String>(json['version']),
      sourceJson: serializer.fromJson<String>(json['sourceJson']),
      installed: serializer.fromJson<bool>(json['installed']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      origin: serializer.fromJson<String>(json['origin']),
      publisherId: serializer.fromJson<String?>(json['publisherId']),
      packageDigest: serializer.fromJson<String?>(json['packageDigest']),
      reviewId: serializer.fromJson<String?>(json['reviewId']),
      signatureKeyId: serializer.fromJson<String?>(json['signatureKeyId']),
      installedAt: serializer.fromJson<DateTime>(json['installedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'version': serializer.toJson<String>(version),
      'sourceJson': serializer.toJson<String>(sourceJson),
      'installed': serializer.toJson<bool>(installed),
      'enabled': serializer.toJson<bool>(enabled),
      'origin': serializer.toJson<String>(origin),
      'publisherId': serializer.toJson<String?>(publisherId),
      'packageDigest': serializer.toJson<String?>(packageDigest),
      'reviewId': serializer.toJson<String?>(reviewId),
      'signatureKeyId': serializer.toJson<String?>(signatureKeyId),
      'installedAt': serializer.toJson<DateTime>(installedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ModuleInstallation copyWith({
    String? id,
    String? version,
    String? sourceJson,
    bool? installed,
    bool? enabled,
    String? origin,
    Value<String?> publisherId = const Value.absent(),
    Value<String?> packageDigest = const Value.absent(),
    Value<String?> reviewId = const Value.absent(),
    Value<String?> signatureKeyId = const Value.absent(),
    DateTime? installedAt,
    DateTime? updatedAt,
  }) => ModuleInstallation(
    id: id ?? this.id,
    version: version ?? this.version,
    sourceJson: sourceJson ?? this.sourceJson,
    installed: installed ?? this.installed,
    enabled: enabled ?? this.enabled,
    origin: origin ?? this.origin,
    publisherId: publisherId.present ? publisherId.value : this.publisherId,
    packageDigest: packageDigest.present
        ? packageDigest.value
        : this.packageDigest,
    reviewId: reviewId.present ? reviewId.value : this.reviewId,
    signatureKeyId: signatureKeyId.present
        ? signatureKeyId.value
        : this.signatureKeyId,
    installedAt: installedAt ?? this.installedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ModuleInstallation copyWithCompanion(ModuleInstallationsCompanion data) {
    return ModuleInstallation(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      sourceJson: data.sourceJson.present
          ? data.sourceJson.value
          : this.sourceJson,
      installed: data.installed.present ? data.installed.value : this.installed,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      origin: data.origin.present ? data.origin.value : this.origin,
      publisherId: data.publisherId.present
          ? data.publisherId.value
          : this.publisherId,
      packageDigest: data.packageDigest.present
          ? data.packageDigest.value
          : this.packageDigest,
      reviewId: data.reviewId.present ? data.reviewId.value : this.reviewId,
      signatureKeyId: data.signatureKeyId.present
          ? data.signatureKeyId.value
          : this.signatureKeyId,
      installedAt: data.installedAt.present
          ? data.installedAt.value
          : this.installedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ModuleInstallation(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('sourceJson: $sourceJson, ')
          ..write('installed: $installed, ')
          ..write('enabled: $enabled, ')
          ..write('origin: $origin, ')
          ..write('publisherId: $publisherId, ')
          ..write('packageDigest: $packageDigest, ')
          ..write('reviewId: $reviewId, ')
          ..write('signatureKeyId: $signatureKeyId, ')
          ..write('installedAt: $installedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    version,
    sourceJson,
    installed,
    enabled,
    origin,
    publisherId,
    packageDigest,
    reviewId,
    signatureKeyId,
    installedAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ModuleInstallation &&
          other.id == this.id &&
          other.version == this.version &&
          other.sourceJson == this.sourceJson &&
          other.installed == this.installed &&
          other.enabled == this.enabled &&
          other.origin == this.origin &&
          other.publisherId == this.publisherId &&
          other.packageDigest == this.packageDigest &&
          other.reviewId == this.reviewId &&
          other.signatureKeyId == this.signatureKeyId &&
          other.installedAt == this.installedAt &&
          other.updatedAt == this.updatedAt);
}

class ModuleInstallationsCompanion extends UpdateCompanion<ModuleInstallation> {
  final Value<String> id;
  final Value<String> version;
  final Value<String> sourceJson;
  final Value<bool> installed;
  final Value<bool> enabled;
  final Value<String> origin;
  final Value<String?> publisherId;
  final Value<String?> packageDigest;
  final Value<String?> reviewId;
  final Value<String?> signatureKeyId;
  final Value<DateTime> installedAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ModuleInstallationsCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.sourceJson = const Value.absent(),
    this.installed = const Value.absent(),
    this.enabled = const Value.absent(),
    this.origin = const Value.absent(),
    this.publisherId = const Value.absent(),
    this.packageDigest = const Value.absent(),
    this.reviewId = const Value.absent(),
    this.signatureKeyId = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ModuleInstallationsCompanion.insert({
    required String id,
    required String version,
    required String sourceJson,
    this.installed = const Value.absent(),
    this.enabled = const Value.absent(),
    this.origin = const Value.absent(),
    this.publisherId = const Value.absent(),
    this.packageDigest = const Value.absent(),
    this.reviewId = const Value.absent(),
    this.signatureKeyId = const Value.absent(),
    required DateTime installedAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       version = Value(version),
       sourceJson = Value(sourceJson),
       installedAt = Value(installedAt),
       updatedAt = Value(updatedAt);
  static Insertable<ModuleInstallation> custom({
    Expression<String>? id,
    Expression<String>? version,
    Expression<String>? sourceJson,
    Expression<bool>? installed,
    Expression<bool>? enabled,
    Expression<String>? origin,
    Expression<String>? publisherId,
    Expression<String>? packageDigest,
    Expression<String>? reviewId,
    Expression<String>? signatureKeyId,
    Expression<DateTime>? installedAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (sourceJson != null) 'source_json': sourceJson,
      if (installed != null) 'installed': installed,
      if (enabled != null) 'enabled': enabled,
      if (origin != null) 'origin': origin,
      if (publisherId != null) 'publisher_id': publisherId,
      if (packageDigest != null) 'package_digest': packageDigest,
      if (reviewId != null) 'review_id': reviewId,
      if (signatureKeyId != null) 'signature_key_id': signatureKeyId,
      if (installedAt != null) 'installed_at': installedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ModuleInstallationsCompanion copyWith({
    Value<String>? id,
    Value<String>? version,
    Value<String>? sourceJson,
    Value<bool>? installed,
    Value<bool>? enabled,
    Value<String>? origin,
    Value<String?>? publisherId,
    Value<String?>? packageDigest,
    Value<String?>? reviewId,
    Value<String?>? signatureKeyId,
    Value<DateTime>? installedAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ModuleInstallationsCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      sourceJson: sourceJson ?? this.sourceJson,
      installed: installed ?? this.installed,
      enabled: enabled ?? this.enabled,
      origin: origin ?? this.origin,
      publisherId: publisherId ?? this.publisherId,
      packageDigest: packageDigest ?? this.packageDigest,
      reviewId: reviewId ?? this.reviewId,
      signatureKeyId: signatureKeyId ?? this.signatureKeyId,
      installedAt: installedAt ?? this.installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (sourceJson.present) {
      map['source_json'] = Variable<String>(sourceJson.value);
    }
    if (installed.present) {
      map['installed'] = Variable<bool>(installed.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (publisherId.present) {
      map['publisher_id'] = Variable<String>(publisherId.value);
    }
    if (packageDigest.present) {
      map['package_digest'] = Variable<String>(packageDigest.value);
    }
    if (reviewId.present) {
      map['review_id'] = Variable<String>(reviewId.value);
    }
    if (signatureKeyId.present) {
      map['signature_key_id'] = Variable<String>(signatureKeyId.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<DateTime>(installedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ModuleInstallationsCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('sourceJson: $sourceJson, ')
          ..write('installed: $installed, ')
          ..write('enabled: $enabled, ')
          ..write('origin: $origin, ')
          ..write('publisherId: $publisherId, ')
          ..write('packageDigest: $packageDigest, ')
          ..write('reviewId: $reviewId, ')
          ..write('signatureKeyId: $signatureKeyId, ')
          ..write('installedAt: $installedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ModuleVersionsTable extends ModuleVersions
    with TableInfo<$ModuleVersionsTable, ModuleVersion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ModuleVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _moduleIdMeta = const VerificationMeta(
    'moduleId',
  );
  @override
  late final GeneratedColumn<String> moduleId = GeneratedColumn<String>(
    'module_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceJsonMeta = const VerificationMeta(
    'sourceJson',
  );
  @override
  late final GeneratedColumn<String> sourceJson = GeneratedColumn<String>(
    'source_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local'),
  );
  static const VerificationMeta _publisherIdMeta = const VerificationMeta(
    'publisherId',
  );
  @override
  late final GeneratedColumn<String> publisherId = GeneratedColumn<String>(
    'publisher_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _packageDigestMeta = const VerificationMeta(
    'packageDigest',
  );
  @override
  late final GeneratedColumn<String> packageDigest = GeneratedColumn<String>(
    'package_digest',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reviewIdMeta = const VerificationMeta(
    'reviewId',
  );
  @override
  late final GeneratedColumn<String> reviewId = GeneratedColumn<String>(
    'review_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _signatureKeyIdMeta = const VerificationMeta(
    'signatureKeyId',
  );
  @override
  late final GeneratedColumn<String> signatureKeyId = GeneratedColumn<String>(
    'signature_key_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _installedAtMeta = const VerificationMeta(
    'installedAt',
  );
  @override
  late final GeneratedColumn<DateTime> installedAt = GeneratedColumn<DateTime>(
    'installed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    moduleId,
    version,
    sourceJson,
    origin,
    publisherId,
    packageDigest,
    reviewId,
    signatureKeyId,
    installedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'module_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ModuleVersion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('module_id')) {
      context.handle(
        _moduleIdMeta,
        moduleId.isAcceptableOrUnknown(data['module_id']!, _moduleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_moduleIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('source_json')) {
      context.handle(
        _sourceJsonMeta,
        sourceJson.isAcceptableOrUnknown(data['source_json']!, _sourceJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceJsonMeta);
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    }
    if (data.containsKey('publisher_id')) {
      context.handle(
        _publisherIdMeta,
        publisherId.isAcceptableOrUnknown(
          data['publisher_id']!,
          _publisherIdMeta,
        ),
      );
    }
    if (data.containsKey('package_digest')) {
      context.handle(
        _packageDigestMeta,
        packageDigest.isAcceptableOrUnknown(
          data['package_digest']!,
          _packageDigestMeta,
        ),
      );
    }
    if (data.containsKey('review_id')) {
      context.handle(
        _reviewIdMeta,
        reviewId.isAcceptableOrUnknown(data['review_id']!, _reviewIdMeta),
      );
    }
    if (data.containsKey('signature_key_id')) {
      context.handle(
        _signatureKeyIdMeta,
        signatureKeyId.isAcceptableOrUnknown(
          data['signature_key_id']!,
          _signatureKeyIdMeta,
        ),
      );
    }
    if (data.containsKey('installed_at')) {
      context.handle(
        _installedAtMeta,
        installedAt.isAcceptableOrUnknown(
          data['installed_at']!,
          _installedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_installedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {moduleId, version};
  @override
  ModuleVersion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ModuleVersion(
      moduleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}module_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      sourceJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_json'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      publisherId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}publisher_id'],
      ),
      packageDigest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}package_digest'],
      ),
      reviewId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_id'],
      ),
      signatureKeyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signature_key_id'],
      ),
      installedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}installed_at'],
      )!,
    );
  }

  @override
  $ModuleVersionsTable createAlias(String alias) {
    return $ModuleVersionsTable(attachedDatabase, alias);
  }
}

class ModuleVersion extends DataClass implements Insertable<ModuleVersion> {
  final String moduleId;
  final String version;
  final String sourceJson;
  final String origin;
  final String? publisherId;
  final String? packageDigest;
  final String? reviewId;
  final String? signatureKeyId;
  final DateTime installedAt;
  const ModuleVersion({
    required this.moduleId,
    required this.version,
    required this.sourceJson,
    required this.origin,
    this.publisherId,
    this.packageDigest,
    this.reviewId,
    this.signatureKeyId,
    required this.installedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['module_id'] = Variable<String>(moduleId);
    map['version'] = Variable<String>(version);
    map['source_json'] = Variable<String>(sourceJson);
    map['origin'] = Variable<String>(origin);
    if (!nullToAbsent || publisherId != null) {
      map['publisher_id'] = Variable<String>(publisherId);
    }
    if (!nullToAbsent || packageDigest != null) {
      map['package_digest'] = Variable<String>(packageDigest);
    }
    if (!nullToAbsent || reviewId != null) {
      map['review_id'] = Variable<String>(reviewId);
    }
    if (!nullToAbsent || signatureKeyId != null) {
      map['signature_key_id'] = Variable<String>(signatureKeyId);
    }
    map['installed_at'] = Variable<DateTime>(installedAt);
    return map;
  }

  ModuleVersionsCompanion toCompanion(bool nullToAbsent) {
    return ModuleVersionsCompanion(
      moduleId: Value(moduleId),
      version: Value(version),
      sourceJson: Value(sourceJson),
      origin: Value(origin),
      publisherId: publisherId == null && nullToAbsent
          ? const Value.absent()
          : Value(publisherId),
      packageDigest: packageDigest == null && nullToAbsent
          ? const Value.absent()
          : Value(packageDigest),
      reviewId: reviewId == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewId),
      signatureKeyId: signatureKeyId == null && nullToAbsent
          ? const Value.absent()
          : Value(signatureKeyId),
      installedAt: Value(installedAt),
    );
  }

  factory ModuleVersion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ModuleVersion(
      moduleId: serializer.fromJson<String>(json['moduleId']),
      version: serializer.fromJson<String>(json['version']),
      sourceJson: serializer.fromJson<String>(json['sourceJson']),
      origin: serializer.fromJson<String>(json['origin']),
      publisherId: serializer.fromJson<String?>(json['publisherId']),
      packageDigest: serializer.fromJson<String?>(json['packageDigest']),
      reviewId: serializer.fromJson<String?>(json['reviewId']),
      signatureKeyId: serializer.fromJson<String?>(json['signatureKeyId']),
      installedAt: serializer.fromJson<DateTime>(json['installedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'moduleId': serializer.toJson<String>(moduleId),
      'version': serializer.toJson<String>(version),
      'sourceJson': serializer.toJson<String>(sourceJson),
      'origin': serializer.toJson<String>(origin),
      'publisherId': serializer.toJson<String?>(publisherId),
      'packageDigest': serializer.toJson<String?>(packageDigest),
      'reviewId': serializer.toJson<String?>(reviewId),
      'signatureKeyId': serializer.toJson<String?>(signatureKeyId),
      'installedAt': serializer.toJson<DateTime>(installedAt),
    };
  }

  ModuleVersion copyWith({
    String? moduleId,
    String? version,
    String? sourceJson,
    String? origin,
    Value<String?> publisherId = const Value.absent(),
    Value<String?> packageDigest = const Value.absent(),
    Value<String?> reviewId = const Value.absent(),
    Value<String?> signatureKeyId = const Value.absent(),
    DateTime? installedAt,
  }) => ModuleVersion(
    moduleId: moduleId ?? this.moduleId,
    version: version ?? this.version,
    sourceJson: sourceJson ?? this.sourceJson,
    origin: origin ?? this.origin,
    publisherId: publisherId.present ? publisherId.value : this.publisherId,
    packageDigest: packageDigest.present
        ? packageDigest.value
        : this.packageDigest,
    reviewId: reviewId.present ? reviewId.value : this.reviewId,
    signatureKeyId: signatureKeyId.present
        ? signatureKeyId.value
        : this.signatureKeyId,
    installedAt: installedAt ?? this.installedAt,
  );
  ModuleVersion copyWithCompanion(ModuleVersionsCompanion data) {
    return ModuleVersion(
      moduleId: data.moduleId.present ? data.moduleId.value : this.moduleId,
      version: data.version.present ? data.version.value : this.version,
      sourceJson: data.sourceJson.present
          ? data.sourceJson.value
          : this.sourceJson,
      origin: data.origin.present ? data.origin.value : this.origin,
      publisherId: data.publisherId.present
          ? data.publisherId.value
          : this.publisherId,
      packageDigest: data.packageDigest.present
          ? data.packageDigest.value
          : this.packageDigest,
      reviewId: data.reviewId.present ? data.reviewId.value : this.reviewId,
      signatureKeyId: data.signatureKeyId.present
          ? data.signatureKeyId.value
          : this.signatureKeyId,
      installedAt: data.installedAt.present
          ? data.installedAt.value
          : this.installedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ModuleVersion(')
          ..write('moduleId: $moduleId, ')
          ..write('version: $version, ')
          ..write('sourceJson: $sourceJson, ')
          ..write('origin: $origin, ')
          ..write('publisherId: $publisherId, ')
          ..write('packageDigest: $packageDigest, ')
          ..write('reviewId: $reviewId, ')
          ..write('signatureKeyId: $signatureKeyId, ')
          ..write('installedAt: $installedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    moduleId,
    version,
    sourceJson,
    origin,
    publisherId,
    packageDigest,
    reviewId,
    signatureKeyId,
    installedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ModuleVersion &&
          other.moduleId == this.moduleId &&
          other.version == this.version &&
          other.sourceJson == this.sourceJson &&
          other.origin == this.origin &&
          other.publisherId == this.publisherId &&
          other.packageDigest == this.packageDigest &&
          other.reviewId == this.reviewId &&
          other.signatureKeyId == this.signatureKeyId &&
          other.installedAt == this.installedAt);
}

class ModuleVersionsCompanion extends UpdateCompanion<ModuleVersion> {
  final Value<String> moduleId;
  final Value<String> version;
  final Value<String> sourceJson;
  final Value<String> origin;
  final Value<String?> publisherId;
  final Value<String?> packageDigest;
  final Value<String?> reviewId;
  final Value<String?> signatureKeyId;
  final Value<DateTime> installedAt;
  final Value<int> rowid;
  const ModuleVersionsCompanion({
    this.moduleId = const Value.absent(),
    this.version = const Value.absent(),
    this.sourceJson = const Value.absent(),
    this.origin = const Value.absent(),
    this.publisherId = const Value.absent(),
    this.packageDigest = const Value.absent(),
    this.reviewId = const Value.absent(),
    this.signatureKeyId = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ModuleVersionsCompanion.insert({
    required String moduleId,
    required String version,
    required String sourceJson,
    this.origin = const Value.absent(),
    this.publisherId = const Value.absent(),
    this.packageDigest = const Value.absent(),
    this.reviewId = const Value.absent(),
    this.signatureKeyId = const Value.absent(),
    required DateTime installedAt,
    this.rowid = const Value.absent(),
  }) : moduleId = Value(moduleId),
       version = Value(version),
       sourceJson = Value(sourceJson),
       installedAt = Value(installedAt);
  static Insertable<ModuleVersion> custom({
    Expression<String>? moduleId,
    Expression<String>? version,
    Expression<String>? sourceJson,
    Expression<String>? origin,
    Expression<String>? publisherId,
    Expression<String>? packageDigest,
    Expression<String>? reviewId,
    Expression<String>? signatureKeyId,
    Expression<DateTime>? installedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (moduleId != null) 'module_id': moduleId,
      if (version != null) 'version': version,
      if (sourceJson != null) 'source_json': sourceJson,
      if (origin != null) 'origin': origin,
      if (publisherId != null) 'publisher_id': publisherId,
      if (packageDigest != null) 'package_digest': packageDigest,
      if (reviewId != null) 'review_id': reviewId,
      if (signatureKeyId != null) 'signature_key_id': signatureKeyId,
      if (installedAt != null) 'installed_at': installedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ModuleVersionsCompanion copyWith({
    Value<String>? moduleId,
    Value<String>? version,
    Value<String>? sourceJson,
    Value<String>? origin,
    Value<String?>? publisherId,
    Value<String?>? packageDigest,
    Value<String?>? reviewId,
    Value<String?>? signatureKeyId,
    Value<DateTime>? installedAt,
    Value<int>? rowid,
  }) {
    return ModuleVersionsCompanion(
      moduleId: moduleId ?? this.moduleId,
      version: version ?? this.version,
      sourceJson: sourceJson ?? this.sourceJson,
      origin: origin ?? this.origin,
      publisherId: publisherId ?? this.publisherId,
      packageDigest: packageDigest ?? this.packageDigest,
      reviewId: reviewId ?? this.reviewId,
      signatureKeyId: signatureKeyId ?? this.signatureKeyId,
      installedAt: installedAt ?? this.installedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (moduleId.present) {
      map['module_id'] = Variable<String>(moduleId.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (sourceJson.present) {
      map['source_json'] = Variable<String>(sourceJson.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (publisherId.present) {
      map['publisher_id'] = Variable<String>(publisherId.value);
    }
    if (packageDigest.present) {
      map['package_digest'] = Variable<String>(packageDigest.value);
    }
    if (reviewId.present) {
      map['review_id'] = Variable<String>(reviewId.value);
    }
    if (signatureKeyId.present) {
      map['signature_key_id'] = Variable<String>(signatureKeyId.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<DateTime>(installedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ModuleVersionsCompanion(')
          ..write('moduleId: $moduleId, ')
          ..write('version: $version, ')
          ..write('sourceJson: $sourceJson, ')
          ..write('origin: $origin, ')
          ..write('publisherId: $publisherId, ')
          ..write('packageDigest: $packageDigest, ')
          ..write('reviewId: $reviewId, ')
          ..write('signatureKeyId: $signatureKeyId, ')
          ..write('installedAt: $installedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FieldDefinitionsTable extends FieldDefinitions
    with TableInfo<$FieldDefinitionsTable, FieldDefinition> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FieldDefinitionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _moduleIdMeta = const VerificationMeta(
    'moduleId',
  );
  @override
  late final GeneratedColumn<String> moduleId = GeneratedColumn<String>(
    'module_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES module_installations (id)',
    ),
  );
  static const VerificationMeta _resourceIdMeta = const VerificationMeta(
    'resourceId',
  );
  @override
  late final GeneratedColumn<String> resourceId = GeneratedColumn<String>(
    'resource_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _configJsonMeta = const VerificationMeta(
    'configJson',
  );
  @override
  late final GeneratedColumn<String> configJson = GeneratedColumn<String>(
    'config_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    key,
    moduleId,
    resourceId,
    label,
    type,
    configJson,
    active,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'field_definitions';
  @override
  VerificationContext validateIntegrity(
    Insertable<FieldDefinition> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('module_id')) {
      context.handle(
        _moduleIdMeta,
        moduleId.isAcceptableOrUnknown(data['module_id']!, _moduleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_moduleIdMeta);
    }
    if (data.containsKey('resource_id')) {
      context.handle(
        _resourceIdMeta,
        resourceId.isAcceptableOrUnknown(data['resource_id']!, _resourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_resourceIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('config_json')) {
      context.handle(
        _configJsonMeta,
        configJson.isAcceptableOrUnknown(data['config_json']!, _configJsonMeta),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  FieldDefinition map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FieldDefinition(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      moduleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}module_id'],
      )!,
      resourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resource_id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      configJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_json'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FieldDefinitionsTable createAlias(String alias) {
    return $FieldDefinitionsTable(attachedDatabase, alias);
  }
}

class FieldDefinition extends DataClass implements Insertable<FieldDefinition> {
  final String key;
  final String moduleId;
  final String resourceId;
  final String label;
  final String type;
  final String configJson;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;
  const FieldDefinition({
    required this.key,
    required this.moduleId,
    required this.resourceId,
    required this.label,
    required this.type,
    required this.configJson,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['module_id'] = Variable<String>(moduleId);
    map['resource_id'] = Variable<String>(resourceId);
    map['label'] = Variable<String>(label);
    map['type'] = Variable<String>(type);
    map['config_json'] = Variable<String>(configJson);
    map['active'] = Variable<bool>(active);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  FieldDefinitionsCompanion toCompanion(bool nullToAbsent) {
    return FieldDefinitionsCompanion(
      key: Value(key),
      moduleId: Value(moduleId),
      resourceId: Value(resourceId),
      label: Value(label),
      type: Value(type),
      configJson: Value(configJson),
      active: Value(active),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory FieldDefinition.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FieldDefinition(
      key: serializer.fromJson<String>(json['key']),
      moduleId: serializer.fromJson<String>(json['moduleId']),
      resourceId: serializer.fromJson<String>(json['resourceId']),
      label: serializer.fromJson<String>(json['label']),
      type: serializer.fromJson<String>(json['type']),
      configJson: serializer.fromJson<String>(json['configJson']),
      active: serializer.fromJson<bool>(json['active']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'moduleId': serializer.toJson<String>(moduleId),
      'resourceId': serializer.toJson<String>(resourceId),
      'label': serializer.toJson<String>(label),
      'type': serializer.toJson<String>(type),
      'configJson': serializer.toJson<String>(configJson),
      'active': serializer.toJson<bool>(active),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  FieldDefinition copyWith({
    String? key,
    String? moduleId,
    String? resourceId,
    String? label,
    String? type,
    String? configJson,
    bool? active,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => FieldDefinition(
    key: key ?? this.key,
    moduleId: moduleId ?? this.moduleId,
    resourceId: resourceId ?? this.resourceId,
    label: label ?? this.label,
    type: type ?? this.type,
    configJson: configJson ?? this.configJson,
    active: active ?? this.active,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  FieldDefinition copyWithCompanion(FieldDefinitionsCompanion data) {
    return FieldDefinition(
      key: data.key.present ? data.key.value : this.key,
      moduleId: data.moduleId.present ? data.moduleId.value : this.moduleId,
      resourceId: data.resourceId.present
          ? data.resourceId.value
          : this.resourceId,
      label: data.label.present ? data.label.value : this.label,
      type: data.type.present ? data.type.value : this.type,
      configJson: data.configJson.present
          ? data.configJson.value
          : this.configJson,
      active: data.active.present ? data.active.value : this.active,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FieldDefinition(')
          ..write('key: $key, ')
          ..write('moduleId: $moduleId, ')
          ..write('resourceId: $resourceId, ')
          ..write('label: $label, ')
          ..write('type: $type, ')
          ..write('configJson: $configJson, ')
          ..write('active: $active, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    key,
    moduleId,
    resourceId,
    label,
    type,
    configJson,
    active,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FieldDefinition &&
          other.key == this.key &&
          other.moduleId == this.moduleId &&
          other.resourceId == this.resourceId &&
          other.label == this.label &&
          other.type == this.type &&
          other.configJson == this.configJson &&
          other.active == this.active &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class FieldDefinitionsCompanion extends UpdateCompanion<FieldDefinition> {
  final Value<String> key;
  final Value<String> moduleId;
  final Value<String> resourceId;
  final Value<String> label;
  final Value<String> type;
  final Value<String> configJson;
  final Value<bool> active;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const FieldDefinitionsCompanion({
    this.key = const Value.absent(),
    this.moduleId = const Value.absent(),
    this.resourceId = const Value.absent(),
    this.label = const Value.absent(),
    this.type = const Value.absent(),
    this.configJson = const Value.absent(),
    this.active = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FieldDefinitionsCompanion.insert({
    required String key,
    required String moduleId,
    required String resourceId,
    required String label,
    required String type,
    this.configJson = const Value.absent(),
    this.active = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       moduleId = Value(moduleId),
       resourceId = Value(resourceId),
       label = Value(label),
       type = Value(type),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<FieldDefinition> custom({
    Expression<String>? key,
    Expression<String>? moduleId,
    Expression<String>? resourceId,
    Expression<String>? label,
    Expression<String>? type,
    Expression<String>? configJson,
    Expression<bool>? active,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (moduleId != null) 'module_id': moduleId,
      if (resourceId != null) 'resource_id': resourceId,
      if (label != null) 'label': label,
      if (type != null) 'type': type,
      if (configJson != null) 'config_json': configJson,
      if (active != null) 'active': active,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FieldDefinitionsCompanion copyWith({
    Value<String>? key,
    Value<String>? moduleId,
    Value<String>? resourceId,
    Value<String>? label,
    Value<String>? type,
    Value<String>? configJson,
    Value<bool>? active,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return FieldDefinitionsCompanion(
      key: key ?? this.key,
      moduleId: moduleId ?? this.moduleId,
      resourceId: resourceId ?? this.resourceId,
      label: label ?? this.label,
      type: type ?? this.type,
      configJson: configJson ?? this.configJson,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (moduleId.present) {
      map['module_id'] = Variable<String>(moduleId.value);
    }
    if (resourceId.present) {
      map['resource_id'] = Variable<String>(resourceId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (configJson.present) {
      map['config_json'] = Variable<String>(configJson.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FieldDefinitionsCompanion(')
          ..write('key: $key, ')
          ..write('moduleId: $moduleId, ')
          ..write('resourceId: $resourceId, ')
          ..write('label: $label, ')
          ..write('type: $type, ')
          ..write('configJson: $configJson, ')
          ..write('active: $active, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FieldValuesTable extends FieldValues
    with TableInfo<$FieldValuesTable, FieldValue> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FieldValuesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id)',
    ),
  );
  static const VerificationMeta _fieldKeyMeta = const VerificationMeta(
    'fieldKey',
  );
  @override
  late final GeneratedColumn<String> fieldKey = GeneratedColumn<String>(
    'field_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES field_definitions ("key")',
    ),
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    taskId,
    fieldKey,
    valueJson,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'field_values';
  @override
  VerificationContext validateIntegrity(
    Insertable<FieldValue> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('field_key')) {
      context.handle(
        _fieldKeyMeta,
        fieldKey.isAcceptableOrUnknown(data['field_key']!, _fieldKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldKeyMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_valueJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {taskId, fieldKey};
  @override
  FieldValue map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FieldValue(
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      fieldKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_key'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FieldValuesTable createAlias(String alias) {
    return $FieldValuesTable(attachedDatabase, alias);
  }
}

class FieldValue extends DataClass implements Insertable<FieldValue> {
  final String taskId;
  final String fieldKey;
  final String valueJson;
  final DateTime updatedAt;
  const FieldValue({
    required this.taskId,
    required this.fieldKey,
    required this.valueJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['task_id'] = Variable<String>(taskId);
    map['field_key'] = Variable<String>(fieldKey);
    map['value_json'] = Variable<String>(valueJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  FieldValuesCompanion toCompanion(bool nullToAbsent) {
    return FieldValuesCompanion(
      taskId: Value(taskId),
      fieldKey: Value(fieldKey),
      valueJson: Value(valueJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory FieldValue.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FieldValue(
      taskId: serializer.fromJson<String>(json['taskId']),
      fieldKey: serializer.fromJson<String>(json['fieldKey']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'taskId': serializer.toJson<String>(taskId),
      'fieldKey': serializer.toJson<String>(fieldKey),
      'valueJson': serializer.toJson<String>(valueJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  FieldValue copyWith({
    String? taskId,
    String? fieldKey,
    String? valueJson,
    DateTime? updatedAt,
  }) => FieldValue(
    taskId: taskId ?? this.taskId,
    fieldKey: fieldKey ?? this.fieldKey,
    valueJson: valueJson ?? this.valueJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  FieldValue copyWithCompanion(FieldValuesCompanion data) {
    return FieldValue(
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      fieldKey: data.fieldKey.present ? data.fieldKey.value : this.fieldKey,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FieldValue(')
          ..write('taskId: $taskId, ')
          ..write('fieldKey: $fieldKey, ')
          ..write('valueJson: $valueJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(taskId, fieldKey, valueJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FieldValue &&
          other.taskId == this.taskId &&
          other.fieldKey == this.fieldKey &&
          other.valueJson == this.valueJson &&
          other.updatedAt == this.updatedAt);
}

class FieldValuesCompanion extends UpdateCompanion<FieldValue> {
  final Value<String> taskId;
  final Value<String> fieldKey;
  final Value<String> valueJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const FieldValuesCompanion({
    this.taskId = const Value.absent(),
    this.fieldKey = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FieldValuesCompanion.insert({
    required String taskId,
    required String fieldKey,
    required String valueJson,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : taskId = Value(taskId),
       fieldKey = Value(fieldKey),
       valueJson = Value(valueJson),
       updatedAt = Value(updatedAt);
  static Insertable<FieldValue> custom({
    Expression<String>? taskId,
    Expression<String>? fieldKey,
    Expression<String>? valueJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (taskId != null) 'task_id': taskId,
      if (fieldKey != null) 'field_key': fieldKey,
      if (valueJson != null) 'value_json': valueJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FieldValuesCompanion copyWith({
    Value<String>? taskId,
    Value<String>? fieldKey,
    Value<String>? valueJson,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return FieldValuesCompanion(
      taskId: taskId ?? this.taskId,
      fieldKey: fieldKey ?? this.fieldKey,
      valueJson: valueJson ?? this.valueJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (fieldKey.present) {
      map['field_key'] = Variable<String>(fieldKey.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FieldValuesCompanion(')
          ..write('taskId: $taskId, ')
          ..write('fieldKey: $fieldKey, ')
          ..write('valueJson: $valueJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RuleExecutionsTable extends RuleExecutions
    with TableInfo<$RuleExecutionsTable, RuleExecution> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RuleExecutionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _moduleIdMeta = const VerificationMeta(
    'moduleId',
  );
  @override
  late final GeneratedColumn<String> moduleId = GeneratedColumn<String>(
    'module_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ruleIdMeta = const VerificationMeta('ruleId');
  @override
  late final GeneratedColumn<String> ruleId = GeneratedColumn<String>(
    'rule_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventPayloadJsonMeta = const VerificationMeta(
    'eventPayloadJson',
  );
  @override
  late final GeneratedColumn<String> eventPayloadJson = GeneratedColumn<String>(
    'event_payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _sourceExecutionIdMeta = const VerificationMeta(
    'sourceExecutionId',
  );
  @override
  late final GeneratedColumn<int> sourceExecutionId = GeneratedColumn<int>(
    'source_execution_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _automationDepthMeta = const VerificationMeta(
    'automationDepth',
  );
  @override
  late final GeneratedColumn<int> automationDepth = GeneratedColumn<int>(
    'automation_depth',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _actionCountMeta = const VerificationMeta(
    'actionCount',
  );
  @override
  late final GeneratedColumn<int> actionCount = GeneratedColumn<int>(
    'action_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    moduleId,
    ruleId,
    eventType,
    entityType,
    entityId,
    eventPayloadJson,
    sourceExecutionId,
    status,
    message,
    automationDepth,
    actionCount,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rule_executions';
  @override
  VerificationContext validateIntegrity(
    Insertable<RuleExecution> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('module_id')) {
      context.handle(
        _moduleIdMeta,
        moduleId.isAcceptableOrUnknown(data['module_id']!, _moduleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_moduleIdMeta);
    }
    if (data.containsKey('rule_id')) {
      context.handle(
        _ruleIdMeta,
        ruleId.isAcceptableOrUnknown(data['rule_id']!, _ruleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ruleIdMeta);
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('event_payload_json')) {
      context.handle(
        _eventPayloadJsonMeta,
        eventPayloadJson.isAcceptableOrUnknown(
          data['event_payload_json']!,
          _eventPayloadJsonMeta,
        ),
      );
    }
    if (data.containsKey('source_execution_id')) {
      context.handle(
        _sourceExecutionIdMeta,
        sourceExecutionId.isAcceptableOrUnknown(
          data['source_execution_id']!,
          _sourceExecutionIdMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    }
    if (data.containsKey('automation_depth')) {
      context.handle(
        _automationDepthMeta,
        automationDepth.isAcceptableOrUnknown(
          data['automation_depth']!,
          _automationDepthMeta,
        ),
      );
    }
    if (data.containsKey('action_count')) {
      context.handle(
        _actionCountMeta,
        actionCount.isAcceptableOrUnknown(
          data['action_count']!,
          _actionCountMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RuleExecution map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RuleExecution(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      moduleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}module_id'],
      )!,
      ruleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rule_id'],
      )!,
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      eventPayloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_payload_json'],
      )!,
      sourceExecutionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_execution_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      ),
      automationDepth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}automation_depth'],
      )!,
      actionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}action_count'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $RuleExecutionsTable createAlias(String alias) {
    return $RuleExecutionsTable(attachedDatabase, alias);
  }
}

class RuleExecution extends DataClass implements Insertable<RuleExecution> {
  final int id;
  final String moduleId;
  final String ruleId;
  final String eventType;
  final String entityType;
  final String entityId;
  final String eventPayloadJson;
  final int? sourceExecutionId;
  final String status;
  final String? message;
  final int automationDepth;
  final int actionCount;
  final DateTime createdAt;
  const RuleExecution({
    required this.id,
    required this.moduleId,
    required this.ruleId,
    required this.eventType,
    required this.entityType,
    required this.entityId,
    required this.eventPayloadJson,
    this.sourceExecutionId,
    required this.status,
    this.message,
    required this.automationDepth,
    required this.actionCount,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['module_id'] = Variable<String>(moduleId);
    map['rule_id'] = Variable<String>(ruleId);
    map['event_type'] = Variable<String>(eventType);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['event_payload_json'] = Variable<String>(eventPayloadJson);
    if (!nullToAbsent || sourceExecutionId != null) {
      map['source_execution_id'] = Variable<int>(sourceExecutionId);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || message != null) {
      map['message'] = Variable<String>(message);
    }
    map['automation_depth'] = Variable<int>(automationDepth);
    map['action_count'] = Variable<int>(actionCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RuleExecutionsCompanion toCompanion(bool nullToAbsent) {
    return RuleExecutionsCompanion(
      id: Value(id),
      moduleId: Value(moduleId),
      ruleId: Value(ruleId),
      eventType: Value(eventType),
      entityType: Value(entityType),
      entityId: Value(entityId),
      eventPayloadJson: Value(eventPayloadJson),
      sourceExecutionId: sourceExecutionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceExecutionId),
      status: Value(status),
      message: message == null && nullToAbsent
          ? const Value.absent()
          : Value(message),
      automationDepth: Value(automationDepth),
      actionCount: Value(actionCount),
      createdAt: Value(createdAt),
    );
  }

  factory RuleExecution.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RuleExecution(
      id: serializer.fromJson<int>(json['id']),
      moduleId: serializer.fromJson<String>(json['moduleId']),
      ruleId: serializer.fromJson<String>(json['ruleId']),
      eventType: serializer.fromJson<String>(json['eventType']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      eventPayloadJson: serializer.fromJson<String>(json['eventPayloadJson']),
      sourceExecutionId: serializer.fromJson<int?>(json['sourceExecutionId']),
      status: serializer.fromJson<String>(json['status']),
      message: serializer.fromJson<String?>(json['message']),
      automationDepth: serializer.fromJson<int>(json['automationDepth']),
      actionCount: serializer.fromJson<int>(json['actionCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'moduleId': serializer.toJson<String>(moduleId),
      'ruleId': serializer.toJson<String>(ruleId),
      'eventType': serializer.toJson<String>(eventType),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'eventPayloadJson': serializer.toJson<String>(eventPayloadJson),
      'sourceExecutionId': serializer.toJson<int?>(sourceExecutionId),
      'status': serializer.toJson<String>(status),
      'message': serializer.toJson<String?>(message),
      'automationDepth': serializer.toJson<int>(automationDepth),
      'actionCount': serializer.toJson<int>(actionCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  RuleExecution copyWith({
    int? id,
    String? moduleId,
    String? ruleId,
    String? eventType,
    String? entityType,
    String? entityId,
    String? eventPayloadJson,
    Value<int?> sourceExecutionId = const Value.absent(),
    String? status,
    Value<String?> message = const Value.absent(),
    int? automationDepth,
    int? actionCount,
    DateTime? createdAt,
  }) => RuleExecution(
    id: id ?? this.id,
    moduleId: moduleId ?? this.moduleId,
    ruleId: ruleId ?? this.ruleId,
    eventType: eventType ?? this.eventType,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    eventPayloadJson: eventPayloadJson ?? this.eventPayloadJson,
    sourceExecutionId: sourceExecutionId.present
        ? sourceExecutionId.value
        : this.sourceExecutionId,
    status: status ?? this.status,
    message: message.present ? message.value : this.message,
    automationDepth: automationDepth ?? this.automationDepth,
    actionCount: actionCount ?? this.actionCount,
    createdAt: createdAt ?? this.createdAt,
  );
  RuleExecution copyWithCompanion(RuleExecutionsCompanion data) {
    return RuleExecution(
      id: data.id.present ? data.id.value : this.id,
      moduleId: data.moduleId.present ? data.moduleId.value : this.moduleId,
      ruleId: data.ruleId.present ? data.ruleId.value : this.ruleId,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      eventPayloadJson: data.eventPayloadJson.present
          ? data.eventPayloadJson.value
          : this.eventPayloadJson,
      sourceExecutionId: data.sourceExecutionId.present
          ? data.sourceExecutionId.value
          : this.sourceExecutionId,
      status: data.status.present ? data.status.value : this.status,
      message: data.message.present ? data.message.value : this.message,
      automationDepth: data.automationDepth.present
          ? data.automationDepth.value
          : this.automationDepth,
      actionCount: data.actionCount.present
          ? data.actionCount.value
          : this.actionCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RuleExecution(')
          ..write('id: $id, ')
          ..write('moduleId: $moduleId, ')
          ..write('ruleId: $ruleId, ')
          ..write('eventType: $eventType, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('eventPayloadJson: $eventPayloadJson, ')
          ..write('sourceExecutionId: $sourceExecutionId, ')
          ..write('status: $status, ')
          ..write('message: $message, ')
          ..write('automationDepth: $automationDepth, ')
          ..write('actionCount: $actionCount, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    moduleId,
    ruleId,
    eventType,
    entityType,
    entityId,
    eventPayloadJson,
    sourceExecutionId,
    status,
    message,
    automationDepth,
    actionCount,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RuleExecution &&
          other.id == this.id &&
          other.moduleId == this.moduleId &&
          other.ruleId == this.ruleId &&
          other.eventType == this.eventType &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.eventPayloadJson == this.eventPayloadJson &&
          other.sourceExecutionId == this.sourceExecutionId &&
          other.status == this.status &&
          other.message == this.message &&
          other.automationDepth == this.automationDepth &&
          other.actionCount == this.actionCount &&
          other.createdAt == this.createdAt);
}

class RuleExecutionsCompanion extends UpdateCompanion<RuleExecution> {
  final Value<int> id;
  final Value<String> moduleId;
  final Value<String> ruleId;
  final Value<String> eventType;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> eventPayloadJson;
  final Value<int?> sourceExecutionId;
  final Value<String> status;
  final Value<String?> message;
  final Value<int> automationDepth;
  final Value<int> actionCount;
  final Value<DateTime> createdAt;
  const RuleExecutionsCompanion({
    this.id = const Value.absent(),
    this.moduleId = const Value.absent(),
    this.ruleId = const Value.absent(),
    this.eventType = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.eventPayloadJson = const Value.absent(),
    this.sourceExecutionId = const Value.absent(),
    this.status = const Value.absent(),
    this.message = const Value.absent(),
    this.automationDepth = const Value.absent(),
    this.actionCount = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  RuleExecutionsCompanion.insert({
    this.id = const Value.absent(),
    required String moduleId,
    required String ruleId,
    required String eventType,
    required String entityType,
    required String entityId,
    this.eventPayloadJson = const Value.absent(),
    this.sourceExecutionId = const Value.absent(),
    required String status,
    this.message = const Value.absent(),
    this.automationDepth = const Value.absent(),
    this.actionCount = const Value.absent(),
    required DateTime createdAt,
  }) : moduleId = Value(moduleId),
       ruleId = Value(ruleId),
       eventType = Value(eventType),
       entityType = Value(entityType),
       entityId = Value(entityId),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<RuleExecution> custom({
    Expression<int>? id,
    Expression<String>? moduleId,
    Expression<String>? ruleId,
    Expression<String>? eventType,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? eventPayloadJson,
    Expression<int>? sourceExecutionId,
    Expression<String>? status,
    Expression<String>? message,
    Expression<int>? automationDepth,
    Expression<int>? actionCount,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (moduleId != null) 'module_id': moduleId,
      if (ruleId != null) 'rule_id': ruleId,
      if (eventType != null) 'event_type': eventType,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (eventPayloadJson != null) 'event_payload_json': eventPayloadJson,
      if (sourceExecutionId != null) 'source_execution_id': sourceExecutionId,
      if (status != null) 'status': status,
      if (message != null) 'message': message,
      if (automationDepth != null) 'automation_depth': automationDepth,
      if (actionCount != null) 'action_count': actionCount,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  RuleExecutionsCompanion copyWith({
    Value<int>? id,
    Value<String>? moduleId,
    Value<String>? ruleId,
    Value<String>? eventType,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? eventPayloadJson,
    Value<int?>? sourceExecutionId,
    Value<String>? status,
    Value<String?>? message,
    Value<int>? automationDepth,
    Value<int>? actionCount,
    Value<DateTime>? createdAt,
  }) {
    return RuleExecutionsCompanion(
      id: id ?? this.id,
      moduleId: moduleId ?? this.moduleId,
      ruleId: ruleId ?? this.ruleId,
      eventType: eventType ?? this.eventType,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      eventPayloadJson: eventPayloadJson ?? this.eventPayloadJson,
      sourceExecutionId: sourceExecutionId ?? this.sourceExecutionId,
      status: status ?? this.status,
      message: message ?? this.message,
      automationDepth: automationDepth ?? this.automationDepth,
      actionCount: actionCount ?? this.actionCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (moduleId.present) {
      map['module_id'] = Variable<String>(moduleId.value);
    }
    if (ruleId.present) {
      map['rule_id'] = Variable<String>(ruleId.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (eventPayloadJson.present) {
      map['event_payload_json'] = Variable<String>(eventPayloadJson.value);
    }
    if (sourceExecutionId.present) {
      map['source_execution_id'] = Variable<int>(sourceExecutionId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (automationDepth.present) {
      map['automation_depth'] = Variable<int>(automationDepth.value);
    }
    if (actionCount.present) {
      map['action_count'] = Variable<int>(actionCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RuleExecutionsCompanion(')
          ..write('id: $id, ')
          ..write('moduleId: $moduleId, ')
          ..write('ruleId: $ruleId, ')
          ..write('eventType: $eventType, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('eventPayloadJson: $eventPayloadJson, ')
          ..write('sourceExecutionId: $sourceExecutionId, ')
          ..write('status: $status, ')
          ..write('message: $message, ')
          ..write('automationDepth: $automationDepth, ')
          ..write('actionCount: $actionCount, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChangeOperationsTable extends ChangeOperations
    with TableInfo<$ChangeOperationsTable, ChangeOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChangeOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _counterMeta = const VerificationMeta(
    'counter',
  );
  @override
  late final GeneratedColumn<int> counter = GeneratedColumn<int>(
    'counter',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
    'synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceId,
    counter,
    entityType,
    entityId,
    action,
    payload,
    createdAt,
    synced,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'change_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChangeOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('counter')) {
      context.handle(
        _counterMeta,
        counter.isAcceptableOrUnknown(data['counter']!, _counterMeta),
      );
    } else if (isInserting) {
      context.missing(_counterMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('synced')) {
      context.handle(
        _syncedMeta,
        synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChangeOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChangeOperation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      counter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}counter'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      synced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}synced'],
      )!,
    );
  }

  @override
  $ChangeOperationsTable createAlias(String alias) {
    return $ChangeOperationsTable(attachedDatabase, alias);
  }
}

class ChangeOperation extends DataClass implements Insertable<ChangeOperation> {
  final String id;
  final String deviceId;
  final int counter;
  final String entityType;
  final String entityId;
  final String action;
  final String payload;
  final DateTime createdAt;
  final bool synced;
  const ChangeOperation({
    required this.id,
    required this.deviceId,
    required this.counter,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.payload,
    required this.createdAt,
    required this.synced,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['counter'] = Variable<int>(counter);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['action'] = Variable<String>(action);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['synced'] = Variable<bool>(synced);
    return map;
  }

  ChangeOperationsCompanion toCompanion(bool nullToAbsent) {
    return ChangeOperationsCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      counter: Value(counter),
      entityType: Value(entityType),
      entityId: Value(entityId),
      action: Value(action),
      payload: Value(payload),
      createdAt: Value(createdAt),
      synced: Value(synced),
    );
  }

  factory ChangeOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChangeOperation(
      id: serializer.fromJson<String>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      counter: serializer.fromJson<int>(json['counter']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      action: serializer.fromJson<String>(json['action']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      synced: serializer.fromJson<bool>(json['synced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'counter': serializer.toJson<int>(counter),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'action': serializer.toJson<String>(action),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'synced': serializer.toJson<bool>(synced),
    };
  }

  ChangeOperation copyWith({
    String? id,
    String? deviceId,
    int? counter,
    String? entityType,
    String? entityId,
    String? action,
    String? payload,
    DateTime? createdAt,
    bool? synced,
  }) => ChangeOperation(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    counter: counter ?? this.counter,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    action: action ?? this.action,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
    synced: synced ?? this.synced,
  );
  ChangeOperation copyWithCompanion(ChangeOperationsCompanion data) {
    return ChangeOperation(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      counter: data.counter.present ? data.counter.value : this.counter,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      action: data.action.present ? data.action.value : this.action,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      synced: data.synced.present ? data.synced.value : this.synced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChangeOperation(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('counter: $counter, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    deviceId,
    counter,
    entityType,
    entityId,
    action,
    payload,
    createdAt,
    synced,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChangeOperation &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.counter == this.counter &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.action == this.action &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.synced == this.synced);
}

class ChangeOperationsCompanion extends UpdateCompanion<ChangeOperation> {
  final Value<String> id;
  final Value<String> deviceId;
  final Value<int> counter;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> action;
  final Value<String> payload;
  final Value<DateTime> createdAt;
  final Value<bool> synced;
  final Value<int> rowid;
  const ChangeOperationsCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.counter = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.action = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.synced = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChangeOperationsCompanion.insert({
    required String id,
    required String deviceId,
    required int counter,
    required String entityType,
    required String entityId,
    required String action,
    required String payload,
    required DateTime createdAt,
    this.synced = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       deviceId = Value(deviceId),
       counter = Value(counter),
       entityType = Value(entityType),
       entityId = Value(entityId),
       action = Value(action),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<ChangeOperation> custom({
    Expression<String>? id,
    Expression<String>? deviceId,
    Expression<int>? counter,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? action,
    Expression<String>? payload,
    Expression<DateTime>? createdAt,
    Expression<bool>? synced,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (counter != null) 'counter': counter,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (action != null) 'action': action,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (synced != null) 'synced': synced,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChangeOperationsCompanion copyWith({
    Value<String>? id,
    Value<String>? deviceId,
    Value<int>? counter,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? action,
    Value<String>? payload,
    Value<DateTime>? createdAt,
    Value<bool>? synced,
    Value<int>? rowid,
  }) {
    return ChangeOperationsCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      counter: counter ?? this.counter,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      action: action ?? this.action,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      synced: synced ?? this.synced,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (counter.present) {
      map['counter'] = Variable<int>(counter.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChangeOperationsCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('counter: $counter, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('synced: $synced, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProjectsTable projects = $ProjectsTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $LabelsTable labels = $LabelsTable(this);
  late final $TaskLabelsTable taskLabels = $TaskLabelsTable(this);
  late final $ModuleInstallationsTable moduleInstallations =
      $ModuleInstallationsTable(this);
  late final $ModuleVersionsTable moduleVersions = $ModuleVersionsTable(this);
  late final $FieldDefinitionsTable fieldDefinitions = $FieldDefinitionsTable(
    this,
  );
  late final $FieldValuesTable fieldValues = $FieldValuesTable(this);
  late final $RuleExecutionsTable ruleExecutions = $RuleExecutionsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $ChangeOperationsTable changeOperations = $ChangeOperationsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    projects,
    tasks,
    labels,
    taskLabels,
    moduleInstallations,
    moduleVersions,
    fieldDefinitions,
    fieldValues,
    ruleExecutions,
    appSettings,
    changeOperations,
  ];
}

typedef $$ProjectsTableCreateCompanionBuilder = ProjectsCompanion Function({
  required String id,
  required String name,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<DateTime?> archivedAt,
  Value<int> rowid,
});
typedef $$ProjectsTableUpdateCompanionBuilder = ProjectsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> archivedAt,
  Value<int> rowid,
});

final class $$ProjectsTableReferences
    extends BaseReferences<_$AppDatabase, $ProjectsTable, Project> {
  $$ProjectsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TasksTable, List<Task>> _tasksRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tasks,
    aliasName: 'projects__id__tasks__project_id',
  );

  $$TasksTableProcessedTableManager get tasksRefs {
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.projectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_tasksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProjectsTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> tasksRefs(
    Expression<bool> Function($$TasksTableFilterComposer f) f,
  ) {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProjectsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  Expression<T> tasksRefs<T extends Object>(
    Expression<T> Function($$TasksTableAnnotationComposer a) f,
  ) {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProjectsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectsTable,
          Project,
          $$ProjectsTableFilterComposer,
          $$ProjectsTableOrderingComposer,
          $$ProjectsTableAnnotationComposer,
          $$ProjectsTableCreateCompanionBuilder,
          $$ProjectsTableUpdateCompanionBuilder,
          (Project, $$ProjectsTableReferences),
          Project,
          PrefetchHooks Function({bool tasksRefs})
        > {
  $$ProjectsTableTableManager(_$AppDatabase db, $ProjectsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProjectsTable, Project>(table),
                  $$ProjectsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({tasksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (tasksRefs) db.tasks],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (tasksRefs)
                    await $_getPrefetchedData<Project, $ProjectsTable, Task>(
                      currentTable: table,
                      referencedTable: $$ProjectsTableReferences
                          ._tasksRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ProjectsTableReferences(db, table, p0).tasksRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.projectId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ProjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectsTable,
      Project,
      $$ProjectsTableFilterComposer,
      $$ProjectsTableOrderingComposer,
      $$ProjectsTableAnnotationComposer,
      $$ProjectsTableCreateCompanionBuilder,
      $$ProjectsTableUpdateCompanionBuilder,
      (Project, $$ProjectsTableReferences),
      Project,
      PrefetchHooks Function({bool tasksRefs})
    >;
typedef $$TasksTableCreateCompanionBuilder = TasksCompanion Function({
  required String id,
  Value<String?> projectId,
  Value<String?> parentTaskId,
  required String title,
  Value<String> notes,
  Value<int> priority,
  Value<String?> dueDate,
  Value<String?> plannedDate,
  Value<DateTime?> completedAt,
  Value<DateTime?> archivedAt,
  Value<DateTime?> deletedAt,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$TasksTableUpdateCompanionBuilder = TasksCompanion Function({
  Value<String> id,
  Value<String?> projectId,
  Value<String?> parentTaskId,
  Value<String> title,
  Value<String> notes,
  Value<int> priority,
  Value<String?> dueDate,
  Value<String?> plannedDate,
  Value<DateTime?> completedAt,
  Value<DateTime?> archivedAt,
  Value<DateTime?> deletedAt,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

final class $$TasksTableReferences
    extends BaseReferences<_$AppDatabase, $TasksTable, Task> {
  $$TasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProjectsTable _projectIdTable(_$AppDatabase db) =>
      db.projects.createAlias('tasks__project_id__projects__id');

  $$ProjectsTableProcessedTableManager? get projectId {
    final $_column = $_itemColumn<String>('project_id');
    if ($_column == null) return null;
    final manager = $$ProjectsTableTableManager(
      $_db,
      $_db.projects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$TaskLabelsTable, List<TaskLabel>>
  _taskLabelsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.taskLabels,
    aliasName: 'tasks__id__task_labels__task_id',
  );

  $$TaskLabelsTableProcessedTableManager get taskLabelsRefs {
    final manager = $$TaskLabelsTableTableManager(
      $_db,
      $_db.taskLabels,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_taskLabelsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FieldValuesTable, List<FieldValue>>
  _fieldValuesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.fieldValues,
    aliasName: 'tasks__id__field_values__task_id',
  );

  $$FieldValuesTableProcessedTableManager get fieldValuesRefs {
    final manager = $$FieldValuesTableTableManager(
      $_db,
      $_db.fieldValues,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_fieldValuesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentTaskId => $composableBuilder(
    column: $table.parentTaskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plannedDate => $composableBuilder(
    column: $table.plannedDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableFilterComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> taskLabelsRefs(
    Expression<bool> Function($$TaskLabelsTableFilterComposer f) f,
  ) {
    final $$TaskLabelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskLabels,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskLabelsTableFilterComposer(
            $db: $db,
            $table: $db.taskLabels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> fieldValuesRefs(
    Expression<bool> Function($$FieldValuesTableFilterComposer f) f,
  ) {
    final $$FieldValuesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.fieldValues,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldValuesTableFilterComposer(
            $db: $db,
            $table: $db.fieldValues,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentTaskId => $composableBuilder(
    column: $table.parentTaskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plannedDate => $composableBuilder(
    column: $table.plannedDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableOrderingComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get parentTaskId => $composableBuilder(
    column: $table.parentTaskId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get plannedDate => $composableBuilder(
    column: $table.plannedDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ProjectsTableAnnotationComposer get projectId {
    final $$ProjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> taskLabelsRefs<T extends Object>(
    Expression<T> Function($$TaskLabelsTableAnnotationComposer a) f,
  ) {
    final $$TaskLabelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskLabels,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskLabelsTableAnnotationComposer(
            $db: $db,
            $table: $db.taskLabels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> fieldValuesRefs<T extends Object>(
    Expression<T> Function($$FieldValuesTableAnnotationComposer a) f,
  ) {
    final $$FieldValuesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.fieldValues,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldValuesTableAnnotationComposer(
            $db: $db,
            $table: $db.fieldValues,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TasksTable,
          Task,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (Task, $$TasksTableReferences),
          Task,
          PrefetchHooks Function({
            bool projectId,
            bool taskLabelsRefs,
            bool fieldValuesRefs,
          })
        > {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
                Value<String?> parentTaskId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String?> dueDate = const Value.absent(),
                Value<String?> plannedDate = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                projectId: projectId,
                parentTaskId: parentTaskId,
                title: title,
                notes: notes,
                priority: priority,
                dueDate: dueDate,
                plannedDate: plannedDate,
                completedAt: completedAt,
                archivedAt: archivedAt,
                deletedAt: deletedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> projectId = const Value.absent(),
                Value<String?> parentTaskId = const Value.absent(),
                required String title,
                Value<String> notes = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String?> dueDate = const Value.absent(),
                Value<String?> plannedDate = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                projectId: projectId,
                parentTaskId: parentTaskId,
                title: title,
                notes: notes,
                priority: priority,
                dueDate: dueDate,
                plannedDate: plannedDate,
                completedAt: completedAt,
                archivedAt: archivedAt,
                deletedAt: deletedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TasksTable, Task>(table),
                  $$TasksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                projectId = false,
                taskLabelsRefs = false,
                fieldValuesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (taskLabelsRefs) db.taskLabels,
                    if (fieldValuesRefs) db.fieldValues,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (projectId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.projectId,
                            referencedTable: $$TasksTableReferences
                                ._projectIdTable(db),
                            referencedColumn: $$TasksTableReferences
                                ._projectIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (taskLabelsRefs)
                        await $_getPrefetchedData<Task, $TasksTable, TaskLabel>(
                          currentTable: table,
                          referencedTable: $$TasksTableReferences
                              ._taskLabelsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TasksTableReferences(
                                db,
                                table,
                                p0,
                              ).taskLabelsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (fieldValuesRefs)
                        await $_getPrefetchedData<
                          Task,
                          $TasksTable,
                          FieldValue
                        >(
                          currentTable: table,
                          referencedTable: $$TasksTableReferences
                              ._fieldValuesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TasksTableReferences(
                                db,
                                table,
                                p0,
                              ).fieldValuesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TasksTable,
      Task,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (Task, $$TasksTableReferences),
      Task,
      PrefetchHooks Function({
        bool projectId,
        bool taskLabelsRefs,
        bool fieldValuesRefs,
      })
    >;
typedef $$LabelsTableCreateCompanionBuilder = LabelsCompanion Function({
  required String id,
  required String name,
  Value<int> color,
  Value<int> rowid,
});
typedef $$LabelsTableUpdateCompanionBuilder = LabelsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> color,
  Value<int> rowid,
});

final class $$LabelsTableReferences
    extends BaseReferences<_$AppDatabase, $LabelsTable, Label> {
  $$LabelsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TaskLabelsTable, List<TaskLabel>>
  _taskLabelsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.taskLabels,
    aliasName: 'labels__id__task_labels__label_id',
  );

  $$TaskLabelsTableProcessedTableManager get taskLabelsRefs {
    final manager = $$TaskLabelsTableTableManager(
      $_db,
      $_db.taskLabels,
    ).filter((f) => f.labelId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_taskLabelsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LabelsTableFilterComposer
    extends Composer<_$AppDatabase, $LabelsTable> {
  $$LabelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> taskLabelsRefs(
    Expression<bool> Function($$TaskLabelsTableFilterComposer f) f,
  ) {
    final $$TaskLabelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskLabels,
      getReferencedColumn: (t) => t.labelId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskLabelsTableFilterComposer(
            $db: $db,
            $table: $db.taskLabels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LabelsTableOrderingComposer
    extends Composer<_$AppDatabase, $LabelsTable> {
  $$LabelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LabelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LabelsTable> {
  $$LabelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  Expression<T> taskLabelsRefs<T extends Object>(
    Expression<T> Function($$TaskLabelsTableAnnotationComposer a) f,
  ) {
    final $$TaskLabelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskLabels,
      getReferencedColumn: (t) => t.labelId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskLabelsTableAnnotationComposer(
            $db: $db,
            $table: $db.taskLabels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LabelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LabelsTable,
          Label,
          $$LabelsTableFilterComposer,
          $$LabelsTableOrderingComposer,
          $$LabelsTableAnnotationComposer,
          $$LabelsTableCreateCompanionBuilder,
          $$LabelsTableUpdateCompanionBuilder,
          (Label, $$LabelsTableReferences),
          Label,
          PrefetchHooks Function({bool taskLabelsRefs})
        > {
  $$LabelsTableTableManager(_$AppDatabase db, $LabelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LabelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LabelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LabelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> color = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => LabelsCompanion(id: id, name: name, color: color, rowid: rowid),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> color = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LabelsCompanion.insert(
                id: id,
                name: name,
                color: color,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LabelsTable, Label>(table),
                  $$LabelsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskLabelsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (taskLabelsRefs) db.taskLabels],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (taskLabelsRefs)
                    await $_getPrefetchedData<Label, $LabelsTable, TaskLabel>(
                      currentTable: table,
                      referencedTable: $$LabelsTableReferences
                          ._taskLabelsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$LabelsTableReferences(db, table, p0).taskLabelsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.labelId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$LabelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LabelsTable,
      Label,
      $$LabelsTableFilterComposer,
      $$LabelsTableOrderingComposer,
      $$LabelsTableAnnotationComposer,
      $$LabelsTableCreateCompanionBuilder,
      $$LabelsTableUpdateCompanionBuilder,
      (Label, $$LabelsTableReferences),
      Label,
      PrefetchHooks Function({bool taskLabelsRefs})
    >;
typedef $$TaskLabelsTableCreateCompanionBuilder = TaskLabelsCompanion Function({
  required String taskId,
  required String labelId,
  Value<int> rowid,
});
typedef $$TaskLabelsTableUpdateCompanionBuilder = TaskLabelsCompanion Function({
  Value<String> taskId,
  Value<String> labelId,
  Value<int> rowid,
});

final class $$TaskLabelsTableReferences
    extends BaseReferences<_$AppDatabase, $TaskLabelsTable, TaskLabel> {
  $$TaskLabelsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TasksTable _taskIdTable(_$AppDatabase db) =>
      db.tasks.createAlias('task_labels__task_id__tasks__id');

  $$TasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $LabelsTable _labelIdTable(_$AppDatabase db) =>
      db.labels.createAlias('task_labels__label_id__labels__id');

  $$LabelsTableProcessedTableManager get labelId {
    final $_column = $_itemColumn<String>('label_id')!;

    final manager = $$LabelsTableTableManager(
      $_db,
      $_db.labels,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_labelIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TaskLabelsTableFilterComposer
    extends Composer<_$AppDatabase, $TaskLabelsTable> {
  $$TaskLabelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$TasksTableFilterComposer get taskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LabelsTableFilterComposer get labelId {
    final $$LabelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labelId,
      referencedTable: $db.labels,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabelsTableFilterComposer(
            $db: $db,
            $table: $db.labels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskLabelsTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskLabelsTable> {
  $$TaskLabelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$TasksTableOrderingComposer get taskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LabelsTableOrderingComposer get labelId {
    final $$LabelsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labelId,
      referencedTable: $db.labels,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabelsTableOrderingComposer(
            $db: $db,
            $table: $db.labels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskLabelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskLabelsTable> {
  $$TaskLabelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$TasksTableAnnotationComposer get taskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LabelsTableAnnotationComposer get labelId {
    final $$LabelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labelId,
      referencedTable: $db.labels,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabelsTableAnnotationComposer(
            $db: $db,
            $table: $db.labels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskLabelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaskLabelsTable,
          TaskLabel,
          $$TaskLabelsTableFilterComposer,
          $$TaskLabelsTableOrderingComposer,
          $$TaskLabelsTableAnnotationComposer,
          $$TaskLabelsTableCreateCompanionBuilder,
          $$TaskLabelsTableUpdateCompanionBuilder,
          (TaskLabel, $$TaskLabelsTableReferences),
          TaskLabel,
          PrefetchHooks Function({bool taskId, bool labelId})
        > {
  $$TaskLabelsTableTableManager(_$AppDatabase db, $TaskLabelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskLabelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskLabelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskLabelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> taskId = const Value.absent(),
                Value<String> labelId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskLabelsCompanion(
                taskId: taskId,
                labelId: labelId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String taskId,
                required String labelId,
                Value<int> rowid = const Value.absent(),
              }) => TaskLabelsCompanion.insert(
                taskId: taskId,
                labelId: labelId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TaskLabelsTable, TaskLabel>(table),
                  $$TaskLabelsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false, labelId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.taskId,
                        referencedTable: $$TaskLabelsTableReferences
                            ._taskIdTable(db),
                        referencedColumn: $$TaskLabelsTableReferences
                            ._taskIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (labelId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.labelId,
                        referencedTable: $$TaskLabelsTableReferences
                            ._labelIdTable(db),
                        referencedColumn: $$TaskLabelsTableReferences
                            ._labelIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TaskLabelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaskLabelsTable,
      TaskLabel,
      $$TaskLabelsTableFilterComposer,
      $$TaskLabelsTableOrderingComposer,
      $$TaskLabelsTableAnnotationComposer,
      $$TaskLabelsTableCreateCompanionBuilder,
      $$TaskLabelsTableUpdateCompanionBuilder,
      (TaskLabel, $$TaskLabelsTableReferences),
      TaskLabel,
      PrefetchHooks Function({bool taskId, bool labelId})
    >;
typedef $$ModuleInstallationsTableCreateCompanionBuilder =
    ModuleInstallationsCompanion Function({
      required String id,
      required String version,
      required String sourceJson,
      Value<bool> installed,
      Value<bool> enabled,
      Value<String> origin,
      Value<String?> publisherId,
      Value<String?> packageDigest,
      Value<String?> reviewId,
      Value<String?> signatureKeyId,
      required DateTime installedAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ModuleInstallationsTableUpdateCompanionBuilder =
    ModuleInstallationsCompanion Function({
      Value<String> id,
      Value<String> version,
      Value<String> sourceJson,
      Value<bool> installed,
      Value<bool> enabled,
      Value<String> origin,
      Value<String?> publisherId,
      Value<String?> packageDigest,
      Value<String?> reviewId,
      Value<String?> signatureKeyId,
      Value<DateTime> installedAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ModuleInstallationsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ModuleInstallationsTable,
          ModuleInstallation
        > {
  $$ModuleInstallationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$FieldDefinitionsTable, List<FieldDefinition>>
  _fieldDefinitionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.fieldDefinitions,
    aliasName: 'module_installations__id__field_definitions__module_id',
  );

  $$FieldDefinitionsTableProcessedTableManager get fieldDefinitionsRefs {
    final manager = $$FieldDefinitionsTableTableManager(
      $_db,
      $_db.fieldDefinitions,
    ).filter((f) => f.moduleId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _fieldDefinitionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ModuleInstallationsTableFilterComposer
    extends Composer<_$AppDatabase, $ModuleInstallationsTable> {
  $$ModuleInstallationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceJson => $composableBuilder(
    column: $table.sourceJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get installed => $composableBuilder(
    column: $table.installed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publisherId => $composableBuilder(
    column: $table.publisherId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packageDigest => $composableBuilder(
    column: $table.packageDigest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewId => $composableBuilder(
    column: $table.reviewId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signatureKeyId => $composableBuilder(
    column: $table.signatureKeyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> fieldDefinitionsRefs(
    Expression<bool> Function($$FieldDefinitionsTableFilterComposer f) f,
  ) {
    final $$FieldDefinitionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.fieldDefinitions,
      getReferencedColumn: (t) => t.moduleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldDefinitionsTableFilterComposer(
            $db: $db,
            $table: $db.fieldDefinitions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ModuleInstallationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ModuleInstallationsTable> {
  $$ModuleInstallationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceJson => $composableBuilder(
    column: $table.sourceJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get installed => $composableBuilder(
    column: $table.installed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publisherId => $composableBuilder(
    column: $table.publisherId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packageDigest => $composableBuilder(
    column: $table.packageDigest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewId => $composableBuilder(
    column: $table.reviewId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signatureKeyId => $composableBuilder(
    column: $table.signatureKeyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ModuleInstallationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ModuleInstallationsTable> {
  $$ModuleInstallationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get sourceJson => $composableBuilder(
    column: $table.sourceJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get installed =>
      $composableBuilder(column: $table.installed, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get publisherId => $composableBuilder(
    column: $table.publisherId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get packageDigest => $composableBuilder(
    column: $table.packageDigest,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reviewId =>
      $composableBuilder(column: $table.reviewId, builder: (column) => column);

  GeneratedColumn<String> get signatureKeyId => $composableBuilder(
    column: $table.signatureKeyId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> fieldDefinitionsRefs<T extends Object>(
    Expression<T> Function($$FieldDefinitionsTableAnnotationComposer a) f,
  ) {
    final $$FieldDefinitionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.fieldDefinitions,
      getReferencedColumn: (t) => t.moduleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldDefinitionsTableAnnotationComposer(
            $db: $db,
            $table: $db.fieldDefinitions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ModuleInstallationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ModuleInstallationsTable,
          ModuleInstallation,
          $$ModuleInstallationsTableFilterComposer,
          $$ModuleInstallationsTableOrderingComposer,
          $$ModuleInstallationsTableAnnotationComposer,
          $$ModuleInstallationsTableCreateCompanionBuilder,
          $$ModuleInstallationsTableUpdateCompanionBuilder,
          (ModuleInstallation, $$ModuleInstallationsTableReferences),
          ModuleInstallation,
          PrefetchHooks Function({bool fieldDefinitionsRefs})
        > {
  $$ModuleInstallationsTableTableManager(
    _$AppDatabase db,
    $ModuleInstallationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ModuleInstallationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ModuleInstallationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ModuleInstallationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String> sourceJson = const Value.absent(),
                Value<bool> installed = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String?> publisherId = const Value.absent(),
                Value<String?> packageDigest = const Value.absent(),
                Value<String?> reviewId = const Value.absent(),
                Value<String?> signatureKeyId = const Value.absent(),
                Value<DateTime> installedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModuleInstallationsCompanion(
                id: id,
                version: version,
                sourceJson: sourceJson,
                installed: installed,
                enabled: enabled,
                origin: origin,
                publisherId: publisherId,
                packageDigest: packageDigest,
                reviewId: reviewId,
                signatureKeyId: signatureKeyId,
                installedAt: installedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String version,
                required String sourceJson,
                Value<bool> installed = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String?> publisherId = const Value.absent(),
                Value<String?> packageDigest = const Value.absent(),
                Value<String?> reviewId = const Value.absent(),
                Value<String?> signatureKeyId = const Value.absent(),
                required DateTime installedAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ModuleInstallationsCompanion.insert(
                id: id,
                version: version,
                sourceJson: sourceJson,
                installed: installed,
                enabled: enabled,
                origin: origin,
                publisherId: publisherId,
                packageDigest: packageDigest,
                reviewId: reviewId,
                signatureKeyId: signatureKeyId,
                installedAt: installedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ModuleInstallationsTable, ModuleInstallation>(
                    table,
                  ),
                  $$ModuleInstallationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({fieldDefinitionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (fieldDefinitionsRefs) db.fieldDefinitions,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (fieldDefinitionsRefs)
                    await $_getPrefetchedData<
                      ModuleInstallation,
                      $ModuleInstallationsTable,
                      FieldDefinition
                    >(
                      currentTable: table,
                      referencedTable: $$ModuleInstallationsTableReferences
                          ._fieldDefinitionsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ModuleInstallationsTableReferences(
                            db,
                            table,
                            p0,
                          ).fieldDefinitionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.moduleId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ModuleInstallationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ModuleInstallationsTable,
      ModuleInstallation,
      $$ModuleInstallationsTableFilterComposer,
      $$ModuleInstallationsTableOrderingComposer,
      $$ModuleInstallationsTableAnnotationComposer,
      $$ModuleInstallationsTableCreateCompanionBuilder,
      $$ModuleInstallationsTableUpdateCompanionBuilder,
      (ModuleInstallation, $$ModuleInstallationsTableReferences),
      ModuleInstallation,
      PrefetchHooks Function({bool fieldDefinitionsRefs})
    >;
typedef $$ModuleVersionsTableCreateCompanionBuilder =
    ModuleVersionsCompanion Function({
      required String moduleId,
      required String version,
      required String sourceJson,
      Value<String> origin,
      Value<String?> publisherId,
      Value<String?> packageDigest,
      Value<String?> reviewId,
      Value<String?> signatureKeyId,
      required DateTime installedAt,
      Value<int> rowid,
    });
typedef $$ModuleVersionsTableUpdateCompanionBuilder =
    ModuleVersionsCompanion Function({
      Value<String> moduleId,
      Value<String> version,
      Value<String> sourceJson,
      Value<String> origin,
      Value<String?> publisherId,
      Value<String?> packageDigest,
      Value<String?> reviewId,
      Value<String?> signatureKeyId,
      Value<DateTime> installedAt,
      Value<int> rowid,
    });

class $$ModuleVersionsTableFilterComposer
    extends Composer<_$AppDatabase, $ModuleVersionsTable> {
  $$ModuleVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get moduleId => $composableBuilder(
    column: $table.moduleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceJson => $composableBuilder(
    column: $table.sourceJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publisherId => $composableBuilder(
    column: $table.publisherId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packageDigest => $composableBuilder(
    column: $table.packageDigest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewId => $composableBuilder(
    column: $table.reviewId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signatureKeyId => $composableBuilder(
    column: $table.signatureKeyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ModuleVersionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ModuleVersionsTable> {
  $$ModuleVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get moduleId => $composableBuilder(
    column: $table.moduleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceJson => $composableBuilder(
    column: $table.sourceJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publisherId => $composableBuilder(
    column: $table.publisherId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packageDigest => $composableBuilder(
    column: $table.packageDigest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewId => $composableBuilder(
    column: $table.reviewId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signatureKeyId => $composableBuilder(
    column: $table.signatureKeyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ModuleVersionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ModuleVersionsTable> {
  $$ModuleVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get moduleId =>
      $composableBuilder(column: $table.moduleId, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get sourceJson => $composableBuilder(
    column: $table.sourceJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get publisherId => $composableBuilder(
    column: $table.publisherId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get packageDigest => $composableBuilder(
    column: $table.packageDigest,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reviewId =>
      $composableBuilder(column: $table.reviewId, builder: (column) => column);

  GeneratedColumn<String> get signatureKeyId => $composableBuilder(
    column: $table.signatureKeyId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => column,
  );
}

class $$ModuleVersionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ModuleVersionsTable,
          ModuleVersion,
          $$ModuleVersionsTableFilterComposer,
          $$ModuleVersionsTableOrderingComposer,
          $$ModuleVersionsTableAnnotationComposer,
          $$ModuleVersionsTableCreateCompanionBuilder,
          $$ModuleVersionsTableUpdateCompanionBuilder,
          (
            ModuleVersion,
            BaseReferences<_$AppDatabase, $ModuleVersionsTable, ModuleVersion>,
          ),
          ModuleVersion,
          PrefetchHooks Function()
        > {
  $$ModuleVersionsTableTableManager(
    _$AppDatabase db,
    $ModuleVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ModuleVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ModuleVersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ModuleVersionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> moduleId = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String> sourceJson = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String?> publisherId = const Value.absent(),
                Value<String?> packageDigest = const Value.absent(),
                Value<String?> reviewId = const Value.absent(),
                Value<String?> signatureKeyId = const Value.absent(),
                Value<DateTime> installedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModuleVersionsCompanion(
                moduleId: moduleId,
                version: version,
                sourceJson: sourceJson,
                origin: origin,
                publisherId: publisherId,
                packageDigest: packageDigest,
                reviewId: reviewId,
                signatureKeyId: signatureKeyId,
                installedAt: installedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String moduleId,
                required String version,
                required String sourceJson,
                Value<String> origin = const Value.absent(),
                Value<String?> publisherId = const Value.absent(),
                Value<String?> packageDigest = const Value.absent(),
                Value<String?> reviewId = const Value.absent(),
                Value<String?> signatureKeyId = const Value.absent(),
                required DateTime installedAt,
                Value<int> rowid = const Value.absent(),
              }) => ModuleVersionsCompanion.insert(
                moduleId: moduleId,
                version: version,
                sourceJson: sourceJson,
                origin: origin,
                publisherId: publisherId,
                packageDigest: packageDigest,
                reviewId: reviewId,
                signatureKeyId: signatureKeyId,
                installedAt: installedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ModuleVersionsTable, ModuleVersion>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ModuleVersionsTable,
                    ModuleVersion
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ModuleVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ModuleVersionsTable,
      ModuleVersion,
      $$ModuleVersionsTableFilterComposer,
      $$ModuleVersionsTableOrderingComposer,
      $$ModuleVersionsTableAnnotationComposer,
      $$ModuleVersionsTableCreateCompanionBuilder,
      $$ModuleVersionsTableUpdateCompanionBuilder,
      (
        ModuleVersion,
        BaseReferences<_$AppDatabase, $ModuleVersionsTable, ModuleVersion>,
      ),
      ModuleVersion,
      PrefetchHooks Function()
    >;
typedef $$FieldDefinitionsTableCreateCompanionBuilder =
    FieldDefinitionsCompanion Function({
      required String key,
      required String moduleId,
      required String resourceId,
      required String label,
      required String type,
      Value<String> configJson,
      Value<bool> active,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$FieldDefinitionsTableUpdateCompanionBuilder =
    FieldDefinitionsCompanion Function({
      Value<String> key,
      Value<String> moduleId,
      Value<String> resourceId,
      Value<String> label,
      Value<String> type,
      Value<String> configJson,
      Value<bool> active,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$FieldDefinitionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $FieldDefinitionsTable, FieldDefinition> {
  $$FieldDefinitionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ModuleInstallationsTable _moduleIdTable(_$AppDatabase db) => db
      .moduleInstallations
      .createAlias('field_definitions__module_id__module_installations__id');

  $$ModuleInstallationsTableProcessedTableManager get moduleId {
    final $_column = $_itemColumn<String>('module_id')!;

    final manager = $$ModuleInstallationsTableTableManager(
      $_db,
      $_db.moduleInstallations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_moduleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$FieldValuesTable, List<FieldValue>>
  _fieldValuesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.fieldValues,
    aliasName: 'field_definitions__key__field_values__field_key',
  );

  $$FieldValuesTableProcessedTableManager get fieldValuesRefs {
    final manager = $$FieldValuesTableTableManager(
      $_db,
      $_db.fieldValues,
    ).filter((f) => f.fieldKey.key.sqlEquals($_itemColumn<String>('key')!));

    final cache = $_typedResult.readTableOrNull(_fieldValuesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FieldDefinitionsTableFilterComposer
    extends Composer<_$AppDatabase, $FieldDefinitionsTable> {
  $$FieldDefinitionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ModuleInstallationsTableFilterComposer get moduleId {
    final $$ModuleInstallationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.moduleId,
      referencedTable: $db.moduleInstallations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ModuleInstallationsTableFilterComposer(
            $db: $db,
            $table: $db.moduleInstallations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> fieldValuesRefs(
    Expression<bool> Function($$FieldValuesTableFilterComposer f) f,
  ) {
    final $$FieldValuesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.key,
      referencedTable: $db.fieldValues,
      getReferencedColumn: (t) => t.fieldKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldValuesTableFilterComposer(
            $db: $db,
            $table: $db.fieldValues,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FieldDefinitionsTableOrderingComposer
    extends Composer<_$AppDatabase, $FieldDefinitionsTable> {
  $$FieldDefinitionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ModuleInstallationsTableOrderingComposer get moduleId {
    final $$ModuleInstallationsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.moduleId,
          referencedTable: $db.moduleInstallations,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ModuleInstallationsTableOrderingComposer(
                $db: $db,
                $table: $db.moduleInstallations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$FieldDefinitionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FieldDefinitionsTable> {
  $$FieldDefinitionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ModuleInstallationsTableAnnotationComposer get moduleId {
    final $$ModuleInstallationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.moduleId,
          referencedTable: $db.moduleInstallations,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ModuleInstallationsTableAnnotationComposer(
                $db: $db,
                $table: $db.moduleInstallations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  Expression<T> fieldValuesRefs<T extends Object>(
    Expression<T> Function($$FieldValuesTableAnnotationComposer a) f,
  ) {
    final $$FieldValuesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.key,
      referencedTable: $db.fieldValues,
      getReferencedColumn: (t) => t.fieldKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldValuesTableAnnotationComposer(
            $db: $db,
            $table: $db.fieldValues,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FieldDefinitionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FieldDefinitionsTable,
          FieldDefinition,
          $$FieldDefinitionsTableFilterComposer,
          $$FieldDefinitionsTableOrderingComposer,
          $$FieldDefinitionsTableAnnotationComposer,
          $$FieldDefinitionsTableCreateCompanionBuilder,
          $$FieldDefinitionsTableUpdateCompanionBuilder,
          (FieldDefinition, $$FieldDefinitionsTableReferences),
          FieldDefinition,
          PrefetchHooks Function({bool moduleId, bool fieldValuesRefs})
        > {
  $$FieldDefinitionsTableTableManager(
    _$AppDatabase db,
    $FieldDefinitionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FieldDefinitionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FieldDefinitionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FieldDefinitionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> moduleId = const Value.absent(),
                Value<String> resourceId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> configJson = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FieldDefinitionsCompanion(
                key: key,
                moduleId: moduleId,
                resourceId: resourceId,
                label: label,
                type: type,
                configJson: configJson,
                active: active,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String moduleId,
                required String resourceId,
                required String label,
                required String type,
                Value<String> configJson = const Value.absent(),
                Value<bool> active = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => FieldDefinitionsCompanion.insert(
                key: key,
                moduleId: moduleId,
                resourceId: resourceId,
                label: label,
                type: type,
                configJson: configJson,
                active: active,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FieldDefinitionsTable, FieldDefinition>(table),
                  $$FieldDefinitionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({moduleId = false, fieldValuesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (fieldValuesRefs) db.fieldValues],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (moduleId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.moduleId,
                        referencedTable: $$FieldDefinitionsTableReferences
                            ._moduleIdTable(db),
                        referencedColumn: $$FieldDefinitionsTableReferences
                            ._moduleIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (fieldValuesRefs)
                    await $_getPrefetchedData<
                      FieldDefinition,
                      $FieldDefinitionsTable,
                      FieldValue
                    >(
                      currentTable: table,
                      referencedTable: $$FieldDefinitionsTableReferences
                          ._fieldValuesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$FieldDefinitionsTableReferences(
                            db,
                            table,
                            p0,
                          ).fieldValuesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.fieldKey == item.key),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$FieldDefinitionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FieldDefinitionsTable,
      FieldDefinition,
      $$FieldDefinitionsTableFilterComposer,
      $$FieldDefinitionsTableOrderingComposer,
      $$FieldDefinitionsTableAnnotationComposer,
      $$FieldDefinitionsTableCreateCompanionBuilder,
      $$FieldDefinitionsTableUpdateCompanionBuilder,
      (FieldDefinition, $$FieldDefinitionsTableReferences),
      FieldDefinition,
      PrefetchHooks Function({bool moduleId, bool fieldValuesRefs})
    >;
typedef $$FieldValuesTableCreateCompanionBuilder =
    FieldValuesCompanion Function({
      required String taskId,
      required String fieldKey,
      required String valueJson,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$FieldValuesTableUpdateCompanionBuilder =
    FieldValuesCompanion Function({
      Value<String> taskId,
      Value<String> fieldKey,
      Value<String> valueJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$FieldValuesTableReferences
    extends BaseReferences<_$AppDatabase, $FieldValuesTable, FieldValue> {
  $$FieldValuesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TasksTable _taskIdTable(_$AppDatabase db) =>
      db.tasks.createAlias('field_values__task_id__tasks__id');

  $$TasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $FieldDefinitionsTable _fieldKeyTable(_$AppDatabase db) => db
      .fieldDefinitions
      .createAlias('field_values__field_key__field_definitions__key');

  $$FieldDefinitionsTableProcessedTableManager get fieldKey {
    final $_column = $_itemColumn<String>('field_key')!;

    final manager = $$FieldDefinitionsTableTableManager(
      $_db,
      $_db.fieldDefinitions,
    ).filter((f) => f.key.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fieldKeyTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FieldValuesTableFilterComposer
    extends Composer<_$AppDatabase, $FieldValuesTable> {
  $$FieldValuesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$TasksTableFilterComposer get taskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FieldDefinitionsTableFilterComposer get fieldKey {
    final $$FieldDefinitionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fieldKey,
      referencedTable: $db.fieldDefinitions,
      getReferencedColumn: (t) => t.key,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldDefinitionsTableFilterComposer(
            $db: $db,
            $table: $db.fieldDefinitions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FieldValuesTableOrderingComposer
    extends Composer<_$AppDatabase, $FieldValuesTable> {
  $$FieldValuesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$TasksTableOrderingComposer get taskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FieldDefinitionsTableOrderingComposer get fieldKey {
    final $$FieldDefinitionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fieldKey,
      referencedTable: $db.fieldDefinitions,
      getReferencedColumn: (t) => t.key,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldDefinitionsTableOrderingComposer(
            $db: $db,
            $table: $db.fieldDefinitions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FieldValuesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FieldValuesTable> {
  $$FieldValuesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$TasksTableAnnotationComposer get taskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FieldDefinitionsTableAnnotationComposer get fieldKey {
    final $$FieldDefinitionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fieldKey,
      referencedTable: $db.fieldDefinitions,
      getReferencedColumn: (t) => t.key,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldDefinitionsTableAnnotationComposer(
            $db: $db,
            $table: $db.fieldDefinitions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FieldValuesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FieldValuesTable,
          FieldValue,
          $$FieldValuesTableFilterComposer,
          $$FieldValuesTableOrderingComposer,
          $$FieldValuesTableAnnotationComposer,
          $$FieldValuesTableCreateCompanionBuilder,
          $$FieldValuesTableUpdateCompanionBuilder,
          (FieldValue, $$FieldValuesTableReferences),
          FieldValue,
          PrefetchHooks Function({bool taskId, bool fieldKey})
        > {
  $$FieldValuesTableTableManager(_$AppDatabase db, $FieldValuesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FieldValuesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FieldValuesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FieldValuesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> taskId = const Value.absent(),
                Value<String> fieldKey = const Value.absent(),
                Value<String> valueJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FieldValuesCompanion(
                taskId: taskId,
                fieldKey: fieldKey,
                valueJson: valueJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String taskId,
                required String fieldKey,
                required String valueJson,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => FieldValuesCompanion.insert(
                taskId: taskId,
                fieldKey: fieldKey,
                valueJson: valueJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FieldValuesTable, FieldValue>(table),
                  $$FieldValuesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false, fieldKey = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.taskId,
                        referencedTable: $$FieldValuesTableReferences
                            ._taskIdTable(db),
                        referencedColumn: $$FieldValuesTableReferences
                            ._taskIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (fieldKey) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.fieldKey,
                        referencedTable: $$FieldValuesTableReferences
                            ._fieldKeyTable(db),
                        referencedColumn: $$FieldValuesTableReferences
                            ._fieldKeyTable(db)
                            .key,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FieldValuesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FieldValuesTable,
      FieldValue,
      $$FieldValuesTableFilterComposer,
      $$FieldValuesTableOrderingComposer,
      $$FieldValuesTableAnnotationComposer,
      $$FieldValuesTableCreateCompanionBuilder,
      $$FieldValuesTableUpdateCompanionBuilder,
      (FieldValue, $$FieldValuesTableReferences),
      FieldValue,
      PrefetchHooks Function({bool taskId, bool fieldKey})
    >;
typedef $$RuleExecutionsTableCreateCompanionBuilder =
    RuleExecutionsCompanion Function({
      Value<int> id,
      required String moduleId,
      required String ruleId,
      required String eventType,
      required String entityType,
      required String entityId,
      Value<String> eventPayloadJson,
      Value<int?> sourceExecutionId,
      required String status,
      Value<String?> message,
      Value<int> automationDepth,
      Value<int> actionCount,
      required DateTime createdAt,
    });
typedef $$RuleExecutionsTableUpdateCompanionBuilder =
    RuleExecutionsCompanion Function({
      Value<int> id,
      Value<String> moduleId,
      Value<String> ruleId,
      Value<String> eventType,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> eventPayloadJson,
      Value<int?> sourceExecutionId,
      Value<String> status,
      Value<String?> message,
      Value<int> automationDepth,
      Value<int> actionCount,
      Value<DateTime> createdAt,
    });

class $$RuleExecutionsTableFilterComposer
    extends Composer<_$AppDatabase, $RuleExecutionsTable> {
  $$RuleExecutionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get moduleId => $composableBuilder(
    column: $table.moduleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ruleId => $composableBuilder(
    column: $table.ruleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventPayloadJson => $composableBuilder(
    column: $table.eventPayloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceExecutionId => $composableBuilder(
    column: $table.sourceExecutionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get automationDepth => $composableBuilder(
    column: $table.automationDepth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get actionCount => $composableBuilder(
    column: $table.actionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RuleExecutionsTableOrderingComposer
    extends Composer<_$AppDatabase, $RuleExecutionsTable> {
  $$RuleExecutionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get moduleId => $composableBuilder(
    column: $table.moduleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruleId => $composableBuilder(
    column: $table.ruleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventPayloadJson => $composableBuilder(
    column: $table.eventPayloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceExecutionId => $composableBuilder(
    column: $table.sourceExecutionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get automationDepth => $composableBuilder(
    column: $table.automationDepth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get actionCount => $composableBuilder(
    column: $table.actionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RuleExecutionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RuleExecutionsTable> {
  $$RuleExecutionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get moduleId =>
      $composableBuilder(column: $table.moduleId, builder: (column) => column);

  GeneratedColumn<String> get ruleId =>
      $composableBuilder(column: $table.ruleId, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get eventPayloadJson => $composableBuilder(
    column: $table.eventPayloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sourceExecutionId => $composableBuilder(
    column: $table.sourceExecutionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<int> get automationDepth => $composableBuilder(
    column: $table.automationDepth,
    builder: (column) => column,
  );

  GeneratedColumn<int> get actionCount => $composableBuilder(
    column: $table.actionCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$RuleExecutionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RuleExecutionsTable,
          RuleExecution,
          $$RuleExecutionsTableFilterComposer,
          $$RuleExecutionsTableOrderingComposer,
          $$RuleExecutionsTableAnnotationComposer,
          $$RuleExecutionsTableCreateCompanionBuilder,
          $$RuleExecutionsTableUpdateCompanionBuilder,
          (
            RuleExecution,
            BaseReferences<_$AppDatabase, $RuleExecutionsTable, RuleExecution>,
          ),
          RuleExecution,
          PrefetchHooks Function()
        > {
  $$RuleExecutionsTableTableManager(
    _$AppDatabase db,
    $RuleExecutionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RuleExecutionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RuleExecutionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RuleExecutionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> moduleId = const Value.absent(),
                Value<String> ruleId = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> eventPayloadJson = const Value.absent(),
                Value<int?> sourceExecutionId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> message = const Value.absent(),
                Value<int> automationDepth = const Value.absent(),
                Value<int> actionCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => RuleExecutionsCompanion(
                id: id,
                moduleId: moduleId,
                ruleId: ruleId,
                eventType: eventType,
                entityType: entityType,
                entityId: entityId,
                eventPayloadJson: eventPayloadJson,
                sourceExecutionId: sourceExecutionId,
                status: status,
                message: message,
                automationDepth: automationDepth,
                actionCount: actionCount,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String moduleId,
                required String ruleId,
                required String eventType,
                required String entityType,
                required String entityId,
                Value<String> eventPayloadJson = const Value.absent(),
                Value<int?> sourceExecutionId = const Value.absent(),
                required String status,
                Value<String?> message = const Value.absent(),
                Value<int> automationDepth = const Value.absent(),
                Value<int> actionCount = const Value.absent(),
                required DateTime createdAt,
              }) => RuleExecutionsCompanion.insert(
                id: id,
                moduleId: moduleId,
                ruleId: ruleId,
                eventType: eventType,
                entityType: entityType,
                entityId: entityId,
                eventPayloadJson: eventPayloadJson,
                sourceExecutionId: sourceExecutionId,
                status: status,
                message: message,
                automationDepth: automationDepth,
                actionCount: actionCount,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RuleExecutionsTable, RuleExecution>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $RuleExecutionsTable,
                    RuleExecution
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RuleExecutionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RuleExecutionsTable,
      RuleExecution,
      $$RuleExecutionsTableFilterComposer,
      $$RuleExecutionsTableOrderingComposer,
      $$RuleExecutionsTableAnnotationComposer,
      $$RuleExecutionsTableCreateCompanionBuilder,
      $$RuleExecutionsTableUpdateCompanionBuilder,
      (
        RuleExecution,
        BaseReferences<_$AppDatabase, $RuleExecutionsTable, RuleExecution>,
      ),
      RuleExecution,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSetting>(table),
                  BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$ChangeOperationsTableCreateCompanionBuilder =
    ChangeOperationsCompanion Function({
      required String id,
      required String deviceId,
      required int counter,
      required String entityType,
      required String entityId,
      required String action,
      required String payload,
      required DateTime createdAt,
      Value<bool> synced,
      Value<int> rowid,
    });
typedef $$ChangeOperationsTableUpdateCompanionBuilder =
    ChangeOperationsCompanion Function({
      Value<String> id,
      Value<String> deviceId,
      Value<int> counter,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> action,
      Value<String> payload,
      Value<DateTime> createdAt,
      Value<bool> synced,
      Value<int> rowid,
    });

class $$ChangeOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $ChangeOperationsTable> {
  $$ChangeOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get counter => $composableBuilder(
    column: $table.counter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChangeOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChangeOperationsTable> {
  $$ChangeOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get counter => $composableBuilder(
    column: $table.counter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChangeOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChangeOperationsTable> {
  $$ChangeOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get counter =>
      $composableBuilder(column: $table.counter, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);
}

class $$ChangeOperationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChangeOperationsTable,
          ChangeOperation,
          $$ChangeOperationsTableFilterComposer,
          $$ChangeOperationsTableOrderingComposer,
          $$ChangeOperationsTableAnnotationComposer,
          $$ChangeOperationsTableCreateCompanionBuilder,
          $$ChangeOperationsTableUpdateCompanionBuilder,
          (
            ChangeOperation,
            BaseReferences<
              _$AppDatabase,
              $ChangeOperationsTable,
              ChangeOperation
            >,
          ),
          ChangeOperation,
          PrefetchHooks Function()
        > {
  $$ChangeOperationsTableTableManager(
    _$AppDatabase db,
    $ChangeOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChangeOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChangeOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChangeOperationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> counter = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> synced = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChangeOperationsCompanion(
                id: id,
                deviceId: deviceId,
                counter: counter,
                entityType: entityType,
                entityId: entityId,
                action: action,
                payload: payload,
                createdAt: createdAt,
                synced: synced,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String deviceId,
                required int counter,
                required String entityType,
                required String entityId,
                required String action,
                required String payload,
                required DateTime createdAt,
                Value<bool> synced = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChangeOperationsCompanion.insert(
                id: id,
                deviceId: deviceId,
                counter: counter,
                entityType: entityType,
                entityId: entityId,
                action: action,
                payload: payload,
                createdAt: createdAt,
                synced: synced,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChangeOperationsTable, ChangeOperation>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChangeOperationsTable,
                    ChangeOperation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChangeOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChangeOperationsTable,
      ChangeOperation,
      $$ChangeOperationsTableFilterComposer,
      $$ChangeOperationsTableOrderingComposer,
      $$ChangeOperationsTableAnnotationComposer,
      $$ChangeOperationsTableCreateCompanionBuilder,
      $$ChangeOperationsTableUpdateCompanionBuilder,
      (
        ChangeOperation,
        BaseReferences<_$AppDatabase, $ChangeOperationsTable, ChangeOperation>,
      ),
      ChangeOperation,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db, _db.projects);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$LabelsTableTableManager get labels =>
      $$LabelsTableTableManager(_db, _db.labels);
  $$TaskLabelsTableTableManager get taskLabels =>
      $$TaskLabelsTableTableManager(_db, _db.taskLabels);
  $$ModuleInstallationsTableTableManager get moduleInstallations =>
      $$ModuleInstallationsTableTableManager(_db, _db.moduleInstallations);
  $$ModuleVersionsTableTableManager get moduleVersions =>
      $$ModuleVersionsTableTableManager(_db, _db.moduleVersions);
  $$FieldDefinitionsTableTableManager get fieldDefinitions =>
      $$FieldDefinitionsTableTableManager(_db, _db.fieldDefinitions);
  $$FieldValuesTableTableManager get fieldValues =>
      $$FieldValuesTableTableManager(_db, _db.fieldValues);
  $$RuleExecutionsTableTableManager get ruleExecutions =>
      $$RuleExecutionsTableTableManager(_db, _db.ruleExecutions);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$ChangeOperationsTableTableManager get changeOperations =>
      $$ChangeOperationsTableTableManager(_db, _db.changeOperations);
}
