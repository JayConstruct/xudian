import 'dart:async';

import '../contracts/json_values.dart';
import '../ui/workspace_header.dart';
import '../ui/ui_component.dart';
import '../ui/ui_pack.dart';
import '../ui/temporal_input.dart';
import '../ui/responsive_content_grid.dart';
import '../ui/input_validation.dart';

import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import 'module_host.dart';
import 'module_package.dart';
import 'time_grid.dart';

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
  int epoch = 0;
  String? error;
  String get sessionKey =>
      '${widget.moduleId}:${widget.handler}:${canonicalJson(widget.pageContext)}';
  bool busy = false, dirty = false;
  bool showProgress = false;
  bool routeActive = true;
  Set<String>? readModules;
  String businessRegistry = '';
  Object? pendingEvent, currentEvent, queryResult;
  WorkspaceHeaderController? headerController;
  BuildContext? nodeContext;
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
      if (readModules != null && !modules.any(readModules!.contains)) return;
      refreshTimer?.cancel();
      refreshTimer = Timer(const Duration(milliseconds: 40), () => _render());
    });
    businessRegistry = _businessRegistry();
    registrySubscription = widget.host.registryChanges.stream.listen((_) {
      final next = _businessRegistry();
      if (next == businessRegistry) return;
      businessRegistry = next;
      unawaited(_render());
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

  @override
  void didUpdateWidget(ScriptPage old) {
    super.didUpdateWidget(old);
    if (old.moduleId != widget.moduleId ||
        old.handler != widget.handler ||
        canonicalJson(old.pageContext) != canonicalJson(widget.pageContext)) {
      epoch++;
      busy = false;
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
      readModules = null;
      subscription?.cancel();
      registrySubscription?.cancel();
      refreshTimer?.cancel();
      _subscribe();
      unawaited(_render());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = ModalRoute.isCurrentOf(context) != false;
    if (active == routeActive) return;
    routeActive = active;
    progressTimer?.cancel();
    showProgress = false;
    if (busy && active) _delayProgress(epoch);
  }

  void _delayProgress(int current) {
    progressTimer?.cancel();
    if (!routeActive) return;
    progressTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && current == epoch && busy) {
        setState(() => showProgress = true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.resumed) unawaited(_render());
  }

  Future<void> _render([Object? event]) async {
    if (!mounted) return;
    if (busy) {
      dirty = true;
      if (event != null) pendingEvent = event;
      return;
    }
    final current = ++epoch;
    final instance = widget.host.instances[widget.moduleId];
    final headerScope = WorkspaceHeaderScope.read(context);
    final headerLease = headerScope?.lease;
    final ownsHeader =
        !widget.embedded &&
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
    try {
      final result = object(
        await widget.host.invokePage(
          widget.moduleId,
          widget.handler,
          {
            'state': state,
            'context': widget.pageContext,
            'event': event,
            'formValues': sentForms,
          },
          onReads: (reads) {
            if (mounted && current == epoch) readModules = reads;
          },
        ),
      );
      if (!mounted ||
          current != epoch ||
          !identical(instance, widget.host.instances[widget.moduleId])) {
        return;
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
        tree = object(result['tree']);
        error = null;
      });
      if (ownsHeader) {
        final raw = result['header'];
        headerScope!.controller.publish(
          headerLease!,
          this,
          raw is Map ? object(raw) : null,
          _render,
        );
      }
    } catch (e) {
      if (mounted && current == epoch) {
        headerController?.clear(this);
        setState(() => error = '$e');
      }
    } finally {
      if (mounted && current == epoch) {
        progressTimer?.cancel();
        setState(() {
          busy = false;
          showProgress = false;
        });
        if (dirty) {
          dirty = false;
          final next = pendingEvent;
          pendingEvent = null;
          unawaited(_render(next));
        }
        refreshTimer?.cancel();
        refreshTimer = Timer(const Duration(minutes: 1), () => _render());
      }
    }
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
    if (event == null) return;
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
      'context': widget.pageContext,
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

  IconData? _icon(Object? value) => switch (value) {
    'calendar' => Icons.calendar_month_outlined,
    'schedule' => Icons.schedule_outlined,
    'school' => Icons.school_outlined,
    'tune' => Icons.tune,
    'importExport' => Icons.import_export,
    'list' => Icons.list_alt_outlined,
    'history' => Icons.history,
    'settings' => Icons.settings_outlined,
    'today' => Icons.today_outlined,
    'add' => Icons.add,
    'delete' => Icons.delete_outline,
    'info' => Icons.info_outline,
    _ => null,
  };

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

  Widget componentNode(Map<String, Object?> spec, int depth) {
    final ref = string(spec['ref'], 'UI component reference');
    final key = '${spec['key'] ?? ref}';
    if (!uiContracts.containsKey(ref)) {
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
    final slots = object(spec['slots'] ?? {})
        .map((name, raw) => MapEntry(name, _slot(raw, name, key, depth)));
    final events = _bindValues(object(spec['events'] ?? {}));
    final callbacks = <String, void Function(Object?)>{
      for (final entry in events.entries)
        entry.key: (value) {
          if (!busy && props['disabled'] != true) {
            _render(
              value == null && entry.key != 'change'
                  ? entry.value
                  : {...object(entry.value), 'value': value},
            );
          }
        },
    };
    if (ref == 'ui.button@1') {
      props['disabled'] = busy || props['disabled'] == true;
    }
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

  Widget node(Map<String, Object?> spec, [int depth = 0, bool replace = true]) {
    if (depth > 32) return const Text('组件嵌套超过限制');
    if (spec['type'] == 'component') return componentNode(spec, depth);
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
                'min',
                'max',
              ])
                if (spec.containsKey(key)) key: spec[key],
            }),
            'label': bind(spec['title']) ?? bind(spec['text']),
            'disabled':
                (busy && spec['interrupt'] is! String) ||
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
    final children = objects(spec['children'])
        .map((n) => node(n, depth + 1))
        .toList();
    final text = '${bind(spec['text']) ?? ''}';
    final event = bind(spec['event']);
    switch (spec['type']) {
      case 'column':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++)
              if (spec['fillHeight'] == true && i == children.length - 1)
                Expanded(child: children[i])
              else
                Padding(
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
        return ExpansionTile(
          key: PageStorageKey(spec['key'] ?? text),
          title: Text(text),
          tilePadding: EdgeInsets.zero,
          children: children,
        );
      case 'card':
        return ContentSurface(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
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
        return SelectableText(text);
      case 'listTile':
        final icon = _icon(spec['icon']);
        final subtitle = bind(spec['subtitle']);
        final trailing = bind(spec['trailing']);
        final enabled = !busy && bind(spec['disabled']) != true;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: icon == null ? null : Icon(icon),
          title: Text('${bind(spec['title']) ?? text}'),
          subtitle: subtitle == null ? null : Text('$subtitle'),
          trailing: trailing == false
              ? null
              : trailing is String
              ? Text(trailing)
              : event == null
              ? null
              : const Icon(Icons.chevron_right),
          enabled: enabled,
          onTap: event == null || !enabled ? null : () => _render(event),
        );
      case 'source':
        return ExpansionTile(
          title: const Text('查看文件内容'),
          children: [
            SelectableText(
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
            : busy || bind(spec['disabled']) == true
            ? null
            : () => _render(event);
        return switch (spec['variant']) {
          'text' => TextButton(onPressed: press, child: Text(text)),
          'outlined' => OutlinedButton(onPressed: press, child: Text(text)),
          'filled' => FilledButton(onPressed: press, child: Text(text)),
          _ => FilledButton.tonal(onPressed: press, child: Text(text)),
        };
      case 'toolbar':
        Widget action(Map<String, Object?> value) => IconButton(
          tooltip: '${value['label'] ?? ''}',
          onPressed: busy || value['disabled'] == true
              ? null
              : () => _render(value['event']),
          icon: Icon(switch (value['icon']) {
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
                              style: Theme.of(uiContext)
                                  .textTheme
                                  .headlineSmall,
                            ),
                            if (spec['subtitle'] != null)
                              Text(
                                '${bind(spec['subtitle'])}',
                                style: Theme.of(uiContext).textTheme.labelSmall,
                              ),
                            if (event != null)
                              const Icon(Icons.arrow_drop_down, size: 20),
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
        return Slider(
          value: (bind(spec['value']) as num? ?? min).toDouble().clamp(
            min,
            max,
          ),
          min: min,
          max: max,
          divisions: spec['divisions'] as int?,
          semanticFormatterCallback: (value) => '$text $value',
          onChanged: busy || bind(spec['disabled']) == true
              ? null
              : (value) => _changeControl(spec, value, event),
        );
      case 'progress':
        return LinearProgressIndicator(
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
                ? const Icon(Icons.search)
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
                    icon: const Icon(Icons.close_rounded),
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
      default:
        return Text('不支持的组件：${spec['type']}');
    }
  }

  Widget pageContent() {
    final spec = tree!;
    final rootChildren = objects(spec['children']);
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
                      spec['type'] == 'component' &&
                          (spec['ref'] as String? ?? '').startsWith('ui.page.')
                  ? Padding(
                      padding: EdgeInsets.only(
                        bottom: spec['underlapChrome'] == true ? 0 : bottom,
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
                        spec['edgeToEdge'] == true ? 0 : 16,
                        spec['edgeToEdge'] == true ? 0 : 16,
                        spec['edgeToEdge'] == true ? 0 : 16,
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
                        spec['edgeToEdge'] == true ? 0 : 16,
                        spec['edgeToEdge'] == true ? 0 : 16,
                        spec['edgeToEdge'] == true ? 0 : 16,
                        16 + bottom,
                      ),
                      child: safeNode(spec),
                    ),
            ),
            if (panel != null)
              Positioned(
                top: top,
                right: 12,
                width: (constraints.maxWidth - 24).clamp(0, 420),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (constraints.maxHeight - top - bottom - 12)
                        .clamp(0, constraints.maxHeight * .65),
                  ),
                  child: FloatingSurface(
                    key: const ValueKey('script-floating-panel'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${panel['title'] ?? ''}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: '${panel['closeLabel'] ?? '关闭面板'}',
                              onPressed: busy
                                  ? null
                                  : () => _render(panel['closeEvent']),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            child: safeNode(object(panel['child'])),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
        final loading = busy && showProgress && routeActive;
        return Column(
          mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // A modal is waiting for user input; only the active page shows
            // render progress. Keep busy for serialization and disabled inputs.
            if (loading && tree != null)
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
            if (widget.embedded)
              Padding(
                padding: const EdgeInsets.all(16),
                child: tree == null
                    ? loading
                          ? const CircularProgressIndicator()
                          : const SizedBox.shrink()
                    : safeNode(tree!),
              )
            else
              Expanded(
                child: tree == null
                    ? loading
                          ? const Center(child: CircularProgressIndicator())
                          : const SizedBox.shrink()
                    : pageContent(),
              ),
            if (tree?['footer'] is Map)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  12 + WorkspaceContentInsets.bottomOf(context),
                ),
                child: FloatingSurface(
                  padding: const EdgeInsets.all(12),
                  child: safeNode(object(tree!['footer'])),
                ),
              ),
          ],
        );
      },
    ),
  );
}
