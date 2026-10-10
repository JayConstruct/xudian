import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_control_services.dart';
import 'package:task_app/core/module_host/host_manager_page.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_app_module.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/data/app_database.dart';

import 'module_host_test.dart' as fixture;

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late ModuleRegistry registry;
  late Directory directory;
  var dirty = false;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('host-controls-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    registry = ModuleRegistry([
      HostManagerModule(),
    ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
    registerHostControlServices(host, registry, hasDirtyLayout: () => dirty);
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': {
              'id': 'test.controls',
              'version': '1.0.0',
              'hostApi': '^1.0.0',
              'dataVersion': 1,
              'dependencies': [],
              'permissions': [
                'services.query:app.host/settings.get@1',
                'services.query:app.host/layout.get@1',
                'services.query:app.host/navigation.list@1',
                'services.command:app.host/settings.patch@1',
                'services.command:app.host/layout.patch@1',
                'services.command:app.host/navigation.open@1',
              ],
            },
            'entryPoint': 'main.js',
            'collections': [],
            'pages': [],
            'services': [],
          },
          {
            'main.js': 'export function render(){return {state:{},tree:{type:"text",text:"controls"}};}',
          },
        ),
        allowUnsignedLocal: true,
      ),
    );
    dirty = false;
  });
  tearDown(() async {
    registry.dispose();
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  ServiceRef service(String id) => ServiceRef('app.host', id, 1);
  Future<Object?> query(String id) =>
      host.query(host.instances['test.controls']!.actor, service(id), {});
  Future<ChangePlan> prepare(String id, Map<String, Object?> args) =>
      host.prepare(host.instances['test.controls']!.actor, service(id), args);
  Future<Object?> commit(ChangePlan p) {
    final actor = host.instances['test.controls']!.actor;
    host.review(p.id, actor);
    return host.commit(actor, p.id);
  }

  test(
    'appearance applies reviewed transaction and conditionally restores',
    () async {
      final before = object(await query('settings.get'));
      final result = object(
        await commit(
          await prepare('settings.patch', {
            'changes': {'theme': 'dark'},
            'expected': before,
          }),
        ),
      );
      expect(object(await query('settings.get'))['theme'], 'dark');
      expect(
        jsonDecode(
          (await store.sql(
                "SELECT value FROM app_settings WHERE key='ui.preferences'",
              )).single['value']
              as String,
        ),
        result['after'],
      );
      await commit(
        await prepare('settings.patch', {
          'changes': result['before'],
          'expected': result['after'],
        }),
      );
      expect(await query('settings.get'), before);
      final pending = await prepare('settings.patch', {
        'changes': {'theme': 'light'},
      });
      await db.customStatement(
        "UPDATE app_settings SET value=? WHERE key='ui.preferences'",
        [
          jsonEncode({...before, 'haptics': false}),
        ],
      );
      await expectLater(commit(pending), throwsStateError);
      expect(object(await query('settings.get'))['haptics'], false);
    },
  );
  test(
    'layout draft and registry changes invalidate already prepared proposals',
    () async {
      final pending = await prepare('layout.patch', {
        'profile': 'narrow',
        'mainLimit': 2,
      });
      dirty = true;
      await expectLater(commit(pending), throwsStateError);
      dirty = false;
      await commit(pending);
      expect(
        object(object(await query('layout.get'))['narrow'])['mainLimit'],
        2,
      );
      final stale = await prepare('layout.patch', {
        'profile': 'wide',
        'mainLimit': 3,
      });
      await host.install(await fixture.package('app.schedule'));
      registry.replaceExtensions([
        for (final i in host.instances.values) ScriptAppModule(host, i.package),
      ]);
      await expectLater(commit(stale), throwsStateError);
    },
  );
  test(
    'navigation is discovered and reviewed through protected host service',
    () async {
      expect(object(await query('navigation.list'))['controls'], [
        'settings',
        'layout',
      ]);
      expect(
        object(
          await commit(
            await prepare('navigation.open', {'target': 'settings'}),
          ),
        )['navigate'],
        'app.host.settings',
      );
      await expectLater(
        prepare('navigation.open', {'target': 'entry', 'entryId': 'missing'}),
        throwsStateError,
      );
      await expectLater(host.uninstall('app.host'), throwsStateError);
    },
  );
}
