import 'package:flutter/material.dart';

import '../../features/settings/settings_widgets.dart';
import '../ui/script_content_widgets.dart';
import '../ui/ui_design.dart';

class ReviewSubject extends StatelessWidget {
  const ReviewSubject({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  final String title, subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: SettingsGroupSurface(
      children: [
        ListTile(
          minTileHeight: 78,
          leading: ScriptGlyph(
            icon: icon,
            surface: true,
            surfaceSize: 44,
            size: 22,
          ),
          title: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          subtitle: Text(subtitle),
        ),
      ],
    ),
  );
}

class ReviewFacts extends StatelessWidget {
  const ReviewFacts({
    super.key,
    this.title,
    required this.items,
    this.emphasizedTitle,
  });
  final String? title, emphasizedTitle;
  final List<({String title, String subtitle})> items;
  @override
  Widget build(BuildContext context) => SettingsGroup(
    title: title,
    dividerIndent: 14,
    bottomSpacing: 12,
    children: [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  item.title,
                  style: item.title == emphasizedTitle
                      ? TextStyle(color: Theme.of(context).colorScheme.error)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: Text(
                  item.subtitle,
                  textAlign: TextAlign.end,
                  style: TextStyle(color: AppDesign.muted(context)),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class ReviewNotice extends StatelessWidget {
  const ReviewNotice(this.message, {super.key, this.icon});
  final IconData? icon;
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: ShapeDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      shape: AppDesign.smoothShape(radius: AppDesign.compactRadius),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}

class ReviewDialog extends StatelessWidget {
  const ReviewDialog({
    super.key,
    required this.title,
    required this.children,
    required this.confirmLabel,
    required this.onConfirm,
    this.cancelLabel = '取消',
  });
  final String title, confirmLabel, cancelLabel;
  final List<Widget> children;
  final VoidCallback? onConfirm;
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: AppDesign.dialogInsets,
    backgroundColor: AppDesign.modalSurface(Theme.of(context)),
    shape: AppDesign.smoothShape(radius: AppDesign.floatingRadius),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: AppDesign.modalSecondary(context),
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(cancelLabel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: onConfirm,
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
