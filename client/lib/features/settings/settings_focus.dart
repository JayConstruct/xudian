import 'package:flutter/material.dart';

/// A destination may request a row without activating its setting.
class SettingsFocus extends InheritedWidget {
  const SettingsFocus({super.key, required this.label, required super.child});
  final String label;

  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsFocus>()?.label;

  @override
  bool updateShouldNotify(SettingsFocus oldWidget) => oldWidget.label != label;
}

class SettingsAnchor extends StatefulWidget {
  const SettingsAnchor(this.label, {super.key, required this.child});
  final String label;
  final Widget child;

  @override
  State<SettingsAnchor> createState() => _SettingsAnchorState();
}

class _SettingsAnchorState extends State<SettingsAnchor> {
  bool active = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final selected = SettingsFocus.of(context) == widget.label;
    if (selected && !active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Scrollable.ensureVisible(context, alignment: .35);
      });
    }
    active = selected;
  }

  @override
  Widget build(BuildContext context) => active
      ? DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 1.6,
            ),
          ),
          child: widget.child,
        )
      : widget.child;
}
