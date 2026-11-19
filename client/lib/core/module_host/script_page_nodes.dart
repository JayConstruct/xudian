part of 'script_page.dart';

extension _ScriptPageNodes on _ScriptPageState {
  bool _swipeContentSafe(Map<String, Object?> spec, [int depth = 0]) {
    if (depth > 32 ||
        !const {
          'column',
          'row',
          'card',
          'text',
          'icon',
          'badge',
          'listTile',
          'button',
          'divider',
        }.contains(spec['type'])) {
      return false;
    }
    // A recipe can introduce selectable text or native slots. Unknown recipes
    // retain all their controls and use the menu, without a competing drag.
    final registry = uiContext
        .dependOnInheritedWidgetOfExactType<UiScopeData>()
        ?.registry;
    final ref = switch (spec['type']) {
      'listTile' => 'ui.listTile@1',
      'card' => 'ui.card@1',
      'text' => 'ui.text@1',
      'button' => 'ui.button@1',
      'divider' => 'ui.divider@1',
      _ => null,
    };
    if (ref != null && registry?.resolve(ref) != null) return false;
    return objects(spec['children'])
        .every((child) => _swipeContentSafe(child, depth + 1));
  }

  Widget _motionNode(Map<String, Object?> spec, int depth) {
    final key = spec['key'];
    if (key is! String || key.isEmpty || spec['child'] is! Map) {
      throw const FormatException('Motion/gesture requires a key and child');
    }
    final identity = ValueKey((
      key,
      renderedInstance,
      treeContextIdentity,
      tree?['scrollKey'] ?? tree?['key'],
    ));
    if (spec['type'] == 'motion') {
      uiObject(spec, {'type', 'key', 'target', 'timing', 'child'}, 'motion');
      uiObject(spec['target'], {
        'opacity',
        'translateX',
        'translateY',
        'scale',
      }, 'motion target');
      final target = ScriptMotionValue.parse(_bindValue(spec['target']));
      final timing = spec.containsKey('timing')
          ? ScriptTiming.parse(spec['timing'])
          : const ScriptTiming();
      return ScriptMotion(
        key: identity,
        target: target,
        timing: timing,
        child: node(object(spec['child']), depth + 1),
      );
    }
    final resolved = <String, Object?>{
      ...spec,
      if (spec.containsKey('enabled')) 'enabled': bind(spec['enabled']),
      if (spec.containsKey('revision')) 'revision': bind(spec['revision']),
      'actions': spec['actions'] is List
          ? (spec['actions'] as List).map((raw) {
              final action = object(raw);
              return {
                ...action,
                'event': _bindValue(action['event']),
                if (action.containsKey('disabled'))
                  'disabled': bind(action['disabled']),
              };
            }).toList()
          : spec['actions'],
    };
    final config = ScriptSwipeConfig.parse(resolved, _icon);
    final child = object(spec['child']);
    return ScriptSwipeActions(
      key: identity,
      config: config,
      canSwipe: _swipeContentSafe(child),
      child: node(child, depth + 1),
      onAction: (event) async {
        if (busy ||
            staleTree ||
            !routeActive ||
            !workspaceActive ||
            !identical(
              renderedInstance,
              widget.host.instances[widget.moduleId],
            )) {
          return;
        }
        await _render(event);
      },
    );
  }

