import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'host_batch_install_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late Directory directory;
  late ModuleHost host;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('worker-recovery-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<ScriptInstance> install() async {
    await host.install(
      await fixtures.candidate(
        'test.recovery',
        script: '''
let count = 0;
export function loop(){while(true){}}
export function render(){return {tree:{type:'text',text:String(++count)}};}
''',
      ),
    );
    return host.instances['test.recovery']!;
  }

  test(
    'activation loads both independent engines before publishing the module',
    () async {
      final bothStarted = Completer<void>();
      var initializations = 0;
      host.nativeServices['test.startup'] = NativeHostService(
        {
          'id': 'test.startup',
          'kind': 'query',
          'input': {'type': 'object'},
          'output': {'type': 'object'},
        },
        (_, _, _) async {
          final index = ++initializations;
          if (initializations == 2) bothStarted.complete();
          await bothStarted.future;
          return {'index': index};
        },
      );
      await host.install(
        await fixtures.candidate(
          'test.parallel',
          permissions: ['services.query:app.host/test.startup@1'],
          script: """
import {services} from '@xudian/sdk';
const initial = await services.query({moduleId:'app.host',serviceId:'test.startup',majorVersion:1},{});
export function value(){return initial;}
""",
        ),
      );
      final instance = host.instances['test.parallel']!;
      final values = await Future.wait([
        instance.worker.invoke('value', {}),
        instance.workflow.invoke('value', {}),
      ]);
      expect(initializations, 2);
      expect(values.map((v) => object(v)['index']).toSet(), {1, 2});
    },
  );

  test(
    'a fatal page call fails once and reopening reloads only its engine',
    () async {
      final instance = await install();
      final old = instance.workflow;
      final computation = instance.worker;
      var cancelled = false;
      final events = StreamController<void>(onCancel: () => cancelled = true);
      addTearDown(events.close);
      instance.subscriptions['old-listener'] = events.stream.listen((_) {});
      await expectLater(
        host.invokePage('test.recovery', 'loop', {}),
        throwsStateError,
      );
      expect(old.closed, isTrue);
      expect(
        instance.workflow,
        same(old),
        reason: 'Failed operations are not replayed',
      );
      final result = object(
        await host.invokePage('test.recovery', 'render', {}),
      );
      expect(object(result['tree'])['text'], '1');
      expect(instance.workflow, isNot(same(old)));
      expect(instance.worker, same(computation));
      expect(cancelled, isTrue);
      expect(instance.subscriptions, isEmpty);
      expect(
        object(
          object(await host.invokePage('test.recovery', 'render', {}))['tree'],
        )['text'],
        '2',
      );
    },
  );

  test(
    'queued computations share a replacement without replaying the failure',
    () async {
      final instance = await install();
      final old = instance.worker;
      final workflow = instance.workflow;
      await expectLater(instance.run('loop', {}, null), throwsStateError);
      expect(old.closed, isTrue);
      final results = await Future.wait([
        instance.run('render', {}, null),
        instance.run('render', {}, null),
      ]);
      expect(results.map((r) => object(object(r)['tree'])['text']), ['1', '2']);
      expect(instance.worker, isNot(same(old)));
      expect(instance.workflow, same(workflow));
      await host.disable('test.recovery');
      await expectLater(instance.run('render', {}, null), throwsStateError);
      expect(
        instance.worker.closed,
        isTrue,
        reason: 'Disabled modules cannot restart',
      );
    },
  );
}
