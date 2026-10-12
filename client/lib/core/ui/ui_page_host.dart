import 'ui_icon.dart';
import 'native_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modules/module_registry.dart';
import 'ui_surfaces.dart';
import '../../features/settings/ui_layout.dart';
import '../../features/settings/ui_layout_page.dart';
import 'ui_annotation.dart';
import 'ui_composition.dart';
import 'ui_layout_resolver.dart';
import 'page_context_validation.dart';
import 'module_detail_page.dart';
import 'page_runtime_context.dart';
import 'page_composition_readiness.dart';
import 'page_first_frame.dart';
import 'date_reveal.dart';
import 'date_navigation_intent.dart';
import 'workspace_header.dart';
import 'temporal_input.dart';

class PagePosition {
  final bucket = PageStorageBucket();
  final Map<String, String> tabs = {};
}

final pagePositionStoreProvider = Provider<Map<String, PagePosition>>(
  (ref) => {},
);
final depthReminderSeenProvider = Provider<Set<String>>((ref) => {});

class UiPageHost extends ConsumerStatefulWidget {
  const UiPageHost({
    super.key,
    required this.registry,
    required this.pageId,
    this.pageContext = const PageContext(),
    this.path = const [],
    this.mountPath = const [],
    this.showDepthWarning = true,
    this.inlineContent = false,
  });

  final ModuleRegistry registry;
  final String pageId;
  final PageContext pageContext;
  final List<String> path;
  final List<String> mountPath;
  final bool showDepthWarning;
  final bool inlineContent;

  @override
  ConsumerState<UiPageHost> createState() => _UiPageHostState();
}

class _UiPageHostState extends ConsumerState<UiPageHost> {
  PagePosition position = PagePosition();
  String? identity;
  bool showDepthNotice = false;
  Map<String, Object?> runtimeValues = const {};
  int runtimeRevision = 0;
  String? runtimeOwner;
  bool ownsRuntimeContext = false;
  PageContext effectiveContext = const PageContext();
  WorkspaceHeaderController? dateHeader;
  bool firstFrameBlocked = false;
  final dateReveal = DateRevealController();
  final dateReadiness = <Object, bool>{};
  bool dateContentReady = true;
  bool dateTransitionEnabled = false;
  int dateVisualRevision = 0;
  Offset? datePointer;
  DateTime? datePointerTime;
  bool dateSwipe = false;
  String? todayDate;

  void _reportTodayDate(String date) {
    try {
      validateRuntimeContextPatch({'selectedDate': date});
    } on FormatException {
      return;
    }
    if (mounted && todayDate != date) setState(() => todayDate = date);
  }

