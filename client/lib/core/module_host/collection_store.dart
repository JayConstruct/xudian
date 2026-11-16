import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/app_database.dart';
import '../contracts/json_values.dart';
import 'json_schema.dart';
import 'collection_query_engine.dart';
import '../performance/ui_load_trace.dart';
import 'module_package.dart';
import 'native_resource.dart';

class ModuleActor {
  ModuleActor(
    this.moduleId,
    this.version,
    this.space,
    this.generation,
    Set<String> permissions,
  ) : permissions = Set.unmodifiable(permissions);
  final String moduleId, version, space;
  final int generation;
  final Set<String> permissions;
}

class RecordKey {
  const RecordKey(this.moduleId, this.space, this.collection, this.id);
  final String moduleId, space, collection, id;
  String get key => jsonEncode([moduleId, space, collection, id]);
  List<Object?> get parameters => [moduleId, space, collection, id];
}

class SnapshotSession {
  SnapshotSession(this.caller, this.requestId);
  final ModuleActor caller;
  final String requestId;
  final Map<String, int> records = {}, collections = {};
  final Map<String, Object?> nativeReads = {};
  final Map<String, Map<String, Object?>> writes = {};
  final Map<String, ModuleActor> participants = {};
  final List<Map<String, Object?>> events = [];
  final List<Map<String, Object?>> approvals = [];
  Object? result;
  int automationDepth = 0;
  List<String> automationTrace = [];
  final activeServices = <String>{};
  bool pagePreparation = false;
  void Function()? onPageSideEffect;
}

class ChangePlan {
  ChangePlan(
    this.id,
    this.caller,
    this.requestId,
    this.content,
    this.createdAt,
  );
  final String id, requestId;
  final ModuleActor caller;
  final Map<String, Object?> content;
  final DateTime createdAt;
  List<Object?> get writes => content['writes'] as List;
  Object? get result => content['result'];
}

class CollectionStore {
  CollectionStore(this.db);
  final AppDatabase db;
  final changes = StreamController<Set<String>>.broadcast();
  int _dataRevision = 0;
  final _moduleDataRevisions = <String, int>{};
  final _dataRevisionBatchKey = Object();

  /// Advances synchronously after a successful write, before asynchronous
  /// change notifications are delivered. Read caches can avoid that gap.
  int get dataRevision => _dataRevision;

  /// A detached snapshot of successful writes by module. Like [dataRevision],
  /// these tokens advance before asynchronous change notifications. A cache
  /// can retain results that read only modules unaffected by another write.
  Map<String, int> get moduleDataRevisions =>
      Map.unmodifiable(_moduleDataRevisions);

  /// Record a committed change to business data or a synthetic read dependency.
  /// Call only after its transaction succeeds, before publishing notifications.
  void recordDataChange(Set<String> modules) {
    if (modules.isEmpty) return;
    final pending = Zone.current[_dataRevisionBatchKey] as Set<String>?;
    if (pending != null) {
      pending.addAll(modules);
      return;
    }
    _dataRevision++;
    for (final module in modules) {
      _moduleDataRevisions[module] = _dataRevision;
    }
  }

  /// An outer transaction containing nested commits (for example a batch
  /// installation) must publish tokens only when the outermost transaction
  /// succeeds. Nested failures discard their own changes without discarding
  /// earlier successful work in the parent transaction.
  Future<T> transactionWithDataRevisions<T>(Future<T> Function() action) async {
    final pending = <String>{};
    final result = await runZoned(
      () => db.transaction(action),
      zoneValues: {_dataRevisionBatchKey: pending},
    );
    recordDataChange(pending);
    return result;
  }

  final events = StreamController<Map<String, Object?>>.broadcast();
  final _plans = <String, ChangePlan>{};
  final _actors = <String, ModuleActor>{};
  late final _queries = CollectionQueryEngine(sql);
  final _nativeResources = <String, NativeResource>{};

  void registerNativeResource(NativeResource resource) =>
      _nativeResources[resource.id] = resource;
  Map<String, ModuleActor> get actors => Map.unmodifiable(_actors);
  void activate(ModuleActor actor) => _actors[actor.moduleId] = actor;
  void deactivate(String id) => _actors.remove(id);
  bool active(ModuleActor actor) => identical(_actors[actor.moduleId], actor);
  void requireActive(ModuleActor actor) {
    if (!active(actor)) {
      throw StateError(
        'Module instance is no longer active: ${actor.moduleId}',
      );
    }
  }

