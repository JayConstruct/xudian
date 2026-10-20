import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/workspace_toolbar_transition.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'toolbar has an independent reversible timeline reduced=$reduced',
      (tester) async {
        final visible = ValueNotifier(true);
        addTearDown(visible.dispose);
        var presence = 1.0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: ValueListenableBuilder(
              valueListenable: visible,
              builder: (context, value, _) => WorkspaceToolbarTransition(
                visible: value,
                builder: (context, value) {
                  presence = value;
                  return const Text('toolbar');
                },
              ),
            ),
          ),
        );
        expect(presence, 1);
        visible.value = false;
        await tester.pump();
        if (reduced) {
          expect(presence, 0);
        } else {
          expect(presence, 1);
          await tester.pump(const Duration(milliseconds: 100));
          expect(presence, greaterThan(0));
          expect(presence, lessThan(1));
          final partial = presence;
          // A new target reverses the running timeline rather than restarting it.
          visible.value = true;
          await tester.pump();
          expect(presence, closeTo(partial, .001));
          await tester.pumpAndSettle();
          expect(presence, 1);
          visible.value = false;
          await tester.pumpAndSettle();
          expect(presence, 0);
        }
        visible.value = true;
        await tester.pumpAndSettle();
        expect(presence, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
