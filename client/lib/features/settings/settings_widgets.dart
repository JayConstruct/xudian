import '../../core/ui/ui_icon.dart';

import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../core/ui/ui_component.dart';

class SettingsList extends StatelessWidget {
  const SettingsList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
    children: children,
  );
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children, this.title});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            SectionHeading(
              title: title!,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 20, endIndent: 20),
            children[i],
          ],
        ],
      ),
    );
    return UiComponent(
      ref: 'ui.nativeSection@1',
      props: {'title': title ?? ''},
      slots: {'content': content},
      fallback: content,
    );
  }
}

class SettingsEntry extends StatelessWidget {
  const SettingsEntry({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.protected = false,
    this.enabled = true,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool protected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => UiComponent(
    ref: 'ui.listTile@1',
    defaultOnly: protected,
    props: {'title': title, 'subtitle': ?subtitle, 'disabled': !enabled},
    events: {
      'press': (_) {
        if (enabled) onTap();
      },
    },
    fallback: ListTile(
      leading: UiIcon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const UiIcon(Icons.chevron_right_rounded),
      enabled: enabled,
      onTap: enabled ? onTap : null,
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
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: AppDesign.muted(context)),
    ),
  );
}
