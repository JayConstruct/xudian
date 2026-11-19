part of 'module_host.dart';

extension _ModuleHostServices on ModuleHost {
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

  Future<Object?> _queryService(
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

  Future<ChangePlan> _prepareService(
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
    final plan = store.seal(session);
    _preparedInvocations[plan] = (reference: ref, input: freezeJson(input));
    return plan;
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
            '_host': {
              'callerModuleId': caller.moduleId,
              'operationId': session.operationId,
            },
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

  void _reviewPlan(String planId, ModuleActor caller) {
    store.plan(planId, caller);
    _reviewed.add(planId);
  }

  Future<Object?> _commitPlan(ModuleActor caller, String planId) async {
    final plan = store.plan(planId, caller);
    final used = <String>{};
    final result = await store.commit(
      planId,
      caller,
      clock: clockNow,
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

  String _directoryBaseline() {
    final ids = instances.keys.toList()..sort();
    return canonicalJson({
      'services': directoryServices(),
      'instances': [
        for (final id in ids)
          {
            'id': id,
            'version': instances[id]!.actor.version,
            'generation': instances[id]!.actor.generation,
            'space': instances[id]!.actor.space,
          },
      ],
    });
  }

  List<Object?> _directoryServices() => [
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
}
