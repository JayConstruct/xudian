import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:pub_semver/pub_semver.dart';

import 'module_ui_declarations.dart';
import 'ui_preferences.dart';
import 'host_schema.dart';

import 'package:drift/native.dart';

import '../../data/app_database.dart';

import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as zones;
import 'package:xquickjs/xquickjs.dart';

import '../contracts/json_values.dart';
import '../performance/ui_load_trace.dart';
import '../ui/ui_pack.dart';
import 'collection_store.dart';
import 'clock_conversion.dart';
import 'json_schema.dart';
import 'legacy_data_migration.dart';
import 'module_package.dart';
import 'service_directory_resource.dart';
import 'system_timezone.dart';
import 'page_workflow_queue.dart';
import 'script_worker_pair.dart';
import 'plan_confirmation.dart';
import 'native_command_approval.dart';
import 'service_ref.dart';
import 'page_invocation.dart';
export 'service_ref.dart';
export 'page_invocation.dart' show PagePlanReview, InlinePagePlanReview;

part 'module_host_installation.dart';
part 'module_host_services.dart';

class ScriptInstance {
  ScriptInstance(this.package, this.actor);
  final ScriptPackage package;
  final ModuleActor actor;
  late final ScriptWorkerPair engines;
  JavaScriptWorker get worker => package.isUiPack
      ? (throw StateError('UI packs do not have JavaScript workers'))
      : engines.current();
  JavaScriptWorker get workflow => package.isUiPack
      ? (throw StateError('UI packs do not have JavaScript workers'))
      : engines.current(workflow: true);
  bool get hasWorkers => !package.isUiPack && engines.hasBoth;
  void closeWorkers() {
    pageWorkflow.close();
    if (!package.isUiPack) engines.close();
  }

