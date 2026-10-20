import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/script_transition.dart';
import 'package:task_app/core/ui/ui_component.dart';

void main() {
  testWidgets('page navigation pushes the destination and pops the source', (
    tester,
  ) async {
    final page = ValueNotifier((
      name: 'home',
      direction: 'forward',
      revision: 0,
    ));
    addTearDown(page.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: page,
            builder: (_, value, _) => ScriptTransition(
              effect: 'page',
              navigationDirection: value.direction,
              replayKey: value.name,
              child: SizedBox(
                height: 200,
                child: Text('${value.name} ${value.revision}'),
              ),
            ),
          ),
        ),
      ),
    );
    page.value = (name: 'detail', direction: 'forward', revision: 0);
    await tester.pump();
    Finder fadeFor(String text) => find
        .ancestor(of: find.text(text), matching: find.byType(FadeTransition))
        .first;
    expect(tester.widget<FadeTransition>(fadeFor('detail 0')).opacity.value, 0);
    expect(find.text('home 0'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('home 0'), findsNothing);
    page.value = (name: 'home', direction: 'back', revision: 0);
    await tester.pump();
    expect(find.text('home 0'), findsOneWidget);
    final outgoing = fadeFor('detail 0');
    expect(tester.widget<FadeTransition>(outgoing).opacity.value, 1);
    expect(
      find
          .descendant(
            of: find.byType(ScriptTransition),
            matching: find.byType(FadeTransition),
          )
          .evaluate()
          .where(
            (element) => find
                .descendant(
                  of: find.byWidget(element.widget),
                  matching: find.text('home 0'),
                )
                .evaluate()
                .isNotEmpty,
          ),
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      tester.widget<FadeTransition>(outgoing).opacity.value,
      inExclusiveRange(0, 1),
    );
    await tester.pumpAndSettle();
    expect(find.text('detail 0'), findsNothing);
    page.value = (name: 'home', direction: 'back', revision: 1);
    await tester.pump();
    expect(find.text('home 1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ScriptTransition),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rapid page direction changes keep one outgoing view and exclude its interaction',
    (tester) async {
      final page = ValueNotifier((name: 'home', direction: 'forward'));
      addTearDown(page.dispose);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: page,
              builder: (_, value, _) => ScriptTransition(
                effect: 'page',
                navigationDirection: value.direction,
                replayKey: value.name,
                child: SizedBox(
                  height: 200,
                  child: TextButton(
                    onPressed: () => taps++,
                    child: Text(value.name),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      page.value = (name: 'detail', direction: 'forward');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      page.value = (name: 'about', direction: 'forward');
      await tester.pump();
      expect(find.text('home'), findsNothing);
      expect(find.text('detail'), findsOneWidget);
      expect(find.text('about'), findsOneWidget);
      final hidden = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.text('detail'),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(hidden.ignoring, isTrue);
      page.value = (name: 'detail', direction: 'back');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('about'), findsNothing);
      await tester.tap(find.text('detail'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced page navigation swaps immediately without retaining the source',
    (tester) async {
      final page = ValueNotifier((name: 'home', direction: 'forward'));
      addTearDown(page.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: page,
              builder: (context, value, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: ScriptTransition(
                  effect: 'page',
                  navigationDirection: value.direction,
                  replayKey: value.name,
                  child: Text(value.name),
                ),
              ),
            ),
          ),
        ),
      );
      for (final direction in ['forward', 'back']) {
        page.value = (name: direction, direction: direction);
        await tester.pump();
        expect(find.text(direction), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ScriptTransition),
            matching: find.byType(FadeTransition),
          ),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final effect in ['fade', 'scale', 'slide', 'page']) {
    testWidgets('$effect transition animates, replays and hides interaction', (
      tester,
    ) async {
      final options = ValueNotifier((visible: true, replay: 0));
      addTearDown(options.dispose);
      var clicks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: options,
              builder: (_, value, _) => ScriptTransition(
                effect: effect,
                visible: value.visible,
                replayKey: value.replay,
                duration: const Duration(milliseconds: 400),
                child: TextButton(
                  onPressed: () => clicks++,
                  child: const Text('animated action'),
                ),
              ),
            ),
          ),
        ),
      );
      final transition = find.descendant(
        of: find.byType(ScriptTransition),
        matching: find.byType(FadeTransition),
      );
      double opacity() =>
          tester.widget<FadeTransition>(transition).opacity.value;
      expect(opacity(), 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(), greaterThan(0));
      expect(opacity(), lessThan(1));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      await tester.tap(find.text('animated action'));
      expect(clicks, 1);
      options.value = (visible: true, replay: 1);
      await tester.pump();
      expect(opacity(), 0);
      await tester.pumpAndSettle();
      options.value = (visible: false, replay: 1);
      await tester.pumpAndSettle();
      expect(opacity(), 0);
      final ignore = tester.widget<IgnorePointer>(
        find.descendant(
          of: find.byType(ScriptTransition),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignore.ignoring, isTrue);
      expect(
        tester
            .widget<ExcludeSemantics>(find.byType(ExcludeSemantics).last)
            .excluding,
        isTrue,
      );
      options.value = (visible: true, replay: 1);
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('page entrance matches app motion and replay preserves input', (
    tester,
  ) async {
    final replay = ValueNotifier(0);
    addTearDown(replay.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: replay,
            builder: (_, value, _) => ScriptTransition(
              effect: 'page',
              replayKey: value,
              child: const TextField(),
            ),
          ),
        ),
      ),
    );
    final transition = find.byType(ScriptTransition);
    final fade = find.descendant(
      of: transition,
      matching: find.byType(FadeTransition),
    );
    final slide = find.descendant(
      of: transition,
      matching: find.byType(SlideTransition),
    );
    double opacity() => tester.widget<FadeTransition>(fade).opacity.value;
    Offset position() => tester.widget<SlideTransition>(slide).position.value;
    expect(
      tester.widget<ScriptTransition>(transition).duration,
      const Duration(milliseconds: 300),
    );
    expect(opacity(), 0);
    expect(position(), const Offset(.04, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(opacity(), closeTo(Curves.easeOutCubic.transform(.5), .0001));
    expect(position().dx, greaterThan(0));
    expect(position().dx, lessThan(.04));
    expect(position().dy, 0);
    await tester.pump(const Duration(milliseconds: 149));
    expect(opacity(), lessThan(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(opacity(), 1);
    expect(position(), Offset.zero);

    await tester.enterText(find.byType(TextField), '保留页面草稿');
    final original = tester.state(find.byType(TextField));
    replay.value++;
    await tester.pump();
    expect(opacity(), 0);
    expect(position(), const Offset(.04, 0));
    expect(tester.state(find.byType(TextField)), same(original));
    expect(find.text('保留页面草稿'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing effect replays while preserving child input state', (
    tester,
  ) async {
    final effect = ValueNotifier('fade');
    addTearDown(effect.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: effect,
            builder: (_, value, _) =>
                ScriptTransition(effect: value, child: const TextField()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'keep draft');
    final original = tester.state(find.byType(TextField));
    effect.value = 'scale';
    await tester.pump();
    final fade = find.descendant(
      of: find.byType(ScriptTransition),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(fade).opacity.value, 0);
    expect(identical(tester.state(find.byType(TextField)), original), isTrue);
    expect(find.text('keep draft'), findsOneWidget);
    await tester.pumpAndSettle();
    effect.value = 'slide';
    await tester.pump();
    expect(tester.widget<FadeTransition>(fade).opacity.value, 0);
    expect(identical(tester.state(find.byType(TextField)), original), isTrue);
    await tester.pumpAndSettle();
  });

  for (final effect in ['fade', 'scale', 'slide', 'page']) {
    testWidgets('$effect reduced motion skips animation and preserves input', (
      tester,
    ) async {
      final replay = ValueNotifier(0);
      addTearDown(replay.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: replay,
              builder: (_, value, _) => ScriptTransition(
                effect: effect,
                replayKey: value,
                child: const TextField(key: ValueKey('draft')),
              ),
            ),
          ),
        ),
      );
      final fade = find.descendant(
        of: find.byType(ScriptTransition),
        matching: find.byType(FadeTransition),
      );
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      await tester.enterText(find.byType(TextField), '保留草稿');
      replay.value++;
      await tester.pump();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      expect(find.text('保留草稿'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'collapse keeps draft and element, clears hidden focus and reverses in place',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: visible,
              builder: (_, value, _) => ScriptTransition(
                collapse: true,
                visible: value,
                child: TextField(controller: controller, focusNode: focus),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '保持草稿');
      controller.value = const TextEditingValue(
        text: '保持草稿',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
        composing: TextRange(start: 1, end: 3),
      );
      final value = controller.value;
      final original = tester.element(find.byType(TextField));
      expect(focus.hasFocus, true);
      visible.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(focus.hasFocus, false);
      final partial = tester.getSize(find.byType(ScriptTransition)).height;
      visible.value = true;
      await tester.pump();
      expect(
        tester.getSize(find.byType(ScriptTransition)).height,
        closeTo(partial, .1),
      );
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(TextField)), same(original));
      expect(controller.value.text, value.text);
      expect(controller.value.selection, value.selection);
      expect(
        focus.hasFocus,
        false,
        reason: 'Reopening does not reopen the keyboard',
      );
      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.getSize(find.byType(ScriptTransition)).height, 0);
      visible.value = true;
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(TextField)), same(original));
      expect(controller.text, '保持草稿');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'collapse under reduced motion settles immediately without refresh replay',
    (tester) async {
      final options = ValueNotifier((
        visible: true,
        reduced: true,
        revision: 0,
      ));
      addTearDown(options.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: options,
              builder: (context, value, _) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: value.reduced),
                child: ScriptTransition(
                  collapse: true,
                  visible: value.visible,
                  child: Text('revision ${value.revision}'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('revision 0'), findsOneWidget);
      options.value = (visible: false, reduced: true, revision: 1);
      await tester.pump();
      expect(find.text('revision 1'), findsNothing);
      expect(tester.getSize(find.byType(ScriptTransition)).height, 0);
      options.value = (visible: true, reduced: true, revision: 2);
      await tester.pump();
      expect(find.text('revision 2'), findsOneWidget);
      options.value = (visible: true, reduced: false, revision: 3);
      await tester.pump();
      final fade = find.descendant(
        of: find.byType(ScriptTransition),
        matching: find.byType(FadeTransition),
      );
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('public button variants keep their appearance and press event', (
    tester,
  ) async {
    var clicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final variant in ['tonal', 'filled', 'outlined', 'text'])
                defaultUiComponent(
                  'ui.button@1',
                  {'label': variant, 'variant': variant},
                  {},
                  {'press': (_) => clicks++},
                ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(FilledButton), findsNWidgets(2));
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
    for (final variant in ['tonal', 'filled', 'outlined', 'text']) {
      await tester.tap(find.text(variant));
    }
    expect(clicks, 4);
  });
}
