import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/script_motion.dart';
import 'package:task_app/core/ui/script_swipe_actions.dart';
import 'package:task_app/core/ui/script_ui_scope.dart';
import 'package:task_app/core/ui/ui_component.dart';
import 'package:task_app/core/ui/ui_icons.dart';
import 'package:task_app/core/ui/ui_pack.dart';
import 'package:task_app/core/module_host/json_schema.dart';

ScriptSwipeConfig config({
  bool enabled = true,
  String label = '执行',
  Object? revision,
  bool longPress = false,
  String? icon,
}) => ScriptSwipeConfig.parse({
  'type': 'swipeActions',
  'key': 'row',
  'enabled': enabled,
  'extent': 100,
  if (longPress) 'menuTrigger': 'longPress',
  'revision': ?revision,
  'actions': [
    {
      'label': label,
      'icon': ?icon,
      'event': {'type': label},
    },
  ],
}, appIconData);

void main() {
  testWidgets(
    'narrow row menu is keyboard accessible and drops stale actions',
    (tester) async {
      final revision = ValueNotifier(0);
      addTearDown(revision.dispose);
      final events = <Object?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(
                width: 90,
                child: ValueListenableBuilder<int>(
                  valueListenable: revision,
                  builder: (_, version, _) => ScriptSwipeActions(
                    config: config(revision: version, longPress: true),
                    canSwipe: false,
                    onAction: (action) async => events.add(action.event),
                    child: const Focus(
                      autofocus: true,
                      child: SizedBox(height: 60, child: Text('row')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('更多操作'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('workspace-menu-surface'));
      expect(
        tester.getBottomRight(menu).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text('row')).dy),
      );
      revision.value++;
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
      expect(events, isEmpty);
      await tester.longPress(find.text('row'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('执行'));
      await tester.pumpAndSettle();
      expect(events, [
        {'type': '执行'},
      ]);
      expect(tester.takeException(), isNull);
    },
  );
  for (final fallback in [false, true]) {
    testWidgets(
      'lost pointer on ${fallback ? 'menu fallback' : 'page inactivity'} does not block a new gesture',
      (tester) async {
        final enabled = ValueNotifier(true);
        addTearDown(enabled.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: enabled,
                builder: (_, value, _) => ScriptUiScope(
                  active: fallback || value,
                  busy: false,
                  child: ScriptSwipeActions(
                    config: config(),
                    canSwipe: !fallback || value,
                    onAction: (_) async {},
                    child: const SizedBox(
                      height: 100,
                      child: Center(child: Text('row')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final first = await tester.startGesture(
          tester.getCenter(find.text('row')),
          pointer: 1,
        );
        await first.moveBy(const Offset(-90, 0));
        await tester.pump();
        enabled.value = false;
        await tester.pumpAndSettle();
        // Deliberately withhold the old pointer's up/cancel as Android may do.
        enabled.value = true;
        await tester.pumpAndSettle();
        final second = await tester.startGesture(
          tester.getCenter(find.text('row')),
          pointer: 2,
        );
        await second.moveBy(const Offset(-150, 0));
        await second.up();
        await tester.pumpAndSettle();
        expect(find.text('执行').hitTestable(), findsOneWidget);
        await first.cancel();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'resolved shared schema fixtures agree with native configuration parsing',
    () {
      final cases = jsonDecode(
        File('../packages/examples/ui-motion-v1-cases.json').readAsStringSync(),
      ) as List;
      for (final fixture in cases.cast<Map>()) {
        final node = (fixture['resolved'] ?? fixture['node']) as Map;
        void parse() {
          if (node['type'] == 'motion') {
            ScriptMotionValue.parse(node['target']);
            if (node.containsKey('timing')) ScriptTiming.parse(node['timing']);
          } else {
            ScriptSwipeConfig.parse(node.cast<String, Object?>(), (_) => null);
          }
        }

        expect(
          parse,
          fixture['valid'] == true ? returnsNormally : throwsFormatException,
          reason: fixture['name'] as String,
        );
      }
    },
  );
  test('new configurations fail closed on invalid values', () {
    for (final invalid in [
      <String, Object?>{},
      {'opacity': double.nan},
      {'scale': 0},
      {'translateY': 4097},
      {'rotation': 1},
      {'opacity': null},
    ]) {
      expect(() => ScriptMotionValue.parse(invalid), throwsFormatException);
    }
    for (final invalid in [
      {'duration': .5},
      {'duration': -1},
      {'curve': 'unknown'},
      {'duration': null},
    ]) {
      expect(() => ScriptTiming.parse(invalid), throwsFormatException);
    }
    expect(
      () => ScriptButtonFeedback.parse({'pressedScale': .5}),
      throwsFormatException,
    );
    expect(
      () => ScriptSwipeConfig.parse({'extent': 48, 'actions': []}, (_) => null),
      throwsFormatException,
    );
    expect(
      () => ScriptSwipeConfig.parse({
        'extent': 48,
        'actions': [
          {'label': 'A', 'event': {}},
          {'label': 'B', 'event': {}},
        ],
      }, (_) => null),
      throwsFormatException,
    );
    expect(
      () => ScriptSwipeConfig.parse({
        'extent': 96,
        'actions': [
          {'label': 'A', 'event': {}, 'command': {}},
        ],
      }, (_) => null),
      throwsFormatException,
    );
  });

  testWidgets(
    'motion preserves progress on reversal and stops on page inactivity',
    (tester) async {
      final target = ValueNotifier(0.0), active = ValueNotifier(true);
      addTearDown(target.dispose);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: active,
              builder: (_, enabled, _) => ScriptUiScope(
                active: enabled,
                busy: false,
                child: ValueListenableBuilder(
                  valueListenable: target,
                  builder: (_, x, _) => ScriptMotion(
                    target: ScriptMotionValue(x: x),
                    timing: const ScriptTiming(
                      duration: Duration(milliseconds: 1000),
                      curve: Curves.linear,
                    ),
                    child: const Text('static'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      double x() => tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byType(ScriptMotion),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .storage[12];
      final element = tester.element(find.text('static'));
      expect(x(), 0);
      target.value = 100;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(x(), closeTo(40, .01));
      target.value = 0;
      await tester.pump();
      expect(x(), closeTo(40, .01));
      await tester.pump(const Duration(milliseconds: 200));
      expect(x(), closeTo(32, .01));
      active.value = false;
      await tester.pump();
      expect(x(), 0);
      final resources = tester
          .widget<ScriptUiEnvironment>(find.byType(ScriptUiEnvironment))
          .resources;
      expect(resources.activeAnimations, 0);
      active.value = true;
      await tester.pump();
      expect(x(), 0);
      expect(tester.element(find.text('static')), same(element));
      await tester.pumpWidget(const SizedBox());
      expect(resources.activeAnimations, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion is immediate and feedback uses the original button',
    (tester) async {
      var taps = 0;
      final target = ValueNotifier(1.0);
      addTearDown(target.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: target,
                builder: (_, scale, _) => Column(
                  children: [
                    ScriptMotion(
                      target: ScriptMotionValue(scale: scale),
                      child: const Text('preview'),
                    ),
                    ScriptFeedbackButton(
                      feedback: ScriptButtonFeedback.parse({}),
                      onPressed: () => taps++,
                      child: const Text('press'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      target.value = .9;
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.tap(find.text('press'));
      await tester.pump();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('public default button accepts feedback and invokes press once', (
    tester,
  ) async {
    var taps = 0;
    final props = <String, Object?>{
      'label': 'public',
      'feedback': {'pressedScale': .95},
    };
    validateSchema(props, uiContracts['ui.button@1']!.propsSchema);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: defaultUiComponent('ui.button@1', props, const {}, {
            'press': (_) => taps++,
          }),
        ),
      ),
    );
    await tester.tap(find.text('public'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.byType(ScriptFeedbackButton), findsOneWidget);
  });

  testWidgets(
    'horizontal reveal is local, vertical drag scrolls, and action locks until completion',
    (tester) async {
      var calls = 0;
      final done = Completer<void>();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptUiScope(
              active: true,
              busy: false,
              child: ListView(
                controller: scroll,
                children: [
                  ScriptSwipeActions(
                    config: config(icon: 'calendarAdd'),
                    canSwipe: true,
                    onAction: (_) async {
                      calls++;
                      await done.future;
                    },
                    child: const SizedBox(
                      height: 100,
                      child: Center(child: Text('row')),
                    ),
                  ),
                  const SizedBox(height: 1600),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.text('row'), const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('执行').hitTestable(), findsOneWidget);
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<AppIconPainter>()
            .map((painter) => painter.glyph),
        contains(AppGlyph.calendarAdd),
      );
      await tester.tap(find.text('执行').hitTestable());
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '更多操作',
              ),
            )
            .onPressed,
        isNull,
      );
      done.complete();
      await tester.pumpAndSettle();
      await tester.drag(find.text('row'), const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('menu fallback remains operable and closes when inactive', (
    tester,
  ) async {
    var calls = 0;
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: active,
            builder: (_, value, _) => ScriptUiScope(
              active: value,
              busy: false,
              child: ScriptSwipeActions(
                config: config(),
                canSwipe: false,
                onAction: (_) async {
                  calls++;
                },
                child: const SelectableText('selectable'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsOneWidget);
    await tester.tap(find.text('执行'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    active.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('second pointer cancels reveal without firing an action', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScriptUiScope(
            active: true,
            busy: false,
            child: ScriptSwipeActions(
              config: config(),
              canSwipe: true,
              onAction: (_) async {
                calls++;
              },
              child: const SizedBox(
                height: 100,
                child: Center(child: Text('row')),
              ),
            ),
          ),
        ),
      ),
    );
    final first = await tester.startGesture(
      tester.getCenter(find.text('row')),
      pointer: 1,
    );
    await first.moveBy(const Offset(-100, 0));
    await tester.pump();
    final second = await tester.startGesture(
      tester.getCenter(find.text('row')),
      pointer: 2,
    );
    await tester.pump();
    await second.up();
    await first.up();
    await tester.pumpAndSettle();
    expect(find.text('执行').hitTestable(), findsNothing);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });
}