  final pageWorkflow = PageWorkflowQueue();
  Future<void> get workflowTail => pageWorkflow.idle;
  set workflowTail(Future<void> value) => pageWorkflow.waitFor(value);
  SnapshotSession? session;
  PageInvocation? page;
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
      try {
        // Reload only before a new operation. A failed command is never replayed.
        final current = await engines.ready();
        session = snapshot;
        completer.complete(
          await current.invoke(
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
  ModuleHost({
    required this.store,
    required this.directory,
    this.interaction,
    this.systemTimezoneResolver,
  });
  SystemTimezoneResolver? systemTimezoneResolver;
  final CollectionStore store;
  final Directory directory;
  // Native polling outlives installation transactions. Keep its timers in the
  // host's owner zone while initialization bridges use the live batch zone.
  final Zone _workerZone = Zone.current;
  Zone? _installBatchZone;
  HostInteraction? interaction;
  void Function(ScriptPackage candidate)? validateCandidate;
  bool preview = false;
  bool _batchInstalling = false;
  final _installBatchPlans = <String, HostInstallBatchPlan>{};
  void discardInstallBatch(HostInstallBatchPlan plan) =>
      _installBatchPlans.remove(plan.id);
  void _notifyRegistry() {
    if (!_batchInstalling) {
      registryChanges.add(null);
      unawaited(checkClockAutomation(force: true));
    }
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
  final _preparedInvocations = Expando<({ServiceRef reference, Object? input})>(
    'prepared service',
  );
  final _grantsUsed = <String, Set<String>>{};
  final _proposals = <String, Map<String, Object?>>{};
  final _migrationInstances = <String>{};
  Future<void> _lifecycle = Future.value();
  StreamSubscription? _automationSubscription;
  Future<void> _automationTail = Future.value();
  Timer? _clockAutomationTimer;
  bool _clockAutomationReady = false;
  bool _clockAutomationActive = true;
  bool _closed = false;
  int? _clockAutomationMinute;
  Future<void> drainAutomation() => _automationTail;

  /// Native clock notifications use the same reviewed automation grants as
  /// module events. Services decide civil dates in their own configured zones.
  /// Neither page queries nor script-published events can invoke this path.
  Future<void> checkClockAutomation({bool force = false}) {
    if (_closed ||
        preview ||
        !_clockAutomationReady ||
        !_clockAutomationActive) {
      return Future.value();
    }
    // Ordinary module lifecycle changes must not create a clock work queue.
    // Registering an otherwise empty Future chain in a UI caller's zone can
    // leave shutdown waiting on a suspended widget/fake-async event loop.
    final hasClockRules = instances.values.any(
      (instance) =>
          store.active(instance.actor) &&
          instance.actor.permissions.contains('automation.execute') &&
          (instance.package.definition['rules'] as List? ?? []).any((raw) {
            final rule = object(raw);
            final publishers =
                rule['publishers'] as List? ??
                [rule['publisher'] ?? instance.actor.moduleId];
            return rule['event'] == 'host.clock.tick' &&
                publishers.contains('app.host');
          }),
    );
    if (!hasClockRules) return Future.value();
    final now = clockNow().toUtc();
    final minute = now.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;
    if (!force && _clockAutomationMinute == minute) return _automationTail;
    _clockAutomationMinute = minute;
    _automationTail = _workerZone.run(
      () => _automationTail
          .then((_) async {
            // Installation/enable must finish before an automatic command can read
            // its package, actor, or persistent data.
            await _lifecycle;
            if (_closed || !_clockAutomationActive) return;
            await _automate({
              'moduleId': 'app.host',
              'event': {'type': 'host.clock.tick', 'at': now.toIso8601String()},
            }, trustedClock: true);
          })
          .catchError((Object error) {
            // A failed periodic check must never block navigation or future ticks.
          }),
    );
    return _automationTail;
  }

  void setClockAutomationActive(bool active) {
    if (_closed) return;
    final resumed = active && !_clockAutomationActive;
    _clockAutomationActive = active;
    _clockAutomationTimer?.cancel();
    _clockAutomationTimer = null;
    if (!active || !_clockAutomationReady) return;
    _clockAutomationTimer = _workerZone.createPeriodicTimer(
      const Duration(minutes: 1),
      (_) => unawaited(checkClockAutomation()),
    );
    if (resumed) unawaited(checkClockAutomation(force: true));
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _lifecycle.then((_) => operation());
    _lifecycle = next.then((_) {}, onError: (Object error) {});
    return next;
  }

  Future<void> initialize() => UiLoadTrace.run('host.initialize', _initialize);

  Future<void> _initialize() async {
    zones.initializeTimeZones();
    store.registerNativeResource(ServiceDirectoryResource(_directoryBaseline));
    await directory.create(recursive: true);
    await store.db.customStatement(hostUiPreferencesSchema);
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
    final installations = await UiLoadTrace.run(
      'host.restore.packages',
      () => store.sql('''SELECT installations.*,
        packages.module_id AS package_id,
        packages.digest AS package_digest,
        packages.origin AS package_origin
        FROM host_installations AS installations
        LEFT JOIN host_packages AS packages
          ON packages.module_id=installations.module_id
          AND packages.version=installations.version
        WHERE installations.installed=1 AND installations.enabled=1'''),
    );
    final pending = {
      for (final row in installations) row['module_id'] as String: row,
    };
    // Dependency retries reuse only this restore's verified bytes. A later
    // initialization still reads and validates every committed package again.
    final verifiedPackages = <String, ScriptPackage>{};
    while (pending.isNotEmpty) {
      var progress = false;
      for (final id in pending.keys.toList()) {
        final row = pending[id]!;
        try {
          final package = verifiedPackages[id] ??= await _storedPackage(
            id,
            row['version'] as String,
            storedRows: row['package_id'] == null
                ? const []
                : [
                    {
                      'digest': row['package_digest'],
                      'origin': row['package_origin'],
                    },
                  ],
          );
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
      _automationTail = _workerZone.run(
        () => _automationTail
            .then((_) => _automate(message))
            .catchError((Object error) {}),
      );
    });
    await store.drainOutbox();
    _clockAutomationReady = true;
    setClockAutomationActive(_clockAutomationActive);
    unawaited(checkClockAutomation(force: true));
  }

  Future<void> _fail(String id, String reason) async {
    failures[id] = reason;
    await store.db.customStatement(
      'UPDATE host_installations SET enabled=0,error=? WHERE module_id=?',
      [reason, id],
    );
  }

  Future<ScriptPackage> _storedPackage(
    String id,
    String version, {
    List<Map<String, Object?>>? storedRows,
  }) => UiLoadTrace.run(
    'host.package.verify',
    () => _readStoredPackage(id, version, storedRows: storedRows),
    arguments: {'moduleId': id, 'version': version},
  );

  Future<ScriptPackage> _readStoredPackage(
    String id,
    String version, {
    List<Map<String, Object?>>? storedRows,
  }) async {
    // Restore can supply rows from its single joined query. An empty list keeps
    // the same missing-provenance failure as the ordinary database lookup.
    final row =
        (storedRows ??
                await store.sql(
                  'SELECT * FROM host_packages WHERE module_id=? AND version=?',
                  [id, version],
                ))
            .single;
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
    _validateRequiredServices(package, {
      for (final entry in instances.entries) entry.key: entry.value.package,
      package.id: package,
    });
  }

  bool _satisfiesService(
    Map<String, Object?> requirement,
    Iterable<Map<String, Object?>> services,
  ) {
    final ref = ServiceRef.parse(requirement);
    return services.any(
      (service) =>
          service['id'] == ref.serviceId &&
          (ref.moduleId == 'app.host'
              ? ref.major == 1
              : service['major'] == ref.major) &&
          (requirement['kind'] == null ||
              requirement['kind'] == service['kind']),
    );
  }

  void _validateRequiredServices(
    ScriptPackage package,
    Map<String, ScriptPackage> selected,
  ) {
    for (final requirement in package.requiredServices) {
      final ref = ServiceRef.parse(requirement);
      final services = ref.moduleId == 'app.host'
          ? nativeServices.values.map((service) => service.definition)
          : (selected[ref.moduleId]?.definition['services'] as List? ?? []).map(
              object,
            );
      if (!_satisfiesService(requirement, services)) {
        throw StateError(
          'Unsatisfied service: ${package.id} requires ${ref.key}',
        );
      }
    }
  }

  void _validateDependents(ScriptPackage package) {
    for (final id in dependents(package.id)) {
      final dependent = instances[id]!.package;
      if (!dependent.acceptsDependency(package.id, package.version)) {
        throw StateError('Update would break module dependency: $id');
      }
      for (final requirement in dependent.requiredServices) {
        final ref = ServiceRef.parse(requirement);
        if (ref.moduleId == package.id &&
            !_satisfiesService(
              requirement,
              (package.definition['services'] as List? ?? []).map(object),
            )) {
          throw StateError(
            'Update would break service dependency: $id/${ref.key}',
          );
        }
      }
    }
  }

  Future<ScriptInstance> _activate(
    ScriptPackage package,
    String space,
    int generation, {
    bool publish = true,
  }) async {
    validateModuleUiDeclarations([
      for (final instance in instances.values)
        if (instance.package.id != package.id) instance.package,
      package,
    ]);
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
    instance.engines = ScriptWorkerPair(
      moduleId: package.id,
      entryPoint: package.definition['entryPoint'] as String,
      create: (workflow) => JavaScriptWorker(
        package.scripts,
        ownerZone: _workerZone,
        memoryLimit: 32 * 1024 * 1024,
        host: (method, args) => (_installBatchZone ?? _workerZone).run(
          () =>
              _bridge(instance, method, object(args ?? {}), workflow: workflow),
        ),
      ),
      beforeWorkflowRestart: () async {
        final subscriptions = instance.subscriptions.values.toList();
        instance.subscriptions.clear();
        await Future.wait(subscriptions.map((s) => s.cancel()));
      },
    );
    try {
      await instance.engines.initialize(lazyWorkflow: package.lazyWorkflow);
    } catch (_) {
      instance.closeWorkers();
      store.deactivate(package.id);
      rethrow;
    }
    if (publish) instances[package.id] = instance;
    return instance;
  }

  Future<JavaScriptWorker> _readyScriptWorker(
    ScriptInstance instance, {
    bool workflow = false,
  }) {
    if (_closed) throw StateError('Module stopped');
    return instance.engines.ready(workflow: workflow);
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

  /// A review binds immutable package bytes and the complete installation state.
  Future<HostInstallBatchPlan> prepareInstallBatch(
    List<ScriptPackage> packages, {
    Map<String, String> repositories = const {},
  }) => _prepareInstallBatch(packages, repositories: repositories);

  Future<void> commitInstallBatch(HostInstallBatchPlan plan) =>
      _commitInstallBatch(plan);

  List<String> affectedDependents(String id) => _affectedDependents(id);

  Future<void> install(ScriptPackage package) =>
      _serialize(() => _install(package));

  List<String> dependents(String id) => _dependents(id);

  Future<void> disable(String id, {bool cascade = false}) =>
      _serialize(() => _disable(id, cascade: cascade));

  Future<void> enable(String id) => _serialize(() => _enable(id));

  Future<void> uninstall(
    String id, {
    bool cascade = false,
    bool deleteData = false,
  }) => _serialize(
    () => _uninstall(id, cascade: cascade, deleteData: deleteData),
  );

  Future<bool> wasErased(String id) => _wasErased(id);

  Future<void> rollback(String id, String version) =>
      _serialize(() => _rollback(id, version));

  Future<void> recoverSnapshot(String id, String snapshotId) =>
      _recoverSnapshot(id, snapshotId);

  Future<Object?> query(
    ModuleActor caller,
    ServiceRef ref,
    Object? input, {
    SnapshotSession? session,
  }) => _queryService(caller, ref, input, session: session);

  Future<ChangePlan> prepare(
    ModuleActor caller,
    ServiceRef ref,
    Object? input, {
    String? requestId,
  }) => _prepareService(caller, ref, input, requestId: requestId);

  void review(String planId, ModuleActor caller) => _reviewPlan(planId, caller);

  Future<Object?> commit(ModuleActor caller, String planId) =>
      _commitPlan(caller, planId);

  List<Object?> directoryServices() => _directoryServices();

  Future<Object?> invokePage(
    String moduleId,
    String handler,
    Object? input, {
    void Function(Set<String>)? onReads,
    void Function(bool)? onReplayable,
    bool readOnly = false,
    bool Function()? shouldRun,
    PagePlanReview? onReview,
    InlinePagePlanReview? onInlineReview,
    bool Function()? commandIsCurrent,
    void Function(ChangePlan plan)? onCommit,
  }) {
    if (readOnly && input is Map && input['event'] != null) {
      throw StateError('Page preparation cannot dispatch events');
    }
    final instance = instances[moduleId];
    if (instance == null) throw StateError('Module unavailable');
    final arguments = <String, Object>{
      'moduleId': moduleId,
      'handler': handler,
      'speculative': readOnly,
    };
    final queued = UiLoadTrace.start('page.queue', arguments: arguments);
    return instance.pageWorkflow
        .run(() async {
          queued?.finish();
          try {
            if (shouldRun?.call() == false ||
                !identical(instance, instances[moduleId])) {
              return null;
            }
            // Speculation must not initialize ESM with potential top-level effects.
            // The first real page request owns lazy initialization.
            if (readOnly && !instance.hasWorkers) return null;
            final worker = await _readyScriptWorker(instance, workflow: true);
            if (shouldRun?.call() == false ||
                !identical(instance, instances[moduleId])) {
              return null;
            }
            final reads = onReads == null ? null : <String>{};
            final replayability = PageReplayability(
              input is Map && input['event'] == null,
            );
            instance.page = PageInvocation(
              readOnly: readOnly,
              reads: reads,
              replayability: replayability,
              review: readOnly ? null : onReview,
              inlineReview: readOnly ? null : onInlineReview,
              commandIsCurrent: readOnly ? null : commandIsCurrent,
              onCommit: readOnly ? null : onCommit,
            );
            final value = await UiLoadTrace.run(
              'page.execute',
              () => worker.invoke(handler, input, timeout: null),
              arguments: arguments,
            );
            if (reads != null) onReads!(Set.unmodifiable(reads));
            onReplayable?.call(
              replayability.safe && replayability.pendingBridges == 0,
            );
            return value;
          } finally {
            instance.page?.close();
            instance.page = null;
          }
        }, speculative: readOnly)
        .whenComplete(() => queued?.finish());
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
    final worker = await _readyScriptWorker(instance, workflow: true);
    return worker.invoke(handler, {});
  }

  Future<Object?> _bridge(
    ScriptInstance instance,
    String method,
    Map<String, Object?> args, {
    bool workflow = false,
  }) {
    final invocation = workflow ? instance.page : null;
    final replayability = invocation?.replayability;
    if (replayability != null) replayability.pendingBridges++;
    return UiLoadTrace.run(
      'page.bridge',
      () => _dispatchBridge(
        instance,
        method,
        args,
        workflow: workflow,
        replayability: replayability,
        invocation: invocation,
      ),
      arguments: {'moduleId': instance.actor.moduleId, 'method': method},
    ).whenComplete(() {
      if (replayability != null) replayability.pendingBridges--;
    });
  }

  Future<Object?> _dispatchBridge(
    ScriptInstance instance,
    String method,
    Map<String, Object?> args, {
    bool workflow = false,
    PageReplayability? replayability,
    PageInvocation? invocation,
  }) async {
    final actor = instance.actor;
    store.requireActive(actor);
    final session = workflow ? null : instance.session;
    final pagePreparation = workflow
        ? (invocation?.readOnly ?? false)
        : session?.pagePreparation == true;
    // Speculative page preparation must never submit commands, open UI,
    // subscribe, or access the network even if the module has those grants.
    const readOnlyMethods = {
      'data.contract',
      'data.get',
      'data.query',
      'services.query',
      'services.directory',
      'extensions.query',
      'extensions.queryMany',
      'clock.now',
      'clock.today',
      'clock.local',
      'clock.systemTimezone',
      'clock.toLocal',
      'clock.toLocalMany',
      'clock.toUtc',
      'ui.preferences.get',
      'ui.catalog',
      'ui.examples',
    };
    if (!readOnlyMethods.contains(method)) {
      replayability?.markUnsafe();
      session?.onPageSideEffect?.call();
    }
    if (pagePreparation && !readOnlyMethods.contains(method)) {
      throw StateError('Page preparation forbids side effects: $method');
    }
    if (_batchInstalling &&
        ![
          'data.contract',
          'data.get',
          'data.query',
          'data.migrationHistory',
          'ids.new',
          'clock.now',
          'clock.today',
          'clock.systemTimezone',
          'clock.toLocal',
          'clock.toLocalMany',
          'clock.toUtc',
          'ui.catalog',
          'ui.examples',
          'services.directory',
        ].contains(method)) {
      throw StateError(
        'Installation validation cannot use external capabilities: $method',
      );
    }
    final pageReads = workflow ? invocation?.reads : null;
    if (_migrationInstances.contains(actor.moduleId) &&
        ![
          'data.get',
          'data.query',
          'data.migrationHistory',
          'ids.new',
          'clock.now',
          'clock.systemTimezone',
          'clock.toLocalMany',
        ].contains(method)) {
      throw StateError('Migration cannot use external capabilities');
    }
    switch (method) {
      case 'ui.examples':
        if (args.isNotEmpty) {
          throw const FormatException('ui.examples takes no arguments');
        }
        pageReads?.add(uiExamplesReadDependency);
        return [
          for (final provider in instances.values)
            if (provider.package.uiPack != null)
              for (final recipe in provider.package.uiPack!.components.entries)
                if (recipe.value.example != null)
                  {
                    'providerId': provider.actor.moduleId,
                    'ref': recipe.key,
                    ...recipe.value.example!,
                    'contract': recipe.value.contract.toJson(),
                  },
        ];
      case 'ui.catalog':
        return [
          for (final contract in uiContracts.values) contract.toJson(),
          for (final id in instance.package.dependencies)
            for (final contract
                in instances[id]?.package.uiPack?.contracts.values ??
                    <UiContract>[])
              if (!uiContracts.containsKey(contract.ref)) contract.toJson(),
        ];
      case 'data.contract':
        pageReads?.add(actor.moduleId);
        final contract =
            instance.package.recordContracts[string(args['id'], 'contract id')];
        if (contract == null) throw StateError('Unknown record contract');
        return contract.toJson();
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
      case 'data.migrationHistory':
        if (preview ||
            session == null ||
            !_migrationInstances.contains(actor.moduleId)) {
          throw StateError('History is available only during data migration');
        }
        return store.migrationHistory(
          actor,
          string(args['collection'], 'collection'),
          args['after'] as int,
        );
      case 'services.directory':
        pageReads?.addAll([
          ...instances.keys,
          for (final raw
              in instance.package.manifest['optionalServices'] as List? ?? [])
            string(object(raw)['moduleId'], 'optional service module'),
        ]);
        session?.nativeReads.putIfAbsent(
          ServiceDirectoryResource.resourceId,
          () => {'registry': _directoryBaseline()},
        );
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
        final snapshot =
            session ??
            (SnapshotSession(actor, const Uuid().v4())
              ..pagePreparation = pagePreparation
              ..onPageSideEffect = replayability?.markUnsafe);
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
            (pageReads == null && !pagePreparation && replayability == null
                ? null
                : (SnapshotSession(actor, const Uuid().v4())
                    ..pagePreparation = pagePreparation
                    ..onPageSideEffect = replayability?.markUnsafe));
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
      case 'clock.toLocal':
        return clockToLocal(args);
      case 'clock.toLocalMany':
        return clockToLocalMany(args);
      case 'clock.toUtc':
        return clockToUtc(args);
      case 'clock.systemTimezone':
        if (args.isNotEmpty) {
          throw const FormatException(
            'clock.systemTimezone takes no arguments',
          );
        }
        if (!actor.permissions.contains('clock') &&
            !actor.permissions.contains('clock.today') &&
            !actor.permissions.contains('clock.systemTimezone')) {
          throw StateError('System timezone permission denied');
        }
        if (preview) {
          throw StateError('Preview forbids external capabilities: $method');
        }
        final timezone = await readSystemTimezone(systemTimezoneResolver);
        store.requireActive(actor);
        return timezone;
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
      case 'ui.preferences.get':
      case 'ui.preferences.set':
        if (!workflow || !actor.permissions.contains('ui')) {
          throw StateError('UI preferences require a UI page workflow');
        }
        final allowed = method == 'ui.preferences.get'
            ? const {'key'}
            : const {'key', 'value'};
        if (args.keys.any((key) => !allowed.contains(key)) ||
            method == 'ui.preferences.set' && !args.containsKey('value')) {
          throw const FormatException('Invalid UI preference arguments');
        }
        final preferences = ModuleUiPreferences(store);
        final key = string(args['key'], 'UI preference key');
        if (method == 'ui.preferences.get') {
          final result = await preferences.get(actor, key);
          pageReads?.add(uiPreferencesReadDependency(actor.moduleId));
          return result;
        }
        return preferences.set(actor, key, args['value']);
      case 'ui.showCode':
        if (!workflow || !actor.permissions.contains('ui')) {
          throw StateError('Code previews require a UI page workflow');
        }
        final title = string(args['title'], 'code preview title');
        final sections = args['sections'];
        if (args.keys.any(
              (key) => !const {'title', 'sections'}.contains(key),
            ) ||
            title.trim().isEmpty ||
            title.length > 120 ||
            sections is! List ||
            sections.isEmpty ||
            sections.length > 12) {
          throw const FormatException('Invalid code preview arguments');
        }
        final normalized = <Map<String, Object?>>[];
        var total = 0;
        for (final raw in sections) {
          final section = object(raw);
          final heading = string(section['title'], 'code section title');
          final code = string(section['code'], 'code section');
          total += code.length;
          if (section.keys.any(
                (key) => !const {'title', 'code'}.contains(key),
              ) ||
              heading.trim().isEmpty ||
              heading.length > 120 ||
              code.trim().isEmpty ||
              total > 100000) {
            throw const FormatException('Invalid code preview section');
          }
          normalized.add({'title': heading, 'code': code});
        }
        final result = await interaction?.call(actor, method, {
          'title': title,
          'sections': normalized,
        });
        store.requireActive(actor);
        return result;
      case 'ui.notify':
        if (!workflow || !actor.permissions.contains('ui')) {
          throw StateError('Notifications require a UI page workflow');
        }
        final message = string(args['message'], 'notification message');
        final kind = args['kind'] ?? 'info';
        final duration = args['duration'] ?? 3000;
        if (args.keys.any(
              (key) => !const {'message', 'kind', 'duration'}.contains(key),
            ) ||
            message.trim().isEmpty ||
            message.length > 200 ||
            !const ['info', 'success', 'error'].contains(kind) ||
            duration is! num ||
            !duration.isFinite ||
            duration != duration.roundToDouble() ||
            duration < 1000 ||
            duration > 10000) {
          throw const FormatException('Invalid notification arguments');
        }
        final result = await interaction?.call(actor, method, {
          'message': message,
          'kind': kind,
          'duration': duration.toInt(),
        });
        store.requireActive(actor);
        return result;
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
        final committedPlan = store.plan(
          string(args['planId'], 'planId'),
          actor,
        );
        final commitResult = await commit(actor, committedPlan.id);
        if (workflow) invocation?.onCommit?.call(committedPlan);
        return commitResult;
      case 'ui.dialog':
        if (!actor.permissions.contains('ui') &&
            !actor.permissions.contains('ui.dialog')) {
          throw StateError('Capability denied: ui.dialog');
        }
        // Opening another form (including a cancelled one) invalidates an
        // earlier submission's capability within this workflow.
        if (workflow) invocation?.commandApproval = null;
        final declaration = freezeJson(args['command']);
        final submitted = await interaction?.call(actor, method, {
          for (final entry in args.entries)
            if (entry.key != 'command') entry.key: entry.value,
        });
        store.requireActive(actor);
        if (workflow &&
            invocation?.active == true &&
            invocation?.commandIsCurrent?.call() == true &&
            submitted is Map) {
          invocation?.commandApproval = NativeCommandApproval.fromInteraction(
            declaration,
            submittedValues: object(submitted),
          );
        }
        return submitted;
      case 'ui.review':
        final plan = store.plan(string(args['planId'], 'planId'), actor);
        final confirmation = args.containsKey('confirmation')
            ? PlanConfirmation.parse(args['confirmation'])
            : null;
        final preparedInvocation = _preparedInvocations[plan];
        final pageReview = invocation?.active == true
            ? invocation?.review
            : null;
        // A click is scoped to the next review attempt, including an adopted
        // plan with no direct service invocation to match against.
        if (workflow) invocation?.review = null;
        final quickAccepted =
            workflow &&
            preparedInvocation != null &&
            pageReview?.call(
                  preparedInvocation.reference,
                  preparedInvocation.input,
                  plan,
                  confirmation,
                ) ==
                true;
        final formAccepted =
            workflow &&
            preparedInvocation != null &&
            invocation?.active == true &&
            invocation?.commandIsCurrent?.call() == true &&
            invocation?.commandApproval?.allows(
                  reference: preparedInvocation.reference.toJson(),
                  input: preparedInvocation.input,
                  writes: plan.writes,
                  confirmation: confirmation,
                ) ==
                true;
        if (workflow) invocation?.commandApproval = null;
        final accepted =
            quickAccepted ||
            formAccepted ||
            workflow &&
                invocation?.active == true &&
                invocation?.inlineReview?.call(plan, confirmation) == true ||
            (await interaction?.call(actor, 'ui.review', {
                  'planId': plan.id,
                  'writes': plan.writes,
                  'result': plan.result,
                  if (confirmation != null)
                    'confirmation': confirmation.toJson(),
                })) ==
                true;
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
        final previewWorker = await isolated._readyScriptWorker(
          isolated.instances[package.id]!,
          workflow: true,
        );
        final value = await previewWorker.invoke(
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

  Future<void> _automate(
    Map<String, Object?> message, {
    bool trustedClock = false,
  }) async {
    final event = object(message['event']);
    // Reserve this event name even if a module forges a matching publisher.
    if (event['type'] == 'host.clock.tick' && !trustedClock) return;
    for (final instance in instances.values.toList()) {
      if (_closed || !store.active(instance.actor)) continue;
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
        if (event['type'] == 'host.clock.tick' &&
            object(session.result)['skipped'] == true &&
            session.writes.isEmpty &&
            session.events.isEmpty) {
          return;
        }
        final plan = store.seal(session);
        review(plan.id, instance.actor);
        await commit(instance.actor, plan.id);
        if (object(session.result)['skipped'] == true) {
          // An unchanged rolling horizon is the normal minute-tick outcome.
          // Preserve useful failure/change history without logging empty polls.
          if (event['type'] == 'host.clock.tick') return;
          status = 'skipped';
        }
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
    _closed = true;
    _clockAutomationTimer?.cancel();
    await _automationSubscription?.cancel();
    // A host that was never initialized has no work to drain. Its initial
    // completed Future may belong to a widget's now-idle fake async zone.
    if (_automationSubscription != null) await _automationTail;
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
