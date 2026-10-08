import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../module_host/json_schema.dart';
import 'ui_pack.dart';
import 'ui_pack_providers.dart';

class UiResolvedRecipe {
  const UiResolvedRecipe(this.pack, this.recipe);
  final UiPackDefinition pack;
  final UiRecipe recipe;
}

/// Registry lookup is cached per immutable package/selection snapshot.
class UiComponentRegistry {
  UiComponentRegistry(this.packs, this.selection, this.moduleId);
  final Map<String, UiPackDefinition> packs;
  final UiSelection selection;
  final String? moduleId;
  final _resolved = <String, UiResolvedRecipe?>{};
  Iterable<UiPackDefinition> get selected sync* {
    final local = moduleId == null ? null : selection.modulePackIds[moduleId];
    if (local == defaultUiPackId) return;
    if (local != null && packs[local] != null) yield packs[local]!;
    if (local != selection.globalPackId &&
        packs[selection.globalPackId] != null) {
      yield packs[selection.globalPackId]!;
    }
  }

  UiResolvedRecipe? resolve(String ref) {
    if (_resolved.containsKey(ref)) return _resolved[ref];
    UiResolvedRecipe? result;
    for (final pack in selected) {
      final recipe = pack.components[ref];
      if (recipe != null) {
        result = UiResolvedRecipe(pack, recipe);
        break;
      }
    }
    if (result == null && !uiContracts.containsKey(ref)) {
      for (final pack in packs.values) {
        final recipe = pack.components[ref];
        if (recipe != null) {
          result = UiResolvedRecipe(pack, recipe);
          break;
        }
      }
    }
    _resolved[ref] = result;
    return result;
  }

  Map<String, Object?> tokens(Brightness brightness) {
    final result = <String, Object?>{};
    for (final pack in selected.toList().reversed) {
      result.addAll(pack.tokens[brightness.name] ?? const {});
    }
    return result;
  }
}

class UiScopeData extends InheritedWidget {
  const UiScopeData({
    super.key,
    required this.registry,
    required this.defaultTheme,
    required this.defaultOnly,
    required this.theme,
    required super.child,
  });
  final UiComponentRegistry registry;
  final ThemeData defaultTheme, theme;
  final bool defaultOnly;
  static UiScopeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UiScopeData>();
  @override
  bool updateShouldNotify(UiScopeData oldWidget) =>
      registry != oldWidget.registry ||
      theme != oldWidget.theme ||
      defaultOnly != oldWidget.defaultOnly;
}

/// Theme and recipe selection rebuild only when a selection/package changes.
/// Explicit preview inputs never read the live package registry.
class UiPackScope extends ConsumerStatefulWidget {
  const UiPackScope({
    super.key,
    required this.child,
    this.moduleId,
    this.defaultOnly = false,
    this.previewPacks,
    this.previewSelection,
  });
  final Widget child;
  final String? moduleId;
  final bool defaultOnly;
  final Map<String, UiPackDefinition>? previewPacks;
  final UiSelection? previewSelection;
  @override
  ConsumerState<UiPackScope> createState() => _UiPackScopeState();
}

class _UiPackScopeState extends ConsumerState<UiPackScope> {
  Map<String, UiPackDefinition>? oldPacks;
  UiSelection? oldSelection;
  String? oldModule;
  ThemeData? oldDefault, cachedTheme;
  bool? oldProtected, oldHighContrast;
  UiComponentRegistry? registry;
  @override
  Widget build(BuildContext context) {
    final inherited = UiScopeData.maybeOf(context);
    var hasProviders = true;
    if (widget.previewPacks == null && !widget.defaultOnly) {
      try {
        ProviderScope.containerOf(context, listen: false);
      } on StateError {
        hasProviders = false;
      }
    }
    final defaultTheme = widget.previewPacks != null
        ? Theme.of(context)
        : inherited?.defaultTheme ?? Theme.of(context);
    // A preview can intentionally choose a non-default implementation while its
    // surrounding configuration controls remain in the protected default UI.
    final protected =
        widget.defaultOnly ||
        (widget.previewPacks == null &&
            (!hasProviders || inherited?.defaultOnly == true));
    final packs = protected
        ? const <String, UiPackDefinition>{}
        : widget.previewPacks ??
              ref.watch(uiPackRegistryProvider).asData?.value ??
              const <String, UiPackDefinition>{};
    final selection = protected
        ? (oldSelection ?? UiSelection())
        : widget.previewSelection ??
              ref.watch(uiSelectionProvider).asData?.value ??
              (oldSelection ?? UiSelection());
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    if (!identical(oldPacks, packs) ||
        !identical(oldSelection, selection) ||
        oldModule != widget.moduleId ||
        oldDefault != defaultTheme ||
        oldProtected != protected ||
        oldHighContrast != highContrast) {
      registry = UiComponentRegistry(
        protected ? const {} : packs,
        selection,
        widget.moduleId,
      );
      cachedTheme = applyUiPackTheme(
        defaultTheme,
        highContrast ? const {} : registry!.tokens(defaultTheme.brightness),
      );
      oldPacks = packs;
      oldSelection = selection;
      oldModule = widget.moduleId;
      oldDefault = defaultTheme;
      oldProtected = protected;
      oldHighContrast = highContrast;
    }
    return UiScopeData(
      registry: registry!,
      defaultTheme: defaultTheme,
      defaultOnly: protected,
      theme: cachedTheme!,
      child: Theme(data: cachedTheme!, child: widget.child),
    );
  }
}

