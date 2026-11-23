import '../../features/settings/settings_widgets.dart';
import '../../features/settings/settings_focus.dart';
import '../ui/workspace_interaction.dart';
import '../ui/ui_icon.dart';
import '../ui/page_runtime_context.dart';
import '../ui/page_composition_readiness.dart';
import '../ui/page_first_frame.dart';
import '../ui/page_loading_placeholder.dart';
import '../ui/date_reveal.dart';
import 'date_page_cache.dart';
import '../../app/app_icons.dart';

import 'dart:async';

import '../contracts/json_values.dart';
import '../performance/ui_load_trace.dart';
import '../ui/workspace_header.dart';
import '../ui/module_detail_page.dart';
import '../ui/workspace_header_action.dart';
import '../ui/workspace_typography.dart';
import '../ui/ui_component.dart';
import '../ui/ui_pack.dart';
import '../ui/temporal_input.dart';
import '../ui/script_transition.dart';
import '../ui/script_motion.dart';
import '../ui/script_swipe_actions.dart';
import '../ui/script_ui_scope.dart';
import '../ui/time_range_table.dart';
import '../ui/conversation_widgets.dart';
import '../ui/native_ui.dart';
import '../ui/script_keyed_list.dart';
import '../ui/draggable_floating_panel.dart';
import '../../app/app_ui_feedback.dart';
import '../../app/app_motion.dart';
import '../ui/responsive_content_grid.dart';
import '../ui/input_validation.dart';
import '../ui/script_form_controls.dart';
import '../ui/script_content_widgets.dart';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:xquickjs/error_message.dart';

import '../../app/design_system.dart';
import 'module_host.dart';
import 'module_package.dart';
import 'time_grid.dart';
import 'planner_board.dart';
import 'planner_quick_adjust.dart';
import 'native_time_gestures.dart';
import 'collection_store.dart';
import 'data_change_review.dart';
import 'inline_plan_review.dart';
import 'native_command_approval.dart';
import 'ui_preferences.dart';

part 'script_page_timeline.dart';
part 'script_page_nodes.dart';

class ScriptPage extends StatefulWidget {
  const ScriptPage({
    super.key,
    required this.host,
    required this.moduleId,
    required this.handler,
    this.pageContext = const {},
    this.embedded = false,
    this.settingsStyle = false,
  });
  final ModuleHost host;
  final String moduleId, handler;
  final Map<String, Object?> pageContext;
  final bool embedded;
  final bool settingsStyle;
  @override
  State<ScriptPage> createState() => _ScriptPageState();
}

class _ScriptPageState extends State<ScriptPage> with WidgetsBindingObserver {
  Map<String, Object?> state = {}, formValues = {};
  Map<String, Object?>? tree;
  String? treeContextIdentity;
  Object? renderedInstance;
  Map<String, Object?>? renderedHeader;
  final controllers = <String, TextEditingController>{};
  final focusNodes = <String, FocusNode>{};
  final scrollControllers = <String, ScrollController>{};
  final inputTimers = <String, Timer>{};
  final formRevisions = <String, int>{};
  final controlKeys = <String, GlobalKey>{};
  final scrollRequests = <String, Object?>{};
  final controlValues = <String, Object?>{};
  final controlConfigs = <String, String>{};
  StreamSubscription<Set<String>>? subscription;
  StreamSubscription<void>? registrySubscription;
  Timer? refreshTimer;
  Timer? progressTimer;
  Timer? datePrefetchTimer;
  final dateCache = DatePageCache();
  int cacheDataRevision = -1;
  int datePrefetchRevision = 0;
  bool dateContentBlocked = false;
  int epoch = 0;
  int dateIntentRevision = 0;
  String? error;
  Map<String, Object?> localRuntimeContext = const {};
  Map<String, Object?> get pageContext => {
    ...widget.pageContext,
    ...?PageRuntimeContextScope.read(context)?.currentValues(),
    ...localRuntimeContext,
  };
  String get sessionKey =>
      '${widget.moduleId}:${widget.handler}:${canonicalJson(withoutRuntimePageContext(widget.pageContext))}';
  bool busy = false, dirty = false;
  bool _refreshingForms = false, _waitingAction = false;
  final _formCacheWrites = <Future<void>>{};
  int _formCacheRevision = 0;
  String? _formCacheError;
  bool get _actionBusy => tree?['queueInputActions'] == true
      ? _waitingAction || busy && !_refreshingForms
      : busy;
  bool _plannerDragging = false, _refreshAfterPlannerDrag = false;
  Completer<void>? _renderFinished;
  bool showProgress = false;
  bool routeActive = true;
  bool workspaceActive = true;
  Set<String>? readModules;
  String businessRegistry = '', examplesRegistry = '';
  Object? pendingEvent, currentEvent, queryResult;
  String? pendingEventContext;
  int? pendingEventRuntimeRevision;
  int? pendingEventDateIntent;
  PageCompositionReadinessScope? compositionReadiness;
  PageFirstFrameReadiness? firstFrameReadiness;
  WorkspaceHeaderController? headerController;
  BuildContext? nodeContext;
  // Rendering a frozen script tree again (busy/chrome/lifecycle changes) must
  // not allocate a new board snapshot and invalidate all its geometry caches.
  final _plannerLists = Expando<List<BoardItem>>('planner snapshot lists');
  bool _quickAdjust = false;
  static const _quickAdjustHeaderEvent = 'host.planner.quickAdjust';
  BoardItem? _pendingPlannerAdjustment;
  BoardItem? _retryPlannerMove;
  ScaffoldMessengerState? _plannerNoticeMessenger;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _plannerUndoNotice;
  final _timeGestures = NativeTimeGestures();
  final _inlineApprovals = Expando<InlinePlanApproval>(
    'native plan confirmation',
  );
  final _commandApprovals = Expando<NativeCommandApproval>(
    'native single command interaction',
  );
  _InlinePlanPreview? _inlinePlanPreview;
  final _timelineViewports = <String, BoardItem>{};
  final _timelinePreferenceSaves =
      <String, Future<void> Function(Object? selectedDate)>{};
  Timer? _timelinePreferenceTimer;
  Future<void>? _timelinePreferenceTail;
  int _timelineChangeRevision = 0;

  _InlinePlanPreview? _readInlinePlanPreview() {
    final declaration = tree?['planReview'];
    final footer = tree?['footer'];
    if (widget.embedded ||
        declaration is! Map ||
        footer is! Map ||
        declaration.length != 2 ||
        declaration['planId'] is! String ||
        declaration['eventType'] is! String ||
        (declaration['eventType'] as String).trim().isEmpty ||
        footer['type'] != 'row' ||
        footer['children'] is! List) {
      return null;
    }
    final buttons = <Map<String, Object?>>[];
    for (final raw in footer['children'] as List) {
      if (raw is! Map ||
          raw['type'] != 'button' ||
          raw['text'] is! String ||
          raw['event'] is! Map ||
          raw['interrupt'] != null) {
        return null;
      }
      buttons.add(object(raw));
    }
    final eventType = declaration['eventType'] as String;
    bool confirms(Map<String, Object?> button) =>
        canonicalJson(button['event']) == canonicalJson({'type': eventType});
    if (buttons.where(confirms).length != 1 || buttons.length > 3) return null;
    try {
      final instance = widget.host.instances[widget.moduleId];
      if (instance == null) return null;
      final plan = widget.host.store.plan(
        declaration['planId'] as String,
        instance.actor,
      );
      final summary = DataChangeSummary.tryParse({
        'planId': plan.id,
        'writes': plan.writes,
        'result': plan.result,
      });
      return summary == null
          ? null
          : _InlinePlanPreview(plan, summary, eventType, buttons);
    } on Object {
      // Unknown, stale or foreign plans keep the ordinary review flow.
      return null;
    }
  }

