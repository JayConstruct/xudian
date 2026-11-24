import 'script_content_widgets.dart' show scriptToneSurface;

import 'package:flutter/material.dart';

import 'sliding_segments.dart';

class ScriptSegmentedControl extends StatelessWidget {
  const ScriptSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.scrollable = false,
    this.compact = false,
    this.icons = const [],
  });
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int>? onSelected;
  final bool scrollable, compact;
  final List<IconData?> icons;

  @override
  Widget build(BuildContext context) => SlidingSegments<int>(
    segments: [
      for (final (i, label) in labels.indexed)
        ButtonSegment(
          value: i,
          label: Text(label),
          icon: i < icons.length && icons[i] != null
              ? Icon(icons[i], size: 15)
              : null,
        ),
    ],
    selected: selectedIndex,
    minSegmentHeight: compact ? 32 : 48,
    onChanged: onSelected,
    scrollable: scrollable,
  );
}

class ScriptFormSection extends StatelessWidget {
  const ScriptFormSection({
    super.key,
    required this.title,
    required this.children,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final List<Widget> children;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (actionLabel != null)
              Flexible(
                child: TextButton(
                  onPressed: onAction,
                  child: Text(actionLabel!, textAlign: TextAlign.end),
                ),
              ),
          ],
        ),
      ),
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) const SizedBox(height: 4),
        children[index],
      ],
    ],
  );
}

class ScriptNotice extends StatelessWidget {
  const ScriptNotice({
    super.key,
    required this.text,
    this.tone = 'info',
    this.action,
  });

  final String text, tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = tone == 'warning'
        ? scheme.error
        : tone == 'success'
        ? scheme.primary
        : scheme.onSurfaceVariant;
    return Semantics(
      liveRegion: tone == 'warning',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: action == null ? 10 : 0,
        ),
        decoration: BoxDecoration(
          color: tone == 'accent' || (action != null && tone == 'warning')
              ? scriptToneSurface(context, tone)
              : foreground.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(12),
        ),
        child: action == null
            ? Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(color: foreground),
              )
            : Row(
                children: [
                  Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
                  action!,
                ],
              ),
      ),
    );
  }
}

class ScriptChoiceCard extends StatelessWidget {
  const ScriptChoiceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
  });

  final String title, subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      enabled: onTap != null,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: .10)
            : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected
                ? Colors.transparent
                : scheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ScriptFieldLabel extends StatelessWidget {
  const ScriptFieldLabel({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 5),
      Semantics(label: label, child: child),
    ],
  );
}
