import 'package:flutter/material.dart';

import '../core/ui/ui_design.dart';
import '../core/ui/ui_icon.dart';

class WorkspaceSidebarItem extends StatelessWidget {
  const WorkspaceSidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : Colors.transparent,
      shape: AppDesign.smoothShape(radius: AppDesign.controlRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: AppDesign.smoothShape(radius: AppDesign.controlRadius),
        hoverColor: scheme.surfaceContainerHigh.withValues(alpha: 0.8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              UiIcon(
                icon,
                size: 21,
                color: selected ? scheme.primary : AppDesign.muted(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