  Widget _node(Map<String, Object?> spec, int depth, bool replace) {
    if (depth > 32) return const Text('组件嵌套超过限制');
    if (spec['type'] == 'motion' || spec['type'] == 'swipeActions') {
      try {
        return _motionNode(spec, depth);
      } on FormatException catch (error) {
        return Text('模块界面无效：$error');
      }
    }
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
        if (spec['type'] == 'taskItem') 'command': spec['command'],
        'props': {
          for (final entry in spec.entries)
            if (!const {
              'type',
              'key',
              'event',
              'openEvent',
              'children',
              'action',
              'command',
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
                'feedback',
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
                _commandEvent(bind(spec['event']), spec['command']);
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
            ? scrollControllers.putIfAbsent(
                '${tree?['scrollKey'] ?? 'page'}',
                ScrollController.new,
              )
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
    final childSpecs = objects(spec['children']);
    final newKeys = childSpecs
        .where(
          (item) => item['type'] == 'motion' || item['type'] == 'swipeActions',
        )
        .map((item) => item['key'])
        .toList();
    if (newKeys.isNotEmpty) {
      final counts = <Object?, int>{};
      for (final item in childSpecs) {
        counts.update(item['key'], (count) => count + 1, ifAbsent: () => 1);
      }
      if (newKeys.any((key) => counts[key] != 1)) {
        throw const FormatException('Duplicate motion/gesture key');
      }
    }
    final children = childSpecs.map((n) => node(n, depth + 1)).toList();
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
          crossAxisAlignment: spec['crossAxisAlignment'] == 'start'
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.stretch,
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
                    bottom:
                        spec['trailingSpacing'] == false &&
                            i == children.length - 1
                        ? 0
                        : (spec['spacing'] as num? ?? 12).toDouble().clamp(
                            0,
                            48,
                          ),
                  ),
                  child: children[i],
                ),
          ],
        );
      case 'row':
        final spacing = (spec['spacing'] as num? ?? 8)
            .toDouble()
            .clamp(0, 48)
            .toDouble();
        if (spec['layout'] == 'flex') {
          final specifications = objects(spec['children']);
          return Row(
            crossAxisAlignment: spec['crossAxisAlignment'] == 'start'
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(width: spacing),
                if (specifications[i]['flex'] is num &&
                    (specifications[i]['flex'] as num) > 0)
                  Expanded(
                    flex: (specifications[i]['flex'] as num).toInt().clamp(
                      1,
                      10,
                    ),
                    child: children[i],
                  )
                else if (specifications[i]['width'] is num)
                  SizedBox(
                    width: (specifications[i]['width'] as num).toDouble().clamp(
                      0,
                      760,
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
          spacing: spacing,
          runSpacing: spacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        );
      case 'grid':
        return ResponsiveContentGrid(children: children);
      case 'segmented':
        final items = objects(spec['items']);
        if (items.isEmpty || items.length > 12) {
          throw const FormatException('Invalid segmented choices');
        }
        final sliding = spec['variant'] == 'sliding';
        return ScriptSegmentedControl(
          key: spec['key'] == null ? null : ValueKey('${spec['key']}'),
          labels: [for (final item in items) '${bind(item['label']) ?? ''}'],
          sliding: sliding,
          selectedIndex: (bind(spec['selectedIndex']) as num? ?? 0).toInt(),
          // Same-level navigation may queue the latest destination during a render.
          onSelected:
              (!sliding && busy) || staleTree || bind(spec['disabled']) == true
              ? null
              : (index) => _render(bind(items[index]['event'])),
        );
      case 'formSection':
        final action = spec['action'] is Map ? object(spec['action']) : null;
        return ScriptFormSection(
          key: spec['key'] == null ? null : ValueKey('${spec['key']}'),
          title: '${bind(spec['title']) ?? ''}',
          actionLabel: action == null ? null : '${bind(action['text']) ?? ''}',
          onAction: busy || action?['event'] == null
              ? null
              : () => _render(bind(action!['event'])),
          children: children,
        );
      case 'notice':
        return ScriptNotice(text: text, tone: '${spec['tone'] ?? 'info'}');
      case 'choiceCard':
        return ScriptChoiceCard(
          key: spec['key'] == null ? null : ValueKey('${spec['key']}'),
          title: '${bind(spec['title']) ?? ''}',
          subtitle: '${bind(spec['subtitle']) ?? ''}',
          selected: bind(spec['selected']) == true,
          onTap: busy || event == null || bind(spec['disabled']) == true
              ? null
              : () => _render(event),
        );
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
      case 'groupItem':
        return ScriptGroupedRow(
          key: spec['key'] == null ? null : ValueKey(spec['key']),
          position: spec['position'] as String? ?? 'only',
          child: node(object(spec['child']), depth + 1),
        );
      case 'card':
        if (spec['variant'] == 'outlined' || spec['event'] != null) {
          final scheme = Theme.of(uiContext).colorScheme;
          final shape = AppDesign.smoothShape(
            side: BorderSide(
              color: spec['variant'] == 'outlined'
                  ? scheme.outlineVariant.withValues(alpha: .65)
                  : Colors.transparent,
            ),
          );
          return Material(
            color: scheme.surface,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: shape,
              onTap:
                  event == null || _actionBusy || bind(spec['disabled']) == true
                  ? null
                  : () => _commandEvent(event, null),
              child: Padding(
                padding: EdgeInsets.all(
                  (spec['padding'] as num? ?? 14).toDouble().clamp(0, 48),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          );
        }
        if (spec['tone'] == 'soft' || spec['tone'] == 'selected') {
          final scheme = Theme.of(uiContext).colorScheme;
          return Material(
            color: spec['tone'] == 'selected'
                ? scheme.primary.withValues(alpha: .10)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: EdgeInsets.all(
                (spec['padding'] as num? ?? 12).toDouble().clamp(0, 48),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          );
        }
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
        final maxLines = bind(spec['maxLines']);
        final overflow = bind(spec['overflow']);
        if (maxLines != null &&
                (maxLines is! int || maxLines < 1 || maxLines > 10) ||
            overflow != null && overflow != 'ellipsis') {
          throw const FormatException('Invalid text line limit');
        }
        final theme = Theme.of(uiContext);
        final baseStyle = switch (spec['style']) {
          'title' => theme.textTheme.titleLarge,
          'metric' => theme.textTheme.displaySmall?.copyWith(
            fontSize: 44,
            height: 1.15,
          ),
          'headline' => theme.textTheme.headlineSmall?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
          'heading' => theme.textTheme.titleMedium,
          'caption' || 'muted' => theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          'body' => theme.textTheme.bodyMedium,
          _ => null,
        };
        final weight = switch (spec['weight']) {
          'bold' => FontWeight.w700,
          'semibold' => FontWeight.w600,
          _ => null,
        };
        final color = switch (spec['color']) {
          'primary' => theme.colorScheme.primary,
          'muted' => theme.colorScheme.onSurfaceVariant,
          _ => null,
        };
        return Text(
          text,
          maxLines: maxLines as int?,
          overflow: overflow == 'ellipsis' ? TextOverflow.ellipsis : null,
          semanticsLabel: overflow == 'ellipsis' ? text : null,
          textAlign: spec['align'] == 'center'
              ? TextAlign.center
              : spec['align'] == 'end'
              ? TextAlign.end
              : TextAlign.start,
          style: weight != null || color != null
              ? (baseStyle ?? theme.textTheme.bodyMedium)?.copyWith(
                  fontWeight: weight,
                  color: color,
                )
              : baseStyle,
        );
      case 'icon':
        return ScriptGlyph(
          icon: _icon(spec['icon']),
          size: (spec['size'] as num? ?? 20).toDouble().clamp(12, 64),
          tone: '${spec['tone'] ?? 'accent'}',
          surface: spec['surface'] == true,
          surfaceSize: (spec['surfaceSize'] as num? ?? 40).toDouble().clamp(
            24,
            80,
          ),
          label: spec['label'] == null ? null : '${bind(spec['label'])}',
        );
      case 'badge':
        return ScriptBadge(
          text: text,
          tone: '${spec['tone'] ?? 'accent'}',
          icon: _icon(spec['icon']),
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
        final enabled = !_actionBusy && bind(spec['disabled']) != true;
        final trailingAction = spec['trailingAction'] is Map
            ? object(spec['trailingAction'])
            : null;
        Widget? trailingControl;
        if (trailingAction != null) {
          final label = '${bind(trailingAction['label']) ?? ''}'.trim();
          if (label.isEmpty) {
            throw const FormatException('List tile action needs a label');
          }
          final actionEvent = bind(trailingAction['event']);
          final onPressed =
              enabled &&
                  bind(trailingAction['disabled']) != true &&
                  actionEvent != null
              ? () => _commandEvent(actionEvent, null)
              : null;
          final actionIcon = UiIcon(
            _icon(trailingAction['icon']) ?? Icons.more_horiz,
          );
          trailingControl = trailingAction['tonal'] == true
              ? IconButton.filledTonal(
                  tooltip: label,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: onPressed,
                  icon: actionIcon,
                )
              : IconButton(
                  tooltip: label,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: onPressed,
                  icon: actionIcon,
                );
          if (trailing is String && trailing.isNotEmpty) {
            trailingControl = ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(uiContext).width * .42,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      trailing,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: spec['trailingAccent'] == true
                          ? TextStyle(
                              color: Theme.of(uiContext).colorScheme.primary,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 4),
                  trailingControl,
                ],
              ),
            );
          }
        }
        final toned = spec['iconTone'] is String;
        final metaIcon = _icon(spec['metaIcon']);
        final lines = subtitle is String && metaIcon != null
            ? subtitle.split('\n')
            : const <String>[];
        final metadata = lines.length == 2;

        final theme = Theme.of(uiContext);
        return ListTile(
          minVerticalPadding: toned ? 8 : null,
          minTileHeight: metadata
              ? 88
              : toned
              ? 60
              : null,
          horizontalTitleGap: toned ? 12 : null,
          minLeadingWidth: toned ? 34 : null,
          contentPadding: EdgeInsets.symmetric(horizontal: toned ? 12 : 8),
          dense: tree?['compact'] == true,
          visualDensity: tree?['compact'] == true && trailingAction == null
              ? const VisualDensity(vertical: -2)
              : null,
          titleTextStyle: toned
              ? theme.textTheme.titleSmall?.copyWith(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                )
              : tree?['compact'] == true
              ? Theme.of(uiContext).textTheme.bodyMedium
              : null,
          subtitleTextStyle: tree?['compact'] == true
              ? Theme.of(uiContext).textTheme.bodySmall
                    ?.copyWith(color: AppDesign.muted(uiContext))
              : null,
          leading: icon == null
              ? null
              : toned
              ? ScriptGlyph(
                  icon: icon,
                  tone: spec['iconTone'] as String,
                  surface: true,
                  surfaceSize: 34,
                )
              : UiIcon(icon),
          title: Text('${bind(spec['title']) ?? text}'),
          subtitle: metadata
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lines.first),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        UiIcon(metaIcon, size: 14),
                        const SizedBox(width: 5),
                        Expanded(child: Text(lines.last)),
                      ],
                    ),
                  ],
                )
              : subtitle == null
              ? null
              : Text('$subtitle'),
          trailing:
              trailingControl ??
              (trailing == false
                  ? null
                  : trailing is String
                  ? ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(uiContext).width * .42,
                      ),
                      child: toned && spec['trailingAccent'] == true
                          ? ScriptBadge(text: trailing, tone: 'warning')
                          : Text(
                              trailing,
                              textAlign: TextAlign.end,
                              style: spec['trailingAccent'] == true
                                  ? TextStyle(
                                      color: Theme.of(uiContext)
                                          .colorScheme
                                          .primary,
                                    )
                                  : null,
                            ),
                    )
                  : event == null
                  ? null
                  : const UiIcon(Icons.chevron_right)),
          enabled: enabled,
          selected: bind(spec['selected']) == true,
          selectedTileColor: Theme.of(uiContext).colorScheme.primary
              .withValues(alpha: .08),
          onTap: event == null || !enabled
              ? null
              : () => _commandEvent(event, null),
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
            : tree?['queueInputActions'] == true && _actionBusy ||
                  bind(spec['disabled']) == true
            ? null
            : () {
                _commandEvent(event, spec['command']);
              };
        final buttonIcon = _icon(spec['icon']);
        final buttonLabel = buttonIcon == null
            ? Text(text)
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  UiIcon(buttonIcon, size: 20),
                  const SizedBox(width: 8),
                  Flexible(child: Text(text)),
                ],
              );
        if (spec.containsKey('feedback')) {
          return ScriptFeedbackButton(
            feedback: ScriptButtonFeedback.parse(spec['feedback']),
            onPressed: press,
            variant: spec['variant'] as String?,
            style: appUiButtonStyle,
            child: buttonLabel,
          );
        }
        return switch (spec['variant']) {
          'text' => TextButton(
            style: appUiButtonStyle,
            onPressed: press,
            child: buttonLabel,
          ),
          'outlined' => OutlinedButton(
            style: appUiButtonStyle,
            onPressed: press,
            child: buttonLabel,
          ),
          'filled' => FilledButton(
            style: appUiButtonStyle,
            onPressed: press,
            child: buttonLabel,
          ),
          _ => FilledButton.tonal(
            style: appUiButtonStyle,
            onPressed: press,
            child: buttonLabel,
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
        final selected = bind(spec['value']) == true;
        final detail = bind(spec['detail']);
        final control = CheckboxListTile(
          controlAffinity: detail == null
              ? ListTileControlAffinity.platform
              : ListTileControlAffinity.leading,
          value: selected,
          title: Text(text),
          secondary: detail == null
              ? null
              : ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(uiContext).width * .33,
                  ),
                  child: Text(
                    '$detail',
                    style: Theme.of(uiContext).textTheme.bodySmall,
                  ),
                ),
          onChanged: busy || bind(spec['disabled']) == true
              ? null
              : (v) => _changeControl(spec, v, event),
        );
        if (detail == null) return control;
        return AnimatedContainer(
          color: selected
              ? Theme.of(uiContext).colorScheme.primary.withValues(alpha: .08)
              : Colors.transparent,
          duration: AppMotion.duration(
            uiContext,
            const Duration(milliseconds: 140),
          ),
          child: control,
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
      case 'emptyState':
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 96, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_icon(spec['icon']) case final icon?)
                if (spec['iconSurface'] == true)
                  ScriptGlyph(
                    icon: icon,
                    surface: true,
                    surfaceSize: 52,
                    size: 24,
                  )
                else
                  UiIcon(icon, size: 28),
              const SizedBox(height: 8),
              Text(
                '${bind(spec['title']) ?? ''}',
                textAlign: TextAlign.center,
                style: Theme.of(uiContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                text,
                textAlign: TextAlign.center,
                style: Theme.of(uiContext).textTheme.bodySmall,
              ),
            ],
          ),
        );
      case 'menuButton':
        return PopupMenuButton<int>(
          tooltip: text,
          popUpAnimationStyle: spec['variant'] == 'tonal'
              ? (AppMotion.reduced(uiContext)
                    ? AnimationStyle.noAnimation
                    : const AnimationStyle(
                        duration: Duration(milliseconds: 160),
                        reverseDuration: Duration(milliseconds: 140),
                      ))
              : null,
          enabled: !_actionBusy && bind(spec['disabled']) != true,
          itemBuilder: (_) => [
            for (final (index, item) in objects(spec['items']).indexed)
              CheckedPopupMenuItem<int>(
                value: index,
                checked: bind(item['selected']) == true,
                child: Text('${bind(item['label'])}'),
              ),
          ],
          onSelected: (index) async {
            final instance = renderedInstance;
            final identity = treeContextIdentity;
            final event = bind(objects(spec['items'])[index]['event']);
            if (mounted &&
                !routeActive &&
                ModalRoute.of(context)?.isCurrent == true) {
              await WidgetsBinding.instance.endOfFrame;
            }
            if (mounted &&
                identical(renderedInstance, instance) &&
                treeContextIdentity == identity) {
              _commandEvent(event, null);
            }
          },
          child: Container(
            decoration: spec['variant'] == 'tonal'
                ? BoxDecoration(
                    color: Theme.of(uiContext).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(22),
                  )
                : null,
            padding: EdgeInsets.symmetric(
              vertical: 10,
              horizontal: spec['variant'] == 'tonal' ? 12 : 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_icon(spec['icon']) case final icon?) ...[
                  UiIcon(icon, size: 14),
                  const SizedBox(width: 4),
                ],
                Text(
                  text,
                  style: Theme.of(uiContext).textTheme.labelMedium?.copyWith(
                    color: Theme.of(uiContext).colorScheme.primary,
                  ),
                ),
                const UiIcon(Icons.expand_more, size: 14),
              ],
            ),
          ),
        );
      case 'spinner':
        return const Center(child: CircularProgressIndicator());
      case 'list':
        return Column(children: children);
      case 'tabs':
        if (spec['variant'] == 'pills' || spec['variant'] == 'underline') {
          final items = objects(spec['items']);
          if (items.isEmpty || items.length > 20) {
            throw const FormatException('Invalid tab choices');
          }
          return ScriptTabChoices(
            labels: [for (final item in items) '${bind(item['label']) ?? ''}'],
            selectedIndex: (bind(spec['selectedIndex']) as num? ?? 0).toInt(),
            underlined: spec['variant'] == 'underline',
            scrollable: spec['scrollable'] == true,
            onSelected: _actionBusy || bind(spec['disabled']) == true
                ? null
                : (index) => _changeControl(spec, index, items[index]['event']),
          );
        }
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
            labelText: spec['presentation'] == 'search' ? null : text,
            hintText: spec['presentation'] == 'search' ? text : null,
            isDense: spec['presentation'] == 'search' ? true : null,
            contentPadding: spec['presentation'] == 'search'
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 14)
                : null,
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
            prefixIcon:
                spec['inputMode'] == 'search' && spec['showSearchIcon'] != false
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
              : (v) => _commandEvent({
                  ...object(event),
                  'value': v,
                }, spec['command']),
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
        return Divider(
          height: (spec['height'] as num?)?.toDouble().clamp(0, 48),
        );
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
        final timeline = _timelineConfig(spec);
        final instance = widget.host.instances[widget.moduleId];
        final timelineTree = tree;
        return WorkspaceDragRegion(
          builder: (context, onDragActiveChanged) => PlannerBoard(
            bottomInset: WorkspaceContentInsets.bottomOf(uiContext),
            onDragActiveChanged: (active) {
              _plannerDragging = active;
              onDragActiveChanged(active);
              if (!active && _refreshAfterPlannerDrag) {
                _refreshAfterPlannerDrag = false;
                Timer.run(() {
                  if (mounted) unawaited(_render());
                });
              }
            },
            enabled: !busy && !staleTree && routeActive && workspaceActive,
            previewIdentity: spec['previewIdentity'],
            quickAdjust: _quickAdjust,
            pendingAdjustment: quickConfig != null
                ? _pendingPlannerAdjustment
                : null,
            onQuickAdjustChanged: quickConfig != null ? _setQuickAdjust : null,
            onViewportChanged: timeline == null
                ? null
                : (viewport) => _plannerViewportChanged(
                    timelineTree,
                    timeline,
                    instance,
                    viewport,
                  ),
            onLoadRange: timeline == null
                ? null
                : (startDate, days) => _loadPlannerRange(
                    timelineTree,
                    timeline,
                    instance,
                    startDate,
                    days,
                  ),
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
            onCommandAction: busy ? null : _commandEvent,
          ),
        );
      default:
        return Text('不支持的组件：${spec['type']}');
    }
  }
}
