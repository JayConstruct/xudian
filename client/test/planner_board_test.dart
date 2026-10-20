import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_board.dart';

const _days = [
  {'date': '2026-10-15', 'label': '周四 10/15'},
  {'date': '2026-10-16', 'label': '周五 10/16'},
  {'date': '2026-10-17', 'label': '周六 10/17'},
  {'date': '2026-10-18', 'label': '周日 10/18'},
  {'date': '2026-10-19', 'label': '周一 10/19'},
];

Future<void> _mount(
  WidgetTester tester, {
  List<BoardItem> candidates = const [],
  List<BoardItem> blocks = const [],
  List<BoardItem> previewBlocks = const [],
  BoardItem options = const {},
  ValueChanged<Object?>? onEvent,
  TextScaler scaler = TextScaler.noScaling,
  BoardItem? selectEvent,
  List<Object?> selectedIds = const [],
  Future<BoardItem> Function(BoardItem)? onPreview,
  bool enabled = true,
  double bottomInset = 0,
  ValueChanged<bool>? onDragActiveChanged,
  bool quickAdjust = false,
  ValueChanged<bool>? onQuickAdjustChanged,
  BoardItem? pendingAdjustment,
  Object? previewIdentity,
  List<BoardItem> days = _days,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(800, 600), textScaler: scaler),
        child: Scaffold(
          body: PlannerBoard(
            days: days,
            candidates: candidates,
            blocks: blocks,
            previewBlocks: previewBlocks,
            options: options,
            onEvent: onEvent ?? (_) {},
            selectEvent: selectEvent,
            selectedIds: selectedIds,
            onPreview: onPreview,
            enabled: enabled,
            bottomInset: bottomInset,
            onDragActiveChanged: onDragActiveChanged,
            quickAdjust: quickAdjust,
            onQuickAdjustChanged: onQuickAdjustChanged,
            pendingAdjustment: pendingAdjustment,
            previewIdentity: previewIdentity,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

BoardItem _block(
  String id,
  String start,
  String end, {
  bool readOnly = false,
}) => {
  'id': id,
  'title': id,
  'start': start,
  'end': end,
  'event': {'action': 'detail', 'id': id},
  'moveEvent': {'action': 'move'},
  if (readOnly) 'readOnly': true,
};

Future<TestGesture> _dragTo(
  WidgetTester tester,
  Finder source,
  Offset point,
) async {
  final gesture = await tester.startGesture(tester.getCenter(source));
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(point - const Offset(0, 2));
  await tester.pump();
  await gesture.moveTo(point);
  await tester.pump(const Duration(milliseconds: 40));
  return gesture;
}

Offset _gridPoint(WidgetTester tester, int day, int minute) {
  final rect = tester.getRect(find.byType(DragTarget<BoardItem>));
  final board = tester.widget<PlannerBoard>(find.byType(PlannerBoard));
  return Offset(
    rect.left +
        rect.width / (board.days.isEmpty ? 5 : board.days.length) * day +
        35,
    rect.top + minute,
  );
}

List<BoardItem> _month() => List.generate(28, (index) {
  final date = DateTime.utc(
    2026,
    10,
    15 + index,
  ).toIso8601String().substring(0, 10);
  return {'date': date, 'label': date.substring(5)};
});

void main() {
  testWidgets('date rail tracks the visible portion of the scrollable days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, options: const {'dashboard': true});
    final rail = find.byKey(const ValueKey('planner-range-rail'));
    final toolbar = find.byKey(const ValueKey('planner-date-toolbar'));
    expect(tester.getSize(toolbar).height, lessThanOrEqualTo(52));
    expect(
      tester.getRect(rail).right,
      lessThan(tester.getRect(find.text('今天')).left),
    );
    expect(tester.widget<Semantics>(rail).properties.label, '当前可见第1至3天，共5天');
    final horizontal = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('planner-horizontal')),
        )
        .controller!;
    horizontal.jumpTo(112);
    await tester.pump();
    expect(tester.widget<Semantics>(rail).properties.label, '当前可见第2至4天，共5天');
    expect(find.byKey(const ValueKey('planner-range-visible:0')), findsNothing);
    expect(
      find.byKey(const ValueKey('planner-range-visible:3')),
      findsOneWidget,
    );
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pump();
    expect(tester.widget<Semantics>(rail).properties.label, '当前可见第3至5天，共5天');
    expect(tester.takeException(), isNull);
  });

  testWidgets('display zoom keeps the visible minute and horizontal position', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final blocks = [
      _block('缩放任务', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
    ];
    const options = {'dashboard': true, 'startMinute': 360, 'endMinute': 1440};
    await _mount(
      tester,
      blocks: blocks,
      options: {...options, 'pixelsPerMinute': 1},
    );
    final vertical = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('planner-vertical')),
        )
        .controller!;
    final horizontal = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('planner-horizontal')),
        )
        .controller!;
    vertical.jumpTo(240);
    horizontal.jumpTo(112);
    await tester.pump();
    await _mount(
      tester,
      blocks: blocks,
      options: {...options, 'pixelsPerMinute': 2},
    );
    expect(vertical.offset, 480);
    expect(horizontal.offset, 112);
    expect(tester.getSize(find.byType(DragTarget<BoardItem>)).height, 2160);
    expect(blocks.single['start'], '2026-10-15T09:00:00');
    await _mount(
      tester,
      blocks: blocks,
      options: {...options, 'pixelsPerMinute': .75},
    );
    // The compact toolbar can expose enough of the final day to reach the
    // bottom; preserve the requested minute up to that real scroll boundary.
    expect(vertical.offset, 180.0.clamp(0, vertical.position.maxScrollExtent));
    expect(horizontal.offset, 112);
    expect(tester.takeException(), isNull);
  });

  testWidgets('candidate tray restores horizontal offset after collapse', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(
      tester,
      candidates: List.generate(12, (i) => {'id': '$i', 'title': '候选$i'}),
      options: const {'dashboard': true},
    );
    final tray = find.byKey(const ValueKey('planner-candidates'));
    final controller = tester.widget<GridView>(tray).controller!;
    controller.jumpTo(200);
    await tester.pump();
    final toggle = find.byKey(const ValueKey('planner-toggle-candidates'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tray, findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<GridView>(tray).controller!.offset, 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'display hours comes from menu settings and refreshes cropped geometry',
    (tester) async {
      final events = <Object?>[];
      final blocks = [
        _block('上午任务', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
      ];
      await _mount(
        tester,
        blocks: blocks,
        options: {
          'dashboard': true,
          'startMinute': 480,
          'endMinute': 1320,
          'initialMinute': 480,
          'displayHoursLabel': '手动 08:00–22:00',
          'displayHoursEvent': {'type': 'displayHours'},
        },
        onEvent: events.add,
      );
      expect(find.byKey(const ValueKey('planner-display-hours')), findsNothing);
      expect(find.byIcon(Icons.schedule_outlined), findsNothing);
      expect(events, isEmpty);
      expect(tester.getSize(find.byType(DragTarget<BoardItem>)).height, 840);
      await _mount(
        tester,
        blocks: blocks,
        options: {'dashboard': true, 'startMinute': 600, 'endMinute': 660},
      );
      expect(tester.getSize(find.byType(DragTarget<BoardItem>)).height, 60);
      expect(find.text('显示范围外有 1 项安排 · 查看'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending icon reserves the actual start-time glyph at a narrow overlapping lane',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mount(
        tester,
        blocks: [
          _block(
            '课程',
            '2026-10-15T08:00:00',
            '2026-10-15T09:35:00',
            readOnly: true,
          ),
          _block('等待', '2026-10-15T11:00:00', '2026-10-15T12:00:00'),
        ],
        options: const {
          'dashboard': true,
          'initialMinute': 480,
          'minColumnWidth': 112,
        },
        enabled: false,
        pendingAdjustment: const {
          'id': '等待',
          'start': '2026-10-15T09:30:00',
          'end': '2026-10-15T10:30:00',
        },
      );
      final badge = find.byKey(const ValueKey('planner-saving:等待'));
      // The test font uses 50dp for HH:mm, so a 53dp lane must keep its
      // saving status semantic-only rather than draw over the time.
      expect(tester.getSize(badge), Size.zero);
      expect(find.byTooltip('保存中'), findsNothing);
      await _mount(
        tester,
        blocks: [
          _block(
            '课程',
            '2026-10-15T08:00:00',
            '2026-10-15T09:35:00',
            readOnly: true,
          ),
          _block('等待', '2026-10-15T11:00:00', '2026-10-15T12:00:00'),
        ],
        options: const {
          'dashboard': true,
          'initialMinute': 480,
          'minColumnWidth': 180,
        },
        enabled: false,
        pendingAdjustment: const {
          'id': '等待',
          'start': '2026-10-15T09:30:00',
          'end': '2026-10-15T10:30:00',
        },
      );
      expect(tester.getSize(badge), const Size(16, 12));
      final start = find.byKey(
        const ValueKey('block-time-start:等待:2026-10-15'),
      );
      final text = tester.widget<Text>(start);
      final painter = TextPainter(
        text: TextSpan(text: text.data, style: text.style),
        textDirection: TextDirection.ltr,
      )..layout();
      final glyph = tester.getTopLeft(start) & painter.size;
      painter.dispose();
      expect(tester.getRect(badge).overlaps(glyph), isFalse);
      expect(find.byTooltip('保存中'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending narrow large-text and minute-long bands keep only status semantics when an icon cannot fit',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final blocks = [
        _block('短保存', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
      ];
      await _mount(
        tester,
        blocks: blocks,
        options: const {'dashboard': true, 'initialMinute': 480},
        enabled: false,
        pendingAdjustment: const {
          'id': '短保存',
          'start': '2026-10-15T09:30:00',
          'end': '2026-10-15T09:31:00',
        },
      );
      final badge = find.byKey(const ValueKey('planner-saving:短保存'));
      expect(tester.getSize(badge), Size.zero);
      expect(tester.widget<Semantics>(badge).properties.label, '保存中');
      expect(find.byTooltip('保存中'), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('occupancy:短保存:2026-10-15')))
            .height,
        1,
      );
      await _mount(
        tester,
        days: const [
          {'date': '2026-10-15'},
          {'date': '2026-10-16'},
          {'date': '2026-10-17'},
          {'date': '2026-10-18'},
          {'date': '2026-10-19'},
        ],
        blocks: [
          ...blocks,
          _block(
            '重叠',
            '2026-10-15T08:00:00',
            '2026-10-15T12:00:00',
            readOnly: true,
          ),
        ],
        options: const {'dashboard': true, 'initialMinute': 480},
        enabled: false,
        scaler: const TextScaler.linear(2),
        pendingAdjustment: const {
          'id': '短保存',
          'start': '2026-10-15T09:30:00',
          'end': '2026-10-15T11:30:00',
        },
      );
      expect(tester.getSize(badge), Size.zero);
      expect(find.byTooltip('保存中'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending adjustment shows one real target placement without mutating or duplicating its original task',
    (tester) async {
      final original = Map<String, Object?>.unmodifiable(
        _block('保存任务', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
      );
      final blocks = List<BoardItem>.unmodifiable([original]);
      const options = {'dashboard': true, 'initialMinute': 480};
      await _mount(tester, blocks: blocks, options: options);
      final occupancy = find.byKey(const ValueKey('occupancy:保存任务:2026-10-15'));
      final originalY = tester.getTopLeft(occupancy).dy;
      final viewport = tester.getRect(
        find.byKey(const ValueKey('planner-vertical')),
      );
      await _mount(
        tester,
        blocks: blocks,
        options: options,
        enabled: false,
        pendingAdjustment: const {
          'id': '保存任务',
          'start': '2026-10-15T10:15:00',
          'end': '2026-10-15T11:00:00',
        },
      );
      expect(occupancy, findsOneWidget);
      expect(
        find.byKey(const ValueKey('block:保存任务:2026-10-15')),
        findsOneWidget,
      );
      expect(find.text('保存任务'), findsOneWidget);
      expect(find.byKey(const ValueKey('planner-saving:保存任务')), findsOneWidget);
      expect(find.byTooltip('保存中'), findsOneWidget);
      expect(tester.getTopLeft(occupancy).dy - originalY, 75);
      expect(tester.getSize(occupancy).height, 45);
      expect(
        tester.getRect(find.byKey(const ValueKey('planner-vertical'))),
        viewport,
      );
      expect(original['start'], '2026-10-15T09:00:00');
      expect(original['end'], '2026-10-15T10:00:00');
      expect(original.containsKey('_saving'), isFalse);
      await _mount(tester, blocks: blocks, options: options);
      expect(find.byKey(const ValueKey('planner-saving:保存任务')), findsNothing);
      expect(tester.getTopLeft(occupancy).dy, originalY);
      expect(tester.getSize(occupancy).height, 60);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending candidate leaves its tray once, keeps other candidates, and restores on clear',
    (tester) async {
      final candidates = List<BoardItem>.unmodifiable([
        Map<String, Object?>.unmodifiable({
          'id': 'candidate:待保存',
          'title': '待保存候选',
          'durationMinutes': 30,
          'moveEvent': {'action': 'move'},
        }),
        const {'id': 'other', 'title': '其余候选', 'durationMinutes': 60},
      ]);
      const options = {
        'dashboard': true,
        'candidateCount': 2,
        'initialMinute': 480,
      };
      await _mount(
        tester,
        candidates: candidates,
        options: options,
        enabled: false,
        pendingAdjustment: const {
          'id': 'candidate:待保存',
          'start': '2026-10-16T09:00:00',
          'end': '2026-10-16T09:30:00',
        },
      );
      final tray = find.byKey(const ValueKey('planner-candidates'));
      expect(
        find.descendant(of: tray, matching: find.text('待保存候选')),
        findsNothing,
      );
      expect(
        find.descendant(of: tray, matching: find.text('其余候选')),
        findsOneWidget,
      );
      expect(find.text('待保存候选'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('planner-candidate-count')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      final target = find.byKey(
        const ValueKey('occupancy:candidate:待保存:2026-10-16'),
      );
      expect(tester.getSize(target).height, 30);
      expect(
        find.byKey(const ValueKey('planner-saving:candidate:待保存')),
        findsOneWidget,
      );
      expect(candidates.first.containsKey('start'), isFalse);
      await _mount(tester, candidates: candidates, options: options);
      expect(
        find.descendant(of: tray, matching: find.text('待保存候选')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('planner-candidate-count')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(target, findsNothing);
      expect(
        find.byKey(const ValueKey('planner-saving:candidate:待保存')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending on a narrow disabled board preserves scroll offsets and permits browsing while blocking move events',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final blocks = [
        _block('可滚动保存', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
      ];
      const options = {'dashboard': true, 'initialMinute': 480};
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: blocks,
        options: options,
        scaler: const TextScaler.linear(2),
        onEvent: events.add,
      );
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-horizontal')),
          )
          .controller!;
      vertical.jumpTo(510);
      horizontal.jumpTo(20);
      await tester.pump();
      await _mount(
        tester,
        blocks: blocks,
        options: options,
        scaler: const TextScaler.linear(2),
        enabled: false,
        onEvent: events.add,
        pendingAdjustment: const {
          'id': '可滚动保存',
          'start': '2026-10-15T10:00:00',
          'end': '2026-10-15T11:00:00',
        },
      );
      expect(vertical.offset, 510);
      expect(horizontal.offset, 20);
      expect(find.byType(LongPressDraggable<BoardItem>), findsNothing);
      expect(
        find.byKey(const ValueKey('planner-saving:可滚动保存')),
        findsOneWidget,
      );
      await tester.longPress(find.text('可滚动保存'));
      await tester.pump();
      expect(events, isEmpty);
      final before = vertical.offset;
      await tester.drag(
        find.byKey(const ValueKey('planner-vertical')),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      expect(vertical.offset, greaterThan(before));
      final scrolled = vertical.offset;
      await _mount(
        tester,
        blocks: blocks,
        options: options,
        scaler: const TextScaler.linear(2),
        onEvent: events.add,
      );
      expect(vertical.offset, scrolled);
      expect(horizontal.offset, 20);
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid or unrelated pending placements do not hide current input tasks',
    (tester) async {
      final blocks = [
        _block('保留任务', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
      ];
      for (final pending in [
        const {
          'id': '不存在',
          'start': '2026-10-15T10:00:00',
          'end': '2026-10-15T11:00:00',
        },
        const {'id': '保留任务', 'start': 'invalid', 'end': '2026-10-15T11:00:00'},
        const {
          'id': '保留任务',
          'start': '2026-10-15T11:00:00',
          'end': '2026-10-15T10:00:00',
        },
      ]) {
        await _mount(
          tester,
          blocks: blocks,
          options: const {'dashboard': true},
          pendingAdjustment: pending,
        );
        expect(
          find.byKey(const ValueKey('occupancy:保留任务:2026-10-15')),
          findsOneWidget,
        );
        expect(find.text('保留任务'), findsOneWidget);
        expect(find.text('保存中'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native quick adjust is opt-in, externally controlled and disabled with the board',
    (tester) async {
      const options = {
        'dashboard': true,
        'filterEvent': {'type': 'filter'},
      };
      await _mount(tester, options: options);
      expect(find.byKey(const ValueKey('planner-quick-adjust')), findsNothing);
      final toggles = <bool>[];
      await _mount(tester, options: options, onQuickAdjustChanged: toggles.add);
      final button = find.byKey(const ValueKey('planner-quick-adjust'));
      final semantics = find.byKey(
        const ValueKey('planner-quick-adjust-semantics'),
      );
      expect(tester.widget<Semantics>(semantics).properties.toggled, isFalse);
      expect(find.byTooltip('拖动后自动保存，可撤销'), findsOneWidget);
      await tester.tap(button);
      expect(toggles, [true]);
      expect(tester.widget<Semantics>(semantics).properties.toggled, isFalse);
      await _mount(
        tester,
        options: options,
        quickAdjust: true,
        onQuickAdjustChanged: toggles.add,
      );
      expect(tester.widget<Semantics>(semantics).properties.toggled, isTrue);
      final scheme = Theme.of(tester.element(button)).colorScheme;
      expect(
        tester.widget<TextButton>(button).style!.backgroundColor!.resolve({}),
        scheme.primaryContainer,
      );
      await tester.tap(button);
      expect(toggles, [true, false]);
      await _mount(
        tester,
        options: options,
        quickAdjust: true,
        onQuickAdjustChanged: toggles.add,
        enabled: false,
      );
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      expect(tester.widget<Semantics>(semantics).properties.enabled, isFalse);
      await tester.tap(button);
      expect(toggles, [true, false]);
      expect(find.text('仅有截止'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native quick adjust and active filter stay readable at 320 width and double text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final toggles = <bool>[];
      final events = <Object?>[];
      await _mount(
        tester,
        scaler: const TextScaler.linear(2),
        options: const {
          'dashboard': true,
          'filterEvent': {'type': 'filter'},
          'onlyDeadline': true,
        },
        quickAdjust: true,
        onQuickAdjustChanged: toggles.add,
        onEvent: events.add,
      );
      expect(tester.takeException(), isNull);
      final quick = find.byKey(const ValueKey('planner-quick-adjust'));
      expect(quick.hitTestable(), findsOneWidget);
      expect(find.text('筛选：仅有截止'), findsOneWidget);
      expect(find.text('仅有截止'), findsNothing);
      expect(
        find.byKey(const ValueKey('planner-toggle-candidates')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.getRect(quick).right, lessThanOrEqualTo(320));
      await tester.tap(quick);
      expect(toggles, [false]);
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow overlap titles fall back to one line before disappearing at the viewport edge',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mount(
        tester,
        options: const {'dashboard': true, 'initialMinute': 540},
        blocks: [
          _block(
            '高等数学课程',
            '2026-10-15T08:00:00',
            '2026-10-15T09:35:00',
            readOnly: true,
          ),
          _block('整理研究资料', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('高等数学课程'), findsOneWidget);
      expect(find.text('整理研究资料'), findsOneWidget);
      final course = tester.widget<Text>(find.text('高等数学课程'));
      expect(course.maxLines, 1);
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      scroll.jumpTo(scroll.offset - 30);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('高等数学课程')).maxLines, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'two overlapping arrangements keep independent time geometry and selection',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mount(
        tester,
        options: const {'dashboard': true, 'initialMinute': 480},
        blocks: [
          _block(
            '课程甲',
            '2026-10-15T08:00:00',
            '2026-10-15T09:35:00',
            readOnly: true,
          ),
          _block('任务乙', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
        ],
      );
      await tester.pumpAndSettle();
      final course = find.byKey(const ValueKey('block:课程甲:2026-10-15'));
      final task = find.byKey(const ValueKey('block:任务乙:2026-10-15'));
      expect(find.byKey(const ValueKey('dense:课程甲:2026-10-15')), findsNothing);
      expect(tester.getRect(course).right, lessThan(tester.getRect(task).left));
      expect(tester.getSize(course).height, 95);
      expect(tester.getSize(task).height, 60);
      expect(tester.getTopLeft(task).dy - tester.getTopLeft(course).dy, 60);
      expect(
        find.descendant(of: course, matching: find.text('课程甲')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: task, matching: find.text('任务乙')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: course, matching: find.text('09:35')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: task, matching: find.text('10:00')),
        findsOneWidget,
      );
      await tester.tap(task);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('planner-selection-panel')),
        findsOneWidget,
      );
      expect(find.text('10/15 09:00 — 10:00 · 1h'), findsOneWidget);
      final material = tester.widget<Material>(
        find.descendant(of: course, matching: find.byType(Material)).first,
      );
      final selected = tester.widget<Material>(
        find.descendant(of: task, matching: find.byType(Material)).first,
      );
      expect(material.color, isNot(selected.color));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'zoom controls avoid the dock and a host rebuild does not cancel an active zoom drag',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final blocks = [
        _block('短甲', '2026-10-15T11:00:00', '2026-10-15T11:03:00'),
        _block('短乙', '2026-10-15T11:05:00', '2026-10-15T11:09:00'),
      ];
      final options = const <String, Object?>{'dashboard': true};
      await _mount(tester, blocks: blocks, options: options, bottomInset: 84);
      await tester.tap(find.text('2项短任务'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放大该时段'));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(find.byTooltip('放大时间轴')).dy,
        lessThanOrEqualTo(600 - 84),
      );
      final source = find.byKey(const ValueKey('block:短甲:2026-10-15'));
      final start = tester.getCenter(source);
      final gesture = await _dragTo(
        tester,
        source,
        start + const Offset(0, 10),
      );
      expect(find.byKey(const ValueKey('planner-drag-start')), findsOneWidget);
      await _mount(tester, blocks: blocks, options: options, bottomInset: 84);
      expect(find.text('已放大'), findsOneWidget);
      expect(find.byKey(const ValueKey('planner-drag-start')), findsOneWidget);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard scheduled drag preserves the grab offset including an off-grid start',
    (tester) async {
      final events = <Object?>[];
      final blocks = [
        _block('偏移抓取', '2026-10-15T09:07:00', '2026-10-15T10:07:00'),
      ];
      await _mount(
        tester,
        blocks: blocks,
        options: const {'dashboard': true},
        onEvent: events.add,
      );
      final block = find.byKey(const ValueKey('block:偏移抓取:2026-10-15'));
      final point = tester.getCenter(block);
      final width =
          tester.getSize(find.byType(DragTarget<BoardItem>)).width / 5;
      final gesture = await tester.startGesture(point);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(point + Offset(width, 0));
      await tester.pump(const Duration(milliseconds: 40));
      final ruler = find.byKey(const ValueKey('planner-drag-start'));
      expect(
        find.descendant(of: ruler, matching: find.text('09:07')),
        findsOneWidget,
      );
      await gesture.moveTo(point + Offset(width + 14, 0));
      await tester.pump();
      expect(find.textContaining('1分钟精调'), findsWidgets);
      await gesture.moveTo(point + Offset(width + 14, 4));
      await tester.pump();
      expect(
        find.descendant(of: ruler, matching: find.text('09:08')),
        findsOneWidget,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect((events.single as Map)['start'], '2026-10-16T09:08:00.000');
      expect((events.single as Map)['end'], '2026-10-16T10:08:00.000');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'underlapping board scrolls its final occupation above the dock',
    (tester) async {
      await _mount(
        tester,
        blocks: [_block('午夜边界', '2026-10-15T23:30:00', '2026-10-16T00:00:00')],
        options: const {'dashboard': true},
        bottomInset: 84,
      );
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      final band = find.byKey(const ValueKey('occupancy:午夜边界:2026-10-15'));
      final viewport = tester.getRect(
        find.byKey(const ValueKey('planner-vertical')),
      );
      expect(tester.getBottomRight(band).dy, closeTo(viewport.bottom - 84, .1));
      expect(tester.getSize(band).height, 30);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard precision keeps real scroll travel while slowing finger travel',
    (tester) async {
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'scroll',
            'title': '滚动细调',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        options: const {'dashboard': true},
      );
      final point = _gridPoint(tester, 0, 615);
      final gesture = await _dragTo(tester, find.text('滚动细调'), point);
      await gesture.moveTo(point + const Offset(14, 0));
      await tester.pump();
      expect(find.textContaining('1分钟精调'), findsWidgets);
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      vertical.jumpTo(vertical.offset + 60);
      await gesture.moveTo(point + const Offset(14, 4));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('planner-drag-start')),
          matching: find.text('11:16'),
        ),
        findsOneWidget,
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard selection changes emphasis without changing occupancy and keeps actions above dock',
    (tester) async {
      await _mount(
        tester,
        blocks: [_block('选中样式', '2026-10-15T09:00:00', '2026-10-15T10:30:00')],
        options: const {'dashboard': true},
        bottomInset: 84,
      );
      await tester.pumpAndSettle();
      final block = find.byKey(const ValueKey('block:选中样式:2026-10-15'));
      final band = find.byKey(const ValueKey('occupancy:选中样式:2026-10-15'));
      final geometry = tester.getRect(band);
      final normalMaterial = tester.widget<Material>(
        find.descendant(of: block, matching: find.byType(Material)).first,
      );
      final normalDecoration = tester
          .widgetList<Container>(
            find.descendant(of: block, matching: find.byType(Container)),
          )
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .single;
      expect(normalDecoration.border, isNull);
      expect(normalDecoration.borderRadius, normalMaterial.borderRadius);
      expect(
        find.byKey(const ValueKey('resize:选中样式:2026-10-15')),
        findsNothing,
      );
      await tester.tap(find.text('选中样式'));
      await tester.pump();
      final selected = tester.widget<Material>(
        find.descendant(of: block, matching: find.byType(Material)).first,
      );
      expect(selected.color, isNot(normalMaterial.color));
      expect(selected.elevation, greaterThan(normalMaterial.elevation));
      expect(selected.borderRadius, normalMaterial.borderRadius);
      final selectedDecoration = tester
          .widgetList<Container>(
            find.descendant(of: block, matching: find.byType(Container)),
          )
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .single;
      expect(selectedDecoration.border!.isUniform, isTrue);
      expect(selectedDecoration.borderRadius, normalDecoration.borderRadius);
      expect(tester.getRect(band), geometry);
      expect(
        find.byKey(const ValueKey('resize:选中样式:2026-10-15')),
        findsOneWidget,
      );
      expect(
        tester
            .getBottomRight(
              find.byKey(const ValueKey('planner-selection-panel')),
            )
            .dy,
        600 - 84,
      );
      await tester.tap(find.byTooltip('关闭选中任务'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('resize:选中样式:2026-10-15')),
        findsNothing,
      );
      expect(tester.getRect(band), geometry);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard defaults to five minute snapping and stationary dwell does not change modes',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'coarse',
            'title': '默认五分钟',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        options: const {'dashboard': true},
        onEvent: events.add,
      );
      final point = _gridPoint(tester, 0, 617);
      final gesture = await _dragTo(tester, find.text('默认五分钟'), point);
      final hint = find.byKey(const ValueKey('planner-drag-hint'));
      expect(hint, findsOneWidget);
      expect(
        find.descendant(of: hint, matching: find.textContaining('5分钟吸附')),
        findsOneWidget,
      );
      expect(find.textContaining('横移精调 · 大幅横移换日'), findsWidgets);
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.descendant(of: hint, matching: find.textContaining('5分钟吸附')),
        findsOneWidget,
      );
      expect(find.textContaining('1分钟精调'), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect((events.single as Map)['snapMinutes'], 5);
      expect((events.single as Map)['start'], '2026-10-15T10:15:00.000');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard horizontal fine gesture locks its date and deliberate day travel preserves the fine time',
    (tester) async {
      final events = <Object?>[];
      final active = <bool>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'fine',
            'title': '横移精调',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        options: const {'dashboard': true},
        onEvent: events.add,
        onDragActiveChanged: active.add,
      );
      final grid = tester.getRect(find.byType(DragTarget<BoardItem>));
      final width = grid.width / 5;
      // Start eight pixels before the next date. Crossing that visual boundary
      // by a few pixels must mean fine adjustment rather than changing dates.
      final point = Offset(
        grid.left + width - 8,
        _gridPoint(tester, 0, 615).dy,
      );
      final gesture = await _dragTo(tester, find.text('横移精调'), point);
      final ruler = find.byKey(const ValueKey('planner-drag-start'));
      expect(active, [true]);
      await gesture.moveTo(point + const Offset(13, 0));
      await tester.pump();
      expect(find.textContaining('5分钟吸附'), findsWidgets);
      await gesture.moveTo(point + const Offset(14, 0));
      await tester.pump();
      expect(find.textContaining('1分钟精调'), findsWidgets);
      expect(
        find.descendant(of: ruler, matching: find.text('10:15')),
        findsOneWidget,
      );
      await gesture.moveTo(point + const Offset(14, 4));
      await tester.pump();
      expect(
        find.descendant(of: ruler, matching: find.text('10:16')),
        findsOneWidget,
      );
      await gesture.moveTo(point + const Offset(14, 80));
      await tester.pump();
      expect(
        find.descendant(of: ruler, matching: find.text('10:35')),
        findsOneWidget,
      );
      expect(find.textContaining('1分钟精调'), findsWidgets);
      // Move decisively into the next column; exit fine mode without rounding
      // or changing the currently previewed wall-clock time.
      await gesture.moveTo(point + Offset(width * .75, 80));
      await tester.pump();
      expect(find.textContaining('5分钟吸附'), findsWidgets);
      expect(
        find.descendant(of: ruler, matching: find.text('10:35')),
        findsOneWidget,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect((events.single as Map)['snapMinutes'], 5);
      expect((events.single as Map)['start'], '2026-10-16T10:35:00.000');
      expect((events.single as Map)['end'], '2026-10-16T11:05:00.000');
      expect(active, [true, false]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard small cross-boundary fine gesture keeps the original date on drop',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'edge',
            'title': '边界精调',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        options: const {'dashboard': true},
        onEvent: events.add,
      );
      final grid = tester.getRect(find.byType(DragTarget<BoardItem>));
      final width = grid.width / 5;
      final point = Offset(
        grid.left + width - 8,
        _gridPoint(tester, 0, 615).dy,
      );
      final gesture = await _dragTo(tester, find.text('边界精调'), point);
      await gesture.moveTo(point + const Offset(14, 0));
      await tester.pump();
      await gesture.moveTo(point + const Offset(14, 4));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect((events.single as Map)['snapMinutes'], 1);
      expect((events.single as Map)['start'], '2026-10-15T10:16:00.000');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard deliberate date change requires sufficient depth inside the next column',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'depth',
            'title': '换日深度',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        options: const {'dashboard': true},
        onEvent: events.add,
      );
      final grid = tester.getRect(find.byType(DragTarget<BoardItem>));
      final width = grid.width / 5;
      final point = _gridPoint(tester, 0, 615);
      final gesture = await _dragTo(tester, find.text('换日深度'), point);
      // Travel already exceeds the distance threshold, but only the deliberate
      // 18 percent incursion may switch dates.
      await gesture.moveTo(Offset(grid.left + width * 1.17, point.dy));
      await tester.pump();
      expect(find.textContaining('1分钟精调'), findsWidgets);
      await gesture.up();
      await tester.pumpAndSettle();
      expect((events.single as Map)['start'], '2026-10-15T10:15:00.000');
      expect((events.single as Map)['snapMinutes'], 1);
      final next = await _dragTo(tester, find.text('换日深度'), point);
      await next.moveTo(Offset(grid.left + width * 1.19, point.dy));
      await tester.pump();
      expect(find.textContaining('5分钟吸附'), findsWidgets);
      await next.up();
      await tester.pumpAndSettle();
      expect((events.last as Map)['start'], '2026-10-16T10:15:00.000');
      expect((events.last as Map)['snapMinutes'], 5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard resize fixes the start while five minute and horizontal fine moves adjust only the end',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: [_block('末端精调', '2026-10-15T09:07:00', '2026-10-15T10:07:00')],
        options: const {'dashboard': true},
        onEvent: events.add,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('末端精调'));
      await tester.pump();
      final handle = find.byKey(const ValueKey('resize:末端精调:2026-10-15'));
      final point = tester.getCenter(handle);
      final gesture = await tester.startGesture(point);
      await gesture.moveTo(point + const Offset(0, 20));
      await tester.pump();
      final end = find.byKey(const ValueKey('planner-drag-end'));
      expect(
        find.descendant(of: end, matching: find.text('10:27')),
        findsOneWidget,
      );
      expect(find.textContaining('5分钟吸附'), findsWidgets);
      await gesture.moveTo(point + const Offset(14, 20));
      await tester.pump();
      expect(
        find.descendant(of: end, matching: find.text('10:27')),
        findsOneWidget,
      );
      expect(find.textContaining('1分钟精调'), findsWidgets);
      await gesture.moveTo(point + const Offset(14, 24));
      await tester.pump();
      expect(
        find.descendant(of: end, matching: find.text('10:28')),
        findsOneWidget,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect((events.single as Map)['start'], '2026-10-15T09:07:00.000');
      expect((events.single as Map)['end'], '2026-10-15T10:28:00.000');
      expect((events.single as Map)['intent'], 'resize');
      expect((events.single as Map)['snapMinutes'], 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard drag hint follows the finger and remains within narrow screen bounds',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'hud',
            'title': '手指提示',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        options: const {'dashboard': true},
      );
      final point = _gridPoint(tester, 0, 615);
      final gesture = await _dragTo(tester, find.text('手指提示'), point);
      final hint = find.byKey(const ValueKey('planner-drag-hint'));
      final initial = tester.getRect(hint);
      await gesture.moveTo(point + const Offset(0, 24));
      await tester.pump();
      final moved = tester.getRect(hint);
      expect(moved.top, greaterThan(initial.top));
      expect((moved.top - initial.top), closeTo(24, 1));
      await gesture.moveTo(const Offset(310, 680));
      await tester.pump();
      final edge = tester.getRect(hint);
      expect(edge.left, greaterThanOrEqualTo(8));
      expect(edge.right, lessThanOrEqualTo(312));
      expect(edge.top, greaterThanOrEqualTo(8));
      expect(edge.bottom, lessThanOrEqualTo(692));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'drag activity survives leaving grid and clears on cancel or disposal',
    (tester) async {
      final active = <bool>[];
      const candidates = [
        {
          'id': 'cancel',
          'title': '拖动状态',
          'durationMinutes': 30,
          'moveEvent': {'action': 'move'},
        },
      ];
      await _mount(
        tester,
        candidates: candidates,
        options: const {'dashboard': true},
        onDragActiveChanged: active.add,
      );
      final source = tester.getCenter(find.text('拖动状态'));
      var gesture = await _dragTo(
        tester,
        find.text('拖动状态'),
        _gridPoint(tester, 0, 615),
      );
      await gesture.moveTo(source);
      await tester.pump();
      expect(active, [true]);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(active, [true, false]);
      gesture = await _dragTo(
        tester,
        find.text('拖动状态'),
        _gridPoint(tester, 0, 615),
      );
      await tester.pumpWidget(const SizedBox());
      await gesture.cancel();
      await tester.pump();
      expect(active, [true, false, true, false]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'candidate region collapses without changing dates or scroll position',
    (tester) async {
      await _mount(
        tester,
        candidates: const [
          {'id': 'pending', 'title': '待安排示例', 'durationMinutes': 90},
        ],
        options: const {'dashboard': true},
      );
      final toggle = find.byKey(const ValueKey('planner-toggle-candidates'));
      final region = find.byKey(const ValueKey('planner-candidate-region'));
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      final offset = vertical.offset;
      final original = tester.getSize(region).height;
      final oldGridTop = tester
          .getTopLeft(find.byKey(const ValueKey('planner-vertical')))
          .dy;
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.getSize(region).height, 0);
      expect(find.text('待安排示例'), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('planner-vertical'))).dy,
        closeTo(oldGridTop - original, .1),
      );
      expect(vertical.offset, offset);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.getSize(region).height, original);
      expect(find.text('待安排示例'), findsOneWidget);
      expect(vertical.offset, offset);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'candidate feedback keeps its source face then animates into the exact band',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'paper',
            'title': '阅读论文',
            'deadlineSummary': '10/17截止',
            'durationMinutes': 90,
            'moveEvent': {'action': 'move'},
          },
        ],
        options: const {'dashboard': true},
        onEvent: events.add,
      );
      final original = tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('planner-candidates')),
          matching: find.byType(LongPressDraggable<BoardItem>),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('阅读论文')),
      );
      await tester.pump(const Duration(milliseconds: 550));
      final feedback = find.byKey(
        const ValueKey('planner-candidate-drag-feedback'),
      );
      expect(tester.getSize(feedback).width, closeTo(original.width, .01));
      expect(tester.getSize(feedback).height, original.height);
      expect(
        find.descendant(of: feedback, matching: find.text('10/17截止')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('planner-drag-start')), findsNothing);
      final point = _gridPoint(tester, 1, 615);
      await gesture.moveTo(point);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(feedback).height, greaterThan(original.height));
      expect(tester.getSize(feedback).height, lessThan(90));
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.getSize(feedback).height, closeTo(90, .1));
      final feedbackDecorations = tester
          .widgetList<DecoratedBox>(
            find.descendant(of: feedback, matching: find.byType(DecoratedBox)),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>();
      expect(feedbackDecorations, isNotEmpty);
      for (final decoration in feedbackDecorations) {
        expect(
          decoration.border == null || decoration.border!.isUniform,
          isTrue,
        );
      }
      expect(
        find.byKey(const ValueKey('local:paper:2026-10-16')),
        findsNothing,
      );
      final start = find.byKey(const ValueKey('planner-drag-start'));
      final end = find.byKey(const ValueKey('planner-drag-end'));
      expect(
        find.descendant(of: start, matching: find.text('10:15')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: end, matching: find.text('11:45')),
        findsOneWidget,
      );
      expect(
        tester.getSize(feedback).width,
        closeTo(
          tester.getSize(find.byType(DragTarget<BoardItem>)).width / 5 - 12,
          .1,
        ),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect((events.single as Map)['start'], '2026-10-16T10:15:00.000');
      expect((events.single as Map)['end'], '2026-10-16T11:45:00.000');
      expect(find.byKey(const ValueKey('planner-drag-start')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one minute candidate keeps a real strip and separate ruler labels; leaving cancels',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'tiny',
            'title': '一分钟任务',
            'durationMinutes': 1,
            'moveEvent': {'action': 'move'},
          },
        ],
        options: const {'dashboard': true},
        onEvent: events.add,
      );
      final source = tester.getCenter(find.text('一分钟任务'));
      final gesture = await _dragTo(
        tester,
        find.text('一分钟任务'),
        _gridPoint(tester, 0, 615),
      );
      await tester.pump(const Duration(milliseconds: 260));
      final feedback = find.byKey(
        const ValueKey('planner-candidate-drag-feedback'),
      );
      expect(tester.getSize(feedback).height, closeTo(1, .1));
      final start = tester.getRect(
        find.byKey(const ValueKey('planner-drag-start')),
      );
      final end = tester.getRect(
        find.byKey(const ValueKey('planner-drag-end')),
      );
      expect(start.overlaps(end), isFalse);
      await gesture.moveTo(source);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      expect(find.byKey(const ValueKey('planner-drag-start')), findsNothing);
      expect(tester.getSize(feedback).height, greaterThan(40));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('two dashboard candidates share the first row', (tester) async {
    await _mount(
      tester,
      candidates: const [
        {'id': 'first', 'title': '第一候选'},
        {'id': 'second', 'title': '第二候选'},
      ],
      options: const {'dashboard': true},
    );
    final first = tester.getRect(find.text('第一候选'));
    final second = tester.getRect(find.text('第二候选'));
    expect(first.top, second.top);
    expect(second.left, greaterThan(first.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dashboard uses two readable candidate columns and compact date controls',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {'id': 'a', 'title': '阅读论文', 'deadlineSummary': '10/17截止'},
          {'id': 'c', 'title': '采购清单', 'durationMinutes': 30},
          {'id': 'b', 'title': '整理笔记', 'durationMinutes': 150},
        ],
        options: const {
          'dashboard': true,
          'rangeLabel': '10月15日—19日',
          'todayEvent': {'type': 'today'},
          'filterEvent': {'type': 'filter'},
        },
        onEvent: events.add,
      );
      expect(find.text('10/17截止'), findsOneWidget);
      expect(find.text('耗时2.5h'), findsOneWidget);
      expect(find.text('耗时30min'), findsOneWidget);
      final paper = tester.getRect(find.text('阅读论文'));
      final notes = tester.getRect(find.text('整理笔记'));
      final shopping = tester.getRect(find.text('采购清单'));
      expect(paper.top, shopping.top);
      expect(notes.top, greaterThan(paper.top));
      expect(notes.left, paper.left);
      expect(shopping.left, greaterThan(paper.left));
      final tray = tester.widget<GridView>(
        find.byKey(const ValueKey('planner-candidates')),
      );
      final delegate =
          tray.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 2);
      expect(delegate.mainAxisExtent, closeTo((800 - 32) / 2, .1));
      expect(
        find.byKey(const ValueKey('planner-candidate-count')),
        findsOneWidget,
      );
      final summary = tester.widget<Text>(find.text('10/17截止'));
      final scheme = Theme.of(tester.element(find.text('10/17截止'))).colorScheme;
      expect(summary.style!.color, isNot(scheme.error));
      await tester.tap(find.text('今天'));
      expect(events, [
        {'type': 'today'},
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scheduled block times follow exact top and bottom edges while short bands stay real',
    (tester) async {
      await _mount(
        tester,
        blocks: [
          _block('边缘时间', '2026-10-15T09:00:00', '2026-10-15T10:30:00'),
          _block('一分钟', '2026-10-16T09:00:00', '2026-10-16T09:01:00'),
        ],
        options: const {'dashboard': true},
      );
      final band = find.byKey(const ValueKey('occupancy:边缘时间:2026-10-15'));
      final card = find.byKey(const ValueKey('block:边缘时间:2026-10-15'));
      expect(tester.getSize(band).height, 90);
      final top = find.descendant(of: card, matching: find.text('09:00'));
      final bottom = find.descendant(of: card, matching: find.text('10:30'));
      expect(
        tester.getTopLeft(top).dy - tester.getTopLeft(band).dy,
        lessThan(8),
      );
      expect(
        tester.getBottomRight(band).dy - tester.getBottomRight(bottom).dy,
        lessThan(8),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('occupancy:一分钟:2026-10-16')))
            .height,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selected gaps merge all read-only and fixed occupancy before displaying free time',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: [
          _block(
            '课程',
            '2026-10-15T08:00:00',
            '2026-10-15T08:30:00',
            readOnly: true,
          ),
          {
            ..._block('固定', '2026-10-15T08:20:00', '2026-10-15T08:45:00'),
            'fixed': true,
          },
          {
            ..._block('选中', '2026-10-15T09:00:00', '2026-10-15T09:30:00'),
            'editTimeEvent': {'type': 'editTime'},
          },
          _block('后续', '2026-10-15T10:00:00', '2026-10-15T11:00:00'),
        ],
        options: const {'dashboard': true},
        onEvent: events.add,
      );
      await tester.tap(find.text('选中'));
      await tester.pump();
      expect(find.text('空闲15分钟'), findsWidgets);
      expect(find.text('空闲30分钟'), findsWidgets);
      expect(find.text('空闲40分钟'), findsNothing);
      await tester.tap(find.text('编辑时间'));
      expect(events.single, {'type': 'editTime', 'id': '选中'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short-task choices zoom only time geometry and return to the unchanged schedule',
    (tester) async {
      final blocks = [
        _block('回复邮件', '2026-10-17T11:00:00', '2026-10-17T11:03:00'),
        _block('提交报销', '2026-10-17T11:05:00', '2026-10-17T11:09:00'),
        _block('确认会议', '2026-10-17T11:12:00', '2026-10-17T11:15:00'),
      ];
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: blocks,
        options: const {'dashboard': true, 'initialMinute': 600},
        onEvent: events.add,
      );
      await tester.tap(find.text('3项短任务'));
      await tester.pumpAndSettle();
      expect(find.text('10/17 11:00 → 10/17 11:03'), findsOneWidget);
      await tester.tap(find.text('放大该时段'));
      await tester.pumpAndSettle();
      expect(find.text('已放大'), findsOneWidget);
      expect(find.text('10月17日 周六'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('planner-ruler:675')),
          matching: find.text('11:15'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('occupancy:回复邮件:2026-10-17')))
            .height,
        84,
      );
      expect(find.text('11:03'), findsOneWidget);
      expect(events, isEmpty);
      await tester.tap(find.text('返回5天视图'));
      await tester.pumpAndSettle();
      expect(find.text('3项短任务'), findsOneWidget);
      expect(blocks.first['start'], '2026-10-17T11:00:00');
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard remains readable on narrow screens with large text in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: brightness,
              ),
            ),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: PlannerBoard(
                  days: _days,
                  candidates: List.generate(
                    6,
                    (i) => {
                      'id': 'c$i',
                      'title': '候选任务$i',
                      'durationMinutes': 30,
                    },
                  ),
                  blocks: [
                    _block('五分钟', '2026-10-15T09:00:00', '2026-10-15T09:05:00'),
                  ],
                  options: const {
                    'dashboard': true,
                    'rangeLabel': '10月15日—19日',
                  },
                  onEvent: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'cross-day selection includes the end date and the next-day free gap',
    (tester) async {
      await _mount(
        tester,
        days: _days.take(2).toList(),
        options: const {'dashboard': true, 'initialMinute': 540},
        blocks: [
          _block('跨日安排', '2026-10-15T09:00:00', '2026-10-16T10:30:00'),
          _block('次日后续', '2026-10-16T11:00:00', '2026-10-16T12:00:00'),
        ],
      );
      expect(find.text('显示范围外有 1 项安排 · 查看'), findsNothing);
      await tester.tap(find.textContaining('跨日安排').first);
      await tester.pump();
      expect(find.text('10/15 09:00 — 10/16 10:30 · 25.5h'), findsOneWidget);
      expect(find.text('空闲30分钟'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('outside warning compares the union of all visible day windows', (
    tester,
  ) async {
    final task = _block('跨日', '2026-10-15T09:00:00', '2026-10-16T10:30:00');
    await _mount(tester, days: _days.take(2).toList(), blocks: [task]);
    expect(find.text('显示范围外有 1 项安排 · 查看'), findsNothing);
    await _mount(
      tester,
      days: _days.take(2).toList(),
      blocks: [task],
      options: const {'startMinute': 540, 'endMinute': 1080},
    );
    expect(find.text('显示范围外有 1 项安排 · 查看'), findsOneWidget);
    await _mount(tester, days: _days.take(1).toList(), blocks: [task]);
    expect(find.text('显示范围外有 1 项安排 · 查看'), findsOneWidget);
    await _mount(
      tester,
      days: [_days[0], _days[2]],
      blocks: [_block('跨隐藏日期', '2026-10-15T23:00:00', '2026-10-17T01:00:00')],
    );
    expect(find.text('显示范围外有 1 项安排 · 查看'), findsOneWidget);
    await _mount(
      tester,
      days: _days.take(1).toList(),
      blocks: [_block('当天', '2026-10-15T09:00:00', '2026-10-15T10:00:00')],
    );
    expect(find.text('显示范围外有 1 项安排 · 查看'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'zoom preserves selection and totals use the latest task revision',
    (tester) async {
      final task = _block('保持选中', '2026-10-15T09:00:00', '2026-10-15T09:03:00');
      const options = {'dashboard': true, 'initialMinute': 540};
      await _mount(tester, blocks: [task], options: options);
      await tester.tap(find.text('保持选中'));
      await tester.pump();
      await tester.tap(find.byTooltip('放大该时段'));
      await tester.pumpAndSettle();
      expect(find.text('查看详情'), findsOneWidget);
      expect(find.text('1项任务 · 总耗时3分钟'), findsOneWidget);
      await _mount(
        tester,
        blocks: [
          {...task, 'end': '2026-10-15T09:05:00'},
        ],
        options: options,
      );
      expect(find.text('1项任务 · 总耗时5分钟'), findsOneWidget);
      expect(find.text('10/15 09:00 — 09:05 · 5分钟'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long pressing a short-task choice safely focuses a stable drag source',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: [
          _block('具体短任务', '2026-10-15T09:00:00', '2026-10-15T09:03:00'),
          _block('相邻短任务', '2026-10-15T09:05:00', '2026-10-15T09:09:00'),
          _block('第三短任务', '2026-10-15T09:12:00', '2026-10-15T09:15:00'),
        ],
        options: const {'dashboard': true, 'initialMinute': 540},
        onEvent: events.add,
      );
      await tester.tap(find.text('3项短任务'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('具体短任务'));
      await tester.pumpAndSettle();
      expect(find.text('已放大该任务，请长按任务块拖动'), findsOneWidget);
      expect(find.text('已放大'), findsOneWidget);
      final card = find.byKey(const ValueKey('block:具体短任务:2026-10-15'));
      final source = find.descendant(of: card, matching: find.text('具体短任务'));
      final grid = tester.getRect(find.byType(DragTarget<BoardItem>));
      final gesture = await _dragTo(
        tester,
        source,
        Offset(grid.left + 60, grid.top + 28 * 5),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveBy(const Offset(0, 28));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(events, hasLength(1));
      expect((events.single as Map)['id'], '具体短任务');
      expect((events.single as Map)['action'], 'move');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long dashboard information clips immediately with scroll and never starts an independent collapse animation',
    (tester) async {
      const id = '驻留课程:2026-10-15';
      await _mount(
        tester,
        blocks: [
          {
            ..._block(
              '驻留课程',
              '2026-10-15T08:00:00',
              '2026-10-15T11:00:00',
              readOnly: true,
            ),
            'location': '教学楼101',
            'teacher': '王老师',
          },
        ],
        options: const {'dashboard': true, 'initialMinute': 540},
      );
      final band = find.byKey(const ValueKey('occupancy:驻留课程:2026-10-15'));
      final start = find.byKey(const ValueKey('block-time-start:$id'));
      final end = find.byKey(const ValueKey('block-time-end:$id'));
      Finder line(String name) =>
          find.byKey(ValueKey('planner-info:$id:$name'));
      Finder textIn(String name) =>
          find.descendant(of: line(name), matching: find.byType(Text));
      final viewport = tester.getRect(
        find.byKey(const ValueKey('planner-vertical')),
      );
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      final startOffset =
          tester.getTopLeft(start).dy - tester.getTopLeft(band).dy;
      final endOffset =
          tester.getBottomRight(band).dy - tester.getBottomRight(end).dy;
      final initialOffset = vertical.offset;
      final initialEndTop = tester.getTopLeft(end).dy;
      Rect clip() {
        RenderObject child = tester.renderObject(textIn('title'));
        while (child.parent is RenderObject) {
          final parent = child.parent!;
          if (parent.runtimeType.toString() == '_ScrollingBlockInfoRender') {
            final box = parent as RenderBox;
            final local = box.describeApproximatePaintClip(child)!;
            return Rect.fromPoints(
              box.localToGlobal(local.topLeft),
              box.localToGlobal(local.bottomRight),
            );
          }
          child = parent;
        }
        throw StateError('The information group must have its own paint clip');
      }

      Rect visiblePart(String name) =>
          tester.getRect(textIn(name)).intersect(clip());
      Future<void> room(double pixels) async {
        vertical.jumpTo(
          initialOffset + initialEndTop - viewport.top - pixels - 5,
        );
        await tester.pump();
      }

      for (final name in ['title', 'location', 'teacher']) {
        expect(textIn(name), findsOneWidget);
        expect(visiblePart(name), tester.getRect(textIn(name)));
      }
      final originalHeights = {
        for (final name in ['title', 'location', 'teacher'])
          name: tester.getSize(line(name)).height,
      };
      await room(39);
      final teacherClip = clip();
      final teacherPart = visiblePart('teacher');
      expect(
        teacherPart.height,
        lessThan(tester.getSize(textIn('teacher')).height),
      );
      expect(
        visiblePart('title').height,
        tester.getSize(textIn('title')).height,
      );
      // Holding the exact scroll offset must not continue fading, translating,
      // collapsing or changing row sizes on a separate animation clock.
      await tester.pump(const Duration(milliseconds: 70));
      expect(clip(), teacherClip);
      expect(visiblePart('teacher'), teacherPart);
      await tester.pump(const Duration(milliseconds: 400));
      expect(clip(), teacherClip);
      expect(visiblePart('teacher'), teacherPart);
      await room(24);
      expect(clip().height, lessThan(teacherClip.height));
      expect(visiblePart('teacher').isEmpty, isTrue);
      expect(
        visiblePart('location').height,
        lessThan(tester.getSize(textIn('location')).height),
      );
      expect(
        visiblePart('title').height,
        tester.getSize(textIn('title')).height,
      );
      await room(5);
      expect(visiblePart('location').isEmpty, isTrue);
      expect(
        visiblePart('title').height,
        lessThan(tester.getSize(textIn('title')).height),
      );
      await room(-5);
      expect(visiblePart('title').isEmpty, isTrue);
      expect(textIn('title').hitTestable(), findsNothing);
      // Reverse scrolling restores the very same mounted rows immediately.
      await room(90);
      for (final name in ['title', 'location', 'teacher']) {
        expect(textIn(name), findsOneWidget);
        expect(tester.getSize(line(name)).height, originalHeights[name]);
        expect(visiblePart(name), tester.getRect(textIn(name)));
        expect(visiblePart(name).top, greaterThanOrEqualTo(viewport.top));
      }
      expect(
        tester.getTopLeft(start).dy - tester.getTopLeft(band).dy,
        closeTo(startOffset, .1),
      );
      expect(
        tester.getBottomRight(band).dy - tester.getBottomRight(end).dy,
        closeTo(endOffset, .1),
      );
      expect(tester.getSize(band).height, 180);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long dashboard metadata remains readable at large text on a narrow screen without duplicating its title',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mount(
        tester,
        blocks: [
          {
            ..._block(
              '大字课程',
              '2026-10-15T08:00:00',
              '2026-10-15T13:00:00',
              readOnly: true,
            ),
            'location': '主教学楼第一会议室',
            'teacher': '李老师',
          },
        ],
        options: const {'dashboard': true, 'initialMinute': 540},
        scaler: const TextScaler.linear(2),
      );
      await tester.pumpAndSettle();
      expect(find.text('大字课程'), findsOneWidget);
      expect(find.text('主教学楼第一会议室'), findsOneWidget);
      expect(find.text('李老师'), findsOneWidget);
      final location = tester.widget<Text>(find.text('主教学楼第一会议室'));
      expect(location.maxLines, 2);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('planner-vertical')),
      );
      for (final label in ['大字课程', '主教学楼第一会议室', '李老师']) {
        final rect = tester.getRect(find.text(label));
        expect(rect.top, greaterThanOrEqualTo(viewport.top));
        expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scrolling into a source block keeps a continuation title without moving true time edges',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: [
          _block(
            '晨间课程',
            '2026-10-15T08:00:00',
            '2026-10-15T10:00:00',
            readOnly: true,
          ),
        ],
        options: const {'dashboard': true, 'initialMinute': 540},
        onEvent: events.add,
      );
      await tester.pumpAndSettle();
      final band = find.byKey(const ValueKey('occupancy:晨间课程:2026-10-15'));
      final originalTop = tester.getTopLeft(band).dy;
      expect(tester.getSize(band).height, 120);
      final resident = find.byKey(const ValueKey('resident:晨间课程:2026-10-15'));
      final title = find.descendant(of: resident, matching: find.text('晨间课程'));
      expect(title, findsOneWidget);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('planner-vertical')),
      );
      expect(tester.getTopLeft(title).dy, greaterThanOrEqualTo(viewport.top));
      expect(tester.getBottomRight(title).dy, lessThan(viewport.top + 40));
      expect(
        find.descendant(of: resident, matching: find.text('09:00')),
        findsNothing,
      );
      await tester.tap(title);
      await tester.pump();
      expect(find.text('10/15 08:00 — 10:00 · 2h'), findsOneWidget);
      expect(tester.getTopLeft(band).dy, originalTop);
      expect(tester.getSize(band).height, 120);
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short-group badge leaves exact bands unobscured with a separate compact label and leader',
    (tester) async {
      tester.view.physicalSize = const Size(411, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mount(
        tester,
        blocks: [
          _block('短甲', '2026-10-17T11:00:00', '2026-10-17T11:03:00'),
          _block('短乙', '2026-10-17T11:05:00', '2026-10-17T11:09:00'),
          _block('短丙', '2026-10-17T11:12:00', '2026-10-17T11:15:00'),
        ],
        options: const {'dashboard': true, 'initialMinute': 600},
      );
      final bands = find.byKey(const ValueKey('dense-occupancy:短甲:2026-10-17'));
      final badge = find.byKey(const ValueKey('short-badge:短甲:2026-10-17'));
      final target = find.byKey(const ValueKey('dense:短甲:2026-10-17'));
      final leader = find.byKey(const ValueKey('short-leader:短甲:2026-10-17'));
      expect(tester.getSize(bands).width, 24);
      expect(tester.getRect(bands).right, lessThan(tester.getRect(badge).left));
      expect(tester.getSize(badge).height, 32);
      expect(tester.getSize(badge).width, inInclusiveRange(76, 88));
      expect(tester.getSize(target).height, 48);
      expect(leader, findsOneWidget);
      final decoration =
          tester.widget<Container>(badge).decoration! as BoxDecoration;
      final scheme = Theme.of(tester.element(badge)).colorScheme;
      expect(decoration.color, scheme.surface);
      expect(decoration.border, isNotNull);
      expect(
        tester.getRect(leader).left,
        greaterThanOrEqualTo(tester.getRect(bands).right),
      );
      await tester.tap(find.text('3项短任务'));
      await tester.pumpAndSettle();
      expect(find.text('10/17 11:00 → 10/17 11:03'), findsOneWidget);
      expect(find.text('10/17 11:05 → 10/17 11:09'), findsOneWidget);
      expect(find.text('10/17 11:12 → 10/17 11:15'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection panel omits local source and visible gap duplicates but keeps narrow-gap fallback',
    (tester) async {
      final task = {
        ..._block('紧凑选中', '2026-10-15T09:25:00', '2026-10-15T09:55:00'),
        'sourceLabel': '任务',
      };
      final before = _block(
        '前一项',
        '2026-10-15T08:00:00',
        '2026-10-15T09:00:00',
      );
      final after = _block('后一项', '2026-10-15T10:30:00', '2026-10-15T11:00:00');
      const options = {'dashboard': true, 'initialMinute': 480};
      await _mount(tester, blocks: [before, task, after], options: options);
      await tester.tap(find.text('紧凑选中'));
      await tester.pump();
      final panel = find.byKey(const ValueKey('planner-selection-panel'));
      expect(
        find.descendant(of: panel, matching: find.text('任务')),
        findsNothing,
      );
      expect(find.text('空闲25分钟'), findsOneWidget);
      expect(find.text('空闲35分钟'), findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.textContaining('空闲')),
        findsNothing,
      );
      final compactHeight = tester.getSize(panel).height;
      await _mount(
        tester,
        blocks: [
          before,
          {...task, 'start': '2026-10-15T09:05:00'},
          after,
        ],
        options: options,
      );
      expect(
        find.descendant(of: panel, matching: find.text('空闲5分钟')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('空闲35分钟')),
        findsNothing,
      );
      expect(tester.getSize(panel).height, greaterThan(compactHeight));
      await _mount(
        tester,
        blocks: [
          before,
          {...task, 'readOnly': true, 'sourceLabel': '课程'},
          after,
        ],
        options: options,
      );
      expect(
        find.descendant(of: panel, matching: find.text('课程')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'drag feedback clamps its actual size inside a narrow screen and preserves pointer-based drops',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'safe',
            'title': '完整反馈',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        options: const {'initialMinute': 540},
        onEvent: events.add,
      );
      final gesture = await _dragTo(
        tester,
        find.text('完整反馈'),
        const Offset(312, 650),
      );
      await tester.pump();
      final feedback = find.byKey(const ValueKey('planner-drag-feedback'));
      final rect = tester.getRect(feedback);
      expect(rect.left, greaterThanOrEqualTo(8));
      expect(rect.right, lessThanOrEqualTo(312));
      expect(rect.top, greaterThanOrEqualTo(8));
      expect(rect.bottom, lessThanOrEqualTo(692));
      final time = find.descendant(
        of: feedback,
        matching: find.textContaining(' → '),
      );
      expect(time, findsOneWidget);
      expect(tester.getRect(time).right, lessThanOrEqualTo(rect.right));
      expect(tester.getRect(time).bottom, lessThanOrEqualTo(rect.bottom));
      await gesture.up();
      await tester.pump();
      expect(events, hasLength(1));
      expect((events.single as Map)['id'], 'safe');
      // The feedback was shifted left, but the proposal still targets day 3.
      expect((events.single as Map)['start'], startsWith('2026-10-17'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dragging a still-visible original title never creates a continuation duplicate',
    (tester) async {
      await _mount(
        tester,
        blocks: [_block('不重复标题', '2026-10-15T09:00:00', '2026-10-15T10:30:00')],
        options: const {'dashboard': true, 'initialMinute': 540},
      );
      await tester.pumpAndSettle();
      expect(find.text('↳ 不重复标题').hitTestable(), findsNothing);
      final gesture = await _dragTo(
        tester,
        find.text('不重复标题'),
        _gridPoint(tester, 1, 9 * 60 + 30),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('↳ 不重复标题').hitTestable(), findsNothing);
      final original = find.byKey(const ValueKey('block:不重复标题:2026-10-15'));
      expect(
        find.descendant(of: original, matching: find.text('09:00')),
        findsOneWidget,
      );
      await gesture.cancel();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'drag proposals prefer explicit actual duration over wall clock difference',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: [
          {
            ..._block('dst', '2026-10-15T09:00:00', '2026-10-15T11:00:00'),
            'durationMinutes': 60.5,
          },
        ],
        onEvent: events.add,
      );
      final gesture = await _dragTo(
        tester,
        find.text('dst'),
        _gridPoint(tester, 1, 10 * 60),
      );
      await gesture.up();
      await tester.pump();
      expect((events.single as Map)['start'], '2026-10-16T10:00:00.000');
      expect((events.single as Map)['end'], '2026-10-16T11:00:30.000');
    },
  );

  testWidgets(
    '28 day board bounds mounted task widgets and reveals both dates and times on scroll',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final days = _month();
      final blocks = [
        for (var day = 0; day < 28; day++)
          for (var hour = 0; hour < 24; hour++)
            _block(
              'day${day}hour$hour',
              '${days[day]['date']}T${hour.toString().padLeft(2, '0')}:00:00',
              '${days[day]['date']}T${hour.toString().padLeft(2, '0')}:10:00',
            ),
      ];
      await _mount(tester, days: days, blocks: blocks);
      int cards() => find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key as ValueKey<String>).value.startsWith('block:'),
          )
          .evaluate()
          .length;
      int taskWidgets() => find
          .byWidgetPredicate((widget) {
            final key = widget.key;
            if (key is! ValueKey<String>) return false;
            return [
              'block:',
              'occupancy:',
              'resize-position:',
            ].any(key.value.startsWith);
          })
          .evaluate()
          .length;
      expect(blocks, hasLength(672));
      expect(cards(), inExclusiveRange(1, 80));
      final initialCards = cards(), initialWidgets = taskWidgets();
      expect(initialWidgets, lessThan(240));
      expect(
        find.byKey(ValueKey('block:day20hour20:${days[20]['date']}')),
        findsNothing,
      );
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-horizontal')),
          )
          .controller!;
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      horizontal.jumpTo(20 * 112);
      vertical.jumpTo(20 * 60);
      await tester.pump();
      await tester.pump();
      expect(find.text('day20hour20'), findsOneWidget);
      expect(find.text('day0hour9'), findsNothing);
      expect(cards(), lessThan(80));
      expect(taskWidgets(), lessThan(240));
      debugPrint(
        'PlannerBoard 672 tasks / 28 days: mounted cards $initialCards → ${cards()}, task surfaces $initialWidgets → ${taskWidgets()}',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dense collision group keeps isolated tasks separately selectable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mount(
        tester,
        blocks: [
          _block('拥挤A', '2026-10-15T09:00:00', '2026-10-15T09:05:00'),
          _block('拥挤B', '2026-10-15T09:00:00', '2026-10-15T09:05:00'),
          _block('孤立任务', '2026-10-15T14:00:00', '2026-10-15T14:30:00'),
        ],
      );
      expect(find.text('2项短任务'), findsOneWidget);
      expect(find.text('孤立任务'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('block:孤立任务:2026-10-15')))
            .width,
        greaterThan(90),
      );
      await tester.tap(find.text('2项短任务'));
      await tester.pumpAndSettle();
      expect(find.text('拥挤A'), findsOneWidget);
      expect(find.text('拥挤B'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('孤立任务'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long cross midnight occupations retain true bands and reachable labels inside viewport',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        days: _month(),
        options: const {'initialMinute': 720},
        blocks: [_block('长跨天', '2026-10-14T23:45:00', '2026-10-18T02:00:00')],
        onEvent: events.add,
      );
      final band = find.byKey(const ValueKey('occupancy:长跨天:2026-10-15'));
      expect(tester.getSize(band).height, 1440);
      final label = find.descendant(
        of: find.byKey(const ValueKey('resident:长跨天:2026-10-15')),
        matching: find.text('↳ 长跨天'),
      );
      final viewport = tester.getRect(
        find.byKey(const ValueKey('planner-vertical')),
      );
      expect(tester.getRect(label).overlaps(viewport), isTrue);
      await tester.tap(label);
      expect(events.single, {'action': 'detail', 'id': '长跨天'});
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-horizontal')),
          )
          .controller!;
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      horizontal.jumpTo(3 * 112);
      vertical.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('occupancy:长跨天:2026-10-18')))
            .height,
        120,
      );
      expect(
        find.byKey(const ValueKey('occupancy:长跨天:2026-10-15')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'virtualized drag and resize sources stay mounted through edge scrolling until release',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = <Object?>[];
      final blocks = [
        _block('source', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
      ];
      await _mount(tester, days: _month(), blocks: blocks, onEvent: events.add);
      final source = find.byKey(const ValueKey('block:source:2026-10-15'));
      final element = tester.element(source);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('planner-vertical')),
      );
      var gesture = await _dragTo(
        tester,
        find.text('source'),
        Offset(viewport.right - 5, viewport.center.dy),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(tester.element(source), same(element));
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(events, hasLength(1));
      expect((events.single as Map)['id'], 'source');
      expect(source, findsNothing);
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-horizontal')),
          )
          .controller!;
      horizontal.jumpTo(0);
      await tester.pump();
      await tester.pump();
      events.clear();
      final handle = find.byKey(const ValueKey('resize:source:2026-10-15'));
      final handleElement = tester.element(handle);
      gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveTo(Offset(viewport.right - 5, viewport.center.dy));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(tester.element(handle), same(handleElement));
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(events, hasLength(1));
      expect((events.single as Map)['intent'], 'resize');
      expect((events.single as Map)['start'], '2026-10-15T09:00:00.000');
      expect(handle, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'valid preview with overdue still states explicit confirmation is required',
    (tester) async {
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'due',
            'title': '截止任务',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        onPreview: (_) async => {
          'valid': true,
          'previewLabel': '移动 · 1项',
          'overdue': [
            {'taskId': 'due', 'title': '截止任务'},
          ],
        },
      );
      final gesture = await _dragTo(
        tester,
        find.text('截止任务'),
        _gridPoint(tester, 0, 9 * 60),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('安排超过截止，落下后需明确确认'), findsWidgets);
      await gesture.cancel();
      await tester.pump();
    },
  );

  testWidgets(
    'late preview after pointer cancellation or widget disposal cannot restore overlays',
    (tester) async {
      const candidates = [
        {
          'id': 'late',
          'title': '取消后预览',
          'durationMinutes': 30,
          'moveEvent': {'action': 'move'},
        },
      ];
      final pending = <Completer<BoardItem>>[];
      Future<BoardItem> preview(BoardItem _) {
        final c = Completer<BoardItem>();
        pending.add(c);
        return c.future;
      }

      await _mount(tester, candidates: candidates, onPreview: preview);
      var gesture = await _dragTo(
        tester,
        find.text('取消后预览'),
        _gridPoint(tester, 0, 9 * 60),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(pending, hasLength(1));
      await gesture.cancel();
      await tester.pump();
      pending[0].complete({'previewLabel': '已取消的回复'});
      await tester.pump();
      await tester.pump();
      expect(find.text('已取消的回复'), findsNothing);
      gesture = await _dragTo(
        tester,
        find.text('取消后预览'),
        _gridPoint(tester, 0, 10 * 60),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(pending, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
      pending[1].complete({'previewLabel': '已销毁的回复'});
      await gesture.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'canceling duration adjustment commits nothing and stops its scroll timer',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: [
          _block('cancel-size', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
        ],
        onEvent: events.add,
      );
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey('resize:cancel-size:2026-10-15')),
        ),
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.cancel();
      await tester.pump();
      final offset = vertical.offset;
      await tester.pump(const Duration(milliseconds: 800));
      expect(vertical.offset, offset);
      expect(events, isEmpty);
      expect(find.textContaining('调整时长'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edge auto scroll moves both axes, keeps fine mode and stops on drop or cancel',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = <Object?>[];
      const candidates = [
        {
          'id': 'edge',
          'title': '边缘任务',
          'durationMinutes': 30,
          'moveEvent': {'action': 'move'},
        },
      ];
      await _mount(tester, candidates: candidates, onEvent: events.add);
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-horizontal')),
          )
          .controller!;
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      final viewport = tester.getRect(
        find.byKey(const ValueKey('planner-vertical')),
      );
      final initialY = vertical.offset;
      var gesture = await _dragTo(
        tester,
        find.text('边缘任务'),
        viewport.bottomRight - const Offset(10, 12),
      );
      for (var i = 0; i < 28; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(horizontal.offset, greaterThan(0));
      expect(vertical.offset, greaterThan(initialY));
      expect(find.textContaining('1分钟细调'), findsWidgets);
      await gesture.up();
      await tester.pump();
      expect((events.single as Map)['snapMinutes'], 1);
      final x = horizontal.offset, y = vertical.offset;
      await tester.pump(const Duration(milliseconds: 400));
      expect(horizontal.offset, x);
      expect(vertical.offset, y);
      events.clear();
      gesture = await _dragTo(
        tester,
        find.text('边缘任务'),
        viewport.topLeft + const Offset(55, 8),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.cancel();
      await tester.pump();
      final canceledX = horizontal.offset, canceledY = vertical.offset;
      await tester.pump(const Duration(milliseconds: 800));
      expect(horizontal.offset, canceledX);
      expect(vertical.offset, canceledY);
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('edge auto scroll respects both maximum extents', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(
      tester,
      candidates: const [
        {
          'id': 'bound',
          'title': '边界任务',
          'durationMinutes': 30,
          'moveEvent': {'action': 'move'},
        },
      ],
    );
    final horizontal = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('planner-horizontal')),
        )
        .controller!;
    final vertical = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('planner-vertical')),
        )
        .controller!;
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    vertical.jumpTo(vertical.position.maxScrollExtent);
    await tester.pump();
    final rect = tester.getRect(find.byKey(const ValueKey('planner-vertical')));
    final gesture = await _dragTo(
      tester,
      find.text('边界任务'),
      rect.bottomRight - const Offset(4, 4),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(horizontal.offset, horizontal.position.maxScrollExtent);
    expect(vertical.offset, vertical.position.maxScrollExtent);
    await gesture.cancel();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'duration handle changes only end and protects minimum positive duration',
    (tester) async {
      final events = <Object?>[];
      final blocks = [
        _block('resize', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
      ];
      await _mount(tester, blocks: blocks, onEvent: events.add);
      var handle = find.byKey(const ValueKey('resize:resize:2026-10-15'));
      var gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(find.textContaining('调整时长'), findsWidgets);
      await gesture.up();
      await tester.pump();
      expect(events.single, {
        'action': 'move',
        'id': 'resize',
        'start': '2026-10-15T09:00:00.000',
        'end': '2026-10-15T10:30:00.000',
        'intent': 'resize',
        'snapMinutes': 15,
      });
      events.clear();
      gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, -90));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect((events.single as Map)['end'], '2026-10-15T09:01:00.000');
    },
  );

  testWidgets(
    'cross midnight resize is one operation and fixed or read only sources have no handle',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        options: const {'initialMinute': 0},
        blocks: [
          _block('night', '2026-10-15T23:45:00', '2026-10-16T00:30:00'),
          {
            ..._block('fixed', '2026-10-15T01:00:00', '2026-10-15T02:00:00'),
            'fixed': true,
          },
          _block(
            'course',
            '2026-10-15T03:00:00',
            '2026-10-15T04:00:00',
            readOnly: true,
          ),
        ],
        onEvent: events.add,
      );
      expect(
        find.byKey(const ValueKey('resize:night:2026-10-15')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('resize:fixed:2026-10-15')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('resize:course:2026-10-15')),
        findsNothing,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('resize:night:2026-10-16'))),
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(events, hasLength(1));
      expect((events.single as Map)['start'], '2026-10-15T23:45:00.000');
      expect((events.single as Map)['end'], '2026-10-16T01:00:00.000');
      expect((events.single as Map)['intent'], 'resize');
    },
  );

  testWidgets(
    'local swap previews both origins while keeping each tasks duration',
    (tester) async {
      await _mount(
        tester,
        blocks: [
          _block('a', '2026-10-15T09:00:00', '2026-10-15T09:30:00'),
          _block('b', '2026-10-16T10:00:00', '2026-10-16T11:30:00'),
        ],
      );
      final gesture = await _dragTo(
        tester,
        find.text('a'),
        _gridPoint(tester, 1, 10 * 60 + 45),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final a = find.byKey(const ValueKey('local:a:2026-10-16'));
      final b = find.byKey(const ValueKey('local:b:2026-10-15'));
      expect(tester.getSize(a).height, 30);
      expect(tester.getSize(b).height, 90);
      expect(
        tester.getTopLeft(a).dy,
        tester
            .getTopLeft(find.byKey(const ValueKey('occupancy:b:2026-10-16')))
            .dy,
      );
      expect(
        tester.getTopLeft(b).dy,
        tester
            .getTopLeft(find.byKey(const ValueKey('occupancy:a:2026-10-15')))
            .dy,
      );
      expect(find.text('交换几何预览 · 15分钟吸附'), findsOneWidget);
      await gesture.cancel();
      await tester.pump();
    },
  );

  testWidgets(
    'releasing during target transition cannot swap the previously hovered task',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'source',
            'title': '过渡任务',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        blocks: [
          _block('a', '2026-10-16T09:00:00', '2026-10-16T10:00:00'),
          _block('b', '2026-10-17T09:00:00', '2026-10-17T10:00:00'),
        ],
        onEvent: events.add,
      );
      final gesture = await _dragTo(
        tester,
        find.text('过渡任务'),
        _gridPoint(tester, 1, 9 * 60 + 30),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('交换 · 待校验'), findsOneWidget);
      await gesture.moveTo(_gridPoint(tester, 2, 9 * 60 + 30));
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.up();
      await tester.pump();
      expect((events.single as Map)['intent'], 'move');
      expect((events.single as Map).containsKey('targetId'), isFalse);
    },
  );

  testWidgets(
    'preview requests debounce and ignore out of order replies, cancellation and view changes',
    (tester) async {
      final requests = <BoardItem>[];
      final pending = <Completer<BoardItem>>[];
      final events = <Object?>[];
      const candidates = [
        {
          'id': 'async',
          'title': '异步任务',
          'durationMinutes': 30,
          'moveEvent': {'action': 'move'},
        },
      ];
      Future<BoardItem> preview(BoardItem event) {
        requests.add(event);
        final completer = Completer<BoardItem>();
        pending.add(completer);
        return completer.future;
      }

      await _mount(
        tester,
        candidates: candidates,
        onPreview: preview,
        onEvent: events.add,
        previewIdentity: 'v1',
      );
      final gesture = await _dragTo(
        tester,
        find.text('异步任务'),
        _gridPoint(tester, 0, 9 * 60),
      );
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, 2));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      expect(requests, hasLength(1));
      await gesture.moveTo(_gridPoint(tester, 0, 10 * 60));
      await tester.pump(const Duration(milliseconds: 200));
      expect(requests, hasLength(2));
      pending[1].complete({
        'valid': false,
        'previewLabel': '服务校验结果',
        'conflicts': ['与课程冲突'],
        'previewBlocks': [
          _block('service', '2026-10-16T10:00:00', '2026-10-16T10:30:00'),
        ],
      });
      await tester.pump();
      await tester.pump();
      expect(find.text('与课程冲突'), findsWidgets);
      expect(
        find.byKey(const ValueKey('service:service:2026-10-16')),
        findsOneWidget,
      );
      pending[0].complete({'previewLabel': '过时结果'});
      await tester.pump();
      expect(find.text('过时结果'), findsNothing);
      await _mount(
        tester,
        candidates: candidates,
        onPreview: preview,
        onEvent: events.add,
        previewIdentity: 'v2',
      );
      await gesture.moveTo(_gridPoint(tester, 1, 10 * 60));
      await tester.pump(const Duration(milliseconds: 220));
      await gesture.up();
      await tester.pump();
      expect(events, isEmpty);
      expect(requests, hasLength(2));
      expect(find.text('服务校验结果'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending preview and edge timers are harmless after disable and disposal',
    (tester) async {
      final completer = Completer<BoardItem>();
      var calls = 0;
      const candidates = [
        {
          'id': 'dispose',
          'title': '生命周期任务',
          'durationMinutes': 30,
          'moveEvent': {'action': 'move'},
        },
      ];
      Future<BoardItem> preview(BoardItem _) {
        calls++;
        return completer.future;
      }

      await _mount(tester, candidates: candidates, onPreview: preview);
      final gesture = await _dragTo(
        tester,
        find.text('生命周期任务'),
        _gridPoint(tester, 0, 9 * 60),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, 1);
      await _mount(
        tester,
        candidates: candidates,
        onPreview: preview,
        enabled: false,
      );
      completer.complete({'previewLabel': '禁用后的结果'});
      await tester.pump();
      expect(find.text('禁用后的结果'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await gesture.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'target dwell distinguishes center swap from edge insertion and preserves raw ids',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'source',
            'title': '拖动源',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        blocks: [
          _block('target', '2026-10-16T09:00:00', '2026-10-16T10:30:00'),
        ],
        onEvent: events.add,
      );
      var gesture = await _dragTo(
        tester,
        find.text('拖动源'),
        _gridPoint(tester, 1, 9 * 60 + 45),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('交换 · 待校验'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect((events.last as Map)['intent'], 'swap');
      expect((events.last as Map)['targetId'], 'target');
      gesture = await _dragTo(
        tester,
        find.text('拖动源'),
        _gridPoint(tester, 1, 9 * 60),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('插入 · 待校验'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect((events.last as Map)['intent'], 'insert');
      expect((events.last as Map)['targetId'], 'target');
    },
  );

  testWidgets(
    '100 overlapping blocks retain true stripes and accessible choice without negative widths',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: List.generate(
          100,
          (i) => _block('密集$i', '2026-10-15T09:00:00', '2026-10-15T09:05:00'),
        ),
        onEvent: events.add,
      );
      expect(tester.takeException(), isNull);
      final stripe = find.byKey(
        const ValueKey('dense-occupancy:密集0:2026-10-15'),
      );
      expect(tester.getSize(stripe).width, greaterThan(0));
      // One painter carries all exact-length bands; aggregation has a separate
      // minimum-height selection label and does not create 100 band widgets.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>).value.startsWith('occupancy:密集'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('100项短任务'));
      await tester.pumpAndSettle();
      expect(find.text('密集0'), findsOneWidget);
      await tester.tap(find.text('密集0'));
      await tester.pumpAndSettle();
      expect(events.single, {'action': 'detail', 'id': '密集0'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320 wide board scrolls dates at 1.5 text scale and preserves candidate identity',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = <Object?>[];
      await _mount(
        tester,
        scaler: const TextScaler.linear(1.5),
        candidates: const [
          {
            'id': 'raw-task',
            'title': '待选任务',
            'selected': true,
            'selectEvent': {'type': 'select', 'id': 'candidate:raw-task'},
          },
        ],
        onEvent: events.add,
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      await tester.tap(find.byType(Checkbox));
      expect(events.single, {
        'type': 'select',
        'id': 'candidate:raw-task',
        'selected': false,
        'value': false,
      });
      events.clear();
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-horizontal')),
          )
          .controller!;
      expect(horizontal.position.maxScrollExtent, greaterThan(0));
      await tester.drag(
        find.byKey(const ValueKey('planner-horizontal')),
        const Offset(-230, 0),
      );
      await tester.pumpAndSettle();
      expect(horizontal.offset, greaterThan(0));
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      final before = vertical.offset;
      await tester.drag(
        find.byKey(const ValueKey('planner-vertical')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(vertical.offset, greaterThan(before));
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deadline summary never changes execution placement; short occupancy stays true length',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: [
          {
            ..._block('短任务', '2026-10-15T09:00:00', '2026-10-15T09:05:00'),
            'deadlineSummary': '截10/19',
          },
          _block('长任务', '2026-10-15T10:00:00', '2026-10-15T11:30:00'),
        ],
        onEvent: events.add,
      );
      final short = find.byKey(const ValueKey('occupancy:短任务:2026-10-15'));
      final long = find.byKey(const ValueKey('occupancy:长任务:2026-10-15'));
      expect(tester.getSize(short).height, 5);
      expect(tester.getSize(long).height, 90);
      expect(tester.getTopLeft(long).dy - tester.getTopLeft(short).dy, 60);
      expect(find.text('截10/19'), findsNothing);
      expect(find.text('09:00–09:05'), findsOneWidget);
      expect(find.text('10:00'), findsWidgets);
      expect(find.text('11:30'), findsOneWidget);
      await tester.tap(find.text('短任务'));
      expect(events.single, {'action': 'detail', 'id': '短任务'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'candidate long press proposes another day with duration and 15 minute snapping',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'raw-task',
            'title': '候选任务',
            'durationMinutes': 30,
            'deadlineSummary': '截10/15',
            'moveEvent': {'action': 'move'},
          },
        ],
        onEvent: events.add,
      );
      final gesture = await _dragTo(
        tester,
        find.text('候选任务'),
        _gridPoint(tester, 1, 9 * 60 + 8),
      );
      expect(find.textContaining('15分钟吸附'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      final event = events.single as Map;
      expect(event['id'], 'raw-task');
      expect(event['start'], '2026-10-16T09:15:00.000');
      expect(event['end'], '2026-10-16T09:45:00.000');
      expect(event['snapMinutes'], 15);
      expect(event['intent'], 'move');
      expect(event.containsKey('deadlineSummary'), isFalse);
      expect(find.text('候选任务'), findsOneWidget);
    },
  );

  testWidgets(
    'stationary dwell enters one minute mode without shifting the candidate time',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'fine',
            'title': '细调任务',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        onEvent: events.add,
      );
      final point = _gridPoint(tester, 0, 9 * 60 + 7);
      final gesture = await _dragTo(tester, find.text('细调任务'), point);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.textContaining('1分钟细调'), findsOneWidget);
      expect(find.text('10/15 09:00 → 10/15 09:30'), findsOneWidget);
      await gesture.moveBy(const Offset(0, 3));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect((events.single as Map)['start'], '2026-10-15T09:03:00.000');
      expect((events.single as Map)['snapMinutes'], 1);
    },
  );

  testWidgets(
    'courses and fixed tasks expose details and cannot initiate a drag',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: [
          _block(
            '只读课程',
            '2026-10-15T09:00:00',
            '2026-10-15T10:00:00',
            readOnly: true,
          ),
          {
            ..._block('固定任务', '2026-10-15T10:00:00', '2026-10-15T11:00:00'),
            'fixed': true,
          },
        ],
        onEvent: events.add,
      );
      expect(find.byType(LongPressDraggable<BoardItem>), findsNothing);
      await tester.tap(find.text('只读课程'));
      expect(events.single, {'action': 'detail', 'id': '只读课程'});
    },
  );

  testWidgets(
    'cross midnight segments share an id and caller previews retain both swap locations',
    (tester) async {
      await _mount(
        tester,
        blocks: [_block('跨夜', '2026-10-15T23:45:00', '2026-10-16T00:30:00')],
        previewBlocks: [
          _block('first', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
          _block('second', '2026-10-16T10:00:00', '2026-10-16T10:30:00'),
        ],
      );
      expect(
        find.byKey(const ValueKey('occupancy:跨夜:2026-10-15')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('preview:first:2026-10-15')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('preview:second:2026-10-16')),
        findsOneWidget,
      );
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      vertical.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('occupancy:跨夜:2026-10-16')))
            .height,
        30,
      );
      vertical.jumpTo(vertical.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('occupancy:跨夜:2026-10-15')))
            .height,
        15,
      );
    },
  );

  testWidgets('outside range entry preserves access to hidden occupations', (
    tester,
  ) async {
    final events = <Object?>[];
    await _mount(
      tester,
      blocks: [_block('隐藏安排', '2026-10-15T06:00:00', '2026-10-15T07:00:00')],
      options: const {'startMinute': 480, 'endMinute': 1080},
      onEvent: events.add,
    );
    expect(
      find.byKey(const ValueKey('occupancy:隐藏安排:2026-10-15')),
      findsNothing,
    );
    await tester.tap(find.text('显示范围外有 1 项安排 · 查看'));
    await tester.pumpAndSettle();
    expect(find.text('10/15 06:00 → 10/15 07:00'), findsOneWidget);
    await tester.tap(find.text('隐藏安排'));
    await tester.pumpAndSettle();
    expect(events.single, {'action': 'detail', 'id': '隐藏安排'});
  });

  testWidgets(
    'large text keeps two candidate rows and selection is a separate event',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        scaler: const TextScaler.linear(2),
        candidates: const [
          {
            'id': 'one',
            'title': '无截止',
            'event': {'action': 'detail'},
          },
          {'id': 'two', 'title': '第二行', 'deadlineSummary': '截10/16'},
          {'id': 'three', 'title': '第三列'},
        ],
        selectEvent: const {'action': 'select'},
        selectedIds: const ['one'],
        onEvent: events.add,
      );
      final checkboxes = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .toList();
      expect(checkboxes.first.value, isTrue);
      await tester.tap(find.byType(Checkbox).first);
      expect(events.single, {
        'action': 'select',
        'id': 'one',
        'selected': false,
        'value': false,
      });
      expect(
        tester.getTopLeft(find.text('无截止')).dy,
        lessThan(tester.getTopLeft(find.text('第二行')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
