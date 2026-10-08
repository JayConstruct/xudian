import '../core/module_host/host_manager_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/modules/module_registry.dart';
import '../core/modules/builtin_module_registration.dart';
import '../core/security/capability_registry.dart';
import '../features/settings/app_preferences.dart';
import '../core/ui/ui_annotation.dart';
import '../core/ui/ui_component.dart';
import '../core/ui/app_navigation.dart';
import '../core/ui/global_overlay_host.dart';
import 'app_shell.dart';
import 'design_system.dart';

class XudianApp extends ConsumerWidget {
  XudianApp({super.key}) {
    registry = ModuleRegistry(
      [],
      capabilities: CapabilityRegistry([
        'tasks.query',
        'tasks.command',
        'ui.registry',
        'ui.composition',
      ]),
    );
    registry.registerBuiltin(
      BuiltinModuleRegistration(
        module: HostManagerModule(),
        title: '模块管理',
        description: '安装、授权和恢复独立模块',
        canDisable: false,
      ),
    );
  }

  late final ModuleRegistry registry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences =
        ref.watch(appPreferencesProvider).asData?.value ??
        const AppPreferences();
    return MaterialApp(
      navigatorKey: ref.read(appNavigationProvider).navigatorKey,
      navigatorObservers: [ref.read(appNavigationProvider)],
      title: '序点',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: preferences.themeMode,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            disableAnimations:
                media.disableAnimations || preferences.reduceMotion,
          ),
          child: UiPackScope(
            child: Builder(
              builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
                value: AppDesign.overlayStyle(Theme.of(context).brightness),
                child: AnnotationControls(
                  child: GlobalOverlayHost(registry: registry, child: child!),
                ),
              ),
            ),
          ),
        );
      },
      home: AppShell(registry: registry),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppDesign.brand,
      brightness: brightness,
      surface: dark ? const Color(0xFF252A30) : const Color(0xFFFBFCFD),
    );
    final controlShape = AppDesign.smoothShape(radius: AppDesign.controlRadius);
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? AppDesign.darkCanvas
          : AppDesign.lightCanvas,
      useMaterial3: true,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
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
        fillColor: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
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
        elevation: 8,
        shape: AppDesign.smoothShape(radius: AppDesign.selectionRadius),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: controlShape,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: controlShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: controlShape),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: controlShape),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(shape: controlShape),
      ),
      chipTheme: ChipThemeData(
        shape: AppDesign.smoothShape(radius: AppDesign.compactRadius),
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
}
