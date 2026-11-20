import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/ui/native_ui.dart';
import '../../core/ui/ui_component.dart';
import '../../core/ui/ui_design.dart';
import '../../core/ui/ui_icon.dart';
import 'settings_feature_card.dart';
import 'settings_focus.dart';
import 'settings_widgets.dart';

export 'settings_feature_card.dart' show SettingsFeatureCard;

class SettingsHome extends StatelessWidget {
  const SettingsHome({
    super.key,
    required this.appearance,
    required this.layout,
    required this.management,
    required this.support,
    required this.shortcuts,
    this.onClose,
    this.onSearch,
    this.onDirectory,
    this.returnToSearch = false,
  });
  final bool returnToSearch;
  final VoidCallback? onClose, onSearch, onDirectory;
  final SettingsFeatureCard appearance, layout;
  final List<SettingsHomeEntry> management, support, shortcuts;

  @override
  Widget build(BuildContext context) {
    const maxWidth = 760.0;
    final media = MediaQuery.of(context);
    final width = media.size.width - media.padding.horizontal;
    final textScale = media.textScaler.scale(16) / 16;
    final margin = math.max(AppDesign.pageGutter, (width - maxWidth) / 2);
    final wide = width >= 820 && maxWidth >= 680 * textScale;
    final sections = LayoutBuilder(
      builder: (context, constraints) {
        final sectionWidth = math.min(
          maxWidth,
          constraints.maxWidth - 2 * AppDesign.pageGutter,
        );
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
          spacing: twoColumns ? 24 : SettingsGroup.spacing,
          children: children,
        );
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppDesign.pageGutter,
            wide ? 12 : 6,
            AppDesign.pageGutter,
            32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (onSearch != null && onDirectory != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                minimumSize: const Size(0, 46),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surface,
                                shape: AppDesign.smoothShape(
                                  radius: AppDesign.controlRadius,
                                ),
                              ),
                              onPressed: onSearch,
                              icon: const UiIcon(Icons.search, size: 18),
                              label: const Text('搜索设置'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            flex: 0,
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 46),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                shape: AppDesign.smoothShape(
                                  radius: AppDesign.controlRadius,
                                ),
                              ),
                              onPressed: onDirectory,
                              icon: const UiIcon(
                                Icons.list_alt_outlined,
                                size: 18,
                              ),
                              label: const Text('入口目录'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  twoColumns
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 28,
                          children: [
                            Expanded(
                              flex: 288,
                              child: column([personal, ?common]),
                            ),
                            Expanded(flex: 444, child: column([manage, help])),
                          ],
                        )
                      : column([personal, manage, help, ?common]),
                ],
              ),
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
          leading: onClose != null || Navigator.canPop(context)
              ? Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: BackButton(onPressed: onClose),
                )
              : null,
          actions: [
            if (returnToSearch)
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回查找'),
              ),
          ],
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
    : child = SettingsGroupSurface(children: entries);
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SettingsGroup.headingGap,
      children: [SettingsHeading(title), child],
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
    final summary = subtitle;
    return SettingsAnchor(
      title,
      child: UiComponent(
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
              minTileHeight: compact
                  ? SettingsListTileTheme.singleLineHeight
                  : SettingsListTileTheme.twoLineHeight,
              leading: SettingsGlyph(icon, surface: !compact),
              title: Text(title),
              subtitle: summary == null && (inline || badge == null)
                  ? null
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (summary != null) Text(summary),
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
      ),
    );
  }
}
