import 'package:flutter/material.dart';

import 'native_ui.dart';
import 'ui_icon.dart';
import 'ui_icons.dart';
import 'workspace_header.dart';

/// A touch menu replaces its current level in place, preserving its anchor.
/// Module actions are always resolved against the current leased contribution.
class WorkspaceHeaderMenu extends StatefulWidget {
  const WorkspaceHeaderMenu({
    super.key,
    required this.controller,
    required this.owner,
    required this.lease,
    required this.hostItems,
    this.inlineActionLabels = const {},
  });

  final WorkspaceHeaderController controller;
  final Object? owner;
  final WorkspaceHeaderLease? lease;
  final List<Widget> hostItems;
  final Set<String> inlineActionLabels;

  @override
  State<WorkspaceHeaderMenu> createState() => _WorkspaceHeaderMenuState();
}

class _WorkspaceHeaderMenuState extends State<WorkspaceHeaderMenu> {
  final _path = <String>[];
  Object? _menuToken;

  @override
  void initState() {
    super.initState();
    _menuToken = widget.controller.beginMenu(widget.lease, widget.owner);
  }

  @override
  void dispose() {
    widget.controller.endMenu(_menuToken);
    super.dispose();
  }

  late final _dispatchQueue = _WorkspaceMenuDispatchQueue(
    widget.controller,
    widget.owner,
    widget.lease,
  );

  WorkspaceHeaderContent? get _content => _dispatchQueue.content;

  List<Map> _actions(Object? raw) =>
      raw is List ? raw.whereType<Map>().toList() : const [];

  List<Map> get _rootActions => _actions(_content?.spec['actions'])
      .where(
        (action) =>
            action['overflowOnly'] != true ||
            !widget.inlineActionLabels.contains(action['label']),
      )
      .toList();

  void _dispatch(Map action, String eventKey, {bool keepOpen = false}) {
    final content = _content;
    if (content == null || action[eventKey] is! Map) return;
    if (!keepOpen) Navigator.of(context).pop();
    _dispatchQueue.add(action[eventKey]);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      var actions = _rootActions;
      var validDepth = 0;
      for (final label in _path) {
        final matches = actions.where((action) => action['label'] == label);
        if (matches.isEmpty || matches.first['children'] is! List) break;
        actions = _actions(matches.first['children']);
        validDepth++;
      }
      if (validDepth < _path.length) {
        _path.removeRange(validDepth, _path.length);
      }
      return PopScope(
        canPop: _path.isEmpty,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _path.isNotEmpty) setState(_path.removeLast);
        },
        child: SizedBox(
          width: _path.isEmpty ? null : 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_path.isNotEmpty) ...[
                _row(
                  label: _path.last,
                  icon: Icons.arrow_back_rounded,
                  tooltip: '返回上级菜单',
                  onTap: () => setState(_path.removeLast),
                ),
                const Divider(height: 8),
              ],
              for (final action in actions) ...[
                if (action['separatorBefore'] == true) const Divider(height: 8),
                _action(action),
              ],
              if (_path.isEmpty) ...[
                if (actions.isNotEmpty && widget.hostItems.isNotEmpty)
                  const Divider(height: 8),
                ...widget.hostItems,
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _action(Map action) {
    final label = '${action['label']}';
    if (action['kind'] == 'choiceGrid') {
      final choices = _actions(action['children']);
      final columns = MediaQuery.textScalerOf(context).scale(14) > 23 ? 1 : 2;
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            const SizedBox(height: 4),
            Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                for (var i = 0; i < choices.length; i += columns)
                  TableRow(
                    children: [
                      for (var col = 0; col < columns; col++)
                        i + col >= choices.length
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.all(4),
                                child: _choice(choices[i + col]),
                              ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      );
    }
    if (action['kind'] == 'stepper') {
      final compact = MediaQuery.textScalerOf(context).scale(14) <= 17;
      final controls = Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          NativeUi(
            child: IconButton(
              tooltip: '缩小时间轴',
              onPressed: action['decreaseEnabled'] == false
                  ? null
                  : () => _dispatch(action, 'decreaseEvent', keepOpen: true),
              icon: const UiIcon(Icons.remove, size: 20),
            ),
          ),
          if (compact)
            SizedBox(
              width: 42,
              child: Text(
                '${action['valueLabel'] ?? ''}',
                textAlign: TextAlign.center,
              ),
            )
          else
            Expanded(
              child: Text(
                '${action['valueLabel'] ?? ''}',
                textAlign: TextAlign.center,
              ),
            ),
          NativeUi(
            child: IconButton(
              tooltip: '放大时间轴',
              onPressed: action['increaseEnabled'] == false
                  ? null
                  : () => _dispatch(action, 'increaseEvent', keepOpen: true),
              icon: const UiIcon(Icons.add, size: 20),
            ),
          ),
        ],
      );
      final title = Text(label, style: Theme.of(context).textTheme.labelMedium);
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
        child: compact
            ? Row(
                children: [
                  Expanded(child: title),
                  controls,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 4), controls],
              ),
      );
    }
    final submenu = action['children'] is List;
    return _row(
      label: label,
      icon: appIconData(action['icon']),
      subtitle: action['subtitle'] as String?,
      value: action['valueLabel'] as String?,
      selected: action['selected'] == true,
      submenu: submenu,
      onTap: submenu
          ? () => setState(() => _path.add(label))
          : () => _dispatch(action, 'event'),
    );
  }

  Widget _choice(Map choice) {
    final selected = choice['selected'] == true;
    final colors = Theme.of(context).colorScheme;
    return NativeUi(
      child: Semantics(
        selected: selected,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            backgroundColor: selected ? colors.primary : null,
            foregroundColor: selected ? colors.onPrimary : null,
            side: selected ? BorderSide(color: colors.primary) : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => _dispatch(choice, 'event', keepOpen: true),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selected) ...[
                const UiIcon(Icons.check_rounded, size: 16),
                const SizedBox(width: 4),
              ],
              Flexible(child: Text('${choice['label']}')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row({
    required String label,
    required VoidCallback onTap,
    IconData? icon,
    String? subtitle,
    String? value,
    String? tooltip,
    bool selected = false,
    bool submenu = false,
  }) {
    Widget result = Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                if (icon != null) ...[
                  UiIcon(icon, size: 20),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (value != null &&
                          MediaQuery.textScalerOf(context).scale(14) > 20)
                        Text(
                          value,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (value != null &&
                    MediaQuery.textScalerOf(context).scale(14) <= 20) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                if (selected) const UiIcon(Icons.check_rounded, size: 20),
                if (submenu)
                  const UiIcon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) result = Tooltip(message: tooltip, child: result);
    return result;
  }
}

/// Queued clicks outlive the popup, but never the contribution's lease.
/// Resolve the latest callback immediately before each dispatch so a page's
/// asynchronous handler cannot coalesce already accepted menu interactions.
class _WorkspaceMenuDispatchQueue {
  _WorkspaceMenuDispatchQueue(this.controller, this.owner, this.lease);

  final WorkspaceHeaderController controller;
  final Object? owner;
  final WorkspaceHeaderLease? lease;
  Future<void> _tail = Future<void>.value();

  WorkspaceHeaderContent? get content =>
      identical(controller.lease, lease) &&
          lease?.isActive() == true &&
          identical(controller.content?.owner, owner)
      ? controller.content
      : null;

  void add(Object? event) {
    _tail = _tail
        .then((_) async {
          final current = content;
          if (current != null) await current.dispatch(event);
        })
        .catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'workspace header menu',
              context: ErrorDescription(
                'while dispatching a queued menu action',
              ),
            ),
          );
        });
  }
}