  Future<List<Map<String, Object?>>> sql(
    String query, [
    List<Object?> args = const [],
  ]) async =>
      (await db
              .customSelect(
                query,
                variables: [
                  for (final arg in args)
                    if (arg is int)
                      Variable<int>(arg)
                    else
                      Variable<String>(arg as String?),
                ],
              )
              .get())
          .map((row) => row.data.cast<String, Object?>())
          .toList();

  Future<void> define(ScriptPackage package, String space) async {
    for (final raw in package.definition['collections'] as List? ?? []) {
      final c = object(raw);
      await db.customStatement(
        'INSERT OR IGNORE INTO host_collections(module_id,space,name,definition) VALUES(?,?,?,?)',
        [package.id, space, c['id'], canonicalJson(c)],
      );
    }
  }

  /// Validate the entire candidate, including records outside query pagination,
  /// and rebuild indexes before publishing an updated data pointer.
  Future<void> validateAndReindex(ScriptPackage package, String space) async {
    await db.transaction(() async {
      await db.customStatement(
        'DELETE FROM host_indexes WHERE module_id=? AND space=?',
        [package.id, space],
      );
      final declared = (package.definition['collections'] as List? ?? [])
          .map((c) => object(c)['id'])
          .toSet();
      for (final collection in await sql(
        'SELECT name FROM host_collections WHERE module_id=? AND space=?',
        [package.id, space],
      )) {
        if (!declared.contains(collection['name'])) {
          await db.customStatement(
            'DELETE FROM host_collections WHERE module_id=? AND space=? AND name=?',
            [package.id, space, collection['name']],
          );
        }
      }
      for (final raw in package.definition['collections'] as List? ?? []) {
        final def = object(raw), collection = def['id'] as String;
        final unique = <String, Set<String>>{};
        for (final record in await sql(
          'SELECT id,value FROM host_records WHERE module_id=? AND space=? AND collection=? AND deleted=0',
          [package.id, space, collection],
        )) {
          final value = jsonDecode(record['value'] as String);
          validateSchema(value, object(def['schema']));
          if (object(value)['id'] != record['id']) {
            throw const FormatException('Record id mismatch');
          }
          for (final index in def['indexes'] as List? ?? []) {
            final spec = object(index);
            final indexed = canonicalJson([
              for (final field in spec['fields'] as List)
                CollectionQueryEngine.field(value, field as String),
            ]);
            if (spec['unique'] == true &&
                !(unique[spec['id'] as String] ??= {}).add(indexed)) {
              throw StateError('Unique index conflict in candidate');
            }
            await db.customStatement(
              'INSERT INTO host_indexes VALUES(?,?,?,?,?,?)',
              [
                package.id,
                space,
                collection,
                spec['id'],
                record['id'],
                indexed,
              ],
            );
          }
        }
      }
    });
  }

  Future<Map<String, Object?>> definition(
    ModuleActor actor,
    String name,
  ) async {
    final rows = await sql(
      'SELECT definition FROM host_collections WHERE module_id=? AND space=? AND name=?',
      [actor.moduleId, actor.space, name],
    );
    if (rows.isEmpty) throw StateError('Undeclared collection: $name');
    return object(jsonDecode(rows.single['definition'] as String));
  }

  Future<Object?> get(
    ModuleActor actor,
    String collection,
    String id, {
    SnapshotSession? session,
  }) async {
    requireActive(actor);
    await definition(actor, collection);
    session?.participants[actor.moduleId] = actor;
    final key = RecordKey(actor.moduleId, actor.space, collection, id);
    final staged = session?.writes[key.key];
    if (staged != null) return staged['value'];
    final rows = await sql(
      'SELECT value,revision,deleted FROM host_records WHERE module_id=? AND space=? AND collection=? AND id=?',
      key.parameters,
    );
    final revision = rows.isEmpty ? 0 : rows.single['revision'] as int;
    final previous = session?.records[key.key];
    if (previous != null && previous != revision) {
      throw StateError('Snapshot changed while preparing');
    }
    session?.records[key.key] = revision;
    if (rows.isEmpty || rows.single['deleted'] == 1) return null;
    return freezeJson(jsonDecode(rows.single['value'] as String));
  }

  Future<bool> entityExists(
    ModuleActor actor,
    String collection,
    String id,
  ) async {
    final value = await get(actor, collection, id);
    if (value == null) return false;
    final def = await definition(actor, collection);
    return CollectionQueryEngine.matches(
      object(value),
      def['entityActiveFilter'],
    );
  }

