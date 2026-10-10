import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:task_app/core/contracts/json_values.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'module_host_test.dart' as fixture;

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('xudian-permissions-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    await host.install(await fixture.package('app.schedule'));
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });
  Future<ScriptPackage> caller({
    List<String> permissions = const [],
    List<String> dependencies = const [],
  }) async => ScriptPackage.verify(
    await ScriptPackage.build(
      {
        'formatVersion': 3,
        'manifest': {
          'id': 'test.caller',
          'version': '1.0.0',
          'hostApi': '^1.0.0',
          'dataVersion': 1,
          'permissions': permissions,
          'dependencies': dependencies,
        },
        'entryPoint': 'main.js',
        'collections': [],
        'pages': [],
        'services': [],
      },
      {'main.js': "export function value(){return 1;}"},
    ),
    allowUnsignedLocal: true,
  );
  Future<void> saveTable(String name) async {
    final actor = host.instances['app.schedule']!.actor;
    final p = await host.prepare(
      actor,
      fixture.schedule('schedule.timetable.save'),
      {
        'timetable': {...fixture.timetable(), 'name': name},
      },
    );
    host.review(p.id, actor);
    await host.commit(actor, p.id);
  }

  test(
    'module version dependencies prevent incompatible provider updates',
    () async {
      final client = await ScriptPackage.verify(
        await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': {
              'id': 'test.versioned',
              'version': '1.0.0',
              'hostApi': '^1.0.0',
              'dataVersion': 1,
              'permissions': [],
              'dependencies': [
                {'moduleId': 'app.schedule', 'version': '^1.0.0'},
              ],
            },
            'entryPoint': 'main.js',
            'collections': [],
            'services': [],
            'pages': [],
          },
          {'main.js': 'export function value(){return 1;}'},
        ),
        allowUnsignedLocal: true,
      );
      await host.install(client);
      final current = await fixture.package('app.schedule');
      final update = await ScriptPackage.verify(
        await ScriptPackage.build({
          ...current.definition,
          'manifest': {...current.manifest, 'version': '2.0.0'},
        }, current.scripts),
        allowUnsignedLocal: true,
      );
      await expectLater(host.install(update), throwsStateError);
      expect(host.instances['app.schedule']!.package.version, current.version);
      expect(host.instances.containsKey('test.versioned'), true);
    },
  );
  test(
    'dependencies, fake actor and caller-supplied identity grant no access',
    () async {
      await saveTable('原始');
      await host.install(await caller(dependencies: ['app.schedule']));
      final actor = host.instances['test.caller']!.actor;
      await expectLater(
        host.query(actor, fixture.schedule('schedule.query.week'), {
          'timetableId': 't',
          'teachingWeek': 1,
          '_host': {'callerModuleId': 'app.schedule'},
        }),
        throwsStateError,
      );
      final forged = ModuleActor(
        actor.moduleId,
        actor.version,
        actor.space,
        actor.generation,
        {'services.query:app.schedule/schedule.query.week@1'},
      );
      await expectLater(
        host.query(forged, fixture.schedule('schedule.query.week'), {
          'timetableId': 't',
          'teachingWeek': 1,
        }),
        throwsStateError,
      );
      expect(() => actor.permissions.add('ui'), throwsUnsupportedError);
      await expectLater(store.get(actor, 'timetables', 't'), throwsStateError);
    },
  );
  test('expired and revoked grants reject prepared writes at commit', () async {
    await saveTable('原始');
    await host.install(await caller(permissions: ['grants.request']));
    final actor = host.instances['test.caller']!.actor;
    const scope = 'app.schedule/schedule.timetable.save@1';
    final grant = HostGrant('grant', actor, {
      scope,
    }, DateTime.now().add(const Duration(minutes: 30)));
    host.grants[grant.id] = grant;
    final plan = await host.prepare(
      actor,
      fixture.schedule('schedule.timetable.save'),
      {
        'timetable': {...fixture.timetable(), 'name': '越权'},
      },
    );
    host.review(plan.id, actor);
    grant.revoked = true;
    await expectLater(host.commit(actor, plan.id), throwsStateError);
    host.grants[grant.id] = HostGrant('grant', actor, {
      scope,
    }, DateTime.now().subtract(const Duration(seconds: 1)));
    await expectLater(host.commit(actor, plan.id), throwsStateError);
    expect(
      object(
        await store.get(
          host.instances['app.schedule']!.actor,
          'timetables',
          't',
        ),
      )['name'],
      '原始',
    );
  });
  test(
    'adapter import identity and provider confirmation cannot be spoofed',
    () async {
      await host.install(
        await caller(
          permissions: [
            'services.command:app.schedule/schedule.import.prepare@1',
          ],
        ),
      );
      final adapter = host.instances['test.caller']!.actor,
          provider = host.instances['app.schedule']!.actor;
      final plan = await host.prepare(
        adapter,
        fixture.schedule('schedule.import.prepare'),
        {
          'draft': {
            'draftVersion': 1,
            'scope': 'school:semester',
            'adapterVersion': 'test@1',
            'complete': true,
            'timetable': fixture.timetable(),
            'courses': [],
            'meetings': [],
            'warnings': [],
          },
          'mode': 'new',
          '_host': {'callerModuleId': 'forged.school'},
        },
      );
      host.review(plan.id, adapter);
      await expectLater(host.commit(adapter, plan.id), throwsStateError);
      expect(await store.query(provider, 'timetables', {}), isEmpty);
      expect(() => store.adoptProviderPlan(plan.id, adapter), throwsStateError);
      final confirmed = store.adoptProviderPlan(plan.id, provider);
      host.review(confirmed.id, provider);
      await host.commit(provider, confirmed.id);
      final source = object(
        (await store.query(provider, 'importSources', {})).single,
      );
      expect(source['callerModuleId'], 'test.caller');
      expect(jsonDecode(source['sourceKey'] as String), [
        'test.caller',
        'school:semester',
      ]);
    },
  );
  test('failed migration restores pointer; incompatible rollback requires snapshot', () async {
    await saveTable('迁移之前');
    final original = await fixture.package('app.schedule');
    final current = (await store.sql(
      'SELECT * FROM host_installations WHERE module_id=?',
      ['app.schedule'],
    )).single;
    Future<ScriptPackage> update(String version, String script) async {
      final definition = object(jsonDecode(canonicalJson(original.definition)));
      definition['manifest'] = {
        ...original.manifest,
        'version': version,
        'dataVersion': 2,
      };
      definition['migrations'] = {'1': 'migrate'};
      return ScriptPackage.verify(
        await ScriptPackage.build(definition, {
          ...original.scripts,
          'main.js': original.scripts['main.js']! + script,
        }),
        allowUnsignedLocal: true,
      );
    }

    await expectLater(
      host.install(
        await update(
          '1.9.1',
          "\nexport function migrate(){throw new Error('迁移失败');}",
        ),
      ),
      throwsStateError,
    );
    expect(
      (await store.sql(
        'SELECT space FROM host_installations WHERE module_id=?',
        ['app.schedule'],
      )).single['space'],
      current['space'],
    );
    expect(
      object(
        await store.get(
          host.instances['app.schedule']!.actor,
          'timetables',
          't',
        ),
      )['name'],
      '迁移之前',
    );
    await host.install(
      await update(
        '1.9.2',
        "\nexport async function migrate(){const t=await data.get('timetables','t');return {writes:[{collection:'timetables',id:'t',value:{...t,name:'迁移之后'}}],events:[],result:{ok:true}};}",
      ),
    );
    await expectLater(
      host.rollback('app.schedule', original.version),
      throwsStateError,
    );
    await saveTable('升级后的新写入');
    final snapshot = (await store.sql(
      "SELECT * FROM host_snapshots WHERE module_id='app.schedule' AND data_version=1",
    )).single;
    await host.recoverSnapshot('app.schedule', snapshot['id'] as String);
    expect(
      object(
        await store.get(
          host.instances['app.schedule']!.actor,
          'timetables',
          't',
        ),
      )['name'],
      '迁移之前',
    );
    final retained = (await store.sql(
      "SELECT * FROM host_snapshots WHERE module_id='app.schedule' AND data_version=2",
    )).single;
    expect(
      object(
        jsonDecode(
          (await store.sql(
                "SELECT value FROM host_records WHERE module_id='app.schedule' AND space=? AND collection='timetables' AND id='t'",
                [retained['space']],
              )).single['value']
              as String,
        ),
      )['name'],
      '升级后的新写入',
    );
    final abandoned = File(
      '${folder.path}/${List.filled(64, '0').join()}.xmodule',
    );
    await abandoned.writeAsString('uncommitted package');
    await host.close();
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    expect(host.instances['app.schedule']!.package.version, original.version);
    expect(await abandoned.exists(), false);
  });
}
