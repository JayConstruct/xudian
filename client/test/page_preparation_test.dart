import 'dart:async';
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
  late List<String> interactions;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('page-preparation-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    interactions = [];
    host.interaction = (_, method, _) async {
      interactions.add(method);
      return null;
    };
    final bytes = await ScriptPackage.build(
      {
        'formatVersion': 3,
        'manifest': {
          'id': 'test.prepared',
          'version': '1.0.0',
          'hostApi': '^1.20.0',
          'dataVersion': 1,
          'permissions': ['ui', 'services.query:test.prepared/read@1'],
          'dependencies': [],
        },
        'entryPoint': 'main.js',
        'services': [
          {
            'id': 'read',
            'major': 1,
            'kind': 'query',
            'handler': 'read',
            'input': {'type': 'object'},
            'output': {'type': 'string'},
          },
        ],
        'collections': [
          {
            'id': 'items',
            'schema': {
              'type': 'object',
              'required': ['id'],
              'properties': {
                'id': {'type': 'string'},
              },
            },
          },
        ],
        'pages': [
          {
            'id': 'test.prepared.home',
            'title': 'Preparation',
            'handler': 'render',
          },
        ],
      },
      {
        'main.js': r'''
import {ui,clock,ids,http,data,services} from '@xudian/sdk';
let renders=0;
export async function read({effect}={}) {
  if(effect==='ids') await ids.new();
  if(effect==='notify') await ui.notify({message:'nested'});
  if(effect==='command') await services.prepare({moduleId:'test.prepared',serviceId:'write',majorVersion:1},{});
  return clock.today();
}
export async function render({context={},state={}}={}) {
  renders++;
  switch(context.effect) {
    case 'notify': await ui.notify({message:'visible'}); break;
    case 'dialog': await ui.dialog({title:'Dialog',fields:[]}); break;
    case 'navigate': await ui.navigate('test.prepared.home'); break;
    case 'preferences': await ui.preferences.set('draft','changed'); break;
    case 'ids': await ids.new(); break;
    case 'http': await http.request({url:'https://example.com'}); break;
    case 'subscribe': await data.watch('items',{},()=>{}); break;
    case 'command': await services.prepare({moduleId:'test.prepared',serviceId:'write',majorVersion:1},{}); break;
  }
  const value=await services.query({moduleId:'test.prepared',serviceId:'read',majorVersion:1},{effect:context.nestedEffect});
  return {state,tree:{type:'text',text:value},renders};
}
''',
      },
    );
    await host.install(
      await ScriptPackage.verify(bytes, allowUnsignedLocal: true),
    );
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  test(
    'read-only preparation allows queries and tracks dependencies',
    () async {
      host.clockNow = () => DateTime(2026, 10, 12, 12);
      Set<String>? reads;
      final result = object(
        await host.invokePage(
          'test.prepared',
          'render',
          {'context': {}, 'state': {}},
          readOnly: true,
          onReads: (value) => reads = value,
        ),
      );
      expect(object(result['tree'])['text'], '2026-10-12');
      expect(reads, contains('test.prepared'));
      expect(interactions, isEmpty);
    },
  );

  test(
    'preparation forbids all side effects before capability dispatch',
    () async {
      for (final effect in [
        'notify',
        'dialog',
        'navigate',
        'preferences',
        'ids',
        'http',
        'subscribe',
        'command',
      ]) {
        await expectLater(
          host.invokePage('test.prepared', 'render', {
            'context': {'effect': effect},
            'state': {},
          }, readOnly: true),
          throwsA(
            predicate(
              (error) => error.toString().contains(
                'Page preparation forbids side effects',
              ),
            ),
          ),
        );
      }
      expect(interactions, isEmpty);
      // A refused speculation must not poison the foreground worker.
      await host.invokePage('test.prepared', 'render', {
        'context': {'effect': 'notify'},
        'state': {},
      });
      expect(interactions, ['ui.notify']);
    },
  );

  test('preparation never dispatches an event', () {
    expect(
      () => host.invokePage('test.prepared', 'render', {
        'event': {'type': 'complete'},
      }, readOnly: true),
      throwsStateError,
    );
  });

  test('read-only mode follows nested query workers', () async {
    for (final effect in ['ids', 'notify', 'command']) {
      await expectLater(
        host.invokePage('test.prepared', 'render', {
          'context': {'nestedEffect': effect},
        }, readOnly: true),
        throwsA(
          predicate(
            (error) => error.toString().contains(
              'Page preparation forbids side effects',
            ),
          ),
        ),
      );
    }
    expect(interactions, isEmpty);
    // Query UUIDs remain allowed for normal foreground work.
    final result = object(
      await host.invokePage('test.prepared', 'render', {
        'context': {'nestedEffect': 'ids'},
      }),
    );
    expect(object(result['tree'])['type'], 'text');
  });

  test(
    'a no longer needed queued preparation never executes JavaScript',
    () async {
      final gate = Completer<void>();
      final instance = host.instances['test.prepared']!;
      instance.workflowTail = gate.future;
      var needed = true;
      final cancelled = host.invokePage(
        'test.prepared',
        'render',
        {},
        readOnly: true,
        shouldRun: () => needed,
      );
      needed = false;
      gate.complete();
      expect(await cancelled, isNull);
      final result = object(
        await host.invokePage('test.prepared', 'render', {}),
      );
      expect(result['renders'], 1);
    },
  );

  test('failed queue eligibility does not poison later page work', () async {
    await expectLater(
      host.invokePage(
        'test.prepared',
        'render',
        {},
        readOnly: true,
        shouldRun: () => throw StateError('gone'),
      ),
      throwsStateError,
    );
    final result = object(await host.invokePage('test.prepared', 'render', {}));
    expect(result['renders'], 1);
  });

  test(
    'successful writes synchronously advance the cache data revision',
    () async {
      final actor = host.instances['test.prepared']!.actor;
      final session = SnapshotSession(actor, 'revision-test');
      await store.stage(session, actor, {
        'writes': [
          {
            'collection': 'items',
            'id': 'one',
            'value': {'id': 'one'},
          },
        ],
      });
      final plan = store.seal(session);
      final previous = store.dataRevision;
      await store.commit(plan.id, actor, authorize: (_) {}, audit: false);
      expect(store.dataRevision, previous + 1);
      // An idempotent retry has no new write and must not evict warmed dates.
      await store.commit(plan.id, actor, authorize: (_) {}, audit: false);
      expect(store.dataRevision, previous + 1);
    },
  );
}
