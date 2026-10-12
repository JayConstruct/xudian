import 'package:flutter/material.dart';

import 'page_runtime_context.dart';

/// A lease belongs to one page in a workspace or detail route.
/// Nested pages and late responses cannot replace another page's header.
class WorkspaceHeaderLease {
  WorkspaceHeaderLease(
    this.identity,
    this.moduleId,
    this.pageId,
    this.isActive, [
    this.mode = 'contributed',
  ]);
  final String identity, moduleId, pageId, mode;
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
    String mode = 'contributed',
    required bool Function() isActive,
  }) {
    if (!enabled) {
      lease = null;
      content = null;
    } else if (lease?.identity != identity || lease?.mode != mode) {
      lease = WorkspaceHeaderLease(identity, moduleId, pageId, isActive, mode);
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
    if (source.mode != 'contributed') return;
    _publish(source, owner, spec, dispatch);
  }

  /// Date headers belong to the root composition host, never a page script.
  void publishDate(
    WorkspaceHeaderLease source,
    Object owner,
    Object? date, {
    Future<void> Function(Object?)? dispatch,
  }) {
    if (source.mode != 'date' ||
        !identical(source, lease) ||
        !source.isActive()) {
      return;
    }
    final title = formatWorkspaceDate(date) ?? '';
    if (identical(content?.owner, owner) &&
        content?.spec['title'] == title &&
        content?.spec['selectedDate'] == date &&
        (content?.spec['dateNavigation'] == true) == (dispatch != null)) {
      return;
    }
    // Empty context keeps the leased title area reserved until the first
    // selectedDate arrives, matching contributed-header startup behavior.
    if (title.isEmpty) {
      clear(owner);
      return;
    }
    _publish(source, owner, {
      'title': title,
      'selectedDate': date,
      if (dispatch != null) 'dateNavigation': true,
    }, dispatch ?? (_) async {});
  }

  void _publish(
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
          (spec['backEvent'] != null && spec['backEvent'] is! Map) ||
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

/// Civil-date titles follow selectedDate, independent of any business module.
String? formatWorkspaceDate(Object? raw, {DateTime? today}) {
  try {
    validateRuntimeContextPatch({'selectedDate': raw});
  } on FormatException {
    return null;
  }
  final date = DateTime.parse(raw as String);
  final reference = today ?? DateTime.now();
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${date.year == reference.year ? '' : '${date.year}年'}${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';
}
