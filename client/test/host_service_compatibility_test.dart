import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

const serviceId = 'test.value';
const providerId = 'test.provider';
const consumerId = 'test.consumer';

Map<String, Object?> service(String kind, {int major = 1}) => {
  'id': serviceId,
  'major': major,
  'kind': kind,
  'handler': 'value',
  'input': {'type': 'object'},
  'output': {'type': 'object'},
};

Future<ScriptPackage> candidate(
  String id, {
  String version = '1.0.0',
  List<String> permissions = const [],
  List<Object?> serviceDependencies = const [],
  List<Object?> optionalServices = const [],
  List<Object?> services = const [],
  String script = 'export function value(){return {};}',
}) async => ScriptPackage.verify(
  await ScriptPackage.build(
    {
      'formatVersion': 3,
      'manifest': {
        'id': id,
        'version': version,
        'hostApi': '^1.0.0',
        'dataVersion': 1,
        'permissions': permissions,
        'serviceDependencies': serviceDependencies,
        'optionalServices': optionalServices,
      },
      'entryPoint': 'main.js',
      'collections': [],
      'services': services,
      'pages': [],
    },
    {'main.js': script},
  ),
  allowUnsignedLocal: true,
);

Future<ScriptPackage> provider(String kind, {String version = '1.0.0'}) =>
    candidate(providerId, version: version, services: [service(kind)]);

