import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'module_host_test.dart' as fixtures;

Future<ScriptPackage> candidate(
  String id, {
  String version = '1.0.0',
  List<Object?> dependencies = const [],
  List<String> permissions = const [],
  List<Object?> services = const [],
  List<Object?> pages = const [],
  String script =
      'export function render(){return {tree:{type:"text",text:"hello"}};}',
}) async => ScriptPackage.verify(
  await ScriptPackage.build(
    {
      'formatVersion': 3,
      'manifest': {
        'id': id,
        'version': version,
        'hostApi': '^1.8.0',
        'dataVersion': 1,
        'dependencies': dependencies,
        'permissions': permissions,
      },
      'entryPoint': 'main.js',
      'collections': [],
      'services': services,
      'pages': pages,
    },
    {'main.js': script},
  ),
  allowUnsignedLocal: true,
);

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('batch-test-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  test(
    'unordered shared dependencies install once and restart restores chain',
    () async {
      final dependency = await candidate('test.shared');
      final first = await candidate(
        'test.first',
        dependencies: ['test.shared'],
      );
      final second = await candidate(
        'test.second',
        dependencies: ['test.shared'],
      );
      final notifications = <void>[];
      final subscription = host.registryChanges.stream.listen(
        notifications.add,
      );
      final plan = await host.prepareInstallBatch(
        [first, second, dependency],
        repositories: {
          'test.shared': 'Author/shared',
          'test.first': 'First/modules',
          'test.second': 'Second/modules',
        },
      );
      expect(plan.packages.map((p) => p.id), [
        'test.shared',
        'test.first',
        'test.second',
      ]);
      await host.commitInstallBatch(plan);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, hasLength(1));
      expect(await host.repositoryFor('test.first'), 'First/modules');
      expect(await store.sql('SELECT * FROM host_packages'), hasLength(3));
      await subscription.cancel();
      await host.close();
      host = ModuleHost(store: store, directory: directory);
      await host.initialize();
      expect(host.instances.keys.toSet(), {
        'test.shared',
        'test.first',
        'test.second',
      });
      await expectLater(host.commitInstallBatch(plan), throwsStateError);
    },
  );
  test(
    'disabled dependency enables without copying its data or package history',
    () async {
      final dependency = await candidate('test.shared');
      await host.install(dependency);
      final before = (await store.sql('SELECT * FROM host_installations'))
          .single;
      await host.disable(dependency.id);
      final client = await candidate(
        'test.client',
        dependencies: [dependency.id],
      );
      await host.commitInstallBatch(
        await host.prepareInstallBatch([client, dependency]),
      );
      final after = (await store.sql(
        'SELECT * FROM host_installations WHERE module_id=?',
        [dependency.id],
      )).single;
      expect(after['space'], before['space']);
      expect(await store.sql('SELECT * FROM host_snapshots'), isEmpty);
      expect(host.instances.keys, containsAll([dependency.id, client.id]));
    },
  );
  test(
    'stale review, downgrade and release repository switching are rejected',
    () async {
      final module = await candidate('test.module');
      final stale = await host.prepareInstallBatch([module]);
      await host.install(await candidate('test.other'));
      await expectLater(host.commitInstallBatch(stale), throwsStateError);
      expect(host.instances, isNot(contains(module.id)));
      await host.commitInstallBatch(
        await host.prepareInstallBatch(
          [module],
          repositories: {module.id: 'First/releases'},
        ),
      );
      await expectLater(
        host.prepareInstallBatch([
          await candidate(module.id, version: '0.9.0'),
        ]),
        throwsStateError,
      );
      await expectLater(
        host.prepareInstallBatch(
          [await candidate(module.id, version: '1.1.0')],
          repositories: {module.id: 'Second/releases'},
        ),
        throwsStateError,
      );
    },
  );
  test(
    'coordinated provider and consumer upgrades honor final graph constraints',
    () async {
      await host.install(await candidate('test.provider'));
      await host.install(
        await candidate(
          'test.consumer',
          dependencies: [
            {'moduleId': 'test.provider', 'version': '^1.0.0'},
          ],
        ),
      );
      final provider = await candidate('test.provider', version: '2.0.0');
      await expectLater(host.prepareInstallBatch([provider]), throwsStateError);
      final consumer = await candidate(
        'test.consumer',
        version: '2.0.0',
        dependencies: [
          {'moduleId': 'test.provider', 'version': '^2.0.0'},
        ],
      );
      await host.commitInstallBatch(
        await host.prepareInstallBatch([provider, consumer]),
      );
      expect(
        host.instances.values.map((i) => i.package.version),
        everyElement('2.0.0'),
      );
    },
  );
  test(
    'service-only dependencies require correct service major and kind',
    () async {
      final service = await candidate(
        'test.service',
        services: [
          {
            'id': 'value',
            'major': 1,
            'kind': 'query',
            'handler': 'render',
            'input': {},
            'output': {},
          },
        ],
      );
      final client = await candidate(
        'test.client',
        permissions: ['services.query:test.service/value@1'],
      );
      expect(client.dependencies, ['test.service']);
      await host.commitInstallBatch(
        await host.prepareInstallBatch([client, service]),
      );
      await expectLater(
        host.prepareInstallBatch([
          await candidate(
            'test.wrong',
            permissions: ['services.query:test.service/value@2'],
          ),
        ]),
        throwsStateError,
      );
      await expectLater(
        host.prepareInstallBatch([
          await candidate(
            'test.command',
            permissions: ['services.command:test.service/value@1'],
          ),
        ]),
        throwsStateError,
      );
      expect(host.affectedDependents(service.id), [client.id]);
    },
  );
  test('late runtime failure rolls back all packages and preserves enabled state and course data', () async {
    await host.install(await fixtures.package('app.schedule'));
    final actor = host.instances['app.schedule']!.actor;
    final dataPlan = await host.prepare(
      actor,
      fixtures.schedule('schedule.timetable.save'),
      {'timetable': fixtures.timetable()},
    );
    host.review(dataPlan.id, actor);
    await host.commit(actor, dataPlan.id);
    final disabled = await candidate('test.disabled');
    await host.install(disabled);
    await host.disable(disabled.id);
    final before = await store.sql(
      'SELECT * FROM host_installations ORDER BY module_id',
    );
    final records = await store.sql(
      'SELECT * FROM host_records ORDER BY module_id,space,collection,id',
    );
    final good = await candidate('test.good');
    final bad = await candidate(
      'test.bad',
      dependencies: [good.id],
      script: 'throw new Error("load failed");',
    );
    await expectLater(
      host.commitInstallBatch(
        await host.prepareInstallBatch(
          [good, bad, disabled],
          repositories: {good.id: 'Author/modules'},
        ),
      ),
      throwsA(anything),
    );
    expect(
      await store.sql('SELECT * FROM host_installations ORDER BY module_id'),
      before,
    );
    expect(
      await store.sql(
        'SELECT * FROM host_records ORDER BY module_id,space,collection,id',
      ),
      records,
    );
    expect(host.instances.keys, ['app.schedule']);
    expect(await host.repositoryFor(good.id), isNull);
    expect(
      await store.sql('SELECT * FROM host_packages WHERE module_id=?', [
        good.id,
      ]),
      isEmpty,
    );
    expect(store.active(actor), false);
    await host.close();
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    expect(host.instances.keys, ['app.schedule']);
    expect(
      object(
        await store.get(
          host.instances['app.schedule']!.actor,
          'timetables',
          't',
        ),
      )['name'],
      '课表',
    );
  });
  test('final UI registration failure rolls back the complete batch', () async {
    final one = await candidate(
      'test.one',
      pages: [
        {'id': 'duplicate.page', 'handler': 'render'},
      ],
    );
    final two = await candidate(
      'test.two',
      pages: [
        {'id': 'duplicate.page', 'handler': 'render'},
      ],
    );
    await expectLater(
      host.commitInstallBatch(await host.prepareInstallBatch([one, two])),
      throwsStateError,
    );
    expect(host.instances, isEmpty);
    expect(await store.sql('SELECT * FROM host_installations'), isEmpty);
    expect(await store.sql('SELECT * FROM host_packages'), isEmpty);
  });
  test(
    'protected official identity and publisher provenance survive batch path',
    () async {
      final module = await candidate('test.official');
      final official = await ScriptPackage.verify(
        module.bytes,
        preinstalledDigest: module.packageDigest,
      );
      await host.install(official);
      final update = await candidate(module.id, version: '1.1.0');
      await expectLater(host.prepareInstallBatch([update]), throwsStateError);
      await expectLater(host.prepareInstallBatch([module]), throwsStateError);
      await expectLater(
        host.prepareInstallBatch(
          [official],
          repositories: {module.id: 'Other/repository'},
        ),
        throwsStateError,
      );
      expect(host.instances[module.id]!.package.origin, 'preinstalled');
      expect(host.instances[module.id]!.package.version, '1.0.0');
    },
  );
  test(
    'deactivation callback failure restores runtime and notification state',
    () async {
      await host.install(await candidate('test.old'));
      host.onDeactivate = (_) => throw StateError('callback failed');
      await expectLater(
        host.commitInstallBatch(
          await host.prepareInstallBatch([await candidate('test.new')]),
        ),
        throwsStateError,
      );
      expect(host.instances.keys, ['test.old']);
      host.onDeactivate = null;
      await host.commitInstallBatch(
        await host.prepareInstallBatch([await candidate('test.new')]),
      );
      expect(host.instances.keys.toSet(), {'test.old', 'test.new'});
    },
  );
  test(
    'unsigned publisher text cannot replace a previously signed identity',
    () async {
      final module = await candidate('test.signed');
      await host.install(module);
      // Seed provenance of a previously verified market installation.
      await db.customStatement(
        'UPDATE host_packages SET origin=?,release=? WHERE module_id=?',
        ['market', '{"channel":"market","publisherId":"Trusted"}', module.id],
      );
      final spoof = await ScriptPackage.verify(
        await ScriptPackage.build(
          {
            ...module.definition,
            'manifest': {...module.manifest, 'version': '1.1.0'},
          },
          module.scripts,
          release: {'channel': 'local', 'publisherId': 'Trusted'},
        ),
        allowUnsignedLocal: true,
      );
      await expectLater(host.prepareInstallBatch([spoof]), throwsStateError);
      await expectLater(host.install(spoof), throwsStateError);
      expect(host.instances[module.id]!.package.version, '1.0.0');
    },
  );
  test('runtime validation refuses external side effects before transaction commits', () async {
    var interactions = 0;
    host.interaction = (_, _, _) async {
      interactions++;
      return null;
    };
    final module = await candidate(
      'test.external',
      permissions: ['files'],
      script: "await globalThis.__host('files.saveText',{name:'x',text:'y'}); export function render(){return {};}",
    );
    await expectLater(
      host.commitInstallBatch(await host.prepareInstallBatch([module])),
      throwsA(anything),
    );
    expect(interactions, 0);
    expect(await store.sql('SELECT * FROM host_installations'), isEmpty);
  });
}
