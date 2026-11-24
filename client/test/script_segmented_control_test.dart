import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/script_form_controls.dart';

const labels = ['目录', '待推进', '跟进'];

Finder get indicator => find.descendant(
  of: find.byType(ScriptSegmentedControl),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).boxShadow != null,
  ),
);

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('slider and label highlights move together in $direction', (
      tester,
    ) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: direction,
              child: SizedBox(
                width: 367,
                child: ValueListenableBuilder(
                  valueListenable: selected,
                  builder: (context, index, _) => ScriptSegmentedControl(
                    labels: labels,
                    selectedIndex: index,
                    onSelected: (next) => selected.value = next,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final first = tester.getCenter(find.text(labels.first)).dx;
      final step = tester.getCenter(find.text(labels[1])).dx - first;
      final scheme = Theme.of(tester.element(indicator)).colorScheme;
      double checkHighlights() {
        final position = (tester.getCenter(indicator).dx - first) / step;
        for (var index = 0; index < labels.length; index++) {
          final style = DefaultTextStyle.of(
            tester.element(find.text(labels[index])),
          ).style;
          final coverage = (1 - (position - index).abs()).clamp(0.0, 1.0);
          final color = Color.lerp(
            scheme.onSurfaceVariant,
            scheme.primary,
            coverage,
          )!;
          expect(style.color!.toARGB32(), color.toARGB32());
          expect(style.fontWeight!.value, (400 + 200 * coverage).round());
        }
        return position;
      }

      expect(checkHighlights(), closeTo(0, .001));
      await tester.tap(find.text(labels.last));
      await tester.pump();
      expect(checkHighlights(), closeTo(0, .001));
      await tester.pump(const Duration(milliseconds: 90));
      final interrupted = checkHighlights();
      expect(interrupted, inExclusiveRange(0, 1));
      await tester.tap(find.text(labels.first));
      await tester.pump();
      expect(checkHighlights(), closeTo(interrupted, .001));
      await tester.pump(const Duration(milliseconds: 70));
      expect(checkHighlights(), inExclusiveRange(0, interrupted));
      await tester.pumpAndSettle();
      expect(checkHighlights(), closeTo(0, .001));
      for (var index = 1; index < labels.length; index++) {
        await tester.tap(find.text(labels[index]));
        await tester.pumpAndSettle();
        expect(checkHighlights(), closeTo(index, .001));
      }
    });
  }

  testWidgets(
    'reduced motion aligns immediately and wrapping uses a static selection',
    (tester) async {
      Future<void> show(int index, double width) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: SizedBox(
                width: width,
                child: ScriptSegmentedControl(
                  labels: labels,
                  selectedIndex: index,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      await show(0, 360);
      await show(2, 360);
      expect(
        tester.getCenter(indicator).dx,
        tester.getCenter(find.text(labels.last)).dx,
      );
      await show(1, 180);
      expect(indicator, findsNothing);
      final current = find.text(labels[1]);
      final scheme = Theme.of(tester.element(current)).colorScheme;
      expect(
        DefaultTextStyle.of(tester.element(current)).style.color,
        scheme.primary,
      );
      expect(
        tester.getTopLeft(find.text(labels.last)).dy,
        greaterThan(tester.getTopLeft(current).dy),
      );
    },
  );
}
