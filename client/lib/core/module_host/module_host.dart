import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:pub_semver/pub_semver.dart';

import '../modules/module_registry.dart';
import '../security/capability_registry.dart';
import 'script_app_module.dart';

import 'package:drift/native.dart';

import '../../data/app_database.dart';

import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as zones;
import 'package:xquickjs/xquickjs.dart';

import '../contracts/json_values.dart';
import '../ui/ui_pack.dart';
import 'collection_store.dart';
import 'json_schema.dart';
import 'legacy_migration.dart';
import 'module_package.dart';

class ServiceRef {
  const ServiceRef(this.moduleId, this.serviceId, this.major);
  final String moduleId, serviceId;
  final int major;
  factory ServiceRef.parse(Object? value) {
    final v = object(value, 'ServiceRef');
    return ServiceRef(
      string(v['moduleId'], 'moduleId'),
      string(v['serviceId'], 'serviceId'),
      v['majorVersion'] as int,
    );
  }
  String get key => '$moduleId/$serviceId@$major';
  Map<String, Object?> toJson() => {
    'moduleId': moduleId,
    'serviceId': serviceId,
    'majorVersion': major,
  };
}

class ScriptInstance {
  ScriptInstance(this.package, this.actor);
  final ScriptPackage package;
  final ModuleActor actor;
  JavaScriptWorker? _worker, _workflow;
  JavaScriptWorker get worker =>
      _worker ?? (throw StateError('UI packs do not have JavaScript workers'));
  set worker(JavaScriptWorker value) => _worker = value;
  JavaScriptWorker get workflow =>
      _workflow ??
      (throw StateError('UI packs do not have JavaScript workers'));
  set workflow(JavaScriptWorker value) => _workflow = value;
  bool get hasWorkers => _worker != null && _workflow != null;
  void closeWorkers() {
    _worker?.close();
    _workflow?.close();
  }

  Future<void> workflowTail = Future.value();
  SnapshotSession? session;
  Set<String>? pageReads;
  final subscriptions = <String, StreamSubscription>{};
  Future<void> tail = Future.value();
  Future<Object?> run(
    String handler,
    Object? input,
    SnapshotSession? snapshot, {
    bool computation = true,
  }) {
    final completer = Completer<Object?>();
    tail = tail.then((_) async {
      session = snapshot;
      try {
        completer.complete(
          await worker.invoke(
            handler,
            input,
            timeout: computation ? const Duration(seconds: 10) : null,
          ),
        );
      } catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        session = null;
      }
    });
    return completer.future;
  }
}

class HostGrant {
  HostGrant(
    this.id,
    this.caller,
    this.scopes,
    this.expiresAt, {
    this.remainingWrites = 20,
  });
  final String id;
  final ModuleActor caller;
  final Set<String> scopes;
  final DateTime expiresAt;
  int remainingWrites;
  bool revoked = false;
  bool get valid =>
      !revoked && remainingWrites > 0 && DateTime.now().isBefore(expiresAt);
}

typedef HostInteraction = Future<Object?> Function(
  ModuleActor caller,
  String method,
  Map<String, Object?> arguments,
);

class NativeHostService {
  NativeHostService(this.definition, this.call);
  final Map<String, Object?> definition;
  final Future<Object?> Function(
    ModuleActor caller,
    Object? input,
    SnapshotSession session,
  )
  call;
}

class HostInstallBatchPlan {
  HostInstallBatchPlan._(
    this.id,
    List<ScriptPackage> packages,
    Map<String, String> repositories,
    this.baseline,
  ) : packages = List.unmodifiable(packages),
      repositories = Map.unmodifiable(repositories);
  final String id, baseline;
  final List<ScriptPackage> packages;
  final Map<String, String> repositories;
}

class ModuleHost {
  ModuleHost({required this.store, required this.directory, this.interaction});
  final CollectionStore store;
  final Directory directory;
  HostInteraction? interaction;
  void Function(ScriptPackage candidate)? validateCandidate;
  bool preview = false;
  bool _batchInstalling = false;
  final _installBatchPlans = <String, HostInstallBatchPlan>{};
  void discardInstallBatch(HostInstallBatchPlan plan) =>
      _installBatchPlans.remove(plan.id);
  void _notifyRegistry() {
    if (!_batchInstalling) registryChanges.add(null);
  }

  DateTime Function() clockNow = DateTime.now;
  void Function(ModuleActor)? onDeactivate;
  Future<void> Function(String moduleId)? onDeleteData;
  final nativeServices = <String, NativeHostService>{};
  final nativeActor = ModuleActor('app.host', '1.0.0', 'host-controls', 1, {
    'packages.prepare',
  });
  void Function(ChangePlan plan)? validateNativePlan;
  final _workflowEpoch = <String, int>{};
  final instances = <String, ScriptInstance>{};
  final grants = <String, HostGrant>{};
  final registryChanges = StreamController<void>.broadcast();
  final failures = <String, String>{};
  final pageSessions = <String, Map<String, Object?>>{};
  final _reviewed = <String>{};
  final _grantsUsed = <String, Set<String>>{};
  final _proposals = <String, Map<String, Object?>>{};
  final _migrationInstances = <String>{};
  Future<void> _lifecycle = Future.value();
  StreamSubscription? _automationSubscription;
  Future<void> _automationTail = Future.value();
  Future<void> drainAutomation() => _automationTail;
  Future<void> _serialize(Future<void> Function() operation) {
    final next = _lifecycle.then((_) => operation());
    _lifecycle = next.then((_) {}, onError: (Object error) {});
    return next;
  }

  Future<void> initialize() async {
    zones.initializeTimeZones();
    await directory.create(recursive: true);
    await migrateLegacyData(store);
    store.activate(nativeActor);
    await store.db.customStatement(
      'INSERT OR IGNORE INTO host_collections(module_id,space,name,definition) VALUES(?,?,?,?)',
      [
        'app.host',
        'host-controls',
        'settings',
        canonicalJson({
          'id': 'settings',
          'schema': {
            'type': 'object',
            'required': ['id', 'values'],
            'properties': {
              'id': {'type': 'string'},
              'values': {'type': 'object'},
            },
          },
        }),
      ],
    );
    for (final table in ['host_records', 'host_collections', 'host_indexes']) {
      await store.db.customStatement(
        'DELETE FROM $table WHERE space NOT IN (?,?) AND space NOT IN (SELECT space FROM host_installations UNION SELECT space FROM host_snapshots)',
        ['legacy-v1', 'host-controls'],
      );
    }
    final registeredDigests = (await store.sql(
      'SELECT digest FROM host_packages',
    )).map((row) => row['digest']).toSet();
    for (final file in await directory.list().toList()) {
      if (file is! File) continue;
      final name = file.uri.pathSegments.last;
      if (name.endsWith('.candidate') ||
          (RegExp(r'^[a-f0-9]{64}\.xmodule$').hasMatch(name) &&
              !registeredDigests.contains(name.substring(0, 64)))) {
        await file.delete();
      }
    }
    // The database points only at committed content-addressed packages.
    final installations = await store.sql(
      'SELECT * FROM host_installations WHERE installed=1 AND enabled=1',
    );
    final pending = {
      for (final row in installations) row['module_id'] as String: row,
    };
    while (pending.isNotEmpty) {
      var progress = false;
      for (final id in pending.keys.toList()) {
        final row = pending[id]!;
        try {
          final package = await _storedPackage(id, row['version'] as String);
          if (package.dependencies.any(pending.containsKey)) continue;
          _validateDependencies(package);
          await _activate(
            package,
            row['space'] as String,
            row['generation'] as int,
          );
          pending.remove(id);
          progress = true;
        } catch (error) {
          await _fail(id, '$error');
          pending.remove(id);
          progress = true;
        }
      }
      if (!progress) {
        for (final id in pending.keys) {
          await _fail(id, 'Missing or circular dependency');
        }
        break;
      }
    }
    _automationSubscription ??= store.events.stream.listen((message) {
      _automationTail = _automationTail
          .then((_) => _automate(message))
          .catchError((Object error) {});
    });
    await store.drainOutbox();
  }

  Future<void> _fail(String id, String reason) async {
    failures[id] = reason;
    await store.db.customStatement(
      'UPDATE host_installations SET enabled=0,error=? WHERE module_id=?',
      [reason, id],
    );
  }

