import 'package:flutter/material.dart';

import 'app_destination.dart';
import 'ui_slot.dart';

sealed class UiRegistration {
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
