import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/app_destination.dart';
import 'package:task_app/core/ui/ui_registration.dart';

class _Module implements AppModule {
  _Module(this.manifest, {this.ui = const []});

  @override
  final ModuleManifest manifest;

  @override
  final List<UiRegistration> ui;
}

void main() {
  test('registry validates required capabilities', () {
    expect(
      () => ModuleRegistry(
        [
          _Module(const ModuleManifest(
            id: 'app.test.module',
            version: '1.0.0',
            coreApi: '1',
            requiresCapabilities: ['missing.capability'],
          )),
        ],
        capabilities: CapabilityRegistry(const []),
      ),
      throwsStateError,
    );
  });

  test('registry requires ui.register permission for UI', () {
    final destination = AppDestination(
      id: 'test',
      label: 'Test',
      icon: Icons.circle_outlined,
      selectedIcon: Icons.circle,
      builder: (_) => const SizedBox.shrink(),
    );

    expect(
      () => ModuleRegistry(
        [
          _Module(
            const ModuleManifest(
              id: 'app.test.module',
              version: '1.0.0',
              coreApi: '1',
              requiresCapabilities: ['ui.registry'],
            ),
            ui: [NavigationRegistration(destination)],
          ),
        ],
        capabilities: CapabilityRegistry(['ui.registry']),
      ),
      throwsStateError,
    );
  });

  test('failed runtime module change leaves registry intact', () {
    final destination = AppDestination(
      id: 'stable',
      label: 'Stable',
      icon: Icons.circle_outlined,
      selectedIcon: Icons.circle,
      builder: (_) => const SizedBox.shrink(),
    );
    final registry = ModuleRegistry(
      [
        _Module(
          const ModuleManifest(
            id: 'app.stable.module',
            version: '1.0.0',
            coreApi: '1',
            permissions: ['ui.register'],
          ),
          ui: [NavigationRegistration(destination)],
        ),
      ],
      capabilities: CapabilityRegistry(const []),
    );

    expect(
      () => registry.addOrReplace(
        _Module(
          const ModuleManifest(
            id: 'app.bad.module',
            version: '1.0.0',
            coreApi: '1',
            requiresCapabilities: ['missing.capability'],
          ),
        ),
      ),
      throwsStateError,
    );
    expect(registry.ui.primaryDestinations.single.id, 'stable');
    expect(registry.modules.single.manifest.id, 'app.stable.module');
  });

  test('registry exposes UI through slots', () {
    final destination = AppDestination(
      id: 'test',
      label: 'Test',
      icon: Icons.circle_outlined,
      selectedIcon: Icons.circle,
      builder: (_) => const SizedBox.shrink(),
    );
    final registry = ModuleRegistry(
      [
        _Module(
          const ModuleManifest(
            id: 'app.test.module',
            version: '1.0.0',
            coreApi: '1',
            requiresCapabilities: ['ui.registry'],
            permissions: ['ui.register'],
          ),
          ui: [NavigationRegistration(destination)],
        ),
      ],
      capabilities: CapabilityRegistry(['ui.registry']),
    );

    expect(registry.ui.primaryDestinations.single.id, 'test');
  });
}
