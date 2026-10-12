import 'package:flutter/material.dart';

import 'ui_registration.dart';
import 'page_runtime_context.dart';
import '../contracts/json_values.dart';
import 'ui_slot.dart';

enum UiPlacement { main, header, more, settings, hidden, page }

enum UiOpening { workspace, detail, adaptivePanel }

enum PageSlotKind { entries, tabs, sections }

/// Generic page parameters. Entity references belong in `values['entities']`
/// and are validated explicitly; a legacy ID alone does not identify an owner.
class PageContext {
  /// Legacy named IDs remain accepted for const source compatibility. When
  /// present they override the same keys in [values]. All public operations
  /// consume the normalized [values] map, regardless of how it was supplied.
  const PageContext({
    String? taskId,
    String? projectId,
    Map<String, Object?> values = const {},
  }) : _legacyTaskId = taskId,
       _legacyProjectId = projectId,
       // Keep the public `values` parameter name for const call-site compatibility.
       // ignore: prefer_initializing_formals
       _values = values;

  final Map<String, Object?> _values;
  final String? _legacyTaskId;
  final String? _legacyProjectId;

  Map<String, Object?> get values => Map.unmodifiable({
    ..._values,
    if (_legacyTaskId != null) 'taskId': _legacyTaskId,
    if (_legacyProjectId != null) 'projectId': _legacyProjectId,
  });

  /// Compatibility aliases for parameters used by older page contracts.
  String? get taskId => value('taskId');
  String? get projectId => value('projectId');

  String? value(String name) {
    final raw = values[name];
    return raw is String ? raw : null;
  }

  bool satisfies(Iterable<String> required) {
    final parameters = values;
    return required.every(
      (name) => parameters[name] != null && parameters[name] != '',
    );
  }

  String get identity => canonicalJson(values);

  String get navigationIdentity =>
      canonicalJson(withoutRuntimePageContext(values));

  PageContext merge(PageContext other) =>
      PageContext(values: {...values, ...other.values});

  /// Flat script parameters; the same keys are used for every module.
  Map<String, Object?> toJson() => values;

  /// Preserve the persisted layout format used by older app versions. The
  /// compatibility keys are emitted at the top level, other parameters under
  /// `values`, so existing layouts can continue to round-trip unchanged.
  Map<String, Object?> toLayoutJson() {
    final parameters = {...values};
    final legacyTaskId = parameters['taskId'];
    final legacyProjectId = parameters['projectId'];
    if (legacyTaskId is String) parameters.remove('taskId');
    if (legacyProjectId is String) parameters.remove('projectId');
    return {
      if (legacyTaskId is String) 'taskId': legacyTaskId,
      if (legacyProjectId is String) 'projectId': legacyProjectId,
      if (parameters.isNotEmpty) 'values': parameters,
    };
  }

  /// Adapt persisted layouts and older entry declarations at their boundary.
  /// Explicit top-level IDs take precedence over duplicate `values` keys.
  factory PageContext.fromLayoutJson(Map<String, Object?> json) => PageContext(
    taskId: json['taskId'] as String?,
    projectId: json['projectId'] as String?,
    values: (json['values'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  @override
  bool operator ==(Object other) =>
      other is PageContext &&
      canonicalJson(other.values) == canonicalJson(values);

  @override
  int get hashCode => canonicalJson(values).hashCode;
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
    ...context.toLayoutJson(),
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
      context: PageContext.fromLayoutJson(json),
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
    this.inline = false,
    this.capacity,
    this.requiredContext = const [],
  }) : assert(!inline || kind == PageSlotKind.sections);

  final String id;
  final String label;
  final PageSlotKind kind;
  final bool isPublic;
  final bool editable;
  final bool inline;
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
    this.initializesRuntimeContext = false,
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

  /// The container renders its initializer before mounting date contributions.
  final bool initializesRuntimeContext;
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

/// Contributions in an inline section use their natural height and share the
/// enclosing page's scrollable instead of creating a separate page viewport.
class UiPageContentScope extends InheritedWidget {
  const UiPageContentScope({
    super.key,
    required this.inline,
    required super.child,
  });

  final bool inline;

  static bool inlineOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<UiPageContentScope>()
          ?.inline ??
      false;

  @override
  bool updateShouldNotify(UiPageContentScope oldWidget) =>
      inline != oldWidget.inline;
}