  Future<ScriptPackage> _storedPackage(String id, String version) async {
    final row = (await store.sql(
      'SELECT * FROM host_packages WHERE module_id=? AND version=?',
      [id, version],
    )).single;
    final bytes = await File('${directory.path}/${row['digest']}.xmodule')
        .readAsBytes();
    // Revalidate every file. Trust is derived from previously verified immutable
    // database provenance, never from the package's own channel claim.
    final package = await ScriptPackage.verify(
      bytes,
      preinstalledDigest: row['digest'] as String,
    );
    if (package.id != id || package.version != version) {
      throw StateError('Stored package identity mismatch');
    }
    return package.withStoredOrigin(row['origin'] as String);
  }

  void _validateDependencies(ScriptPackage package) {
    final visiting = <String>{}, visited = <String>{};
    void visit(ScriptPackage current) {
      if (!visiting.add(current.id)) {
        throw StateError('Circular module dependency: ${current.id}');
      }
      for (final id in current.dependencies) {
        if (visited.contains(id)) continue;
        final dependency = id == package.id ? package : instances[id]?.package;
        if (dependency != null) visit(dependency);
      }
      visiting.remove(current.id);
      visited.add(current.id);
    }

    visit(package);
    for (final id in package.dependencies) {
      if (!instances.containsKey(id) || id == package.id) {
        throw StateError('Missing dependency: $id');
      }
      if (!package.acceptsDependency(id, instances[id]!.package.version)) {
        throw StateError('Incompatible dependency version: $id');
      }
    }
    if (package.isUiPack) {
      for (final id in package.dependencies) {
        if (!instances[id]!.package.isUiPack) {
          throw StateError('UI packs may depend only on other UI packs: $id');
        }
      }
      package.uiPack!.validateDependencies({
        for (final entry in instances.entries)
          if (entry.value.package.uiPack != null)
            entry.key: entry.value.package.uiPack!,
      }, package.dependencies);
    }
    for (final raw in package.requiredServices) {
      final ref = ServiceRef.parse(raw);
      if (ref.moduleId != package.id) _service(ref);
    }
  }

  Future<ScriptInstance> _activate(
    ScriptPackage package,
    String space,
    int generation, {
    bool publish = true,
  }) async {
    final actor = ModuleActor(
      package.id,
      package.version,
      space,
      generation,
      package.permissions.toSet(),
    );
    final instance = ScriptInstance(package, actor);
    store.activate(actor);
    if (package.isUiPack) {
      if (publish) instances[package.id] = instance;
      return instance;
    }
    JavaScriptWorker? computation, workflow;
    try {
      computation = JavaScriptWorker(
        package.scripts,
        memoryLimit: 32 * 1024 * 1024,
        host: (method, args) => _bridge(instance, method, object(args ?? {})),
      );
      workflow = JavaScriptWorker(
        package.scripts,
        memoryLimit: 32 * 1024 * 1024,
        host: (method, args) =>
            _bridge(instance, method, object(args ?? {}), workflow: true),
      );
      instance.worker = computation;
      instance.workflow = workflow;
      await instance.worker.load(package.definition['entryPoint'] as String);
      await instance.workflow.load(package.definition['entryPoint'] as String);
    } catch (error) {
      computation?.close();
      workflow?.close();
      store.deactivate(package.id);
      rethrow;
    }
    if (publish) instances[package.id] = instance;
    return instance;
  }

  Future<Map<String, ScriptPackage>> installedPackages() async => {
    for (final row in await store.sql(
      'SELECT module_id,version FROM host_installations WHERE installed=1',
    ))
      row['module_id'] as String: await _storedPackage(
        row['module_id'] as String,
        row['version'] as String,
      ),
  };

