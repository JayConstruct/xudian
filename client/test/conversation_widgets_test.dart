import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/conversation_widgets.dart';
import 'package:task_app/core/ui/ui_design.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'conversation remains readable at 320px with large text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final controller = TextEditingController(text: '下一条消息');
        final focus = FocusNode();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppDesign.theme(brightness),
            home: Scaffold(
              body: Column(
                children: [
                  const Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          ConversationMessage(
                            text: '帮我查看今天的待办与课程安排',
                            outgoing: true,
                            label: '你',
                          ),
                          ConversationMessage(
                            text: '今天还有三项待办，可以先阅读论文，再整理笔记。',
                            outgoing: false,
                            label: 'AI 助手',
                          ),
                        ],
                      ),
                    ),
                  ),
                  ConversationComposer(
                    controller: controller,
                    focusNode: focus,
                    hint: '输入消息…',
                    busy: false,
                    onChanged: (_) {},
                    onSend: () {},
                    onCancel: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          tester.widget<TextField>(find.byType(TextField)).style?.fontSize,
          14,
        );
        expect(
          tester.getSize(find.byTooltip('发送')).width,
          greaterThanOrEqualTo(48),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        focus.dispose();
      },
    );
  }

  testWidgets(
    'composer sends valid text and allows a new draft while cancel is active',
    (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      var busy = false, sent = 0, cancelled = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return ConversationComposer(
                  controller: controller,
                  focusNode: focus,
                  hint: '输入消息…',
                  busy: busy,
                  onChanged: (_) {},
                  onSend: () => sent++,
                  onCancel: () => cancelled++,
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('发送'));
      expect(sent, 0);
      await tester.enterText(find.byType(TextField), '第一条');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      expect(sent, 1);
      rebuild(() => busy = true);
      await tester.pump();
      await tester.enterText(find.byType(TextField), '保留下一条草稿');
      await tester.tap(find.byTooltip('取消当前操作'));
      expect(cancelled, 1);
      expect(controller.text, '保留下一条草稿');
      rebuild(() => busy = false);
      await tester.pump();
      expect(controller.text, '保留下一条草稿');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      focus.dispose();
    },
  );
}
