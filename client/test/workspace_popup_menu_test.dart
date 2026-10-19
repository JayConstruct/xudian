import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/workspace_popup_menu.dart';
import 'package:task_app/core/ui/ui_icon.dart';
import 'package:task_app/core/ui/workspace_header.dart';

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

  testWidgets(
    'touch submenu updates choices and zoom without closing and back preserves host menu',
    (tester) async {
      final controller = WorkspaceHeaderController();
      addTearDown(controller.dispose);
      final owner = Object();
      final lease = controller.activate(
        identity: 'planner',
        moduleId: 'planner',
        pageId: 'home',
        enabled: true,
        isActive: () => true,
      )!;
      var days = 5;
      var zoom = 1;
      var settings = 0;
      late void Function() publish;
      publish = () => controller.publish(
        lease,
        owner,
        {
          'title': '规划',
          'actions': [
            {
              'label': '新建',
              'overflowOnly': true,
              'event': {'type': 'add'},
            },
            {
              'label': '视图',
              'valueLabel': '$days天',
              'children': [
                {
                  'kind': 'choiceGrid',
                  'label': '显示天数',
                  'children': [
                    for (final value in [3, 5, 7])
                      {
                        'label': '$value天',
                        'selected': days == value,
                        'event': {'type': 'days', 'value': value},
                      },
                  ],
                },
                {
                  'kind': 'stepper',
                  'label': '时间轴缩放',
                  'valueLabel': zoom == 1 ? '标准' : '放大',
                  'decreaseEnabled': zoom > 1,
                  'increaseEnabled': zoom < 2,
                  'decreaseEvent': {'type': 'zoom', 'value': -1},
                  'increaseEvent': {'type': 'zoom', 'value': 1},
                },
              ],
            },
          ],
        },
        (event) async {
          final data = event as Map;
          if (data['type'] == 'days') days = data['value'] as int;
          if (data['type'] == 'zoom') zoom += data['value'] as int;
          publish();
        },
      );
      publish();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                WorkspacePopupMenu(
                  headerController: controller,
                  headerOwner: owner,
                  headerLease: lease,
                  inlineActionLabels: const {'新建'},
                  onSelected: (_) => settings++,
                  items: const [PopupMenuItem(value: -1, child: Text('设置'))],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('页面菜单'));
      await tester.pumpAndSettle();
      expect(find.text('新建'), findsNothing);
      expect(find.text('设置'), findsOneWidget);
      await tester.tap(find.text('视图'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7天'));
      await tester.pumpAndSettle();
      expect(days, 7);
      expect(find.text('显示天数'), findsOneWidget);
      expect(
        tester
            .widgetList<Semantics>(
              find.ancestor(
                of: find.text('7天'),
                matching: find.byType(Semantics),
              ),
            )
            .any((semantics) => semantics.properties.selected == true),
        isTrue,
      );
      await tester.tap(find.byTooltip('放大时间轴'));
      await tester.pumpAndSettle();
      expect(find.text('放大'), findsOneWidget);
      final increase = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('放大时间轴'),
          matching: find.byType(IconButton),
        ),
      );
      expect(increase.onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('7天'), findsOneWidget);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(settings, 1);
      expect(
        find.byKey(const ValueKey('workspace-menu-surface')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid zoom clicks dispatch serially using each latest contribution',
    (tester) async {
      final controller = WorkspaceHeaderController();
      addTearDown(controller.dispose);
      final owner = Object();
      final lease = controller.activate(
        identity: 'queue',
        moduleId: 'planner',
        pageId: 'home',
        enabled: true,
        isActive: () => true,
      )!;
      final gates = List.generate(3, (_) => Completer<void>());
      final started = <int>[];
      var zoom = 0;
      late void Function() publish;
      publish = () {
        final generation = zoom;
        controller.publish(lease, owner, _zoomHeader(zoom), (_) async {
          started.add(generation);
          await gates[generation].future;
          zoom++;
          publish();
        });
      };
      publish();
      await tester.pumpWidget(_queuedMenuApp(controller, owner, lease));
      await tester.tap(find.byTooltip('页面菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('视图'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('放大时间轴'));
      }
      expect(started, [0]);
      gates[0].complete();
      await tester.pumpAndSettle();
      expect(started, [0, 1]);
      expect(find.text('1级'), findsOneWidget);
      gates[1].complete();
      await tester.pumpAndSettle();
      expect(started, [0, 1, 2]);
      expect(find.text('2级'), findsOneWidget);
      gates[2].complete();
      await tester.pumpAndSettle();
      expect(zoom, 3);
      expect(find.text('3级'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final invalidate in [false, true]) {
    testWidgets(
      'queued clicks after popup closes ${invalidate ? 'discard inactive lease' : 'complete while lease remains active'}',
      (tester) async {
        final controller = WorkspaceHeaderController();
        addTearDown(controller.dispose);
        final owner = Object();
        var active = true;
        final lease = controller.activate(
          identity: 'queue',
          moduleId: 'planner',
          pageId: 'home',
          enabled: true,
          isActive: () => active,
        )!;
        final gate = Completer<void>();
        var calls = 0;
        controller.publish(lease, owner, _zoomHeader(0), (_) async {
          calls++;
          if (calls == 1) await gate.future;
        });
        await tester.pumpWidget(_queuedMenuApp(controller, owner, lease));
        await tester.tap(find.byTooltip('页面菜单'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('视图'));
        await tester.pumpAndSettle();
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byTooltip('放大时间轴'));
        }
        expect(calls, 1);
        await tester.tapAt(const Offset(10, 300));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('workspace-menu-surface')),
          findsNothing,
        );
        if (invalidate) active = false;
        gate.complete();
        await tester.pumpAndSettle();
        expect(calls, invalidate ? 1 : 3);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'stale contribution disappears while protected host settings remain callable',
    (tester) async {
      final controller = WorkspaceHeaderController();
      addTearDown(controller.dispose);
      final owner = Object();
      final lease = controller.activate(
        identity: 'old',
        moduleId: 'planner',
        pageId: 'home',
        enabled: true,
        isActive: () => true,
      )!;
      var calls = 0;
      controller.publish(
        lease,
        owner,
        {
          'title': '规划',
          'actions': [
            {
              'label': '筛选',
              'children': [
                {
                  'label': '旧操作',
                  'event': {'type': 'old'},
                },
              ],
            },
          ],
        },
        (_) async {
          calls++;
        },
      );
      var hostCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                WorkspacePopupMenu(
                  headerController: controller,
                  headerOwner: owner,
                  headerLease: lease,
                  onSelected: (_) => hostCalls++,
                  items: const [PopupMenuItem(value: -1, child: Text('设置'))],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('页面菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      controller.clear(owner);
      await tester.pumpAndSettle();
      expect(find.text('旧操作'), findsNothing);
      expect(find.text('设置'), findsOneWidget);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(hostCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

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

Map<String, Object?> _zoomHeader(int zoom) => {
  'title': '规划',
  'actions': [
    {
      'label': '视图',
      'children': [
        {
          'kind': 'stepper',
          'label': '时间轴缩放',
          'valueLabel': '$zoom级',
          'decreaseEvent': {'type': 'zoom', 'delta': -1},
          'increaseEvent': {'type': 'zoom', 'delta': 1},
        },
      ],
    },
  ],
};

Widget _queuedMenuApp(
  WorkspaceHeaderController controller,
  Object owner,
  WorkspaceHeaderLease lease,
) => MaterialApp(
  home: Scaffold(
    appBar: AppBar(
      actions: [
        WorkspacePopupMenu(
          headerController: controller,
          headerOwner: owner,
          headerLease: lease,
          onSelected: (_) {},
          items: const [PopupMenuItem(value: -1, child: Text('设置'))],
        ),
      ],
    ),
  ),
);
