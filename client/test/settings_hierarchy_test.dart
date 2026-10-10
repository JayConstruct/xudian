import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/host_settings_page.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/ui_annotation.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_page_host.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';
import 'package:task_app/features/settings/app_preferences.dart';
import 'package:task_app/features/settings/appearance_settings_page.dart';
import 'package:task_app/features/settings/ui_layout_page.dart';

class _FailingPreferences extends AppPreferencesController {
  @override
  Future<AppPreferences> build() async => const AppPreferences();

  @override
  Future<void> save(AppPreferences preferences) async {
    throw StateError('storage unavailable');
  }
}

void main() {
  late AppDatabase database;
  late ModuleRegistry registry;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    registry = ModuleRegistry(
      const [],
      capabilities: CapabilityRegistry(const []),
    );
  });
  tearDown(() async {
    registry.dispose();
    await database.close();
  });

  Future<void> show(WidgetTester tester, {bool dark = false}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((_) async => database)],
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          home: HostSettingsPage(registry: registry),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    if (find.text(text).evaluate().isEmpty) {
      await tester.scrollUntilVisible(find.text(text), 200);
    }
    await Scrollable.ensureVisible(
      tester.element(find.text(text)),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'appearance save failure preserves the applied setting and allows retry',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPreferencesProvider.overrideWith(_FailingPreferences.new),
          ],
          child: MaterialApp(home: AppearanceSettingsPage(registry: registry)),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, '减少动画');
      expect(find.text('设置保存失败，请重试'), findsOneWidget);
      final control = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '减少动画'),
      );
      expect(control.value, isFalse);
      expect(control.onChanged, isNotNull);
      await tap(tester, '减少动画');
      expect(tester.takeException(), isNull);
    },
  );

  for (final wide in [false, true]) {
    testWidgets(
      'categories and appearance persist on ${wide ? 'desktop dark' : '320px large text'}',
      (tester) async {
        tester.view.physicalSize = wide
            ? const Size(1200, 900)
            : const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = wide ? 1 : 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await show(tester, dark: wide);
        expect(find.byType(SwitchListTile), findsNothing);
        await tap(tester, '外观与交互');
        await tap(tester, '外观主题');
        await tap(tester, '深色');
        await tap(tester, '减少动画');
        final row =
            await (database.select(database.appSettings)..where(
                  (row) => row.key.equals(AppPreferencesController.storageKey),
                ))
                .getSingle();
        expect(jsonDecode(row.value), {
          'theme': 'dark',
          'reduceMotion': true,
          'haptics': true,
        });
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.textContaining('深色 ·'), findsOneWidget);
        await tap(tester, '辅助工具');
        await tap(tester, '界面标注模式');
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SwitchListTile)),
        );
        expect(container.read(uiAnnotationProvider), isTrue);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('界面标注已开启'), findsOneWidget);
        await tap(tester, '模块与连接');
        expect(find.text('模块管理与恢复'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tap(tester, '关于序点');
        expect(find.text('关于序点'), findsOneWidget);
        expect(find.text('项目地址'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tap(tester, '布局与导航');
        expect(
          tester
              .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
              .selected,
          {wide},
        );
        expect(find.byType(UiLayoutPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'settings shortcuts honor order and content pages open once with context',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const pageId = 'test.settings.page';
      registry.ui.register(
        UiPageRegistration(
          id: pageId,
          moduleId: 'test.settings',
          title: '设置内容',
          builder: (_, context) =>
              Center(child: Text('上下文：${context.values['scope']}')),
        ),
      );
      for (final (id, label, content) in [
        ('first', '第一个入口', false),
        ('second', '第二个入口', false),
        ('content', '专属选项', true),
      ]) {
        registry.ui.register(
          UiEntryRegistration(
            id: id,
            moduleId: 'test.settings',
            pageId: pageId,
            label: label,
            icon: Icons.settings,
            content: content,
            defaultMount: UiMount(
              placement: UiPlacement.settings,
              order: id == 'second' ? -1 : 0,
              context: const PageContext(values: {'scope': '保留'}),
            ),
          ),
        );
      }
      await show(tester);
      final labels = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title as Text).data)
          .toList();
      expect(labels.indexOf('第二个入口'), lessThan(labels.indexOf('第一个入口')));
      expect(find.text('专属选项'), findsNothing);
      await tap(tester, '第二个入口');
      expect(find.text('上下文：保留'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, '模块与连接');
      expect(find.text('专属选项'), findsOneWidget);
      expect(find.byType(UiPageHost), findsNothing);
      await tap(tester, '专属选项');
      expect(find.byType(UiPageHost), findsOneWidget);
      expect(find.text('上下文：保留'), findsOneWidget);
    },
  );
}
