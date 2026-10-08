import 'package:flutter/material.dart';

/// A lease belongs to one active workspace and one actual runtime instance.
/// Nested pages and late responses cannot replace the host's current header.
class WorkspaceHeaderLease {
  WorkspaceHeaderLease(
    this.identity,
    this.moduleId,
    this.pageId,
    this.isActive,
  );
  final String identity, moduleId, pageId;
  final bool Function() isActive;
}

class WorkspaceHeaderContent {
  WorkspaceHeaderContent(this.spec, this.dispatch, this.owner);
  final Map<String, Object?> spec;
  final Future<void> Function(Object?) dispatch;
  final Object owner;
}

class WorkspaceHeaderController extends ChangeNotifier {
  WorkspaceHeaderLease? lease;
  WorkspaceHeaderContent? content;
  bool _scheduled = false, _disposed = false;

  WorkspaceHeaderLease? activate({
    required String identity,
    required String moduleId,
    required String pageId,
    required bool enabled,
    required bool Function() isActive,
  }) {
    if (!enabled) {
      lease = null;
      content = null;
    } else if (lease?.identity != identity) {
      lease = WorkspaceHeaderLease(identity, moduleId, pageId, isActive);
      content = null;
    }
    return lease;
  }

  void publish(
    WorkspaceHeaderLease source,
    Object owner,
    Map<String, Object?>? spec,
    Future<void> Function(Object?) dispatch,
  ) {
    if (!identical(source, lease) || !source.isActive()) return;
    if (spec != null) {
      if (spec['title'] is! String ||
          (spec['title'] as String).isEmpty ||
          (spec['title'] as String).length > 256 ||
          (spec['autoHideChrome'] != null && spec['autoHideChrome'] is! bool) ||
          (spec['leading'] != null &&
              (spec['leading'] is! Map ||
                  (spec['leading'] as Map)['label'] is! String)) ||
          (spec['titleEvent'] != null && spec['titleEvent'] is! Map) ||
          (spec['actions'] != null &&
              (spec['actions'] is! List ||
                  (spec['actions'] as List).any(
                    (action) =>
                        action is! Map ||
                        action['label'] is! String ||
                        action['event'] is! Map,
                  )))) {
        throw const FormatException('Invalid workspace header');
      }
    }
    content = spec == null
        ? null
        : WorkspaceHeaderContent(spec, (event) async {
            if (identical(source, lease) &&
                source.isActive() &&
                identical(content?.owner, owner)) {
              await dispatch(event);
            }
          }, owner);
    _notifyLater();
  }

  void clear(Object owner) {
    if (!identical(content?.owner, owner)) return;
    content = null;
    _notifyLater();
  }

  void _notifyLater() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class WorkspaceHeaderScope extends InheritedWidget {
  const WorkspaceHeaderScope({
    super.key,
    required this.controller,
    required this.lease,
    required super.child,
  });
  final WorkspaceHeaderController controller;
  final WorkspaceHeaderLease? lease;
  static WorkspaceHeaderScope? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WorkspaceHeaderScope>();
  @override
  bool updateShouldNotify(WorkspaceHeaderScope oldWidget) =>
      oldWidget.lease != lease;
}
