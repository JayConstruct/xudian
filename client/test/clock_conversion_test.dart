import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/clock_conversion.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';
import 'package:timezone/data/latest.dart' as zones;

void main() {
  setUpAll(zones.initializeTimeZones);

  test('UTC conversion changes civil date using explicit zone', () {
    expect(
      clockToLocal({
        'utc': '2026-10-13T20:30:00.000Z',
        'zone': 'Asia/Shanghai',
      }),
      {'date': '2026-10-14', 'time': '04:30', 'weekday': 3},
    );
  });

  test('batch UTC conversion preserves order and single-item DST results', () {
    final items = <Map<String, Object?>>[
      {'utc': '2026-11-01T05:30:00Z', 'zone': 'America/New_York'},
      {'utc': '2026-11-01T06:30:00Z', 'zone': 'America/New_York'},
      {'utc': '2026-03-08T07:30:00Z', 'zone': 'America/New_York'},
      {'utc': '2026-04-04T15:15:00Z', 'zone': 'Australia/Lord_Howe'},
      {'utc': '2026-10-13T20:30:00.123456Z', 'zone': 'Asia/Shanghai'},
      {'utc': '2011-12-30T10:00:00Z', 'zone': 'Pacific/Apia'},
    ];
    expect(clockToLocalMany({'items': items}), items.map(clockToLocal).toList());
    expect(clockToLocalMany({'items': []}), isEmpty);
    expect(
      clockToLocalMany({'items': List.filled(256, items.first)}),
      hasLength(256),
    );
  });

  test('batch conversion rejects invalid shape, limits and bad items', () {
    final good = {'utc': '2026-10-13T20:30:00Z', 'zone': 'UTC'};
    for (final items in <Object?>[
      null,
      {},
      List.filled(257, good),
      [good, null],
      [good, {'utc': '2026-02-30T12:00:00Z', 'zone': 'UTC'}],
      [good, {'utc': good['utc']}],
    ]) {
      expect(() => clockToLocalMany({'items': items}), throwsFormatException);
    }
    expect(
      () => clockToLocalMany({
        'items': [good, {'utc': good['utc'], 'zone': 'unknown/zone'}],
      }),
      throwsA(isA<Exception>()),
    );
  });

  test('ordinary civil time has one UTC instant', () {
    expect(
      clockToUtc({
        'date': '2026-10-14',
        'time': '04:30',
        'zone': 'Asia/Shanghai',
      }),
      {
        'status': 'unique',
        'instants': ['2026-10-13T20:30:00.000Z'],
      },
    );
  });

  test('DST fold lists both instants in ascending order', () {
    expect(
      clockToUtc({
        'date': '2026-11-01',
        'time': '01:30',
        'zone': 'America/New_York',
      }),
      {
        'status': 'ambiguous',
        'instants': ['2026-11-01T05:30:00.000Z', '2026-11-01T06:30:00.000Z'],
      },
    );
  });

  test('DST gap and skipped civil day have no UTC instant', () {
    for (final input in [
      {'date': '2026-03-08', 'time': '02:30', 'zone': 'America/New_York'},
      {'date': '2011-12-30', 'time': '12:00', 'zone': 'Pacific/Apia'},
    ]) {
      expect(clockToUtc(input), {'status': 'nonexistent', 'instants': []});
    }
  });

  test('half-hour DST fold is also ambiguous', () {
    expect(
      clockToUtc({
        'date': '2026-04-05',
        'time': '01:45',
        'zone': 'Australia/Lord_Howe',
      }),
      {
        'status': 'ambiguous',
        'instants': ['2026-04-04T14:45:00.000Z', '2026-04-04T15:15:00.000Z'],
      },
    );
  });

  test('invalid civil values and UTC normalization are rejected', () {
    for (final input in [
      {'date': '2026-02-30', 'time': '12:00', 'zone': 'UTC'},
      {'date': '2026-02-28', 'time': '24:00', 'zone': 'UTC'},
      {'date': '2026-02-28', 'time': '12:00:00', 'zone': 'UTC'},
    ]) {
      expect(() => clockToUtc(input), throwsFormatException);
    }
    for (final utc in [
      '2026-02-30T12:00:00Z',
      '2026-10-13T24:00:00Z',
      '2026-10-13T12:00:00',
      '2026-10-13T12:00:00+08:00',
    ]) {
      expect(
        () => clockToLocal({'utc': utc, 'zone': 'UTC'}),
        throwsFormatException,
      );
    }
    expect(
      () => clockToUtc({
        'date': '2026-10-13',
        'time': '12:00',
        'zone': 'unknown/zone',
      }),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'SDK conversions run inside queries, commands and page preparation',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final store = CollectionStore(db);
      final folder = await Directory.systemTemp.createTemp('clock-conversion-');
      final host = ModuleHost(store: store, directory: folder);
      await host.initialize();
      try {
        final package = await ScriptPackage.verify(
          await ScriptPackage.build(
            {
              'formatVersion': 3,
              'manifest': {
                'id': 'test.clock',
                'version': '1.0.0',
                'hostApi': '^1.23.0',
                'dataVersion': 1,
                'permissions': <String>[],
              },
              'entryPoint': 'main.js',
              'collections': [],
              'services': [
                for (final kind in ['query', 'command'])
                  {
                    'id': kind,
                    'major': 1,
                    'kind': kind,
                    'handler': kind == 'command' ? 'prepare' : 'convert',
                    'input': {'type': 'object'},
                    'output': {'type': 'object'},
                  },
              ],
              'pages': [
                {
                  'id': 'test.clock.home',
                  'title': 'Clock',
                  'handler': 'convert',
                },
              ],
            },
            {
              'main.js': r'''
import {clock} from '@xudian/sdk';
export async function convert() {
  const local = await clock.toLocal({utc:'2026-11-01T05:30:00Z',zone:'America/New_York'});
  const utc = await clock.toUtc({...local,zone:'America/New_York'});
  const batch = await clock.toLocalMany([
    {utc:'2026-11-01T05:30:00Z',zone:'America/New_York'},
    {utc:'2026-11-01T06:30:00Z',zone:'America/New_York'},
  ]);
  return {local,utc,batch};
}
export async function prepare() {return {result:await convert(),writes:[]};}
export async function invalid() {return clock.toLocalMany([{utc:'2026-02-30T12:00:00Z',zone:'UTC'}]);}
''',
            },
          ),
          allowUnsignedLocal: true,
        );
        await host.install(package);
        final caller = host.instances['test.clock']!.actor;
        final query = await host.query(
          caller,
          const ServiceRef('test.clock', 'query', 1),
          {},
        );
        expect(object(object(query)['utc'])['status'], 'ambiguous');
        expect(object(query)['batch'], [
          object(query)['local'],
          object(query)['local'],
        ]);
        final plan = await host.prepare(
          caller,
          const ServiceRef('test.clock', 'command', 1),
          {},
        );
        expect(plan.result, query);
        expect(
          await host.invokePage('test.clock', 'convert', {}, readOnly: true),
          query,
        );
        await expectLater(
          host.invokePage('test.clock', 'invalid', {}, readOnly: true),
          throwsA(isA<StateError>()),
        );
      } finally {
        await host.close();
        await store.close();
        await db.close();
        await folder.delete(recursive: true);
      }
    },
  );
}
