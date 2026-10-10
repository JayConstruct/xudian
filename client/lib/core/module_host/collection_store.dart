import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/app_database.dart';
import '../contracts/json_values.dart';
import 'json_schema.dart';
import 'module_package.dart';

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
  final events = StreamController<Map<String, Object?>>.broadcast();
  final _plans = <String, ChangePlan>{};
  final _actors = <String, ModuleActor>{};
  final _sqlPageCompatibility = <String, bool>{};
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
                _path(value, field as String),
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
    return _filter(object(value), def['entityActiveFilter']);
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
    if (session == null || session.writes.isEmpty) {
      final page = await _querySqlPage(
        actor,
        collection,
        options,
        offset,
        limit,
        revision,
      );
      if (page != null) return page;
    }
    final rows = await sql(
      'SELECT id,value FROM host_records WHERE module_id=? AND space=? AND collection=? AND deleted=0 ORDER BY id',
      [actor.moduleId, actor.space, collection],
    );
    final values = <String, Object?>{
      for (final row in rows)
        row['id'] as String: jsonDecode(row['value'] as String),
    };
    for (final write in session?.writes.values ?? <Map<String, Object?>>[]) {
      if (write['moduleId'] == actor.moduleId &&
          write['space'] == actor.space &&
          write['collection'] == collection) {
        if (write['value'] == null) {
          values.remove(write['id']);
        } else {
          values[write['id'] as String] = write['value'];
        }
      }
    }
    final result = values.values
        .where((v) => _filter(object(v), options['filter']))
        .toList();
    final sorts = options['sort'] as List? ?? [];
    if (sorts.isNotEmpty) {
      result.sort((a, b) {
        for (final raw in sorts) {
          final s = object(raw);
          final av = _path(a, s['field'] as String),
              bv = _path(b, s['field'] as String);
          var cmp = _compare(av, bv);
          if (s['direction'] == 'desc') cmp = -cmp;
          if (cmp != 0) return cmp;
        }
        return '${object(a)['id']}'.compareTo('${object(b)['id']}');
      });
    }
    return (freezeJson(result.skip(offset).take(limit).toList()) as List)
        .cast<Object?>();
  }

  /// Keep filtering and pagination inside SQLite when its scalar semantics
  /// exactly match the Dart fallback. Checks return metadata only, never records.
  Future<List<Object?>?> _querySqlPage(
    ModuleActor actor,
    String collection,
    Map<String, Object?> options,
    int offset,
    int limit,
    int revision,
  ) async {
    final compiler = _ScalarQueryCompiler();
    final predicate = compiler.filter(options['filter']);
    if (predicate == null) return null;
    final scope = [actor.moduleId, actor.space, collection];
    const where = 'module_id=? AND space=? AND collection=? AND deleted=0';
    final sorts = options['sort'] as List? ?? [];
    if (sorts.length > 64 || compiler.args.length > 700) return null;
    final compatibilityKey = canonicalJson({
      'scope': scope,
      'revision': revision,
      'sort': sorts,
      'types': compiler.typeChecks.map(
        (key, value) => MapEntry(key, value.toList()),
      ),
      'ascii': compiler.asciiChecks.toList(),
    });
    final cached = _sqlPageCompatibility[compatibilityKey];
    if (cached == false) return null;
    void cache(bool compatible) {
      if (_sqlPageCompatibility.length >= 128) _sqlPageCompatibility.clear();
      _sqlPageCompatibility[compatibilityKey] = compatible;
    }

    final orderBy = <String>[];
    final orderArgs = <Object?>[];
    for (final raw in sorts) {
      final sort = object(raw);
      final path = compiler.path(sort['field']);
      if (path == null) return null;
      orderBy.add(
        "json_extract(value,?) ${sort['direction'] == 'desc' ? 'DESC' : 'ASC'}",
      );
      orderArgs.add(path);
      if (cached == true) continue;
      final kinds =
          (await sql(
                'SELECT DISTINCT json_type(value,?) AS kind FROM host_records WHERE $where',
                [path, ...scope],
              ))
              .map((row) => row['kind'])
              .where((kind) => kind != null && kind != 'null')
              .toSet();
      if (kinds.every((kind) => kind == 'integer' || kind == 'real')) {
        // Nulls sort first ascending, as in _compare.
      } else if (kinds.every((kind) => kind == 'text')) {
        compiler.asciiChecks.add(path);
      } else if (kinds.every((kind) => kind == 'true' || kind == 'false')) {
        // Both booleans have the same order as their Dart string values.
      } else {
        cache(false);
        return null;
      }
    }
    if (cached != true) {
      for (final check in compiler.typeChecks.entries) {
        final placeholders = List.filled(check.value.length, '?').join(',');
        final invalid = await sql(
          'SELECT 1 FROM host_records WHERE $where AND '
          'json_type(value,?) IS NOT NULL AND json_type(value,?) NOT IN ($placeholders) LIMIT 1',
          [...scope, check.key, check.key, ...check.value],
        );
        if (invalid.isNotEmpty) {
          cache(false);
          return null;
        }
      }
      for (final path in compiler.asciiChecks) {
        final invalid = await sql(
          'SELECT 1 FROM host_records WHERE $where AND json_type(value,?)=\'text\' AND '
          'length(CAST(json_extract(value,?) AS BLOB)) != length(json_extract(value,?)) LIMIT 1',
          [...scope, path, path, path],
        );
        if (invalid.isNotEmpty) {
          cache(false);
          return null;
        }
      }
      // Record IDs are the stable tiebreaker. Non-ASCII IDs use the Dart path so
      // ordering also remains exact for UTF-16 surrogate pairs.
      final unicodeIds = await sql(
        'SELECT 1 FROM host_records WHERE $where AND length(CAST(id AS BLOB)) != length(id) LIMIT 1',
        scope,
      );
      if (unicodeIds.isNotEmpty) {
        cache(false);
        return null;
      }
      cache(true);
    }
    orderBy.add('id ASC');
    final rows = await sql(
      'SELECT id,value FROM host_records WHERE $where AND ($predicate) '
      'ORDER BY ${orderBy.join(',')} LIMIT ? OFFSET ?',
      [...scope, ...compiler.args, ...orderArgs, limit, offset],
    );
    return (freezeJson([
      for (final row in rows) jsonDecode(row['value'] as String),
    ]) as List).cast<Object?>();
  }

  Object? _path(Object? value, String path) {
    for (final part in path.split('.')) {
      if (value is! Map) return null;
      value = value[part];
    }
    return value;
  }

  int _compare(Object? a, Object? b) => a == b
      ? 0
      : a == null
      ? -1
      : b == null
      ? 1
      : a is num && b is num
      ? a.compareTo(b)
      : '$a'.compareTo('$b');
  bool _filter(Map<String, Object?> value, Object? raw) {
    if (raw == null) return true;
    final f = object(raw);
    if (f['all'] is List) {
      return (f['all'] as List).every((v) => _filter(value, v));
    }
    if (f['any'] is List) {
      return (f['any'] as List).any((v) => _filter(value, v));
    }
    final actual = _path(value, string(f['field'], 'filter.field')),
        expected = f['value'];
    return switch (f['op']) {
      'eq' => canonicalJson(actual) == canonicalJson(expected),
      'ne' => canonicalJson(actual) != canonicalJson(expected),
      'isNull' => actual == null,
      'notNull' => actual != null,
      'in' =>
        expected is List &&
            expected.any((v) => canonicalJson(v) == canonicalJson(actual)),
      'contains' =>
        actual is String && expected is String && actual.contains(expected),
      'lt' =>
        actual != null && expected != null && _compare(actual, expected) < 0,
      'lte' =>
        actual != null && expected != null && _compare(actual, expected) <= 0,
      'gt' =>
        actual != null && expected != null && _compare(actual, expected) > 0,
      'gte' =>
        actual != null && expected != null && _compare(actual, expected) >= 0,
      _ => throw FormatException('Unsupported filter operation: ${f['op']}'),
    };
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
        final rows = await sql('SELECT value FROM app_settings WHERE key=?', [
          e.key,
        ]);
        if ((rows.isEmpty ? null : rows.single['value']) != e.value) {
          throw StateError('Host setting conflict; prepare again');
        }
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
        if (w['moduleId'] == 'app.host' && w['collection'] == 'settings') {
          if (value == null) {
            throw StateError('Host settings cannot be deleted');
          }
          await db.customStatement(
            'INSERT INTO app_settings VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
            [w['id'], canonicalJson(object(value)['values'])],
          );
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
                _path(value, field as String),
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

/// SQL supports only values whose equality and ordering agree with canonical
/// JSON and _compare. Unsupported shapes intentionally retain the Dart path.
class _ScalarQueryCompiler {
  final args = <Object?>[];
  final typeChecks = <String, Set<String>>{};
  final asciiChecks = <String>{};
  int _nodes = 0;

  String? path(Object? field) {
    if (field is! String || field.isEmpty) return null;
    final parts = field.split('.');
    if (parts.any(
      (part) => !RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(part),
    )) {
      return null;
    }
    return r'$' + parts.map((part) => '."$part"').join();
  }

  void requireTypes(String path, Set<String> kinds) {
    final previous = typeChecks[path];
    if (previous == null) {
      typeChecks[path] = kinds;
    } else {
      previous.retainAll(kinds);
    }
  }

  String? filter(Object? raw, [int depth = 0]) {
    if (raw == null) return '1';
    if (depth > 32 || ++_nodes > 128 || raw is! Map) return null;
    final f = raw.cast<String, Object?>();
    for (final group in ['all', 'any']) {
      if (f[group] is List) {
        final clauses = <String>[];
        for (final child in f[group] as List) {
          final compiled = filter(child, depth + 1);
          if (compiled == null) return null;
          clauses.add('($compiled)');
        }
        if (clauses.isEmpty) return group == 'all' ? '1' : '0';
        return clauses.join(group == 'all' ? ' AND ' : ' OR ');
      }
    }
    final jsonPath = path(f['field']);
    if (jsonPath == null) return null;
    final expected = f['value'];
    switch (f['op']) {
      case 'isNull':
        args.add(jsonPath);
        return "COALESCE(json_type(value,?), 'null')='null'";
      case 'notNull':
        args.add(jsonPath);
        return "COALESCE(json_type(value,?), 'null')!='null'";
      case 'eq':
      case 'ne':
        final equal = equality(jsonPath, expected);
        return equal == null
            ? null
            : f['op'] == 'eq'
            ? equal
            : 'NOT ($equal)';
      case 'in':
        if (expected is! List) return '0';
        if (expected.isEmpty) return '0';
        if (expected.length > 128) return null;
        final clauses = <String>[];
        for (final value in expected) {
          final equal = equality(jsonPath, value);
          if (equal == null) return null;
          clauses.add('($equal)');
        }
        return clauses.join(' OR ');
      case 'lt':
      case 'lte':
      case 'gt':
      case 'gte':
        if (expected == null) return '0';
        if (expected is num && expected.isFinite) {
          requireTypes(jsonPath, {'null', 'integer', 'real'});
        } else if (expected is String &&
            expected.codeUnits.every((c) => c > 0 && c < 128)) {
          requireTypes(jsonPath, {'null', 'text'});
          asciiChecks.add(jsonPath);
        } else {
          return null;
        }
        final operator = {
          'lt': '<',
          'lte': '<=',
          'gt': '>',
          'gte': '>=',
        }[f['op']];
        args.addAll([jsonPath, canonicalJson(expected)]);
        return "COALESCE(json_extract(value,?) $operator json_extract(?, '\$'),0)";
      default:
        return null;
    }
  }

  String? equality(String path, Object? expected) {
    if (expected == null) {
      args.add(path);
      return "COALESCE(json_type(value,?), 'null')='null'";
    }
    if (expected is bool) {
      args.add(path);
      return "COALESCE(json_type(value,?)='${expected ? 'true' : 'false'}',0)";
    }
    if (expected is String || expected is int) {
      args.addAll([
        path,
        expected is String ? 'text' : 'integer',
        path,
        canonicalJson(expected),
      ]);
      return "COALESCE(json_type(value,?)=? AND json_extract(value,?)=json_extract(?, '\$'),0)";
    }
    return null;
  }
}
