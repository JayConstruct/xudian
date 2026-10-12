import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/frosted_toolbar_surface.dart';
import 'package:task_app/app/mobile_bottom_dock.dart';
import 'package:task_app/core/ui/app_destination.dart';
import 'package:task_app/core/ui/ui_component.dart';
import 'package:task_app/core/ui/ui_pack.dart';

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
  for (final useBase in [false, true]) {
    testWidgets(
      'AI remains available through ${useBase ? 'base' : 'navigation slot'} chrome recipe',
      (tester) async {
        final pack = UiPackDefinition.parse(
          moduleId: 'test.dock',
          version: '1.0.0',
          digest: 'dock-recipe',
          source: {
            'contractVersion': 1,
            'chrome': {
              'ui.chrome.bottomNav@1': {
                'tree': {
                  'type': 'primitive',
                  'name': 'column',
                  'children': [
                    {
                      'type': 'primitive',
                      'name': 'text',
                      'props': {'text': '自定义导航样式'},
                    },
                    if (useBase)
                      {'type': 'base'}
                    else ...[
                      {'type': 'slot', 'name': 'navigation'},
                      {'type': 'slot', 'name': 'input'},
                    ],
                  ],
                },
              },
            },
          },
        );
        var assistantCalls = 0;
        var selected = 0;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: UiPackScope(
                previewPacks: {'test.dock': pack},
                previewSelection: UiSelection(globalPackId: 'test.dock'),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: 360,
                      child: MobileBottomDock(
                        destinations: _destinations.take(2).toList(),
                        selectedIndex: 0,
                        showNavigation: true,
                        hasMore: false,
                        onSelected: (value) => selected = value,
                        onAssistant: () => assistantCalls++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('自定义导航样式'), findsOneWidget);
        expect(find.text('AI'), findsOneWidget);
        await tester.tap(find.text('AI'));
        await tester.pumpAndSettle();
        expect(assistantCalls, 1);
        expect(selected, 0);
        await tester.tap(find.text('页面 1'));
        await tester.pumpAndSettle();
        expect(selected, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final direction in TextDirection.values) {
    testWidgets(
      'More is a capsule destination and AI is independent in ${direction.name}',
      (tester) async {
        final selected = ValueNotifier(1);
        addTearDown(selected.dispose);
        var assistantCalls = 0;
        final destinations = [
          AppDestination(
            id: 'app.shell.more',
            label: '更多',
            icon: Icons.apps_rounded,
            selectedIcon: Icons.apps_rounded,
            builder: (_) => const SizedBox.shrink(),
          ),
          ..._destinations.take(2),
        ];
        await _pumpDock(
          tester,
          selected,
          destinations: destinations,
          direction: direction,
          hasMore: false,
          onAssistant: () => assistantCalls++,
        );
        final capsule = find.byKey(const ValueKey('mobile-navigation-capsule'));
        expect(
          find.descendant(of: capsule, matching: find.text('更多')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mobile-navigation-more')),
          findsNothing,
        );
        await tester.tap(find.text('AI'));
        await tester.pumpAndSettle();
        expect(assistantCalls, 1);
        expect(selected.value, 1);
        await tester.tap(find.text('更多'));
        await tester.pumpAndSettle();
        expect(selected.value, 0);
        _expectSelected(tester, 0, label: '更多');
        await _pumpDock(
          tester,
          selected,
          destinations: destinations,
          direction: direction,
          hasMore: false,
        );
        expect(find.text('AI'), findsNothing);
        expect(find.text('更多'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'pressed lens lifts outside the glass and returns inside on release',
    (tester) async {
      final selected = ValueNotifier(1);
      addTearDown(selected.dispose);
      await _pumpDock(tester, selected);
      final surface = find.byType(FrostedToolbarSurface);
      final indicator = find.byKey(
        const ValueKey('mobile-navigation-indicator'),
      );
      final rest = tester.getRect(indicator);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('页面 1')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final raised = tester.getRect(indicator);
      expect(raised.top, lessThan(tester.getRect(surface).top - 5));
      expect(raised.bottom, greaterThan(tester.getRect(surface).bottom + 5));
      expect(raised.width, greaterThan(rest.width + 20));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(indicator), rest);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'continuous pointer updates keep the lens moving and stretch it by speed',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await _pumpDock(tester, selected);
      final indicator = find.byKey(
        const ValueKey('mobile-navigation-indicator'),
      );
      final start = tester.getCenter(find.text('页面 0'));
      final gesture = await tester.startGesture(start);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final raisedWidth = tester.getRect(indicator).width;
      for (var frame = 1; frame <= 12; frame++) {
        await gesture.moveTo(start + Offset(frame * 10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getCenter(indicator).dx, greaterThan(start.dx + 50));
      expect(tester.getRect(indicator).width, greaterThan(raisedWidth + 5));
      expect(selected.value, 0);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.getCenter(indicator).dx, closeTo(start.dx, .01));
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'edge pulling is resisted and cancellation restores the dock in ${direction.name}',
      (tester) async {
        final selected = ValueNotifier(3);
        addTearDown(selected.dispose);
        await _pumpDock(tester, selected, direction: direction);
        final surface = find.byType(FrostedToolbarSurface);
        final rest = tester.getRect(surface);
        final start = tester.getCenter(find.text('页面 3'));
        final sign = direction == TextDirection.ltr ? 1.0 : -1.0;
        final gesture = await tester.startGesture(start);
        await gesture.moveTo(start + Offset(sign * 300, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        final pulled = tester.getRect(surface);
        expect((pulled.center.dx - rest.center.dx) * sign, greaterThan(3));
        expect((pulled.center.dx - rest.center.dx).abs(), lessThan(25));
        expect(pulled.width, greaterThan(rest.width));
        expect(selected.value, 3);
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(tester.getRect(surface), rest);
        expect(selected.value, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('keyboard activation switches the focused destination', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await _pumpDock(tester, selected);
    Focus.of(tester.element(find.text('页面 2'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected.value, 2);
    _expectSelected(tester, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a vertical cancelled touch does not activate another page', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await _pumpDock(tester, selected);
    final start = tester.getCenter(find.text('页面 2'));
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(0, -60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected.value, 0);
    _expectSelected(tester, 0);
    expect(tester.takeException(), isNull);
  });

  for (final target in [
    'mobile-navigation-capsule',
    'mobile-navigation-more',
  ]) {
    testWidgets(
      '$target grows on press and springs back without changing insets',
      (tester) async {
        final selected = ValueNotifier(0);
        addTearDown(selected.dispose);
        await _pumpDock(tester, selected, hasMore: true);
        final slot = find.byKey(ValueKey(target));
        final surface = find.descendant(
          of: slot,
          matching: find.byType(FrostedToolbarSurface),
        );
        final layout = tester.getSize(
          find.byKey(const ValueKey('mobile-bottom-dock')),
        );
        final rest = tester.getRect(surface);
        final gesture = await tester.startGesture(
          target.endsWith('more')
              ? rest.center
              : tester.getCenter(find.text('页面 0')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        expect(tester.getRect(surface).width, greaterThan(rest.width * 1.02));
        expect(selected.value, 0);
        expect(
          tester.getSize(find.byKey(const ValueKey('mobile-bottom-dock'))),
          layout,
        );
        await gesture.cancel();
        await tester.pump();
        var reboundedPastRest = false;
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 40));
          reboundedPastRest |= tester.getRect(surface).width < rest.width - .01;
          expect(
            tester.getSize(find.byKey(const ValueKey('mobile-bottom-dock'))),
            layout,
          );
        }
        expect(reboundedPastRest, isTrue);
        await tester.pumpAndSettle();
        expect(tester.getRect(surface).width, closeTo(rest.width, .01));
        expect(selected.value, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a new press during rebound stays continuous and returns to rest',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await _pumpDock(tester, selected);
      final surface = find.byType(FrostedToolbarSurface);
      final rest = tester.getRect(surface);
      final first = await tester.startGesture(
        tester.getCenter(find.text('页面 0')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await first.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final interruptedWidth = tester.getRect(surface).width;
      final second = await tester.startGesture(
        tester.getCenter(find.text('页面 0')),
      );
      await tester.pump();
      expect(tester.getRect(surface).width, closeTo(interruptedWidth, .01));
      await tester.pump(const Duration(milliseconds: 150));
      await second.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(surface).width, closeTo(rest.width, .01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion keeps pressed surfaces and lens at rest size', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await _pumpDock(tester, selected, disableAnimations: true, hasMore: true);
    final surface = find.byType(FrostedToolbarSurface).first;
    final indicator = find.byKey(const ValueKey('mobile-navigation-indicator'));
    final rest = tester.getRect(surface);
    final lensRest = tester.getRect(indicator);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('页面 0')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(surface), rest);
    expect(tester.getRect(indicator), lensRest);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(surface), rest);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'enabling reduced motion during a press settles and cancels the old touch',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await _pumpDock(tester, selected);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('页面 2')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      await _pumpDock(tester, selected, disableAnimations: true);
      final indicator = find.byKey(
        const ValueKey('mobile-navigation-indicator'),
      );
      final stopped = tester.getRect(indicator);
      expect(
        stopped.center.dx,
        closeTo(tester.getCenter(find.text('页面 0')).dx, .01),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getRect(indicator), stopped);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected.value, 0);
      await tester.tap(find.text('页面 2'));
      await tester.pumpAndSettle();
      expect(selected.value, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'releasing a drag at a slot center switches from tracking to rebound',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await _pumpDock(tester, selected);
      final target = tester.getCenter(find.text('页面 1')).dx;
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('页面 0')),
      );
      await tester.pump();
      await gesture.moveTo(
        Offset(target, tester.getCenter(find.text('页面 0')).dy),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();
      final indicator = find.byKey(
        const ValueKey('mobile-navigation-indicator'),
      );
      var overshot = false;
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        overshot |= tester.getCenter(indicator).dx > target + .1;
      }
      expect(overshot, isTrue);
      await tester.pumpAndSettle();
      expect(tester.getCenter(indicator).dx, closeTo(target, .01));
      expect(selected.value, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'press previews the lens and release commits in ${direction.name}',
      (tester) async {
        final selected = ValueNotifier(0);
        addTearDown(selected.dispose);
        await _pumpDock(tester, selected, direction: direction);
        final indicator = find.byKey(
          const ValueKey('mobile-navigation-indicator'),
        );
        final before = tester.getCenter(indicator).dx;
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('页面 2')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        expect(selected.value, 0);
        final actual = tester.getCenter(indicator).dx;
        final target = tester.getCenter(find.text('页面 2')).dx;
        expect((actual - target).abs(), lessThan((before - target).abs() / 4));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(selected.value, 2);
        expect(
          tester.getCenter(indicator).dx,
          closeTo(tester.getCenter(find.text('页面 2')).dx, .01),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'capsule follows selection without moving icons or labels in ${direction.name}',
      (tester) async {
        final selected = ValueNotifier(0);
        addTearDown(selected.dispose);
        await _pumpDock(tester, selected, direction: direction);
        final before = [
          for (var i = 0; i < 4; i++) tester.getRect(find.text('页面 $i')),
        ];
        _expectSelected(tester, 0);
        expect(find.byIcon(Icons.circle_outlined), findsNWidgets(4));
        expect(find.byIcon(Icons.circle), findsNothing);
        expect(
          find.byKey(const ValueKey('mobile-navigation-indicator')),
          findsOneWidget,
        );
        selected.value = 3;
        await tester.pumpAndSettle();
        _expectSelected(tester, 3);
        for (var i = 0; i < 4; i++) {
          expect(tester.getRect(find.text('页面 $i')).center, before[i].center);
        }
        expect(
          tester
              .getCenter(
                find.byKey(const ValueKey('mobile-navigation-indicator')),
              )
              .dx,
          closeTo(tester.getCenter(find.text('页面 3')).dx, .01),
        );
        expect(find.byIcon(Icons.circle_outlined), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final direction in TextDirection.values) {
    testWidgets(
      'scrubbing previews locally and switches once on release in ${direction.name}',
      (tester) async {
        final selected = ValueNotifier(0);
        addTearDown(selected.dispose);
        var changes = 0;
        selected.addListener(() => changes++);
        await _pumpDock(tester, selected, direction: direction);
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('页面 0')),
        );
        await gesture.moveTo(tester.getCenter(find.text('页面 3')));
        await tester.pump();
        expect(selected.value, 0);
        expect(changes, 0);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(selected.value, 3);
        expect(changes, 1);
        _expectSelected(tester, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('cancelled scrubbing returns to the current page', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await _pumpDock(tester, selected);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('页面 0')),
    );
    await gesture.moveTo(tester.getCenter(find.text('页面 2')));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(selected.value, 0);
    _expectSelected(tester, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact capsule and More are separate and both remain tappable',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await _pumpDock(
        tester,
        selected,
        destinations: _destinations.take(3).toList(),
        hasMore: true,
      );
      final capsule = tester.getRect(
        find.byKey(const ValueKey('mobile-navigation-capsule')),
      );
      final more = tester.getRect(
        find.byKey(const ValueKey('mobile-navigation-more')),
      );
      expect(capsule.width + more.width, lessThan(360));
      expect(capsule.right, lessThan(more.left));
      expect(more.width, more.height);
      expect(more.width, greaterThanOrEqualTo(kMinInteractiveDimension));
      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();
      expect(selected.value, 3);
      _expectSelected(tester, 3, label: '更多');
      expect(tester.takeException(), isNull);
    },
  );

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
    _expectSelected(tester, 1);

    await tester.tap(find.text('页面 2'));
    await tester.pumpAndSettle();
    expect(selected.value, 2);
    _expectSelected(tester, 2);
  });

  testWidgets('reduced motion updates selection without animation', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await _pumpDock(tester, selected, disableAnimations: true);

    selected.value = 2;
    await tester.pump();
    _expectSelected(tester, 2);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byType(AnimatedSize), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overflow destinations select the more slot', (tester) async {
    final selected = ValueNotifier(5);
    addTearDown(selected.dispose);
    await _pumpDock(tester, selected, destinations: _destinations);
    _expectSelected(tester, 4, label: '更多');
    expect(find.text('更多'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large text keeps all destinations tappable with the input dock',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await _pumpDock(
        tester,
        selected,
        destinations: _destinations,
        textScale: 2,
        input: const TextField(),
      );
      expect(find.byType(TextField), findsOneWidget);
      for (final label in ['页面 0', '页面 1', '页面 2', '页面 3', '更多']) {
        final target = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.selected != null,
          ),
        );
        final size = tester.getSize(target);
        expect(size.width, greaterThanOrEqualTo(kMinInteractiveDimension));
        expect(size.height, greaterThanOrEqualTo(kMinInteractiveDimension));
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
      expect(selected.value, 4);
      expect(tester.takeException(), isNull);
      await _pumpDock(
        tester,
        selected,
        input: const TextField(),
        showNavigation: false,
      );
      expect(find.byKey(const ValueKey('mobile-navigation')), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
  double textScale = 1,
  Widget? input,
  bool showNavigation = true,
  bool? hasMore,
  VoidCallback? onAssistant,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: disableAnimations,
          highContrast: highContrast,
          textScaler: TextScaler.linear(textScale),
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
                    showNavigation: showNavigation,
                    hasMore: hasMore,
                    onAssistant: onAssistant,
                    input: input,
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

void _expectSelected(WidgetTester tester, int index, {String? label}) {
  final selectedLabel = find.text(label ?? '页面 $index');
  final style = tester
      .widget<AnimatedDefaultTextStyle>(
        find
            .ancestor(
              of: selectedLabel,
              matching: find.byType(AnimatedDefaultTextStyle),
            )
            .first,
      )
      .style;
  expect(
    style.color,
    Theme.of(tester.element(selectedLabel)).colorScheme.primary,
  );
  expect(style.fontWeight, FontWeight.w600);
  final semantics = tester
      .widgetList<Semantics>(
        find.ancestor(of: selectedLabel, matching: find.byType(Semantics)),
      )
      .singleWhere((widget) => widget.properties.selected != null);
  expect(semantics.properties.selected, isTrue);
}