  Future<List<Object?>> query(
    ModuleActor actor,
    String collection,
    Map<String, Object?> options, {
    SnapshotSession? session,
  }) async {
    requireActive(actor);
    await definition(actor, collection);
    session?.participants[actor.moduleId] = actor;
    final scope = jsonEncode([actor.moduleId, actor.space, collection]);
    final revision =
        (await sql(
              'SELECT revision FROM host_collections WHERE module_id=? AND space=? AND name=?',
              [actor.moduleId, actor.space, collection],
            )).single['revision']
            as int;
    final previous = session?.collections[scope];
    if (previous != null && previous != revision) {
      throw StateError('Collection changed while preparing');
    }
    session?.collections[scope] = revision;
    final offset = options['offset'] as int? ?? 0,
        limit = options['limit'] as int? ?? 10000;
    if (offset < 0 || limit < 1 || limit > 10000) {
      throw const FormatException('Invalid pagination');
    }
    final overlay = (session?.writes.values ?? <Map<String, Object?>>[])
        .where(
          (write) =>
              write['moduleId'] == actor.moduleId &&
              write['space'] == actor.space &&
              write['collection'] == collection,
        )
        .toList();
    final trace = UiLoadTrace.start(
      'collection.query',
      arguments: {
        'moduleId': actor.moduleId,
        'collection': collection,
        'offset': offset,
        'limit': limit,
        'overlayWrites': overlay.length,
      },
    );
    var mode = overlay.isEmpty ? 'fallback' : 'overlay';
    var decoded = 0;
    var returned = 0;
    var outcome = 'error';
    try {
      if (overlay.isEmpty) {
        final page = await _queries.sqlPage(
          [actor.moduleId, actor.space, collection],
          collection,
          options,
          offset,
          limit,
          revision,
        );
        if (page != null) {
          mode = 'sql';
          decoded = page.length;
          returned = page.length;
          outcome = 'ok';
          return page;
        }
      }
      final result = await _queries.fallbackPage(
        [actor.moduleId, actor.space, collection],
        options,
        overlay,
        offset,
        limit,
      );
      // Multiple chunks must describe one revision, including outside a command.
      final current = await sql(
        'SELECT revision FROM host_collections WHERE module_id=? AND space=? AND name=?',
        [actor.moduleId, actor.space, collection],
      );
      if (current.isEmpty || current.single['revision'] != revision) {
        throw StateError('Collection changed while reading');
      }
      decoded = result.decoded;
      final page = result.page;
      returned = page.length;
      outcome = 'ok';
      return page;
    } finally {
      trace?.finish(
        arguments: {
          'mode': mode,
          'recordsDecoded': decoded,
          'returned': returned,
          'outcome': outcome,
        },
      );
    }
  }

  Future<void> stage(
    SnapshotSession session,
    ModuleActor actor,
    Map<String, Object?> result,
  ) async {
    requireActive(actor);
    session.participants[actor.moduleId] = actor;
    for (final raw in result['writes'] as List? ?? []) {
      final write = object(raw);
      final name = string(write['collection'], 'write.collection');
      final id = string(write['id'], 'write.id');
      final value = write['value'];
      final definition = await this.definition(actor, name);
      if (value != null) {
        validateSchema(value, object(definition['schema']));
        if (object(value)['id'] != id) {
          throw const FormatException('Record id mismatch');
        }
      }
      final before = await get(actor, name, id, session: session);
      final key = RecordKey(actor.moduleId, actor.space, name, id);
      if (canonicalJson(before) == canonicalJson(value)) continue;
      session.writes[key.key] = {
        'moduleId': actor.moduleId,
        'space': actor.space,
        'collection': name,
        'id': id,
        'value': freezeJson(value),
        'before': session.writes.containsKey(key.key)
            ? session.writes[key.key]!['before']
            : before,
      };
    }
    for (final raw in result['events'] as List? ?? []) {
      session.events.add({
        'moduleId': actor.moduleId,
        'event': freezeJson({
          ...object(raw),
          'automationDepth': session.automationDepth,
          'automationTrace': session.automationTrace,
        }),
      });
    }
    if (utf8.encode(canonicalJson(session.writes.values.toList())).length >
        8 * 1024 * 1024) {
      throw StateError('Plan exceeds data limit');
    }
    if (session.writes.length > 5000) {
      throw StateError('Plan exceeds write limit');
    }
  }

