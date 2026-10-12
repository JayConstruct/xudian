import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/page_composition_readiness.dart';

void main() {
  testWidgets(
    'first sections appear together; refresh retains and disables them',
    (tester) async {
      final scopes = <String, PageCompositionReadinessScope>{};
      final owners = {'a': Object(), 'b': Object()};
      var taps = 0;
      Future<void> show(String identity) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageCompositionReadyGroup(
              identity: identity,
              memberIds: const ['a', 'b'],
              children: [
                for (final id in ['a', 'b'])
                  _AsyncMember(
                    id: id,
                    onMounted: (scope) {
                      scopes[id] = scope;
                      scope.begin(owners[id]!);
                    },
                    child: TextButton(
                      onPressed: () => taps++,
                      child: Text('section-$id'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await show('date-1');
      final controller = scopes['a']!.controller;
      expect(controller.hasDisplayed, false);
      scopes['a']!.complete(owners['a']!);
      await tester.pump();
      expect(controller.hasDisplayed, false);
      scopes['b']!.complete(owners['b']!);
      await tester.pump();
      await tester.pump();
      expect(controller.hasDisplayed, true);
      expect(controller.waiting, false);
      await tester.tap(find.text('section-a'));
      expect(taps, 1);
      final retained = tester.state(find.byType(_AsyncMember).first);
      final staleScope = scopes['a']!;
      scopes['a']!.allowContextChanges();
      await show('date-2');
      expect(controller.hasDisplayed, true);
      expect(controller.waiting, true);
      expect(tester.state(find.byType(_AsyncMember).first), same(retained));
      await tester.tap(find.text('section-a'));
      await tester.tap(find.text('section-b'), warnIfMissed: false);
      expect(
        taps,
        2,
        reason: 'Date controls stay usable while business content waits',
      );
      staleScope.complete(owners['a']!);
      await tester.pump();
      expect(controller.waiting, true);
      scopes['a']!.complete(owners['a']!);
      scopes['b']!.complete(
        owners['b']!,
      ); // Error renderers use the same completion.
      await tester.pump();
      await tester.pump();
      expect(controller.waiting, false);
      await tester.tap(find.text('section-a'));
      expect(taps, 3);
    },
  );

  testWidgets(
    'native sections need no renderer and become visible after a frame',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PageCompositionReadyGroup(
            identity: 'native',
            memberIds: ['native'],
            children: [Text('native-section')],
          ),
        ),
      );
      await tester.pump();
      final scope = tester.widget<PageCompositionReadinessScope>(
        find.byType(PageCompositionReadinessScope),
      );
      expect(scope.controller.waiting, false);
      expect(scope.controller.hasDisplayed, true);
      expect(tester.takeException(), isNull);
    },
  );
}

class _AsyncMember extends StatefulWidget {
  const _AsyncMember({
    required this.id,
    required this.onMounted,
    required this.child,
  });
  final String id;
  final void Function(PageCompositionReadinessScope) onMounted;
  final Widget child;
  @override
  State<_AsyncMember> createState() => _AsyncMemberState();
}

class _AsyncMemberState extends State<_AsyncMember> {
  int? generation;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context
        .dependOnInheritedWidgetOfExactType<PageCompositionReadinessScope>()!;
    if (generation != scope.generation) {
      generation = scope.generation;
      widget.onMounted(scope);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
