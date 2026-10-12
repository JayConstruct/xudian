import '../core/module_host/host_manager_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/modules/module_registry.dart';
import '../core/modules/builtin_module_registration.dart';
import '../core/security/capability_registry.dart';
import '../features/settings/app_preferences.dart';
import '../core/ui/ui_annotation.dart';
import '../core/ui/ui_component.dart';
import '../core/ui/app_navigation.dart';
import '../core/ui/global_overlay_host.dart';
import 'app_shell.dart';
import 'app_scroll_behavior.dart';
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
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN')],
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: AppDesign.theme(Brightness.light),
      darkTheme: AppDesign.theme(Brightness.dark),
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
}
