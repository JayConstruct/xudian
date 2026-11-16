import 'package:task_app/core/performance/ui_load_trace.dart';

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/data/app_database.dart';

class RecordingStore extends CollectionStore {
  RecordingStore(super.db);
  final queries = <String>[];
  @override
  Future<List<Map<String, Object?>>> sql(
    String query, [
    List<Object?> args = const [],
  ]) {
    queries.add(query);
    return super.sql(query, args);
  }

  bool get paginated => queries.any(
    (q) => q.contains('SELECT id,value') && q.contains('LIMIT ? OFFSET ?'),
  );
}

void main() {
  late AppDatabase db;
  late RecordingStore store;
  late ModuleActor actor;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = RecordingStore(db);
    actor = ModuleActor('test.records', '1.0.0', 'space', 1, {});
    store.activate(actor);
    await db.customStatement(
      'INSERT INTO host_collections(module_id,space,name,definition) VALUES(?,?,?,?)',
      [
        actor.moduleId,
        actor.space,
        'records',
        jsonEncode({
          'id': 'records',
          'schema': {'type': 'object'},
        }),
      ],
    );
  });
  tearDown(() async {
    await store.close();
    await db.close();
  });
  Future<void> records(List<Map<String, Object?>> values) async {
    for (final value in values) {
      await db.customStatement(
        'INSERT INTO host_records(module_id,space,collection,id,value,revision,deleted) VALUES(?,?,?,?,?,1,0)',
        [
          actor.moduleId,
          actor.space,
          'records',
          value['id'],
          jsonEncode(value),
        ],
      );
    }
  }

  Future<void> same(Map<String, Object?> options, {bool? fast}) async {
    store.queries.clear();
    final actual = await store.query(actor, 'records', options);
    if (fast != null) expect(store.paginated, fast, reason: '$options');
    // A deletion of an absent record in this scope exercises the reference
    // overlay path without changing the result.
    final fallback = SnapshotSession(actor, 'reference');
    fallback.writes['unrelated'] = {
      'moduleId': actor.moduleId,
      'space': actor.space,
      'collection': 'records',
      'id': 'absent-reference-record',
      'value': null,
    };
    final expected = await store.query(
      actor,
      'records',
      options,
      session: fallback,
    );
    expect(actual, expected, reason: '$options');
  }

  test(
    'unrelated writes retain SQL pagination and report bounded decoding',
    () async {
      await records(
        List.generate(
          600,
          (i) => {'id': 'r${i.toString().padLeft(4, '0')}', 'value': i},
        ),
      );
      for (final scope in [
        ['other.module', actor.space, 'records'],
        [actor.moduleId, 'other-space', 'records'],
        [actor.moduleId, actor.space, 'other-collection'],
      ]) {
        final session = SnapshotSession(actor, 'unrelated');
        session.writes['other'] = {
          'moduleId': scope[0],
          'space': scope[1],
          'collection': scope[2],
          'id': 'x',
          'value': null,
        };
        final samples = <UiLoadSample>[];
        store.queries.clear();
        final page = await UiLoadTrace.observe(
          () => store.query(actor, 'records', {
            'offset': 300,
            'limit': 2,
          }, session: session),
          samples.add,
        );
        expect(page.map((row) => (row as Map)['value']), [300, 301]);
        expect(store.paginated, isTrue);
        expect(samples.single.arguments['recordsDecoded'], 2);
        expect(samples.single.arguments['mode'], 'sql');
        expect(session.collections, hasLength(1));
      }
    },
  );

  test(
    'chunked fallback preserves exact sorted pages and overlay order',
    () async {
      final values = List.generate(
        777,
        (i) => <String, Object?>{
          'id': 'r${i.toString().padLeft(4, '0')}',
          'rank': (i * 31) % 97,
          'title': '条目${i % 9}',
        },
      );
      await records(values);
      final session = SnapshotSession(actor, 'chunks');
      for (final entry in <String, Object?>{
        'r0000': null,
        'r0256': {'id': 'r0256', 'rank': 900, 'title': '条目2'},
        'new': {'id': 'new', 'rank': -1, 'title': '条目2'},
      }.entries) {
        session.writes[entry.key] = {
          'moduleId': actor.moduleId,
          'space': actor.space,
          'collection': 'records',
          'id': entry.key,
          'value': entry.value,
        };
      }
      final expected = [
        for (final value in values)
          if (value['id'] != 'r0000')
            value['id'] == 'r0256'
                ? session.writes['r0256']!['value'] as Map<String, Object?>
                : value,
        session.writes['new']!['value'] as Map<String, Object?>,
      ];
      for (final descending in [false, true]) {
        final sorted =
            expected.where((v) => (v['title'] as String).contains('2')).toList()
              ..sort((a, b) {
                final rank =
                    (a['rank'] as int).compareTo(b['rank'] as int) *
                    (descending ? -1 : 1);
                return rank == 0
                    ? (a['id'] as String).compareTo(b['id'] as String)
                    : rank;
              });
        final samples = <UiLoadSample>[];
        final page = await UiLoadTrace.observe(
          () => store.query(actor, 'records', {
            'filter': {'field': 'title', 'op': 'contains', 'value': '2'},
            'sort': [
              {'field': 'rank', 'direction': descending ? 'desc' : 'asc'},
            ],
            'offset': 7,
            'limit': 11,
          }, session: session),
          samples.add,
        );
        expect(page, sorted.skip(7).take(11).toList());
        expect(samples.single.arguments['mode'], 'overlay');
        expect(samples.single.arguments['recordsDecoded'], 775);
      }
      expect(
        await store.query(actor, 'records', {
          'offset': 775,
          'limit': 10,
        }, session: session),
        expected.skip(775).toList(),
      );
    },
  );

  test(
    'null, missing, false and numeric/string equality remain distinct',
    () async {
      await records([
        {'id': 'a'},
        {'id': 'b', 'value': null},
        {'id': 'c', 'value': false},
        {'id': 'd', 'value': true},
        {'id': 'e', 'value': 1},
        {'id': 'f', 'value': 1.0},
        {'id': 'g', 'value': '1'},
        {
          'id': 'h',
          'value': {'a': 1},
        },
      ]);
      for (final op in ['eq', 'ne']) {
        for (final value in [null, false, true, 1, '1']) {
          await same({
            'filter': {'field': 'value', 'op': op, 'value': value},
          }, fast: true);
        }
      }
      for (final op in ['isNull', 'notNull']) {
        await same({
          'filter': {'field': 'value', 'op': op},
        }, fast: true);
      }
      await same({
        'filter': {
          'field': 'value',
          'op': 'in',
          'value': [null, false, 1, '1'],
        },
      }, fast: true);
      await same({
        'filter': {'field': 'value', 'op': 'eq', 'value': 1.0},
      }, fast: false);
      await same({
        'filter': {
          'field': 'value',
          'op': 'eq',
          'value': {'a': 1},
        },
      }, fast: false);
    },
  );

  test(
    'numeric order, nulls, stable id ties and pagination run in SQL',
    () async {
      await records([
        {'id': 'a', 'priority': 2, 'createdAt': '2026-01-02'},
        {'id': 'b', 'priority': 2.0, 'createdAt': '2026-01-01'},
        {'id': 'c', 'priority': 2, 'createdAt': '2026-01-01'},
        {'id': 'd', 'priority': -1, 'createdAt': '2026-01-01'},
        {'id': 'e', 'priority': 10, 'createdAt': '2026-01-01'},
        {'id': 'f', 'priority': null},
        {'id': 'g'},
      ]);
      for (final direction in ['asc', 'desc']) {
        for (var offset = 0; offset < 8; offset++) {
          await same({
            'sort': [
              {'field': 'priority', 'direction': direction},
              {'field': 'createdAt', 'direction': 'asc'},
            ],
            'offset': offset,
            'limit': 2,
          }, fast: true);
        }
      }
      for (final op in ['lt', 'lte', 'gt', 'gte']) {
        await same({
          'filter': {'field': 'priority', 'op': op, 'value': 2.0},
        }, fast: true);
      }
    },
  );

  test('task filters all/any and date ordering remain SQL paginated', () async {
    await records([
      {'id': 'a', 'deletedAt': null, 'priority': 2, 'dueDate': '2026-10-01'},
      {'id': 'b', 'priority': 1, 'plannedDate': '2026-10-08'},
      {'id': 'c', 'priority': 3, 'dueDate': '2026-10-10'},
      {'id': 'd', 'priority': 0, 'deletedAt': '2026-01-01'},
      {'id': 'e', 'priority': 1, 'parentTaskId': 'a'},
    ]);
    await same({
      'filter': {
        'all': [
          for (final field in [
            'deletedAt',
            'archivedAt',
            'completedAt',
            'parentTaskId',
            'projectId',
          ])
            {'field': field, 'op': 'isNull'},
          {
            'any': [
              {'field': 'dueDate', 'op': 'lte', 'value': '2026-10-08'},
              {'field': 'plannedDate', 'op': 'eq', 'value': '2026-10-08'},
            ],
          },
        ],
      },
      'sort': [
        {'field': 'priority', 'direction': 'desc'},
      ],
      'offset': 1,
      'limit': 1,
    }, fast: true);
    await same({
      'filter': {'all': []},
    }, fast: true);
    await same({
      'filter': {'any': []},
    }, fast: true);
  });

  test(
    'mixed scalar sorts and comparisons fall back with exact Dart semantics',
    () async {
      await records([
        {'id': 'a', 'value': 2},
        {'id': 'b', 'value': '10'},
        {'id': 'c', 'value': false},
        {'id': 'd', 'value': null},
      ]);
      await same({
        'sort': [
          {'field': 'value'},
        ],
      }, fast: false);
      for (final expected in [2, '10', false]) {
        await same({
          'filter': {'field': 'value', 'op': 'lt', 'value': expected},
        }, fast: false);
      }
      await same({
        'filter': {
          'any': [
            {'field': 'value', 'op': 'lt', 'value': 2},
            {'field': 'value', 'op': 'gt', 'value': '1'},
          ],
        },
      }, fast: false);
    },
  );

  test('Unicode ordering, contains and unsafe JSON path fall back', () async {
    await records([
      {'id': 'a', 'title': '中文'},
      {'id': 'b', 'title': '😀'},
      {'id': 'c', 'title': '\ue000'},
      {'id': 'd', 'title': 'ascii', 'strange"key': 'safe'},
    ]);
    await same({
      'sort': [
        {'field': 'title'},
      ],
    }, fast: false);
    await same({
      'filter': {'field': 'title', 'op': 'lt', 'value': 'z'},
    }, fast: false);
    await same({
      'filter': {'field': 'title', 'op': 'contains', 'value': '文'},
    }, fast: false);
    await same({
      'filter': {'field': 'strange"key', 'op': 'eq', 'value': 'safe'},
    }, fast: false);
    await same({
      'filter': {'field': 'title', 'op': 'eq', 'value': '中文'},
    }, fast: true);
  });

  test('staged additions updates and deletes bypass SQL and preserve snapshot tracking', () async {
    await records([
      {'id': 'a', 'priority': 1},
      {'id': 'b', 'priority': 2},
    ]);
    final session = SnapshotSession(actor, 'staged');
    for (final value in [
      null,
      {'id': 'b', 'priority': 4},
      {'id': 'c', 'priority': 3},
    ]) {
      final id = value == null ? 'a' : value['id'] as String;
      session.writes[RecordKey(
        actor.moduleId,
        actor.space,
        'records',
        id,
      ).key] = {
        'moduleId': actor.moduleId,
        'space': actor.space,
        'collection': 'records',
        'id': id,
        'value': value,
      };
    }
    store.queries.clear();
    final values = await store.query(actor, 'records', {
      'sort': [
        {'field': 'priority', 'direction': 'desc'},
      ],
      'offset': 1,
      'limit': 1,
    }, session: session);
    expect(values, [
      {'id': 'c', 'priority': 3},
    ]);
    expect(store.paginated, isFalse);
    expect(session.collections, hasLength(1));
    expect(session.participants.keys, [actor.moduleId]);
    await db.customStatement('UPDATE host_collections SET revision=revision+1');
    await expectLater(
      store.query(actor, 'records', {}, session: session),
      throwsStateError,
    );
  });

  test(
    'compatibility metadata is reused until collection revision changes',
    () async {
      await records([
        {'id': 'a', 'value': 1},
        {'id': 'b', 'value': 2},
      ]);
      final options = {
        'sort': [
          {'field': 'value'},
        ],
        'limit': 1,
      };
      await same(options, fast: true);
      store.queries.clear();
      await store.query(actor, 'records', options);
      expect(
        store.queries.any((q) => q.contains('SELECT DISTINCT json_type')),
        isFalse,
      );
      expect(store.paginated, isTrue);
      await records([
        {'id': 'c', 'value': '10'},
      ]);
      await db.customStatement(
        'UPDATE host_collections SET revision=revision+1',
      );
      await same(options, fast: false);
      await db.customStatement('UPDATE host_records SET value=? WHERE id=?', [
        jsonEncode({'id': 'c', 'value': 10}),
        'c',
      ]);
      await db.customStatement(
        'UPDATE host_collections SET revision=revision+1',
      );
      await same(options, fast: true);
    },
  );

  test(
    'fast pagination decodes only requested page and rejects invalid bounds',
    () async {
      await records([
        for (var i = 0; i < 100; i++)
          {'id': i.toString().padLeft(3, '0'), 'priority': i % 4},
      ]);
      store.queries.clear();
      final page = await store.query(actor, 'records', {
        'offset': 40,
        'limit': 5,
      });
      expect(page, hasLength(5));
      expect(store.paginated, isTrue);
      for (final options in [
        {'offset': -1},
        {'limit': 0},
        {'limit': 10001},
      ]) {
        await expectLater(
          store.query(actor, 'records', options),
          throwsFormatException,
        );
      }
    },
  );
}
