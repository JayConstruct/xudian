import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/clock_conversion.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/system_timezone.dart';
import 'package:task_app/core/platform/system_timezone.dart';
import 'package:task_app/data/app_database.dart';
import 'package:timezone/data/latest_all.dart' as zones;

Future<ScriptPackage> _package(
  String id, {
  List<String> permissions = const ['clock.today'],
}) async => ScriptPackage.verify(
  await ScriptPackage.build(
    {
      'formatVersion': 3,
      'manifest': {
        'id': id,
        'name': '系统时区测试',
        'version': '1.0.0',
        'hostApi': '^1.22.0',
        'dataVersion': 1,
        'permissions': permissions,
      },
      'entryPoint': 'main.js',
      'collections': [],
      'services': [
        {
          'id': 'query',
          'major': 1,
          'kind': 'query',
          'handler': 'read',
          'input': {},
          'output': {},
        },
        {
          'id': 'prepare',
          'major': 1,
          'kind': 'command',
          'handler': 'prepare',
          'input': {},
          'output': {},
        },
      ],
      'pages': [
        {'id': '$id.home', 'title': '时区', 'handler': 'read'},
      ],
    },
    {
      'main.js': r'''
import {clock} from '@xudian/sdk';
export async function read() {return clock.systemTimezone();}
export async function prepare() {return {writes:[],result:await read()};}
export async function badArgs() {return globalThis.__host('clock.systemTimezone',{zone:'UTC'});}
export async function explicit() {
  return {system:await read(),today:await clock.today('Asia/Shanghai'),
    local:await clock.local('America/New_York'),
    fold:await clock.toUtc({date:'2026-11-01',time:'01:30',zone:'America/New_York'})};
}
export async function forbidden() {return clock.systemTimezone();}
''',
    },
  ),
  allowUnsignedLocal: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(zones.initializeTimeZones);

  testWidgets('a stalled native read falls back after its deadline', (
    tester,
  ) async {
    final stalled = Completer<String?>();
    final result = readSystemTimezone(() => stalled.future);
    await tester.pump(const Duration(seconds: 3));
    expect(await result, {'zone': 'Asia/Shanghai', 'source': 'fallback'});
    stalled.complete('America/New_York');
    await tester.pump();
    expect(await result, {'zone': 'Asia/Shanghai', 'source': 'fallback'});
  });

  test('valid IANA regions and UTC resolve without offset inference', () async {
    for (final zone in [
      'Asia/Shanghai',
      'America/New_York',
      'Australia/Lord_Howe',
      'Pacific/Apia',
      'Asia/Calcutta',
      'Europe/Kiev',
      'UTC',
    ]) {
      expect(await readSystemTimezone(() async => zone), {
        'zone': zone,
        'source': 'system',
      });
    }
    for (final alias in ['GMT', 'Etc/GMT', 'Etc/UTC']) {
      expect(await readSystemTimezone(() async => alias), {
        'zone': 'UTC',
        'source': 'system',
      });
    }
  });

  test(
    'missing invalid abbreviation offset and failure return explicit fallback',
    () async {
      const fallback = {'zone': 'Asia/Shanghai', 'source': 'fallback'};
      expect(await readSystemTimezone(null), fallback);
      for (final zone in [
        null,
        '',
        'CST',
        'EST',
        'GMT+08:00',
        '+08:00',
        'Unknown/Timezone',
        ' Asia/Shanghai ',
        'Etc/Unknown',
      ]) {
        expect(
          await readSystemTimezone(() async => zone),
          fallback,
          reason: '$zone',
        );
      }
      expect(
        await readSystemTimezone(() async => throw MissingPluginException()),
        fallback,
      );
      expect(
        await readSystemTimezone(
          () async => throw PlatformException(code: 'unavailable'),
        ),
        fallback,
      );
    },
  );

  test(
    'platform channel rereads native value and rejects non-string output',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Object? native = 'Europe/Berlin';
      var requests = 0;
      messenger.setMockMethodCallHandler(SystemTimezonePlatform.channel, (
        call,
      ) async {
        expect(call.method, 'systemTimezone');
        expect(call.arguments, isNull);
        requests++;
        return native;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemTimezonePlatform.channel,
          null,
        ),
      );
      const platform = SystemTimezonePlatform();
      expect(await platform.resolve(), 'Europe/Berlin');
      native = 'Pacific/Auckland';
      expect(await platform.resolve(), 'Pacific/Auckland');
      native = 480;
      expect(await readSystemTimezone(platform.resolve), {
        'zone': 'Asia/Shanghai',
        'source': 'fallback',
      });
      expect(requests, 3);
    },
  );

  group('real SDK bridge', () {
    late AppDatabase db;
    late CollectionStore store;
    late Directory directory;
    late ModuleHost host;
    String? systemZone;
    var reads = 0;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = CollectionStore(db);
      directory = await Directory.systemTemp.createTemp('system-timezone-');
      reads = 0;
      systemZone = 'Europe/Berlin';
      host = ModuleHost(
        store: store,
        directory: directory,
        systemTimezoneResolver: () async {
          reads++;
          return systemZone;
        },
      );
      await host.initialize();
      await host.install(await _package('test.clock'));
    });
    tearDown(() async {
      await host.close();
      await store.close();
      await db.close();
      await directory.delete(recursive: true);
    });

    test(
      'query command preparation and page preparation allow permissioned read',
      () async {
        final actor = host.instances['test.clock']!.actor;
        expect(
          await host.query(
            actor,
            const ServiceRef('test.clock', 'query', 1),
            {},
          ),
          {'zone': 'Europe/Berlin', 'source': 'system'},
        );
        final plan = await host.prepare(
          actor,
          const ServiceRef('test.clock', 'prepare', 1),
          {},
        );
        expect(plan.result, {'zone': 'Europe/Berlin', 'source': 'system'});
        expect(plan.writes, isEmpty);
        expect(
          await host.invokePage('test.clock', 'read', {}, readOnly: true),
          plan.result,
        );
        expect(reads, 3);
      },
    );

    test(
      'system setting changes appear on the next read including fallback',
      () async {
        expect(await host.invokePage('test.clock', 'read', {}), {
          'zone': 'Europe/Berlin',
          'source': 'system',
        });
        systemZone = 'America/New_York';
        expect(await host.invokePage('test.clock', 'read', {}), {
          'zone': 'America/New_York',
          'source': 'system',
        });
        systemZone = null;
        expect(await host.invokePage('test.clock', 'read', {}), {
          'zone': 'Asia/Shanghai',
          'source': 'fallback',
        });
        systemZone = 'Pacific/Apia';
        expect(await host.invokePage('test.clock', 'read', {}), {
          'zone': 'Pacific/Apia',
          'source': 'system',
        });
        expect(reads, 4);
      },
    );

    test('no clock permission and unknown host arguments reject before native reads', () async {
      await host.install(await _package('test.denied', permissions: []));
      final denied = host.instances['test.denied']!.actor;
      await expectLater(
        host.query(denied, const ServiceRef('test.denied', 'query', 1), {}),
        throwsA(
          predicate(
            (error) => '$error'.contains('System timezone permission denied'),
          ),
        ),
      );
      await expectLater(
        host.invokePage('test.clock', 'badArgs', {}),
        throwsA(predicate((error) => '$error'.contains('takes no arguments'))),
      );
      expect(reads, 0);
    });

    test('broad and precise clock permissions are accepted', () async {
      for (final (index, permission) in [
        'clock',
        'clock.systemTimezone',
      ].indexed) {
        final id = 'test.permission$index';
        await host.install(await _package(id, permissions: [permission]));
        expect(await host.invokePage(id, 'read', {}), {
          'zone': 'Europe/Berlin',
          'source': 'system',
        });
      }
    });

    test('isolated preview rejects real system access', () async {
      host.preview = true;
      await expectLater(
        host.invokePage('test.clock', 'read', {}),
        throwsA(
          predicate(
            (error) =>
                '$error'.contains('Preview forbids external capabilities'),
          ),
        ),
      );
      expect(reads, 0);
    });

    test('explicit timetable zones retain cross-day and DST semantics after system change', () async {
      host.clockNow = () => DateTime.utc(2026, 10, 13, 20, 30);
      final before = object(
        await host.invokePage('test.clock', 'explicit', {}),
      );
      systemZone = 'Pacific/Honolulu';
      final after = object(await host.invokePage('test.clock', 'explicit', {}));
      expect(before['system'], isNot(after['system']));
      expect(after['today'], '2026-10-14');
      expect(after['today'], before['today']);
      expect(after['local'], before['local']);
      expect(after['fold'], before['fold']);
      expect(object(after['fold'])['instants'], [
        '2026-11-01T05:30:00.000Z',
        '2026-11-01T06:30:00.000Z',
      ]);
      expect(
        clockToLocal({
          'utc': '2026-10-13T20:30:00Z',
          'zone': 'Asia/Shanghai',
        })['date'],
        '2026-10-14',
      );
    });

    test(
      'native read completion cannot authorize a deactivated caller',
      () async {
        final pending = Completer<String?>();
        host.systemTimezoneResolver = () => pending.future;
        final result = host.invokePage('test.clock', 'read', {});
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final rejected = expectLater(result, throwsStateError);
        await host.disable('test.clock');
        pending.complete('UTC');
        await rejected;
      },
    );
  });
}
