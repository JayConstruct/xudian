import 'package:flutter/material.dart';

import '../modules/module_registry.dart';
import 'ui_registration.dart';
import 'ui_slot.dart';

class GlobalOverlayHost extends StatefulWidget {
  const GlobalOverlayHost({
    super.key,
    required this.registry,
    required this.child,
  });

  final ModuleRegistry registry;
  final Widget child;

  @override
  State<GlobalOverlayHost> createState() => _GlobalOverlayHostState();
}

class _GlobalOverlayHostState extends State<GlobalOverlayHost> {
  @override
  void initState() {
    super.initState();
    widget.registry.addListener(_changed);
  }

  @override
  void didUpdateWidget(GlobalOverlayHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registry != widget.registry) {
      oldWidget.registry.removeListener(_changed);
      widget.registry.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.registry.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: widget.child),
      for (final overlay
          in widget.registry.ui
              .forSlot(UiSlot.globalOverlay)
              .whereType<WidgetRegistration>())
        Positioned.fill(
          key: ValueKey(overlay.id),
          child: overlay.builder(context),
        ),
    ],
  );
}
