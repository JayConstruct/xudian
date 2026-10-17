import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A drag signal is scoped to one active workspace generation. Retained pages
/// and late disposal callbacks cannot change the current workspace's chrome.
class WorkspaceInteractionLease {
  WorkspaceInteractionLease._(this.identity, this.isActive);
  final String identity;
  final bool Function() isActive;
}

class WorkspaceInteractionController extends ChangeNotifier {
  WorkspaceInteractionLease? _lease;
  final Set<Object> _dragOwners = {};
  bool _disposed = false, _scheduled = false;
  bool get dragging => _dragOwners.isNotEmpty;

  WorkspaceInteractionLease activate(
    String identity,
    bool Function() isActive,
  ) {
    if (_lease?.identity != identity) {
      _lease = WorkspaceInteractionLease._(identity, isActive);
      _dragOwners.clear();
    }
    return _lease!;
  }

  void setDragging(WorkspaceInteractionLease source, Object owner, bool value) {
    if (_disposed || !identical(source, _lease) || !source.isActive()) return;
    final changed = value ? _dragOwners.add(owner) : _dragOwners.remove(owner);
    if (changed) _notify();
  }

  void releaseOwner(WorkspaceInteractionLease source, Object owner) {
    if (_disposed || !identical(source, _lease)) return;
    if (_dragOwners.remove(owner)) _notify();
  }

  void _notify() {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _dragOwners.clear();
    super.dispose();
  }
}

class WorkspaceInteractionScope extends InheritedWidget {
  const WorkspaceInteractionScope({
    super.key,
    required this.controller,
    required this.lease,
    required super.child,
  });
  final WorkspaceInteractionController controller;
  final WorkspaceInteractionLease lease;
  static WorkspaceInteractionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceInteractionScope>();
  @override
  bool updateShouldNotify(WorkspaceInteractionScope oldWidget) =>
      !identical(controller, oldWidget.controller) ||
      !identical(lease, oldWidget.lease);
}

/// Each region owns its drag signal. A board is free to cancel or disappear at
/// any moment without leaving the dock hidden for the next page.
class WorkspaceDragRegion extends StatefulWidget {
  const WorkspaceDragRegion({super.key, required this.builder});
  final Widget Function(
    BuildContext context,
    ValueChanged<bool> onDragActiveChanged,
  )
  builder;
  @override
  State<WorkspaceDragRegion> createState() => _WorkspaceDragRegionState();
}

class _WorkspaceDragRegionState extends State<WorkspaceDragRegion> {
  WorkspaceInteractionScope? _scope;
  bool _active = false;
  void _release() {
    final scope = _scope;
    if (scope != null) scope.controller.releaseOwner(scope.lease, this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = WorkspaceInteractionScope.maybeOf(context);
    final active =
        TickerMode.valuesOf(context).enabled &&
        ModalRoute.isCurrentOf(context) != false;
    if (!identical(scope?.controller, _scope?.controller) ||
        !identical(scope?.lease, _scope?.lease) ||
        !active) {
      _release();
    }
    _scope = scope;
    _active = active;
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    // Capture this lease, rather than reading the newest lease in a late call.
    return widget.builder(context, (dragging) {
      if (!mounted ||
          !_active ||
          scope == null ||
          !identical(scope.lease, _scope?.lease)) {
        return;
      }
      scope.controller.setDragging(scope.lease, this, dragging);
    });
  }

  @override
  void deactivate() {
    _active = false;
    _release();
    super.deactivate();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }
}

/// Paint-only dock motion: drag state never changes the workspace viewport or
/// its reserved bottom inset. Input and semantics stop as soon as dragging starts.
class WorkspaceInteractionDock extends StatelessWidget {
  const WorkspaceInteractionDock({
    super.key,
    required this.controller,
    required this.child,
  });
  final WorkspaceInteractionController controller;
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: child,
    builder: (context, child) {
      final hidden = controller.dragging;
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180);
      return IgnorePointer(
        ignoring: hidden,
        child: ExcludeSemantics(
          excluding: hidden,
          child: AnimatedSlide(
            key: const ValueKey('workspace-drag-dock-slide'),
            offset: Offset(0, hidden ? 1.5 : 0),
            duration: duration,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              key: const ValueKey('workspace-drag-dock-opacity'),
              opacity: hidden ? 0 : 1,
              duration: duration,
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