Color? _color(Object? value) {
  if (value is! String || !value.startsWith('#')) return null;
  final digits = value.substring(1);
  final parsed = int.tryParse(digits, radix: 16);
  if (parsed == null) return null;
  return Color(digits.length == 6 ? 0xff000000 | parsed : parsed);
}

ThemeData applyUiPackTheme(ThemeData base, Map<String, Object?> tokens) {
  if (tokens.isEmpty) return base;
  final primary = _color(tokens['primary']);
  var scheme = primary == null
      ? base.colorScheme
      : ColorScheme.fromSeed(seedColor: primary, brightness: base.brightness);
  scheme = scheme.copyWith(
    surface: _color(tokens['surface']),
    onSurface: _color(tokens['onSurface']),
    outline: _color(tokens['outline']),
  );
  final radius = (tokens['radius'] as num?)?.toDouble();
  final shape = radius == null
      ? null
      : RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));
  final spacing = (tokens['spacing'] as num?)?.toDouble();
  final scale = (tokens['fontScale'] as num?)?.toDouble();
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: _color(tokens['canvas']),
    textTheme: scale == null
        ? null
        : base.textTheme.apply(fontSizeFactor: scale),
    cardTheme: base.cardTheme.copyWith(color: scheme.surface, shape: shape),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: scheme.surface,
      shape: shape,
    ),
    listTileTheme: base.listTileTheme.copyWith(
      contentPadding: spacing == null
          ? null
          : EdgeInsets.symmetric(
              horizontal: spacing * 2,
              vertical: spacing / 2,
            ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: (base.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
        shape: shape == null ? null : WidgetStatePropertyAll(shape),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (base.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
        shape: shape == null ? null : WidgetStatePropertyAll(shape),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (base.textButtonTheme.style ?? const ButtonStyle()).copyWith(
        shape: shape == null ? null : WidgetStatePropertyAll(shape),
      ),
    ),
  );
}

/// A native control owns its state and callbacks; a UI package supplies only
/// the presentation. Without a scope this wrapper is a zero-provider fallback.
class UiComponent extends StatefulWidget {
  const UiComponent({
    super.key,
    required this.ref,
    required this.fallback,
    this.props = const {},
    this.slots = const {},
    this.events = const {},
    this.moduleId,
    this.defaultOnly = false,
  });
  final String ref;
  final Widget fallback;
  final Map<String, Object?> props;
  final Map<String, Widget> slots;
  final Map<String, void Function(Object?)> events;
  final String? moduleId;
  final bool defaultOnly;
  @override
  State<UiComponent> createState() => _UiComponentState();
}

class _UiComponentState extends State<UiComponent> {
  final nativeKey = GlobalKey();
  @override
  Widget build(BuildContext context) {
    final ref = widget.ref,
        fallback = KeyedSubtree(key: nativeKey, child: widget.fallback);
    final props = widget.props,
        events = widget.events,
        moduleId = widget.moduleId;
    final slots = widget.slots.map(
      (name, child) =>
          MapEntry(name, identical(child, widget.fallback) ? fallback : child),
    );
    final scope = UiScopeData.maybeOf(context);
    if (widget.defaultOnly || scope == null || scope.defaultOnly) {
      return fallback;
    }
    final registry = moduleId == null || moduleId == scope.registry.moduleId
        ? scope.registry
        : UiComponentRegistry(
            scope.registry.packs,
            scope.registry.selection,
            moduleId,
          );
    final resolved = registry.resolve(ref);
    if (resolved == null) return fallback;
    try {
      validateSchema(props, resolved.recipe.contract.propsSchema);
      return _UiRecipeView(
        registry: registry,
        resolved: resolved,
        props: props,
        slots: slots,
        events: events,
        fallback: fallback,
        refs: {ref},
        depth: 0,
      );
    } catch (error) {
      // Failure records contain identifiers, never input values or page text.
      debugPrint(
        'UI fallback ${resolved.pack.moduleId}@${resolved.pack.version} $ref: ${error.runtimeType}',
      );
      return fallback;
    }
  }
}

class _UiRecipeView extends StatelessWidget {
  const _UiRecipeView({
    required this.registry,
    required this.resolved,
    required this.props,
    required this.slots,
    required this.events,
    required this.fallback,
    required this.refs,
    required this.depth,
  });
  final UiComponentRegistry registry;
  final UiResolvedRecipe resolved;
  final Map<String, Object?> props;
  final Map<String, Widget> slots;
  final Map<String, void Function(Object?)> events;
  final Widget fallback;
  final Set<String> refs;
  final int depth;
  @override
  Widget build(BuildContext context) {
    try {
      return _node(context, resolved.recipe.tree, {
        'props': props,
        'environment': {
          'wide': MediaQuery.sizeOf(context).width >= 820,
          'dark': Theme.of(context).brightness == Brightness.dark,
          'highContrast': MediaQuery.of(context).highContrast,
          'reduceMotion': MediaQuery.disableAnimationsOf(context),
        },
      }, depth);
    } catch (error) {
      debugPrint(
        'UI fallback ${resolved.pack.moduleId} ${resolved.recipe.contract.ref}: ${error.runtimeType}',
      );
      return fallback;
    }
  }

  Widget _node(
    BuildContext context,
    UiRecipeNode node,
    Map<String, Object?> values,
    int level, {
    bool flex = false,
  }) {
    if (level > 32) return fallback;
    Object? value(String name) => evaluateUiValue(node.values[name], values);
    switch (node.type) {
      case 'base':
        return fallback;
      case 'slot':
        return slots[value('name')] ?? const SizedBox.shrink();
      case 'if':
        return _node(
          context,
          node.branches[value('condition') == true ? 'then' : 'else']!,
          values,
          level + 1,
          flex: flex,
        );
      case 'responsive':
        return _node(
          context,
          node.branches[MediaQuery.sizeOf(context).width >= 820
              ? 'wide'
              : 'narrow']!,
          values,
          level + 1,
          flex: flex,
        );
      case 'repeat':
        final items = value('items');
        if (items is! List) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) => ListView.builder(
            shrinkWrap: !constraints.hasBoundedHeight,
            physics: constraints.hasBoundedHeight
                ? null
                : const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final local = {...values, 'item': items[i], 'index': i};
              final key = evaluateUiValue(node.values['key'], local) ?? i;
              return KeyedSubtree(
                key: ValueKey(key),
                child: _node(
                  context,
                  node.branches['child']!,
                  local,
                  level + 1,
                ),
              );
            },
          ),
        );
      case 'component':
        final ref = value('ref') as String;
        final childProps =
            (value('props') as Map?)?.cast<String, Object?>() ?? {};
        final childSlots = node.slots.map(
          (k, n) => MapEntry(k, _node(context, n, values, level + 1)),
        );
        final forwarding =
            (value('events') as Map?)?.cast<String, String>() ?? {};
        final childEvents = <String, void Function(Object?)>{
          for (final e in forwarding.entries)
            if (events[e.value] != null) e.key: events[e.value]!,
        };
        final native = defaultUiComponent(
          ref,
          childProps,
          childSlots,
          childEvents,
        );
        final child = registry.resolve(ref);
        if (child == null || refs.contains(ref)) return native;
        validateSchema(childProps, child.recipe.contract.propsSchema);
        return _UiRecipeView(
          registry: registry,
          resolved: child,
          props: childProps,
          slots: childSlots,
          events: childEvents,
          fallback: native,
          refs: {...refs, ref},
          depth: level + 1,
        );
      case 'primitive':
        final p = (value('props') as Map?)?.cast<String, Object?>() ?? {};
        final event = value('event');
        final callback = events[event];
        final name = value('name');
        final spacing = _dimension(p['spacing'], fallback: 8, max: 48);
        Widget child(int i, {bool allowFlex = false}) => _node(
          context,
          node.children[i],
          values,
          level + 1,
          flex: allowFlex,
        );
        Widget onlyChild() =>
            node.children.isEmpty ? const SizedBox.shrink() : child(0);
        Widget widget;
        switch (name) {
          case 'column':
          case 'row':
            widget = LayoutBuilder(
              builder: (context, constraints) {
                final vertical = name == 'column';
                final bounded = vertical
                    ? constraints.hasBoundedHeight
                    : constraints.hasBoundedWidth;
                final children = <Widget>[];
                for (var i = 0; i < node.children.length; i++) {
                  if (i != 0 && spacing > 0) {
                    children.add(
                      SizedBox(
                        height: vertical ? spacing : null,
                        width: vertical ? null : spacing,
                      ),
                    );
                  }
                  final raw = node.children[i];
                  var content = _node(
                    context,
                    raw,
                    values,
                    level + 1,
                    flex: bounded,
                  );
                  final needsViewport =
                      resolved.recipe.contract.ref == 'ui.page.list@1' ||
                      resolved.recipe.contract.ref == 'ui.page.timeGrid@1' ||
                      resolved.recipe.contract.ref == 'ui.chrome.sidebar@1';
                  if (vertical &&
                      bounded &&
                      needsViewport &&
                      !(raw.type == 'primitive' &&
                          raw.values['name'] == 'expanded') &&
                      raw.descendants.any(
                        (n) =>
                            n.type == 'base' ||
                            n.type == 'slot' &&
                                {
                                  'items',
                                  'grid',
                                  'navigation',
                                }.contains(n.values['name']),
                      )) {
                    content = Expanded(child: content);
                  }
                  children.add(content);
                }
                return Flex(
                  direction: vertical ? Axis.vertical : Axis.horizontal,
                  mainAxisSize: p['fill'] == true && bounded
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  crossAxisAlignment: vertical
                      ? CrossAxisAlignment.stretch
                      : CrossAxisAlignment.center,
                  children: children,
                );
              },
            );
          case 'wrap':
            widget = Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (var i = 0; i < node.children.length; i++) child(i),
              ],
            );
          case 'text':
            widget = Text(
              '${p['text'] ?? p['label'] ?? ''}',
              maxLines: p['maxLines'] is int
                  ? (p['maxLines'] as int).clamp(1, 20)
                  : null,
              overflow: p['maxLines'] is int ? TextOverflow.ellipsis : null,
              style: p['style'] == 'title'
                  ? Theme.of(context).textTheme.titleLarge
                  : p['style'] == 'secondary'
                  ? Theme.of(context).textTheme.bodySmall
                  : null,
            );
          case 'icon':
            widget = Icon(
              uiIcon(p['name']),
              size: _dimension(p['size'], fallback: 24, max: 64),
            );
          case 'button':
            final onPressed =
                callback == null ||
                    p['disabled'] == true ||
                    props['disabled'] == true
                ? null
                : () => callback(null);
            final label = Text(
              '${p['label'] ?? p['text'] ?? props['label'] ?? ''}',
            );
            final style = ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
            );
            widget = switch (p['variant']) {
              'outlined' => OutlinedButton(
                onPressed: onPressed,
                style: style,
                child: label,
              ),
              'text' => TextButton(
                onPressed: onPressed,
                style: style,
                child: label,
              ),
              'filled' => FilledButton(
                onPressed: onPressed,
                style: style,
                child: label,
              ),
              _ => FilledButton.tonal(
                onPressed: onPressed,
                style: style,
                child: label,
              ),
            };
          case 'card':
            final content = node.children.length == 1
                ? onlyChild()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < node.children.length; i++) child(i),
                    ],
                  );
            widget = Material(
              color: Theme.of(context).colorScheme.surface,
              shape: Theme.of(context).cardTheme.shape,
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: EdgeInsets.all(
                  _dimension(p['padding'], fallback: 12, max: 48),
                ),
                child: content,
              ),
            );
          case 'divider':
            widget = const Divider();
          case 'spacer':
            widget = SizedBox(
              height: _dimension(p['height'], fallback: spacing, max: 200),
              width: _dimension(p['width'], fallback: spacing, max: 200),
            );
          case 'padding':
            widget = Padding(
              padding: EdgeInsets.all(
                _dimension(p['padding'], fallback: spacing, max: 48),
              ),
              child: onlyChild(),
            );
          case 'expanded':
            widget = flex
                ? Expanded(
                    flex: (p['flex'] as int? ?? 1).clamp(1, 12),
                    child: onlyChild(),
                  )
                : onlyChild();
          case 'scroll':
            widget = SingleChildScrollView(child: onlyChild());
          case 'list':
            widget = LayoutBuilder(
              builder: (context, constraints) => ListView.builder(
                shrinkWrap: !constraints.hasBoundedHeight,
                physics: constraints.hasBoundedHeight
                    ? null
                    : const NeverScrollableScrollPhysics(),
                itemCount: node.children.length,
                itemBuilder: (context, i) => child(i),
              ),
            );
          default:
            return fallback;
        }
        if (p['width'] is num || p['height'] is num) {
          widget = SizedBox(
            width: p['width'] is num
                ? _dimension(p['width'], fallback: 0, max: 2048)
                : null,
            height: p['height'] is num
                ? _dimension(p['height'], fallback: 0, max: 2048)
                : null,
            child: widget,
          );
        }
        return widget;
      default:
        return fallback;
    }
  }
}

