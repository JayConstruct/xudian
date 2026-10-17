import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/workspace_header.dart';

void main() {
  test(
    'date titles format civil dates and show years outside the current year',
    () {
      final today = DateTime(2026, 10, 10);
      expect(formatWorkspaceDate('2026-10-10', today: today), '10月10日 周六');
      expect(formatWorkspaceDate('2027-01-01', today: today), '2027年1月1日 周五');
      for (final value in [
        null,
        '2026-02-30',
        '0000-01-01',
        '2026-10-10T00:00:00',
      ]) {
        expect(formatWorkspaceDate(value, today: today), isNull);
      }
    },
  );

  testWidgets(
    'date leases reject script headers, stale publishers and mode changes; identical dates do not notify twice',
    (tester) async {
      final controller = WorkspaceHeaderController();
      addTearDown(controller.dispose);
      final owner = Object();
      var active = true;
      final lease = controller.activate(
        identity: 'page:1',
        moduleId: 'test.date',
        pageId: 'test.date.home',
        enabled: true,
        mode: 'date',
        isActive: () => active,
      )!;
      controller.publish(lease, Object(), {
        'title': 'forged script header',
        'autoHideChrome': true,
      }, (_) async {});
      expect(controller.content, isNull);
      controller.publishDate(lease, owner, '2027-01-01');
      expect(controller.content!.spec, {
        'title': '2027年1月1日 周五',
        'selectedDate': '2027-01-01',
      });
      expect(controller.content!.spec['autoHideChrome'], isNull);
      var notifications = 0;
      controller.addListener(() => notifications++);
      await tester.pump();
      final before = notifications;
      controller.publishDate(lease, owner, '2027-01-01');
      await tester.pump();
      expect(notifications, before);
      active = false;
      controller.publishDate(lease, owner, '2027-01-02');
      expect(controller.content!.spec['title'], '2027年1月1日 周五');
      final contributed = controller.activate(
        identity: 'page:1',
        moduleId: 'test.date',
        pageId: 'test.date.home',
        enabled: true,
        mode: 'contributed',
        isActive: () => true,
      )!;
      expect(contributed, isNot(same(lease)));
      expect(controller.content, isNull);
      controller.publishDate(lease, owner, '2027-01-03');
      controller.publishDate(contributed, owner, '2027-01-03');
      expect(controller.content, isNull);
      controller.publish(contributed, owner, {
        'title': 'Normal script title',
      }, (_) async {});
      expect(controller.content!.spec['title'], 'Normal script title');
      await tester.pump();
    },
  );

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
        {'title': 'Title', 'compact': 'bad'},
        {
          'title': 'Title',
          'actions': [
            {
              'label': 'New',
              'event': <String, Object?>{},
              'presentation': 'unknown',
            },
          ],
        },
        {
          'title': 'Title',
          'actions': [
            {
              'label': 'New',
              'event': <String, Object?>{},
              'variant': 'unknown',
            },
          ],
        },
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
