import 'package:flutter/material.dart';

import 'app_destination.dart';
import 'ui_composition.dart' show PageContext;
import 'ui_slot.dart';

abstract class UiRegistration {
  const UiRegistration(this.slot);

  final UiSlot slot;
}

class NavigationRegistration extends UiRegistration {
  const NavigationRegistration(this.destination)
    : super(UiSlot.navigationPrimary);

  final AppDestination destination;
}

class WidgetRegistration extends UiRegistration {
  const WidgetRegistration(super.slot, this.id, this.builder);

  final String id;
  final WidgetBuilder builder;
}

/// A workspace chooses its assistant from the capabilities of its content.
/// Opening stays module-owned; availability never requires a network request.
class WorkspaceAssistantRegistration extends UiRegistration {
  const WorkspaceAssistantRegistration({
    required this.id,
    required this.label,
    required this.onOpen,
    required this.supports,
  }) : super(UiSlot.workspaceAssistant);

  final String id, label;
  final Future<void> Function(BuildContext context, PageContext pageContext)
  onOpen;
  final bool Function(Set<String> moduleIds) supports;
}
