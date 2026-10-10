import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/legacy_migration.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

void main() {
  const id = 'app.import.zhengfang';
  const neighbor = 'app.import.zhengfang.extra';
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('host-erasure-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<ScriptPackage> package(
    String moduleId, {
    String version = '1.0.0',
    List<String> dependencies = const [],
  }) async => ScriptPackage.verify(
    await ScriptPackage.build(
      {
        'formatVersion': 3,
        'manifest': {
          'id': moduleId,
          'name': '正方教务导入（通用）',
          'version': version,
          'hostApi': '^1.0.0',
          'dataVersion': 1,
          'permissions': [],
          'dependencies': dependencies,
        },
        'entryPoint': 'main.js',
        'collections': [
          {
            'id': 'notes',
            'schema': {'type': 'object'},
          },
        ],
        'pages': [],
        'services': [],
      },
      {'main.js': 'export function ready(){return true;}'},
    ),
    allowUnsignedLocal: true,
  );

  Future<void> record(String moduleId) => db.customStatement(
    'INSERT INTO host_records(module_id,space,collection,id,value,revision) '
    'VALUES(?,?,?,?,?,1)',
    [
      moduleId,
      host.instances[moduleId]!.actor.space,
      'notes',
      'n',
      '{"id":"n"}',
    ],
  );

  Future<void> legacy(String moduleId) async {
    await db.customStatement(
      'INSERT INTO module_installations(id,version,source_json,installed,enabled,installed_at,updated_at) VALUES(?,?,?,0,0,1,1)',
      [moduleId, '1.0.0', '{}'],
    );
    await db.customStatement(
      'INSERT INTO module_versions(module_id,version,source_json,installed_at) VALUES(?,?,?,1)',
      [moduleId, '1.0.0', '{}'],
    );
    await db.customStatement(
      'INSERT INTO field_definitions(key,module_id,resource_id,label,type,created_at,updated_at) VALUES(?,?,?,?,?,1,1)',
      ['$moduleId:subject', moduleId, 'subject', '科目', 'text'],
    );
    await db.customStatement('INSERT INTO host_meta(key,value) VALUES(?,?)', [
      'legacy-source:$moduleId:1.0.0',
      '{}',
    ]);
  }

  test('erase an already uninstalled legacy module removes versions and archives, preserves shared data', () async {
    final original = await package(id);
    final updated = await package(id, version: '1.1.0');
    final kept = await package(neighbor);
    await host.install(original);
    await record(id);
    await host.install(updated);
    await host.install(kept);
    await record(neighbor);
    await host.install(await package('app.schedule'));
    await record('app.schedule');
    await legacy(id);
    await legacy(neighbor);
    await db.customStatement(
      'INSERT INTO tasks(id,title,created_at,updated_at) VALUES(?,?,1,1)',
      ['t', '共享任务'],
    );
    for (final moduleId in [id, neighbor]) {
      await db.customStatement(
        'INSERT INTO field_values(task_id,field_key,value_json,updated_at) VALUES(?,?,?,1)',
        ['t', '$moduleId:subject', jsonEncode('高数')],
      );
    }
    await db.customStatement(
      'INSERT INTO host_operations VALUES(?,?,?,?,?,?,?,?,?,?,?)',
      [
        'op',
        'plan',
        id,
        'app.schedule',
        'notes',
        'n',
        null,
        '{}',
        'now',
        'device',
        1,
      ],
    );
    await db.customStatement('INSERT INTO host_commits VALUES(?,?,?,?,?)', [
      'plan',
      id,
      'request',
      'fingerprint',
      '{}',
    ]);
    await db.customStatement(
      'INSERT INTO host_operations VALUES(?,?,?,?,?,?,?,?,?,?,?)',
      [
        'target-op',
        'target-plan',
        neighbor,
        id,
        'notes',
        'n',
        null,
        '{}',
        'now',
        'device',
        2,
      ],
    );
    await db.customStatement('INSERT INTO host_commits VALUES(?,?,?,?,?)', [
      'target-plan',
      neighbor,
      'target-request',
      'fingerprint',
      '{"private":"erased"}',
    ]);
    await db.customStatement('INSERT INTO host_commits VALUES(?,?,?,?,?)', [
      'kept-plan',
      neighbor,
      'kept-request',
      'fingerprint',
      '{}',
    ]);
    final shared = await store.sql(
      'SELECT * FROM host_records WHERE module_id IN (?,?) ORDER BY module_id,space,id',
      [neighbor, 'app.schedule'],
    );
    final neighborPackages = await store.sql(
      'SELECT * FROM host_packages WHERE module_id=?',
      [neighbor],
    );
    await host.uninstall(id);
    expect(
      (await store.sql(
        'SELECT installed FROM host_installations WHERE module_id=?',
        [id],
      )).single['installed'],
      0,
    );
    expect(
      await store.sql('SELECT * FROM host_packages WHERE module_id=?', [id]),
      hasLength(2),
    );
    String? credentialsDeleted;
    host.onDeleteData = (moduleId) async => credentialsDeleted = moduleId;

    await host.uninstall(id, cascade: true, deleteData: true);

    expect(credentialsDeleted, id);
    for (final table in [
      'host_installations',
      'host_packages',
      'host_records',
      'host_collections',
      'host_indexes',
      'host_snapshots',
      'host_operations',
      'host_automation',
      'host_outbox',
      'module_versions',
      'field_definitions',
      'rule_executions',
    ]) {
      expect(
        await store.sql('SELECT * FROM $table WHERE module_id=?', [id]),
        isEmpty,
        reason: table,
      );
    }
    expect(
      await store.sql('SELECT * FROM host_operations WHERE caller=?', [id]),
      isEmpty,
    );
    expect(
      await store.sql('SELECT * FROM host_commits WHERE caller=?', [id]),
      isEmpty,
    );
    expect(
      await store.sql('SELECT * FROM host_commits WHERE plan_id=?', [
        'target-plan',
      ]),
      isEmpty,
    );
    expect(
      await store.sql('SELECT * FROM host_commits WHERE plan_id=?', [
        'kept-plan',
      ]),
      hasLength(1),
    );
    expect(
      await store.sql('SELECT * FROM module_installations WHERE id=?', [id]),
      isEmpty,
    );
    expect(
      await store.sql('SELECT * FROM field_values WHERE field_key=?', [
        '$id:subject',
      ]),
      isEmpty,
    );
    expect(
      await store.sql('SELECT * FROM host_meta WHERE key=?', [
        'legacy-source:$id:1.0.0',
      ]),
      isEmpty,
    );
    expect(await host.wasErased(id), isTrue);
    expect(
      await store.sql(
        'SELECT * FROM host_records WHERE module_id IN (?,?) ORDER BY module_id,space,id',
        [neighbor, 'app.schedule'],
      ),
      shared,
    );
    expect(
      await store.sql('SELECT * FROM host_packages WHERE module_id=?', [
        neighbor,
      ]),
      neighborPackages,
    );
    expect(
      await store.sql('SELECT * FROM field_values WHERE field_key=?', [
        '$neighbor:subject',
      ]),
      hasLength(1),
    );
    expect(
      await store.sql('SELECT * FROM tasks WHERE id=?', ['t']),
      hasLength(1),
    );
    for (final source in [original, updated]) {
      expect(
        await File('${directory.path}/${source.packageDigest}.xmodule')
            .exists(),
        isFalse,
      );
    }
    expect(
      await File('${directory.path}/${kept.packageDigest}.xmodule').exists(),
      isTrue,
    );

    await host.close();
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    await migrateLegacyInstallations(host);
    expect(host.instances, isNot(contains(id)));
    expect(
      await store.sql('SELECT * FROM host_installations WHERE module_id=?', [
        id,
      ]),
      isEmpty,
    );
    await host.install(original);
    expect(await store.query(host.instances[id]!.actor, 'notes', {}), isEmpty);
  });

  test(
    'migration retries skip erased identities even if old archives reappear',
    () async {
      await host.install(await package(id));
      await host.uninstall(id, deleteData: true);
      await legacy(id);
      await db.customStatement(
        "DELETE FROM host_meta WHERE key IN ('legacy-data-v1','legacy-packages-v1')",
      );
      await migrateLegacyData(store);
      await migrateLegacyInstallations(host);
      expect(
        await store.sql('SELECT * FROM host_records WHERE module_id=?', [id]),
        isEmpty,
      );
      expect(
        await store.sql('SELECT * FROM host_packages WHERE module_id=?', [id]),
        isEmpty,
      );
      expect(
        await store.sql('SELECT * FROM host_installations WHERE module_id=?', [
          id,
        ]),
        isEmpty,
      );
      expect(host.failures, isEmpty);
    },
  );

  test(
    'erase cascades deactivation but preserves dependents and their data',
    () async {
      await host.install(await package(id));
      await host.install(await package(neighbor, dependencies: [id]));
      await record(neighbor);
      await host.uninstall(id, cascade: true, deleteData: true);
      expect(host.instances, isEmpty);
      expect(
        (await store.sql(
          'SELECT installed,enabled FROM host_installations WHERE module_id=?',
          [neighbor],
        )).single,
        {'installed': 1, 'enabled': 0},
      );
      expect(
        await store.sql('SELECT * FROM host_records WHERE module_id=?', [
          neighbor,
        ]),
        hasLength(1),
      );
      expect(
        await store.sql('SELECT * FROM host_packages WHERE module_id=?', [
          neighbor,
        ]),
        hasLength(1),
      );
    },
  );

  test('failed erasure rolls back data and keeps package files', () async {
    final source = await package(id);
    await host.install(source);
    await record(id);
    await legacy(id);
    await db.customStatement(
      "CREATE TRIGGER fail_erasure BEFORE DELETE ON module_versions BEGIN SELECT RAISE(ABORT,'test failure'); END",
    );
    await expectLater(
      host.uninstall(id, deleteData: true),
      throwsA(isA<Exception>()),
    );
    expect(await host.wasErased(id), isFalse);
    expect(
      await store.sql('SELECT * FROM host_records WHERE module_id=?', [id]),
      hasLength(1),
    );
    expect(
      await store.sql('SELECT * FROM host_installations WHERE module_id=?', [
        id,
      ]),
      hasLength(1),
    );
    expect(
      await store.sql('SELECT * FROM host_packages WHERE module_id=?', [id]),
      hasLength(1),
    );
    expect(
      await File('${directory.path}/${source.packageDigest}.xmodule').exists(),
      isTrue,
    );
  });
}
