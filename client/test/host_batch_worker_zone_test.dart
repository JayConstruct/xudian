import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'host_batch_install_test.dart' as batch;
import 'module_host_test.dart' as fixtures;

void main() {
  test(
    'batch module load and migration share the live transaction then leave it',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final store = CollectionStore(db);
      final directory = await Directory.systemTemp.createTemp(
        'batch-worker-zone-',
      );
      final host = ModuleHost(store: store, directory: directory);
      addTearDown(() async {
        await host.close();
        await store.close();
        await db.close();
        await directory.delete(recursive: true);
      });
      await host.initialize();
      final original = await fixtures.package('app.schedule');
      await host.install(original);
      final actor = host.instances[original.id]!.actor;
      final plan = await host.prepare(
        actor,
        fixtures.schedule('schedule.timetable.save'),
        {'timetable': fixtures.timetable()},
      );
      host.review(plan.id, actor);
      await host.commit(actor, plan.id);
      final before = await store.sql(
        'SELECT * FROM host_records ORDER BY module_id,space,collection,id',
      );
      final definition = Map<String, Object?>.of(original.definition);
      definition['manifest'] = {
        ...original.manifest,
        'version': '2.0.0',
        'dataVersion': 2,
      };
      definition['migrations'] = {'1': 'zoneMigration'};
      final updated = await ScriptPackage.verify(
        await ScriptPackage.build(definition, {
          ...original.scripts,
          'main.js':
              original.scripts['main.js']! +
              r'''
const initialTable = await data.get('timetables','t');
if (initialTable?.name !== '课表') throw new Error('initialization lost transaction');
export async function zoneMigration() {
  const t = await data.get('timetables','t');
  return {writes:[{collection:'timetables',id:'t',value:{...t,name:'迁移后的课表'}}],events:[],result:{ok:true}};
}
''',
        }),
        allowUnsignedLocal: true,
      );
      final bad = await batch.candidate(
        'test.after.migration',
        dependencies: [original.id],
        script: 'throw new Error("fail after the migration write");',
      );
      await expectLater(
        host.commitInstallBatch(await host.prepareInstallBatch([updated, bad])),
        throwsStateError,
      );
      expect(
        await store.sql(
          'SELECT * FROM host_records ORDER BY module_id,space,collection,id',
        ),
        before,
      );
      expect(host.instances[original.id]!.package.version, original.version);
      expect(await store.sql('SELECT * FROM host_snapshots'), isEmpty);
      final restored = object(
        await host.query(
          host.instances[original.id]!.actor,
          fixtures.schedule('schedule.query.timetables'),
          {},
        ),
      );
      expect(object((restored['timetables'] as List).single)['name'], '课表');

      await host.commitInstallBatch(await host.prepareInstallBatch([updated]));
      final migrated = object(
        await host.query(
          host.instances[original.id]!.actor,
          fixtures.schedule('schedule.query.timetables'),
          {},
        ),
      );
      expect(object((migrated['timetables'] as List).single)['name'], '迁移后的课表');
      // A foreground request after commit uses the host owner zone, not the
      // transaction captured when this worker was created.
      final page = object(
        await host.invokePage(original.id, 'render', {
          'context': {'pageId': 'schedule.home'},
          'state': {},
        }),
      );
      expect(page['tree'], isA<Map>());
    },
  );
}
