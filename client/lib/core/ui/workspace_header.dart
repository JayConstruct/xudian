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
  final _menuSessions =
      <Object, ({WorkspaceHeaderLease lease, Object owner})>{};

  /// Native popups cover their page route while retaining the active lease.
  /// This grants visibility for publishing updates, never event authority.
  Object? beginMenu(WorkspaceHeaderLease? source, Object? owner) {
    if (source == null ||
        owner == null ||
        !identical(source, lease) ||
        !source.isActive() ||
        !identical(content?.owner, owner)) {
      return null;
    }
    final token = Object();
    _menuSessions[token] = (lease: source, owner: owner);
    return token;
  }

  void endMenu(Object? token) => _menuSessions.remove(token);

  bool isMenuOpenFor(WorkspaceHeaderLease? source, Object owner) =>
      source != null &&
      identical(source, lease) &&
      source.isActive() &&
      identical(content?.owner, owner) &&
      _menuSessions.values.any(
        (session) =>
            identical(session.lease, source) && identical(session.owner, owner),
      );

  WorkspaceHeaderLease? activate({
    required String identity,
    required String moduleId,
    required String pageId,
    required bool enabled,
    String mode = 'contributed',
    required bool Function() isActive,
  }) {
    if (!enabled) {
      _menuSessions.clear();
      lease = null;
      content = null;
    } else if (lease?.identity != identity || lease?.mode != mode) {
      _menuSessions.clear();
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
    String? todayDate,
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
        content?.spec['todayDate'] == todayDate &&
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
      'todayDate': ?todayDate,
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
          (spec['compact'] != null && spec['compact'] is! bool) ||
          (spec['leading'] != null &&
              (spec['leading'] is! Map ||
                  (spec['leading'] as Map)['label'] is! String)) ||
          (spec['titleEvent'] != null && spec['titleEvent'] is! Map) ||
          (spec['backEvent'] != null && spec['backEvent'] is! Map) ||
          (spec['actions'] != null &&
              !validWorkspaceHeaderActions(spec['actions']))) {
        throw const FormatException('Invalid workspace header');
      }
    }
    _menuSessions.removeWhere(
      (_, session) => spec == null || !identical(session.owner, owner),
    );
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
    _menuSessions.removeWhere((_, session) => identical(session.owner, owner));
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
    _menuSessions.clear();
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

/// Bounded, recursive action schema shared by contributed workspace menus.
bool validWorkspaceHeaderActions(Object? value) {
  var count = 0;
  bool valid(Object? raw, int depth) {
    if (raw is! Map || depth > 4 || ++count > 64) return false;
    bool text(String key, {bool required = false}) =>
        raw[key] == null && !required ||
        raw[key] is String &&
            (raw[key] as String).isNotEmpty &&
            (raw[key] as String).length <= 256;
    if (!text('label', required: true) ||
        !text('icon') ||
        !text('subtitle') ||
        !text('valueLabel')) {
      return false;
    }
    for (final key in [
      'iconOnly',
      'overflowOnly',
      'selected',
      'separatorBefore',
      'decreaseEnabled',
      'increaseEnabled',
    ]) {
      if (raw[key] != null && raw[key] is! bool) return false;
    }
    if (raw['presentation'] != null &&
        !const {'inline', 'menu'}.contains(raw['presentation'])) {
      return false;
    }
    if (raw['variant'] != null &&
        !const {'filled', 'tonal', 'text'}.contains(raw['variant'])) {
      return false;
    }
    if (raw['iconOnly'] == true && raw['icon'] is! String) return false;
    if (raw['presentation'] == 'inline' &&
        (raw['event'] is! Map ||
            raw['children'] != null ||
            raw['kind'] != null)) {
      return false;
    }
    final kind = raw['kind'];
    if (kind != null && !const {'choiceGrid', 'stepper'}.contains(kind)) {
      return false;
    }
    if (kind == 'stepper') {
      return raw['children'] == null &&
          raw['decreaseEvent'] is Map &&
          raw['increaseEvent'] is Map;
    }
    final children = raw['children'];
    if (children != null) {
      return children is List &&
          children.isNotEmpty &&
          children.length <= 16 &&
          children.every(
            (child) =>
                valid(child, depth + 1) &&
                (kind != 'choiceGrid' ||
                    child is Map &&
                        child['event'] is Map &&
                        child['kind'] == null &&
                        child['children'] == null),
          );
    }
    return kind == null && raw['event'] is Map;
  }

  return value is List &&
      value.length <= 12 &&
      value.every((action) => valid(action, 0));
}
