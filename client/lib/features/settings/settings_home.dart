import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/ui/native_ui.dart';
import '../../core/ui/ui_component.dart';
import '../../core/ui/ui_design.dart';
import '../../core/ui/ui_icon.dart';
import 'settings_feature_card.dart';

export 'settings_feature_card.dart' show SettingsFeatureCard;

class SettingsHome extends StatelessWidget {
  const SettingsHome({
    super.key,
    required this.appearance,
    required this.layout,
    required this.management,
    required this.support,
    required this.shortcuts,
  });
  final SettingsFeatureCard appearance, layout;
  final List<SettingsHomeEntry> management, support, shortcuts;

  @override
  Widget build(BuildContext context) {
    const maxWidth = 760.0;
    final media = MediaQuery.of(context);
    final width = media.size.width - media.padding.horizontal;
    final textScale = media.textScaler.scale(16) / 16;
    final margin = math.max(20.0, (width - maxWidth) / 2);
    final wide = width >= 820 && maxWidth >= 680 * textScale;
    final sections = LayoutBuilder(
      builder: (context, constraints) {
        final sectionWidth = math.min(maxWidth, constraints.maxWidth - 40);
        final twoColumns = wide && sectionWidth >= 680 * textScale;
        final widgets = [appearance, layout];
        final personal = _Section(
          title: '个性化',
          child: !twoColumns && sectionWidth >= 300 * textScale
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [for (final card in widgets) Expanded(child: card)],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: widgets,
                ),
        );
        final manage = _Section.entries('应用与数据', management);
        final help = _Section.entries('支持与关于', support);
        final common = shortcuts.isEmpty
            ? null
            : _Section.entries('常用入口', shortcuts);
        Widget column(List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: twoColumns ? 24 : 22.5,
          children: children,
        );
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, wide ? 12 : 6, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxWidth),
              child: twoColumns
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 28,
                      children: [
                        Expanded(flex: 288, child: column([personal, ?common])),
                        Expanded(flex: 444, child: column([manage, help])),
                      ],
                    )
                  : column([personal, manage, help, ?common]),
            ),
          ),
        );
      },
    );
    return NativeUi(
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: wide ? 76 : 56,
          automaticallyImplyLeading: false,
          leadingWidth: margin + 32,
          leading: Navigator.canPop(context)
              ? Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: const BackButton(),
                )
              : null,
          centerTitle: false,
          titleSpacing: wide ? 16 : 10,
          title: Text(
            '设置',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: wide ? 27 : 25,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: UiComponent(
            ref: 'ui.page.settings@1',
            props: const {'title': '设置'},
            slots: {'sections': sections},
            fallback: sections,
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  _Section.entries(this.title, List<SettingsHomeEntry> entries)
    : child = Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Material(
            color: scheme.surface,
            shape: AppDesign.smoothShape(
              radius: 17,
              side: BorderSide(color: scheme.outlineVariant, width: .8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: .65,
                      thickness: .65,
                      indent: 58,
                      endIndent: 15,
                      color: scheme.outlineVariant,
                    ),
                  entries[i],
                ],
              ],
            ),
          );
        },
      );
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Semantics(
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
        ),
        child,
      ],
    );
    return UiComponent(
      ref: 'ui.nativeSection@1',
      props: {'title': title},
      slots: {'content': content},
      fallback: content,
    );
  }
}

class SettingsHomeEntry extends StatelessWidget {
  const SettingsHomeEntry({
    super.key,
    required this.title,
    this.subtitle,
    this.status,
    required this.icon,
    required this.onTap,
    this.protected = false,
  });
  final String title;
  final String? subtitle, status;
  final IconData icon;
  final VoidCallback onTap;
  final bool protected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = subtitle == null;
    final foreground = scheme.onSurfaceVariant;
    final badge = status == null
        ? null
        : DecoratedBox(
            decoration: ShapeDecoration(
              color: scheme.primaryContainer,
              shape: const StadiumBorder(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Text(
                status!,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          );
    final label = Text(
      title,
      style: const TextStyle(
        fontSize: 15.3,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    );
    final glyph = UiIcon(icon, size: 18, color: foreground);
    final summary = subtitle;
    return UiComponent(
      ref: 'ui.listTile@1',
      defaultOnly: protected,
      props: {
        'title': title,
        if (summary != null) 'subtitle': [summary, ?status].join(' · '),
        'disabled': false,
      },
      events: {'press': (_) => onTap()},
      fallback: LayoutBuilder(
        builder: (context, constraints) {
          final inline =
              constraints.maxWidth >=
              330 * MediaQuery.textScalerOf(context).scale(14) / 14;
          return ListTile(
            onTap: onTap,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            minTileHeight: compact ? 50 : 62,
            minVerticalPadding: 8,
            minLeadingWidth: 32,
            horizontalTitleGap: 12,
            leading: SizedBox.square(
              dimension: 32,
              child: compact
                  ? Center(child: glyph)
                  : DecoratedBox(
                      decoration: ShapeDecoration(
                        color: scheme.surfaceContainerHigh.withValues(
                          alpha: .7,
                        ),
                        shape: AppDesign.smoothShape(radius: 10),
                      ),
                      child: Center(child: glyph),
                    ),
            ),
            title: summary == null
                ? label
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label,
                      Text(
                        summary,
                        style: TextStyle(
                          fontSize: 12.1,
                          height: 1.45,
                          color: foreground,
                        ),
                      ),
                      if (!inline && badge != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: badge,
                        ),
                    ],
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 10,
              children: [
                if (inline && badge != null) badge,
                UiIcon(
                  Icons.chevron_right_rounded,
                  size: 12,
                  color: foreground,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
