import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/ui_preferences.dart';
import 'package:task_app/data/app_database.dart';

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleActor first, second;
  var request = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    first = ModuleActor('test.first', '1.0.0', 'live', 1, {});
    second = ModuleActor('test.second', '1.0.0', 'live', 1, {});
    for (final actor in [first, second]) {
      store.activate(actor);
      await db.customStatement(
        'INSERT INTO host_collections(module_id,space,name,definition) VALUES(?,?,?,?)',
        [
          actor.moduleId,
          actor.space,
          'items',
          jsonEncode({
            'id': 'items',
            'schema': {'type': 'object'},
            'indexes': [
              {
                'id': 'uniqueName',
                'fields': ['name'],
                'unique': true,
              },
            ],
          }),
        ],
      );
    }
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  Future<void> stage(
    SnapshotSession session,
    ModuleActor actor,
    String id,
    String name,
  ) => store.stage(session, actor, {
    'writes': [
      {
        'collection': 'items',
        'id': id,
        'value': {'id': id, 'name': name},
      },
    ],
  });

  SnapshotSession session() => SnapshotSession(first, 'request-${request++}');

  test(
    'successful writes publish detached dependency tokens without audit',
    () async {
      final notifications = <Set<String>>[];
      final subscription = store.changes.stream.listen(notifications.add);
      addTearDown(subscription.cancel);
      final before = store.moduleDataRevisions;
      final change = session();
      await stage(change, first, 'one', 'one');
      await stage(change, first, 'two', 'two');
      final plan = store.seal(change);
      await store.commit(plan.id, first, authorize: (_) {}, audit: false);
      expect(store.dataRevision, 1);
      expect(store.moduleDataRevisions, {'test.first': 1});
      expect(before, isEmpty, reason: 'A captured baseline must not mutate.');
      expect(notifications, isEmpty);
      await store.commit(plan.id, first, authorize: (_) {}, audit: false);
      expect(store.dataRevision, 1);
      expect(store.moduleDataRevisions, {'test.first': 1});

      final combined = session();
      await stage(combined, first, 'three', 'three');
      await stage(combined, second, 'one', 'one');
      await store.commit(
        store.seal(combined).id,
        first,
        authorize: (_) {},
        audit: false,
      );
      expect(store.dataRevision, 2);
      expect(store.moduleDataRevisions, {'test.first': 2, 'test.second': 2});
    },
  );

  test(
    'a partial transaction rollback advances no dependency tokens',
    () async {
      final initial = session();
      await stage(initial, first, 'existing', 'reserved');
      await store.commit(
        store.seal(initial).id,
        first,
        authorize: (_) {},
        audit: false,
      );
      final before = store.moduleDataRevisions;
      final conflicting = session();
      await stage(conflicting, second, 'partial', 'free');
      await stage(conflicting, first, 'conflict', 'reserved');
      await expectLater(
        store.commit(
          store.seal(conflicting).id,
          first,
          authorize: (_) {},
          audit: false,
        ),
        throwsStateError,
      );
      expect(await store.get(second, 'items', 'partial'), isNull);
      expect(store.dataRevision, 1);
      expect(store.moduleDataRevisions, before);
    },
  );

  test(
    'outer rollback discards revisions from successful nested commits',
    () async {
      await expectLater(
        store.transactionWithDataRevisions(() async {
          final change = session();
          await stage(change, first, 'rolledBack', 'one');
          await store.commit(
            store.seal(change).id,
            first,
            authorize: (_) {},
            audit: false,
          );
          expect(store.dataRevision, 0);
          expect(store.moduleDataRevisions, isEmpty);
          throw StateError('outer validation failed');
        }),
        throwsStateError,
      );
      expect(await store.get(first, 'items', 'rolledBack'), isNull);
      expect(store.dataRevision, 0);
      expect(store.moduleDataRevisions, isEmpty);
    },
  );

  test(
    'nested failed work leaves only committed parent dependencies',
    () async {
      await store.transactionWithDataRevisions(() async {
        await expectLater(
          store.transactionWithDataRevisions(() async {
            final failed = session();
            await stage(failed, first, 'rolledBack', 'one');
            await store.commit(
              store.seal(failed).id,
              first,
              authorize: (_) {},
              audit: false,
            );
            throw StateError('nested validation failed');
          }),
          throwsStateError,
        );
        final change = session();
        await stage(change, second, 'committed', 'two');
        await store.commit(
          store.seal(change).id,
          first,
          authorize: (_) {},
          audit: false,
        );
        expect(store.dataRevision, 0);
      });
      expect(await store.get(first, 'items', 'rolledBack'), isNull);
      expect(await store.get(second, 'items', 'committed'), isNotNull);
      expect(store.dataRevision, 1);
      expect(store.moduleDataRevisions, {'test.second': 1});
    },
  );

  test('UI preferences advance only their synthetic read dependency', () async {
    final preferences = ModuleUiPreferences(store);
    final firstDependency = uiPreferencesReadDependency(first.moduleId);
    final secondDependency = uiPreferencesReadDependency(second.moduleId);
    await preferences.set(first, 'pinned', ['button']);
    expect(store.dataRevision, 1);
    expect(store.moduleDataRevisions, {firstDependency: 1});
    await preferences.set(first, 'pinned', ['button']);
    expect(
      store.dataRevision,
      1,
      reason: 'An unchanged preference is not a write.',
    );
    final before = store.moduleDataRevisions;
    await expectLater(
      preferences.set(first, 'pinned', List.filled(300, true)),
      throwsFormatException,
    );
    expect(store.dataRevision, 1);
    expect(store.moduleDataRevisions, before);
    await preferences.set(second, 'pinned', ['date']);
    expect(store.moduleDataRevisions, {
      firstDependency: 1,
      secondDependency: 2,
    });
    await preferences.set(first, 'pinned', null);
    expect(store.moduleDataRevisions, {
      firstDependency: 3,
      secondDependency: 2,
    });
  });
}
