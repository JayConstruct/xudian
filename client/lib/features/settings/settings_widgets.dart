export '../../core/ui/sliding_segments.dart';
import '../../core/ui/native_ui.dart';
import '../../core/ui/ui_icon.dart';
import 'settings_focus.dart';

import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../core/ui/ui_component.dart';

class SettingsList extends StatelessWidget {
  const SettingsList({
    super.key,
    required this.children,
    this.footer,
    this.horizontalPadding = AppDesign.pageGutter,
  });
  final List<Widget> children;

  final Widget? footer;
  final double horizontalPadding;

  static EdgeInsets contentPadding({
    double horizontal = AppDesign.pageGutter,
    double bottomInset = 0,
    bool edgeToEdge = false,
  }) => EdgeInsets.fromLTRB(
    edgeToEdge ? 0 : horizontal,
    edgeToEdge ? 0 : 8,
    edgeToEdge ? 0 : horizontal,
    32 + bottomInset,
  );

  @override
  Widget build(BuildContext context) {
    final list = SingleChildScrollView(
      padding: contentPadding(horizontal: horizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    if (footer == null) return list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: list),
        SettingsFooter(child: footer!),
      ],
    );
  }
}

class SettingsFooter extends StatelessWidget {
  const SettingsFooter({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.pageGutter,
        0,
        AppDesign.pageGutter,
        5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(
            height: 1,
            thickness: .65,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 8),
          OutlinedButtonTheme(
            data: OutlinedButtonThemeData(
              style:
                  (OutlinedButtonTheme.of(context).style ?? const ButtonStyle())
                      .copyWith(
                        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                        backgroundColor: WidgetStatePropertyAll(
                          Theme.of(context).colorScheme.surface,
                        ),
                      ),
            ),
            child: child,
          ),
        ],
      ),
    ),
  );
}

class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        fontSize: 13.3,
        height: 1.5,
        fontWeight: FontWeight.w600,
        color: AppDesign.muted(context),
      ),
    ),
  );
}

class SettingsSearchField extends StatelessWidget {
  const SettingsSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.autofocus = false,
    this.fieldKey,
  });
  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final bool autofocus;
  final Key? fieldKey;
  @override
  Widget build(BuildContext context) {
    return NativeUi(
      child: TextField(
        key: fieldKey,
        controller: controller,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        onChanged: (_) => onChanged(),
        decoration:
            AppDesign.outlinedField(
              context,
              search: true,
              highlighted: controller.text.isNotEmpty,
            ).copyWith(
              hintText: hint,
              prefixIcon: const UiIcon(Icons.search, size: 19),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      icon: const UiIcon(Icons.close, size: 16),
                      onPressed: () {
                        controller.clear();
                        onChanged();
                      },
                    ),
            ),
      ),
    );
  }
}

class SettingsGroupSurface extends StatelessWidget {
  const SettingsGroupSurface({
    super.key,
    required this.children,
    this.dividerIndent = SettingsListTileTheme.textIndent,
    this.insertDividers = true,
    this.mainAxisSize = MainAxisSize.max,
  });
  final List<Widget> children;
  final double dividerIndent;
  final bool insertDividers;
  final MainAxisSize mainAxisSize;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: c.surface,
      shape: AppDesign.smoothShape(
        radius: 17,
        side: BorderSide(color: c.outlineVariant, width: .8),
      ),
      clipBehavior: Clip.antiAlias,
      child: SettingsListTileTheme(
        child: Column(
          mainAxisSize: mainAxisSize,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (insertDividers && i > 0)
                SettingsDivider(indent: dividerIndent),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({
    super.key,
    this.indent = SettingsListTileTheme.textIndent,
    this.height,
  });

  final double indent;
  final double? height;

  @override
  Widget build(BuildContext context) => Divider(
    height: height ?? .65,
    thickness: .65,
    indent: indent,
    endIndent: 15,
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

class SettingsListTileTheme extends StatelessWidget {
  const SettingsListTileTheme({super.key, required this.child});
  final Widget child;
  static const horizontalPadding = 14.0;
  static const glyphSize = 32.0;
  static const titleGap = 12.0;
  static const textIndent = horizontalPadding + glyphSize + titleGap;
  static const singleLineHeight = 50.0;
  static const twoLineHeight = 62.0;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTileTheme.merge(
      contentPadding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
      minLeadingWidth: glyphSize,
      // Two-line ListTiles use their text height and vertical padding on Android.
      minVerticalPadding: 11.5,
      minTileHeight: singleLineHeight,
      horizontalTitleGap: titleGap,
      titleTextStyle: TextStyle(
        fontSize: 15.3,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontSize: 12.1,
        height: 1.45,
        color: colors.onSurfaceVariant,
      ),
      child: child,
    );
  }
}

class SettingsGroup extends StatelessWidget {
  static const spacing = 22.0;
  static const headingGap = 10.0;
  const SettingsGroup({
    super.key,
    required this.children,
    this.title,
    this.dividerIndent = SettingsListTileTheme.textIndent,
    this.bottomSpacing = spacing,
  });
  final double bottomSpacing, dividerIndent;
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            SettingsHeading(title!),
            const SizedBox(height: headingGap),
          ],
          SettingsGroupSurface(
            dividerIndent: dividerIndent,
            children: children,
          ),
        ],
      ),
    );
    return SettingsAnchor(
      title ?? '',
      child: UiComponent(
        ref: 'ui.nativeSection@1',
        props: {'title': title ?? ''},
        slots: {'content': content},
        fallback: content,
      ),
    );
  }
}

