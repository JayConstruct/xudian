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

  test('nested action schema accepts controls and rejects unbounded or malformed nodes', () {
    const event = <String, Object?>{'type': 'change'};
    final actions = [
      {
        'label': '新建',
        'icon': 'add',
        'iconOnly': true,
        'overflowOnly': true,
        'event': event,
      },
      {
        'label': '视图',
        'children': [
          {
            'kind': 'choiceGrid',
            'label': '显示天数',
            'children': [
              {'label': '5天', 'event': event, 'selected': true},
            ],
          },
          {
            'kind': 'stepper',
            'label': '时间轴缩放',
            'valueLabel': '标准',
            'decreaseEvent': event,
            'increaseEvent': event,
          },
        ],
      },
    ];
    expect(validWorkspaceHeaderActions(actions), isTrue);
    expect(
      validWorkspaceHeaderActions([
        {'label': 'missing event'},
      ]),
      isFalse,
    );
    expect(
      validWorkspaceHeaderActions([
        {'label': 'bad', 'children': []},
      ]),
      isFalse,
    );
    expect(
      validWorkspaceHeaderActions([
        {'label': 'bad', 'kind': 'stepper', 'increaseEvent': event},
      ]),
      isFalse,
    );
    expect(
      validWorkspaceHeaderActions([
        {'label': 'bad', 'event': event, 'iconOnly': 'true'},
      ]),
      isFalse,
    );
    expect(
      validWorkspaceHeaderActions([
        {
          'label': 'bad',
          'presentation': 'inline',
          'children': [
            {'label': 'child', 'event': event},
          ],
        },
      ]),
      isFalse,
    );
    expect(
      validWorkspaceHeaderActions([
        {'label': 'bad', 'iconOnly': true, 'event': event},
      ]),
      isFalse,
    );
    expect(
      validWorkspaceHeaderActions([
        {
          'label': 'bad',
          'kind': 'choiceGrid',
          'children': [
            {
              'label': 'child',
              'children': [
                {'label': 'grandchild', 'event': event},
              ],
            },
          ],
        },
      ]),
      isFalse,
    );
    Object nested = {'label': 'leaf', 'event': event};
    for (var i = 0; i < 6; i++) {
      nested = {
        'label': 'nested',
        'children': [nested],
      };
    }
    expect(validWorkspaceHeaderActions([nested]), isFalse);
    expect(
      validWorkspaceHeaderActions(
        List.filled(13, {'label': 'leaf', 'event': event}),
      ),
      isFalse,
    );
  });

  testWidgets(
    'native menus track only the current active owner and release independent sessions',
    (tester) async {
      final controller = WorkspaceHeaderController();
      addTearDown(controller.dispose);
      final owner = Object();
      final otherOwner = Object();
      var active = true;
      final lease = controller.activate(
        identity: 'planner',
        moduleId: 'planner',
        pageId: 'home',
        enabled: true,
        isActive: () => active,
      )!;
      Future<void> dispatch(Object? event) async {}
      expect(controller.beginMenu(lease, owner), isNull);
      controller.publish(lease, owner, {'title': '规划'}, dispatch);
      expect(controller.beginMenu(lease, otherOwner), isNull);
      final first = controller.beginMenu(lease, owner);
      final second = controller.beginMenu(lease, owner);
      expect(first, isNotNull);
      expect(controller.isMenuOpenFor(lease, owner), isTrue);
      expect(controller.isMenuOpenFor(lease, otherOwner), isFalse);
      controller.endMenu(first);
      expect(controller.isMenuOpenFor(lease, owner), isTrue);
      active = false;
      expect(controller.isMenuOpenFor(lease, owner), isFalse);
      expect(controller.beginMenu(lease, owner), isNull);
      active = true;
      controller.endMenu(second);
      expect(controller.isMenuOpenFor(lease, owner), isFalse);
      controller.beginMenu(lease, owner);
      controller.publish(lease, owner, {'title': '更新规划'}, dispatch);
      expect(controller.isMenuOpenFor(lease, owner), isTrue);
      controller.publish(lease, otherOwner, {'title': '新实例'}, dispatch);
      expect(controller.isMenuOpenFor(lease, owner), isFalse);
      controller.publish(lease, owner, {'title': '规划'}, dispatch);
      expect(controller.isMenuOpenFor(lease, owner), isFalse);
      controller.beginMenu(lease, owner);
      controller.clear(owner);
      controller.publish(lease, owner, {'title': '规划'}, dispatch);
      expect(controller.isMenuOpenFor(lease, owner), isFalse);
      controller.beginMenu(lease, owner);
      controller.activate(
        identity: 'different',
        moduleId: 'other',
        pageId: 'home',
        enabled: true,
        isActive: () => true,
      );
      expect(controller.isMenuOpenFor(lease, owner), isFalse);
      expect(controller.beginMenu(lease, owner), isNull);
      await tester.pump();
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
