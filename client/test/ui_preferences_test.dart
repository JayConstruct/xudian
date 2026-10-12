import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/ui_preferences.dart';
import 'package:task_app/data/app_database.dart';

Future<ScriptPackage> _package(String id, {bool ui = true}) async =>
    ScriptPackage.verify(
      await ScriptPackage.build(
        {
          'formatVersion': 3,
          'manifest': {
            'id': id,
            'version': '1.0.0',
            'hostApi': '^1.12.0',
            'dataVersion': 1,
            'permissions': [if (ui) 'ui'],
          },
          'entryPoint': 'main.js',
          'collections': [],
          'pages': [],
          'services': [
            for (final kind in ['query', 'command'])
              {
                'id': kind,
                'major': 1,
                'kind': kind,
                'handler': 'write',
                'input': {'type': 'object'},
                'output': {'type': 'object'},
              },
          ],
        },
        {
          'main.js': '''
import {ui} from '@xudian/sdk';
export function read(args){ return ui.preferences.get(args.key); }
export function write(args){ return ui.preferences.set(args.key,args.value); }
export function forge(args){ return globalThis.__host('ui.preferences.set',args); }
export function notify(args){ return ui.notify(args); }
export function showCode(args){ return ui.showCode(args); }
''',
        },
      ),
      allowUnsignedLocal: true,
    );