Future<ScriptPackage> consumer(String kind) => candidate(
  consumerId,
  permissions: ['services.$kind:$providerId/$serviceId@1'],
);

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('service-compatibility-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  final unsatisfiedService = throwsA(
    isA<StateError>().having(
      (error) => error.message,
      'message',
      contains('Unsatisfied service'),
    ),
  );

  const optionalQuery = {
    'moduleId': providerId,
    'serviceId': serviceId,
    'majorVersion': 1,
    'kind': 'query',
  };

  test(
    'optional query installs without provider and survives provider disable',
    () async {
      final optional = await candidate(
        consumerId,
        permissions: ['services.query:$providerId/$serviceId@1'],
        optionalServices: [optionalQuery],
      );
      expect(optional.dependencies, isEmpty);
      expect(optional.requiredServices, isEmpty);
      await host.install(optional);
      final caller = host.instances[consumerId]!.actor;
      const ref = ServiceRef(providerId, serviceId, 1);
      await expectLater(host.query(caller, ref, {}), throwsStateError);
      await host.install(await provider('query'));
      expect(await host.query(caller, ref, {}), {});
      expect(host.dependents(providerId), isEmpty);
      await host.disable(providerId);
      expect(host.instances[consumerId]!.actor, same(caller));
      await expectLater(host.query(caller, ref, {}), throwsStateError);
      await host.enable(providerId);
      expect(await host.query(caller, ref, {}), {});
    },
  );

  test('optional queries cannot remove command service requirements', () async {
    final optional = await candidate(
      consumerId,
      permissions: [
        'services.query:$providerId/$serviceId@1',
        'services.command:$providerId/$serviceId@1',
      ],
      optionalServices: [optionalQuery],
    );
    expect(optional.dependencies, [providerId]);
    expect(optional.requiredServices.single['kind'], 'command');
  });

  test(
    'optional declarations require query kind and exact permission',
    () async {
      await expectLater(
        candidate(consumerId, optionalServices: [optionalQuery]),
        throwsFormatException,
      );
      for (final declarations in [
        [
          {...optionalQuery, 'kind': 'command'},
        ],
        [
          {...optionalQuery, 'majorVersion': 0},
        ],
        [optionalQuery, optionalQuery],
      ]) {
        await expectLater(
          candidate(
            consumerId,
            optionalServices: declarations,
            permissions: ['services.query:$providerId/$serviceId@1'],
          ),
          throwsFormatException,
        );
      }
    },
  );

  for (final change in ['install', 'enable', 'disable', 'restart']) {
    test(
      'directory baseline detects optional provider $change at commit',
      () async {
        if (change != 'install') {
          await host.install(await provider('query'));
          if (change == 'enable') await host.disable(providerId);
        }
        await host.install(
          await candidate(
            consumerId,
            permissions: ['services.query:$providerId/$serviceId@1'],
            optionalServices: [optionalQuery],
            services: [service('command')],
            script:
                '''
import {services} from '@xudian/sdk';
export async function value() {
  const directory = await services.directory();
  return {result:{available:directory.some(s=>s.moduleId==='$providerId')},writes:[]};
}
export async function render() {return services.directory();}
''',
          ),
        );
        Set<String>? reads;
        await host.invokePage(
          consumerId,
          'render',
          {},
          readOnly: true,
          onReads: (value) => reads = value,
        );
        expect(reads, contains(providerId));
        final caller = host.instances[consumerId]!.actor;
        final plan = await host.prepare(
          caller,
          const ServiceRef(consumerId, serviceId, 1),
          {},
        );
        host.review(plan.id, caller);
        switch (change) {
          case 'install':
            await host.install(await provider('query'));
          case 'enable':
            await host.enable(providerId);
          case 'disable':
            await host.disable(providerId);
          case 'restart':
            await host.disable(providerId);
            await host.enable(providerId);
        }
        await expectLater(
          host.commit(caller, plan.id),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Service directory changed'),
            ),
          ),
        );
        final fresh = await host.prepare(
          caller,
          const ServiceRef(consumerId, serviceId, 1),
          {},
        );
        host.review(fresh.id, caller);
        expect(await host.commit(caller, fresh.id), fresh.result);
      },
    );
  }

  for (final requiredKind in ['query', 'command']) {
    final otherKind = requiredKind == 'query' ? 'command' : 'query';

    test(
      'single install rejects $requiredKind permission on $otherKind service',
      () async {
        await host.install(await provider(otherKind));
        await expectLater(
          host.install(await consumer(requiredKind)),
          unsatisfiedService,
        );
        expect(host.instances.keys, [providerId]);
        expect(
          await store.sql('SELECT * FROM host_installations'),
          hasLength(1),
        );
      },
    );

    test(
      'batch rejects $requiredKind permission on $otherKind service',
      () async {
        await expectLater(
          host.prepareInstallBatch([
            await consumer(requiredKind),
            await provider(otherKind),
          ]),
          unsatisfiedService,
        );
        expect(host.instances, isEmpty);
        expect(await store.sql('SELECT * FROM host_installations'), isEmpty);
      },
    );

    test(
      'provider update rejects $requiredKind to $otherKind and preserves actors',
      () async {
        await host.install(await provider(requiredKind));
        await host.install(await consumer(requiredKind));
        final providerActor = host.instances[providerId]!.actor;
        final consumerActor = host.instances[consumerId]!.actor;
        final before = await store.sql(
          'SELECT * FROM host_installations ORDER BY module_id',
        );

        final update = await provider(otherKind, version: '1.1.0');
        await expectLater(
          host.install(update),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Update would break service dependency'),
            ),
          ),
        );
        expect(host.instances[providerId]!.actor, same(providerActor));
        expect(host.instances[consumerId]!.actor, same(consumerActor));
        expect(
          await store.sql(
            'SELECT * FROM host_installations ORDER BY module_id',
          ),
          before,
        );
        expect(await store.sql('SELECT * FROM host_snapshots'), isEmpty);

        await expectLater(
          host.prepareInstallBatch([update]),
          unsatisfiedService,
        );
      },
    );

    test(
      'enable rejects stale $requiredKind requirement after provider changes',
      () async {
        await host.install(await provider(requiredKind));
        await host.install(await consumer(requiredKind));
        await host.disable(consumerId);
        await host.install(await provider(otherKind, version: '1.1.0'));

        await expectLater(host.enable(consumerId), unsatisfiedService);
        expect(host.instances.keys, [providerId]);
        expect(
          (await store.sql(
            'SELECT enabled FROM host_installations WHERE module_id=?',
            [consumerId],
          )).single['enabled'],
          0,
        );
      },
    );

    test(
      'provider snapshot recovery rejects $requiredKind to $otherKind',
      () async {
        await host.install(await provider(otherKind));
        await host.install(await provider(requiredKind, version: '1.1.0'));
        final snapshot =
            (await store.sql(
                  'SELECT id FROM host_snapshots WHERE module_id=?',
                  [providerId],
                )).single['id']
                as String;
        await host.install(await consumer(requiredKind));
        final providerActor = host.instances[providerId]!.actor;
        final consumerActor = host.instances[consumerId]!.actor;
        final before = await store.sql(
          'SELECT * FROM host_installations ORDER BY module_id',
        );

        await expectLater(
          host.recoverSnapshot(providerId, snapshot),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Update would break service dependency'),
            ),
          ),
        );
        expect(host.instances[providerId]!.actor, same(providerActor));
        expect(host.instances[consumerId]!.actor, same(consumerActor));
        expect(
          await store.sql(
            'SELECT * FROM host_installations ORDER BY module_id',
          ),
          before,
        );
      },
    );
  }

  test('snapshot recovery rejects stale service kind before replacing active consumer', () async {
    await host.install(await provider('query'));
    await host.install(await consumer('query'));
    await host.install(await candidate(consumerId, version: '1.1.0'));
    final snapshot =
        (await store.sql('SELECT id FROM host_snapshots WHERE module_id=?', [
              consumerId,
            ])).single['id']
            as String;
    await host.install(await provider('command', version: '1.1.0'));
    final current = host.instances[consumerId]!.actor;

    await expectLater(
      host.recoverSnapshot(consumerId, snapshot),
      unsatisfiedService,
    );
    expect(host.instances[consumerId]!.actor, same(current));
    expect(host.instances[consumerId]!.package.version, '1.1.0');
  });

  test(
    'startup isolates a persisted consumer whose provider kind changed',
    () async {
      await host.install(await provider('query'));
      await host.install(await consumer('query'));
      await host.disable(consumerId);
      await host.install(await provider('command', version: '1.1.0'));
      // Older hosts could persist this incompatible graph as enabled.
      await db.customStatement(
        'UPDATE host_installations SET enabled=1 WHERE module_id=?',
        [consumerId],
      );
      await host.close();
      host = ModuleHost(store: store, directory: directory);
      await host.initialize();

      expect(host.instances.keys, [providerId]);
      expect(host.failures[consumerId], contains('Unsatisfied service'));
    },
  );

  test(
    'native service requirements check kind and host major version',
    () async {
      host.nativeServices[serviceId] = NativeHostService({
        'id': serviceId,
        'kind': 'query',
      }, (caller, input, session) async => {});
      for (final permission in [
        'services.command:app.host/$serviceId@1',
        'services.query:app.host/$serviceId@2',
      ]) {
        final invalid = await candidate(consumerId, permissions: [permission]);
        await expectLater(host.install(invalid), unsatisfiedService);
        await expectLater(
          host.prepareInstallBatch([invalid]),
          unsatisfiedService,
        );
      }
      await host.install(
        await candidate(
          consumerId,
          permissions: ['services.query:app.host/$serviceId@1'],
        ),
      );
      expect(host.instances.keys, [consumerId]);
    },
  );

  test(
    'untyped service dependencies remain compatible across kind changes',
    () async {
      await host.install(await provider('query'));
      await host.install(
        await candidate(
          consumerId,
          serviceDependencies: [
            {'moduleId': providerId, 'serviceId': serviceId, 'majorVersion': 1},
          ],
        ),
      );
      await host.install(await provider('command', version: '1.1.0'));
      expect(host.instances.keys.toSet(), {providerId, consumerId});
      expect(host.instances[providerId]!.package.version, '1.1.0');
    },
  );

  test('self service permissions validate the candidate definition', () async {
    final invalid = await candidate(
      providerId,
      services: [service('command')],
      permissions: ['services.query:$providerId/$serviceId@1'],
    );
    await expectLater(host.install(invalid), unsatisfiedService);
    await expectLater(host.prepareInstallBatch([invalid]), unsatisfiedService);
    await host.install(
      await candidate(
        providerId,
        services: [service('query')],
        permissions: ['services.query:$providerId/$serviceId@1'],
      ),
    );
    expect(host.instances.keys, [providerId]);
  });
}
