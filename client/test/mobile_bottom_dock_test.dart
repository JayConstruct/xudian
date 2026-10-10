import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/mobile_bottom_dock.dart';
import 'package:task_app/core/ui/app_destination.dart';

final _destinations = List.generate(
  6,
  (index) => AppDestination(
    id: 'destination-$index',
    label: '页面 $index',
    icon: Icons.circle_outlined,
    selectedIcon: Icons.circle,
    builder: (_) => const SizedBox.shrink(),
  ),
);

void main() {
  for (final direction in TextDirection.values) {
    testWidgets(
      'indicator translates without navigation layout in ${direction.name}',
      (tester) async {
        final selected = ValueNotifier(0);
        addTearDown(selected.dispose);
        await _pumpDock(tester, selected, direction: direction);
        final navigation = find.byKey(const ValueKey('mobile-navigation'));
        final stack = tester.renderObject<RenderStack>(
          find.descendant(of: navigation, matching: find.byType(Stack)),
        );
        _expectIndicatorAt(tester, 0, direction: direction);

        selected.value = 3;
        await tester.pump();
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(
            const Duration(milliseconds: 16),
            EnginePhase.build,
          );
          expect(stack.debugNeedsLayout, isFalse);
          await tester.pump();
        }
        await tester.pumpAndSettle();
        _expectIndicatorAt(tester, 3, direction: direction);
        expect(find.byType(AnimatedPositionedDirectional), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('rapid selection changes settle on the latest destination', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await _pumpDock(tester, selected);

    selected.value = 3;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 64));
    selected.value = 1;
    await tester.pumpAndSettle();
    _expectIndicatorAt(tester, 1);

    await tester.tap(find.text('页面 2'));
    await tester.pumpAndSettle();
    expect(selected.value, 2);
    _expectIndicatorAt(tester, 2);
  });

  testWidgets('reduced motion updates the indicator without animation', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await _pumpDock(tester, selected, disableAnimations: true);

    selected.value = 2;
    await tester.pump();
    _expectIndicatorAt(tester, 2);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byType(AnimatedSize), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overflow destinations select the more slot', (tester) async {
    final selected = ValueNotifier(5);
    addTearDown(selected.dispose);
    await _pumpDock(tester, selected, destinations: _destinations);
    _expectIndicatorAt(tester, 4, count: 5);
    expect(find.text('更多'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('high contrast skips background blur', (tester) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await _pumpDock(tester, selected, highContrast: true);
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isFalse,
    );

    await _pumpDock(tester, selected);
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isTrue,
    );
  });
}

Future<void> _pumpDock(
  WidgetTester tester,
  ValueNotifier<int> selected, {
  TextDirection direction = TextDirection.ltr,
  bool disableAnimations = false,
  bool highContrast = false,
  List<AppDestination>? destinations,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: disableAnimations,
          highContrast: highContrast,
        ),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 360,
                child: ValueListenableBuilder<int>(
                  valueListenable: selected,
                  builder: (context, selectedIndex, child) => MobileBottomDock(
                    destinations:
                        destinations ?? _destinations.take(4).toList(),
                    selectedIndex: selectedIndex,
                    onSelected: (index) => selected.value = index,
                    showNavigation: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectIndicatorAt(
  WidgetTester tester,
  int index, {
  TextDirection direction = TextDirection.ltr,
  int count = 4,
}) {
  final navigation = tester.getRect(
    find.byKey(const ValueKey('mobile-navigation')),
  );
  final indicator = tester.getRect(
    find.byKey(const ValueKey('mobile-navigation-indicator')),
  );
  final distance = navigation.width / count * (index + 0.5);
  final expected = direction == TextDirection.ltr
      ? navigation.left + distance
      : navigation.right - distance;
  expect(indicator.center.dx, closeTo(expected, 0.01));
}
