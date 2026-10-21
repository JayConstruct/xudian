import 'package:flutter/material.dart';

/// Equal-width choices wrap on narrow or large-text layouts without clipping.
class ScriptSegmentedControl extends StatelessWidget {
  const ScriptSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimum = MediaQuery.textScalerOf(context).scale(16) * 4 + 24;
        final columns = (constraints.maxWidth / minimum).floor().clamp(
          1,
          labels.length,
        );
        final width = (constraints.maxWidth - 8) / columns;
        return Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Wrap(
              children: [
                for (var index = 0; index < labels.length; index++)
                  SizedBox(
                    width: width,
                    child: Semantics(
                      selected: selectedIndex == index,
                      button: true,
                      child: Material(
                        color: selectedIndex == index
                            ? scheme.primary.withValues(alpha: .12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(11),
                          onTap: onSelected == null
                              ? null
                              : () => onSelected!(index),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 10,
                              ),
                              child: Text(
                                labels[index],
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: selectedIndex == index
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                  fontWeight: selectedIndex == index
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
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
  const ScriptNotice({super.key, required this.text, this.tone = 'info'});

  final String text, tone;

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(color: foreground),
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
