import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('page-read-tracking-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  Future<void> install(
    String id,
    String script, {
    List<Object?> services = const [],
    List<String> permissions = const [],
  }) async {
    final definition = <String, Object?>{
      'formatVersion': 3,
      'manifest': {
        'id': id,
        'version': '1.0.0',
        'hostApi': '^1.6.0',
        'dataVersion': 1,
        'permissions': permissions,
        'dependencies': [],
      },
      'entryPoint': 'main.js',
      'collections': [
        {
          'id': 'records',
          'schema': {'type': 'object'},
        },
      ],
      'services': services,
      'pages': [],
    };
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(definition, {'main.js': script}),
        allowUnsignedLocal: true,
      ),
    );
  }

  Map<String, Object?> queryService(
    String id, {
    Map<String, Object?>? extensionFor,
  }) => {
    'id': id,
    'major': 1,
    'kind': 'query',
    'handler': id,
    'input': {'type': 'object'},
    'output': {'type': 'object'},
    'extensionFor': ?extensionFor,
  };

  test('direct data reads are captured per serialized invocation and failures do not publish', () async {
    await install(
      'test.direct',
      "import {data} from '@xudian/sdk'; export async function render(input){if(input.fail)throw Error('failed');if(input.read)await data.query('records',{});return {tree:{type:'text',text:'ok'}};}",
    );
    Set<String>? first, second;
    final reads = host.invokePage('test.direct', 'render', {
      'read': true,
    }, onReads: (value) => first = value);
    final noReads = host.invokePage(
      'test.direct',
      'render',
      {},
      onReads: (value) => second = value,
    );
    await Future.wait([reads, noReads]);
    expect(first, {'test.direct'});
    expect(second, isEmpty);
    expect(() => first!.add('unsafe'), throwsUnsupportedError);
    var called = false;
    await expectLater(
      host.invokePage('test.direct', 'render', {
        'fail': true,
      }, onReads: (_) => called = true),
      throwsStateError,
    );
    expect(called, isFalse);
  });

  test(
    'service queries include nested providers actual read participants',
    () async {
      await install(
        'test.source',
        "import {data} from '@xudian/sdk';export async function read(){return {items:await data.query('records',{})};}",
        services: [queryService('read')],
      );
      await install(
        'test.provider',
        "import {services} from '@xudian/sdk';export async function read(){return services.query({moduleId:'test.source',serviceId:'read',majorVersion:1},{});}",
        services: [queryService('read')],
        permissions: ['services.query:test.source/read@1'],
      );
      await install(
        'test.consumer',
        "import {services} from '@xudian/sdk';export async function render(){return services.query({moduleId:'test.provider',serviceId:'read',majorVersion:1},{});}",
        permissions: ['services.query:test.provider/read@1'],
      );
      Set<String>? reads;
      await host.invokePage(
        'test.consumer',
        'render',
        {},
        onReads: (value) => reads = value,
      );
      expect(
        reads,
        containsAll(['test.consumer', 'test.provider', 'test.source']),
      );
      expect(
        host.instances.values.every(
          (i) => i.session == null && i.pageReads == null,
        ),
        isTrue,
      );
    },
  );

  test('extension reads include provider while unrelated installed module is excluded', () async {
    await install(
      'test.extension',
      "import {data} from '@xudian/sdk';export async function fields(){await data.query('records',{});return {definitions:[],values:{}};}",
      services: [
        queryService(
          'fields',
          extensionFor: {'moduleId': 'test.consumer', 'collection': 'records'},
        ),
      ],
    );
    await install('test.unrelated', "export function render(){return {};}");
    await install(
      'test.consumer',
      "import {extensions} from '@xudian/sdk';export async function render(){return extensions.query({moduleId:'test.consumer',collection:'records',id:'1'});}",
      permissions: ['extensions.query'],
    );
    Set<String>? reads;
    await host.invokePage(
      'test.consumer',
      'render',
      {},
      onReads: (value) => reads = value,
    );
    expect(reads, contains('test.extension'));
    expect(reads, isNot(contains('test.unrelated')));
  });
}
