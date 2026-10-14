import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_page_transition.dart';

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
  static const dialogInsets = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 24,
  );
  static const dialogContentPadding = EdgeInsets.fromLTRB(20, 16, 20, 20);
  static const dialogTitlePadding = EdgeInsets.fromLTRB(20, 20, 20, 0);
  static const dialogActionsPadding = EdgeInsets.fromLTRB(12, 0, 12, 12);
  static const dialogConstraints = BoxConstraints(minWidth: 280, maxWidth: 760);

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
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
        },
      ),
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
        insetPadding: dialogInsets,
        constraints: dialogConstraints,
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
