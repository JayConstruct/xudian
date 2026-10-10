import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/workspace_header.dart';

void main() {
  testWidgets(
    'header leases reject late pages, old instances and stale menu actions',
    (tester) async {
      final controller = WorkspaceHeaderController();
      addTearDown(controller.dispose);
      var active = true;
      final first = controller.activate(
        identity: 'first:1',
        moduleId: 'private.first',
        pageId: 'private.first.home',
        enabled: true,
        isActive: () => active,
      )!;
      final owner = Object();
      var calls = 0;
      Future<void> dispatch(Object? event) async {
        calls++;
      }

      controller.publish(first, owner, {'title': 'First'}, dispatch);
      final oldAction = controller.content!.dispatch;
      await oldAction({'type': 'open'});
      expect(calls, 1);
      final second = controller.activate(
        identity: 'second:1',
        moduleId: 'private.second',
        pageId: 'private.second.home',
        enabled: true,
        isActive: () => true,
      )!;
      expect(controller.content, isNull);
      controller.publish(first, owner, {'title': 'Late'}, dispatch);
      expect(controller.content, isNull);
      await oldAction({'type': 'open'});
      expect(calls, 1);
      final otherOwner = Object();
      controller.publish(second, otherOwner, {'title': 'Second'}, dispatch);
      controller.clear(owner);
      expect(controller.content!.spec['title'], 'Second');
      final invalidated = controller.activate(
        identity: 'first:2',
        moduleId: 'private.first',
        pageId: 'private.first.home',
        enabled: true,
        isActive: () => active,
      )!;
      active = false;
      controller.publish(invalidated, owner, {'title': 'Inactive'}, dispatch);
      expect(controller.content, isNull);
      await tester.pump();
    },
  );

  testWidgets(
    'malformed module headers fail without losing the protected host layout',
    (tester) async {
      final controller = WorkspaceHeaderController();
      addTearDown(controller.dispose);
      final lease = controller.activate(
        identity: 'first:1',
        moduleId: 'private.first',
        pageId: 'private.first.home',
        enabled: true,
        isActive: () => true,
      )!;
      final owner = Object();
      Future<void> dispatch(Object? event) async {}
      for (final spec in <Map<String, Object?>>[
        {'title': 42},
        {'title': 'Title', 'leading': 'bad'},
        {'title': 'Title', 'backEvent': 'bad'},
        {
          'title': 'Title',
          'actions': [
            {'label': 'broken', 'event': 'bad'},
          ],
        },
      ]) {
        expect(
          () => controller.publish(lease, owner, spec, dispatch),
          throwsFormatException,
        );
        expect(controller.content, isNull);
      }
      controller.publish(lease, owner, {'title': 'Good'}, dispatch);
      controller.activate(
        identity: 'disabled',
        moduleId: '',
        pageId: '',
        enabled: false,
        isActive: () => false,
      );
      expect(controller.content, isNull);
      await tester.pump();
    },
  );
}