  Future<String?> repositoryFor(String id) async {
    final rows = await store.sql('SELECT value FROM host_meta WHERE key=?', [
      'module-repository:$id',
    ]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<String> _installationBaseline() async => canonicalJson({
    'installations': await store.sql(
      'SELECT * FROM host_installations ORDER BY module_id',
    ),
    'packages': await store.sql(
      'SELECT module_id,version,digest,origin,release FROM host_packages ORDER BY module_id,version',
    ),
    'repositories': await store.sql(
      "SELECT * FROM host_meta WHERE key LIKE 'module-repository:%' ORDER BY key",
    ),
  });

  /// A review binds immutable package bytes and the complete installation state.
  Future<HostInstallBatchPlan> prepareInstallBatch(
    List<ScriptPackage> packages, {
    Map<String, String> repositories = const {},
  }) async {
    final baseline = await _installationBaseline();
    final byId = <String, ScriptPackage>{};
    if (repositories.keys.any((id) => !packages.any((p) => p.id == id)) ||
        repositories.values.any(
          (repository) =>
              !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')
                  .hasMatch(repository),
        )) {
      throw StateError('Invalid release repository binding');
    }
    for (final package in packages) {
      if ([
        'app.modulemanager',
        'app.host',
        'app.ui.default',
      ].contains(package.id)) {
        throw StateError('Host control identity is reserved');
      }
      if (byId.containsKey(package.id)) {
        throw StateError(
          'Duplicate module in installation batch: ${package.id}',
        );
      }
      byId[package.id] = package;
      final previous = await repositoryFor(package.id);
      final history = await store.sql(
        'SELECT origin,release,definition,digest,version FROM host_packages WHERE module_id=?',
        [package.id],
      );
      if (history.any((row) => row['origin'] == 'preinstalled')) {
        if (package.origin != 'preinstalled') {
          throw StateError(
            'Official module identity requires its original release source',
          );
        }
        if (repositories[package.id] != null &&
            repositories[package.id]!.toLowerCase() !=
                (previous ?? 'JayConstruct/xudian').toLowerCase()) {
          throw StateError('Official module release repository cannot change');
        }
      }
      if (history.any(
        (row) =>
            row['origin'] == 'market' &&
            (package.origin != 'market' ||
                object(jsonDecode(row['release'] as String))['publisherId'] !=
                    package.release['publisherId']),
      )) {
        throw StateError('Publisher identity cannot change');
      }
      if (history.any(
        (row) =>
            row['version'] == package.version &&
            row['digest'] != package.packageDigest,
      )) {
        throw StateError('Module version and source are immutable');
      }
      if (previous != null &&
          repositories[package.id] != null &&
          previous.toLowerCase() != repositories[package.id]!.toLowerCase()) {
        throw StateError('Release repository cannot change: ${package.id}');
      }
      final rows = await store.sql(
        'SELECT version,installed FROM host_installations WHERE module_id=?',
        [package.id],
      );
      if (rows.isNotEmpty &&
          rows.single['installed'] == 1 &&
          Version.parse(package.version) <
              Version.parse(rows.single['version'] as String)) {
        throw StateError('Automatic downgrade is forbidden: ${package.id}');
      }
    }
    final selected = {
      for (final instance in instances.values)
        instance.package.id: instance.package,
      ...byId,
    };
    _validateBatchGraph(selected);
    final ordered = <ScriptPackage>[];
    final visited = <String>{};
    void visit(ScriptPackage package) {
      if (!visited.add(package.id)) return;
      for (final id in package.dependencies) {
        if (byId[id] != null) visit(byId[id]!);
      }
      ordered.add(package);
    }

    for (final package in packages) {
      visit(package);
    }
    if (baseline != await _installationBaseline()) {
      throw StateError(
        'Installation state changed; resolve dependencies again',
      );
    }
    final plan = HostInstallBatchPlan._(
      const Uuid().v4(),
      ordered,
      repositories,
      baseline,
    );
    _installBatchPlans[plan.id] = plan;
    return plan;
  }

  void _validateBatchGraph(Map<String, ScriptPackage> selected) {
    final visiting = <String>{}, visited = <String>{};
    void visit(ScriptPackage package) {
      if (visited.contains(package.id)) return;
      if (!visiting.add(package.id)) {
        throw StateError('Circular module dependency: ${package.id}');
      }
      for (final id in package.dependencies) {
        final dependency = selected[id];
        if (dependency == null ||
            !package.acceptsDependency(id, dependency.version)) {
          throw StateError(
            'Unsatisfied dependency: ${package.id} requires $id',
          );
        }
        visit(dependency);
      }
      for (final raw in package.requiredServices) {
        final ref = ServiceRef.parse(raw);
        final services = ref.moduleId == 'app.host'
            ? nativeServices.values.map((s) => s.definition)
            : (selected[ref.moduleId]?.definition['services'] as List? ?? [])
                  .map(object);
        if (!services.any(
          (s) =>
              s['id'] == ref.serviceId &&
              (ref.moduleId == 'app.host'
                  ? ref.major == 1
                  : s['major'] == ref.major) &&
              (raw['kind'] == null || raw['kind'] == s['kind']),
        )) {
          throw StateError(
            'Unsatisfied service: ${package.id} requires ${ref.key}',
          );
        }
      }
      visiting.remove(package.id);
      visited.add(package.id);
    }

    for (final package in selected.values) {
      visit(package);
    }
  }

  Future<void> commitInstallBatch(
    HostInstallBatchPlan plan,
  ) => _serialize(() async {
    if (!identical(_installBatchPlans.remove(plan.id), plan)) {
      throw StateError('Installation plan expired or already used');
    }
    if (await _installationBaseline() != plan.baseline) {
      throw StateError(
        'Installation state changed; resolve dependencies again',
      );
    }
    if (plan.packages.isEmpty) return;
    final priorRows = await store.sql('SELECT * FROM host_installations');
    final priorPackages = {
      for (final instance in instances.values)
        instance.package.id: instance.package,
    };
    final priorFailures = Map<String, String>.of(failures);
    final rowsById = {
      for (final row in priorRows) row['module_id'] as String: row,
    };
    // Quiesce runtime participants before moving any database pointers. Other
    // lifecycle operations are serialized, and stale data plans lose actors.
    _batchInstalling = true;
    try {
      for (final id in instances.keys.toList()) {
        _stop(id);
      }
      await store.db.transaction(() async {
        // Restart the complete final graph in dependency order. Reused modules
        // must be available before candidates that depend on them, while reused
        // dependents must wait for a candidate provider's new version.
        final candidates = {
          for (final package in plan.packages) package.id: package,
        };
        final pending = {...priorPackages, ...candidates};
        while (pending.isNotEmpty) {
          final available = pending.values
              .where(
                (package) => package.dependencies.every(instances.containsKey),
              )
              .toList();
          if (available.isEmpty) {
            throw StateError('Cannot activate final dependency graph');
          }
          for (final package in available) {
            if (!candidates.containsKey(package.id)) {
              await _enable(package.id);
              pending.remove(package.id);
              continue;
            }
            final row = rowsById[package.id];
            if (row != null &&
                row['installed'] == 1 &&
                row['version'] == package.version) {
              final existing = await _storedPackage(
                package.id,
                package.version,
              );
              if (existing.packageDigest != package.packageDigest) {
                throw StateError('Module version and source are immutable');
              }
              await _enable(package.id);
            } else {
              await _install(package);
            }
            final repository = plan.repositories[package.id];
            if (repository != null) {
              await store.db.customStatement(
                'INSERT INTO host_meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
                ['module-repository:${package.id}', repository],
              );
            }
            pending.remove(package.id);
          }
        }
        _validateBatchGraph({
          for (final instance in instances.values)
            instance.package.id: instance.package,
        });
        for (final instance in instances.values) {
          _validateDependencies(instance.package);
          validateCandidate?.call(instance.package);
        }
        final registry = ModuleRegistry([
          for (final instance in instances.values)
            ScriptAppModule(this, instance.package),
        ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
        registry.dispose();
      });
    } catch (error) {
      final callback = onDeactivate;
      onDeactivate = null;
      try {
        for (final id in instances.keys.toList()) {
          _stop(id);
        }
      } finally {
        onDeactivate = callback;
      }
      failures
        ..clear()
        ..addAll(priorFailures);
      final pending = Map<String, ScriptPackage>.of(priorPackages);
      while (pending.isNotEmpty) {
        final available = pending.values
            .where((p) => p.dependencies.every(instances.containsKey))
            .toList();
        if (available.isEmpty) {
          throw StateError('Failed to restore previous runtime after: $error');
        }
        for (final package in available) {
          final row = rowsById[package.id]!;
          await _activate(
            package,
            row['space'] as String,
            row['generation'] as int,
          );
          pending.remove(package.id);
        }
      }
      rethrow;
    } finally {
      _batchInstalling = false;
      registryChanges.add(null);
    }
  });

  List<String> affectedDependents(String id) {
    final affected = <String>{};
    void visit(String current) {
      for (final dependent in dependents(current)) {
        if (affected.add(dependent)) visit(dependent);
      }
    }

    visit(id);
    return affected.toList();
  }

  Future<void> install(ScriptPackage package) =>
      _serialize(() => _install(package));
  Future<void> _install(ScriptPackage package) async {
    if ([
      'app.modulemanager',
      'app.host',
      'app.ui.default',
    ].contains(package.id)) {
      throw StateError('Host control identity is reserved');
    }
    if (!_batchInstalling) validateCandidate?.call(package);
    _validateDependencies(package);
    final current = await store.sql(
      'SELECT * FROM host_installations WHERE module_id=?',
      [package.id],
    );
    final previousVersions = await store.sql(
      'SELECT * FROM host_packages WHERE module_id=? AND version=?',
      [package.id, package.version],
    );
    if (previousVersions.isNotEmpty &&
        previousVersions.single['digest'] != package.packageDigest) {
      throw StateError('Module version and source are immutable');
    }
    final history = await store.sql(
      'SELECT origin,release,definition FROM host_packages WHERE module_id=?',
      [package.id],
    );
    if (history.any(
      (row) =>
          (object(
                object(jsonDecode(row['definition'] as String))['manifest'],
              )['kind'] ==
              'uiPack') !=
          package.isUiPack,
    )) {
      throw StateError('Installed module kind cannot change');
    }
    if (history.any((row) => row['origin'] == 'preinstalled') &&
        package.origin != 'preinstalled') {
      throw StateError(
        'Official module identity requires its original release source',
      );
    }
    if (history.any(
      (row) =>
          row['origin'] == 'market' &&
          (package.origin != 'market' ||
              object(jsonDecode(row['release'] as String))['publisherId'] !=
                  package.release['publisherId']),
    )) {
      throw StateError('Publisher identity cannot change');
    }
    final blob = File('${directory.path}/${package.packageDigest}.xmodule');
    if (!await blob.exists()) {
      final pending = File('${blob.path}.candidate');
      await pending.writeAsBytes(package.bytes, flush: true);
      await pending.rename(blob.path);
    }
    final prior = current.isEmpty ? null : current.single;
    final old = instances[package.id];
    final oldSpace = prior?['space'] as String?;
    final oldDataVersion = prior?['data_version'] as int?;
    if (oldDataVersion != null && package.dataVersion < oldDataVersion) {
      throw StateError(
        'Use explicit snapshot recovery for incompatible rollback',
      );
    }
    final space = const Uuid().v4();
    final generation = (prior?['generation'] as int? ?? 0) + 1;
    final paused = <String>[];
    void pauseDependents(String id) {
      for (final dependent in dependents(id)) {
        if (paused.contains(dependent)) continue;
        pauseDependents(dependent);
        paused.add(dependent);
        _stop(dependent);
      }
    }

    if (old != null) {
      if (package.isUiPack) {
        final available = {
          for (final entry in instances.entries)
            if (entry.value.package.uiPack != null)
              entry.key: entry.value.package.uiPack!,
          package.id: package.uiPack!,
        };
        for (final dependent in instances.values) {
          if (dependent.package.isUiPack &&
              dependent.package.dependencies.contains(package.id)) {
            dependent.package.uiPack!.validateDependencies(
              available,
              dependent.package.dependencies,
            );
          }
        }
      }
      for (final id in dependents(package.id)) {
        if (!instances[id]!.package.acceptsDependency(
          package.id,
          package.version,
        )) {
          throw StateError('Update would break module dependency: $id');
        }
        for (final raw in instances[id]!.package.requiredServices) {
          final ref = ServiceRef.parse(raw);
          if (ref.moduleId == package.id &&
              !(package.definition['services'] as List? ?? []).any(
                (v) =>
                    object(v)['id'] == ref.serviceId &&
                    object(v)['major'] == ref.major,
              )) {
            throw StateError(
              'Update would break service dependency: $id/${ref.key}',
            );
          }
        }
      }
      pauseDependents(package.id);
      _stop(package.id);
    }
    ScriptInstance? candidate;
    try {
      await store.db.transaction(() async {
        if (oldSpace != null) {
          await store.db.customStatement(
            'INSERT INTO host_collections SELECT module_id,?,name,definition,revision FROM host_collections WHERE module_id=? AND space=?',
            [space, package.id, oldSpace],
          );
          await store.db.customStatement(
            'INSERT INTO host_records SELECT module_id,?,collection,id,value,revision,deleted FROM host_records WHERE module_id=? AND space=?',
            [space, package.id, oldSpace],
          );
          await store.db.customStatement(
            'INSERT INTO host_indexes SELECT module_id,?,collection,index_name,record_id,value FROM host_indexes WHERE module_id=? AND space=?',
            [space, package.id, oldSpace],
          );
        } else {
          await store.db.customStatement(
            'INSERT INTO host_collections SELECT module_id,?,name,definition,revision FROM host_collections WHERE module_id=? AND space=?',
            [space, package.id, 'legacy-v1'],
          );
          await store.db.customStatement(
            'INSERT INTO host_records SELECT module_id,?,collection,id,value,revision,deleted FROM host_records WHERE module_id=? AND space=?',
            [space, package.id, 'legacy-v1'],
          );
        }
        await store.define(package, space);
        for (final raw in package.definition['collections'] as List? ?? []) {
          final c = object(raw);
          await store.db.customStatement(
            'UPDATE host_collections SET definition=? WHERE module_id=? AND space=? AND name=?',
            [canonicalJson(c), package.id, space, c['id']],
          );
        }
      });
      candidate = await _activate(package, space, generation, publish: false);
      _migrationInstances.add(package.id);
      try {
        if (oldDataVersion != null && oldDataVersion < package.dataVersion) {
          final migrations = object(package.definition['migrations'] ?? {});
          final handler = migrations['$oldDataVersion'];
          if (handler is! String) {
            throw StateError('Missing data migration from $oldDataVersion');
          }
          final session = SnapshotSession(candidate.actor, const Uuid().v4());
          final result = object(
            await candidate.run(handler, {
              'from': oldDataVersion,
              'to': package.dataVersion,
            }, session),
          );
          await store.stage(session, candidate.actor, result);
          session.result = result['result'];
          final plan = store.seal(session);
          await store.commit(
            plan.id,
            candidate.actor,
            authorize: (_) {},
            audit: false,
          );
        }
        await store.validateAndReindex(package, space);
      } finally {
        _migrationInstances.remove(package.id);
      }
      await store.db.transaction(() async {
        if (previousVersions.isEmpty) {
          await store.db.customStatement(
            'INSERT INTO host_packages VALUES(?,?,?,?,?,?,?)',
            [
              package.id,
              package.version,
              package.packageDigest,
              package.origin,
              canonicalJson(package.release),
              canonicalJson(package.definition),
              DateTime.now().toUtc().toIso8601String(),
            ],
          );
        }
        if (prior != null) {
          await store.db.customStatement(
            'INSERT INTO host_snapshots VALUES(?,?,?,?,?,?)',
            [
              const Uuid().v4(),
              package.id,
              oldSpace,
              prior['version'],
              oldDataVersion,
              DateTime.now().toUtc().toIso8601String(),
            ],
          );
        }
        await store.db.customStatement(
          '''INSERT INTO host_installations VALUES(?,?,?,?,1,1,?,NULL)
          ON CONFLICT(module_id) DO UPDATE SET version=excluded.version,space=excluded.space,
          data_version=excluded.data_version,installed=1,enabled=1,generation=excluded.generation,error=NULL''',
          [package.id, package.version, space, package.dataVersion, generation],
        );
      });
      instances[package.id] = candidate;
      for (final id in paused.reversed) {
        try {
          await _enable(id);
        } catch (error) {
          await _fail(id, '$error');
        }
      }
      failures.remove(package.id);
      _notifyRegistry();
    } catch (error) {
      candidate?.closeWorkers();
      _stop(package.id);
      if (old != null && oldSpace != null) {
        await _activate(old.package, oldSpace, generation + 1);
        await store.db.customStatement(
          'UPDATE host_installations SET generation=? WHERE module_id=?',
          [generation + 1, package.id],
        );
      }
      for (final id in paused.reversed) {
        try {
          await _enable(id);
        } catch (error) {
          await _fail(id, '$error');
        }
      }
      rethrow;
    }
  }

  void _stop(String id) {
    final instance = instances.remove(id);
    store.deactivate(id);
    pageSessions.removeWhere((key, _) => key.startsWith('$id:'));
    _proposals.removeWhere(
      (_, proposal) => (proposal['caller'] as ModuleActor).moduleId == id,
    );
    instance?.closeWorkers();
    for (final sub
        in instance?.subscriptions.values ?? <StreamSubscription>[]) {
      sub.cancel();
    }
    for (final grant in grants.values) {
      if (grant.caller.moduleId == id ||
          grant.scopes.any((s) => s.startsWith('$id/'))) {
        grant.revoked = true;
      }
    }
    if (instance != null) onDeactivate?.call(instance.actor);
  }

  List<String> dependents(String id) => [
    for (final entry in instances.entries)
      if (entry.key != id &&
          (entry.value.package.dependencies.contains(id) ||
              (entry.value.package.manifest['serviceDependencies'] as List? ??
                      [])
                  .any((v) => object(v)['moduleId'] == id)))
        entry.key,
  ];
  Future<void> disable(String id, {bool cascade = false}) =>
      _serialize(() => _disable(id, cascade: cascade));
  Future<void> _disable(String id, {bool cascade = false}) async {
    if (['app.modulemanager', 'app.host', 'app.ui.default'].contains(id)) {
      throw StateError('Protected host controls cannot be disabled');
    }
    final affected = dependents(id);
    if (affected.isNotEmpty && !cascade) {
      throw StateError('Active dependents: ${affected.join(', ')}');
    }
    for (final dependent in affected) {
      await _disable(dependent, cascade: true);
    }
    _stop(id);
    await store.db.customStatement(
      'UPDATE host_installations SET enabled=0,generation=generation+1 WHERE module_id=?',
      [id],
    );
    _notifyRegistry();
  }

  Future<void> enable(String id) => _serialize(() => _enable(id));
  Future<void> _enable(String id) async {
    final row = (await store.sql(
      'SELECT * FROM host_installations WHERE module_id=? AND installed=1',
      [id],
    )).single;
    final package = await _storedPackage(id, row['version'] as String);
    _validateDependencies(package);
    await _activate(
      package,
      row['space'] as String,
      (row['generation'] as int) + 1,
    );
    await store.db.customStatement(
      'UPDATE host_installations SET enabled=1,error=NULL,generation=generation+1 WHERE module_id=?',
      [id],
    );
    _notifyRegistry();
  }

  Future<void> uninstall(
    String id, {
    bool cascade = false,
    bool deleteData = false,
  }) => _serialize(
    () => _uninstall(id, cascade: cascade, deleteData: deleteData),
  );
  Future<void> _uninstall(
    String id, {
    bool cascade = false,
    bool deleteData = false,
  }) async {
    await _disable(id, cascade: cascade);
    if (deleteData) await onDeleteData?.call(id);
    await store.db.transaction(() async {
      await store.db.customStatement(
        'UPDATE host_installations SET installed=0 WHERE module_id=?',
        [id],
      );
      if (deleteData) {
        for (final table in [
          'host_records',
          'host_collections',
          'host_indexes',
          'host_snapshots',
          'host_operations',
          'host_automation',
          'host_outbox',
        ]) {
          await store.db.customStatement(
            'DELETE FROM $table WHERE module_id=?',
            [id],
          );
        }
        await store.db.customStatement(
          'DELETE FROM host_commits WHERE caller=?',
          [id],
        );
      }
    });
    _notifyRegistry();
  }

  Future<void> rollback(String id, String version) =>
      _serialize(() => _rollback(id, version));
  Future<void> _rollback(String id, String version) async {
    final row = (await store.sql(
      'SELECT data_version FROM host_installations WHERE module_id=?',
      [id],
    )).single;
    final package = await _storedPackage(id, version);
    if (package.dataVersion != row['data_version']) {
      throw StateError(
        'Data version differs; select a reviewed data snapshot recovery',
      );
    }
    await _install(package);
  }

  Future<void> recoverSnapshot(String id, String snapshotId) => _serialize(
    () async {
      final snapshots = await store.sql(
        'SELECT * FROM host_snapshots WHERE module_id=? AND id=?',
        [id, snapshotId],
      );
      if (snapshots.isEmpty) throw StateError('Snapshot unavailable');
      final snapshot = snapshots.single;
      final current = (await store.sql(
        'SELECT * FROM host_installations WHERE module_id=?',
        [id],
      )).single;
      final package = await _storedPackage(id, snapshot['version'] as String);
      _validateDependencies(package);
      validateCandidate?.call(package);
      final space = const Uuid().v4(),
          generation = (current['generation'] as int) + 1;
      _stop(id);
      ScriptInstance? candidate;
      try {
        await store.db.transaction(() async {
          await store.db.customStatement(
            'INSERT INTO host_collections SELECT module_id,?,name,definition,revision FROM host_collections WHERE module_id=? AND space=?',
            [space, id, snapshot['space']],
          );
          await store.db.customStatement(
            'INSERT INTO host_records SELECT module_id,?,collection,id,value,revision,deleted FROM host_records WHERE module_id=? AND space=?',
            [space, id, snapshot['space']],
          );
          await store.db.customStatement(
            'INSERT INTO host_indexes SELECT module_id,?,collection,index_name,record_id,value FROM host_indexes WHERE module_id=? AND space=?',
            [space, id, snapshot['space']],
          );
          await store.db.customStatement(
            'INSERT INTO host_snapshots VALUES(?,?,?,?,?,?)',
            [
              const Uuid().v4(),
              id,
              current['space'],
              current['version'],
              current['data_version'],
              DateTime.now().toUtc().toIso8601String(),
            ],
          );
        });
        candidate = await _activate(package, space, generation, publish: false);
        await store.db.customStatement(
          'UPDATE host_installations SET version=?,space=?,data_version=?,installed=1,enabled=1,generation=?,error=NULL WHERE module_id=?',
          [package.version, space, package.dataVersion, generation, id],
        );
        instances[id] = candidate;
        _notifyRegistry();
      } catch (error) {
        candidate?.closeWorkers();
        store.deactivate(id);
        if (current['enabled'] == 1) {
          await _activate(
            await _storedPackage(id, current['version'] as String),
            current['space'] as String,
            generation + 1,
          );
        }
        rethrow;
      }
    },
  );

  Map<String, Object?> _service(ServiceRef ref) {
    if (ref.moduleId == 'app.host' && ref.major == 1) {
      final native = nativeServices[ref.serviceId];
      if (native != null) return native.definition;
    }
    final provider = instances[ref.moduleId];
    if (provider == null) throw StateError('Service provider unavailable');
    for (final raw in provider.package.definition['services'] as List? ?? []) {
      final service = object(raw);
      if (service['id'] == ref.serviceId && service['major'] == ref.major) {
        return service;
      }
    }
    throw StateError('Service version unavailable: ${ref.key}');
  }

  void _authorize(
    ModuleActor caller,
    ServiceRef ref,
    String kind, {
    SnapshotSession? session,
    Object? input,
  }) {
    store.requireActive(caller);
    if (caller.moduleId == ref.moduleId) return;
    final permission = 'services.$kind:${ref.key}';
    if (caller.permissions.contains(permission)) return;
    if (kind == 'command' && input is Map && input['entity'] is Map) {
      final entity = object(input['entity']);
      for (final raw
          in instances[ref.moduleId]?.package.definition['services'] as List? ??
              []) {
        final extension = object(raw)['extensionFor'];
        if (extension is Map &&
            extension['moduleId'] == entity['moduleId'] &&
            extension['collection'] == entity['collection'] &&
            object(extension['commands'] ?? {}).values
                .contains(ref.serviceId) &&
            caller.permissions.contains(
              'extensions.command:${entity['moduleId']}/${entity['collection']}',
            )) {
          return;
        }
      }
    }
    final matching = grants.values.where(
      (g) =>
          identical(g.caller, caller) && g.valid && g.scopes.contains(ref.key),
    );
    if (!caller.permissions.contains('grants.request') || matching.isEmpty) {
      throw StateError('Service permission denied: ${ref.key}');
    }
    if (session != null) {
      session.approvals.add({
        'grantId': matching.first.id,
        'scope': ref.key,
        'callerModuleId': caller.moduleId,
        'generation': caller.generation,
      });
    }
  }

  Future<Object?> query(
    ModuleActor caller,
    ServiceRef ref,
    Object? input, {
    SnapshotSession? session,
  }) async {
    final service = _service(ref);
    if (service['kind'] != 'query') throw StateError('Service is not a query');
    _authorize(caller, ref, 'query', session: session);
    validateSchema(input, object(service['input']));
    final snapshot = session ?? SnapshotSession(caller, const Uuid().v4());
    snapshot.participants[caller.moduleId] = caller;
    if (ref.moduleId == 'app.host') {
      snapshot.participants['app.host'] = nativeActor;
      final value = await nativeServices[ref.serviceId]!.call(
        caller,
        input,
        snapshot,
      );
      _authorize(caller, ref, 'query', session: session);
      validateSchema(value, object(service['output']));
      return value;
    }
    final result = await _invokeService(
      snapshot,
      instances[ref.moduleId]!,
      service['handler'] as String,
      input is Map
          ? {
              ...object(input),
              '_host': {'callerModuleId': caller.moduleId},
            }
          : input,
      ref,
    );
    store.requireActive(caller);
    _authorize(caller, ref, 'query', session: session);
    validateSchema(result, object(service['output']));
    return result;
  }

  Future<ChangePlan> prepare(
    ModuleActor caller,
    ServiceRef ref,
    Object? input, {
    String? requestId,
  }) async {
    final session = SnapshotSession(caller, requestId ?? const Uuid().v4());
    session.result = await _prepareInto(
      session,
      caller,
      ref,
      input,
    ).timeout(const Duration(seconds: 10));
    return store.seal(session);
  }

  Future<Object?> _prepareInto(
    SnapshotSession session,
    ModuleActor caller,
    ServiceRef ref,
    Object? input,
  ) async {
    final service = _service(ref);
    if (service['kind'] != 'command') {
      throw StateError('Service is not a command');
    }
    _authorize(caller, ref, 'command', session: session, input: input);
    validateSchema(input, object(service['input']));
    session.participants[caller.moduleId] = caller;
    if (ref.moduleId == 'app.host') {
      session.participants['app.host'] = nativeActor;
      final value = await nativeServices[ref.serviceId]!.call(
        caller,
        input,
        session,
      );
      validateSchema(value, object(service['output']));
      return value;
    }
    final provider = instances[ref.moduleId]!;
    final actualInput = input is Map
        ? {
            ...object(input),
            '_host': {'callerModuleId': caller.moduleId},
          }
        : input;
    final result = object(
      await _invokeService(
        session,
        provider,
        service['handler'] as String,
        actualInput,
        ref,
      ),
    );
    if (service['confirmation'] == 'provider') {
      session.approvals.add({'provider': ref.moduleId});
    }
    validateSchema(result['result'], object(service['output']));
    await store.stage(session, provider.actor, result);
    return result['result'];
  }

  Future<Object?> _invokeService(
    SnapshotSession session,
    ScriptInstance provider,
    String handler,
    Object? input,
    ServiceRef ref,
  ) async {
    if (session.activeServices.contains(ref.key) ||
        session.activeServices.length >= 8) {
      throw StateError('Service recursion or depth exceeded');
    }
    session.activeServices.add(ref.key);
    try {
      return identical(provider.session, session)
          ? await provider.worker.invoke(handler, input)
          : await provider.run(handler, input, session);
    } finally {
      session.activeServices.remove(ref.key);
    }
  }

  void review(String planId, ModuleActor caller) {
    store.plan(planId, caller);
    _reviewed.add(planId);
  }

  Future<Object?> commit(ModuleActor caller, String planId) async {
    final plan = store.plan(planId, caller);
    final used = <String>{};
    final result = await store.commit(
      planId,
      caller,
      authorize: (p) {
        validateNativePlan?.call(p);
        if (!_reviewed.contains(planId)) {
          throw StateError('Host review required for actual changes');
        }
        for (final raw in p.content['approvals'] as List) {
          final approval = object(raw);
          if (approval['provider'] != null) {
            if (approval['provider'] != caller.moduleId) {
              throw StateError('Provider confirmation is required');
            }
            continue;
          }
          if (approval['hostRegistry'] != null) continue;
          final g = grants[approval['grantId']];
          if (g == null ||
              !g.valid ||
              !identical(g.caller, store.actors[approval['callerModuleId']]) ||
              g.caller.generation != approval['generation'] ||
              !g.scopes.contains(approval['scope'])) {
            throw StateError('Authorization expired or revoked');
          }
          used.add(g.id);
        }
      },
    );
    if (!_grantsUsed.containsKey(plan.id)) {
      for (final id in used) {
        grants[id]!.remainingWrites--;
      }
      _grantsUsed[plan.id] = used;
    }
    return result;
  }

  List<Object?> directoryServices() => [
    for (final native in nativeServices.values)
      {...native.definition, 'moduleId': 'app.host', 'moduleName': '宿主'},
    for (final instance in instances.values)
      for (final raw in instance.package.definition['services'] as List? ?? [])
        {
          ...object(raw),
          'moduleId': instance.actor.moduleId,
          'moduleName': instance.package.title,
        },
  ];
  Future<Object?> invokePage(
    String moduleId,
    String handler,
    Object? input, {
    void Function(Set<String>)? onReads,
  }) {
    final instance = instances[moduleId];
    if (instance == null) throw StateError('Module unavailable');
    final result = Completer<Object?>();
    instance.workflowTail = instance.workflowTail.then((_) async {
      final reads = onReads == null ? null : <String>{};
      instance.pageReads = reads;
      try {
        final value = await instance.workflow.invoke(
          handler,
          input,
          timeout: null,
        );
        if (reads != null) onReads!(Set.unmodifiable(reads));
        result.complete(value);
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        instance.pageReads = null;
      }
    });
    return result.future;
  }

  Future<Object?> invokeInterrupt(String moduleId, String handler) async {
    final instance = instances[moduleId];
    if (instance == null ||
        !(instance.package.definition['interruptHandlers'] as List? ?? [])
            .contains(handler)) {
      throw StateError('Unknown interrupt handler');
    }
    _workflowEpoch[moduleId] = (_workflowEpoch[moduleId] ?? 0) + 1;
    _proposals.removeWhere((_, p) => identical(p['caller'], instance.actor));
    _reviewed.removeWhere((id) {
      try {
        return identical(store.plan(id, instance.actor).caller, instance.actor);
      } catch (_) {
        return false;
      }
    });
    return instance.workflow.invoke(handler, {});
  }

  Future<Object?> _bridge(
    ScriptInstance instance,
    String method,
    Map<String, Object?> args, {
    bool workflow = false,
  }) async {
    final actor = instance.actor;
    store.requireActive(actor);
    if (_batchInstalling &&
        ![
          'data.get',
          'data.query',
          'ids.new',
          'clock.now',
          'clock.today',
          'ui.catalog',
          'services.directory',
        ].contains(method)) {
      throw StateError(
        'Installation validation cannot use external capabilities: $method',
      );
    }
    final session = workflow ? null : instance.session;
    final pageReads = workflow ? instance.pageReads : null;
    if (_migrationInstances.contains(actor.moduleId) &&
        !['data.get', 'data.query', 'ids.new', 'clock.now'].contains(method)) {
      throw StateError('Migration cannot use external capabilities');
    }
    switch (method) {
      case 'ui.catalog':
        return [
          for (final contract in uiContracts.values) contract.toJson(),
          for (final id in instance.package.dependencies)
            for (final contract
                in instances[id]?.package.uiPack?.contracts.values ??
                    <UiContract>[])
              if (!uiContracts.containsKey(contract.ref)) contract.toJson(),
        ];
      case 'data.get':
        pageReads?.add(actor.moduleId);
        return store.get(
          actor,
          string(args['collection'], 'collection'),
          string(args['id'], 'id'),
          session: session,
        );
      case 'data.query':
        pageReads?.add(actor.moduleId);
        return store.query(
          actor,
          string(args['collection'], 'collection'),
          args,
          session: session,
        );
      case 'services.directory':
        return directoryServices();
      case 'extensions.query':
      case 'extensions.queryMany':
        final entities = method == 'extensions.query'
            ? [object(args['entity'])]
            : (args['entities'] as List).map(object).toList();
        if (entities.isEmpty) return {'definitions': [], 'valuesById': {}};
        if (entities.any(
              (e) =>
                  e['moduleId'] != actor.moduleId ||
                  e['collection'] != entities.first['collection'],
            ) ||
            !actor.permissions.contains('extensions.query')) {
          throw StateError('Extension read scope denied');
        }
        final valuesById = <String, Map<String, Object?>>{
              for (final e in entities) e['id'] as String: {},
            },
            definitions = <Object?>[];
        final snapshot = session ?? SnapshotSession(actor, const Uuid().v4());
        for (final provider in instances.values) {
          for (final raw
              in provider.package.definition['services'] as List? ?? []) {
            final service = object(raw), scope = service['extensionFor'];
            if (service['kind'] != 'query' ||
                scope is! Map ||
                scope['moduleId'] != actor.moduleId ||
                scope['collection'] != entities.first['collection']) {
              continue;
            }
            pageReads?.add(provider.actor.moduleId);
            final inputs = service['supportsBatch'] == true
                ? [
                    {'entities': entities},
                  ]
                : [
                    for (final e in entities) {'entity': e},
                  ];
            for (final input in inputs) {
              final result = object(
                await _invokeService(
                  snapshot,
                  provider,
                  service['handler'] as String,
                  {
                    ...input,
                    '_host': {
                      'callerModuleId': actor.moduleId,
                      'extensionQuery': true,
                    },
                  },
                  ServiceRef(
                    provider.actor.moduleId,
                    service['id'] as String,
                    service['major'] as int,
                  ),
                ),
              );
              definitions.addAll([
                for (final raw in result['definitions'] as List? ?? [])
                  {
                    ...object(raw),
                    'moduleId': provider.actor.moduleId,
                    'commands': scope['commands'] ?? {},
                  },
              ]);
              if (service['supportsBatch'] == true) {
                for (final e in object(result['valuesById'] ?? {}).entries) {
                  valuesById[e.key]?.addAll(object(e.value));
                }
              } else {
                valuesById[object(input['entity'])['id']]?.addAll(
                  object(result['values'] ?? {}),
                );
              }
            }
          }
        }
        pageReads?.addAll(snapshot.participants.keys);
        return method == 'extensions.query'
            ? {
                'values': valuesById[entities.single['id']],
                'definitions': definitions,
              }
            : {'valuesById': valuesById, 'definitions': definitions};
      case 'services.query':
        final ref = ServiceRef.parse(args['ref']);
        final querySnapshot =
            session ??
            (pageReads == null
                ? null
                : SnapshotSession(actor, const Uuid().v4()));
        final value = await query(
          actor,
          ref,
          args['input'],
          session: querySnapshot,
        );
        pageReads?.add(ref.moduleId);
        if (querySnapshot != null) {
          pageReads?.addAll(querySnapshot.participants.keys);
        }
        return value;
      case 'services.prepare':
        if (session != null) {
          return _prepareInto(
            session,
            actor,
            ServiceRef.parse(args['ref']),
            args['input'],
          );
        }
        final plan = await prepare(
          actor,
          ServiceRef.parse(args['ref']),
          args['input'],
        );
        return {
          'planId': plan.id,
          'result': plan.result,
          'writes': plan.writes,
        };
      case 'ids.new':
        return const Uuid().v4();
      case 'clock.now':
        return clockNow().toUtc().toIso8601String();
      case 'clock.today':
      case 'clock.local':
        final local = args['zone'] == null
            ? clockNow().toLocal()
            : tz.TZDateTime.from(
                clockNow(),
                tz.getLocation(string(args['zone'], 'zone')),
              );
        final date =
            '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
        if (method == 'clock.local') {
          return {
            'date': date,
            'time':
                '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
            'weekday': local.weekday,
          };
        }
        return date;
    }
    if (session != null) {
      throw StateError('Preparation forbids side effects: $method');
    }
    if (preview) {
      throw StateError('Preview forbids external capabilities: $method');
    }
    switch (method) {
      case 'services.adopt':
        final plan = store.adoptProviderPlan(
          string(args['planId'], 'planId'),
          actor,
        );
        return {
          'planId': plan.id,
          'result': plan.result,
          'writes': plan.writes,
        };
      case 'subscriptions.close':
        await instance.subscriptions.remove(args['id'])?.cancel();
        return null;
      case 'data.watch':
      case 'services.watch':
        final id = const Uuid().v4();
        int revision = 0;
        Future<void> refresh() async {
          final current = ++revision;
          try {
            final value = method == 'data.watch'
                ? await store.query(
                    actor,
                    string(args['collection'], 'collection'),
                    args,
                  )
                : await query(
                    actor,
                    ServiceRef.parse(args['ref']),
                    args['input'],
                  );
            if (store.active(actor) && current == revision) {
              instance.workflow.emit(id, value);
            }
          } catch (error) {
            if (store.active(actor)) {
              instance.workflow.emit(id, {'error': '$error'});
            }
          }
        }
        instance.subscriptions[id] = store.changes.stream.listen(
          (_) => refresh(),
        );
        Future<void>.delayed(const Duration(milliseconds: 5), refresh);
        return id;
      case 'events.subscribe':
        final source = string(args['moduleId'], 'event source'),
            types = (args['types'] as List).cast<String>();
        if (types.any(
          (type) =>
              !actor.permissions.contains('events.subscribe:$source/$type'),
        )) {
          throw StateError('Event subscription permission denied');
        }
        final id = const Uuid().v4();
        instance.subscriptions[id] = store.events.stream.listen((message) {
          if (message['moduleId'] == source &&
              types.contains(object(message['event'])['type'])) {
            instance.workflow.emit(id, message);
          }
        });
        return id;
      case 'services.commit':
        return commit(actor, string(args['planId'], 'planId'));
      case 'ui.review':
        final plan = store.plan(string(args['planId'], 'planId'), actor);
        final accepted = await interaction?.call(actor, 'ui.review', {
          'planId': plan.id,
          'writes': plan.writes,
          'result': plan.result,
        });
        store.requireActive(actor);
        if (accepted != true) return false;
        review(plan.id, actor);
        return true;
      case 'grants.request':
        if (!actor.permissions.contains('grants.request')) {
          throw StateError('Grant permission denied');
        }
        final scopes = (args['scopes'] as List).cast<String>().toSet();
        if (scopes.isEmpty ||
            scopes.any(
              (s) => !directoryServices().any((v) {
                final x = object(v);
                return '${x['moduleId']}/${x['id']}@${x['major']}' == s;
              }),
            )) {
          throw StateError('Unknown service scope');
        }
        final accepted = await interaction?.call(actor, method, {
          'scopes': scopes.toList(),
          'minutes': 30,
          'writeLimit': 20,
        });
        store.requireActive(actor);
        if (accepted != true) return null;
        final grant = HostGrant(
          const Uuid().v4(),
          actor,
          scopes,
          DateTime.now().add(const Duration(minutes: 30)),
        );
        grants[grant.id] = grant;
        return {
          'id': grant.id,
          'expiresAt': grant.expiresAt.toIso8601String(),
          'writeLimit': 20,
        };
      case 'grants.revoke':
        final g = grants[args['id']];
        if (g != null && identical(g.caller, actor)) g.revoked = true;
        return null;
      case 'packages.prepare':
        return _preparePackage(actor, args);
      case 'packages.review':
        return _reviewPackage(actor, string(args['id'], 'proposal'));
      case 'http.request':
        if (!actor.permissions.contains('http')) {
          throw StateError('HTTP permission denied');
        }
        final uri = Uri.parse(string(args['url'], 'URL'));
        if (args['credential'] == null &&
            !(instance.package.manifest['httpOrigins'] as List? ?? []).contains(
              uri.origin,
            )) {
          throw StateError('Network origin is undeclared');
        }
        final value = await interaction?.call(actor, method, args);
        store.requireActive(actor);
        return value;
      default:
        final permission = method.split('.').first;
        if (!actor.permissions.contains(permission) &&
            !actor.permissions.contains(method)) {
          throw StateError('Capability denied: $method');
        }
        final value = await interaction?.call(actor, method, args);
        store.requireActive(actor);
        return value;
    }
  }

  Future<Object?> _preparePackage(
    ModuleActor actor,
    Map<String, Object?> args,
  ) async {
    if (!actor.permissions.contains('packages.prepare')) {
      throw StateError('Module development permission denied');
    }
    final definition = object(args['definition']);
    final sources = object(args['files']).cast<String, String>();
    final bytes = await ScriptPackage.build(definition, sources);
    final package = await ScriptPackage.verify(bytes, allowUnsignedLocal: true);
    final existing = await store.sql(
      'SELECT * FROM host_installations WHERE module_id=?',
      [package.id],
    );
    final epoch = _workflowEpoch[actor.moduleId] ?? 0;
    final sandbox = await Directory.systemTemp.createTemp('xudian-preview-');
    final previewDb = _PreviewDatabase(),
        previewStore = CollectionStore(previewDb);
    final isolated = ModuleHost(store: previewStore, directory: sandbox)
      ..preview = true;
    final previews = <Object?>[];
    Map<String, Object?>? previousDefinition;
    Map<String, String>? previousFiles;
    try {
      await isolated.initialize();
      if (existing.isNotEmpty) {
        final current = existing.single;
        final previous = await _storedPackage(
          package.id,
          current['version'] as String,
        );
        previousDefinition = previous.definition;
        previousFiles = previous.scripts;
        for (final row in await store.sql(
          'SELECT * FROM host_records WHERE module_id=? AND space=?',
          [package.id, current['space']],
        )) {
          await previewDb.customStatement(
            'INSERT OR REPLACE INTO host_collections(module_id,space,name,definition) VALUES(?,?,?,?)',
            [
              package.id,
              'legacy-v1',
              row['collection'],
              canonicalJson({
                'id': row['collection'],
                'schema': {'type': 'object'},
              }),
            ],
          );
          await previewDb.customStatement(
            'INSERT OR REPLACE INTO host_records VALUES(?,?,?,?,?,?,?)',
            [
              package.id,
              'legacy-v1',
              row['collection'],
              row['id'],
              row['value'],
              row['revision'],
              row['deleted'],
            ],
          );
        }
      }
      // Preview executes against a copied data space and rejects every external
      // operation, including network, user dialogs and formal database writes.
      final loaded = <String>{}, loading = <String>{};
      Future<void> dependency(String id) async {
        if (loaded.contains(id)) return;
        final instance = instances[id];
        if (instance == null || !loading.add(id)) {
          throw StateError('Preview dependency unavailable or cyclic: $id');
        }
        for (final child in instance.package.dependencies) {
          await dependency(child);
        }
        for (final row in await store.sql(
          'SELECT * FROM host_collections WHERE module_id=? AND space=?',
          [id, instance.actor.space],
        )) {
          await previewDb.customStatement(
            'INSERT OR REPLACE INTO host_collections VALUES(?,?,?,?,?)',
            [id, 'legacy-v1', row['name'], row['definition'], row['revision']],
          );
        }
        for (final row in await store.sql(
          'SELECT * FROM host_records WHERE module_id=? AND space=?',
          [id, instance.actor.space],
        )) {
          await previewDb.customStatement(
            'INSERT OR REPLACE INTO host_records VALUES(?,?,?,?,?,?,?)',
            [
              id,
              'legacy-v1',
              row['collection'],
              row['id'],
              row['value'],
              row['revision'],
              row['deleted'],
            ],
          );
        }
        await isolated.install(instance.package);
        loading.remove(id);
        loaded.add(id);
      }

      for (final id in package.dependencies) {
        await dependency(id);
      }
      if (existing.isNotEmpty) {
        await isolated.install(
          await _storedPackage(
            package.id,
            existing.single['version'] as String,
          ),
        );
      }
      await isolated.install(package);
      if (package.isUiPack) {
        previews.add({
          'kind': 'uiPack',
          'moduleId': package.id,
          'uiPack': package.definition['uiPack'],
        });
      }
      for (final page in package.definition['pages'] as List? ?? []) {
        if (object(page)['kind'] == 'container') continue;
        final value = await isolated.instances[package.id]!.workflow.invoke(
          object(page)['handler'] as String,
          {
            'state': {},
            'context': object(page)['previewContext'] ?? {},
            'formValues': {},
          },
        );
        previews.add({'pageId': object(page)['id'], 'view': value});
      }
    } finally {
      await isolated.close();
      await previewStore.close();
      await previewDb.close();
      await sandbox.delete(recursive: true);
    }
    if (epoch != (_workflowEpoch[actor.moduleId] ?? 0)) {
      throw StateError('Module preview cancelled');
    }
    final id = const Uuid().v4();
    _proposals[id] = {
      'caller': actor,
      'bytes': bytes,
      'digest': package.packageDigest,
      'baseline': canonicalJson(existing),
      'definition': definition,
      'files': sources,
      'moduleId': package.id,
      'previews': previews,
      'previousDefinition': previousDefinition,
      'previousFiles': previousFiles,
    };
    return {'id': id, 'digest': package.packageDigest};
  }

  Future<ScriptPackage> packageSource(String id, String version) =>
      _storedPackage(id, version);

  /// Protected host editor uses the same isolated preview and digest-bound
  /// review as script-generated proposals, even when no AI module is installed.
  Future<bool> editLocalPackage(Map<String, Object?> input) async {
    final proposal = object(await _preparePackage(nativeActor, input));
    return await _reviewPackage(nativeActor, proposal['id'] as String) == true;
  }

  Future<Object?> _reviewPackage(ModuleActor actor, String id) async {
    final proposal = _proposals[id];
    if (proposal == null || !identical(proposal['caller'], actor)) {
      throw StateError('Unknown proposal');
    }
    final baseline = await store.sql(
      'SELECT * FROM host_installations WHERE module_id=?',
      [proposal['moduleId']],
    );
    if (canonicalJson(baseline) != proposal['baseline']) {
      throw StateError('Module changed; regenerate proposal');
    }
    final package = await ScriptPackage.verify(
      proposal['bytes'] as List<int>,
      allowUnsignedLocal: true,
    );
    if (package.packageDigest != proposal['digest']) {
      throw StateError('Candidate changed');
    }
    final accepted = await interaction?.call(actor, 'packages.review', {
      'digest': package.packageDigest,
      'definition': proposal['definition'],
      'files': proposal['files'],
      'baseline': baseline,
      'previousDefinition': proposal['previousDefinition'],
      'previousFiles': proposal['previousFiles'],
      'preview': proposal['previews'],
    });
    store.requireActive(actor);
    if (accepted != true) return false;
    if (!identical(_proposals[id], proposal)) {
      throw StateError('Proposal was cancelled');
    }
    if (canonicalJson(
          await store.sql(
            'SELECT * FROM host_installations WHERE module_id=?',
            [package.id],
          ),
        ) !=
        proposal['baseline']) {
      throw StateError('Review baseline changed');
    }
    await _serialize(() async {
      store.requireActive(actor);
      if (!identical(_proposals[id], proposal) ||
          canonicalJson(
                await store.sql(
                  'SELECT * FROM host_installations WHERE module_id=?',
                  [package.id],
                ),
              ) !=
              proposal['baseline']) {
        throw StateError('Review baseline changed before installation');
      }
      await _install(package);
    });
    _proposals.remove(id);
    return true;
  }

  Future<void> _automate(Map<String, Object?> message) async {
    final event = object(message['event']);
    for (final instance in instances.values.toList()) {
      if (!instance.actor.permissions.contains('automation.execute')) continue;
      for (final raw in instance.package.definition['rules'] as List? ?? []) {
        final rule = object(raw);
        final publishers =
            (rule['publishers'] as List? ??
            [rule['publisher'] ?? instance.actor.moduleId]);
        if (rule['event'] == event['type'] &&
            publishers.contains(message['moduleId'])) {
          await _runRule(instance, rule, event);
        }
      }
    }
  }

  Future<void> _runRule(
    ScriptInstance instance,
    Map<String, Object?> rule,
    Map<String, Object?> event, {
    String? retryOf,
  }) async {
    final id = const Uuid().v4(),
        key = '${instance.actor.moduleId}:${rule['id']}';
    final depth = event['automationDepth'] as int? ?? 0;
    final trace = (event['automationTrace'] as List? ?? []).cast<String>();
    var status = 'success';
    String? error;
    try {
      if (depth >= 8 || trace.contains(key)) {
        status = 'skipped';
        error = 'Automation depth or loop protection';
      } else {
        final session = SnapshotSession(instance.actor, id)
          ..automationDepth = depth + 1
          ..automationTrace = [...trace, key];
        session.result = await _prepareInto(
          session,
          instance.actor,
          ServiceRef(instance.actor.moduleId, rule['serviceId'] as String, 1),
          {'ruleId': rule['id'], 'event': event},
        ).timeout(const Duration(seconds: 10));
        final plan = store.seal(session);
        review(plan.id, instance.actor);
        await commit(instance.actor, plan.id);
        if (object(session.result)['skipped'] == true) status = 'skipped';
      }
    } catch (e) {
      status = 'failure';
      error = '$e';
    }
    await store.db.customStatement(
      'INSERT INTO host_automation VALUES(?,?,?,?,?,?,?,?,?)',
      [
        id,
        instance.actor.moduleId,
        rule['id'],
        canonicalJson(event),
        status,
        error,
        retryOf,
        depth,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<void> retryAutomation(String id) async {
    final execution = (await store.sql(
      'SELECT * FROM host_automation WHERE id=?',
      [id],
    )).single;
    if (execution['status'] != 'failure') {
      throw StateError('Only failed executions may retry');
    }
    final instance = instances[execution['module_id']];
    if (instance == null) throw StateError('Rule module unavailable');
    final rule = (instance.package.definition['rules'] as List)
        .map(object)
        .firstWhere((r) => r['id'] == execution['rule_id']);
    await _runRule(instance, rule, {
      ...object(jsonDecode(execution['event'] as String)),
      'automationDepth': 0,
      'automationTrace': [],
    }, retryOf: id);
  }

  Future<List<Map<String, Object?>>> automationHistory(String moduleId) async {
    final records = await store.sql(
      'SELECT * FROM host_automation WHERE module_id=? ORDER BY created_at DESC LIMIT 100',
      [moduleId],
    );
    final installation = await store.sql(
      'SELECT * FROM host_installations WHERE module_id=?',
      [moduleId],
    );
    if (installation.isEmpty) return records;
    final package = await _storedPackage(
      moduleId,
      installation.single['version'] as String,
    );
    final collection = package.definition['legacyExecutionCollection'];
    if (collection is! String) return records;
    for (final row in await store.sql(
      'SELECT value FROM host_records WHERE module_id=? AND space=? AND collection=? AND deleted=0 LIMIT 100',
      [moduleId, installation.single['space'], collection],
    )) {
      final value = object(jsonDecode(row['value'] as String));
      records.add({
        'id': 'legacy:${value['id']}',
        'module_id': moduleId,
        'rule_id': value['ruleId'],
        'status': value['status'],
        'created_at': value['createdAt'],
        'message': value['message'],
        'retry_of': value['sourceExecutionId'] == null
            ? null
            : 'legacy:${value['sourceExecutionId']}',
        'legacy': value,
      });
    }
    return records;
  }

  Future<void> retryHistoricalAutomation(String moduleId, String id) async {
    if (!id.startsWith('legacy:')) return retryAutomation(id);
    final record = (await automationHistory(moduleId))
        .firstWhere((row) => row['id'] == id);
    if (record['status'] != 'failure') {
      throw StateError('Only failed executions may retry');
    }
    final instance = instances[moduleId];
    if (instance == null) throw StateError('Rule module unavailable');
    final value = object(record['legacy']);
    final rule = (instance.package.definition['rules'] as List)
        .map(object)
        .firstWhere((rule) => rule['id'] == value['ruleId']);
    await _runRule(instance, rule, {
      'type': value['eventType'],
      'entity': {
        'moduleId': instance.package.definition['legacyEventProvider'],
        'collection': '${value['entityType']}s',
        'id': value['entityId'],
      },
      'payload': jsonDecode(value['eventPayloadJson'] as String),
      'automationDepth': 0,
      'automationTrace': [],
    }, retryOf: id);
  }

  Future<void> close() async {
    await _automationSubscription?.cancel();
    for (final id in instances.keys.toList()) {
      _stop(id);
    }
    store.deactivate('app.host');
    await registryChanges.close();
  }
}

class _PreviewDatabase extends AppDatabase {
  _PreviewDatabase() : super(NativeDatabase.memory());
}
