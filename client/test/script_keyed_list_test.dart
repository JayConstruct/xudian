import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/script_keyed_list.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    List<String> ids, {
    String scope = 'today',
    Object? feedback,
    Set<String> remove = const {},
    Set<String> highlight = const {},
    bool reduced = false,
    ScrollController? scroll,
    Widget Function(String)? child,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: ScriptKeyedList(
            scope: scope,
            feedbackKey: feedback,
            removeKeys: remove,
            highlightKeys: highlight,
            scrollController: scroll,
            items: [
              for (final id in ids)
                ScriptListItem(
                  id: id,
                  builder: (_) =>
                      child?.call(id) ?? SizedBox(height: 80, child: Text(id)),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Finder row(String id, [String scope = 'today']) =>
      find.byKey(ValueKey((scope, id)));
  double opacity(WidgetTester tester, String id) => tester
      .widget<FadeTransition>(
        find.descendant(of: row(id), matching: find.byType(FadeTransition)),
      )
      .opacity
      .value;
  double tint(WidgetTester tester, String id) =>
      (tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: row(id),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration)
          .color!
          .a;

  testWidgets('reorders preserve input and fresh additions highlight once', (
    tester,
  ) async {
    Widget child(String id) => id == 'draft' ? const TextField() : Text(id);
    await show(tester, ['a', 'draft'], child: child);
    expect(opacity(tester, 'a'), 1);
    await tester.enterText(find.byType(TextField), 'keep selection');
    final original = tester.element(find.byType(TextField));
    await show(
      tester,
      ['new', 'draft', 'a'],
      feedback: 1,
      highlight: {'new'},
      child: child,
    );
    expect(tester.element(find.byType(TextField)), same(original));
    expect(opacity(tester, 'a'), 1);
    expect(opacity(tester, 'new'), 1);
    expect(tint(tester, 'new'), greaterThan(0));
    await tester.pump(const Duration(milliseconds: 300));
    final amount = tint(tester, 'new');
    await show(
      tester,
      ['new', 'draft', 'a'],
      feedback: 1,
      highlight: {'new'},
      child: child,
    );
    expect(tint(tester, 'new'), closeTo(amount, .001));
    await tester.pump(const Duration(milliseconds: 650));
    expect(tint(tester, 'new'), 0);
    await show(tester, ['draft', 'a'], child: child);
    await show(
      tester,
      ['new', 'draft', 'a'],
      feedback: 1,
      highlight: {'new'},
      child: child,
    );
    expect(
      tint(tester, 'new'),
      0,
      reason: 'Clearing feedback never rearms a consumed token',
    );
    expect(tester.element(find.byType(TextField)), same(original));
    expect(find.text('keep selection'), findsOneWidget);
  });

  testWidgets(
    'confirmed exits survive refresh and a second commit without replay',
    (tester) async {
      await show(tester, ['a', 'b', 'c']);
      await show(tester, ['b', 'c'], feedback: 1, remove: {'a'});
      expect(row('a'), findsOneWidget);
      expect(
        tester
            .widget<IgnorePointer>(
              find.descendant(
                of: row('a'),
                matching: find.byType(IgnorePointer),
              ),
            )
            .ignoring,
        true,
      );
      expect(
        tester
            .widget<ExcludeSemantics>(
              find.descendant(
                of: row('a'),
                matching: find.byType(ExcludeSemantics),
              ),
            )
            .excluding,
        true,
      );
      await tester.pump(const Duration(milliseconds: 80));
      final before = opacity(tester, 'a');
      expect(before, allOf(greaterThan(0), lessThan(1)));
      await show(tester, ['b', 'c'], feedback: 1, remove: {'a'});
      expect(opacity(tester, 'a'), closeTo(before, .001));
      await show(tester, ['c'], feedback: 2, remove: {'b'});
      expect(opacity(tester, 'a'), closeTo(before, .001));
      expect(row('b'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 141));
      expect(row('a'), findsNothing);
      expect(row('b'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 80));
      expect(row('b'), findsNothing);
      expect(opacity(tester, 'c'), 1);
    },
  );

  testWidgets(
    'ordinary removals, present completed rows and scope changes never exit',
    (tester) async {
      await show(tester, ['a', 'b']);
      await show(tester, ['b']);
      expect(row('a'), findsNothing);
      await show(tester, ['b'], feedback: 1, remove: {'b'});
      expect(
        opacity(tester, 'b'),
        1,
        reason: 'Historical completion can retain its row',
      );
      await show(tester, [], feedback: 1, remove: {'b'});
      expect(
        row('b'),
        findsNothing,
        reason: 'A consumed completion does not animate a later deletion',
      );
      await show(
        tester,
        ['a'],
        scope: 'tomorrow',
        feedback: 2,
        highlight: {'a'},
      );
      expect(
        tester
            .widget<FadeTransition>(
              find.descendant(
                of: row('a', 'tomorrow'),
                matching: find.byType(FadeTransition),
              ),
            )
            .opacity
            .value,
        1,
      );
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: row('a', 'tomorrow'),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.color!.a, 0);
    },
  );

  testWidgets('reduced motion finishes exits and suppresses highlight', (
    tester,
  ) async {
    await show(tester, ['a']);
    await show(tester, ['new'], feedback: 1, remove: {'a'}, highlight: {'new'});
    expect(row('a'), findsOneWidget);
    await show(
      tester,
      ['new'],
      feedback: 1,
      remove: {'a'},
      highlight: {'new'},
      reduced: true,
    );
    expect(row('a'), findsNothing);
    expect(tint(tester, 'new'), 0);
    await show(tester, [], feedback: 2, remove: {'new'}, reduced: true);
    expect(row('new'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lazy rows retain state after reorder and offscreen exits retire on time',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final ids = List.generate(100, (i) => 'row-$i');
      var builds = 0;
      Widget child(String id) {
        builds++;
        return SizedBox(
          height: 80,
          child: id == 'row-0' ? const TextField() : Text(id),
        );
      }

      await show(tester, ids, scroll: controller, child: child);
      expect(
        builds,
        lessThan(20),
        reason: 'Lazy mode builds only visible/cache rows',
      );
      await tester.enterText(find.byType(TextField), 'lazy draft');
      final original = tester.element(find.byType(TextField));
      await show(
        tester,
        ['inserted', ...ids.where((id) => id != 'row-99')],
        feedback: 1,
        remove: {'row-99'},
        scroll: controller,
        child: child,
      );
      expect(tester.element(find.byType(TextField)), same(original));
      final view = tester.widget<ListView>(find.byType(ListView));
      expect(view.childrenDelegate.estimatedChildCount, 101);
      await tester.pump(const Duration(milliseconds: 221));
      expect(
        tester
            .widget<ListView>(find.byType(ListView))
            .childrenDelegate
            .estimatedChildCount,
        100,
      );
      expect(find.text('lazy draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