  Widget _inlineReviewFooter(_InlinePlanPreview preview) => UiPackScope(
    defaultOnly: true,
    child: NativeUi(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '实际变更：新增 ${preview.summary.count(DataChangeKind.add)} · 修改 ${preview.summary.count(DataChangeKind.update)} · 删除 ${preview.summary.count(DataChangeKind.delete)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: '查看实际变更详情',
                onPressed: () => showDataChangeDetails(context, preview.summary),
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final button in preview.buttons)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child:
                        button['event'] is Map &&
                            canonicalJson(button['event']) ==
                                canonicalJson({'type': preview.eventType})
                        ? FilledButton(
                            onPressed: busy || bind(button['disabled']) == true
                                ? null
                                : () {
                                    if (!mounted ||
                                        busy ||
                                        staleTree ||
                                        !routeActive ||
                                        !workspaceActive ||
                                        !identical(
                                          preview,
                                          _inlinePlanPreview,
                                        ) ||
                                        !identical(
                                          renderedInstance,
                                          widget.host.instances[widget
                                              .moduleId],
                                        )) {
                                      return;
                                    }
                                    final event = <String, Object?>{
                                      'type': preview.eventType,
                                    };
                                    _inlineApprovals[event] =
                                        InlinePlanApproval(preview.plan);
                                    unawaited(_render(event));
                                  },
                            child: Text(
                              button['text'] as String,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : TextButton(
                            onPressed: busy || bind(button['disabled']) == true
                                ? null
                                : () => _render(button['event']),
                            child: Text(
                              button['text'] as String,
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  BoardItem? _quickAdjustmentConfig(BoardItem spec) => _timeGestures
      .configuration(widget.host, widget.moduleId, spec['quickAdjustment']);

  void _plannerEvent(Object? event, BoardItem? quickConfig) {
    if (busy || staleTree || !routeActive || !workspaceActive) return;
    if (event is Map && event['type'] == 'dismissMove') {
      _retryPlannerMove = null;
    }
    if (event is Map &&
        event['type'] == 'retryMove' &&
        quickConfig != null &&
        _quickAdjust &&
        _retryPlannerMove != null) {
      _plannerEvent(Map<String, Object?>.of(_retryPlannerMove!), quickConfig);
      return;
    }
    if (quickConfig != null &&
        _quickAdjust &&
        event is Map &&
        event['type'] == 'move') {
      _timeGestures.begin(event, widget.host, widget.moduleId, quickConfig);
      if (event['intent'] == null ||
          event['intent'] == 'move' ||
          event['intent'] == 'resize') {
        _retryPlannerMove = object(freezeJson(event));
        setState(() {
          _pendingPlannerAdjustment = Map.unmodifiable({
            'id': event['taskId'] ?? event['id'],
            'start': event['start'],
            'end': event['end'],
          });
        });
      }
    }
    unawaited(_render(event));
  }

  void _commandEvent(Object? event, Object? declaration) {
    if (!mounted ||
        _actionBusy ||
        staleTree ||
        !routeActive ||
        !workspaceActive) {
      return;
    }
    if (busy) {
      final instance = widget.host.instances[widget.moduleId];
      final identity = canonicalJson(pageContext);
      final pageKey = tree?['scrollKey'];
      final dateIntent = dateIntentRevision;
      final runtimeRevision = PageRuntimeContextScope.read(context)
          ?.currentRevision();
      final boundDeclaration = _bindValue(declaration);
      setState(() => _waitingAction = true);
      unawaited(() async {
        bool current() =>
            mounted &&
            routeActive &&
            workspaceActive &&
            !staleTree &&
            identical(instance, widget.host.instances[widget.moduleId]) &&
            identity == canonicalJson(pageContext) &&
            pageKey == tree?['scrollKey'] &&
            dateIntent == dateIntentRevision &&
            runtimeRevision ==
                PageRuntimeContextScope.read(context)?.currentRevision();
        while (current() && busy && _refreshingForms) {
          final finished = _renderFinished;
          if (finished == null) break;
          await finished.future;
        }
        if (!mounted) return;
        setState(() => _waitingAction = false);
        if (current() && !busy) _commandEvent(event, boundDeclaration);
      }());
      return;
    }
    if (event is! Map || declaration == null) {
      unawaited(_render(event));
      return;
    }
    // Use a fresh event identity. Only this actual native callback may attach
    // authority; a script sending identical JSON cannot recover it.
    final nativeEvent = freezeJson(event) as Map<String, Object?>;
    final approval = NativeCommandApproval.fromInteraction(
      _bindValue(declaration),
    );
    if (approval != null) _commandApprovals[nativeEvent] = approval;
    unawaited(_render(nativeEvent));
  }

  void _showPlannerUndo(PlannerQuickAdjustment adjustment, Object instance) {
    final undo = adjustment.undoAdjustment;
    final batchId = adjustment.batchId;
    if (undo == null || batchId == null || !routeActive || !workspaceActive) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(uiContext);
    if (messenger == null) return;
    // A new adjustment replaces its predecessor immediately, without queuing
    // an outgoing notice/animation during consecutive scheduling gestures.
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    final message = adjustment.successMessage ?? '已调整';
    final notice = messenger.showSnackBar(
      SnackBar(
        content: Tooltip(
          message: message,
          child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          WorkspaceContentInsets.bottomOf(uiContext) + 12,
        ),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            if (!mounted ||
                !routeActive ||
                !workspaceActive ||
                !identical(instance, widget.host.instances[widget.moduleId])) {
              return;
            }
            final event = <String, Object?>{'type': 'undo', 'id': batchId};
            _timeGestures.attachUndo(event, undo);
            unawaited(_render(event));
          },
        ),
      ),
    );
    _plannerUndoNotice = notice;
    _plannerNoticeMessenger = messenger;
    unawaited(
      notice.closed.then((_) {
        if (identical(_plannerUndoNotice, notice)) {
          _plannerUndoNotice = null;
          _plannerNoticeMessenger = null;
        }
      }),
    );
  }

  void _closePlannerUndo() {
    final notice = _plannerUndoNotice;
    final messenger = _plannerNoticeMessenger;
    // Closing an owned controller removes only this page's notice. Defer the
    // messenger state update when navigation is currently building the tree.
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scheduleMicrotask(() {
          if (!identical(_plannerUndoNotice, notice)) return;
          _plannerUndoNotice = null;
          _plannerNoticeMessenger = null;
          // FeatureController.close assumes a live, nonempty queue. The
          // messenger may have been disposed along with this entire page.
          if (messenger?.mounted == true) messenger!.removeCurrentSnackBar();
        });
      });
    }
  }

  List<BoardItem> _plannerItems(Object? value) {
    if (value is! List) return const [];
    return _plannerLists[value] ??= objects(value);
  }

