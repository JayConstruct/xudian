import '../core/ui/ui_icon.dart';
import '../core/ui/native_ui.dart';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ui/ui_component.dart';

class AppDesign {
  static const brand = Color(0xFF606EAE);
  static const lightCanvas = Color(0xFFF5F5F2);
  static const darkCanvas = Color(0xFF1D1E22);
  static const lightSurface = Color(0xFFFEFEFC);
  static const darkSurface = Color(0xFF27282D);
  static const charcoal = Color(0xFF303239);
  static const compactRadius = 12.0;
  static const controlRadius = 14.0;
  static const radius = 20.0;
  static const selectionRadius = 20.0;
  static const selectionBorderRadius = BorderRadius.all(
    Radius.circular(selectionRadius),
  );
  static const floatingRadius = 24.0;
  static const dockRadius = 28.0;

  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(seedColor: brand, brightness: brightness).copyWith(
          primary: dark ? const Color(0xFFB9C3F0) : brand,
          onPrimary: dark ? const Color(0xFF252F60) : Colors.white,
          primaryContainer: dark
              ? const Color(0xFF333B59)
              : const Color(0xFFE9ECF6),
          onPrimaryContainer: dark
              ? const Color(0xFFDCE2FB)
              : const Color(0xFF465489),
          surface: dark ? darkSurface : lightSurface,
          onSurface: dark ? const Color(0xFFE8E8E8) : charcoal,
          onSurfaceVariant: dark
              ? const Color(0xFFAEAFB7)
              : const Color(0xFF6D707A),
          outline: dark ? const Color(0xFF7A7D89) : const Color(0xFFBABDC8),
          outlineVariant: dark
              ? const Color(0xFF42444E)
              : const Color(0xFFE3E4E8),
          surfaceContainerLowest: dark ? darkCanvas : lightSurface,
          surfaceContainerLow: dark
              ? const Color(0xFF222328)
              : const Color(0xFFF8F8F5),
          surfaceContainer: dark ? darkSurface : const Color(0xFFF1F2EF),
          surfaceContainerHigh: dark
              ? const Color(0xFF2D2F35)
              : const Color(0xFFEDEEEB),
          surfaceContainerHighest: dark
              ? const Color(0xFF34363D)
              : const Color(0xFFE7E8E5),
          surfaceTint: Colors.transparent,
        );
    final controlShape = AppDesign.smoothShape(radius: AppDesign.controlRadius);
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? AppDesign.darkCanvas
          : AppDesign.lightCanvas,
      useMaterial3: true,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        minLeadingWidth: 24,
        horizontalTitleGap: 14,
      ),
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: scheme.onSurface,
        systemOverlayStyle: AppDesign.overlayStyle(brightness),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: AppDesign.smoothShape(),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: ShapedInputBorder(
          shape: controlShape,
          borderSide: BorderSide.none,
        ),
        focusedBorder: ShapedInputBorder(
          shape: controlShape,
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
        ),
        errorBorder: ShapedInputBorder(
          shape: controlShape,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: ShapedInputBorder(
          shape: controlShape,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: AppDesign.smoothShape(radius: AppDesign.floatingRadius),
        clipBehavior: Clip.antiAlias,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDesign.dockRadius),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        elevation: 4,
        shape: AppDesign.smoothShape(radius: AppDesign.selectionRadius),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: controlShape,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: controlShape,
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: controlShape,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: controlShape),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(shape: controlShape),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        secondaryLabelStyle: TextStyle(color: scheme.onPrimaryContainer),
        showCheckmark: false,
      ),
      sliderTheme: const SliderThemeData(trackHeight: 12),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        linearMinHeight: 10,
        borderRadius: BorderRadius.all(Radius.circular(100)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer.withValues(alpha: 0.7),
        indicatorShape: AppDesign.smoothShape(
          radius: AppDesign.selectionRadius,
        ),
        elevation: 0,
      ),
    );
  }

  /// Shared continuous curve for surfaces, outlines, shadows and ink effects.
  static RoundedSuperellipseBorder smoothShape({
    double radius = AppDesign.radius,
    BorderSide side = BorderSide.none,
  }) => RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(radius),
    side: side,
  );

  static Color canvas(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  static Color surface(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  static Color muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: brightness,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: dark ? darkCanvas : lightCanvas,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
    );
  }

  static List<BoxShadow> softShadow(BuildContext context) => [
    BoxShadow(
      color: Colors.black.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.14 : 0.04,
      ),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];
}

