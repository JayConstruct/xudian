import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

Map<String, Object?> uiDefinition({
  String id = 'test.appearance',
  String version = '1.0.0',
  List<Object?> dependencies = const [],
  Map<String, Object?>? components,
}) => {
  'formatVersion': 3,
  'manifest': {
    'id': id,
    'kind': 'uiPack',
    'version': version,
    'hostApi': '^1.6.0',
    'dataVersion': 1,
    'permissions': [],
    'dependencies': dependencies,
  },
  'collections': [],
  'services': [],
  'pages': [],
  'uiPack': {
    'contractVersion': 1,
    'components':
        components ??
        {
          'ui.button@1': {
            'tree': {'type': 'base'},
          },
        },
    'tokens': {
      'light': {'primary': '#336699'},
    },
  },
};

Future<ScriptPackage> uiPackage({
  String id = 'test.appearance',
  String version = '1.0.0',
  List<Object?> dependencies = const [],
  Map<String, Object?>? components,
}) async => ScriptPackage.verify(
  await ScriptPackage.build(
    uiDefinition(
      id: id,
      version: version,
      dependencies: dependencies,
      components: components,
    ),
    {},
  ),
  allowUnsignedLocal: true,
);

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('ui-pack-lifecycle-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  test('UI package compiles once and starts no JavaScript workers', () async {
    final package = await uiPackage();
    expect(package.isUiPack, isTrue);
    expect(package.uiPack, isNotNull);
    expect(package.scripts, isEmpty);
    expect(
      identical(package.uiPack, package.withStoredOrigin('local').uiPack),
      isTrue,
    );
    await host.install(package);
    final instance = host.instances[package.id]!;
    expect(instance.hasWorkers, isFalse);
    expect(() => instance.worker, throwsStateError);
    expect(() => instance.workflow, throwsStateError);
    expect(
      await store.sql('SELECT * FROM host_collections WHERE module_id=?', [
        package.id,
      ]),
      isEmpty,
    );
  });

  test(
    'UI package disable, enable, restart and uninstall use existing lifecycle',
    () async {
      final package = await uiPackage();
      await host.install(package);
      await host.disable(package.id);
      expect(host.instances, isEmpty);
      await host.enable(package.id);
      expect(host.instances[package.id]!.hasWorkers, isFalse);
      await host.close();
      host = ModuleHost(store: store, directory: folder);
      await host.initialize();
      expect(host.instances[package.id]!.package.uiPack, isNotNull);
      expect(host.instances[package.id]!.hasWorkers, isFalse);
      await host.uninstall(package.id);
      expect(host.instances, isEmpty);
      await host.close();
      host = ModuleHost(store: store, directory: folder);
      await host.initialize();
      expect(host.instances, isEmpty);
    },
  );

  test(
    'UI update rollback and immutable digest history work without workers',
    () async {
      final original = await uiPackage();
      await host.install(original);
      await host.install(await uiPackage(version: '1.1.0'));
      expect(host.instances[original.id]!.package.version, '1.1.0');
      await host.rollback(original.id, '1.0.0');
      expect(
        host.instances[original.id]!.package.packageDigest,
        original.packageDigest,
      );
      expect(host.instances[original.id]!.hasWorkers, isFalse);
      final conflicting = await uiPackage(
        components: {
          'ui.card@1': {
            'tree': {'type': 'base'},
          },
        },
      );
      await expectLater(host.install(conflicting), throwsStateError);
      expect(
        host.instances[original.id]!.package.packageDigest,
        original.packageDigest,
      );
    },
  );

  test(
    'failed candidate retains active implementation and committed version',
    () async {
      final original = await uiPackage();
      await host.install(original);
      host.validateCandidate = (_) => throw StateError('Candidate rejected');
      await expectLater(
        host.install(await uiPackage(version: '1.1.0')),
        throwsStateError,
      );
      expect(
        host.instances[original.id]!.package.packageDigest,
        original.packageDigest,
      );
      expect(host.instances[original.id]!.hasWorkers, isFalse);
      final rows = await store.sql(
        'SELECT version FROM host_installations WHERE module_id=?',
        [original.id],
      );
      expect(rows.single['version'], '1.0.0');
    },
  );

  test(
    'dependencies use version constraints and prevent cycles on update',
    () async {
      await host.install(await uiPackage(id: 'test.provider'));
      await host.install(
        await uiPackage(
          dependencies: [
            {'moduleId': 'test.provider', 'version': '^1.0.0'},
          ],
        ),
      );
      await expectLater(host.disable('test.provider'), throwsStateError);
      await expectLater(
        host.install(
          await uiPackage(
            id: 'test.provider',
            version: '1.1.0',
            dependencies: ['test.appearance'],
          ),
        ),
        throwsStateError,
      );
      expect(host.instances['test.provider']!.package.version, '1.0.0');
      await host.disable('test.provider', cascade: true);
      expect(host.instances, isEmpty);
      await expectLater(host.enable('test.appearance'), throwsStateError);
      await host.enable('test.provider');
      await host.enable('test.appearance');
      await host.close();
      host = ModuleHost(store: store, directory: folder);
      await host.initialize();
      expect(
        host.instances.keys,
        containsAll(['test.provider', 'test.appearance']),
      );
      expect(host.instances.values.every((i) => !i.hasWorkers), isTrue);
    },
  );

  test(
    'UI providers cannot depend on scripts or change package kind',
    () async {
      final definition = {
        ...uiDefinition(id: 'test.script'),
        'manifest': {
          ...object(uiDefinition(id: 'test.script')['manifest']),
          'kind': 'script',
        },
        'entryPoint': 'main.js',
      }..remove('uiPack');
      final script = await ScriptPackage.verify(
        await ScriptPackage.build(definition, {
          'main.js': 'export function render(){ return {tree:{type:"text",text:"ok"}}; }',
        }),
        allowUnsignedLocal: true,
      );
      await host.install(script);
      await expectLater(
        host.install(await uiPackage(dependencies: ['test.script'])),
        throwsStateError,
      );
      await expectLater(
        host.install(await uiPackage(id: 'test.script', version: '1.1.0')),
        throwsStateError,
      );
      expect(host.instances['test.script']!.hasWorkers, isTrue);
      await host.uninstall('test.script');
      await expectLater(
        host.install(await uiPackage(id: 'test.script', version: '1.1.0')),
        throwsStateError,
      );
    },
  );

  test(
    'removing a referenced provider export rejects update before deactivation',
    () async {
      await host.install(
        await uiPackage(
          id: 'test.provider',
          components: {
            'test.provider.badge@1': {
              'tree': {
                'type': 'primitive',
                'name': 'text',
                'props': {'label': 'Badge'},
              },
            },
          },
        ),
      );
      await host.install(
        await uiPackage(
          dependencies: ['test.provider'],
          components: {
            'ui.tag@1': {
              'tree': {'type': 'component', 'ref': 'test.provider.badge@1'},
            },
          },
        ),
      );
      final oldProvider = host.instances['test.provider'];
      final oldConsumer = host.instances['test.appearance'];
      await expectLater(
        host.install(await uiPackage(id: 'test.provider', version: '1.1.0')),
        throwsFormatException,
      );
      expect(identical(host.instances['test.provider'], oldProvider), isTrue);
      expect(identical(host.instances['test.appearance'], oldConsumer), isTrue);
    },
  );

  test('catalog exposes declared custom contracts once and hides unrelated providers', () async {
    await host.install(
      await uiPackage(
        id: 'test.provider',
        components: {
          'ui.button@1': {
            'tree': {'type': 'base'},
          },
          'test.provider.badge@1': {
            'tree': {
              'type': 'primitive',
              'name': 'text',
              'props': {'label': 'Badge'},
            },
          },
        },
      ),
    );
    await host.install(
      await uiPackage(
        id: 'test.unrelated',
        components: {
          'test.unrelated.badge@1': {
            'tree': {
              'type': 'primitive',
              'name': 'text',
              'props': {'label': 'Badge'},
            },
          },
        },
      ),
    );
    final definition = {
      'formatVersion': 3,
      'manifest': {
        'id': 'test.consumer',
        'version': '1.0.0',
        'hostApi': '^1.6.0',
        'dataVersion': 1,
        'permissions': [],
        'dependencies': ['test.provider'],
      },
      'entryPoint': 'main.js',
      'collections': [],
      'services': [],
      'pages': [],
    };
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(definition, {
          'main.js': "import {ui} from '@xudian/sdk';export function catalog(){return ui.catalog();}",
        }),
        allowUnsignedLocal: true,
      ),
    );
    final contracts = await host.instances['test.consumer']!.worker.invoke(
      'catalog',
      {},
    ) as List;
    final refs = contracts.map((c) => object(c)['ref']).toList();
    expect(refs.where((ref) => ref == 'ui.button@1'), hasLength(1));
    expect(refs, contains('test.provider.badge@1'));
    expect(refs, isNot(contains('test.unrelated.badge@1')));
  });

  test(
    'pure UI pack rejects executable capabilities and reserved identity',
    () async {
      final base = uiDefinition();
      final cases = <Map<String, Object?>>[
        {...base, 'entryPoint': 'main.js'},
        {
          ...base,
          'collections': [
            {
              'id': 'records',
              'schema': {'type': 'object'},
            },
          ],
        },
        {
          ...base,
          'services': [
            {'id': 'unsafe'},
          ],
        },
        {
          ...base,
          'pages': [
            {'id': 'unsafe'},
          ],
        },
        {
          ...base,
          'contributions': [
            {'id': 'unsafe'},
          ],
        },
        {
          ...base,
          'interruptHandlers': ['unsafe'],
        },
        {
          ...base,
          'migrations': {'1': 'unsafe'},
        },
        {
          ...base,
          'manifest': {
            ...object(base['manifest']),
            'permissions': ['http'],
          },
        },
        {
          ...base,
          'manifest': {
            ...object(base['manifest']),
            'serviceDependencies': [{}],
          },
        },
        {
          ...base,
          'manifest': {...object(base['manifest']), 'dataVersion': 2},
        },
        {
          ...base,
          'manifest': {...object(base['manifest']), 'kind': 'unknown'},
        },
        uiDefinition(id: 'app.ui.default'),
        {
          ...base,
          'uiPack': {'contractVersion': 99},
        },
      ];
      for (final definition in cases) {
        await expectLater(
          ScriptPackage.verify(
            await ScriptPackage.build(definition, {}),
            allowUnsignedLocal: true,
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        ScriptPackage.verify(
          await ScriptPackage.build(base, {
            'unused.js': 'export const unsafe = 1;',
          }),
          allowUnsignedLocal: true,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'SDK builds component nodes locally and catalog remains host read only',
    () async {
      final definition = {
        'formatVersion': 3,
        'manifest': {
          'id': 'test.consumer',
          'version': '1.0.0',
          'hostApi': '^1.6.0',
          'dataVersion': 1,
          'permissions': [],
          'dependencies': [],
        },
        'entryPoint': 'main.js',
        'collections': [],
        'services': [],
        'pages': [],
      };
      final package = await ScriptPackage.verify(
        await ScriptPackage.build(definition, {
          'main.js': "import {ui} from '@xudian/sdk'; export function node(){return ui.component('ui.button@1',{key:'save',props:{label:'保存'},events:{press:{type:'save'}}});} export async function catalog(){return await ui.catalog();}",
        }),
        allowUnsignedLocal: true,
      );
      await host.install(package);
      final result = await host.instances[package.id]!.worker.invoke(
        'node',
        {},
      );
      expect(result, {
        'type': 'component',
        'ref': 'ui.button@1',
        'key': 'save',
        'props': {'label': '保存'},
        'slots': {},
        'events': {
          'press': {'type': 'save'},
        },
      });
      final catalog = await host.instances[package.id]!.worker.invoke(
        'catalog',
        {},
      ) as List;
      expect(catalog, isNotEmpty);
      expect(
        await store.sql('SELECT * FROM host_records WHERE module_id=?', [
          package.id,
        ]),
        isEmpty,
      );
    },
  );

  test(
    'package proposal previews include UI definitions without invoking scripts',
    () async {
      Map<String, Object?>? review;
      host.interaction = (_, method, args) async {
        expect(method, 'packages.review');
        review = args;
        return true;
      };
      expect(
        await host.editLocalPackage({
          'definition': uiDefinition(),
          'files': <String, String>{},
        }),
        isTrue,
      );
      expect((review!['preview'] as List).single, {
        'kind': 'uiPack',
        'moduleId': 'test.appearance',
        'uiPack': uiDefinition()['uiPack'],
      });
      expect(host.instances['test.appearance']!.hasWorkers, isFalse);
    },
  );
}
