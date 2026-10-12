import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/page_first_frame.dart';

void main() {
  testWidgets(
    'nested native gates all become ready in the first painted frame',
    (tester) async {
      var reports = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PageFirstFrameScope(
            onReady: () => reports++,
            child: const PageFirstFrameGate(
              child: PageFirstFrameGate(
                child: PageFirstFrameGate(child: Text('nested native page')),
              ),
            ),
          ),
        ),
      );
      expect(
        reports,
        1,
        reason: 'Gate depth must not add a preparation frame per ancestor',
      );
      await tester.pump();
      expect(reports, 1);
    },
  );

  testWidgets('native pages report once after their first built frame', (
    tester,
  ) async {
    var reports = 0;
    Widget page() => MaterialApp(
      home: PageFirstFrameScope(
        onReady: () => reports++,
        child: const Text('native content'),
      ),
    );
    await tester.pumpWidget(page());
    expect(reports, 1);
    await tester.pumpWidget(page());
    expect(reports, 1);
  });

  testWidgets(
    'post-frame asynchronous results wait until their new content is painted',
    (tester) async {
      var reports = 0;
      var finished = false;
      var registered = false;
      final owner = Object();
      late StateSetter update;
      late PageFirstFrameReadiness readiness;
      // Register before the gates queue their own checks for this same frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        update(() => finished = true);
        readiness.complete(owner);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: PageFirstFrameScope(
            onReady: () => reports++,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                readiness = PageFirstFrameReadinessScope.read(context)!;
                if (!registered) {
                  registered = true;
                  readiness.begin(owner);
                }
                return Text(finished ? 'real content' : 'pending content');
              },
            ),
          ),
        ),
      );
      expect(reports, 0);
      expect(find.text('pending content'), findsOneWidget);
      await tester.pump();
      expect(reports, 1);
      expect(find.text('real content'), findsOneWidget);
    },
  );

  testWidgets(
    'initialization gates and all asynchronous owners must complete',
    (tester) async {
      var reports = 0;
      var blocked = true;
      late PageFirstFrameReadiness readiness;
      final owner = Object();
      var registered = false;
      Widget page() => MaterialApp(
        home: PageFirstFrameScope(
          onReady: () => reports++,
          child: PageFirstFrameGate(
            blocked: blocked,
            child: Builder(
              builder: (context) {
                readiness = PageFirstFrameReadinessScope.read(context)!;
                if (!registered) {
                  registered = true;
                  readiness.begin(owner);
                }
                return const Text('initialization');
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(page());
      readiness.complete(owner);
      await tester.pump();
      expect(reports, 0, reason: 'Initialization alone is not the final page');
      blocked = false;
      final sectionOwner = Object();
      readiness.begin(sectionOwner);
      await tester.pumpWidget(page());
      expect(reports, 0);
      readiness.complete(sectionOwner);
      await tester.pump();
      await tester.pump();
      expect(reports, 1);
      readiness.begin(Object());
      await tester.pump();
      expect(reports, 1, reason: 'Already visited pages stay ready');
    },
  );
}