  ChangePlan seal(SnapshotSession session) {
    final id = const Uuid().v4();
    final content = object(
      freezeJson({
        'records': session.records,
        'nativeReads': session.nativeReads,
        'collections': session.collections,
        'writes': session.writes.values.toList(),
        'events': session.events,
        'participants': [
          for (final a in session.participants.values)
            {
              'moduleId': a.moduleId,
              'version': a.version,
              'space': a.space,
              'generation': a.generation,
            },
        ],
        'approvals': session.approvals,
        'result': session.result,
      }),
    );
    final plan = ChangePlan(
      id,
      session.caller,
      session.requestId,
      content,
      DateTime.now(),
    );
    _plans[id] = plan;
    _plans.removeWhere(
      (_, p) =>
          DateTime.now().difference(p.createdAt) > const Duration(minutes: 30),
    );
    return plan;
  }

  ChangePlan plan(String id, ModuleActor caller) {
    requireActive(caller);
    final p = _plans[id];
    if (p == null || !identical(p.caller, caller)) {
      throw StateError('Plan is missing or belongs to another caller');
    }
    return p;
  }

  ChangePlan adoptProviderPlan(String id, ModuleActor provider) {
    requireActive(provider);
    final source = _plans[id];
    if (source == null) {
      throw StateError('Import plan unavailable; prepare again');
    }
    requireActive(source.caller);
    final required = (source.content['approvals'] as List)
        .map(object)
        .where((a) => a['provider'] != null)
        .map((a) => a['provider'])
        .toSet();
    if (required.length != 1 ||
        required.single != provider.moduleId ||
        source.writes.any((w) => object(w)['moduleId'] != provider.moduleId)) {
      throw StateError('Provider confirmation scope denied');
    }
    final plan = ChangePlan(
      const Uuid().v4(),
      provider,
      'adopt:${source.id}',
      source.content,
      source.createdAt,
    );
    _plans[plan.id] = plan;
    return plan;
  }

