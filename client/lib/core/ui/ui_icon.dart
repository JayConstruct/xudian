import 'package:flutter/material.dart';

import 'ui_icons.dart';
import 'ui_component.dart';

/// App-owned icons participate in the same public UI selection as controls.
/// Recipe icon primitives use AppSymbolIcon directly to avoid recursion.
class UiIcon extends StatelessWidget {
  const UiIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
    this.selected = false,
  });
  final IconData? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;
  final bool selected;

  @override
  Widget build(BuildContext context) => UiComponent(
    ref: 'ui.icon@1',
    props: {
      'name': appIconName(icon),
      'size': size ?? IconTheme.of(context).size ?? 24,
      'selected': selected,
      if (color != null)
        'color': '#${color!.toARGB32().toRadixString(16).padLeft(8, '0')}',
      if (semanticLabel != null) 'semanticLabel': semanticLabel,
    },
    fallback: AppIcon(
      icon,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
      selected: selected,
    ),
  );
}
