import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

class RecordingStore extends CollectionStore {
  RecordingStore(super.db);
  final pages = <({int offset, int length, int limit})>[];
  bool changeAfterPage = false;

  @override
  Future<List<Object?>> query(
    ModuleActor actor,
    String collection,
    Map<String, Object?> options, {
    SnapshotSession? session,
  }) async {
    final result = await super.query(
      actor,
      collection,
      options,
      session: session,
    );
    if (collection == 'tasks') {
      pages.add((
        offset: options['offset'] as int? ?? 0,
        length: result.length,
        limit: options['limit'] as int? ?? 10000,
      ));
      if (changeAfterPage) {
        changeAfterPage = false;
        await db.customStatement(
          'UPDATE host_collections SET revision=revision+1 WHERE module_id=? AND space=? AND name=?',
          [actor.moduleId, actor.space, collection],
        );
      }
    }
    return result;
  }
}

void main() {
  late AppDatabase db;
  late RecordingStore store;
  late Directory directory;
  late ModuleHost host;
  late ModuleActor actor;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = RecordingStore(db);
    directory = await Directory.systemTemp.createTemp('task-scan-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 8, 12);
    await host.initialize();
    final source = Directory('../packages/modules/app.tasks');
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          object(
            jsonDecode(await File('${source.path}/module.json').readAsString()),
          ),
          {'main.js': await File('${source.path}/main.js').readAsString()},
        ),
        allowUnsignedLocal: true,
      ),
    );
    actor = host.instances['app.tasks']!.actor;
    await db.transaction(() async {
      for (var i = 0; i < 10005; i++) {
        final id = 'task-${i.toString().padLeft(5, '0')}';
        final title = i == 1000
            ? 'İstanbul NEEDLE'
            : [0, 999, 10001, 10002, 10003, 10004].contains(i)
            ? '中文 NeEdLe $i'
            : '普通任务 $i';
        final value = {
          'id': id,
          'title': title,
          'priority': 0,
          'createdAt': id,
          'dueDate': '2026-10-08',
          'plannedDate': '2026-10-07',
          'completedAt': i == 0 || i == 999 ? 'completed' : null,
          'archivedAt': null,
          'deletedAt': null,
          'parentTaskId': null,
        };
        await db.customStatement(
          'INSERT INTO host_records(module_id,space,collection,id,value,revision,deleted) VALUES(?,?,?,?,?,1,0)',
          [actor.moduleId, actor.space, 'tasks', id, jsonEncode(value)],
        );
      }
    });
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<Object?> query(
    String service,
    Map<String, Object?> input, {
    SnapshotSession? session,
  }) => host.query(
    actor,
    ServiceRef('app.tasks', service, 1),
    input,
    session: session,
  );

  test('search preserves Unicode casing, matching offsets and the tail beyond 10000', () async {
    final early = await query('task.list', {
      'view': 'raw',
      'query': '中文 needle',
      'limit': 1,
    });
    expect((early as List).map((v) => object(v)['id']), ['task-00000']);
    expect(store.pages, [(offset: 0, length: 1000, limit: 1000)]);
    store.pages.clear();
    final tail = await query('task.list', {
      'view': 'raw',
      'query': '中文 NEEDLE',
      'offset': 2,
      'limit': 2,
    });
    expect((tail as List).map((v) => object(v)['id']), [
      'task-10001',
      'task-10002',
    ]);
    expect(store.pages.length, 11);
    expect(store.pages.map((p) => p.length).reduce((a, b) => a + b), 10005);
    expect(store.pages.every((p) => p.limit == 1000 && p.length <= 1000), true);
    final unicode = await query('task.list', {
      'view': 'raw',
      'query': 'i\u0307STANBUL',
      'limit': 1,
    });
    expect((unicode as List).map((v) => object(v)['id']), ['task-01000']);
    final empty = await query('task.list', {
      'view': 'raw',
      'query': '中文 needle',
      'offset': 6,
      'limit': 1,
    });
    expect(empty, isEmpty);
  });

  test(
    'streamed day counts include all pages and preserve sorted first 50',
    () async {
      final result = object(
        await query('task.dayCounts', {
          'dates': ['2026-10-07', '2026-10-08'],
        }),
      );
      final days = (result['days'] as List).map(object).toList();
      expect(days[0], {
        'date': '2026-10-07',
        'pending': 10003,
        'completed': 2,
        'overdue': 0,
        'loadedPending': 49,
        'loadedCompleted': 1,
        'hasMore': true,
        'truncated': false,
      });
      expect(days[1], {
        'date': '2026-10-08',
        'pending': 10003,
        'completed': 0,
        'overdue': 0,
        'loadedPending': 50,
        'loadedCompleted': 0,
        'hasMore': true,
        'truncated': false,
      });
      expect(store.pages.length, 11);
      expect(store.pages.map((p) => p.length).reduce((a, b) => a + b), 10005);
      expect(store.pages.every((p) => p.length <= 1000), true);
    },
  );

  test('search sees staged writes before matching and pagination', () async {
    final session = SnapshotSession(actor, 'staged-search');
    const id = 'task-00001';
    final original = object(await store.get(actor, 'tasks', id));
    session.writes[RecordKey(actor.moduleId, actor.space, 'tasks', id).key] = {
      'moduleId': actor.moduleId,
      'space': actor.space,
      'collection': 'tasks',
      'id': id,
      'value': {...original, 'title': '中文 NEEDLE staged'},
    };
    final result = await query('task.list', {
      'view': 'raw',
      'query': '中文 needle',
      'offset': 1,
      'limit': 1,
    }, session: session);
    expect((result as List).map((v) => object(v)['id']), [id]);
  });

  test(
    'changed collection between pages rejects mixed search and count snapshots',
    () async {
      store.changeAfterPage = true;
      await expectLater(
        query('task.list', {
          'view': 'raw',
          'query': '中文 needle',
          'offset': 2,
          'limit': 1,
        }),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Collection changed while preparing'),
          ),
        ),
      );
      store.changeAfterPage = true;
      await expectLater(
        query('task.dayCounts', {
          'dates': ['2026-10-07'],
        }),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Collection changed while preparing'),
          ),
        ),
      );
    },
  );
}