  bool retainDateNavigation = false;
  bool get staleTree =>
      tree != null && treeContextIdentity != canonicalJson(pageContext);
  BuildContext get uiContext => nodeContext ?? context;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final saved = widget.host.pageSessions[sessionKey];
    if (saved != null) {
      state = object(saved['state']);
      formValues = object(saved['formValues']);
    }
    _subscribe();
    unawaited(_render());
  }

  void _subscribe() {
    subscription = widget.host.store.changes.stream.listen((modules) {
      _timelineChangeRevision++;
      dateCache.invalidateModules(modules);
      if (readModules != null && !modules.any(readModules!.contains)) return;
      refreshTimer?.cancel();
      refreshTimer = Timer(const Duration(milliseconds: 40), () => _render());
    });
    businessRegistry = _businessRegistry();
    examplesRegistry = _examplesRegistry();
    registrySubscription = widget.host.registryChanges.stream.listen((_) {
      final next = _businessRegistry();
      final nextExamples = _examplesRegistry();
      final refresh =
          next != businessRegistry ||
          (readModules?.contains(uiExamplesReadDependency) == true &&
              nextExamples != examplesRegistry);
      if (nextExamples != examplesRegistry) {
        dateCache.invalidateModules({uiExamplesReadDependency});
      }
      businessRegistry = next;
      examplesRegistry = nextExamples;
      if (refresh) {
        dateCache.clear();
        unawaited(_render());
      }
    });
    // Civil dates can change in a configured timezone while the page is open.
    refreshTimer = Timer(const Duration(minutes: 1), () => _render());
  }

  String _businessRegistry() => widget.host.instances.values
      .where((i) => !i.package.isUiPack)
      .map(
        (i) => '${i.actor.moduleId}:${i.actor.generation}:${i.actor.version}',
      )
      .join('|');

  String _examplesRegistry() => widget.host.instances.values
      .where((i) => i.package.isUiPack)
      .map(
        (i) =>
            '${i.actor.moduleId}:${i.actor.generation}:${i.package.packageDigest}',
      )
      .join('|');

  @override
  void didUpdateWidget(ScriptPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.host, widget.host) ||
        old.moduleId != widget.moduleId ||
        old.handler != widget.handler ||
        canonicalJson(withoutRuntimePageContext(old.pageContext)) !=
            canonicalJson(withoutRuntimePageContext(widget.pageContext))) {
      unawaited(_flushTimelinePreferences());
      _timelineViewports.clear();
      epoch++;
      dateCache.clear();
      cacheDataRevision = -1;
      datePrefetchRevision++;
      datePrefetchTimer?.cancel();
      busy = false;
      _quickAdjust = false;
      _pendingPlannerAdjustment = null;
      _retryPlannerMove = null;
      _closePlannerUndo();
      showProgress = false;
      progressTimer?.cancel();
      for (final controller in controllers.values) {
        controller.dispose();
      }
      controllers.clear();
      for (final node in focusNodes.values) {
        node.dispose();
      }
      focusNodes.clear();
      for (final controller in scrollControllers.values) {
        controller.dispose();
      }
      scrollControllers.clear();
      for (final timer in inputTimers.values) {
        timer.cancel();
      }
      inputTimers.clear();
      formRevisions.clear();
      controlKeys.clear();
      scrollRequests.clear();
      controlValues.clear();
      controlConfigs.clear();
      _formCacheRevision++;
      _formCacheError = null;
      state = {};
      formValues = {};
      tree = null;
      treeContextIdentity = null;
      renderedInstance = null;
      renderedHeader = null;
      error = null;
      localRuntimeContext = const {};
      readModules = null;
      subscription?.cancel();
      registrySubscription?.cancel();
      refreshTimer?.cancel();
      _subscribe();
      unawaited(_render());
    } else if (canonicalJson(old.pageContext) !=
        canonicalJson(widget.pageContext)) {
      unawaited(_flushTimelinePreferences());
      unawaited(_render());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    workspaceActive = TickerMode.valuesOf(context).enabled;
    final active = ModalRoute.isCurrentOf(context) != false && workspaceActive;
    if (active == routeActive) return;
    routeActive = active;
    if (!active) unawaited(_flushTimelinePreferences());
    if (!active) _closePlannerUndo();
    if (!workspaceActive) headerController?.clear(this);
    progressTimer?.cancel();
    showProgress = false;
    if (busy && active) _delayProgress(epoch);
    if (active) _restoreHeader();
    if (active && dirty && !busy) {
      dirty = false;
      final next = _takePendingEvent();
      unawaited(_render(next));
    }
  }

  void _restoreHeader() {
    final scope = WorkspaceHeaderScope.read(context);
    final lease = scope?.lease;
    if (tree == null ||
        widget.embedded ||
        lease?.mode != 'contributed' ||
        lease?.moduleId != widget.moduleId ||
        lease?.pageId != widget.pageContext['pageId'] ||
        !identical(renderedInstance, widget.host.instances[widget.moduleId]) ||
        treeContextIdentity != canonicalJson(pageContext)) {
      return;
    }
    headerController = scope!.controller;
    scope.controller.publish(lease!, this, _hostHeader, _renderHeaderEvent);
  }

  bool get _hasQuickAdjustHeader =>
      renderedHeader?['compact'] == true &&
      renderedHeader?['layout'] == 'plannerTimeline' &&
      _hasQuickAdjustBoard(tree);

  bool _hasQuickAdjustBoard(Object? node) {
    if (node is Map) {
      if (node['type'] == 'plannerBoard' &&
          _quickAdjustmentConfig(object(node)) != null) {
        return true;
      }
      return node.values.any(_hasQuickAdjustBoard);
    }
    return node is List && node.any(_hasQuickAdjustBoard);
  }

  Map<String, Object?> get _quickAdjustHeaderAction => {
    'label': '调整',
    'tooltip': '快速调整',
    'icon': 'tune',
    'presentation': 'inline',
    'variant': 'text',
    'overflowOnly': true,
    'selected': _quickAdjust,
    'event': {'type': _quickAdjustHeaderEvent},
  };

  Map<String, Object?>? get _hostHeader => !_hasQuickAdjustHeader
      ? renderedHeader
      : {
          ...renderedHeader!,
          'actions': [
            _quickAdjustHeaderAction,
            ...?renderedHeader!['actions'] as List?,
          ],
        };

  void _setQuickAdjust(bool value) {
    if (!mounted || !workspaceActive || staleTree || _quickAdjust == value) {
      return;
    }
    setState(() => _quickAdjust = value);
    _restoreHeader();
  }

  // Open-menu controls may be pressed while a preference invalidation is
  // refreshing the page. Preserve each accepted action instead of feeding it
  // through the ordinary latest-intent slot used by date navigation.
  Future<void> _renderHeaderEvent(Object? event) async {
    if (event is Map && event['type'] == _quickAdjustHeaderEvent) {
      if (_hasQuickAdjustHeader) _setQuickAdjust(!_quickAdjust);
      return;
    }
    final instance = widget.host.instances[widget.moduleId];
    final identity = canonicalJson(pageContext);
    final controller = headerController;
    final lease = controller?.lease;
    bool valid() =>
        mounted &&
        workspaceActive &&
        identical(instance, widget.host.instances[widget.moduleId]) &&
        canonicalJson(pageContext) == identity &&
        identical(controller?.lease, lease) &&
        lease?.isActive() == true;
    while (valid() && busy) {
      final finished = _renderFinished;
      if (finished == null) return;
      await finished.future;
    }
    // Navigator.pop exposes the workspace route before its inherited
    // isCurrent dependency has rebuilt this page. Await that frame before
    // starting an event which may flush pending viewport preferences.
    if (!mounted) return;
    if (valid() && !routeActive && ModalRoute.of(context)?.isCurrent == true) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (valid()) await _render(event);
  }

  void _delayProgress(int current) {
    progressTimer?.cancel();
    if (!routeActive || _pendingPlannerAdjustment != null) return;
    progressTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && current == epoch && busy) {
        setState(() => showProgress = true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value != AppLifecycleState.resumed) {
      unawaited(_flushTimelinePreferences());
    }
    if (value == AppLifecycleState.resumed) {
      dateCache.clear();
      unawaited(_render());
    }
  }

  void _checkDateCacheRevision() {
    // Registry notifications are asynchronous too. A provider replacement can
    // change a preparation's meaning even if this renderer's instance survives.
    final nextRegistry = _businessRegistry();
    final nextExamples = _examplesRegistry();
    if (nextRegistry != businessRegistry) dateCache.clear();
    if (nextExamples != examplesRegistry) {
      dateCache.invalidateModules({uiExamplesReadDependency});
    }
    businessRegistry = nextRegistry;
    examplesRegistry = nextExamples;
    final revision = widget.host.store.dataRevision;
    if (cacheDataRevision != revision) {
      dateCache.synchronizeDataRevision(
        revision,
        widget.host.store.moduleDataRevisions,
      );
      cacheDataRevision = revision;
    }
  }

  void _prepareAdjacentDates({
    Duration delay = const Duration(milliseconds: 100),
  }) {
    datePrefetchTimer?.cancel();
    final current = ++datePrefetchRevision;
    if (DateRevealScope.read(context) == null) return;
    final date = parseInputDate(pageContext['selectedDate']);
    if (date == null || !workspaceActive || !routeActive) return;
    final instance = widget.host.instances[widget.moduleId];
    if (instance == null) return;
    final dataRevision = widget.host.store.dataRevision;
    final registry = _businessRegistry();
    final examples = _examplesRegistry();
    final selectedDate = pageContext['selectedDate'];
    bool canStart() =>
        mounted &&
        !busy &&
        workspaceActive &&
        routeActive &&
        current == datePrefetchRevision &&
        dataRevision == widget.host.store.dataRevision &&
        registry == _businessRegistry() &&
        examples == _examplesRegistry() &&
        identical(instance, widget.host.instances[widget.moduleId]) &&
        selectedDate == pageContext['selectedDate'];
    datePrefetchTimer = Timer(delay, () async {
      if (!canStart()) return;
      // Input defaults are registered during the paint after a query. Capture
      // state and forms only once that paint has completed, not in its finally.
      final inputState = freezeJson(state);
      final inputForms = freezeJson(formValues);
      final contextValues = Map<String, Object?>.of(pageContext);
      final signature = canonicalJson([inputState, inputForms, contextValues]);
      bool isCurrent() =>
          canStart() &&
          signature == canonicalJson([state, formValues, pageContext]);
      for (final offset in const [1, -1]) {
        if (!isCurrent()) break;
        final next = DateTime.utc(date.year, date.month, date.day + offset);
        if (next.year < 1 || next.year > 9999) continue;
        final input = <String, Object?>{
          'state': inputState,
          'context': {...contextValues, 'selectedDate': formatInputDate(next)},
          'event': null,
          'formValues': inputForms,
        };
        _checkDateCacheRevision();
        await dateCache.prepare(
          instance: instance,
          input: input,
          shouldRun: isCurrent,
          load: (stillCurrent) async {
            Set<String> reads = const {};
            var replayable = false;
            final result = await widget.host.invokePage(
              widget.moduleId,
              widget.handler,
              input,
              readOnly: true,
              shouldRun: stillCurrent,
              onReads: (value) => reads = value,
              onReplayable: (value) => replayable = value,
            );
            return result is Map && replayable
                ? PreparedDatePage(result: object(result), reads: reads)
                : null;
          },
        );
        // Yield between speculative reads so a foreground event can enter the
        // serialized workflow before the other adjacent date is prepared.
        await Future<void>.delayed(Duration.zero);
      }
    });
  }

  Future<void> _render([Object? event]) async {
    if (!mounted) return;
    if (event == null && _plannerDragging) {
      _refreshAfterPlannerDrag = true;
      return;
    }
    if (!workspaceActive) {
      dirty = true;
      if (event != null) _queueEvent(event);
      return;
    }
    firstFrameReadiness = PageFirstFrameReadinessScope.read(context);
    if (_pendingPlannerAdjustment == null) firstFrameReadiness?.begin(this);
    final readiness = PageCompositionReadinessScope.read(context);
    compositionReadiness = readiness;
    if (_pendingPlannerAdjustment == null) readiness?.begin(this);
    if (busy) {
      dirty = true;
      if (event != null) _queueEvent(event);
      return;
    }
    final current = ++epoch;
    final finished = _renderFinished = Completer<void>();
    final requestedDateIntent = dateIntentRevision;
    final requestContext = pageContext;
    final runtimeScope = PageRuntimeContextScope.read(context);
    final runtimeRevision = runtimeScope?.currentRevision();
    final instance = widget.host.instances[widget.moduleId];
    final headerScope = WorkspaceHeaderScope.read(context);
    final headerLease = headerScope?.lease;
    final ownsHeader =
        !widget.embedded &&
        headerLease?.mode == 'contributed' &&
        headerLease?.moduleId == widget.moduleId &&
        headerLease?.pageId == widget.pageContext['pageId'];
    if (ownsHeader) headerController = headerScope!.controller;
    progressTimer?.cancel();
    setState(() {
      busy = true;
      _refreshingForms =
          event == null || event is Map && event['type'] == 'field';
      showProgress = false;
    });
    // Fast renders and opening a chooser should not flash a loading indicator.
    _delayProgress(current);
    final sentForms = Map<String, Object?>.of(formValues);
    final sentRevisions = Map<String, int>.of(formRevisions);
    final adjustment = event is Map ? _timeGestures.lookup(event) : null;
    final inlineApproval = event is Map ? _inlineApprovals[event] : null;
    final commandApproval = event is Map ? _commandApprovals[event] : null;
    bool commandIsCurrent() =>
        mounted &&
        current == epoch &&
        routeActive &&
        workspaceActive &&
        requestedDateIntent == dateIntentRevision &&
        canonicalJson(requestContext) == canonicalJson(pageContext) &&
        runtimeRevision == runtimeScope?.currentRevision() &&
        identical(instance, widget.host.instances[widget.moduleId]);
    String? approvedPlanId;
    try {
      if (_formCacheWrites.isNotEmpty) {
        do {
          await Future.wait(_formCacheWrites.toList());
        } while (_formCacheWrites.isNotEmpty);
        if (!mounted ||
            current != epoch ||
            event != null && (!routeActive || !workspaceActive || staleTree) ||
            !identical(instance, widget.host.instances[widget.moduleId]) ||
            canonicalJson(requestContext) != canonicalJson(pageContext) ||
            runtimeRevision != runtimeScope?.currentRevision()) {
          return;
        }
      }
      if (event != null && _timelineViewports.isNotEmpty ||
          _timelinePreferenceTail != null) {
        do {
          await _flushTimelinePreferences();
        } while (mounted &&
            current == epoch &&
            _timelinePreferenceSaves.isNotEmpty);
        if (!mounted ||
            current != epoch ||
            event != null && (!routeActive || !workspaceActive || staleTree) ||
            !identical(instance, widget.host.instances[widget.moduleId]) ||
            canonicalJson(requestContext) != canonicalJson(pageContext) ||
            runtimeRevision != runtimeScope?.currentRevision()) {
          return;
        }
      }
      final input = freezeJson(<String, Object?>{
        'state': state,
        'context': requestContext,
        'event': event,
        'formValues': sentForms,
      }) as Map<String, Object?>;
      _checkDateCacheRevision();
      final requestedDataRevision = widget.host.store.dataRevision;
      final requestedTimelineData = _timelineDataIdentity();
      final requestedViewports = Map<String, BoardItem>.of(_timelineViewports);
      final requestedRegistry = businessRegistry;
      final requestedExamples = examplesRegistry;
      final startedAt = clock.now();
      final prepared = instance == null
          ? null
          : dateCache.lookup(instance, input);
      if (event == null && requestContext['selectedDate'] is String) {
        UiLoadTrace.instant(
          'page.cache',
          arguments: {
            'moduleId': widget.moduleId,
            'handler': widget.handler,
            'outcome': prepared == null ? 'miss' : 'hit',
          },
        );
      }
      Set<String>? resultReads = prepared?.reads;
      var replayable = false;
      final result = object(
        prepared?.result ??
            await widget.host.invokePage(
              widget.moduleId,
              widget.handler,
              input,
              onReads: (reads) => resultReads = reads,
              onReplayable: (value) => replayable = value,
              commandIsCurrent: commandIsCurrent,
              onInlineReview: inlineApproval == null
                  ? null
                  : (plan, confirmation) {
                      if (!mounted ||
                          current != epoch ||
                          !routeActive ||
                          !workspaceActive ||
                          canonicalJson(requestContext) !=
                              canonicalJson(pageContext) ||
                          runtimeRevision !=
                              PageRuntimeContextScope.read(context)
                                  ?.currentRevision() ||
                          !identical(
                            instance,
                            widget.host.instances[widget.moduleId],
                          )) {
                        return false;
                      }
                      return inlineApproval.allows(plan, confirmation);
                    },
              onReview: commandApproval != null
                  ? (reference, preparedInput, plan, confirmation) =>
                        commandIsCurrent() &&
                        commandApproval.allows(
                          reference: reference.toJson(),
                          input: preparedInput,
                          writes: plan.writes,
                          confirmation: confirmation,
                        )
                  : adjustment != null
                  ? (reference, preparedInput, plan, confirmation) {
                      if (reference.major != 1 || !commandIsCurrent()) {
                        return false;
                      }
                      final accepted = adjustment.allows(
                        moduleId: reference.moduleId,
                        serviceId: reference.serviceId,
                        input: preparedInput,
                        writes: plan.writes,
                        result: plan.result,
                        confirmation: confirmation,
                      );
                      if (accepted) {
                        approvedPlanId = plan.id;
                      } else if (_pendingPlannerAdjustment != null) {
                        setState(() => _pendingPlannerAdjustment = null);
                      }
                      return accepted;
                    }
                  : null,
              onCommit: adjustment == null
                  ? null
                  : (plan) {
                      if (plan.id == approvedPlanId &&
                          mounted &&
                          current == epoch &&
                          instance != null &&
                          identical(
                            instance,
                            widget.host.instances[widget.moduleId],
                          )) {
                        _retryPlannerMove = null;
                        _showPlannerUndo(adjustment, instance);
                      }
                    },
            ),
      );
      if (!mounted ||
          current != epoch ||
          !identical(instance, widget.host.instances[widget.moduleId])) {
        return;
      }
      // A result queried for an older date cannot publish its tree or patch
      // after another contribution has changed this composition's date.
      if (canonicalJson(requestContext) != canonicalJson(pageContext) ||
          requestedDateIntent != dateIntentRevision ||
          event == null &&
              (_timelineViewports.isEmpty
                  ? requestedDataRevision != widget.host.store.dataRevision
                  : requestedTimelineData != _timelineDataIdentity()) ||
          requestedRegistry != _businessRegistry() ||
          resultReads?.contains(uiExamplesReadDependency) == true &&
              requestedExamples != _examplesRegistry() ||
          runtimeRevision !=
              PageRuntimeContextScope.read(context)?.currentRevision()) {
        dirty = true;
        return;
      }
      if (event != null &&
          result['dismissPage'] == true &&
          !widget.embedded &&
          ModalRoute.of(context)?.isCurrent == true) {
        final owner = context.findAncestorWidgetOfExactType<ModuleDetailPage>();
        if (owner != null &&
            owner.pageId == widget.pageContext['pageId'] &&
            owner.registry.ui.page(owner.pageId)?.moduleId == widget.moduleId) {
          Navigator.of(context).pop();
          return;
        }
      }
      final patch = result.containsKey('runtimeContextPatch')
          ? validateRuntimeContextPatch(result['runtimeContextPatch'])
          : const <String, Object?>{};
      readModules = resultReads;
      // Seed only the exact successful request. Rebasing to returned state or
      // newly registered forms could skip meaningful handler state transitions.
      // Live draft edits and side-effectful foreground work are never replayed.
      if (prepared == null &&
          event == null &&
          instance != null &&
          replayable &&
          resultReads != null &&
          canonicalJson(input['formValues']) == canonicalJson(formValues) &&
          canonicalJson(sentRevisions) == canonicalJson(formRevisions)) {
        dateCache.remember(
          instance,
          input,
          PreparedDatePage(result: result, reads: resultReads!),
          startedAt: startedAt,
        );
      }
      setState(() {
        for (final key in result['clearForms'] as List? ?? []) {
          if (_unchangedForm(key as String, sentForms, sentRevisions)) {
            controllers[key]?.clear();
            formValues[key] = controllers.containsKey(key) ? '' : null;
            formRevisions[key] = (formRevisions[key] ?? 0) + 1;
            inputTimers.remove(key)?.cancel();
          }
        }
        currentEvent = event;
        queryResult = result['queryResult'];
        for (final entry in object(result['replaceForms'] ?? {}).entries) {
          if (_unchangedForm(entry.key, sentForms, sentRevisions)) {
            final controller = controllers[entry.key];
            final nextText = '${entry.value ?? ''}';
            // An echoed value is not a new edit. Reassigning controller.text
            // would reset the caret and interrupt an active IME composition.
            if (controller != null && controller.text != nextText) {
              final previous = controller.value;
              final selection = previous.selection.isValid
                  ? previous.selection.copyWith(
                      baseOffset: previous.selection.baseOffset.clamp(
                        0,
                        nextText.length,
                      ),
                      extentOffset: previous.selection.extentOffset.clamp(
                        0,
                        nextText.length,
                      ),
                    )
                  : TextSelection.collapsed(offset: nextText.length);
              final composing = previous.composing;
              final retainComposing =
                  composing.isValid &&
                  composing.isNormalized &&
                  !composing.isCollapsed &&
                  composing.end <= previous.text.length &&
                  composing.end <= nextText.length &&
                  composing.textInside(previous.text) ==
                      composing.textInside(nextText);
              controller.value = TextEditingValue(
                text: nextText,
                selection: selection,
                composing: retainComposing ? composing : TextRange.empty,
              );
            }
            formValues[entry.key] = entry.value;
            formRevisions[entry.key] = (formRevisions[entry.key] ?? 0) + 1;
            inputTimers.remove(entry.key)?.cancel();
          }
        }
        final nextState = _timelineViewports.isEmpty
            ? object(result['state'] ?? state)
            : Map<String, Object?>.of(object(result['state'] ?? state));
        final nextTree = object(result['tree']);
        _retainPlannerViewport(nextState, nextTree, event, requestedViewports);
        state = nextState;
        if (state['moveIntent'] == null) _retryPlannerMove = null;
        _pendingPlannerAdjustment = null;
        tree = nextTree;
        _inlinePlanPreview = _readInlinePlanPreview();
        treeContextIdentity = canonicalJson({...requestContext, ...patch});
        renderedInstance = instance;
        renderedHeader = result['header'] is Map
            ? object(result['header'])
            : null;
        error = null;
      });
      if (_hasDateNavigation(tree)) readiness?.allowContextChanges();
      final todayDate = _declaredTodayDate(tree);
      if (todayDate != null) runtimeScope?.reportTodayDate?.call(todayDate);
      if (patch.isNotEmpty) {
        if (runtimeScope != null) {
          if (patch.entries.any(
            (entry) => requestContext[entry.key] != entry.value,
          )) {
            readiness?.allowContextChanges();
          }
          runtimeScope.update(patch);
        } else if (patch.entries.any(
          (entry) => pageContext[entry.key] != entry.value,
        )) {
          localRuntimeContext = Map.unmodifiable({
            ...localRuntimeContext,
            ...patch,
          });
          dirty = true;
        }
      }
      if (ownsHeader &&
          (routeActive ||
              headerScope!.controller.isMenuOpenFor(headerLease, this))) {
        headerScope!.controller.publish(
          headerLease!,
          this,
          _hostHeader,
          _renderHeaderEvent,
        );
      }
    } catch (e) {
      if (mounted && current == epoch) {
        headerController?.clear(this);
        setState(() => error = scriptErrorMessage(e));
      }
    } finally {
      if (mounted && current == epoch) {
        progressTimer?.cancel();
        setState(() {
          busy = false;
          showProgress = false;
          _pendingPlannerAdjustment = null;
        });
        if (dirty) {
          dirty = false;
          final next = _takePendingEvent();
          unawaited(_render(next));
        } else {
          readiness?.complete(this);
          firstFrameReadiness?.complete(this);
          _prepareAdjacentDates();
        }
        refreshTimer?.cancel();
        refreshTimer = Timer(const Duration(minutes: 1), () => _render());
      }
      finished.complete();
    }
  }

  void _queueEvent(Object event) {
    pendingEvent = event;
    pendingEventContext = canonicalJson(pageContext);
    pendingEventRuntimeRevision = PageRuntimeContextScope.read(context)
        ?.currentRevision();
    pendingEventDateIntent = dateIntentRevision;
  }

  Object? _takePendingEvent() {
    final next =
        pendingEventContext == canonicalJson(pageContext) &&
            pendingEventRuntimeRevision ==
                PageRuntimeContextScope.read(context)?.currentRevision() &&
            pendingEventDateIntent == dateIntentRevision
        ? pendingEvent
        : null;
    pendingEvent = null;
    pendingEventContext = null;
    pendingEventRuntimeRevision = null;
    pendingEventDateIntent = null;
    return next;
  }

  bool _unchangedForm(
    String key,
    Map<String, Object?> sent,
    Map<String, int> revisions,
  ) =>
      (formRevisions[key] ?? 0) == (revisions[key] ?? 0) &&
      canonicalJson(formValues[key]) == canonicalJson(sent[key]);

  void _cacheFormValues() {
    final config = tree?['formCache'];
    if (config == null) return;
    final host = widget.host;
    final instance = host.instances[widget.moduleId];
    final identity = canonicalJson(pageContext);
    final revision = ++_formCacheRevision;
    bool current() =>
        mounted &&
        revision == _formCacheRevision &&
        identical(instance, widget.host.instances[widget.moduleId]) &&
        identity == canonicalJson(pageContext);
    void report({required bool failed}) {
      if (current()) {
        setState(() {
          _formCacheError = failed ? '草稿未保存，请保留当前页面并重试。' : null;
        });
      }
    }

    try {
      if (config is! Map ||
          config['preferenceKey'] is! String ||
          config['fields'] is! List ||
          (config['fields'] as List).isEmpty ||
          (config['fields'] as List).length > 64 ||
          (config['fields'] as List).any(
            (field) => field is! String || field.isEmpty,
          ) ||
          instance == null ||
          !instance.actor.permissions.contains('ui')) {
        report(failed: true);
        return;
      }
      final values = freezeJson({
        for (final field in config['fields'] as List)
          if (formValues.containsKey(field)) field as String: formValues[field],
      });
      // Start the transaction now, before the input debounce or route disposal.
      // Keep every pending write so a subsequent module workflow can clear the
      // cache after them, without an older native write resurrecting its draft.
      final write = ModuleUiPreferences(host.store).set(
        instance.actor,
        config['preferenceKey'] as String,
        values,
        notify: false,
      );
      late final Future<void> pending;
      pending = write
          .then<void>((_) => report(failed: false))
          .catchError((Object _) => report(failed: true))
          .whenComplete(() => _formCacheWrites.remove(pending));
      _formCacheWrites.add(pending);
    } catch (_) {
      report(failed: true);
    }
  }

  void _changeForm(
    String key,
    Object? value,
    Object? event, {
    bool debounce = false,
  }) {
    setState(() {
      formValues[key] = value;
      formRevisions[key] = (formRevisions[key] ?? 0) + 1;
    });
    _cacheFormValues();
    inputTimers.remove(key)?.cancel();
    if (event == null) {
      _prepareAdjacentDates(delay: const Duration(milliseconds: 300));
      return;
    }
    final payload = {...object(event), 'value': value};
    if (debounce) {
      inputTimers[key] = Timer(const Duration(milliseconds: 150), () {
        inputTimers.remove(key);
        if (mounted) unawaited(_render(payload));
      });
    } else {
      unawaited(_render(payload));
    }
  }

  void _changeControl(Map<String, Object?> spec, Object? value, Object? event) {
    final key = spec['key'];
    if (key is String) {
      _changeForm(key, value, event);
    } else if (event != null) {
      unawaited(_render({...object(event), 'value': value}));
    }
  }

  Object? _selectionValue(String key, Map<String, Object?> spec) {
    final provided = bind(spec['value']);
    final previous = controlValues[key];
    // Accept externally changed selections, while preserving a newer local edit.
    if (spec.containsKey('value') &&
        controlValues.containsKey(key) &&
        canonicalJson(provided) != canonicalJson(previous) &&
        canonicalJson(formValues[key]) == canonicalJson(previous)) {
      formValues[key] = provided;
      if (controllers[key] case final controller?) {
        controller.text = '${provided ?? ''}';
      }
      formRevisions[key] = (formRevisions[key] ?? 0) + 1;
    }
    controlValues[key] = freezeJson(provided);
    formValues.putIfAbsent(key, () => provided);
    return formValues[key];
  }

  @override
  void dispose() {
    unawaited(_flushTimelinePreferences());
    _closePlannerUndo();
    compositionReadiness?.complete(this);
    firstFrameReadiness?.complete(this);
    headerController?.clear(this);
    if (widget.host.pageSessions.length >= 100) {
      widget.host.pageSessions.remove(widget.host.pageSessions.keys.first);
    }
    if (widget.host.instances.containsKey(widget.moduleId)) {
      widget.host.pageSessions[sessionKey] = {
        'state': Map<String, Object?>.of(state),
        'formValues': {
          ...formValues,
          for (final c in controllers.entries)
            if (formValues[c.key] != null || c.value.text.isNotEmpty)
              c.key: c.value.text,
        },
      };
    }
    epoch++;
    datePrefetchRevision++;
    datePrefetchTimer?.cancel();
    dateCache.dispose();
    progressTimer?.cancel();
    subscription?.cancel();
    registrySubscription?.cancel();
    refreshTimer?.cancel();
    for (final timer in inputTimers.values) {
      timer.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
    for (final c in controllers.values) {
      c.dispose();
    }
    for (final node in focusNodes.values) {
      node.dispose();
    }
    for (final controller in scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Object? bind(Object? raw) {
    if (raw is! Map || !raw.containsKey('bind')) return raw;
    final path = raw['bind'];
    if (path is! List || path.isEmpty) {
      throw const FormatException('Binding requires a typed path');
    }
    Object? result = {
      'state': state,
      'context': pageContext,
      'formValues': formValues,
      'queryResult': queryResult,
      'event': currentEvent,
    };
    for (final part in path) {
      if (result is Map && part is String) {
        result = result[part];
      } else if (result is List &&
          part is int &&
          part >= 0 &&
          part < result.length) {
        result = result[part];
      } else {
        return null;
      }
    }
    return result;
  }

  Future<Map<String, Object?>> _previewQuery(
    Map<String, Object?> declaration,
    Map<String, Object?> proposal,
  ) async {
    final instance = widget.host.instances[widget.moduleId];
    if (instance == null ||
        busy ||
        staleTree ||
        !routeActive ||
        !workspaceActive) {
      throw StateError('页面已变化，请重新拖动');
    }
    final requestEpoch = epoch;
    final dataRevision = widget.host.store.dataRevision;
    final contextIdentity = canonicalJson(pageContext);
    // This is deliberately a query: a preview cannot prepare or commit writes,
    // and the caller's normal service permissions still apply.
    final result = await widget.host.query(
      instance.actor,
      ServiceRef.parse(declaration['ref']),
      {...object(declaration['input'] ?? {}), 'proposal': proposal},
    );
    if (!mounted ||
        requestEpoch != epoch ||
        dataRevision != widget.host.store.dataRevision ||
        !identical(instance, widget.host.instances[widget.moduleId]) ||
        contextIdentity != canonicalJson(pageContext) ||
        !routeActive ||
        !workspaceActive) {
      throw StateError('预览依据已变化，请重新拖动');
    }
    return object(result);
  }

  Widget safeNode(Map<String, Object?> spec) {
    try {
      if (spec['template'] is String &&
          (spec['template'] as String).startsWith('ui.page.')) {
        final ref = spec['template'] as String;
        final native = node(spec);
        return UiComponent(
          ref: ref,
          fallback: native,
          slots: {ref == 'ui.page.timeGrid@1' ? 'grid' : 'content': native},
          props: {'title': spec['title']},
        );
      }
      return node(spec);
    } catch (error) {
      return Text('模块界面无效：$error');
    }
  }

  IconData? _icon(Object? value) => appIconData(value);

  Map<String, Object?> _bindValues(Map<String, Object?> values) =>
      values.map((key, value) => MapEntry(key, _bindValue(value)));
  Object? _bindValue(Object? raw) {
    if (raw is Map) {
      if (raw.containsKey('bind')) return bind(raw);
      return _bindValues(object(raw));
    }
    if (raw is List) return raw.map(_bindValue).toList();
    return raw;
  }

  Widget _slot(Object? raw, String name, String ownerKey, int depth) {
    final children = raw is List
        ? objects(raw)
        : raw is Map && raw['type'] == 'list'
        ? objects(raw['children'])
        : null;
    if (children == null) {
      return raw is Map
          ? node(object(raw), depth + 1)
          : const SizedBox.shrink();
    }
    if (name == 'items') {
      final scrollKey =
          '$ownerKey:$name:${raw is Map ? raw['scrollKey'] ?? '' : ''}';
      final controller = scrollControllers.putIfAbsent(
        scrollKey,
        ScrollController.new,
      );
      if (raw is Map && raw.containsKey('scrollRequest')) {
        final request = raw['scrollRequest'];
        if (scrollRequests[scrollKey] != request) {
          scrollRequests[scrollKey] = request;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                scrollRequests[scrollKey] == request &&
                controller.hasClients) {
              controller.jumpTo(0);
            }
          });
        }
      }
      return ListView.builder(
        key: PageStorageKey(scrollKey),
        controller: controller,
        padding: widget.settingsStyle
            ? SettingsList.contentPadding(
                bottomInset: WorkspaceContentInsets.bottomOf(uiContext),
              )
            : EdgeInsets.fromLTRB(
                16,
                8,
                16,
                WorkspaceContentInsets.bottomOf(uiContext) + 24,
              ),
        itemCount: children.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Builder(builder: (context) => node(children[i], depth + 1)),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in children)
          Builder(builder: (_) => node(child, depth + 1)),
      ],
    );
  }

  Widget componentNode(
    Map<String, Object?> spec,
    int depth, {
    bool registeredExample = false,
  }) {
    final ref = string(spec['ref'], 'UI component reference');
    final key = '${spec['key'] ?? ref}';
    if (!registeredExample && !uiContracts.containsKey(ref)) {
      final current = widget.host.instances[widget.moduleId];
      if (current == null ||
          !current.package.dependencies.any(
            (id) =>
                widget.host.instances[id]?.package.uiPack?.contracts
                    .containsKey(ref) ==
                true,
          )) {
        throw const FormatException('独有 UI 组件需要声明包依赖');
      }
    }
    final props = _bindValues(object(spec['props'] ?? {}));
    if (ref == 'ui.dayOverview@1' &&
        PageRuntimeContextScope.read(context)?.dateTodayInMenu == true) {
      props['returnToToday'] = false;
    }
    if (ref == 'ui.dayOverview@1' && pageContext['selectedDate'] is String) {
      // This control follows presentation intent immediately, while its counts
      // and other records continue to wait for the script's current query.
      props['selectedDate'] = pageContext['selectedDate'];
      if (staleTree) props['summary'] = null;
    }
    final slots = object(spec['slots'] ?? {})
        .map((name, raw) => MapEntry(name, _slot(raw, name, key, depth)));
    final events = _bindValues(object(spec['events'] ?? {}));
    final callbacks = <String, void Function(Object?)>{
      for (final entry in events.entries)
        entry.key: (value) {
          if ((!busy || ref == 'ui.dayOverview@1' && entry.key == 'change') &&
              props['disabled'] != true) {
            if (ref == 'ui.dayOverview@1' && entry.key == 'change') {
              Map<String, Object?>? patch;
              try {
                patch = validateRuntimeContextPatch({'selectedDate': value});
              } on FormatException {
                // Invalid module/UI-pack input stays within the script's render
                // error boundary, rather than throwing from a widget callback.
              }
              if (patch != null) {
                dateIntentRevision++;
                // A date choice is presentation intent. Publish it before the
                // script query returns so older responses cannot briefly rewind
                // the header, including a rapid A -> B -> A reversal.
                PageCompositionReadinessScope.read(context)
                    ?.allowContextChanges();
                PageRuntimeContextScope.read(context)?.update(patch);
              }
            }
            final event = value == null && entry.key != 'change'
                ? entry.value
                : {...object(entry.value), 'value': value};
            if (ref == 'ui.taskItem@1' && entry.key == 'change' ||
                ref == 'ui.button@1' && entry.key == 'press') {
              _commandEvent(event, spec['command']);
            } else {
              _render(event);
            }
          }
        },
    };
    // Page execution is serialized by the callbacks above. Keep buttons in
    // their declared visual state while an unrelated action is being handled.
    Widget native;
    final controlType = switch (ref) {
      'ui.input@1' => 'input',
      'ui.numberInput@1' => 'input',
      'ui.checkbox@1' => 'checkbox',
      'ui.toggle@1' => 'switch',
      'ui.select@1' => 'select',
      'ui.multiSelect@1' => 'multiSelect',
      'ui.dateInput@1' => 'dateInput',
      'ui.dateTimeInput@1' => 'dateTimeInput',
      'ui.dateRangeInput@1' => 'dateRangeInput',
      'ui.timeInput@1' => 'timeInput',
      'ui.slider@1' => 'slider',
      'ui.timeGrid@1' => 'timeGrid',
      'ui.entityRow@1' => 'listTile',
      'ui.listTile@1' => 'listTile',
      _ => null,
    };
    if (controlType != null) {
      native = node(
        {
          'type': controlType,
          ...props,
          if (ref == 'ui.numberInput@1') 'inputMode': 'number',
          'key': props['key'] ?? key,
          'text': props['label'] ?? props['title'] ?? props['text'],
          'event': events['change'] ?? events['press'] ?? events['submit'],
          if (events['change'] != null && controlType == 'input')
            'onChangeEvent': events['change'],
        },
        depth + 1,
        false,
      );
      slots.putIfAbsent('control', () => native);
    } else if (widget.settingsStyle &&
        ref == 'ui.sectionHeader@1' &&
        props['count'] == null &&
        props['subtitle'] == null &&
        props['actionLabel'] == null &&
        callbacks.isEmpty) {
      native = SettingsHeading(props['title'] as String? ?? '');
    } else {
      native = defaultUiComponent(ref, props, slots, callbacks);
    }
    return UiComponent(
      key: ValueKey(key),
      ref: ref,
      props: props,
      slots: slots,
      events: callbacks,
      fallback: native,
    );
  }

  Widget componentExample(Map<String, Object?> spec, int depth) {
    if (spec.keys.any(
      (key) => !{'type', 'key', 'providerId', 'ref', 'events'}.contains(key),
    )) {
      throw const FormatException('Registered UI samples cannot be overridden');
    }
    final providerId = string(spec['providerId'], 'UI example provider');
    final ref = string(spec['ref'], 'UI example reference');
    final pack = widget.host.instances[providerId]?.package.uiPack;
    final example = pack?.components[ref]?.example;
    if (pack == null || example == null) {
      return const Text('此界面示例的提供模块当前不可用');
    }
    final events = object(spec['events'] ?? {});
    if (events.keys.any(
      (port) => !(example['events'] as List).contains(port),
    )) {
      throw const FormatException(
        'UI example only forwards declared sample ports',
      );
    }
    final key = '${spec['key'] ?? '$providerId:$ref'}';
    return UiPackScope(
      key: ValueKey(key),
      previewPacks: {providerId: pack},
      previewSelection: UiSelection(globalPackId: providerId),
      child: Builder(
        builder: (localContext) {
          final previous = nodeContext;
          nodeContext = localContext;
          try {
            return componentNode(
              {
                'ref': ref,
                'key': key,
                'props': example['props'],
                'slots': example['slots'],
                'events': events,
              },
              depth + 1,
              registeredExample: true,
            );
          } finally {
            nodeContext = previous;
          }
        },
      ),
    );
  }

  bool _hasDateNavigation(Object? spec) {
    if (spec is Map) {
      if (spec['type'] == 'dayOverview' || spec['ref'] == 'ui.dayOverview@1') {
        return true;
      }
      return spec.values.any(_hasDateNavigation);
    }
    return spec is List && spec.any(_hasDateNavigation);
  }

  String? _declaredTodayDate(Object? spec) {
    if (spec is Map) {
      if (spec['type'] == 'dayOverview' || spec['ref'] == 'ui.dayOverview@1') {
        final raw = spec['type'] == 'dayOverview'
            ? spec['todayDate']
            : (spec['props'] as Map?)?['todayDate'];
        if (raw is String) return raw;
      }
      for (final value in spec.values) {
        final date = _declaredTodayDate(value);
        if (date != null) return date;
      }
    } else if (spec is List) {
      for (final value in spec) {
        final date = _declaredTodayDate(value);
        if (date != null) return date;
      }
    }
    return null;
  }

  Widget node(Map<String, Object?> spec, [int depth = 0, bool replace = true]) {
    final child = _node(spec, depth, replace);
    // Keep the navigation's Elements and animation alive across a date query.
    // Other branches remain mounted, but cannot display or expose old records.
    if (!retainDateNavigation || _hasDateNavigation(spec)) return child;
    return Offstage(
      key: spec['key'] == null ? null : ValueKey(spec['key']),
      offstage: staleTree,
      child: IgnorePointer(
        ignoring: dateContentBlocked,
        child: ExcludeFocus(
          excluding: dateContentBlocked,
          child: ExcludeSemantics(excluding: dateContentBlocked, child: child),
        ),
      ),
    );
  }

  Widget _pageTransition(
    Widget child, {
    String slot = 'content',
    bool fillViewport = false,
  }) {
    final raw = tree?['pageTransition'];
    if (raw == null) return child;
    if (raw is! Map) {
      return const Text('模块界面无效：页面过渡配置无效');
    }
    final direction = raw['direction'];
    final duration = raw['duration'] ?? 260;
    if (!const ['forward', 'back', 'next', 'previous'].contains(direction) ||
        duration is! int ||
        duration < 100 ||
        duration > 2000) {
      return const Text('模块界面无效：页面过渡配置无效');
    }
    return ScriptTransition(
      key: ValueKey('script-page-transition:$slot'),
      effect: 'page',
      replayKey: tree?['scrollKey'] ?? tree?['key'] ?? 'page',
      navigationDirection: direction as String,
      duration: Duration(milliseconds: duration),
      fillViewport: fillViewport,
      child: child,
    );
  }

  Widget? _retainedFooter;

  Widget _pageFooter() {
    final footer = tree?['footer'];
    final animated = tree?['pageTransition'] is Map;
    if (footer is! Map) {
      return animated ? _footerPresence(false) : const SizedBox.shrink();
    }
    final child = _inlinePlanPreview != null
        ? _inlineReviewFooter(_inlinePlanPreview!)
        : safeNode(object(footer));
    final message = tree?['footerMessage'];
    final edge = tree?['footerStyle'] == 'edge';
    final flat = edge || tree?['footerStyle'] == 'flat';
    final rendered = _pageTransition(
      Container(
        decoration: flat
            ? BoxDecoration(
                color: edge
                    ? Theme.of(context).scaffoldBackgroundColor
                    : Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant
                        .withValues(alpha: .4),
                  ),
                ),
              )
            : null,
        padding: EdgeInsets.fromLTRB(
          edge ? AppDesign.pageGutter : 16,
          edge ? 10 : 8,
          edge ? AppDesign.pageGutter : 16,
          12 + WorkspaceContentInsets.bottomOf(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message is Map)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  liveRegion: true,
                  child: safeNode(object(message)),
                ),
              ),
            footer['type'] == 'messageComposer' || flat
                ? child
                : FloatingSurface(
                    padding: const EdgeInsets.all(12),
                    child: child,
                  ),
          ],
        ),
      ),
      slot: 'footer',
    );
    if (!animated) return rendered;
    _retainedFooter = rendered;
    return _footerPresence(true);
  }

  Widget _footerPresence(bool visible) => ScriptTransition(
    key: const ValueKey('script-page-footer-presence'),
    effect: 'slide',
    visible: visible,
    collapse: true,
    duration: const Duration(milliseconds: 260),
    child: AppMotion.reduced(context)
        ? _retainedFooter ?? const SizedBox.shrink()
        : AnimatedSize(
            alignment: Alignment.bottomCenter,
            duration: AppMotion.disclosure,
            curve: AppMotion.enter,
            child: _retainedFooter ?? const SizedBox.shrink(),
          ),
  );

  Widget _pageBody(Map<String, Object?> spec) {
    final child = safeNode(spec);
    if (spec['pageTransition'] == null || AppMotion.reduced(context)) {
      return child;
    }
    return AnimatedSize(
      duration: AppMotion.duration(context, AppMotion.disclosure),
      curve: AppMotion.enter,
      alignment: Alignment.topCenter,
      child: child,
    );
  }

  double _columnGap(
    Map<String, Object?> column,
    List<Map<String, Object?>> children,
    int index,
    int depth,
  ) {
    final settings = widget.settingsStyle;
    if (index == children.length - 1 &&
        (column['trailingSpacing'] == false || settings && depth > 0)) {
      return 0;
    }
    if (settings) {
      final type = children[index]['type'];
      if (type == 'sectionHeader') return SettingsGroup.headingGap;
      if (type == 'card' || depth == 0 && type == 'column') {
        return SettingsGroup.spacing;
      }
    }
    return (column['spacing'] as num? ?? 12).toDouble().clamp(0, 48);
  }

  Widget pageContent() {
    final spec = tree!;
    final rootChildren = objects(spec['children']);
    final scrollKey = '${spec['scrollKey'] ?? 'page'}';
    final controller = scrollControllers.putIfAbsent(
      scrollKey,
      ScrollController.new,
    );
    if (spec['followEnd'] != null &&
        scrollRequests['followEnd'] != spec['followEnd']) {
      final follow =
          !controller.hasClients || controller.position.extentAfter < 80;
      scrollRequests['followEnd'] = spec['followEnd'];
      if (follow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(tree, spec) && controller.hasClients) {
            controller.jumpTo(controller.position.maxScrollExtent);
          }
        });
      }
    }
    return _pageTransition(
      LayoutBuilder(
        builder: (context, constraints) {
          final rawPanel = spec['floatingPanel'];
          final panel = rawPanel is Map ? object(rawPanel) : null;
          final bottom = WorkspaceContentInsets.bottomOf(context);
          final compact = spec['compact'] == true;
          final edgeToEdge = spec['edgeToEdge'] == true;
          final horizontal = compact ? 16.0 : AppDesign.pageGutter;
          final scrollPadding = widget.settingsStyle
              ? SettingsList.contentPadding(
                  edgeToEdge: edgeToEdge,
                  bottomInset: bottom,
                )
              : EdgeInsets.fromLTRB(
                  edgeToEdge ? 0 : horizontal,
                  edgeToEdge
                      ? 0
                      : compact
                      ? 8
                      : 16,
                  edgeToEdge ? 0 : horizontal,
                  16 + bottom,
                );
          final top = ((panel?['top'] as num?) ?? 16)
              .toDouble()
              .clamp(0, constraints.maxHeight * .25)
              .toDouble();
          return Stack(
            children: [
              Positioned.fill(
                child:
                    spec['fillHeight'] == true ||
                        spec['type'] == 'keyedList' ||
                        spec['type'] == 'component' &&
                            (spec['ref'] as String? ?? '').startsWith(
                              'ui.page.',
                            )
                    ? Padding(
                        padding: EdgeInsets.only(
                          bottom:
                              spec['underlapChrome'] == true ||
                                  spec['type'] == 'keyedList'
                              ? 0
                              : bottom,
                        ),
                        child: safeNode(spec),
                      )
                    : spec['type'] == 'column' &&
                          spec['template'] == null &&
                          rootChildren.length > 50
                    ? ListView.builder(
                        key: PageStorageKey(scrollKey),
                        controller: controller,
                        padding: scrollPadding,
                        itemCount: rootChildren.length,
                        itemBuilder: (context, i) {
                          final child = rootChildren[i];
                          return Padding(
                            key: child['key'] == null
                                ? null
                                : ValueKey(child['key']),
                            padding: EdgeInsets.only(
                              bottom: _columnGap(spec, rootChildren, i, 0),
                            ),
                            child: node(child, 1),
                          );
                        },
                      )
                    : SingleChildScrollView(
                        key: PageStorageKey(scrollKey),
                        controller: controller,
                        padding: scrollPadding,
                        child: _pageBody(spec),
                      ),
              ),
              if (panel != null)
                DraggableFloatingPanel(
                  key: ValueKey(('script-floating-panel', panel['key'])),
                  viewport: constraints.biggest,
                  bottomInset: bottom,
                  initialTop: top,
                  title: '${panel['title'] ?? ''}',
                  closeLabel: '${panel['closeLabel'] ?? '关闭面板'}',
                  onClose: busy ? null : () => _render(panel['closeEvent']),
                  child: safeNode(object(panel['child'])),
                ),
            ],
          );
        },
      ),
      fillViewport: true,
    );
  }

  @override
  Widget build(BuildContext context) => UiPackScope(
    moduleId: widget.moduleId,
    child: ScriptUiScope(
      active: routeActive && workspaceActive && !staleTree,
      busy: busy,
      child: Builder(
        builder: (context) {
          nodeContext = context;
          dateContentBlocked =
              DateRevealScope.of(context)?.isTransitioning == true;
          retainDateNavigation = _hasDateNavigation(tree);
          // Inline compositions provide one shared progress indicator.
          final loading =
              busy &&
              showProgress &&
              routeActive &&
              compositionReadiness == null &&
              _pendingPlannerAdjustment == null;
          final contextController =
              compositionReadiness?.controller.contextControllers.contains(
                compositionReadiness!.memberId,
              ) ==
              true;
          final currentTree =
              tree != null &&
              (treeContextIdentity == canonicalJson(pageContext) ||
                  contextController ||
                  retainDateNavigation);
          final headerLease = WorkspaceHeaderScope.read(context)?.lease;
          final hasNativeHeader =
              headerLease?.mode == 'contributed' &&
              headerLease?.moduleId == widget.moduleId &&
              headerLease?.pageId == widget.pageContext['pageId'];
          final content = Column(
            mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
            children: [
              // A modal is waiting for user input; only the active page shows
              // render progress. Keep busy for serialization and disabled inputs.
              if (loading && currentTree)
                const LinearProgressIndicator(minHeight: 2),
              if (error != null)
                MaterialBanner(
                  content: Text(error!),
                  actions: [
                    TextButton(
                      onPressed: () => _render(),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              if (_formCacheError != null)
                MaterialBanner(
                  content: Text(_formCacheError!),
                  actions: [
                    TextButton(
                      onPressed: _cacheFormValues,
                      child: const Text('重试保存'),
                    ),
                  ],
                ),
              if (!widget.embedded && currentTree && tree?['header'] is Map)
                safeNode(object(tree!['header'])),
              if (!widget.embedded &&
                  currentTree &&
                  _hasQuickAdjustHeader &&
                  !hasNativeHeader)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDesign.pageGutter,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: WorkspaceHeaderAction(
                        key: const ValueKey('planner-standalone-quick-adjust'),
                        action: _quickAdjustHeaderAction,
                        compact: true,
                        onPressed: () => _setQuickAdjust(!_quickAdjust),
                      ),
                    ),
                  ),
                ),
              if (widget.embedded)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppDesign.pageGutter,
                    vertical: tree?['compact'] == true ? 4 : 12,
                  ),
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      Offstage(
                        offstage: !currentTree,
                        child: tree == null
                            ? const SizedBox.shrink()
                            : safeNode(tree!),
                      ),
                      if (!currentTree && loading)
                        const PageLoadingPlaceholder(),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Offstage(
                        offstage: !currentTree,
                        child: tree == null
                            ? const SizedBox.shrink()
                            : pageContent(),
                      ),
                      if (!currentTree && loading)
                        const Align(
                          alignment: Alignment.topCenter,
                          child: PageLoadingPlaceholder(),
                        ),
                    ],
                  ),
                ),
              if (tree?['footer'] is Map || tree?['pageTransition'] is Map)
                Offstage(offstage: !currentTree, child: _pageFooter()),
            ],
          );
          return IgnorePointer(
            ignoring: dateContentBlocked && !retainDateNavigation,
            child: ExcludeFocus(
              excluding: dateContentBlocked && !retainDateNavigation,
              child: ExcludeSemantics(
                excluding: dateContentBlocked && !retainDateNavigation,
                child: content,
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _InlinePlanPreview {
  const _InlinePlanPreview(
    this.plan,
    this.summary,
    this.eventType,
    this.buttons,
  );
  final ChangePlan plan;
  final DataChangeSummary summary;
  final String eventType;
  final List<Map<String, Object?>> buttons;
}
