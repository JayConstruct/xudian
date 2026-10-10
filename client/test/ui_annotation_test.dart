import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/ui_annotation.dart';

Widget _app(Widget body, {bool controls = true}) => ProviderScope(
  child: MaterialApp(
    builder: controls
        ? (context, child) => AnnotationControls(child: child)
        : null,
    home: Scaffold(body: body),
  ),
);

UiAnnotationController _controller(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(UiAnnotation).first),
      listen: false,
    ).read(uiAnnotationProvider.notifier);

Finder _badge(String number) =>
    find.byKey(ValueKey('ui-annotation-badge-$number'));

void main() {
  testWidgets('SafeArea cannot move badges into the system status bar', (
    tester,
  ) async {
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 16);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      _app(
        const SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: UiAnnotation(
              id: 'app.demo.header',
              name: '顶部入口',
              child: SizedBox(width: 48, height: 48),
            ),
          ),
        ),
      ),
    );
    _controller(tester).setEnabled(true);
    await tester.pumpAndSettle();
    final badge = tester.getRect(_badge('U01'));
    expect(badge.top, greaterThanOrEqualTo(24));
    expect(
      badge.bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height - 16),
    );
    expect(tester.takeException(), isNull);
  });

  test('annotation mode belongs to the current provider session only', () {
    final first = ProviderContainer.test();
    expect(first.read(uiAnnotationProvider), isFalse);
    first.read(uiAnnotationProvider.notifier).setEnabled(true);
    expect(first.read(uiAnnotationProvider), isTrue);
    final next = ProviderContainer.test();
    expect(next.read(uiAnnotationProvider), isFalse);
    expect(next.read(uiAnnotationProvider.notifier).isHidden, isFalse);
  });

  testWidgets(
    'overlay preserves size, position, child state and ordinary taps',
    (tester) async {
      var taps = 0;
      final input = TextEditingController(text: '保持输入');
      addTearDown(input.dispose);
      const areaKey = ValueKey('business-area');
      await tester.pumpWidget(
        _app(
          Center(
            child: UiAnnotation(
              id: 'app.demo.form',
              name: '输入区域',
              child: SizedBox(
                key: areaKey,
                width: 240,
                height: 180,
                child: Column(
                  children: [
                    TextField(controller: input),
                    TextButton(
                      onPressed: () => taps++,
                      child: const Text('业务操作'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byKey(areaKey));
      final position = tester.getTopLeft(find.byKey(areaKey));
      expect(_badge('U01'), findsNothing);
      expect(find.byTooltip('退出界面标注'), findsNothing);
      final controller = _controller(tester);
      controller.setEnabled(true);
      await tester.pumpAndSettle();
      expect(_badge('U01'), findsOneWidget);
      expect(tester.getSize(find.byKey(areaKey)), size);
      expect(tester.getTopLeft(find.byKey(areaKey)), position);
      await tester.tap(find.text('业务操作'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(input.text, '保持输入');
      controller.setEnabled(false);
      await tester.pumpAndSettle();
      expect(_badge('U01'), findsNothing);
      expect(tester.getSize(find.byKey(areaKey)), size);
      expect(tester.getTopLeft(find.byKey(areaKey)), position);
      expect(input.text, '保持输入');
      await tester.tap(find.text('业务操作'));
      await tester.pumpAndSettle();
      expect(taps, 2);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'repeated stable IDs receive data-free, distinct session numbers',
    (tester) async {
      await tester.pumpWidget(
        _app(
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final objectId in ['private-task-123', 'private-task-456'])
                  Padding(
                    padding: const EdgeInsets.all(30),
                    child: UiAnnotation(
                      key: ValueKey(objectId),
                      id: 'app.tasks.complete',
                      name: '完成按钮',
                      child: SizedBox(
                        width: 160,
                        height: 40,
                        child: TextButton(
                          onPressed: () {},
                          child: const Text('完成'),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      final controller = _controller(tester);
      controller.setEnabled(true);
      await tester.pumpAndSettle();
      expect(find.text('U01 · 完成按钮'), findsOneWidget);
      expect(find.text('U02 · 完成按钮'), findsOneWidget);
      controller.setHidden(true);
      await tester.pumpAndSettle();
      expect(_badge('U01'), findsNothing);
      expect(_badge('U02'), findsNothing);
      controller.setHidden(false);
      await tester.pumpAndSettle();
      expect(_badge('U01'), findsOneWidget);
      expect(_badge('U02'), findsOneWidget);
      await tester.tap(_badge('U02'));
      await tester.pumpAndSettle();
      final description = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      expect(description, contains('会话编号：U02'));
      expect(description, contains('UI ID：app.tasks.complete'));
      expect(description, isNot(contains('private-task')));
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inspection copies declared metadata, never child data or keys', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
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
    final input = TextEditingController(text: 'private-input-secret');
    addTearDown(input.dispose);
    await tester.pumpWidget(
      _app(
        Center(
          child: UiAnnotation(
            key: const ValueKey('business-object-id-987'),
            id: 'app.demo.editor',
            name: '任务编辑',
            moduleId: 'app.demo',
            pagePath: 'app.demo.home / app.demo.edit',
            slot: 'editor',
            purpose: '编辑内容',
            child: SizedBox(
              width: 260,
              height: 160,
              child: Column(
                children: [
                  const Text('private-task-body'),
                  TextField(controller: input),
                  Semantics(
                    label: 'private-object-id',
                    child: const Text('正文'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _controller(tester).setEnabled(true);
    await tester.pumpAndSettle();
    await tester.tap(_badge('U01'));
    await tester.pumpAndSettle();
    final description = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(description, contains('UI ID：app.demo.editor'));
    expect(description, contains('模块：app.demo'));
    expect(description, contains('页面路径：app.demo.home / app.demo.edit'));
    expect(description, contains('槽位：editor'));
    expect(description, isNot(contains('private-')));
    expect(description, isNot(contains('business-object-id')));
    await tester.tap(find.text('复制标识'));
    await tester.pumpAndSettle();
    expect(clipboard, description);
    expect(find.byType(AlertDialog), findsNothing);
    expect(_badge('U01'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('independent controls pause, resume, move and exit safely', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Center(
          child: UiAnnotation(
            id: 'app.demo.action',
            name: '业务按钮',
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('正常点击'),
            ),
          ),
        ),
      ),
    );
    final controller = _controller(tester);
    controller.setEnabled(true);
    await tester.pumpAndSettle();
    final initialExit = tester.getCenter(find.byTooltip('退出界面标注'));
    await tester.drag(
      find.byIcon(Icons.drag_indicator),
      const Offset(-200, -120),
    );
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byTooltip('退出界面标注')), isNot(initialExit));
    await tester.tap(find.byTooltip('暂时隐藏标注'));
    await tester.pumpAndSettle();
    expect(controller.isHidden, isTrue);
    expect(_badge('U01'), findsNothing);
    expect(find.byTooltip('退出界面标注'), findsOneWidget);
    await tester.tap(find.text('正常点击'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    await tester.tap(find.byTooltip('显示标注'));
    await tester.pumpAndSettle();
    expect(controller.isHidden, isFalse);
    expect(_badge('U01'), findsOneWidget);
    await tester.tap(find.byTooltip('退出界面标注'));
    await tester.pumpAndSettle();
    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(UiAnnotation)),
        listen: false,
      ).read(uiAnnotationProvider),
      isFalse,
    );
    expect(find.byTooltip('退出界面标注'), findsNothing);
    expect(_badge('U01'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('root exit remains available while inspecting a region', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Center(
          child: UiAnnotation(
            id: 'app.demo.inspect',
            name: '检查区域',
            child: SizedBox(width: 240, height: 160),
          ),
        ),
      ),
    );
    _controller(tester).setEnabled(true);
    await tester.pumpAndSettle();
    await tester.tap(_badge('U01'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byTooltip('退出界面标注'), findsOneWidget);
    await tester.tap(find.byTooltip('退出界面标注'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('退出界面标注'), findsNothing);
    expect(_badge('U01'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clipped and offscreen annotations follow scrolling', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    const viewportKey = ValueKey('clipped-viewport');
    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox(
            key: viewportKey,
            width: 280,
            height: 180,
            child: ClipRect(
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    const UiAnnotation(
                      id: 'app.demo.first',
                      name: '第一项',
                      child: SizedBox(width: 160, height: 50),
                    ),
                    const SizedBox(height: 300),
                    const UiAnnotation(
                      id: 'app.demo.last',
                      name: '末项',
                      child: SizedBox(width: 160, height: 50),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _controller(tester).setEnabled(true);
    await tester.pumpAndSettle();
    expect(find.text('U01 · 第一项'), findsOneWidget);
    expect(find.textContaining('· 末项'), findsNothing);
    final viewport = tester.getRect(find.byKey(viewportKey));
    final first = tester.getRect(_badge('U01'));
    expect(viewport.contains(first.topLeft), isTrue);
    expect(
      viewport.contains(first.bottomRight - const Offset(0.1, 0.1)),
      isTrue,
    );
    scroll.jumpTo(330);
    await tester.pumpAndSettle();
    expect(find.textContaining('· 第一项'), findsNothing);
    expect(find.text('U02 · 末项'), findsOneWidget);
    final last = tester.getRect(_badge('U02'));
    expect(viewport.contains(last.topLeft), isTrue);
    expect(
      viewport.contains(last.bottomRight - const Offset(0.1, 0.1)),
      isTrue,
    );
    _controller(tester).setEnabled(false);
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(_badge('U01'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested regions avoid label collisions and adapt to large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Center(
          child: UiAnnotation(
            id: 'app.demo.region',
            name: '很长的父级页面区域名称，用于验证大字布局',
            child: SizedBox(
              width: 260,
              height: 260,
              child: Center(
                child: UiAnnotation(
                  id: 'app.demo.nested',
                  name: '很长的嵌套操作入口名称，用于验证标签裁剪',
                  child: SizedBox(
                    width: 180,
                    height: 80,
                    child: TextButton(
                      onPressed: () => taps++,
                      child: const Text('执行'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _controller(tester).setEnabled(true);
    await tester.pumpAndSettle();
    expect(_badge('U01'), findsOneWidget);
    expect(_badge('U02'), findsOneWidget);
    final parent = tester.getRect(_badge('U01'));
    final child = tester.getRect(_badge('U02'));
    expect(parent.overlaps(child), isFalse);
    for (final rectangle in [parent, child]) {
      expect(rectangle.width, lessThanOrEqualTo(240));
      expect(rectangle.left, greaterThanOrEqualTo(0));
      expect(rectangle.right, lessThanOrEqualTo(320));
      expect(rectangle.top, greaterThanOrEqualTo(0));
      expect(rectangle.bottom, lessThanOrEqualTo(640));
    }
    await tester.tap(find.text('执行'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'annotations also work without root controls and survive teardown',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const Center(
            child: UiAnnotation(
              id: 'app.demo.standalone',
              name: '独立区域',
              child: SizedBox(width: 200, height: 100),
            ),
          ),
          controls: false,
        ),
      );
      _controller(tester).setEnabled(true);
      await tester.pumpAndSettle();
      expect(_badge('U01'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );
}
