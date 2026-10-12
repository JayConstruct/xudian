import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/workspace_popup_menu.dart';
import 'package:task_app/core/ui/ui_icon.dart';

void main() {
  testWidgets('circular ellipsis keeps a full 48dp touch target', (
    tester,
  ) async {
    await tester.pumpWidget(_app(onSelected: (_) {}));
    final button = find.byTooltip('页面菜单');
    final size = tester.getSize(button);
    expect(size.width, greaterThanOrEqualTo(kMinInteractiveDimension));
    expect(size.height, greaterThanOrEqualTo(kMinInteractiveDimension));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is UiIcon && widget.icon == Icons.more_horiz_rounded,
      ),
      findsOneWidget,
    );
    final widget = tester.widget<IconButton>(find.byType(IconButton));
    expect(widget.style!.shape!.resolve({}), isA<CircleBorder>());
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('whole menu fades and scales with scrim and one light impact', (
    tester,
  ) async {
    final feedback = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          feedback.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    int? selected;
    await tester.pumpWidget(_app(onSelected: (value) => selected = value));
    await tester.tap(find.byTooltip('页面菜单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final surface = find.byKey(const ValueKey('workspace-menu-surface'));
    final scale = tester.widget<ScaleTransition>(
      find.ancestor(of: surface, matching: find.byType(ScaleTransition)),
    );
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: surface, matching: find.byType(FadeTransition)),
    );
    expect(scale.scale.value, greaterThan(.94));
    expect(scale.scale.value, lessThan(1));
    expect(fade.opacity.value, greaterThan(0));
    expect(fade.opacity.value, lessThan(1));
    final barrier = tester
        .widgetList<ModalBarrier>(find.byType(ModalBarrier))
        .singleWhere((barrier) => barrier.color != null);
    expect(barrier.dismissible, isTrue);
    expect(barrier.color!.a, greaterThan(0));
    expect(barrier.color!.a, lessThan(.13));
    expect(feedback, ['HapticFeedbackType.lightImpact']);
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).width, 196);
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    expect(surface, findsNothing);
    expect(selected, isNull);
    await tester.tap(find.byTooltip('页面菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(selected, -1);
    expect(surface, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets(
      'large text stays within safe edges and back dismisses $direction',
      (tester) async {
        tester.view.physicalSize = const Size(320, 420);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _app(
            direction: direction,
            largeText: true,
            haptics: false,
            reduceMotion: true,
            onSelected: (_) => fail('Back must not select an entry'),
          ),
        );
        await tester.tap(find.byTooltip('页面菜单'));
        await tester.pumpAndSettle();
        final surface = find.byKey(const ValueKey('workspace-menu-surface'));
        final bounds = tester.getRect(surface);
        expect(bounds.left, greaterThanOrEqualTo(8));
        expect(bounds.right, lessThanOrEqualTo(312));
        expect(bounds.top, greaterThanOrEqualTo(32));
        expect(bounds.bottom, lessThanOrEqualTo(388));
        expect(find.text('完整显示的较长功能入口名称'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(surface, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _app({
  required ValueChanged<int> onSelected,
  TextDirection direction = TextDirection.ltr,
  bool largeText = false,
  bool haptics = true,
  bool reduceMotion = false,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      padding: const EdgeInsets.symmetric(vertical: 24),
      textScaler: TextScaler.linear(largeText ? 2 : 1),
    ),
    child: Directionality(textDirection: direction, child: child!),
  ),
  home: Scaffold(
    appBar: AppBar(
      actions: [
        WorkspacePopupMenu(
          haptics: haptics,
          reduceMotion: reduceMotion,
          onSelected: onSelected,
          items: [
            if (largeText)
              for (var i = 0; i < 8; i++)
                PopupMenuItem<int>(
                  value: i,
                  height: 44,
                  child: Text(i == 0 ? '完整显示的较长功能入口名称' : '入口 $i'),
                ),
            const PopupMenuItem<int>(value: -1, height: 44, child: Text('设置')),
          ],
        ),
      ],
    ),
  ),
);
