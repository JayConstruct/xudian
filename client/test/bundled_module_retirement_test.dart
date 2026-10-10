import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/bundled_module_retirement.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('retired-bundle-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<ScriptPackage> package(String id, {List<String> depends = const []}) =>
      ScriptPackage.build(
        {
          'formatVersion': 3,
          'manifest': {
            'id': id,
            'version': '1.0.0',
            'hostApi': '^1.0.0',
            'dataVersion': 1,
            'permissions': [],
            'dependencies': depends,
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
        {'main.js': 'export function render(){return {};}'},
      ).then((bytes) => ScriptPackage.verify(bytes, allowUnsignedLocal: true));

  Future<void> addRecord(String id) async {
    final actor = host.instances[id]!.actor;
    await db.customStatement(
      'INSERT INTO host_records(module_id,space,collection,id,value,revision) '
      'VALUES(?,?,?,?,?,?)',
      [
        id,
        actor.space,
        'notes',
        'n',
        jsonEncode({'id': 'n', 'text': '保留'}),
        1,
      ],
    );
  }

  test(
    'withdrawn defaults uninstall without deleting shared data or history',
    () async {
      await host.install(await package('test.tasks'));
      final retired = await package('test.view', depends: ['test.tasks']);
      await host.install(retired);
      await host.install(
        await package('test.extension', depends: ['test.view']),
      );
      await addRecord('test.tasks');
      await addRecord('test.view');
      final records = await store.sql(
        'SELECT * FROM host_records ORDER BY module_id',
      );
      final packages = await store.sql(
        'SELECT * FROM host_packages ORDER BY module_id',
      );

      await retireBundledModules(host, ['test.view', 'test.view']);

      expect(host.instances.keys, contains('test.tasks'));
      expect(host.instances.keys, isNot(contains('test.view')));
      expect(host.instances.keys, isNot(contains('test.extension')));
      final row = (await store.sql(
        'SELECT installed,enabled FROM host_installations WHERE module_id=?',
        ['test.view'],
      )).single;
      expect(row, {'installed': 0, 'enabled': 0});
      expect(
        await store.sql('SELECT * FROM host_records ORDER BY module_id'),
        records,
      );
      expect(
        await store.sql('SELECT * FROM host_packages ORDER BY module_id'),
        packages,
      );
      expect(
        await File('${directory.path}/${retired.packageDigest}.xmodule')
            .exists(),
        isTrue,
      );

      await host.close();
      host = ModuleHost(store: store, directory: directory);
      await host.initialize();
      await retireBundledModules(host, ['test.view']);
      expect(host.instances.keys, isNot(contains('test.view')));
      expect(host.instances.keys, contains('test.tasks'));
      expect(
        await store.sql('SELECT * FROM host_records ORDER BY module_id'),
        records,
      );
    },
  );

  test('one-time withdrawal respects a later explicit reinstall', () async {
    final retired = await package('test.view');
    await host.install(retired);
    await addRecord('test.view');
    await retireBundledModules(host, ['test.view']);
    await host.install(retired);
    await retireBundledModules(host, ['test.view']);
    expect(host.instances.keys, contains('test.view'));
    final activeRecords = await store.sql(
      'SELECT value FROM host_records WHERE module_id=? AND space=?',
      ['test.view', host.instances['test.view']!.actor.space],
    );
    expect(activeRecords, hasLength(1));
    expect(jsonDecode(activeRecords.single['value'] as String), {
      'id': 'n',
      'text': '保留',
    });
  });

  test(
    'fresh installs do not manufacture withdrawn installation rows',
    () async {
      await retireBundledModules(host, ['test.absent']);
      expect(await store.sql('SELECT * FROM host_installations'), isEmpty);
      expect(await store.sql('SELECT * FROM host_packages'), isEmpty);
      await host.install(await package('test.absent'));
      await retireBundledModules(host, ['test.absent']);
      expect(host.instances.keys, contains('test.absent'));
    },
  );
}