  Future<Object?> commit(
    String id,
    ModuleActor caller, {
    required void Function(ChangePlan) authorize,
    bool audit = true,
  }) async {
    final p = plan(id, caller);
    final fingerprint = canonicalJson(p.content);
    bool changed = false;
    final result = await db.transaction(() async {
      requireActive(caller);
      authorize(p);
      final previous = await sql(
        'SELECT fingerprint,result FROM host_commits WHERE caller=? AND request_id=?',
        [caller.moduleId, p.requestId],
      );
      if (previous.isNotEmpty) {
        if (previous.single['fingerprint'] != fingerprint) {
          throw StateError('Idempotency request content changed');
        }
        return jsonDecode(previous.single['result'] as String);
      }
      for (final raw in p.content['participants'] as List) {
        final participant = object(raw);
        final a = _actors[participant['moduleId']];
        if (a == null ||
            a.version != participant['version'] ||
            a.space != participant['space'] ||
            a.generation != participant['generation']) {
          throw StateError('Plan refers to an old module instance');
        }
      }
      for (final e in object(p.content['nativeReads'] ?? {}).entries) {
        final resource = _nativeResources[e.key];
        if (resource == null) {
          throw StateError('Native resource unavailable: ${e.key}');
        }
        await resource.validateReads(db, object(e.value));
      }
      for (final e in object(p.content['records']).entries) {
        final key = jsonDecode(e.key) as List;
        final rows = await sql(
          'SELECT revision FROM host_records WHERE module_id=? AND space=? AND collection=? AND id=?',
          key,
        );
        if ((rows.isEmpty ? 0 : rows.single['revision']) != e.value) {
          throw StateError('Record conflict; prepare again');
        }
      }
      for (final e in object(p.content['collections']).entries) {
        final key = jsonDecode(e.key) as List;
        final rows = await sql(
          'SELECT revision FROM host_collections WHERE module_id=? AND space=? AND name=?',
          key,
        );
        if (rows.isEmpty || rows.single['revision'] != e.value) {
          throw StateError('Collection conflict; prepare again');
        }
      }
      for (final raw in p.writes) {
        final w = object(raw);
        await db.customStatement(
          'DELETE FROM host_indexes WHERE module_id=? AND space=? AND collection=? AND record_id=?',
          [w['moduleId'], w['space'], w['collection'], w['id']],
        );
      }
      final touched = <String>{};
      for (final raw in p.writes) {
        final w = object(raw);
        final key = [w['moduleId'], w['space'], w['collection'], w['id']];
        final value = w['value'];
        for (final resource in _nativeResources.values) {
          if (resource.ownsWrite(w)) await resource.applyWrite(db, w);
        }
        await db.customStatement(
          '''INSERT INTO host_records(module_id,space,collection,id,value,revision,deleted)
          VALUES(?,?,?,?,?,1,?) ON CONFLICT(module_id,space,collection,id) DO UPDATE SET
          value=excluded.value,revision=host_records.revision+1,deleted=excluded.deleted''',
          [
            ...key,
            value == null ? null : canonicalJson(value),
            value == null ? 1 : 0,
          ],
        );
        await db.customStatement(
          'DELETE FROM host_indexes WHERE module_id=? AND space=? AND collection=? AND record_id=?',
          key,
        );
        final actor = _actors[w['moduleId']]!;
        final def = await definition(actor, w['collection'] as String);
        if (value != null) {
          for (final index in def['indexes'] as List? ?? []) {
            final spec = object(index);
            final indexed = canonicalJson([
              for (final field in spec['fields'] as List)
                CollectionQueryEngine.field(value, field as String),
            ]);
            if (spec['unique'] == true) {
              final collision = await sql(
                'SELECT record_id FROM host_indexes WHERE module_id=? AND space=? AND collection=? AND index_name=? AND value=?',
                [
                  w['moduleId'],
                  w['space'],
                  w['collection'],
                  spec['id'],
                  indexed,
                ],
              );
              if (collision.isNotEmpty) {
                throw StateError('Unique index conflict');
              }
            }
            await db.customStatement(
              'INSERT INTO host_indexes VALUES(?,?,?,?,?,?)',
              [
                w['moduleId'],
                w['space'],
                w['collection'],
                spec['id'],
                w['id'],
                indexed,
              ],
            );
          }
        }
        touched.add(jsonEncode(key.take(3).toList()));
        if (audit) {
          final devices = await sql(
            "SELECT value FROM app_settings WHERE key='device_id'",
          );
          final deviceId = devices.isEmpty
              ? const Uuid().v4()
              : devices.single['value'] as String;
          if (devices.isEmpty) {
            await db.customStatement(
              "INSERT INTO app_settings VALUES('device_id',?)",
              [deviceId],
            );
          }
          final counters = await sql(
            "SELECT value FROM app_settings WHERE key='operation_counter'",
          );
          final counter =
              (int.tryParse(
                    counters.isEmpty ? '0' : counters.single['value'] as String,
                  ) ??
                  0) +
              1;
          await db.customStatement(
            "INSERT INTO app_settings VALUES('operation_counter',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            ['$counter'],
          );
          await db.customStatement(
            'INSERT INTO host_operations VALUES(?,?,?,?,?,?,?,?,?,?,?)',
            [
              const Uuid().v4(),
              id,
              caller.moduleId,
              w['moduleId'],
              w['collection'],
              w['id'],
              w['before'] == null ? null : canonicalJson(w['before']),
              value == null ? null : canonicalJson(value),
              DateTime.now().toUtc().toIso8601String(),
              deviceId,
              counter,
            ],
          );
        }
      }
      for (final scope in touched) {
        await db.customStatement(
          'UPDATE host_collections SET revision=revision+1 WHERE module_id=? AND space=? AND name=?',
          jsonDecode(scope) as List,
        );
      }
      for (final raw in audit ? p.content['events'] as List : []) {
        final e = object(raw);
        await db.customStatement(
          'INSERT INTO host_outbox(plan_id,module_id,event) VALUES(?,?,?)',
          [id, e['moduleId'], canonicalJson(e['event'])],
        );
      }
      await db.customStatement('INSERT INTO host_commits VALUES(?,?,?,?,?)', [
        id,
        caller.moduleId,
        p.requestId,
        fingerprint,
        canonicalJson(p.result),
      ]);
      changed = true;
      return p.result;
    });
    // Publish only after the transaction succeeds: conflicts and rolled-back
    // writes must not advance tokens, and idempotent retries change neither.
    if (changed && p.writes.isNotEmpty) {
      recordDataChange({
        for (final w in p.writes) object(w)['moduleId'] as String,
      });
    }
    if (changed && audit) {
      changes.add({for (final w in p.writes) object(w)['moduleId'] as String});
      await drainOutbox();
    }
    return result;
  }

  Future<void> _outboxTail = Future.value();
  Future<void> drainOutbox() {
    final next = _outboxTail.then((_) => _drainOutbox());
    _outboxTail = next.then((_) {}, onError: (Object error) {});
    return next;
  }

  Future<void> _drainOutbox() async {
    for (final row in await sql(
      'SELECT * FROM host_outbox WHERE delivered=0 ORDER BY id',
    )) {
      events.add({
        'moduleId': row['module_id'],
        'id': row['id'],
        'event': jsonDecode(row['event'] as String),
      });
      await db.customStatement(
        'UPDATE host_outbox SET delivered=1 WHERE id=?',
        [row['id']],
      );
    }
  }

  Future<void> close() async {
    await changes.close();
    await events.close();
  }
}