class SettingsEntry extends StatelessWidget {
  const SettingsEntry({
    super.key,
    required this.title,
    required this.icon,
    this.onTap,
    this.trailingIcon = Icons.chevron_right_rounded,
    this.tileKey,
    this.trailing,
    this.subtitle,
    this.protected = false,
    this.enabled = true,
    this.selected = false,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final IconData trailingIcon;
  final Widget? trailing;
  final Key? tileKey;
  final bool protected;
  final bool enabled;
  final bool selected;

  @override
  Widget build(BuildContext context) => SettingsAnchor(
    title,
    child: UiComponent(
      ref: 'ui.listTile@1',
      defaultOnly: protected,
      props: {'title': title, 'subtitle': ?subtitle, 'disabled': !enabled},
      events: {
        if (onTap != null)
          'press': (_) {
            if (enabled) onTap!();
          },
      },
      fallback: ListTile(
        key: tileKey,
        minTileHeight: subtitle == null
            ? SettingsListTileTheme.singleLineHeight
            : SettingsListTileTheme.twoLineHeight,
        leading: SettingsGlyph(icon, surface: subtitle != null),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing:
            trailing ?? (onTap == null ? null : UiIcon(trailingIcon, size: 12)),
        enabled: enabled,
        selected: selected,
        selectedColor: Theme.of(context).colorScheme.onSurface,
        onTap: enabled ? onTap : null,
      ),
    ),
  );
}

class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 16),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 12.5,
        height: 1.5,
        color: AppDesign.muted(context),
      ),
    ),
  );
}

class SettingsEmptyState extends StatelessWidget {
  const SettingsEmptyState({
    super.key,
    required this.title,
    required this.detail,
    this.icon = Icons.search,
    this.grouped = true,
  });

  final String title, detail;
  final IconData icon;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        children: [
          SettingsGlyph(icon, size: 46, radius: 14, iconSize: 22),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppDesign.muted(context)),
          ),
        ],
      ),
    );
    return grouped ? SettingsGroupSurface(children: [body]) : body;
  }
}

class SettingsGlyph extends StatelessWidget {
  const SettingsGlyph(
    this.icon, {
    super.key,
    this.surface = true,
    this.size = SettingsListTileTheme.glyphSize,
    this.radius = 10,
    this.iconSize = 18,
  });
  final bool surface;
  final IconData icon;
  final double size, radius, iconSize;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: !surface
        ? null
        : ShapeDecoration(
            shape: AppDesign.smoothShape(radius: radius),
            color: Theme.of(context).colorScheme.surfaceContainerHigh
                .withValues(alpha: .7),
          ),
    child: UiIcon(
      icon,
      size: iconSize,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class SettingsSummary extends StatelessWidget {
  const SettingsSummary({
    super.key,
    required this.label,
    required this.title,
    required this.detail,
    required this.icon,
  });
  final String label, title, detail;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: SettingsGroup.spacing),
      child: Container(
        constraints: const BoxConstraints(minHeight: 100),
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
        decoration: ShapeDecoration(
          color: c.primaryContainer,
          shape: AppDesign.smoothShape(
            radius: 18,
            side: BorderSide(
              color: Color.lerp(c.primaryContainer, c.primary, .16)!,
              width: .8,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: c.onPrimaryContainer),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    detail,
                    style: TextStyle(
                      color: c.onPrimaryContainer,
                      fontSize: 12.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              height: 42,
              width: 42,
              decoration: ShapeDecoration(
                color: c.surface,
                shape: AppDesign.smoothShape(radius: 13),
              ),
              alignment: Alignment.center,
              child: UiIcon(icon, size: 22, color: c.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.expandedActions = false,
    this.showClose = false,
  });
  final Widget title, content;
  final List<Widget> actions;
  final bool expandedActions, showClose;
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DefaultTextStyle(
                style: Theme.of(context).textTheme.titleLarge!
                    .copyWith(fontWeight: FontWeight.w700, fontSize: 22),
                child: showClose
                    ? Row(
                        children: [
                          Expanded(child: title),
                          IconButton(
                            tooltip: '关闭',
                            icon: const UiIcon(Icons.close_rounded, size: 18),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      )
                    : title,
              ),
              const SizedBox(height: 14),
              Flexible(child: content),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: expandedActions
                      ? Row(
                          spacing: 8,
                          children: [
                            for (final action in actions)
                              Expanded(child: action),
                          ],
                        )
                      : Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          children: actions,
                        ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<T?> showSettingsModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useGlobalStyle = false,
  bool compactFrame = false,
}) {
  final scope = UiScopeData.maybeOf(context);
  final builtIn = !useGlobalStyle && scope?.defaultOnly == true;
  final theme = builtIn
      ? scope?.defaultTheme ?? Theme.of(context)
      : Theme.of(context);
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: !compactFrame,
    backgroundColor: compactFrame
        ? AppDesign.modalSurface(theme)
        : theme.scaffoldBackgroundColor,
    barrierColor: compactFrame
        ? AppDesign.modalBarrier(theme)
        : theme.colorScheme.scrim.withValues(alpha: .33),
    shape: const RoundedSuperellipseBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
    ),
    builder: (context) {
      Widget body(BuildContext sheet) {
        if (!compactFrame) return builder(sheet);
        return OutlinedButtonTheme(
          data: OutlinedButtonThemeData(
            style:
                theme.outlinedButtonTheme.style?.merge(
                  AppDesign.modalSecondary(sheet),
                ) ??
                AppDesign.modalSecondary(sheet),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(child: builder(sheet)),
            ],
          ),
        );
      }

      if (useGlobalStyle) {
        return UiPackScope.global(child: Builder(builder: body));
      }
      if (builtIn) {
        return UiPackScope(defaultOnly: true, child: Builder(builder: body));
      }
      return body(context);
    },
  );
}
