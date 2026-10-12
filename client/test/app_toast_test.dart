import 'package:task_app/app/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app_toast.dart';

void main() {
  testWidgets(
    'floating toast adapts on narrow screens and allows page interaction',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var clicks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => AppToast.show(
                      context,
                      message: '设置已保存，可随时重新调整显示选项',
                      kind: 'success',
                    ),
                    child: const Text('提示'),
                  ),
                  const SizedBox(height: 200),
                  TextButton(
                    onPressed: () => clicks++,
                    child: const Text('页面操作'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final before = tester.getRect(find.text('页面操作'));
      await tester.tap(find.text('提示'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppIcon &&
              widget.icon == Icons.check_circle_outline_rounded,
        ),
        findsOneWidget,
      );
      final notice = tester.getRect(find.text('设置已保存，可随时重新调整显示选项'));
      expect(notice.left, greaterThanOrEqualTo(12));
      expect(notice.right, lessThanOrEqualTo(308));
      expect(tester.getRect(find.text('页面操作')), before);
      await tester.tap(find.text('页面操作'));
      expect(clicks, 1);
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pumpAndSettle();
      expect(find.text('设置已保存，可随时重新调整显示选项'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'notices replace previous content, expire, and respect reduced motion',
    (tester) async {
      late BuildContext source;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                source = context;
                return const Text('content');
              },
            ),
          ),
        ),
      );
      AppToast.show(
        source,
        message: 'first notice',
        duration: const Duration(seconds: 1),
      );
      await tester.pump();
      final fade = find
          .ancestor(
            of: find.text('first notice'),
            matching: find.byType(FadeTransition),
          )
          .first;
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      AppToast.show(
        source,
        message: 'second notice',
        kind: 'error',
        duration: const Duration(seconds: 1),
      );
      await tester.pump();
      expect(find.text('first notice'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppIcon && widget.icon == Icons.error_outline_rounded,
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('second notice'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('toast remains reachable above a modal panel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (panel) => SizedBox(
                  height: 300,
                  child: Center(
                    child: TextButton(
                      onPressed: () =>
                          AppToast.show(panel, message: 'panel notice'),
                      child: const Text('panel action'),
                    ),
                  ),
                ),
              ),
              child: const Text('open panel'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open panel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('panel action'));
    await tester.pumpAndSettle();
    expect(find.text('panel notice'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pumpAndSettle();
    expect(find.text('panel notice'), findsNothing);
    expect(find.text('panel action'), findsOneWidget);
  });
}
