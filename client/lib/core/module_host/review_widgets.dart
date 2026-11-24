import 'package:flutter/material.dart';

import '../../features/settings/settings_widgets.dart';
import '../ui/ui_component.dart';
import '../ui/script_content_widgets.dart';
import '../ui/ui_design.dart';

class ReviewSubject extends StatelessWidget {
  const ReviewSubject({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.quote = false,
  });
  final String title, subtitle;
  final IconData icon;
  final bool quote;
  @override
  Widget build(BuildContext context) {
    if (quote) {
      final theme = Theme.of(context);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 15,
                height: 1.65,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
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
    this.destructive = false,
  });
  final String title, confirmLabel, cancelLabel;
  final List<Widget> children;
  final VoidCallback? onConfirm;
  final bool destructive;
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
                    style: destructive
                        ? FilledButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .error,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onError,
                          )
                        : null,
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

Future<bool> showReviewConfirmation(
  BuildContext context, {
  required String title,
  required List<Widget> children,
  required String confirmLabel,
  String cancelLabel = '取消',
}) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: AppDesign.modalBarrier(Theme.of(context)),
      builder: (sheet) => UiPackScope(
        defaultOnly: true,
        child: ReviewDialog(
          title: title,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          onConfirm: () => Navigator.pop(sheet, true),
          children: children,
        ),
      ),
    ) ??
    false;
