import 'package:flutter/material.dart';

import '../../core/modules/app_module.dart';
import '../../core/modules/module_manifest.dart';
import '../../core/modules/module_registry.dart';
import '../../core/ui/app_destination.dart';
import '../../core/ui/ui_registration.dart';
import 'module_manager_page.dart';

class ModuleManagerModule implements AppModule {
  ModuleManagerModule({required this.registry});

  final ModuleRegistry registry;

  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'app.module.manager',
    version: '1.0.0',
    coreApi: '1',
    requiresCapabilities: ['ui.registry'],
    permissions: ['ui.register'],
  );

  @override
  List<UiRegistration> get ui => [
    NavigationRegistration(
      AppDestination(
        id: 'modules',
        label: '模块',
        icon: Icons.extension_outlined,
        selectedIcon: Icons.extension,
        builder: (_) => ModuleManagerPage(registry: registry),
      ),
    ),
  ];
}
