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
  var now = DateTime.utc(2026, 10, 21, 15, 59);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('host-clock-');
    host = ModuleHost(store: store, directory: folder);
    now = DateTime.utc(2026, 10, 21, 15, 59);
    host.clockNow = () => now;
    await host.initialize();
    await host.drainAutomation();
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  Future<void> install(
    String id, {
    bool permission = true,
    bool fail = false,
  }) async {
    final bytes = await ScriptPackage.build(
      {
        'formatVersion': 3,
        'manifest': {
          'id': id,
          'name': 'Clock automation fixture',
          'version': '1.0.0',
          'hostApi': '^1.36.0',
          'dataVersion': 1,
          'permissions': ['clock.today', if (permission) 'automation.execute'],
          'dependencies': [],
        },
        'entryPoint': 'main.js',
        'pages': [],
        'collections': [
          {
            'id': 'days',
            'schema': {'type': 'object'},
          },
        ],
        'services': [
          {
            'id': 'replenish',
            'major': 1,
            'kind': 'command',
            'handler': 'replenish',
            'input': {'type': 'object'},
            'output': {'type': 'object'},
          },
          {
            'id': 'stats',
            'major': 1,
            'kind': 'query',
            'handler': 'stats',
            'input': {'type': 'object'},
            'output': {'type': 'object'},
          },
        ],
        'rules': [
          {
            'id': 'rolling',
            'event': 'host.clock.tick',
            'publishers': ['app.host'],
            'serviceId': 'replenish',
          },
        ],
      },
      {
        'main.js':
            '''
import {clock,data} from '@xudian/sdk';
let calls=0;
export async function replenish({ruleId,event}) {
  calls++;
  if ($fail) throw Error('fixture cannot replenish');
  if(ruleId!=='rolling'||event.type!=='host.clock.tick'||!event.at) throw Error('bad native event');
  const today=await clock.today('Asia/Shanghai');
  if(await data.get('days',today))return {writes:[],events:[],result:{skipped:true}};
  return {writes:[{collection:'days',id:today,value:{id:today}}],result:{date:today}};
}
export async function stats() {return {calls,days:await data.query('days',{})};}
''',
      },
    );
    await host.install(
      await ScriptPackage.verify(bytes, allowUnsignedLocal: true),
    );
    await host.drainAutomation();
  }

  Future<Map<String, Object?>> stats(String id) async => object(
    await host.query(host.instances[id]!.actor, ServiceRef(id, 'stats', 1), {}),
  );

  test(
    'installation and civil midnight replenish once; empty polls do not write',
    () async {
      await install('test.clock');
      expect((await stats('test.clock'))['days'], hasLength(1));
      final calls = (await stats('test.clock'))['calls'];
      await host.checkClockAutomation();
      await host.checkClockAutomation();
      expect((await stats('test.clock'))['calls'], calls);

      now = now.add(const Duration(minutes: 1)); // Shanghai midnight.
      await host.checkClockAutomation();
      expect((await stats('test.clock'))['days'], hasLength(2));
      final commits = await store.sql('SELECT * FROM host_commits');
      final history = await host.automationHistory('test.clock');
      expect(history, hasLength(2));

      now = now.add(const Duration(minutes: 1));
      await host.checkClockAutomation();
      expect((await stats('test.clock'))['days'], hasLength(2));
      expect(
        await store.sql('SELECT * FROM host_commits'),
        hasLength(commits.length),
      );
      expect(
        await host.automationHistory('test.clock'),
        hasLength(history.length),
      );
    },
  );

  test('foreground timer catches midnight and stops when host closes', () async {
    await host.close();
    var clockReads = 0;
    // Accelerate only the native minute timer; QuickJS and database scheduling
    // retain real timers, so this exercises the actual polling callback.
    host =
        runZoned(
            () => ModuleHost(store: store, directory: folder),
            zoneSpecification: ZoneSpecification(
              createPeriodicTimer: (self, parent, zone, duration, callback) =>
                  parent.createPeriodicTimer(
                    zone,
                    duration == const Duration(minutes: 1)
                        ? const Duration(milliseconds: 15)
                        : duration,
                    callback,
                  ),
            ),
          )
          ..clockNow = () {
            clockReads++;
            return now;
          };
    await host.initialize();
    await install('test.clock');
    now = now.add(const Duration(minutes: 1));
    for (var attempt = 0; attempt < 30; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await host.drainAutomation();
      if (((await stats('test.clock'))['days'] as List).length == 2) break;
    }
    expect((await stats('test.clock'))['days'], hasLength(2));
    await host.close();
    final readsAtClose = clockReads;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(clockReads, readsAtClose);
  });

  test('clock work outlives the UI async zone that resumes the host', () async {
    await install('test.clock');
    host.setClockAutomationActive(false);
    now = now.add(const Duration(days: 1));
    final suspendedCallbacks = <void Function()>[];
    runZoned(
      () => host.setClockAutomationActive(true),
      zoneSpecification: ZoneSpecification(
        scheduleMicrotask: (_, parent, zone, callback) =>
            suspendedCallbacks.add(callback),
      ),
    ); // Leave this UI zone without pumping its queued futures.
    await host.drainAutomation().timeout(const Duration(seconds: 2));
    expect((await stats('test.clock'))['days'], hasLength(2));
    await host.close().timeout(const Duration(seconds: 2));
  });

  test(
    'resume and cold restore catch up without an open planner page',
    () async {
      await install('test.clock');
      host.setClockAutomationActive(false);
      now = now.add(const Duration(days: 10));
      await host.checkClockAutomation();
      expect((await stats('test.clock'))['days'], hasLength(1));
      host.setClockAutomationActive(true);
      await host.drainAutomation();
      expect((await stats('test.clock'))['days'], hasLength(2));

      await host.close();
      now = now.add(const Duration(days: 10));
      host = ModuleHost(store: store, directory: folder)..clockNow = () => now;
      await host.initialize();
      await host.drainAutomation();
      expect((await stats('test.clock'))['days'], hasLength(3));
    },
  );

  test(
    'untrusted ticks, missing permission, and disabled modules cannot run',
    () async {
      await install('test.clock');
      await install('test.no.grant', permission: false);
      final before = (await stats('test.clock'))['calls'];
      store.events.add({
        'moduleId': 'app.host',
        'event': {'type': 'host.clock.tick', 'at': now.toIso8601String()},
      });
      await Future<void>.delayed(Duration.zero);
      await host.drainAutomation();
      expect((await stats('test.clock'))['calls'], before);
      expect((await stats('test.no.grant'))['calls'], 0);

      await host.disable('test.clock');
      now = now.add(const Duration(days: 1));
      await host.checkClockAutomation();
      expect(await host.automationHistory('test.clock'), hasLength(1));
      await host.enable('test.clock');
      await host.drainAutomation();
      expect((await stats('test.clock'))['days'], hasLength(2));
    },
  );

  test(
    'a failing clock rule is recorded while other rules keep running',
    () async {
      await install('test.failing', fail: true);
      await install('test.healthy');
      expect((await stats('test.healthy'))['days'], hasLength(1));
      final failures = await host.automationHistory('test.failing');
      expect(failures, isNotEmpty);
      expect(failures.first['status'], 'failure');
      now = now.add(const Duration(days: 1));
      await host.checkClockAutomation();
      expect((await stats('test.healthy'))['days'], hasLength(2));
    },
  );
}
