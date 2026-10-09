import 'package:flutter/material.dart';

import 'ui_registration.dart';
import '../contracts/json_values.dart';
import 'ui_slot.dart';

enum UiPlacement { main, header, more, settings, hidden, page }

enum UiOpening { workspace, detail, adaptivePanel }

enum PageSlotKind { entries, tabs, sections }

class PageContext {
  const PageContext({this.taskId, this.projectId, this.values = const {}});

  final Map<String, Object?> values;

  final String? taskId;
  final String? projectId;

  String? value(String name) => switch (name) {
    'taskId' => taskId,
    'projectId' => projectId,
    _ => values[name] is String ? values[name] as String : null,
  };

  bool satisfies(Iterable<String> required) => required.every(
    (name) => name == 'taskId' || name == 'projectId'
        ? value(name)?.isNotEmpty == true
        : values[name] != null && values[name] != '',
  );

  String get identity =>
      '${taskId ?? ''}:${projectId ?? ''}:${canonicalJson(values)}';

  PageContext merge(PageContext other) => PageContext(
    taskId: other.taskId ?? taskId,
    projectId: other.projectId ?? projectId,
    values: {...values, ...other.values},
  );

  @override
  bool operator ==(Object other) =>
      other is PageContext &&
      other.taskId == taskId &&
      other.projectId == projectId &&
      canonicalJson(other.values) == canonicalJson(values);

  @override
  int get hashCode => Object.hash(taskId, projectId, canonicalJson(values));
}

class UiMount {
  const UiMount({
    this.placement = UiPlacement.main,
    this.pageId,
    this.slotId,
    this.order = 0,
    this.context = const PageContext(),
  });

  final UiPlacement placement;
  final String? pageId;
  final String? slotId;
  final int order;
  final PageContext context;

  @override
  bool operator ==(Object other) =>
      other is UiMount &&
      other.placement == placement &&
      other.pageId == pageId &&
      other.slotId == slotId &&
      other.order == order &&
      other.context == context;

  @override
  int get hashCode => Object.hash(placement, pageId, slotId, order, context);

  Map<String, Object?> toJson() => {
    'placement': placement.name,
    if (pageId != null) 'pageId': pageId,
    if (slotId != null) 'slotId': slotId,
    'order': order,
    if (context.taskId != null) 'taskId': context.taskId,
    if (context.projectId != null) 'projectId': context.projectId,
    if (context.values.isNotEmpty) 'values': context.values,
  };

  factory UiMount.fromJson(Map<String, Object?> json) {
    final placement = UiPlacement.values.byName(json['placement'] as String);
    if (placement == UiPlacement.page &&
        (json['pageId'] is! String || json['slotId'] is! String)) {
      throw const FormatException('Page mount requires pageId and slotId');
    }
    final order = json['order'] ?? 0;
    if (order is! int) throw const FormatException('Invalid mount order');
    return UiMount(
      placement: placement,
      pageId: json['pageId'] as String?,
      slotId: json['slotId'] as String?,
      order: order,
      context: PageContext(
        taskId: json['taskId'] as String?,
        projectId: json['projectId'] as String?,
        values: (json['values'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
    );
  }
}

class PageSlotDefinition {
  const PageSlotDefinition({
    required this.id,
    required this.label,
    this.kind = PageSlotKind.entries,
    this.isPublic = false,
    this.editable = true,
    this.capacity,
    this.requiredContext = const [],
  });

  final String id;
  final String label;
  final PageSlotKind kind;
  final bool isPublic;
  final bool editable;
  final int? capacity;
  final List<String> requiredContext;
}

typedef PageFactory = Widget Function(
  BuildContext context,
  PageContext pageContext,
);

class UiPageRegistration extends UiRegistration {
  const UiPageRegistration({
    required this.id,
    required this.moduleId,
    required this.title,
    required this.builder,
    this.slots = const [],
    this.requiredContext = const [],
    this.retainPosition = false,
    this.quickAdd = false,
    this.container = false,
    this.quickAddDefaults = const {},
    this.headerMode = 'standard',
  }) : super(UiSlot.workspacePage);

  final String id;
  final String moduleId;
  final String title;
  final PageFactory builder;
  final List<PageSlotDefinition> slots;
  final List<String> requiredContext;
  final bool retainPosition;
  final bool quickAdd;
  final bool container;
  final Map<String, Object?> quickAddDefaults;
  final String headerMode;
}

class UiEntryRegistration extends UiRegistration {
  const UiEntryRegistration({
    required this.id,
    required this.moduleId,
    required this.pageId,
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.opening = UiOpening.workspace,
    this.defaultMount = const UiMount(),
    this.content = false,
  }) : super(UiSlot.navigationPrimary);

  final String id;
  final String moduleId;
  final String pageId;
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final UiOpening opening;
  final UiMount defaultMount;
  final bool content;
}

String placementLabel(UiPlacement placement) => switch (placement) {
  UiPlacement.main => '主导航',
  UiPlacement.header => '顶部菜单',
  UiPlacement.more => '更多',
  UiPlacement.settings => '设置常用入口',
  UiPlacement.hidden => '隐藏',
  UiPlacement.page => '页面槽位',
};

class UiEntryActivationScope extends InheritedWidget {
  const UiEntryActivationScope({
    super.key,
    required super.child,
    required this.open,
  });

  final void Function(UiEntryRegistration entry, PageContext context) open;

  static UiEntryActivationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UiEntryActivationScope>();

  @override
  bool updateShouldNotify(UiEntryActivationScope oldWidget) =>
      open != oldWidget.open;
}
