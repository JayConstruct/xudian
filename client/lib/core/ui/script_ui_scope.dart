import 'package:flutter/material.dart';

/// Page-local resources. Neither animation frames nor gesture progress cross JS.
class ScriptUiResources {
  final _animations = <Object>{};
  final _open = <Object, (Object, VoidCallback)>{};
  int skippedAnimations = 0;
  int get activeAnimations => _animations.length;

  bool acquire(Object owner) {
    if (_animations.contains(owner)) return true;
    if (_animations.length >= 64) {
      skippedAnimations++;
      return false;
    }
    return _animations.add(owner);
  }

  void release(Object owner) => _animations.remove(owner);
  void open(Object group, Object owner, VoidCallback close) {
    final previous = _open[group];
    _open[group] = (owner, close);
    if (previous != null && !identical(previous.$1, owner)) previous.$2();
  }

  void forget(Object owner) =>
      _open.removeWhere((_, value) => identical(value.$1, owner));
}

class ScriptUiScope extends StatefulWidget {
  const ScriptUiScope({
    super.key,
    required this.active,
    required this.busy,
    required this.child,
  });
  final bool active, busy;
  final Widget child;

  static ScriptUiEnvironment? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScriptUiEnvironment>();

  @override
  State<ScriptUiScope> createState() => _ScriptUiScopeState();
}

class _ScriptUiScopeState extends State<ScriptUiScope>
    with WidgetsBindingObserver {
  final resources = ScriptUiResources();
  bool foreground = true;

  @override
  void initState() {
    super.initState();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScriptUiEnvironment(
    active: foreground && widget.active,
    busy: widget.busy,
    resources: resources,
    child: widget.child,
  );
}

class ScriptUiEnvironment extends InheritedWidget {
  const ScriptUiEnvironment({
    super.key,
    required this.active,
    required this.busy,
    required this.resources,
    required super.child,
  });
  final bool active, busy;
  final ScriptUiResources resources;
  @override
  bool updateShouldNotify(ScriptUiEnvironment oldWidget) =>
      active != oldWidget.active ||
      busy != oldWidget.busy ||
      !identical(resources, oldWidget.resources);
}
