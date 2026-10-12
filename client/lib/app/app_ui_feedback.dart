import '../core/ui/ui_component.dart';
import '../core/ui/native_ui.dart';
import '../core/ui/ui_icon.dart';

import 'package:flutter/material.dart';

/// Shared action geometry; capsule shapes are reserved for selection chips.
const appUiButtonStyle = ButtonStyle(
  shape: WidgetStatePropertyAll(
    RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
    ),
  ),
  minimumSize: WidgetStatePropertyAll(Size(48, 48)),
  padding: WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  ),
);

class AppSlider extends StatelessWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.semanticFormatterCallback,
  });

  final double value, min, max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final SemanticFormatterCallback? semanticFormatterCallback;

  @override
  Widget build(BuildContext context) => SliderTheme(
    data: SliderTheme.of(context).copyWith(
      trackHeight: 12,
      trackShape: const RoundedRectSliderTrackShape(),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
    ),
    child: Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      semanticFormatterCallback: semanticFormatterCallback,
      onChanged: onChanged,
    ),
  );
}

class AppProgressIndicator extends StatelessWidget {
  const AppProgressIndicator({super.key, this.value});

  final double? value;

  @override
  Widget build(BuildContext context) => LinearProgressIndicator(
    value: value,
    minHeight: 10,
    borderRadius: BorderRadius.circular(100),
    trackGap: 0,
    stopIndicatorRadius: 0,
  );
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: .4),
              shape: BoxShape.circle,
            ),
            child: UiIcon(
              Icons.error_outline_rounded,
              size: 72,
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            NativeUi(
              child: FilledButton.tonal(
                style: appUiButtonStyle,
                onPressed: onRetry,
                child: const Text('重试'),
              ),
            ),
          ],
        ],
      ),
    );
    return UiComponent(
      ref: 'ui.nativeFeedback@1',
      props: {'kind': 'error', 'message': message},
      slots: {'control': content},
      fallback: content,
    );
  }
}
