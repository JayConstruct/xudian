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

  testWidgets('duplicate notices keep animation and original deadline', (
    tester,
  ) async {
    late BuildContext source;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            source = context;
            return const Scaffold();
          },
        ),
      ),
    );
    AppToast.show(
      source,
      message: '已保存',
      kind: 'success',
      duration: const Duration(seconds: 1),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final fade = find
        .ancestor(of: find.text('已保存'), matching: find.byType(FadeTransition))
        .first;
    final opacity = tester.widget<FadeTransition>(fade).opacity;
    expect(opacity.value, greaterThan(0));
    expect(opacity.value, lessThan(1));
    AppToast.show(
      source,
      message: '已保存',
      kind: 'success',
      duration: const Duration(seconds: 10),
    );
    await tester.pump();
    expect(tester.widget<FadeTransition>(fade).opacity, same(opacity));
    await tester.pump(const Duration(milliseconds: 910));
    await tester.pump(AppToast.exitDuration);
    await tester.pump();
    expect(find.text('已保存'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a repeated message can be shown while the old one exits', (
    tester,
  ) async {
    late BuildContext source;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            source = context;
            return const Scaffold();
          },
        ),
      ),
    );
    AppToast.show(source, message: '提示');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pump(const Duration(milliseconds: 50));
    AppToast.show(source, message: '提示');
    await tester.pumpAndSettle();
    expect(find.text('提示'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pumpAndSettle();
    expect(find.text('提示'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tearing down an overlay does not leave a stale notice', (
    tester,
  ) async {
    late BuildContext source;
    Widget app() => MaterialApp(
      home: Builder(
        builder: (context) {
          source = context;
          return const Scaffold();
        },
      ),
    );
    await tester.pumpWidget(app());
    AppToast.show(source, message: '旧窗口');
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    AppToast.show(source, message: '新窗口');
    await tester.pumpAndSettle();
    expect(find.text('新窗口'), findsOneWidget);
    expect(find.text('旧窗口'), findsNothing);
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('independent root overlays own their notices', (tester) async {
    late BuildContext left, right;
    await tester.pumpWidget(
      Row(
        textDirection: TextDirection.ltr,
        children: [
          Expanded(
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  left = context;
                  return const Scaffold();
                },
              ),
            ),
          ),
          Expanded(
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  right = context;
                  return const Scaffold();
                },
              ),
            ),
          ),
        ],
      ),
    );
    AppToast.show(left, message: '左侧窗口');
    AppToast.show(right, message: '右侧窗口');
    await tester.pumpAndSettle();
    expect(find.text('左侧窗口'), findsOneWidget);
    expect(find.text('右侧窗口'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭提示').first);
    await tester.pumpAndSettle();
    expect(find.text('左侧窗口'), findsNothing);
    expect(find.text('右侧窗口'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long large text remains scrollable above the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    late BuildContext source;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2.5),
            padding: const EdgeInsets.only(top: 24),
            viewInsets: const EdgeInsets.only(bottom: 280),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            source = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final message = '长文本演示，正文可以滚动并保留关闭操作。' * 10;
    AppToast.show(
      source,
      message: message,
      kind: 'error',
      duration: const Duration(seconds: 10),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('错误'), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    final close = tester.getRect(find.byTooltip('关闭提示'));
    expect(close.top, greaterThanOrEqualTo(36));
    expect(close.bottom, lessThanOrEqualTo(360));
    final card = find
        .ancestor(of: find.text(message), matching: find.byType(Material))
        .first;
    expect(tester.getRect(card).top, 36);
    expect(tester.getRect(card).bottom, lessThanOrEqualTo(348));
    final scrollable = find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(scrollable, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
