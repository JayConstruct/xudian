import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app_ui_feedback.dart';
import 'package:task_app/app/app_icons.dart';

void main() {
  testWidgets(
    'slider keeps native drag behavior and updates rounded progress',
    (tester) async {
      final value = ValueNotifier(.2);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: ValueListenableBuilder(
                  valueListenable: value,
                  builder: (_, progress, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppSlider(
                        value: progress,
                        min: 0,
                        max: 1,
                        divisions: 10,
                        semanticFormatterCallback: (current) =>
                            '${(current * 100).round()}%',
                        onChanged: (next) => value.value = next,
                      ),
                      AppProgressIndicator(value: progress),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(Slider), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(value.value, greaterThan(.2));
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, value.value);
      expect(
        tester.getSize(find.byType(LinearProgressIndicator)).height,
        greaterThanOrEqualTo(10),
      );
      expect(
        tester.widget<Slider>(find.byType(Slider)).semanticFormatterCallback!(
          .5,
        ),
        '50%',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'error illustration remains readable with retry on a small large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AppErrorState(
                message: '加载失败，请稍后重试',
                onRetry: () => retries++,
              ),
            ),
          ),
        ),
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppIcon && widget.icon == Icons.error_outline_rounded,
        ),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(
              find.byWidgetPredicate(
                (widget) =>
                    widget is AppIcon &&
                    widget.icon == Icons.error_outline_rounded,
              ),
            )
            .width,
        greaterThanOrEqualTo(64),
      );
      await tester.tap(find.text('重试'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