void main() {
  late AppDatabase database;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(database);
    directory = await Directory.systemTemp.createTemp('ui-preferences-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    for (final id in ['test.first', 'test.second', 'test.noaccess']) {
      await host.install(await _package(id, ui: id != 'test.noaccess'));
    }
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await database.close();
    await directory.delete(recursive: true);
  });
  Future<Object?> read(String id) =>
      host.invokePage(id, 'read', {'key': 'gallery.pinned'});
  Future<Object?> write(Object? value, {String id = 'test.first'}) =>
      host.invokePage(id, 'write', {'key': 'gallery.pinned', 'value': value});

  test(
    'preference reads and successful writes invalidate only caller UI scope',
    () async {
      final firstScope = uiPreferencesReadDependency('test.first');
      final secondScope = uiPreferencesReadDependency('test.second');
      Set<String>? reads;
      await host.invokePage('test.first', 'read', {
        'key': 'gallery.pinned',
      }, onReads: (value) => reads = value);
      expect(reads, {firstScope});
      final records = await store.sql('SELECT * FROM host_records');
      final operations = await store.sql('SELECT * FROM host_operations');
      final outbox = await store.sql('SELECT * FROM host_outbox');
      final published = <Set<String>>[];
      final subscription = store.changes.stream.listen(published.add);
      addTearDown(subscription.cancel);
      await write(['button']);
      await Future<void>.delayed(Duration.zero);
      expect(published, [
        {firstScope},
      ]);
      expect(await read('test.first'), ['button']);
      await write(['date'], id: 'test.second');
      await Future<void>.delayed(Duration.zero);
      expect(published, [
        {firstScope},
        {secondScope},
      ]);
      await expectLater(write(List.filled(300, true)), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(published, [
        {firstScope},
        {secondScope},
      ]);
      await write(null);
      await Future<void>.delayed(Duration.zero);
      expect(published.last, {firstScope});
      expect(await read('test.first'), isNull);
      expect(await store.sql('SELECT * FROM host_records'), records);
      expect(await store.sql('SELECT * FROM host_operations'), operations);
      expect(await store.sql('SELECT * FROM host_outbox'), outbox);
    },
  );

  test(
    'preferences are isolated, persist across lifecycle, and erase with data',
    () async {
      final records = await store.sql('SELECT * FROM host_records');
      expect(await write(['button', 'date']), ['button', 'date']);
      expect(await read('test.second'), isNull);
      expect(await read('test.first'), ['button', 'date']);
      await host.close();
      // Simulate an existing schema-2 installation opening with the new host.
      host = ModuleHost(store: store, directory: directory);
      await host.initialize();
      expect(await read('test.first'), ['button', 'date']);
      await host.disable('test.first');
      await host.enable('test.first');
      expect(await read('test.first'), ['button', 'date']);
      await host.uninstall('test.first');
      await host.install(await _package('test.first'));
      expect(await read('test.first'), ['button', 'date']);
      expect(await store.sql('SELECT * FROM host_records'), records);
      await host.uninstall('test.first', deleteData: true);
      expect(
        await store.sql('SELECT * FROM host_ui_preferences WHERE module_id=?', [
          'test.first',
        ]),
        isEmpty,
      );
    },
  );

  test('UI preferences reject unprivileged, preview, service and cross-module access', () async {
    await expectLater(write(['button'], id: 'test.noaccess'), throwsStateError);
    await expectLater(
      host.invokePage('test.first', 'forge', {
        'key': 'gallery.pinned',
        'value': ['button'],
        'moduleId': 'test.second',
      }),
      throwsStateError,
    );
    final actor = host.instances['test.first']!.actor;
    for (final query in [true, false]) {
      await expectLater(
        query
            ? host.query(actor, const ServiceRef('test.first', 'query', 1), {
                'key': 'gallery.pinned',
                'value': ['button'],
              })
            : host.prepare(
                actor,
                const ServiceRef('test.first', 'command', 1),
                {
                  'key': 'gallery.pinned',
                  'value': ['button'],
                },
              ),
        throwsStateError,
      );
    }
    host.preview = true;
    await expectLater(read('test.first'), throwsStateError);
    await expectLater(write(['button']), throwsStateError);
    host.preview = false;
    expect(await read('test.first'), isNull);
  });

  test(
    'invalid or oversized preferences preserve the previous value',
    () async {
      await write(['button']);
      Object? deep = 'leaf';
      for (var i = 0; i < 10; i++) {
        deep = [deep];
      }
      for (final value in [
        deep,
        List.filled(300, true),
        List.filled(3, '中' * 3000),
      ]) {
        await expectLater(write(value), throwsStateError);
        expect(await read('test.first'), ['button']);
      }
      await expectLater(
        host.invokePage('test.first', 'write', {
          'key': '../another',
          'value': true,
        }),
        throwsStateError,
      );
      await write(null);
      expect(await read('test.first'), isNull);
    },
  );

  test('notifications validate and forward real UI interaction', () async {
    final calls = <Map<String, Object?>>[];
    host.interaction = (actor, method, args) async {
      expect(actor.moduleId, 'test.first');
      expect(method, 'ui.notify');
      calls.add(args);
      return null;
    };
    await host.invokePage('test.first', 'notify', {'message': '已固定'});
    expect(calls.single, {'message': '已固定', 'kind': 'info', 'duration': 3000});
    await expectLater(
      host.invokePage('test.first', 'notify', {'message': '中' * 201}),
      throwsStateError,
    );
    await expectLater(
      host.invokePage('test.noaccess', 'notify', {'message': '不允许'}),
      throwsStateError,
    );
    host.preview = true;
    await expectLater(
      host.invokePage('test.first', 'notify', {'message': '不允许'}),
      throwsStateError,
    );
    host.preview = false;
    expect(calls, hasLength(1));
  });

  test(
    'code preview validates bounded sections and requires UI workflow',
    () async {
      final calls = <Map<String, Object?>>[];
      host.interaction = (_, method, args) async {
        expect(method, 'ui.showCode');
        calls.add(args);
        return null;
      };
      final valid = {
        'title': '调用方式',
        'sections': [
          {'title': '调用', 'code': "await ui.notify({message: '完成'});"},
        ],
      };
      await host.invokePage('test.first', 'showCode', valid);
      expect(calls.single, valid);
      for (final invalid in [
        {...valid, 'sections': []},
        {...valid, 'moduleId': 'test.second'},
        {
          ...valid,
          'sections': [
            {'title': '调用', 'code': 'a' * 100001},
          ],
        },
        {
          ...valid,
          'sections': [
            {'title': '调用', 'code': '   '},
          ],
        },
      ]) {
        await expectLater(
          host.invokePage('test.first', 'showCode', invalid),
          throwsStateError,
        );
      }
      await expectLater(
        host.invokePage('test.noaccess', 'showCode', valid),
        throwsStateError,
      );
      host.preview = true;
      await expectLater(
        host.invokePage('test.first', 'showCode', valid),
        throwsStateError,
      );
      host.preview = false;
      expect(calls, hasLength(1));
      expect(await store.sql('SELECT * FROM host_operations'), isEmpty);
    },
  );
}
