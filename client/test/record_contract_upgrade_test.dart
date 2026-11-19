import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/native_time_gestures.dart';
import 'package:task_app/core/module_host/record_contract.dart';
import 'package:task_app/data/app_database.dart';

import 'support/module_fixtures.dart' show sourcePackage;

const config = <String, Object?>{
  'contract': 'time-range/2',
  'taskModuleId': 'app.tasks',
  'applyServiceId': 'planner.operation.apply',
  'undoServiceId': 'planner.batch.undo',
  'records': {
    'subject': 'time',
    'journal': 'journal',
    'receipt': 'receipt',
    'occurrence': 'occurrence',
  },
};

String nextPatch(String version) {
  final parts = version.split('.');
  return '${parts[0]}.${parts[1]}.${int.parse(parts[2]) + 1}';
}

Future<ScriptPackage> renamed(String id) async {
  final original = await sourcePackage(id);
  const fields = {
    'plannedStartAt': 'beginInstant',
    'plannedEndAt': 'finishInstant',
    'plannedTimezone': 'displayZone',
    'plannedDate': 'dayKey',
    'estimatedMinutes': 'lengthMinutes',
    'updatedAt': 'changedOn',
    'completedAt': 'doneOn',
    'archivedAt': 'archivedOn',
    'deletedAt': 'removedOn',
  };
  String transform(String value) {
    for (final e in fields.entries) {
      value = value.replaceAll(e.key, e.value);
    }
    for (final e in {
      'tasks': 'entries',
      'batches': 'journalRows',
      'receipts': 'receiptRows',
      'occurrences': 'instanceRows',
    }.entries) {
      value = value
          .replaceAll("'${e.key}'", "'${e.value}'")
          .replaceAll('"${e.key}"', '"${e.value}"');
    }
    return value;
  }

  return ScriptPackage.verify(
    await ScriptPackage.build(
      object(jsonDecode(transform(jsonEncode(original.definition)))),
      original.scripts.map((name, source) => MapEntry(name, transform(source))),
    ),
    allowUnsignedLocal: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ModuleHost host;
  late Directory folder;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    folder = await Directory.systemTemp.createTemp('record-contract-');
    host = ModuleHost(store: CollectionStore(db), directory: folder);
    host.clockNow = () => DateTime.utc(2026, 10, 20);
    await host.initialize();
  });
  tearDown(() async {
    await host.close();
    await host.store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  test(
    'verified record contracts survive persisted package restoration',
    () async {
      await host.install(await sourcePackage('app.tasks'));
      await host.install(await sourcePackage('app.planner'));
      await host.close();
      host = ModuleHost(store: host.store, directory: folder);
      await host.initialize();
      final restored = NativeTimeGestures().configuration(
        host,
        'app.planner',
        config,
      );
      expect(restored, isNotNull);
      expect(
        host
            .instances['app.tasks']!
            .package
            .recordContracts['time']!
            .collection,
        'tasks',
      );
      expect(
        host
            .instances['app.planner']!
            .package
            .recordContracts['journal']!
            .settings['retainedRecords'],
        50,
      );
    },
  );

  test('private collections and fields can all change without changing native time approval', () async {
    await host.install(await renamed('app.tasks'));
    await host.install(await renamed('app.planner'));
    final tasks = host.instances['app.tasks']!.actor,
        owner = host.instances['app.planner']!.actor;
    final create = await host.prepare(
      tasks,
      const ServiceRef('app.tasks', 'task.create', 1),
      {
        'title': 'Contract fixture',
        'beginInstant': '2026-10-21T01:00:00Z',
        'finishInstant': '2026-10-21T01:30:00Z',
        'displayZone': 'Asia/Shanghai',
        'lengthMinutes': 30,
      },
    );
    host.review(create.id, tasks);
    final created = object(await host.commit(tasks, create.id));
    final event = <String, Object?>{
      'intent': 'move',
      'taskId': created['id'],
      'id': created['id'],
      'start': '2026-10-21T10:00:00.000',
      'end': '2026-10-21T10:30:00.000',
    };
    final gestures = NativeTimeGestures();
    expect(gestures.configuration(host, 'app.planner', config), isNotNull);
    gestures.begin(event, host, 'app.planner', config);
    final preview = await host.query(
      owner,
      const ServiceRef('app.planner', 'planner.operation.preview', 1),
      {
        'kind': 'move',
        'taskId': created['id'],
        'date': '2026-10-21',
        'start': '10:00',
        'end': '10:30',
        'timezone': 'Asia/Shanghai',
        'preserveDuration': true,
      },
    );
    final input = {
      'operationKey': 'schema-independent',
      'preview': preview,
      'allowOverdue': false,
    };
    final plan = await host.prepare(
      owner,
      const ServiceRef('app.planner', 'planner.operation.apply', 1),
      input,
    );
    final approval = gestures.lookup(event)!;
    expect(
      approval.allows(
        moduleId: 'app.planner',
        serviceId: 'planner.operation.apply',
        input: input,
        writes: plan.writes,
        result: plan.result,
        confirmation: null,
      ),
      isTrue,
    );
    expect(
      plan.writes.cast<Map>().any((w) => w['collection'] == 'entries'),
      isTrue,
    );
    host.review(plan.id, owner);
    await host.commit(owner, plan.id);
    final undo = await host.prepare(
      owner,
      const ServiceRef('app.planner', 'planner.batch.undo', 1),
      {'id': 'schema-independent'},
    );
    expect(
      approval.undoAdjustment!.allows(
        moduleId: 'app.planner',
        serviceId: 'planner.batch.undo',
        input: {'id': 'schema-independent'},
        writes: undo.writes,
        result: undo.result,
        confirmation: null,
      ),
      isTrue,
    );
    host.review(undo.id, owner);
    await host.commit(owner, undo.id);
    final restored = object(
      await host.query(tasks, const ServiceRef('app.tasks', 'task.get', 1), {
        'id': created['id'],
      }),
    );
    expect(restored['beginInstant'], '2026-10-21T01:00:00.000Z');
    expect(restored.containsKey('plannedStartAt'), isFalse);
  });

  test('page cannot supply bindings, unknown roles, or retain authority after provider replacement', () async {
    await host.install(await sourcePackage('app.tasks'));
    await host.install(await sourcePackage('app.planner'));
    final gestures = NativeTimeGestures();
    expect(
      gestures.configuration(host, 'app.planner', {
        ...config,
        'fields': {'startAt': 'title'},
      }),
      isNull,
    );
    expect(
      gestures.configuration(host, 'app.planner', {
        ...config,
        'records': {'subject': 'missing'},
      }),
      isNull,
    );
    final event = <String, Object?>{'intent': 'move'};
    gestures.begin(event, host, 'app.planner', config);
    final original = await sourcePackage('app.tasks');
    final definition = object(jsonDecode(jsonEncode(original.definition)));
    object(definition['manifest'])['version'] = nextPatch(original.version);
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(definition, original.scripts),
        allowUnsignedLocal: true,
      ),
    );
    expect(
      gestures
          .lookup(event)!
          .allows(
            moduleId: 'app.planner',
            serviceId: 'planner.operation.apply',
            input: {},
            writes: [],
            result: {},
            confirmation: null,
          ),
      isFalse,
    );
  });

  test(
    'retention policy changes in a module update without a host change',
    () async {
      await host.install(await sourcePackage('app.tasks'));
      final original = await sourcePackage('app.planner');
      await host.install(original);
      final definition = object(jsonDecode(jsonEncode(original.definition)));
      object(definition['manifest'])['version'] = nextPatch(original.version);
      object(
        object(object(definition['recordContracts'])['journal'])['settings'],
      )['retainedRecords'] = 2;
      await host.install(
        await ScriptPackage.verify(
          await ScriptPackage.build(definition, original.scripts),
          allowUnsignedLocal: true,
        ),
      );
      final tasks = host.instances['app.tasks']!.actor,
          owner = host.instances['app.planner']!.actor;
      final create = await host.prepare(
        tasks,
        const ServiceRef('app.tasks', 'task.create', 1),
        {
          'title': 'Retention fixture',
          'plannedStartAt': '2026-10-21T01:00:00Z',
          'plannedEndAt': '2026-10-21T01:30:00Z',
          'plannedTimezone': 'Asia/Shanghai',
          'estimatedMinutes': 30,
        },
      );
      host.review(create.id, tasks);
      final created = object(await host.commit(tasks, create.id));
      for (var index = 0; index < 3; index++) {
        final start = '${10 + index}:00', end = '${10 + index}:30';
        final event = <String, Object?>{
          'intent': 'move',
          'taskId': created['id'],
          'id': created['id'],
          'start': '2026-10-21T$start:00.000',
          'end': '2026-10-21T$end:00.000',
        };
        final gestures = NativeTimeGestures();
        gestures.begin(event, host, 'app.planner', config);
        final preview = await host.query(
          owner,
          const ServiceRef('app.planner', 'planner.operation.preview', 1),
          {
            'kind': 'move',
            'taskId': created['id'],
            'date': '2026-10-21',
            'start': start,
            'end': end,
            'timezone': 'Asia/Shanghai',
            'preserveDuration': true,
          },
        );
        final input = {
          'operationKey': 'move-$index',
          'preview': preview,
          'allowOverdue': false,
        };
        final plan = await host.prepare(
          owner,
          const ServiceRef('app.planner', 'planner.operation.apply', 1),
          input,
        );
        expect(
          gestures
              .lookup(event)!
              .allows(
                moduleId: 'app.planner',
                serviceId: 'planner.operation.apply',
                input: input,
                writes: plan.writes,
                result: plan.result,
                confirmation: null,
              ),
          isTrue,
        );
        host.review(plan.id, owner);
        await host.commit(owner, plan.id);
      }
      expect(await host.store.query(owner, 'batches', {}), hasLength(2));
      expect(await host.store.query(owner, 'receipts', {}), hasLength(3));
      final rendered = await host.invokePage('app.planner', 'render', {
        'context': {'pageId': 'app.planner.home'},
        'state': {'history': true},
      });
      expect(jsonEncode(rendered), contains('最近2次操作'));
      expect(jsonEncode(rendered), isNot(contains('最近50次操作')));
    },
  );

  test('roles are injective and unmapped canonical-looking fields cannot shadow bindings', () async {
    final definition = object(
      jsonDecode(jsonEncode((await sourcePackage('app.tasks')).definition)),
    );
    final parsed = RecordContract.parse(definition)['time']!;
    final projected = parsed.project({
      'id': 'a',
      'plannedStartAt': 'correct',
      'startAt': 'shadow',
      'secret': 'keep',
    });
    expect(projected['startAt'], 'correct');
    expect(projected[r'$raw:startAt'], 'shadow');
    expect(projected[r'$raw:secret'], 'keep');
    object(
      object(object(definition['recordContracts'])['time'])['fields'],
    )['endAt'] = 'plannedStartAt';
    expect(() => RecordContract.parse(definition), throwsFormatException);
  });
}