double _dimension(
  Object? value, {
  required double fallback,
  required double max,
}) =>
    value is num && value.isFinite ? value.toDouble().clamp(0, max) : fallback;

IconData uiIcon(Object? name) => switch (name) {
  'add' => Icons.add,
  'settings' => Icons.settings_outlined,
  'calendar' => Icons.calendar_month_outlined,
  'info' => Icons.info_outline,
  'check' => Icons.check,
  'inbox' => Icons.inbox_outlined,
  'list' => Icons.list_alt_outlined,
  'delete' => Icons.delete_outline,
  _ => Icons.circle_outlined,
};

/// Default public templates accept already-owned business widgets in slots.
/// They never query data or dispatch a service themselves.
Widget defaultUiComponent(
  String ref,
  Map<String, Object?> props,
  Map<String, Widget> slots,
  Map<String, void Function(Object?)> events,
) {
  Widget slot(String name) => slots[name] ?? const SizedBox.shrink();
  switch (ref) {
    case 'ui.button@1':
      return FilledButton.tonal(
        onPressed: props['disabled'] == true || events['press'] == null
            ? null
            : () => events['press']!(null),
        child: Text('${props['label'] ?? ''}'),
      );
    case 'ui.text@1':
      return Text('${props['text'] ?? props['label'] ?? ''}');
    case 'ui.icon@1':
      return Icon(uiIcon(props['name']));
    case 'ui.divider@1':
      return const Divider();
    case 'ui.card@1':
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: slot('content'),
        ),
      );
    case 'ui.page.list@1':
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (slots['filters'] != null) slot('filters'),
          Expanded(
            child: props['empty'] == true && slots['empty'] != null
                ? slot('empty')
                : slot('items'),
          ),
          if (slots['footer'] != null) slot('footer'),
        ],
      );
    case 'ui.page.timeGrid@1':
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (slots['filters'] != null) slot('filters'),
          Expanded(child: slot('grid')),
          if (slots['legend'] != null) slot('legend'),
          if (slots['detail'] != null) slot('detail'),
        ],
      );
    case 'ui.page.form@1':
    case 'ui.page.settings@1':
    case 'ui.page.detail@1':
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (props['title'] is String)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(props['title'] as String),
              ),
            slot(
              ref == 'ui.page.form@1'
                  ? 'fields'
                  : ref == 'ui.page.settings@1'
                  ? 'sections'
                  : 'content',
            ),
            if (slots['actions'] != null) slot('actions'),
          ],
        ),
      );
    case 'ui.list@1':
      return slot('items');
    case 'ui.empty@1':
      return Center(child: Text('${props['title'] ?? '暂无内容'}'));
    case 'ui.loading@1':
      return const Center(child: CircularProgressIndicator());
    case 'ui.progress@1':
      return LinearProgressIndicator(
        value: props['value'] is num
            ? (props['value'] as num).toDouble().clamp(0, 1)
            : null,
      );
    case 'ui.error@1':
      return Column(
        children: [
          Text('${props['message'] ?? '加载失败'}'),
          if (events['retry'] != null)
            TextButton(
              onPressed: () => events['retry']!(null),
              child: const Text('重试'),
            ),
        ],
      );
    default:
      return slots['control'] ?? slots['content'] ?? const SizedBox.shrink();
  }
}
