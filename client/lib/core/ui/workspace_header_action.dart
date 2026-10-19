import 'package:flutter/material.dart';

import 'native_ui.dart';
import 'ui_icon.dart';
import 'ui_icons.dart';

/// Optional shortcuts; actions that do not fit remain in the host menu.
/// Measuring the real labels keeps large text and narrow headers usable.
List<Map<String, Object?>> fittingHeaderActions(
  BuildContext context,
  List<Map<String, Object?>> actions,
  double availableWidth,
) {
  final candidates = actions
      .where((action) => action['presentation'] == 'inline')
      .take(2)
      .toList();
  final selected = <Map<String, Object?>>[];
  final prioritized = [...candidates]
    ..sort(
      (a, b) => (b['variant'] == 'filled' ? 1 : 0).compareTo(
        a['variant'] == 'filled' ? 1 : 0,
      ),
    );
  for (final action in prioritized) {
    var width = 48.0;
    if (action['iconOnly'] != true &&
        (action['variant'] == 'filled' || action['variant'] == 'tonal')) {
      final painter = TextPainter(
        text: TextSpan(
          text: '${action['label']}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )..layout();
      width = painter.width + 28 + (action['icon'] == null ? 0 : 24);
      painter.dispose();
    }
    if (availableWidth >= width + 4) {
      selected.add(action);
      availableWidth -= width + 4;
    }
  }
  return candidates.where(selected.contains).toList();
}

class WorkspaceHeaderAction extends StatelessWidget {
  const WorkspaceHeaderAction({
    super.key,
    required this.action,
    required this.onPressed,
  });

  final Map<String, Object?> action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = '${action['label']}';
    final icon = appIconData(action['icon']);
    final variant = action['variant'];
    if (action['iconOnly'] == true) {
      final style = IconButton.styleFrom(
        minimumSize: const Size.square(kMinInteractiveDimension),
        fixedSize: const Size.square(kMinInteractiveDimension),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );
      final child = UiIcon(icon ?? Icons.more_horiz, size: 22);
      return NativeUi(
        child: variant == 'filled'
            ? IconButton.filled(
                tooltip: label,
                onPressed: onPressed,
                style: style,
                icon: child,
              )
            : variant == 'tonal'
            ? IconButton.filledTonal(
                tooltip: label,
                onPressed: onPressed,
                style: style,
                icon: child,
              )
            : IconButton(
                tooltip: label,
                onPressed: onPressed,
                style: style,
                icon: child,
              ),
      );
    }
    if (variant != 'filled' && variant != 'tonal') {
      return NativeUi(
        child: IconButton(
          tooltip: label,
          onPressed: onPressed,
          icon: UiIcon(icon ?? Icons.more_horiz, size: 20),
        ),
      );
    }
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[UiIcon(icon, size: 18), const SizedBox(width: 6)],
        Text(label, maxLines: 1),
      ],
    );
    final style = FilledButton.styleFrom(
      minimumSize: const Size(48, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    return NativeUi(
      child: variant == 'tonal'
          ? FilledButton.tonal(onPressed: onPressed, style: style, child: child)
          : FilledButton(onPressed: onPressed, style: style, child: child),
    );
  }
}
