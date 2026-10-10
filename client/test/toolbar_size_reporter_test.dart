import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/toolbar_size_reporter.dart';

void main() {
  testWidgets('reports actual chrome size once and follows layout changes', (
    tester,
  ) async {
    final reports = <Size>[];
    final height = ValueNotifier(64.0);
    addTearDown(height.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ValueListenableBuilder<double>(
            valueListenable: height,
            builder: (_, height, _) => ToolbarSizeReporter(
              onSizeChanged: reports.add,
              child: SizedBox(width: 320, height: height),
            ),
          ),
        ),
      ),
    );
    expect(reports, [const Size(320, 64)]);
    await tester.pump();
    expect(reports, hasLength(1));
    height.value = 148;
    await tester.pump();
    expect(reports, [const Size(320, 64), const Size(320, 148)]);
    await tester.pump();
    expect(reports, hasLength(2));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('does not schedule post-layout work without a subscriber', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: ToolbarSizeReporter(child: SizedBox(width: 100, height: 40)),
        ),
      ),
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