/// Content groups sit quietly on the canvas; floating controls own the shadows.
class ContentSurface extends StatelessWidget {
  const ContentSurface({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => UiComponent(
    ref: 'ui.card@1',
    slots: {
      'content': Padding(padding: padding ?? EdgeInsets.zero, child: child),
    },
    fallback: Material(
      color: AppDesign.surface(context),
      shape: Theme.of(context).cardTheme.shape ?? AppDesign.smoothShape(),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    ),
  );
}

class DetailPage extends StatelessWidget {
  const DetailPage({
    super.key,
    required this.title,
    required this.child,
    this.leading,
    this.titleMaxLines = 1,
  });

  final String title;
  final Widget child;
  final Widget? leading;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    double? toolbarHeight;
    if (titleMaxLines > 1) {
      final style =
          Theme.of(context).appBarTheme.titleTextStyle ??
          Theme.of(context).textTheme.titleLarge;
      final painter =
          TextPainter(
            text: TextSpan(text: title, style: style),
            maxLines: titleMaxLines,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(
            maxWidth: (MediaQuery.sizeOf(context).width - 112).clamp(
              48,
              double.infinity,
            ),
          );
      toolbarHeight = (painter.height + 16).clamp(
        kToolbarHeight,
        double.infinity,
      );
      painter.dispose();
    }
    return NativeUi(
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: toolbarHeight,
          title: Text(
            title,
            maxLines: titleMaxLines,
            overflow: TextOverflow.ellipsis,
          ),
          leading: leading,
          centerTitle: false,
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SizedBox.expand(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: AppDesign.muted(context)),
          ),
        ),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ],
    ),
  );
}

class TaskSummary extends StatelessWidget {
  const TaskSummary({super.key, required this.total, required this.completed});

  final int total;
  final int completed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
    child: Text(
      completed == 0
          ? '$total 项待办'
          : '${total - completed} 项待办 · $completed 项完成',
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: AppDesign.muted(context)),
    ),
  );
}

class WorkspaceEmptyState extends StatelessWidget {
  const WorkspaceEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.task_alt_rounded,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        32,
        24,
        32,
        WorkspaceContentInsets.bottomOf(context) + 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight:
              (constraints.maxHeight -
                      WorkspaceContentInsets.bottomOf(context) -
                      48)
                  .clamp(0, double.infinity),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UiIcon(
                icon,
                size: 36,
                color: AppDesign.muted(context).withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppDesign.muted(context)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Space scrollable pages need below their last item to clear the floating dock.
class WorkspaceContentInsets extends InheritedWidget {
  const WorkspaceContentInsets({
    super.key,
    required this.bottom,
    required super.child,
  });

  final double bottom;

  static double bottomOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WorkspaceContentInsets>()
          ?.bottom ??
      0;

  @override
  bool updateShouldNotify(WorkspaceContentInsets oldWidget) =>
      bottom != oldWidget.bottom;
}

class FloatingSurface extends StatelessWidget {
  const FloatingSurface({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final surface = AppDesign.surface(context);
    final shape = AppDesign.smoothShape(radius: AppDesign.floatingRadius);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: AppDesign.softShadow(context),
      ),
      child: ClipRSuperellipse(
        borderRadius: shape.borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            shape: shape,
            color: surface.withValues(alpha: 0.91),
            child: Padding(
              padding: padding ?? const EdgeInsets.all(12),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class TaskObjectTile extends StatefulWidget {
  const TaskObjectTile({
    super.key,
    required this.title,
    required this.completed,
    required this.onCompleted,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final bool completed;
  final ValueChanged<bool?>? onCompleted;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  State<TaskObjectTile> createState() => _TaskObjectTileState();
}

class _TaskObjectTileState extends State<TaskObjectTile> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: ShapeDecoration(
          color: hovered
              ? theme.colorScheme.surfaceContainerHigh
              : widget.completed
              ? theme.colorScheme.surfaceContainerLow
              : theme.colorScheme.surface,
          shape: AppDesign.smoothShape(),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            customBorder: AppDesign.smoothShape(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  NativeUi(
                    child: Checkbox(
                      value: widget.completed,
                      onChanged: widget.onCompleted,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            decoration: widget.completed
                                ? TextDecoration.lineThrough
                                : null,
                            color: widget.completed
                                ? AppDesign.muted(context)
                                : null,
                          ),
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 3),
                          DefaultTextStyle.merge(
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppDesign.muted(context),
                            ),
                            child: widget.subtitle!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 8),
                    widget.trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
