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
import '../ui/workspace_header_action.dart';
import '../ui/workspace_typography.dart';
import '../ui/ui_component.dart';
import '../ui/ui_pack.dart';
import '../ui/temporal_input.dart';
import '../ui/script_transition.dart';
import '../ui/time_range_table.dart';
import '../ui/conversation_widgets.dart';
import '../ui/native_ui.dart';
import '../ui/script_keyed_list.dart';
import '../ui/draggable_floating_panel.dart';
import '../../app/app_ui_feedback.dart';
import '../../app/app_motion.dart';
import '../ui/responsive_content_grid.dart';
import '../ui/input_validation.dart';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:xquickjs/error_message.dart';

import '../../app/design_system.dart';
import 'module_host.dart';
import 'module_package.dart';
import 'time_grid.dart';
import 'planner_board.dart';
import 'planner_quick_adjust.dart';
import 'collection_store.dart';
import 'data_change_review.dart';
import 'inline_plan_review.dart';

class ScriptPage extends StatefulWidget {
  const ScriptPage({
    super.key,
    required this.host,
    required this.moduleId,
    required this.handler,
    this.pageContext = const {},
    this.embedded = false,
  });
  final ModuleHost host;
  final String moduleId, handler;
  final Map<String, Object?> pageContext;
  final bool embedded;
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
  final _plannerApprovals = Expando<PlannerQuickAdjustment>(
    'native planner gesture',
  );
  final _inlineApprovals = Expando<InlinePlanApproval>(
    'native plan confirmation',
  );
  _InlinePlanPreview? _inlinePlanPreview;

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
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (context) => UiPackScope(
                    defaultOnly: true,
                    child: NativeUi(
                      child: SafeArea(
                        child: SizedBox(
                          height: MediaQuery.sizeOf(context).height * .65,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: DataChangeReview(summary: preview.summary),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
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
  BoardItem? _quickAdjustmentConfig(BoardItem spec) {
    final config = spec['quickAdjustment'];
    if (config is! Map ||
        !['taskModuleId', 'applyServiceId', 'undoServiceId'].every(
          (key) => config[key] is String && (config[key] as String).isNotEmpty,
        )) {
      return null;
    }
    return object(config);
  }

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
      _plannerApprovals[event] = PlannerQuickAdjustment.move(
        object(event),
        moduleId: widget.moduleId,
        taskModuleId: quickConfig['taskModuleId'] as String,
        applyServiceId: quickConfig['applyServiceId'] as String,
        undoServiceId: quickConfig['undoServiceId'] as String,
      );
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
            _plannerApprovals[event] = undo;
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
      showProgress = false;
    });
    // Fast renders and opening a chooser should not flash a loading indicator.
    _delayProgress(current);
    final sentForms = Map<String, Object?>.of(formValues);
    final sentRevisions = Map<String, int>.of(formRevisions);
    final adjustment = event is Map ? _plannerApprovals[event] : null;
    final inlineApproval = event is Map ? _inlineApprovals[event] : null;
    String? approvedPlanId;
    try {
      final input = freezeJson(<String, Object?>{
        'state': state,
        'context': requestContext,
        'event': event,
        'formValues': sentForms,
      }) as Map<String, Object?>;
      _checkDateCacheRevision();
      final requestedDataRevision = widget.host.store.dataRevision;
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
              onReview: adjustment != null
                  ? (reference, preparedInput, plan, confirmation) {
                      if (reference.major != 1 ||
                          !mounted ||
                          !routeActive ||
                          !workspaceActive ||
                          !identical(
                            instance,
                            widget.host.instances[widget.moduleId],
                          )) {
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
              requestedDataRevision != widget.host.store.dataRevision ||
          requestedRegistry != _businessRegistry() ||
          resultReads?.contains(uiExamplesReadDependency) == true &&
              requestedExamples != _examplesRegistry() ||
          runtimeRevision !=
              PageRuntimeContextScope.read(context)?.currentRevision()) {
        dirty = true;
        return;
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
            controllers[entry.key]?.text = '${entry.value ?? ''}';
            formValues[entry.key] = entry.value;
            formRevisions[entry.key] = (formRevisions[entry.key] ?? 0) + 1;
            inputTimers.remove(entry.key)?.cancel();
          }
        }
        state = object(result['state'] ?? state);
        if (state['moveIntent'] == null) _retryPlannerMove = null;
        _pendingPlannerAdjustment = null;
        tree = object(result['tree']);
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
        padding: EdgeInsets.fromLTRB(
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
            _render(
              value == null && entry.key != 'change'
                  ? entry.value
                  : {...object(entry.value), 'value': value},
            );
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

  Widget _node(Map<String, Object?> spec, int depth, bool replace) {
    if (depth > 32) return const Text('组件嵌套超过限制');
    if (spec['type'] == 'component') return componentNode(spec, depth);
    if (spec['type'] == 'componentExample') {
      return componentExample(spec, depth);
    }
    final dailyRef = switch (spec['type']) {
      'dayOverview' => 'ui.dayOverview@1',
      'sectionHeader' => 'ui.sectionHeader@1',
      'agendaItem' => 'ui.agendaItem@1',
      'taskItem' => 'ui.taskItem@1',
      _ => null,
    };
    if (dailyRef != null) {
      final event = bind(spec['event']);
      final action = spec['action'] is Map ? object(spec['action']) : null;
      return componentNode({
        'ref': dailyRef,
        'key':
            spec['key'] ?? '$dailyRef:${spec['title'] ?? spec['date'] ?? ''}',
        'props': {
          for (final entry in spec.entries)
            if (!const {
              'type',
              'key',
              'event',
              'openEvent',
              'children',
              'action',
            }.contains(entry.key))
              entry.key: entry.value,
          if (action != null) 'actionLabel': action['label'],
          if (action != null) 'actionIcon': action['icon'],
        },
        'slots': {
          if (spec['children'] != null)
            'details': {'type': 'column', 'children': spec['children']},
        },
        'events': {
          if (action?['event'] != null)
            'press': action!['event']
          else if (event != null &&
              !{'taskItem', 'dayOverview'}.contains(spec['type']))
            'press': event,
          if ({'taskItem', 'dayOverview'}.contains(spec['type']) &&
              event != null)
            'change': event,
          if (spec['openEvent'] != null) 'open': spec['openEvent'],
        },
      }, depth);
    }
    if (replace) {
      final ref = switch (spec['type']) {
        'button' => 'ui.button@1',
        'card' => 'ui.card@1',
        'text' => 'ui.text@1',
        'listTile' => 'ui.listTile@1',
        'checkbox' => 'ui.checkbox@1',
        'switch' => 'ui.toggle@1',
        'select' => 'ui.select@1',
        'input' => 'ui.input@1',
        'multiSelect' => 'ui.multiSelect@1',
        'dateInput' => 'ui.dateInput@1',
        'dateTimeInput' => 'ui.dateTimeInput@1',
        'dateRangeInput' => 'ui.dateRangeInput@1',
        'timeInput' => 'ui.timeInput@1',
        'timeGrid' => 'ui.timeGrid@1',
        'divider' => 'ui.divider@1',
        'spinner' => 'ui.loading@1',
        'progress' => 'ui.progress@1',
        'tabs' => 'ui.tabs@1',
        'slider' => 'ui.slider@1',
        _ => null,
      };
      if (ref != null) {
        final native = node(spec, depth, false);
        return UiComponent(
          key: spec['key'] == null ? null : ValueKey('${spec['key']}'),
          ref: ref,
          fallback: native,
          props: {
            ..._bindValues({
              for (final key in [
                'text',
                'title',
                'subtitle',
                'value',
                'style',
                'variant',
                'min',
                'max',
              ])
                if (spec.containsKey(key)) key: spec[key],
            }),
            'label': bind(spec['title']) ?? bind(spec['text']),
            'disabled':
                (busy &&
                    spec['type'] != 'button' &&
                    spec['interrupt'] is! String) ||
                bind(spec['disabled']) == true,
          },
          slots: {'control': native, 'content': native},
          events: {
            'press': (_) {
              if (spec['interrupt'] is String) {
                widget.host.invokeInterrupt(
                  widget.moduleId,
                  spec['interrupt'] as String,
                );
              } else if (!busy && bind(spec['disabled']) != true) {
                _render(bind(spec['event']));
              }
            },
          },
        );
      }
    }
    if (spec['type'] == 'keyedList') {
      final items = objects(spec['children']);
      final keys = items.map((item) => item['key']).toList();
      final scope = bind(spec['scope']);
      final feedbackKey = bind(spec['feedbackKey']);
      final removeKeys = bind(spec['removeKeys']) ?? const [];
      final highlightKeys = bind(spec['highlightKeys']) ?? const [];
      final duration = bind(spec['duration']) ?? 220;
      final spacing = bind(spec['spacing']) ?? 12;
      if (scope is! String ||
          keys.any((key) => key is! String || key.isEmpty) ||
          keys.toSet().length != keys.length ||
          feedbackKey != null &&
              feedbackKey is! String &&
              feedbackKey is! num ||
          feedbackKey is num && !feedbackKey.isFinite ||
          removeKeys is! List ||
          removeKeys.any((key) => key is! String) ||
          highlightKeys is! List ||
          highlightKeys.any((key) => key is! String) ||
          duration is! num ||
          !duration.isFinite ||
          duration != duration.roundToDouble() ||
          duration < 100 ||
          duration > 2000 ||
          spacing is! num ||
          !spacing.isFinite ||
          spacing < 0 ||
          spacing > 48) {
        throw const FormatException('Invalid keyedList node');
      }
      final scrolling = depth == 0 && !widget.embedded;
      return ScriptKeyedList(
        key: spec['key'] == null ? null : ValueKey('${spec['key']}'),
        scope: scope,
        feedbackKey: feedbackKey,
        removeKeys: removeKeys.cast<String>().toSet(),
        highlightKeys: highlightKeys.cast<String>().toSet(),
        duration: Duration(milliseconds: duration.toInt()),
        spacing: spacing.toDouble(),
        scrollController: scrolling
            ? scrollControllers.putIfAbsent('page', ScrollController.new)
            : null,
        padding: scrolling
            ? EdgeInsets.fromLTRB(
                spec['edgeToEdge'] == true ? 0 : 20,
                spec['edgeToEdge'] == true ? 0 : 16,
                spec['edgeToEdge'] == true ? 0 : 20,
                16 + WorkspaceContentInsets.bottomOf(uiContext),
              )
            : EdgeInsets.zero,
        items: [
          for (final item in items)
            ScriptListItem(
              id: item['key'] as String,
              builder: (context) {
                final previous = nodeContext;
                nodeContext = context;
                try {
                  return node(item, depth + 1);
                } catch (error) {
                  return Text('模块界面无效：$error');
                } finally {
                  nodeContext = previous;
                }
              },
            ),
        ],
      );
    }
    final children = objects(spec['children'])
        .map((n) => node(n, depth + 1))
        .toList();
    final text = '${bind(spec['text']) ?? ''}';
    final event = bind(spec['event']);
    switch (spec['type']) {
      case 'pageHeader':
        return NativeUi(
          ref: 'ui.chrome.pageHeader@1',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${bind(spec['title']) ?? ''}',
                        style: Theme.of(uiContext).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (spec['subtitle'] != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${bind(spec['subtitle'])}',
                          style: Theme.of(uiContext).textTheme.bodySmall
                              ?.copyWith(color: AppDesign.muted(uiContext)),
                        ),
                      ],
                    ],
                  ),
                ),
                for (final action in objects(spec['actions']))
                  NativeUi(
                    child: IconButton(
                      tooltip: '${action['label'] ?? ''}',
                      onPressed: busy || action['disabled'] == true
                          ? null
                          : () => _render(action['event']),
                      icon: UiIcon(_icon(action['icon'])),
                    ),
                  ),
              ],
            ),
          ),
        );
      case 'chatMessage':
        final message = ConversationMessage(
          text: text,
          outgoing: spec['role'] == 'user',
          label: '${spec['label'] ?? ''}',
        );
        return UiComponent(
          ref: 'ui.nativeSection@1',
          props: {'title': '${spec['label'] ?? ''}'},
          slots: {'content': message},
          fallback: message,
        );
      case 'messageComposer':
        final key = spec['key'] as String;
        final controller = controllers.putIfAbsent(
          key,
          () => TextEditingController(text: '${formValues[key] ?? ''}'),
        );
        return ConversationComposer(
          controller: controller,
          focusNode: focusNodes.putIfAbsent(key, FocusNode.new),
          hint: text,
          busy: busy,
          enabled: bind(spec['disabled']) != true,
          onChanged: (value) => _changeForm(key, value, null),
          onSend: () {
            if (!busy) _render(event);
          },
          onCancel: spec['interrupt'] is String
              ? () => widget.host.invokeInterrupt(
                  widget.moduleId,
                  spec['interrupt'] as String,
                )
              : null,
        );
      case 'transition':
        final effect = bind(spec['effect']) ?? 'fade';
        final visible = spec['visible'] == null ? true : bind(spec['visible']);
        final duration =
            bind(spec['duration']) ??
            (effect == 'page'
                    ? AppMotion.pageTransition
                    : AppMotion.scriptTransition)
                .inMilliseconds;
        final collapse = spec['collapse'] == null
            ? false
            : bind(spec['collapse']);
        final replayKey = bind(spec['replayKey']);
        final direction = bind(spec['direction']);
        if (!const ['fade', 'scale', 'slide', 'page'].contains(effect) ||
            visible is! bool ||
            collapse is! bool ||
            duration is! num ||
            !duration.isFinite ||
            duration != duration.roundToDouble() ||
            duration < 100 ||
            duration > 2000 ||
            replayKey != null && replayKey is! String && replayKey is! num ||
            replayKey is num && !replayKey.isFinite ||
            direction != null &&
                (effect != 'page' ||
                    visible != true ||
                    collapse != false ||
                    !const ['forward', 'back'].contains(direction)) ||
            spec['child'] is! Map) {
          throw const FormatException('Invalid transition node');
        }
        return ScriptTransition(
          key: spec['key'] == null ? null : ValueKey('${spec['key']}'),
          effect: effect as String,
          visible: visible,
          collapse: collapse,
          replayKey: replayKey,
          navigationDirection: direction as String?,
          duration: Duration(milliseconds: duration.toInt()),
          child: node(object(spec['child']), depth + 1),
        );
      case 'column':
        final keyCounts = <Key, int>{};
        for (final child in children) {
          final key = child.key;
          if (key != null) keyCounts[key] = (keyCounts[key] ?? 0) + 1;
        }
        return Column(
          key: spec['key'] == null ? null : ValueKey('${spec['key']}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++)
              if (spec['fillHeight'] == true && i == children.length - 1)
                Expanded(
                  key: keyCounts[children[i].key] == 1 ? children[i].key : null,
                  child: children[i],
                )
              else
                Padding(
                  // Keys must own the sibling element, not only its inner
                  // control, when rows are inserted before a focused input.
                  key: keyCounts[children[i].key] == 1 ? children[i].key : null,
                  padding: EdgeInsets.only(
                    bottom: (spec['spacing'] as num? ?? 12).toDouble().clamp(
                      0,
                      48,
                    ),
                  ),
                  child: children[i],
                ),
          ],
        );
      case 'row':
        if (spec['layout'] == 'flex') {
          final specifications = objects(spec['children']);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                if (specifications[i]['flex'] is num &&
                    (specifications[i]['flex'] as num) > 0)
                  Expanded(
                    flex: (specifications[i]['flex'] as num).toInt().clamp(
                      1,
                      10,
                    ),
                    child: children[i],
                  )
                else
                  children[i],
              ],
            ],
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        );
      case 'grid':
        return ResponsiveContentGrid(children: children);
      case 'inset':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );
      case 'disclosure':
        final rounded = AppDesign.smoothShape();
        return ExpansionTile(
          key: PageStorageKey(spec['key'] ?? text),
          title: Text(text),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: rounded,
          collapsedShape: rounded,
          clipBehavior: Clip.antiAlias,
          backgroundColor: Theme.of(uiContext).colorScheme.surfaceContainerLow,
          children: children,
        );
      case 'card':
        return ContentSurface(
          child: Padding(
            padding: EdgeInsets.all(tree?['compact'] == true ? 8 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        );
      case 'text':
        return Text(
          text,
          style: spec['style'] == 'title'
              ? Theme.of(uiContext).textTheme.titleLarge
              : spec['style'] == 'heading'
              ? Theme.of(uiContext).textTheme.titleMedium
              : spec['style'] == 'muted'
              ? Theme.of(uiContext).textTheme.bodySmall?.copyWith(
                  color: Theme.of(uiContext).colorScheme.onSurfaceVariant,
                )
              : null,
        );
      case 'richText':
        return SelectableText(
          key: PageStorageKey(('richText', spec['key'] ?? text)),
          text,
        );
      case 'listTile':
        final icon = _icon(spec['icon']);
        final subtitle = bind(spec['subtitle']);
        final trailing = bind(spec['trailing']);
        final enabled = !busy && bind(spec['disabled']) != true;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          dense: tree?['compact'] == true,
          visualDensity: tree?['compact'] == true
              ? const VisualDensity(vertical: -2)
              : null,
          titleTextStyle: tree?['compact'] == true
              ? Theme.of(uiContext).textTheme.bodyMedium
              : null,
          subtitleTextStyle: tree?['compact'] == true
              ? Theme.of(uiContext).textTheme.bodySmall
                    ?.copyWith(color: AppDesign.muted(uiContext))
              : null,
          leading: icon == null ? null : UiIcon(icon),
          title: Text('${bind(spec['title']) ?? text}'),
          subtitle: subtitle == null ? null : Text('$subtitle'),
          trailing: trailing == false
              ? null
              : trailing is String
              ? Text(trailing)
              : event == null
              ? null
              : const UiIcon(Icons.chevron_right),
          enabled: enabled,
          onTap: event == null || !enabled ? null : () => _render(event),
        );
      case 'source':
        return ExpansionTile(
          title: const Text('查看文件内容'),
          children: [
            SelectableText(
              key: PageStorageKey(('sourceText', spec['key'] ?? text)),
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        );
      case 'button':
        final press = spec['interrupt'] is String
            ? () => widget.host.invokeInterrupt(
                widget.moduleId,
                spec['interrupt'] as String,
              )
            : bind(spec['disabled']) == true
            ? null
            : () {
                if (!busy) _render(event);
              };
        return switch (spec['variant']) {
          'text' => TextButton(
            style: appUiButtonStyle,
            onPressed: press,
            child: Text(text),
          ),
          'outlined' => OutlinedButton(
            style: appUiButtonStyle,
            onPressed: press,
            child: Text(text),
          ),
          'filled' => FilledButton(
            style: appUiButtonStyle,
            onPressed: press,
            child: Text(text),
          ),
          _ => FilledButton.tonal(
            style: appUiButtonStyle,
            onPressed: press,
            child: Text(text),
          ),
        };
      case 'toolbar':
        Widget action(Map<String, Object?> value) => IconButton(
          tooltip: '${value['label'] ?? ''}',
          onPressed: busy || value['disabled'] == true
              ? null
              : () => _render(value['event']),
          icon: UiIcon(switch (value['icon']) {
            'swap' => Icons.swap_horiz,
            'chevron_left' => Icons.chevron_left,
            'chevron_right' => Icons.chevron_right,
            'today' => Icons.today_outlined,
            'settings' => Icons.tune,
            _ => Icons.more_horiz,
          }),
        );
        final sideActions = objects(spec['actions']);
        final trailing = spec['trailing'] is Map
            ? object(spec['trailing'])
            : null;
        final sideWidth =
            (48.0 * (sideActions.length + (trailing == null ? 0 : 1)))
                .clamp(48, 192)
                .toDouble();
        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: Material(
            color: Theme.of(uiContext).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: sideWidth,
                    child: spec['leading'] is Map
                        ? action(object(spec['leading']))
                        : null,
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: busy || event == null
                          ? null
                          : () => _render(event),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${bind(spec['title']) ?? text}',
                              textAlign: TextAlign.center,
                              maxLines: WorkspaceTypography.titleMaxLines,
                              overflow: TextOverflow.ellipsis,
                              style: WorkspaceTypography.titleStyle(
                                Theme.of(uiContext).textTheme,
                              ),
                            ),
                            if (spec['subtitle'] != null)
                              Text(
                                '${bind(spec['subtitle'])}',
                                style: Theme.of(uiContext).textTheme.labelSmall,
                              ),
                            if (event != null)
                              const UiIcon(Icons.arrow_drop_down, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: sideWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (final item in sideActions) action(item),
                        if (trailing != null) action(trailing),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case 'checkbox':
        return CheckboxListTile(
          value: bind(spec['value']) == true,
          title: Text(text),
          onChanged: busy || bind(spec['disabled']) == true
              ? null
              : (v) => _changeControl(spec, v, event),
        );
      case 'switch':
        return SwitchListTile(
          title: Text(text),
          value: bind(spec['value']) == true,
          onChanged: busy || bind(spec['disabled']) == true
              ? null
              : (value) => _changeControl(spec, value, event),
        );
      case 'select':
        final items = objects(spec['items']);
        final value = bind(spec['value']);
        return DropdownButtonFormField<Object>(
          borderRadius: AppDesign.selectionBorderRadius,
          key: ValueKey('${spec['key']}:$value'),
          initialValue: items.any((item) => item['value'] == value)
              ? value
              : null,
          decoration: InputDecoration(labelText: text),
          isExpanded: true,
          items: [
            for (final item in items)
              DropdownMenuItem(
                value: item['value'],
                child: Text(
                  '${item['label']}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: busy || bind(spec['disabled']) == true
              ? null
              : (value) => _changeControl(spec, value, event),
        );
      case 'multiSelect':
        final key = string(spec['key'], 'multi-select key');
        final selected = (_selectionValue(key, spec) as List? ?? []).toSet();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: Theme.of(uiContext).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in objects(spec['items'] ?? spec['options']))
                  FilterChip(
                    showCheckmark: false,
                    shape: const StadiumBorder(),
                    label: Text('${item['label']}'),
                    selected: selected.contains(item['value']),
                    onSelected: busy || bind(spec['disabled']) == true
                        ? null
                        : (checked) {
                            final next = {...selected};
                            if (checked) {
                              next.add(item['value']);
                            } else {
                              next.remove(item['value']);
                            }
                            _changeForm(key, next.toList(), event);
                          },
                  ),
              ],
            ),
          ],
        );
      case 'slider':
        final min = (spec['min'] as num? ?? 0).toDouble(),
            max = (spec['max'] as num? ?? 1).toDouble();
        return AppSlider(
          value: (bind(spec['value']) as num? ?? min).toDouble().clamp(
            min,
            max,
          ),
          min: min,
          max: max,
          divisions: (spec['divisions'] as num?)?.toInt(),
          semanticFormatterCallback: (value) => '$text $value',
          onChanged: busy || bind(spec['disabled']) == true
              ? null
              : (value) => _changeControl(spec, value, event),
        );
      case 'progress':
        return AppProgressIndicator(
          value: spec['value'] == null
              ? null
              : (bind(spec['value']) as num).toDouble().clamp(0, 1),
        );
      case 'spinner':
        return const Center(child: CircularProgressIndicator());
      case 'list':
        return Column(children: children);
      case 'tabs':
        final tabs = <Widget>[
          for (final entry in objects(spec['items']).asMap().entries)
            if (spec['selectedIndex'] != null)
              ChoiceChip(
                showCheckmark: false,
                shape: const StadiumBorder(),
                label: Text('${entry.value['label']}'),
                selected: bind(spec['selectedIndex']) == entry.key,
                onSelected: busy || bind(spec['disabled']) == true
                    ? null
                    : (_) =>
                          _changeControl(spec, entry.key, entry.value['event']),
              )
            else
              TextButton(
                onPressed: busy ? null : () => _render(entry.value['event']),
                child: Text('${entry.value['label']}'),
              ),
        ];
        if (spec['scrollable'] == true) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tab in tabs)
                  Padding(padding: const EdgeInsets.only(right: 8), child: tab),
              ],
            ),
          );
        }
        return Wrap(spacing: 8, runSpacing: 8, children: tabs);
      case 'input':
      case 'sourceEditor':
        final key = string(spec['key'], 'input key');
        final controller = controllers.putIfAbsent(key, () {
          final initial = '${formValues[key] ?? bind(spec['value']) ?? ''}';
          formValues.putIfAbsent(key, () => initial);
          return TextEditingController(text: initial);
        });
        return TextField(
          controller: controller,
          focusNode: focusNodes.putIfAbsent(key, FocusNode.new),
          enabled: bind(spec['disabled']) != true,
          keyboardType: spec['inputMode'] == 'number'
              ? TextInputType.numberWithOptions(
                  decimal: spec['integer'] != true,
                  signed: true,
                )
              : spec['inputMode'] == 'search'
              ? TextInputType.text
              : spec['inputMode'] == 'url'
              ? TextInputType.url
              : null,
          obscureText: false,
          autofillHints: spec['inputMode'] == 'url'
              ? const [AutofillHints.url]
              : null,
          autocorrect: spec['inputMode'] != 'url',
          enableSuggestions: spec['inputMode'] != 'url',
          textInputAction: spec['inputMode'] == 'search'
              ? TextInputAction.search
              : null,
          minLines:
              spec['minLines'] as int? ??
              (spec['multiline'] == true || spec['type'] == 'sourceEditor'
                  ? 4
                  : 1),
          maxLines:
              spec['maxLines'] as int? ??
              (spec['multiline'] == true || spec['type'] == 'sourceEditor'
                  ? 16
                  : 1),
          decoration: InputDecoration(
            labelText: text,
            helperText: spec['helperText'] == null
                ? null
                : '${bind(spec['helperText'])}',
            errorText: spec['errorText'] == null
                ? spec['inputMode'] == 'number'
                      ? validateNumberInput(
                          controller.text,
                          integer: spec['integer'] == true,
                          min: spec['min'] as num?,
                          max: spec['max'] as num?,
                        )
                      : null
                : '${bind(spec['errorText'])}',
            prefixIcon: spec['inputMode'] == 'search'
                ? const UiIcon(Icons.search)
                : null,
            suffixIcon: spec['clearable'] == true && controller.text.isNotEmpty
                ? IconButton(
                    tooltip: '清除$text',
                    onPressed: bind(spec['disabled']) == true
                        ? null
                        : () {
                            controller.clear();
                            _changeForm(
                              key,
                              '',
                              bind(spec['onChangeEvent']),
                              debounce: true,
                            );
                          },
                    icon: const UiIcon(Icons.close_rounded),
                  )
                : null,
          ),
          onChanged: (v) {
            _changeForm(key, v, bind(spec['onChangeEvent']), debounce: true);
          },
          onSubmitted: event == null
              ? null
              : (v) => _render({...object(event), 'value': v}),
        );
      case 'timeRangeTable':
        final key = string(spec['key'], 'time range table key');
        final value = _selectionValue(key, spec);
        if (value is! Map || spec['baseline'] is! Map) {
          throw const FormatException('Invalid time range table');
        }
        return TimeRangeTable(
          key: ValueKey(key),
          value: object(value),
          baseline: object(spec['baseline']),
          enabled: !busy && bind(spec['disabled']) != true,
          onChanged: (value) => _changeForm(key, value, null),
        );
      case 'dateInput':
      case 'dateTimeInput':
      case 'dateRangeInput':
      case 'timeInput':
        final key = string(spec['key'], 'temporal input key');
        final kind = switch (spec['type']) {
          'dateInput' => TemporalInputKind.date,
          'dateTimeInput' => TemporalInputKind.dateTime,
          'dateRangeInput' => TemporalInputKind.dateRange,
          _ => TemporalInputKind.time,
        };
        _selectionValue(key, spec);
        final controller = kind == TemporalInputKind.dateRange
            ? null
            : controllers.putIfAbsent(
                key,
                () => TextEditingController(text: '${formValues[key] ?? ''}'),
              );
        final session = sessionKey;
        final instance = widget.host.instances[widget.moduleId];
        final revision = formRevisions[key] ?? 0;
        final config = canonicalJson({
          'kind': kind.name,
          'disabled': bind(spec['disabled']),
          'minDate': spec['minDate'],
          'maxDate': spec['maxDate'],
        });
        controlConfigs[key] = config;
        final inputKey = controlKeys.putIfAbsent(key, GlobalKey.new);
        final control = TemporalInput(
          key: inputKey,
          kind: kind,
          label: text,
          value: formValues[key],
          controller: controller,
          focusNode: focusNodes.putIfAbsent(key, FocusNode.new),
          enabled: !busy && bind(spec['disabled']) != true,
          clearable: spec['clearable'] == true,
          editable: spec['editable'] != false && kind != TemporalInputKind.time,
          minDate: spec['minDate'] as String?,
          maxDate: spec['maxDate'] as String?,
          errorText: spec['errorText'] == null
              ? null
              : '${bind(spec['errorText'])}',
          isCurrent: () =>
              mounted &&
              session == sessionKey &&
              inputKey.currentContext != null &&
              revision == (formRevisions[key] ?? 0) &&
              config == controlConfigs[key] &&
              identical(instance, widget.host.instances[widget.moduleId]),
          onChanged: (value) => _changeForm(key, value, event),
        );
        // Legacy timetable time rows use compact inputs inside a wrapping row.
        if (kind == TemporalInputKind.time) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  (spec['width'] as num? ??
                          (spec['clearable'] == true ? 208 : 156) *
                              MediaQuery.textScalerOf(uiContext).scale(14) /
                              14)
                      .toDouble()
                      .clamp(120, 320)
                      .toDouble();
              return SizedBox(
                width: constraints.hasBoundedWidth
                    ? width.clamp(0, constraints.maxWidth).toDouble()
                    : width,
                child: control,
              );
            },
          );
        }
        return control;
      case 'divider':
        return const Divider();
      case 'timeGrid':
        return TimeGrid(
          columns: objects(spec['columns']),
          rows: objects(spec['rows']),
          blocks: objects(spec['blocks']),
          corner: object(spec['corner'] ?? {}),
          options: object(spec['options'] ?? {}),
          bottomInset: object(spec['options'] ?? {})['underlapChrome'] == true
              ? WorkspaceContentInsets.bottomOf(uiContext)
              : 0,
          onEvent: busy ? (_) {} : _render,
        );
      case 'plannerBoard':
        final quickConfig = _quickAdjustmentConfig(spec);
        return WorkspaceDragRegion(
          builder: (context, onDragActiveChanged) => PlannerBoard(
            bottomInset: WorkspaceContentInsets.bottomOf(uiContext),
            onDragActiveChanged: onDragActiveChanged,
            enabled: !busy && !staleTree && routeActive && workspaceActive,
            previewIdentity: spec['previewIdentity'],
            quickAdjust: _quickAdjust,
            pendingAdjustment: quickConfig != null
                ? _pendingPlannerAdjustment
                : null,
            onQuickAdjustChanged: quickConfig != null ? _setQuickAdjust : null,
            onPreview: spec['previewQuery'] is Map
                ? (proposal) =>
                      _previewQuery(object(spec['previewQuery']), proposal)
                : null,
            days: _plannerItems(spec['days']),
            candidates: _plannerItems(spec['candidates']),
            blocks: _plannerItems(spec['blocks']),
            previewBlocks: _plannerItems(spec['previewBlocks']),
            previewLabel: spec['previewLabel'] as String?,
            selectedIds: (spec['selectedIds'] as List?)?.cast<Object?>() ?? [],
            selectEvent: spec['selectEvent'] is Map
                ? object(spec['selectEvent'])
                : null,
            options: object(spec['options'] ?? {}),
            onEvent: busy
                ? (_) {}
                : (event) => _plannerEvent(event, quickConfig),
          ),
        );
      default:
        return Text('不支持的组件：${spec['type']}');
    }
  }

  Widget pageContent() {
    final spec = tree!;
    final rootChildren = objects(spec['children']);
    final controller = scrollControllers.putIfAbsent(
      'page',
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final rawPanel = spec['floatingPanel'];
        final panel = rawPanel is Map ? object(rawPanel) : null;
        final bottom = WorkspaceContentInsets.bottomOf(context);
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
                          (spec['ref'] as String? ?? '').startsWith('ui.page.')
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
                      controller: scrollControllers.putIfAbsent(
                        'page',
                        ScrollController.new,
                      ),
                      padding: EdgeInsets.fromLTRB(
                        spec['edgeToEdge'] == true
                            ? 0
                            : spec['compact'] == true
                            ? 16
                            : 20,
                        spec['edgeToEdge'] == true
                            ? 0
                            : spec['compact'] == true
                            ? 8
                            : 16,
                        spec['edgeToEdge'] == true
                            ? 0
                            : spec['compact'] == true
                            ? 16
                            : 20,
                        16 + bottom,
                      ),
                      itemCount: rootChildren.length,
                      itemBuilder: (context, i) {
                        final child = rootChildren[i];
                        return Padding(
                          key: child['key'] == null
                              ? null
                              : ValueKey(child['key']),
                          padding: EdgeInsets.only(
                            bottom: (spec['spacing'] as num? ?? 12)
                                .toDouble()
                                .clamp(0, 48),
                          ),
                          child: node(child, 1),
                        );
                      },
                    )
                  : SingleChildScrollView(
                      controller: scrollControllers.putIfAbsent(
                        'page',
                        ScrollController.new,
                      ),
                      padding: EdgeInsets.fromLTRB(
                        spec['edgeToEdge'] == true
                            ? 0
                            : spec['compact'] == true
                            ? 16
                            : 20,
                        spec['edgeToEdge'] == true
                            ? 0
                            : spec['compact'] == true
                            ? 8
                            : 16,
                        spec['edgeToEdge'] == true
                            ? 0
                            : spec['compact'] == true
                            ? 16
                            : 20,
                        16 + bottom,
                      ),
                      child: safeNode(spec),
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
    );
  }

  @override
  Widget build(BuildContext context) => UiPackScope(
    moduleId: widget.moduleId,
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
            if (!widget.embedded && currentTree && tree?['header'] is Map)
              safeNode(object(tree!['header'])),
            if (!widget.embedded &&
                currentTree &&
                _hasQuickAdjustHeader &&
                !hasNativeHeader)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
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
                    if (!currentTree && loading) const PageLoadingPlaceholder(),
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
            if (tree?['footer'] is Map)
              Offstage(
                offstage: !currentTree,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    12 + WorkspaceContentInsets.bottomOf(context),
                  ),
                  child: _inlinePlanPreview != null
                      ? FloatingSurface(
                          padding: const EdgeInsets.all(12),
                          child: _inlineReviewFooter(_inlinePlanPreview!),
                        )
                      : tree!['footer'] is Map &&
                            object(tree!['footer'])['type'] == 'messageComposer'
                      ? safeNode(object(tree!['footer']))
                      : FloatingSurface(
                          padding: const EdgeInsets.all(12),
                          child: safeNode(object(tree!['footer'])),
                        ),
                ),
              ),
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