  void _forgetDateReadiness(Object owner) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      dateReadiness.remove(owner);
      if (!dateContentReady && dateReadiness.values.every((value) => value)) {
        setState(() => dateContentReady = true);
      }
    });
  }

  void _dateReadinessChanged(Object owner, int revision, bool ready) {
    if (!mounted || revision != runtimeRevision) return;
    dateReadiness[owner] = ready;
    // Ordinary task edits already have their own feedback. Only a date intent
    // freezes this viewport; section queries alone must not start a wave.
    if (dateContentReady && !dateReveal.isTransitioning) return;
    final complete = dateReadiness.values.every((value) => value);
    if (complete != dateContentReady) {
      setState(() => dateContentReady = complete);
    }
  }

  void _prepareDate(String next, Rect? bounds) {
    final previous = effectiveContext.values['selectedDate'];
    if (!dateTransitionEnabled || previous is! String || previous == next) {
      return;
    }
    final pointerRecent =
        datePointerTime != null &&
        DateTime.now().difference(datePointerTime!) <
            const Duration(seconds: 1);
    if (dateContentReady || dateReveal.isTransitioning) {
      dateReveal.prepare(
        originGlobal: bounds?.center ?? (pointerRecent ? datePointer : null),
        initialRadius: bounds == null ? 24 : bounds.shortestSide / 2,
        swipe: bounds == null && pointerRecent && dateSwipe,
        direction: next.compareTo(previous) >= 0 ? 1 : -1,
      );
    }
    dateContentReady = false;
    dateVisualRevision++;
    dateReadiness.updateAll((_, _) => false);
  }

  // Runtime date changes must not suspend or remount an existing page while
  // validating the same persistent references. Retry must target this same key.
  PageContext get validationContext =>
      PageContext(values: withoutRuntimePageContext(effectiveContext.values));

  Future<void> _dateHeaderEvent(Object? raw) async {
    if (!mounted || raw is! Map) return;
    final selected = effectiveContext.values['selectedDate'];
    final date = parseInputDate(selected);
    if (date == null) return;
    String? next;
    switch (raw['type']) {
      case 'date.choose':
        next = await pickTemporalValue(
          context,
          kind: TemporalInputKind.date,
          value: selected,
          minDate: '0001-01-01',
          maxDate: '9999-12-31',
          isCurrent: () =>
              mounted && effectiveContext.values['selectedDate'] == selected,
        ) as String?;
      case 'date.previous':
      case 'date.next':
        final shifted = DateTime.utc(
          date.year,
          date.month,
          date.day + (raw['type'] == 'date.previous' ? -1 : 1),
        );
        if (shifted.year >= 1 && shifted.year <= 9999) {
          next = formatInputDate(shifted);
        }
      case 'date.today':
        next = todayDate ?? formatInputDate(DateTime.now());
    }
    if (mounted &&
        next != null &&
        effectiveContext.values['selectedDate'] == selected) {
      _updateRuntimeContext(
        {'selectedDate': next},
        originBounds: raw['originBounds'] is Rect
            ? raw['originBounds'] as Rect
            : null,
      );
    }
  }

  bool _updateRuntimeContext(Map<String, Object?> raw, {Rect? originBounds}) {
    final patch = validateRuntimeContextPatch(raw);
    if (!mounted ||
        patch.entries.every(
          (entry) => runtimeValues[entry.key] == entry.value,
        )) {
      return false;
    }
    if (patch['selectedDate'] case final String next) {
      _prepareDate(next, originBounds);
    }
    setState(() {
      runtimeValues = Map.unmodifiable({...runtimeValues, ...patch});
      runtimeRevision++;
    });
    return true;
  }

  @override
  void initState() {
    super.initState();
    widget.registry.addListener(_changed);
  }

  @override
  void didUpdateWidget(UiPageHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedDate = widget.pageContext.values['selectedDate'];
    if (ownsRuntimeContext &&
        oldWidget.pageId == widget.pageId &&
        oldWidget.pageContext.navigationIdentity ==
            widget.pageContext.navigationIdentity &&
        oldWidget.pageContext.values['selectedDate'] != selectedDate) {
      // An explicit navigation date supersedes a prior local choice, while
      // keeping the mounted composition, its drafts and its scroll position.
      // Children that inherit runtime context must never rewrite its owner.
      if (selectedDate is String) _prepareDate(selectedDate, null);
      runtimeValues = Map.unmodifiable(
        {...runtimeValues, 'selectedDate': selectedDate}
          ..removeWhere((key, value) => key == 'selectedDate' && value == null),
      );
      runtimeRevision++;
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    dateHeader?.clear(this);
    widget.registry.removeListener(_changed);
    dateReveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildPage(context);
    return widget.path.isEmpty
        ? PageFirstFrameGate(blocked: firstFrameBlocked, child: body)
        : body;
  }

  Widget _buildPage(BuildContext context) {
    firstFrameBlocked = false;
    final inheritedRuntime = PageRuntimeContextScope.maybeOf(context);
    final ownsRuntime = widget.path.isEmpty || inheritedRuntime == null;
    ownsRuntimeContext = ownsRuntime;
    final owner =
        '${widget.pageId}/${widget.mountPath.join('/')}/${widget.pageContext.navigationIdentity}';
    if (ownsRuntime && runtimeOwner != owner) {
      runtimeOwner = owner;
      todayDate = null;
      runtimeValues = const {};
      runtimeRevision++;
    }
    final values = ownsRuntime ? runtimeValues : inheritedRuntime.values;
    effectiveContext = widget.pageContext.merge(PageContext(values: values));
    if (widget.path.contains(widget.pageId)) {
      return _failure(
        UiMountDiagnostic(
          UiMountIssue.contentCycle,
          '循环内容嵌套：${[...widget.path, widget.pageId].join(' → ')}',
        ),
      );
    }
    final page = widget.registry.ui.page(widget.pageId);
    if (page == null) {
      return _failure(
        const UiMountDiagnostic(UiMountIssue.targetUnavailable, '页面不可用，配置已保留'),
      );
    }
    dateTransitionEnabled =
        ownsRuntime &&
        widget.path.isEmpty &&
        !widget.inlineContent &&
        page.container &&
        page.headerMode == 'date';
    if (!effectiveContext.satisfies(page.requiredContext)) {
      return _failure(
        UiMountDiagnostic(
          UiMountIssue.missingContext,
          '页面缺少上下文：${page.requiredContext.join('、')}',
        ),
      );
    }
    if (validationContext.values.isNotEmpty) {
      final validity = ref.watch(
        pageContextValidityProvider(validationContext),
      );
      if (validity.isLoading) {
        firstFrameBlocked = true;
        return const Center(
          child: NativeUi(child: CircularProgressIndicator()),
        );
      }
      if (validity.hasError) {
        return _failure(
          const UiMountDiagnostic(
            UiMountIssue.contextReadFailed,
            '读取页面上下文失败，可稍后重试',
          ),
        );
      }
      if (validity.asData?.value != true) {
        return _failure(
          const UiMountDiagnostic(
            UiMountIssue.invalidContext,
            '上下文引用的对象不存在或不可用，配置已保留',
          ),
        );
      }
    }
    final header = WorkspaceHeaderScope.read(context);
    final lease = header?.lease;
    final ownsDateHeader =
        ownsRuntime &&
        TickerMode.valuesOf(context).enabled &&
        widget.path.isEmpty &&
        !widget.inlineContent &&
        page.headerMode == 'date' &&
        lease?.mode == 'date' &&
        lease?.pageId == page.id &&
        lease?.moduleId == page.moduleId;
    if (ownsDateHeader) {
      if (!identical(dateHeader, header!.controller)) dateHeader?.clear(this);
      dateHeader = header.controller;
      header.controller.publishDate(
        lease!,
        this,
        effectiveContext.values['selectedDate'],
        todayDate: todayDate,
        dispatch: _dateHeaderEvent,
      );
    } else {
      dateHeader?.clear(this);
      dateHeader = null;
    }
    final nextIdentity =
        '${page.id}/${widget.mountPath.join('/')}/${widget.pageContext.navigationIdentity}';
    if (identity != nextIdentity) {
      identity = nextIdentity;
      position = page.retainPosition
          ? ref
                .read(pagePositionStoreProvider)
                .putIfAbsent(nextIdentity, PagePosition.new)
          : PagePosition();
      showDepthNotice =
          widget.showDepthWarning &&
          widget.path.length == 7 &&
          ref.read(depthReminderSeenProvider).add(nextIdentity);
    }
    final profile = (ref.watch(uiLayoutProvider).asData?.value ?? UiLayout())
        .profile(MediaQuery.sizeOf(context).width >= 820);
    final content = KeyedSubtree(
      key: ValueKey(nextIdentity),
      child: UiPageContentScope(
        inline: widget.inlineContent,
        child: Builder(
          builder: (context) => page.builder(context, effectiveContext),
        ),
      ),
    );
    final initializesDate =
        ownsRuntime &&
        page.container &&
        page.initializesRuntimeContext &&
        page.headerMode == 'date' &&
        effectiveContext.values['selectedDate'] == null;
    firstFrameBlocked = initializesDate;
    final body = PageRuntimeContextScope(
      values: values,
      revision: ownsRuntime ? runtimeRevision : inheritedRuntime.revision,
      currentValues: ownsRuntime
          ? () => runtimeValues
          : inheritedRuntime.currentValues,
      currentRevision: ownsRuntime
          ? () => runtimeRevision
          : inheritedRuntime.currentRevision,
      update: ownsRuntime ? _updateRuntimeContext : inheritedRuntime.update,
      dateTodayInMenu:
          ownsDateHeader || inheritedRuntime?.dateTodayInMenu == true,
      reportTodayDate: ownsRuntime
          ? _reportTodayDate
          : inheritedRuntime.reportTodayDate,
      child: PageStorage(
        bucket: position.bucket,
        child: UiAnnotation(
          id: page.id,
          name: page.title,
          moduleId: page.moduleId,
          pagePath: [...widget.path, page.id].join(' / '),
          purpose: '模块页面',
          child: Column(
            mainAxisSize: widget.inlineContent
                ? MainAxisSize.min
                : MainAxisSize.max,
            crossAxisAlignment: widget.inlineContent
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.center,
            children: [
              if (showDepthNotice)
                NativeUi(
                  child: ListTile(
                    leading: const UiIcon(Icons.account_tree_outlined),
                    title: const Text('页面已嵌套 8 层，可继续使用，建议调整布局'),
                    trailing: NativeUi(
                      child: IconButton(
                        tooltip: '关闭深度提醒',
                        onPressed: () =>
                            setState(() => showDepthNotice = false),
                        icon: const UiIcon(Icons.close),
                      ),
                    ),
                  ),
                ),
              if (!page.container || page.slots.isEmpty || initializesDate)
                if (widget.inlineContent) content else Expanded(child: content),
              for (final slot
                  in initializesDate ? <PageSlotDefinition>[] : page.slots)
                if (slot.kind == PageSlotKind.entries || widget.inlineContent)
                  _slot(page, slot, profile)
                else
                  Expanded(child: _slot(page, slot, profile)),
            ],
          ),
        ),
      ),
    );
    if (!dateTransitionEnabled) return body;
    return DateNavigationIntentScope(
      revision: runtimeRevision,
      reportReadiness: _dateReadinessChanged,
      forgetReadiness: _forgetDateReadiness,
      child: DateRevealScope(
        controller: dateReveal,
        child: Listener(
          onPointerDown: (event) {
            datePointer = event.position;
            datePointerTime = DateTime.now();
            dateSwipe = false;
          },
          onPointerMove: (event) {
            final distance = event.position - (datePointer ?? event.position);
            if (distance.dx.abs() > 8 &&
                distance.dx.abs() > distance.dy.abs()) {
              dateSwipe = true;
            }
          },
          child: DateReveal(
            controller: dateReveal,
            revision: dateVisualRevision,
            ready: dateContentReady && !initializesDate,
            blockInteraction: false,
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _slot(
    UiPageRegistration host,
    PageSlotDefinition slot,
    UiLayoutProfile profile,
  ) {
    final entries = orderedEntries(widget.registry.ui, profile.mountFor, (
      entry,
    ) {
      final mount = profile.mountFor(entry);
      return mount.placement == UiPlacement.page &&
          mount.pageId == host.id &&
          mount.slotId == slot.id;
    });
    Widget childFor(UiEntryRegistration entry, int index) {
      final mount = profile.mountFor(entry);
      final reason = mountDiagnostic(
        widget.registry.ui,
        entry,
        mount,
        context: effectiveContext,
      );
      if (reason != null) return _failure(reason, entry: entry);
      if (slot.capacity != null && index >= slot.capacity!) {
        return _failure(
          const UiMountDiagnostic(
            UiMountIssue.capacityExceeded,
            '槽位容量不足，挂载配置已保留',
          ),
          entry: entry,
        );
      }
      return UiPageHost(
        key: ValueKey(entry.id),
        registry: widget.registry,
        pageId: entry.pageId,
        pageContext: widget.pageContext.merge(mount.context),
        path: [...widget.path, widget.pageId],
        mountPath: [...widget.mountPath, entry.id],
        showDepthWarning: widget.showDepthWarning,
        inlineContent: widget.inlineContent || slot.inline,
      );
    }

    final children = <Widget>[];
    if (slot.kind == PageSlotKind.entries) {
      if (entries.isEmpty) return const SizedBox.shrink();
      for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        final entry = entries[entryIndex];
        final mount = profile.mountFor(entry);
        final problem =
            mountDiagnostic(
              widget.registry.ui,
              entry,
              mount,
              context: effectiveContext,
            ) ??
            (slot.capacity != null && entryIndex >= slot.capacity!
                ? const UiMountDiagnostic(
                    UiMountIssue.capacityExceeded,
                    '槽位容量不足，挂载配置已保留',
                  )
                : null);
        children.add(
          UiAnnotation(
            id: entry.id,
            name: entry.label,
            moduleId: entry.moduleId,
            pagePath: host.id,
            slot: slot.id,
            purpose: '打开子页面',
            child: NativeUi(
              child: OutlinedButton.icon(
                onPressed: () {
                  if (problem != null) {
                    showDialog<void>(
                      context: context,
                      builder: (_) => NativeUi(
                        child: AlertDialog(
                          title: const Text('入口失效'),
                          content: _failure(problem, entry: entry),
                        ),
                      ),
                    );
                  } else {
                    final activation = UiEntryActivationScope.maybeOf(context);
                    if (activation != null &&
                        entry.opening != UiOpening.workspace) {
                      activation.open(
                        entry,
                        effectiveContext.merge(mount.context),
                      );
                      return;
                    }
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ModuleDetailPage(
                          registry: widget.registry,
                          pageId: entry.pageId,
                          title: entry.label,
                          pageContext: effectiveContext.merge(mount.context),
                          child: UiPageHost(
                            registry: widget.registry,
                            pageId: entry.pageId,
                            pageContext: effectiveContext.merge(mount.context),
                            mountPath: [...widget.mountPath, entry.id],
                            showDepthWarning: false,
                          ),
                        ),
                      ),
                    );
                  }
                },
                icon: UiIcon(
                  problem == null ? entry.icon : Icons.warning_amber_outlined,
                ),
                label: Text(entry.label),
              ),
            ),
          ),
        );
      }
    }
    Widget body;
    if (slot.kind == PageSlotKind.entries) {
      body = Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(spacing: 8, runSpacing: 8, children: children),
      );
    } else if (entries.isEmpty && slot.inline) {
      body = const SizedBox.shrink();
    } else if (entries.isEmpty) {
      body = Center(child: Text('${slot.label} · 暂无内容'));
    } else if (slot.kind == PageSlotKind.tabs) {
      final retained = position.tabs[slot.id];
      final selected = entries.indexWhere((entry) => entry.id == retained);
      final active = selected < 0 ? 0 : selected;
      body = Column(
        mainAxisSize: widget.inlineContent
            ? MainAxisSize.min
            : MainAxisSize.max,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (
                  var entryIndex = 0;
                  entryIndex < entries.length;
                  entryIndex++
                )
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: NativeUi(
                      child: ChoiceChip(
                        label: Text(entries[entryIndex].label),
                        selected: entryIndex == active,
                        onSelected: (_) => setState(
                          () => position.tabs[slot.id] = entries[entryIndex].id,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.inlineContent)
            childFor(entries[active], active)
          else
            Expanded(child: childFor(entries[active], active)),
        ],
      );
    } else if (slot.inline || widget.inlineContent) {
      final sections = PageCompositionReadyGroup(
        identity: '${host.id}:${effectiveContext.identity}:$runtimeRevision',
        memberIds: [for (final entry in entries) entry.id],
        children: [
          for (var index = 0; index < entries.length; index++)
            childFor(entries[index], index),
        ],
      );
      body = widget.inlineContent
          ? sections
          : SingleChildScrollView(
              key: PageStorageKey('${host.id}/${slot.id}'),
              padding: EdgeInsets.only(
                bottom: WorkspaceContentInsets.bottomOf(context),
              ),
              child: sections,
            );
    } else {
      body = ListView.builder(
        key: PageStorageKey('${host.id}/${slot.id}'),
        itemCount: entries.length,
        itemBuilder: (context, entryIndex) => SizedBox(
          height:
              MediaQuery.sizeOf(context).height.clamp(320, 640).toDouble() *
              0.65,
          child: childFor(entries[entryIndex], entryIndex),
        ),
      );
    }
    return UiAnnotation(
      id: '${host.id}/${slot.id}',
      name: slot.label,
      moduleId: host.moduleId,
      pagePath: [...widget.path, host.id].join(' / '),
      slot: slot.id,
      purpose: '页面槽位',
      child: body,
    );
  }

  void _editFailure(UiEntryRegistration? entry) {
    final candidates = widget.registry.ui.entries.where(
      (candidate) => candidate.id == widget.mountPath.lastOrNull,
    );
    final failedEntry = entry ?? candidates.firstOrNull;
    final failedId = failedEntry?.id ?? widget.mountPath.lastOrNull;
    final desktop = MediaQuery.sizeOf(context).width >= 820;
    final profile = (ref.read(uiLayoutProvider).asData?.value ?? UiLayout())
        .profile(desktop);
    final mount = failedEntry == null
        ? profile.mounts[failedId]
        : profile.mountFor(failedEntry);
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => UiLayoutPage(
          registry: widget.registry,
          initialPageId: mount?.placement == UiPlacement.page
              ? mount!.pageId
              : widget.path.lastOrNull,
          initialEntryId: failedId,
          initialDesktop: desktop,
        ),
      ),
    );
  }

  Widget _failure(UiMountDiagnostic diagnostic, {UiEntryRegistration? entry}) =>
      UiAnnotation(
        id: entry?.id ?? widget.pageId,
        name: '失效挂载',
        purpose: '处理失效配置',
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(diagnostic.message),
                Text(diagnostic.suggestion),
                Wrap(
                  spacing: 8,
                  children: [
                    NativeUi(
                      child: TextButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('配置保持不变，条件恢复后可重新使用')),
                          );
                        },
                        child: const Text('暂时保留'),
                      ),
                    ),
                    NativeUi(
                      child: TextButton(
                        onPressed: () => _editFailure(entry),
                        child: Text(
                          diagnostic.needsContext ? '重新绑定上下文' : '处理挂载',
                        ),
                      ),
                    ),
                    if (diagnostic.issue == UiMountIssue.contextReadFailed)
                      NativeUi(
                        child: TextButton(
                          onPressed: () => ref.invalidate(
                            pageContextValidityProvider(validationContext),
                          ),
                          child: const Text('重试'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}
