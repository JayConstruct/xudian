import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/script_transition.dart';
import 'package:task_app/core/ui/ui_component.dart';

void main() {
  for (final effect in ['fade', 'scale', 'slide']) {
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

  testWidgets('reduce motion skips animation and replay preserves input', (
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
              effect: 'scale',
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
