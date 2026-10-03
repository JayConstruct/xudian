import 'package:flutter/material.dart';

typedef DestinationBuilder = Widget Function(BuildContext context);

class AppDestination {
  const AppDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
    this.quickAdd = false,
    this.quickAddDefaults = const {},
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final DestinationBuilder builder;
  final bool quickAdd;
  final Map<String, Object?> quickAddDefaults;
}
