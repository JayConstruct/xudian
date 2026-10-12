import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app_select_field.dart';
import 'package:task_app/app/app_ui_feedback.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/core/ui/ui_component.dart';

void main() {
  test(
    'light and dark surfaces keep readable text and chosen UI pack colors',
    () {
      double contrast(Color foreground, Color background) {
        final a = foreground.computeLuminance();
        final b = background.computeLuminance();
        return (math.max(a, b) + .05) / (math.min(a, b) + .05);
      }

      for (final brightness in Brightness.values) {
        final theme = AppDesign.theme(brightness);
        final scheme = theme.colorScheme;
        expect(
          contrast(scheme.onSurface, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(scheme.onSurfaceVariant, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
        );
        final selected = applyUiPackTheme(theme, {
          'primary': '#00796B',
          'canvas': '#E2EEEA',
          'radius': 8,
        });
        expect(selected.scaffoldBackgroundColor, const Color(0xFFE2EEEA));
        expect(selected.colorScheme.primary, isNot(scheme.primary));
      }
    },
  );

  testWidgets(
    'large narrow controls remain usable and drafts survive dark mode',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final mode = ValueNotifier(ThemeMode.light);
      addTearDown(mode.dispose);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var actions = 0;
      await tester.pumpWidget(
        ValueListenableBuilder(
          valueListenable: mode,
          builder: (_, current, _) => MaterialApp(
            theme: AppDesign.theme(Brightness.light),
            darkTheme: AppDesign.theme(Brightness.dark),
            themeMode: current,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(labelText: '名称'),
                    ),
                    const SizedBox(height: 12),
                    for (final variant in [
                      'filled',
                      'outlined',
                      'text',
                      'tonal',
                    ])
                      defaultUiComponent(
                        'ui.button@1',
                        {'label': variant, 'variant': variant},
                        {},
                        {'press': (_) => actions++},
                      ),
                    AppSelectField(
                      label: '显示方式',
                      value: 'a',
                      options: const [
                        AppSelectOption(value: 'a', label: '舒适显示'),
                        AppSelectOption(value: 'b', label: '紧凑显示'),
                      ],
                      onChanged: (_) {},
                    ),
                    const SizedBox(height: 12),
                    const AppProgressIndicator(value: .6),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, '保留我的草稿');
      final original = tester.state(find.byType(TextField).first);
      mode.value = ThemeMode.dark;
      await tester.pumpAndSettle();
      expect(
        identical(tester.state(find.byType(TextField).first), original),
        isTrue,
      );
      expect(controller.text, '保留我的草稿');
      for (final variant in ['filled', 'outlined', 'text', 'tonal']) {
        await tester.ensureVisible(find.text(variant));
        await tester.tap(find.text(variant));
        await tester.pump();
      }
      expect(actions, 4);
      final shape = appUiButtonStyle.shape!.resolve({});
      expect(shape, isA<RoundedSuperellipseBorder>());
      expect(
        (shape as RoundedSuperellipseBorder).borderRadius,
        BorderRadius.circular(14),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
