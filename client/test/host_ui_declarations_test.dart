import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/ui/ui_slot.dart';
import 'package:task_app/data/app_database.dart';

Future<ScriptPackage> candidate({
  List<Object?> pages = const [],
  List<Object?> contributions = const [],
}) async => ScriptPackage.verify(
  await ScriptPackage.build(
    {
      'formatVersion': 3,
      'manifest': {
        'id': 'test.declarations',
        'version': '1.0.0',
        'hostApi': '^1.0.0',
        'dataVersion': 1,
      },
      'entryPoint': 'main.js',
      'collections': [],
      'services': [],
      'pages': pages,
      'contributions': contributions,
    },
    {
      'main.js':
          'export function render(){return {tree:{type:"text",text:"ok"}};}',
    },
  ),
  allowUnsignedLocal: true,
);

Map<String, Object?> page(Map<String, Object?> fields) => {
  'id': 'test.declarations.page',
  'handler': 'render',
  ...fields,
};

Map<String, Object?> slot(Map<String, Object?> fields) => {
  'id': 'content',
  'label': 'Content',
  ...fields,
};

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('ui-declarations-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    expect(host.validateCandidate, isNull);
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  final invalidPages = <String, Map<String, Object?>>{
    'missing page handler': {'handler': null},
    'unknown header mode': {'headerMode': 'unknown'},
    'non-boolean runtime initialization': {'initializesRuntimeContext': 1},
    'invalid title type': {'title': 5},
    'non-string required context': {
      'requiredContext': [1],
    },
    'unknown entry opening': {
      'entry': {'id': 'entry', 'opening': 'unknown'},
    },
    'unknown entry placement': {
      'entry': {'id': 'entry', 'placement': 'unknown'},
    },
    'invalid entry order': {
      'entry': {'id': 'entry', 'order': 'first'},
    },
    'invalid legacy context type': {
      'entry': {'id': 'entry', 'taskId': 1},
    },
    'invalid generic context type': {
      'entry': {'id': 'entry', 'values': []},
    },
    'unknown slot kind': {
      'slots': [
        slot({'kind': 'unknown'}),
      ],
    },
    'inline entries slot': {
      'slots': [
        slot({'kind': 'entries', 'inline': true}),
      ],
    },
    'inline tabs slot': {
      'slots': [
        slot({'kind': 'tabs', 'inline': true}),
      ],
    },
    'non-boolean inline value': {
      'slots': [
        slot({'inline': 'true'}),
      ],
    },
    'null inline value': {
      'slots': [
        slot({'inline': null}),
      ],
    },
    'invalid slot label': {
      'slots': [
        slot({'label': 3}),
      ],
    },
  };

  for (final example in invalidPages.entries) {
    test(
      'headless batch rejects ${example.key} and rolls back state',
      () async {
        final plan = await host.prepareInstallBatch([
          await candidate(pages: [page(example.value)]),
        ]);
        await expectLater(host.commitInstallBatch(plan), throwsFormatException);
        expect(host.instances, isEmpty);
        expect(await store.sql('SELECT * FROM host_installations'), isEmpty);
        expect(await store.sql('SELECT * FROM host_packages'), isEmpty);
        expect(await store.sql('SELECT * FROM host_snapshots'), isEmpty);
      },
    );
  }

  test('headless batch rejects an unknown contribution slot', () async {
    final plan = await host.prepareInstallBatch([
      await candidate(
        contributions: [
          {'id': 'entry', 'slot': 'unknown', 'handler': 'render'},
        ],
      ),
    ]);
    await expectLater(host.commitInstallBatch(plan), throwsFormatException);
    expect(host.instances, isEmpty);
    expect(await store.sql('SELECT * FROM host_installations'), isEmpty);
    expect(await store.sql('SELECT * FROM host_packages'), isEmpty);
  });

  test(
    'valid declarations preserve defaults and all supported contribution slots',
    () async {
      final valid = await candidate(
        pages: [
          page({
            'entry': {'id': 'default-entry'},
            'entries': [
              {
                'id': 'configured-entry',
                'opening': 'adaptivePanel',
                'placement': 'page',
                'targetPageId': 'test.declarations.page',
                'slotId': 'sections',
                'values': {'selectedDate': '2026-10-12'},
              },
            ],
            'slots': [
              slot({}),
              slot({'id': 'sections', 'kind': 'sections', 'inline': true}),
            ],
          }),
        ],
        contributions: [
          for (final contributionSlot in UiSlot.values)
            {
              'id': contributionSlot.name,
              'slot': contributionSlot.name,
              'handler': 'render',
            },
        ],
      );
      await host.commitInstallBatch(await host.prepareInstallBatch([valid]));
      expect(host.instances.keys, ['test.declarations']);
      expect(await store.sql('SELECT * FROM host_installations'), hasLength(1));
    },
  );
}
