import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design_system.dart';

class AppSelectOption<T> {
  const AppSelectOption({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final String label;
  final bool enabled;
}

/// A non-editable selection field with the same continuous corners as surfaces.
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.onChanged,
    this.value,
  });

  final String label;
  final T? value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return DropdownMenu<T>(
          initialSelection: value,
          enabled: onChanged != null && options.isNotEmpty,
          label: Text(label),
          expandedInsets: EdgeInsets.zero,
          selectOnly: true,
          requestFocusOnTap: false,
          enableSearch: false,
          textStyle: theme.textTheme.bodyLarge,
          inputDecorationTheme: theme.inputDecorationTheme,
          menuStyle: MenuStyle(
            shape: WidgetStatePropertyAll(
              AppDesign.smoothShape(radius: AppDesign.selectionRadius),
            ),
            backgroundColor: WidgetStatePropertyAll(scheme.surface),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(8),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
            maximumSize: WidgetStatePropertyAll(
              Size(
                constraints.maxWidth,
                math.min(384, MediaQuery.sizeOf(context).height * .55),
              ),
            ),
          ),
          dropdownMenuEntries: [
            for (final option in options)
              DropdownMenuEntry<T>(
                value: option.value,
                label: option.label,
                enabled: option.enabled,
                labelWidget: Text(
                  option.label,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailingIcon: option.value == value
                    ? const Icon(Icons.check_rounded, size: 20)
                    : const SizedBox(width: 20),
                style: ButtonStyle(
                  shape: WidgetStatePropertyAll(
                    AppDesign.smoothShape(radius: AppDesign.controlRadius),
                  ),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                  textStyle: WidgetStatePropertyAll(theme.textTheme.bodyLarge),
                  backgroundColor: WidgetStatePropertyAll(
                    option.value == value
                        ? scheme.secondaryContainer.withValues(alpha: .65)
                        : Colors.transparent,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                        ? scheme.onSurface.withValues(alpha: .38)
                        : option.value == value
                        ? scheme.onSecondaryContainer
                        : scheme.onSurface,
                  ),
                  overlayColor: WidgetStatePropertyAll(
                    scheme.primary.withValues(alpha: .08),
                  ),
                ),
              ),
          ],
          onSelected: onChanged,
        );
      },
    );
  }
}
