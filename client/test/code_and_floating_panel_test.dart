import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_app/core/ui/ui_design.dart';
import 'package:task_app/core/ui/code_preview_dialog.dart';
import 'package:task_app/core/ui/draggable_floating_panel.dart';

Widget _testApp({
  required Widget home,
  Brightness brightness = Brightness.light,
}) => ProviderScope(
  child: MaterialApp(theme: AppDesign.theme(brightness), home: home),
);

void main() {
  testWidgets(
    'failed code copy keeps dialog open and retry shows only a transient success',
    (tester) async {
      var failing = true;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            if (failing) throw PlatformException(code: 'clipboard-unavailable');
            copied = (call.arguments as Map)['text'] as String;
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
      await tester.pumpWidget(
        _testApp(
          home: const CodePreviewDialog(
            title: '调用方式',
            sections: [
              {'title': '组件', 'code': 'ui.component()'},
            ],
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('copy-all-code')));
      await tester.pumpAndSettle();
      expect(find.text('复制失败，请重试'), findsOneWidget);
      expect(find.byType(CodePreviewDialog), findsOneWidget);
      expect(find.textContaining('已复制：'), findsNothing);
      failing = false;
      await tester.tap(find.text('重试复制'));
      await tester.pumpAndSettle();
      expect(copied, 'ui.component()');
      expect(find.text('复制失败，请重试'), findsNothing);
      expect(find.text('已复制：全部调用方式'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CodePreviewDialog),
          matching: find.textContaining('已复制：'),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.textContaining('已复制：'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('code popup copies a section and all exact multiline code', (
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
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const first = "await ui.notify({\n  message: '完成',\n});";
    const second = "if (event?.type === 'press') {\n  state.ready = true;\n}";
    await tester.pumpWidget(
      _testApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCodePreviewDialog(context, {
                'title': '调用方式',
                'sections': [
                  {'title': '组件调用', 'code': first},
                  {'title': '事件处理', 'code': second},
                ],
              }),
              child: const Text('打开代码'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开代码'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('copy-code-0')));
    await tester.pump();
    expect(clipboard, first);
    expect(find.text('已复制：组件调用'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CodePreviewDialog),
        matching: find.textContaining('已复制：'),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('copy-all-code')));
    await tester.pump();
    expect(clipboard, '$first\n\n$second');
    expect(find.text('已复制：全部调用方式'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('关闭调用方式'));
    await tester.pumpAndSettle();
    expect(find.byType(CodePreviewDialog), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'small floating panel drags within bounds and child stays usable',
    (tester) async {
      final viewport = ValueNotifier(const Size(500, 500));
      addTearDown(viewport.dispose);
      var presses = 0, closes = 0;
      await tester.pumpWidget(
        _testApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: viewport,
              builder: (_, size, _) => Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Stack(
                    children: [
                      DraggableFloatingPanel(
                        viewport: size,
                        title: '悬浮窗',
                        bottomInset: 70,
                        onClose: () => closes++,
                        child: Column(
                          children: [
                            const TextField(),
                            TextButton(
                              onPressed: () => presses++,
                              child: const Text('操作'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final handle = find.byKey(
        const ValueKey('script-floating-panel-drag-handle'),
      );
      final panel = find.byType(DraggableFloatingPanel);
      final initial = tester.getRect(panel);
      expect(initial.width, 300);
      await tester.enterText(find.byType(TextField), '保留内容');
      final state = tester.state(find.byType(TextField));
      await tester.drag(handle, const Offset(-120, 120));
      await tester.pump();
      expect(tester.getRect(panel).left, lessThan(initial.left));
      expect(tester.getRect(panel).top, greaterThan(initial.top));
      expect(identical(state, tester.state(find.byType(TextField))), isTrue);
      expect(find.text('保留内容'), findsOneWidget);
      await tester.tap(find.text('操作'));
      await tester.pump();
      expect(presses, 1);
      await tester.drag(handle, const Offset(-2000, 2000));
      await tester.pump();
      final moved = tester.getRect(panel);
      expect(moved.left, greaterThanOrEqualTo(12));
      expect(moved.bottom, lessThanOrEqualTo(430));
      viewport.value = const Size(320, 400);
      await tester.pump();
      final resized = tester.getRect(panel);
      expect(resized.right, lessThanOrEqualTo(320));
      expect(resized.bottom, lessThanOrEqualTo(330));
      viewport.value = const Size(320, 140);
      await tester.pump();
      expect(tester.getRect(panel).bottom, lessThanOrEqualTo(70));
      expect(identical(state, tester.state(find.byType(TextField))), isTrue);
      await tester.tap(find.byTooltip('关闭面板'));
      expect(closes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'long code title keeps copying and closing accessible at large text $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          _testApp(
            brightness: brightness,
            home: CodePreviewDialog(
              title: '长标题' * 40,
              sections: const [
                {'title': '组件', 'code': 'ui.component()'},
              ],
            ),
          ),
        );
        final copy = tester.getRect(
          find.byKey(const ValueKey('copy-all-code')),
        );
        expect(copy.bottom, lessThanOrEqualTo(600));
        expect(find.byTooltip('关闭调用方式'), findsOneWidget);
        final dialog = tester.widget<Dialog>(find.byType(Dialog));
        expect(
          dialog.shape,
          AppDesign.smoothShape(radius: AppDesign.floatingRadius),
        );
        expect(dialog.insetPadding, AppDesign.dialogInsets);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
