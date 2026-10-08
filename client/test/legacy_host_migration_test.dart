import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/legacy_converter.dart';
import 'package:task_app/core/module_host/legacy_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory dir;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    dir = await Directory.systemTemp.createTemp('legacy-v3-');
    host = ModuleHost(store: store, directory: dir);
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<void> tasks() async {
    await host.install(
      await ScriptPackage.verify(
        await File('../dist/modules/app.tasks.xmodule').readAsBytes(),
        allowUnsignedLocal: true,
      ),
    );
  }

  test('legacy data migration preserves ids, states, dates, logs, counters and repeats once', () async {
    final now = DateTime.utc(2026, 10, 1, 12, 13, 14);
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p',
            name: '项目',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 't',
            title: '旧任务',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.customStatement(
      "INSERT INTO app_settings VALUES('device_id','device')",
    );
    await db.customStatement(
      "INSERT INTO app_settings VALUES('operation_counter','42')",
    );
    await host.initialize();
    await tasks();
    final actor = host.instances['app.tasks']!.actor,
        row = object(await store.get(actor, 'tasks', 't'));
    expect(row['id'], 't');
    expect(row['title'], '旧任务');
    expect(row['createdAt'], now.toIso8601String());
    await migrateLegacyData(store);
    expect(await store.query(actor, 'tasks', {}), hasLength(1));
    expect(await store.sql('SELECT * FROM host_operations'), isEmpty);
    expect(
      (await store.sql(
        "SELECT value FROM app_settings WHERE key='operation_counter'",
      )).single['value'],
      '42',
    );
    expect((await db.select(db.tasks).get()).single.title, '旧任务');
  });
  test('complete legacy sample preserves relational data, extension state, retry history and provenance', () async {
    final at = DateTime.utc(2026, 10, 1, 12, 13, 14),
        stamp = at.millisecondsSinceEpoch ~/ 1000;
    final legacy = {
      'formatVersion': 1,
      'manifest': {
        'id': 'example.archive',
        'version': '1.0.0',
        'coreApi': '1',
        'permissions': ['fields.write'],
      },
      'fields': [
        {'id': 'subject', 'label': '科目', 'type': 'text'},
      ],
    };
    await db.customStatement(
      'INSERT INTO module_installations(id,version,source_json,installed,enabled,origin,publisher_id,package_digest,review_id,signature_key_id,installed_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        'example.archive',
        '1.0.0',
        jsonEncode(legacy),
        1,
        0,
        'local',
        null,
        'original-digest',
        null,
        null,
        stamp,
        stamp,
      ],
    );
    await db.customStatement(
      'INSERT INTO module_versions(module_id,version,source_json,origin,package_digest,installed_at) VALUES(?,?,?,?,?,?)',
      [
        'example.archive',
        '1.0.0',
        jsonEncode(legacy),
        'local',
        'original-digest',
        stamp,
      ],
    );
    await db.customStatement('INSERT INTO projects VALUES(?,?,?,?,?)', [
      'p',
      '旧项目',
      stamp,
      stamp,
      null,
    ]);
    await db.customStatement(
      'INSERT INTO tasks(id,project_id,parent_task_id,title,notes,priority,due_date,planned_date,completed_at,archived_at,deleted_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        't',
        'p',
        null,
        '旧任务',
        '备注',
        3,
        '2026-10-10',
        '2026-10-08',
        stamp,
        null,
        null,
        stamp,
        stamp,
      ],
    );
    await db.customStatement('INSERT INTO labels VALUES(?,?,?)', [
      'label',
      '学习',
      0xff486da4,
    ]);
    await db.customStatement('INSERT INTO task_labels VALUES(?,?)', [
      't',
      'label',
    ]);
    await db.customStatement(
      'INSERT INTO field_definitions VALUES(?,?,?,?,?,?,?,?,?)',
      [
        'example.archive:subject',
        'example.archive',
        'subject',
        '科目',
        'text',
        '{}',
        0,
        stamp,
        stamp,
      ],
    );
    await db.customStatement('INSERT INTO field_values VALUES(?,?,?,?)', [
      't',
      'example.archive:subject',
      jsonEncode('高数'),
      stamp,
    ]);
    await db.customStatement(
      'INSERT INTO rule_executions(id,module_id,rule_id,event_type,entity_type,entity_id,event_payload_json,source_execution_id,status,message,automation_depth,action_count,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        1,
        'example.archive',
        'r',
        'task.updated',
        'task',
        't',
        '{}',
        null,
        'failure',
        '原失败',
        2,
        1,
        stamp,
      ],
    );
    await db.customStatement(
      'INSERT INTO rule_executions(id,module_id,rule_id,event_type,entity_type,entity_id,event_payload_json,source_execution_id,status,message,automation_depth,action_count,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        2,
        'example.archive',
        'r',
        'task.updated',
        'task',
        't',
        '{}',
        1,
        'success',
        null,
        2,
        1,
        stamp,
      ],
    );
    await db.customStatement(
      'INSERT INTO change_operations(id,device_id,counter,entity_type,entity_id,action,payload,created_at,synced) VALUES(?,?,?,?,?,?,?,?,?)',
      ['op', 'device', 42, 'task', 't', 'create', '{}', stamp, 0],
    );
    await db.customStatement('INSERT INTO app_settings VALUES(?,?)', [
      'device_id',
      'device',
    ]);
    await db.customStatement('INSERT INTO app_settings VALUES(?,?)', [
      'operation_counter',
      '42',
    ]);
    await db.customStatement('INSERT INTO app_settings VALUES(?,?)', [
      'ai.endpoint',
      'https://example.com/v1',
    ]);
    await db.customStatement('INSERT INTO app_settings VALUES(?,?)', [
      'ai.model',
      'sample-model',
    ]);
    await db.customStatement('INSERT INTO app_settings VALUES(?,?)', [
      'ai.assistant.history',
      jsonEncode({
        'messages': [
          {'role': 'user', 'text': '旧对话'},
        ],
        'audit': [
          {'id': 'audit'},
        ],
        'interrupted': true,
      }),
    ]);
    final layout = {
      'narrow': {
        'mounts': {
          'unknown': {
            'taskId': 't',
            'values': {'future': true},
          },
        },
      },
      'wide': {
        'mounts': {
          'unknown-wide': {'projectId': 'p'},
        },
      },
      'futureSetting': true,
    };
    await db.customStatement('INSERT INTO app_settings VALUES(?,?)', [
      'ui.layout',
      jsonEncode(layout),
    ]);
    final tables = [
      'tasks',
      'projects',
      'labels',
      'task_labels',
      'field_definitions',
      'field_values',
      'rule_executions',
      'module_installations',
      'module_versions',
      'change_operations',
    ];
    final before = {
      for (final table in tables)
        table: await store.sql('SELECT * FROM $table'),
    };
    await host.initialize();
    await tasks();
    await migrateLegacyInstallations(host);
    for (final table in tables) {
      expect(
        await store.sql('SELECT * FROM $table'),
        before[table],
        reason: table,
      );
    }
    final actor = host.instances['app.tasks']!.actor,
        task = object(await store.get(actor, 'tasks', 't'));
    expect(task['notes'], '备注');
    expect(task['priority'], 3);
    expect(task['completedAt'], at.toIso8601String());
    expect(await store.query(actor, 'labels', {}), hasLength(1));
    expect(await store.query(actor, 'taskLabels', {}), hasLength(1));
    final field = object(
      jsonDecode(
        (await store.sql(
              "SELECT value FROM host_records WHERE module_id='example.archive' AND collection='fieldValues' AND space='legacy-v1'",
            )).single['value']
            as String,
      ),
    );
    expect(field['entity'], {
      'moduleId': 'app.tasks',
      'collection': 'tasks',
      'id': 't',
    });
    expect(field['value'], '高数');
    final retry = object(
      jsonDecode(
        (await store.sql(
              "SELECT value FROM host_records WHERE collection='ruleExecutions' AND id='2' AND space='legacy-v1'",
            )).single['value']
            as String,
      ),
    );
    expect(retry['sourceExecutionId'], 1);
    expect(host.failures, isEmpty);
    final converted = (await store.sql(
      "SELECT * FROM host_installations WHERE module_id='example.archive'",
    )).single;
    expect(converted['enabled'], 0);
    final history = await host.automationHistory('example.archive');
    expect(history, hasLength(2));
    expect(
      history.firstWhere((record) => record['id'] == 'legacy:2')['retry_of'],
      'legacy:1',
    );
    final savedLayout = jsonDecode(
      (await store.sql("SELECT value FROM app_settings WHERE key='ui.layout'"))
              .single['value']
          as String,
    );
    expect(savedLayout['futureSetting'], true);
    expect(
      savedLayout['narrow']['mounts']['unknown']['values']['future'],
      true,
    );
    expect(
      savedLayout['narrow']['mounts']['unknown']['values']['entities'][0]['id'],
      't',
    );
    final count = (await store.sql(
      'SELECT COUNT(*) AS count FROM host_records',
    )).single['count'];
    await migrateLegacyData(store);
    await migrateLegacyInstallations(host);
    expect(
      (await store.sql('SELECT COUNT(*) AS count FROM host_records'))
          .single['count'],
      count,
    );
    expect(await store.sql('SELECT * FROM host_operations'), isEmpty);
  });
  final source = <String, Object?>{
    'formatVersion': 1,
    'manifest': {
      'id': 'example.plan',
      'version': '1.0.0',
      'coreApi': '1',
      'requiresCapabilities': ['tasks.command'],
      'permissions': ['tasks.write', 'fields.write'],
    },
    'fields': [
      {'id': 'subject', 'label': '科目', 'type': 'text'},
    ],
    'templates': [
      {
        'id': 'exam',
        'title': '考试计划',
        'project': {'name': '期末复习'},
        'tasks': [
          {
            'key': 'root',
            'title': '制定计划',
            'fields': {'subject': '高数'},
          },
          {'key': 'child', 'title': '第一章', 'parentKey': 'root'},
        ],
      },
    ],
  };
  test(
    'legacy conversion is deterministic and embeds immutable original source',
    () async {
      final a = await convertLegacyModule(source),
          b = await convertLegacyModule(source);
      expect(a.packageDigest, b.packageDigest);
      expect(jsonDecode(utf8.decode(a.files['legacy.json']!)), source);
      expect(a.definition['formatVersion'], 3);
      expect(a.origin, 'local');
    },
  );
  test('script template reads staged task/project results and commits one transaction', () async {
    await host.initialize();
    await tasks();
    await host.install(await convertLegacyModule(source));
    final actor = host.instances['example.plan']!.actor;
    final p = await host.prepare(
      actor,
      const ServiceRef('example.plan', 'template.exam', 1),
      {'templateId': 'exam', 'parameters': {}},
    );
    expect(p.writes, hasLength(4));
    expect(
      await store.query(host.instances['app.tasks']!.actor, 'tasks', {}),
      isEmpty,
    );
    host.review(p.id, actor);
    await host.commit(actor, p.id);
    final all = await store.query(
      host.instances['app.tasks']!.actor,
      'tasks',
      {},
    );
    expect(all, hasLength(2));
    expect(object(all.first)['projectId'], object(p.result)['projectId']);
    expect(await store.query(actor, 'fieldValues', {}), hasLength(1));
  });
  test('invalid last template step leaves every participating collection untouched', () async {
    await host.initialize();
    await tasks();
    final invalid = {
      ...source,
      'templates': [
        {
          'id': 'exam',
          'title': '坏模板',
          'project': {'name': '不应保存'},
          'tasks': [
            {'key': 'ok', 'title': '前序任务'},
            {
              'key': 'bad',
              'title': '后续任务',
              'fields': {'subject': 123},
            },
          ],
        },
      ],
    };
    await host.install(await convertLegacyModule(invalid));
    final actor = host.instances['example.plan']!.actor;
    await expectLater(
      host.prepare(
        actor,
        const ServiceRef('example.plan', 'template.exam', 1),
        {'templateId': 'exam', 'parameters': {}},
      ),
      throwsStateError,
    );
    expect(
      await store.query(host.instances['app.tasks']!.actor, 'tasks', {}),
      isEmpty,
    );
    expect(
      await store.query(host.instances['app.tasks']!.actor, 'projects', {}),
      isEmpty,
    );
    expect(await store.sql('SELECT * FROM host_operations'), isEmpty);
  });
  test(
    'legacy task rule runs after commit with inherited loop trace',
    () async {
      await host.initialize();
      await tasks();
      final rule = {
        ...source,
        'fields': [],
        'templates': [],
        'rules': [
          {
            'id': 'title',
            'event': 'task.updated',
            'actions': [
              {
                'command': 'task.updateFields',
                'payload': {
                  'id': r'$event.entityId',
                  'changes': {'title': '规则标题'},
                },
              },
            ],
          },
        ],
      };
      await host.install(await convertLegacyModule(rule));
      final actor = host.instances['app.tasks']!.actor;
      var p = await host.prepare(
        actor,
        const ServiceRef('app.tasks', 'task.create', 1),
        {'title': '初始'},
      );
      host.review(p.id, actor);
      final result = object(await host.commit(actor, p.id));
      p = await host.prepare(
        actor,
        const ServiceRef('app.tasks', 'task.updateFields', 1),
        {
          'id': result['id'],
          'changes': {'title': '触发规则'},
        },
      );
      host.review(p.id, actor);
      await host.commit(actor, p.id);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await host.drainAutomation();
      expect(
        object(
          await store.get(actor, 'tasks', result['id'] as String),
        )['title'],
        '规则标题',
      );
      final log = await store.sql('SELECT * FROM host_automation');
      expect(log.any((e) => e['status'] == 'success'), true);
      expect(log.any((e) => e['status'] == 'skipped'), true);
    },
  );
  test('field-conditioned rules read extension values without a cross-module execution deadlock', () async {
    await host.initialize();
    await tasks();
    await host.install(
      await convertLegacyModule({
        ...source,
        'templates': [],
        'rules': [
          {
            'id': 'field-rule',
            'event': 'task.updated',
            'condition': {'field': 'fields.subject', 'op': 'eq', 'value': '高数'},
            'actions': [
              {
                'command': 'task.updateFields',
                'payload': {
                  'id': r'$event.entityId',
                  'changes': {'title': '字段触发'},
                },
              },
            ],
          },
        ],
      }),
    );
    final taskActor = host.instances['app.tasks']!.actor,
        extension = host.instances['example.plan']!.actor;
    var plan = await host.prepare(
      taskActor,
      const ServiceRef('app.tasks', 'task.create', 1),
      {'title': '原始标题'},
    );
    host.review(plan.id, taskActor);
    final taskId = object(await host.commit(taskActor, plan.id))['id'];
    plan = await host.prepare(
      extension,
      const ServiceRef('example.plan', 'fields.set', 1),
      {'taskId': taskId, 'fieldKey': 'subject', 'value': '高数'},
    );
    host.review(plan.id, extension);
    await host.commit(extension, plan.id);
    await host.drainAutomation();
    expect(
      object(await store.get(taskActor, 'tasks', taskId as String))['title'],
      '字段触发',
    );
    expect(
      (await store.sql('SELECT * FROM host_automation'))
          .any((row) => row['status'] == 'failure'),
      false,
    );
  });
}
