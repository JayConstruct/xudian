part of 'module_host.dart';

extension _ModuleHostInstallation on ModuleHost {
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

  Future<HostInstallBatchPlan> _prepareInstallBatch(
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
      _validateRequiredServices(package, selected);
      visiting.remove(package.id);
      visited.add(package.id);
    }

    for (final package in selected.values) {
      visit(package);
    }
  }

  Future<void> _commitInstallBatch(
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
      await store.transactionWithDataRevisions(() async {
        final previousZone = _installBatchZone;
        _installBatchZone = Zone.current;
        try {
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
                  (package) =>
                      package.dependencies.every(instances.containsKey),
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
          validateModuleUiDeclarations(
            instances.values.map((instance) => instance.package),
          );
        } finally {
          _installBatchZone = previousZone;
        }
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

  List<String> _affectedDependents(String id) {
    final affected = <String>{};
    void visit(String current) {
      for (final dependent in dependents(current)) {
        if (affected.add(dependent)) visit(dependent);
      }
    }

    visit(id);
    return affected.toList();
  }

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
      _validateDependents(package);
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

  List<String> _dependents(String id) => [
    for (final entry in instances.entries)
      if (entry.key != id &&
          (entry.value.package.dependencies.contains(id) ||
              (entry.value.package.manifest['serviceDependencies'] as List? ??
                      [])
                  .any((v) => object(v)['moduleId'] == id)))
        entry.key,
  ];
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

  Future<bool> _wasErased(String id) async => (await store.sql(
    'SELECT value FROM host_meta WHERE key=?',
    ['erased-module:$id'],
  )).isNotEmpty;

  Future<void> _uninstall(
    String id, {
    bool cascade = false,
    bool deleteData = false,
  }) async {
    await _disable(id, cascade: cascade);
    if (deleteData) await onDeleteData?.call(id);
    final packages = deleteData
        ? await store.sql(
            'SELECT digest FROM host_packages WHERE module_id=?',
            [id],
          )
        : <Map<String, Object?>>[];
    await store.db.transaction(() async {
      await store.db.customStatement(
        'UPDATE host_installations SET installed=0 WHERE module_id=?',
        [id],
      );
      if (deleteData) {
        await store.db.customStatement(
          'DELETE FROM host_commits WHERE caller=? OR plan_id IN '
          '(SELECT plan_id FROM host_operations WHERE module_id=?)',
          [id, id],
        );
        for (final table in [
          'host_records',
          'host_collections',
          'host_indexes',
          'host_snapshots',
          'host_operations',
          'host_automation',
          'host_outbox',
          'host_packages',
          'host_installations',
          'host_ui_preferences',
        ]) {
          await store.db.customStatement(
            'DELETE FROM $table WHERE module_id=?',
            [id],
          );
        }
        await store.db.customStatement(
          'DELETE FROM host_operations WHERE caller=?',
          [id],
        );
        await eraseLegacyModuleArchives(store, id);
        final sourcePrefix = 'legacy-source:$id:';
        await store.db.customStatement(
          'DELETE FROM host_meta WHERE key IN (?,?) OR substr(key,1,?)=?',
          [
            'module-repository:$id',
            'legacy-error:$id',
            sourcePrefix.length,
            sourcePrefix,
          ],
        );
        await store.db.customStatement('DELETE FROM app_settings WHERE key=?', [
          'modules.builtin.$id',
        ]);
        // Keep only a deletion marker so defaults or a migration retry cannot
        // silently reinstall an erased module. Explicit installation is allowed.
        await store.db.customStatement(
          'INSERT OR REPLACE INTO host_meta(key,value) VALUES(?,?)',
          ['erased-module:$id', 'complete'],
        );
      }
    });
    if (deleteData) {
      failures.removeWhere((key, _) => key == id || key.startsWith('$id@'));
    }
    try {
      for (final digest in packages.map((row) => row['digest']).toSet()) {
        if (digest is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
          continue;
        }
        if ((await store.sql('SELECT 1 FROM host_packages WHERE digest=?', [
          digest,
        ])).isNotEmpty) {
          continue;
        }
        final file = File('${directory.path}/$digest.xmodule');
        if (await file.exists()) await file.delete();
      }
    } finally {
      _notifyRegistry();
    }
  }

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

  Future<void> _recoverSnapshot(String id, String snapshotId) => _serialize(
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
      _validateDependents(package);
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
}
