import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/ui_design.dart';
import 'package:task_app/core/ui/ui_feedback.dart';
import 'package:task_app/core/ui/ui_pack.dart';
import 'package:task_app/core/ui/ui_pack_providers.dart';
import 'package:task_app/core/ui/ui_pack_settings_page.dart';
import 'package:task_app/features/settings/app_preferences.dart';
import 'package:task_app/features/settings/appearance_settings_page.dart';

class _SelectionRead extends UiSelectionController {
  _SelectionRead(this.read);
  final UiSelection Function() read;

  @override
  Future<UiSelection> build() async => read();
}

class _PreferencesRead extends AppPreferencesController {
  _PreferencesRead(this.read);
  final AppPreferences Function() read;

  @override
  Future<AppPreferences> build() async => read();
}

void main() {
  testWidgets('style recovery retries failed storage in the default dark UI', (
    tester,
  ) async {
    var attempts = 0;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uiSelectionProvider.overrideWith(
            () => _SelectionRead(() {
              if (++attempts == 1) throw StateError('private storage detail');
              return UiSelection();
            }),
          ),
          moduleHostProvider.overrideWith(
            (_) async => throw StateError('No modules needed'),
          ),
          uiPackRegistryProvider.overrideWith((_) => Stream.value(const {})),
        ],
        child: MaterialApp(
          theme: AppDesign.theme(Brightness.dark),
          home: const UiPackSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text('无法读取界面风格，请重试'), findsOneWidget);
    expect(find.textContaining('private storage detail'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(AppErrorState), findsNothing);
    expect(find.text('全局风格'), findsOneWidget);
    expect(find.text('预览草稿'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('appearance retry restores the actual saved theme controls', (
    tester,
  ) async {
    var attempts = 0;
    final registry = ModuleRegistry([], capabilities: CapabilityRegistry([]));
    addTearDown(registry.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferencesProvider.overrideWith(
            () => _PreferencesRead(() {
              if (++attempts == 1) throw StateError('private storage detail');
              return const AppPreferences(themeMode: ThemeMode.dark);
            }),
          ),
        ],
        child: MaterialApp(
          theme: AppDesign.theme(Brightness.light),
          home: AppearanceSettingsPage(registry: registry),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text('读取外观设置失败，请重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(AppErrorState), findsNothing);
    expect(find.text('深色'), findsOneWidget);
    expect(find.text('减少动画'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
