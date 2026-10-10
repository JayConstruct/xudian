// Frozen v2 contract fixture. New production shell is covered by host_ui_test.dart.
import 'package:task_app/features/ai/ai_module.dart';
import 'package:task_app/features/declarative_runtime/builtin_declarative_modules.dart';
import 'package:task_app/features/module_manager/module_manager_module.dart';
import 'package:task_app/features/projects/projects_module.dart';
import 'package:task_app/features/ui_examples/ui_examples_module.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/modules/builtin_module_registration.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/features/settings/app_preferences.dart';
import 'package:task_app/core/ui/ui_annotation.dart';
import 'package:task_app/core/ui/app_navigation.dart';
import 'package:task_app/core/ui/global_overlay_host.dart';

import 'legacy_app_shell.dart';

import 'package:task_app/app/design_system.dart';

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
    final views = buildBuiltinDeclarativeModules();
    for (var i = 0; i < views.length; i++) {
      registry.registerBuiltin(
        BuiltinModuleRegistration(
          module: views[i],
          title: i == 0 ? '今天' : '收件箱',
          description: 'v2 baseline',
          kind: BuiltinModuleKind.declarative,
        ),
      );
    }
    registry.registerBuiltin(
      BuiltinModuleRegistration(
        module: ProjectsModule(),
        title: '项目',
        description: '组织项目及相关任务',
      ),
    );
    registry.registerBuiltin(
      BuiltinModuleRegistration(
        module: ModuleManagerModule(registry: registry),
        title: '模块管理',
        description: 'v2 baseline',
        canDisable: false,
      ),
    );
    registry.registerBuiltin(
      BuiltinModuleRegistration(
        module: AiModule(registry: registry),
        title: 'AI 助手',
        description: 'v2 baseline',
      ),
    );
    registry.registerBuiltin(
      BuiltinModuleRegistration(
        module: UiExamplesModule(registry: registry),
        title: 'UI 示例',
        description: 'v2 baseline',
      ),
    );
    registry.registerBuiltin(
      BuiltinModuleRegistration(
        module: UiExampleContributionsModule(),
        title: 'UI 示例贡献',
        description: 'v2 baseline',
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
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppDesign.overlayStyle(Theme.of(context).brightness),
            child: AnnotationControls(
              child: GlobalOverlayHost(registry: registry, child: child!),
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
