part of 'script_page.dart';

extension _ScriptPageTimeline on _ScriptPageState {
  _PlannerTimeline? _timelineConfig(BoardItem spec) {
    final key = spec['key'];
    final timeline = object(spec['options'] ?? {})['timeline'];
    if (key is! String || key.isEmpty || timeline is! Map) return null;
    final keys = timeline['stateKeys'];
    if (keys is! Map) return null;
    final values = [
      timeline['rangeContextKey'],
      timeline['preferenceKey'],
      keys['startDate'],
      keys['visibleDays'],
    ];
    if (values.any((value) => value is! String || value.isEmpty)) return null;
    return _PlannerTimeline(
      key,
      values[0] as String,
      values[1] as String,
      values[2] as String,
      values[3] as String,
    );
  }

  BoardItem? _findPlannerBoard(Object? node, String key) {
    if (node is Map) {
      if (node['type'] == 'plannerBoard' && node['key'] == key) {
        return object(node);
      }
      for (final child in node.values) {
        final found = _findPlannerBoard(child, key);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final child in node) {
        final found = _findPlannerBoard(child, key);
        if (found != null) return found;
      }
    }
    return null;
  }

  bool _timelineCurrent(BoardItem? sourceTree, ScriptInstance? instance) =>
      mounted &&
      routeActive &&
      workspaceActive &&
      !staleTree &&
      instance != null &&
      widget.host.store.active(instance.actor) &&
      identical(instance, renderedInstance) &&
      identical(instance, widget.host.instances[widget.moduleId]) &&
      identical(tree, sourceTree);

  String _timelineDataIdentity() => canonicalJson({
    for (final entry in widget.host.store.moduleDataRevisions.entries)
      if (entry.key != uiPreferencesReadDependency(widget.moduleId))
        entry.key: entry.value,
  });

  void _plannerViewportChanged(
    BoardItem? sourceTree,
    _PlannerTimeline timeline,
    ScriptInstance? instance,
    BoardItem viewport,
  ) {
    if (!_timelineCurrent(sourceTree, instance)) return;
    final startDate = viewport['startDate'];
    final days = viewport['visibleDays'] ?? viewport['days'];
    if (startDate is! String ||
        parseInputDate(startDate) == null ||
        days is! int ||
        days < 1 ||
        days > 7) {
      return;
    }
    state = {
      ...state,
      timeline.startDateKey: startDate,
      timeline.daysKey: days,
    };
    _timelineViewports[timeline.key] = {'startDate': startDate, 'days': days};
    final host = widget.host;
    final actor = instance!.actor;
    _timelinePreferenceSaves[timeline.key] = (selectedDate) async {
      if (!actor.permissions.contains('ui')) {
        throw StateError('UI preferences require a UI page workflow');
      }
      await ModuleUiPreferences(host.store).set(actor, timeline.preferenceKey, {
        'startDate': startDate,
        'days': days,
        'selectedDate': selectedDate,
      }, notify: false);
    };
    _timelinePreferenceTimer?.cancel();
    _timelinePreferenceTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_flushTimelinePreferences()),
    );
  }

  Future<void> _flushTimelinePreferences() {
    _timelinePreferenceTimer?.cancel();
    final saves = _timelinePreferenceSaves.values.toList();
    _timelinePreferenceSaves.clear();
    final selectedDate = state['selectedDate'];
    final previous = _timelinePreferenceTail ?? Future<void>.value();
    if (saves.isEmpty) return previous;
    return _timelinePreferenceTail = previous.then((_) async {
      for (final save in saves) {
        try {
          await save(selectedDate);
        } catch (error) {
          debugPrint('Unable to save planner viewport: $error');
        }
      }
    });
  }

  Future<BoardItem?> _loadPlannerRange(
    BoardItem? sourceTree,
    _PlannerTimeline timeline,
    ScriptInstance? instance,
    String startDate,
    int days,
  ) async {
    final current = epoch;
    final changeRevision = _timelineChangeRevision;
    final requestContext = Map<String, Object?>.of(pageContext);
    final runtimeScope = PageRuntimeContextScope.read(context);
    final runtimeRevision = runtimeScope?.currentRevision();
    final dataIdentity = _timelineDataIdentity();
    final registry = _businessRegistry();
    bool isCurrent() =>
        _timelineCurrent(sourceTree, instance) &&
        current == epoch &&
        changeRevision == _timelineChangeRevision &&
        !busy &&
        dataIdentity == _timelineDataIdentity() &&
        registry == _businessRegistry() &&
        runtimeRevision == runtimeScope?.currentRevision() &&
        canonicalJson(requestContext) == canonicalJson(pageContext);
    if (!isCurrent()) return null;
    final result = await widget.host.invokePage(
      widget.moduleId,
      widget.handler,
      freezeJson({
        'state': state,
        'formValues': formValues,
        'event': null,
        'context': {
          ...requestContext,
          timeline.rangeContextKey: {'startDate': startDate, 'days': days},
        },
      }),
      readOnly: true,
      shouldRun: isCurrent,
    );
    if (!isCurrent()) return null;
    final board = _findPlannerBoard(object(result)['tree'], timeline.key);
    if (board == null ||
        board['days'] is! List ||
        board['blocks'] is! List ||
        board['options'] is! Map) {
      throw const FormatException(
        'Planner range response is missing its board',
      );
    }
    return {
      'days': board['days'],
      'blocks': board['blocks'],
      'options': board['options'],
    };
  }

  void _retainPlannerViewport(
    BoardItem nextState,
    BoardItem nextTree,
    Object? event,
    Map<String, BoardItem> requestedViewports,
  ) {
    for (final key in _timelineViewports.keys.toList()) {
      final previous = _findPlannerBoard(tree, key);
      final next = _findPlannerBoard(nextTree, key);
      final timeline = next == null ? null : _timelineConfig(next);
      if (previous == null ||
          timeline == null ||
          canonicalJson(object(previous['options'])['timeline']) !=
              canonicalJson(object(next!['options'])['timeline']) ||
          canonicalJson(object(previous['options'])['scrollRequest']) !=
              canonicalJson(object(next['options'])['scrollRequest'])) {
        _timelineViewports.remove(key);
        _timelinePreferenceSaves.remove(key);
        continue;
      }
      final viewport = _timelineViewports[key]!;
      if (event != null && identical(viewport, requestedViewports[key])) {
        _timelineViewports.remove(key);
        continue;
      }
      nextState[timeline.startDateKey] = viewport['startDate'];
      nextState[timeline.daysKey] = viewport['days'];
    }
  }
}

class _PlannerTimeline {
  const _PlannerTimeline(
    this.key,
    this.rangeContextKey,
    this.preferenceKey,
    this.startDateKey,
    this.daysKey,
  );
  final String key, rangeContextKey, preferenceKey, startDateKey, daysKey;
}
