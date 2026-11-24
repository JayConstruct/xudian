import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/tab_content_transition.dart';
import 'package:task_app/core/ui/ui_motion.dart';

void main() {
  for (final sliver in [false, true]) {
    testWidgets(
      'tab body moves in order and retains the editor (sliver=$sliver)',
      (tester) async {
        final focus = FocusNode();
        final controller = TextEditingController(text: '草稿');
        addTearDown(focus.dispose);
        addTearDown(controller.dispose);
        Future<void> show(int index, {bool reduced = false}) async {
          final body = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('页面 $index'),
              TextField(focusNode: focus, controller: controller),
            ],
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(disableAnimations: reduced),
                  child: sliver
                      ? CustomScrollView(
                          slivers: [
                            TabContentTransition.sliver(
                              index: index,
                              child: SliverToBoxAdapter(child: body),
                            ),
                          ],
                        )
                      : TabContentTransition(index: index, child: body),
                ),
              ),
            ),
          );
        }

        await show(0);
        focus.requestFocus();
        await tester.pump();
        final editor = tester.state(find.byType(EditableText));
        double left(int index) => tester.getTopLeft(find.text('页面 $index')).dx;
        final resting = left(0);
        await show(1);
        expect(find.text('页面 0'), findsNothing);
        expect(left(1), closeTo(resting + 10, .01));
        await tester.pump(AppMotion.tabChange ~/ 2);
        expect(left(1), closeTo(resting + 5, .05));
        await show(0);
        expect(left(0), closeTo(resting - 10, .01));
        expect(tester.state(find.byType(EditableText)), same(editor));
        expect(focus.hasFocus, isTrue);
        expect(controller.text, '草稿');
        await tester.pump(AppMotion.tabChange);
        expect(left(0), resting);
        await show(1, reduced: true);
        expect(left(1), resting);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
