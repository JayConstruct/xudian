import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/workspace_interaction.dart';
import 'package:task_app/core/ui/ui_surfaces.dart';

void main() {
  test('workspace leases reject stale callbacks and independent owners release only their own drag', () {
    final controller = WorkspaceInteractionController();
    addTearDown(controller.dispose);
    var active = true;
    final first = controller.activate('planner:1', () => active);
    final a = Object(), b = Object();
    controller.setDragging(first, a, true);
    controller.setDragging(first, b, true);
    controller.releaseOwner(first, a);
    expect(controller.dragging, isTrue);
    active = false;
    controller.setDragging(first, b, false);
    expect(controller.dragging, isTrue);
    controller.releaseOwner(first, b);
    expect(controller.dragging, isFalse);
    final next = controller.activate('calendar:2', () => true);
    controller.setDragging(first, a, true);
    expect(controller.dragging, isFalse);
    controller.setDragging(next, b, true);
    controller.releaseOwner(first, b);
    expect(controller.dragging, isTrue);
    controller.activate('planner:3', () => true);
    expect(controller.dragging, isFalse);
  });

  testWidgets(
    'drag hides only dock paint input and semantics while preserving page viewport and inset',
    (tester) async {
      final controller = WorkspaceInteractionController();
      addTearDown(controller.dispose);
      final lease = controller.activate('planner:1', () => true);
      late ValueChanged<bool> signal;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: WorkspaceContentInsets(
                    bottom: 98,
                    child: WorkspaceInteractionScope(
                      controller: controller,
                      lease: lease,
                      child: WorkspaceDragRegion(
                        builder: (context, callback) {
                          signal = callback;
                          return Column(
                            children: [
                              const Text('保留顶部标题'),
                              Expanded(
                                child: Builder(
                                  builder: (context) => Text(
                                    '底部边距${WorkspaceContentInsets.bottomOf(context)}',
                                    key: const ValueKey('viewport'),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: WorkspaceInteractionDock(
                    controller: controller,
                    child: Semantics(
                      label: '底部导航语义',
                      child: SizedBox(
                        height: 72,
                        child: FilledButton(
                          onPressed: () => taps++,
                          child: const Text('底部导航'),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final before = tester.getRect(find.byKey(const ValueKey('viewport')));
      final buttonBefore = tester.getCenter(find.text('底部导航'));
      signal(true);
      await tester.pump();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('workspace-drag-dock-opacity')),
            )
            .opacity,
        0,
      );
      expect(find.text('保留顶部标题').hitTestable(), findsOneWidget);
      expect(find.text('底部边距98.0'), findsOneWidget);
      expect(tester.getRect(find.byKey(const ValueKey('viewport'))), before);
      final dock = find.byType(WorkspaceInteractionDock);
      expect(
        tester
            .widget<IgnorePointer>(
              find.descendant(of: dock, matching: find.byType(IgnorePointer)),
            )
            .ignoring,
        isTrue,
      );
      expect(
        tester
            .widget<ExcludeSemantics>(
              find
                  .descendant(of: dock, matching: find.byType(ExcludeSemantics))
                  .first,
            )
            .excluding,
        isTrue,
      );
      await tester.tapAt(buttonBefore);
      expect(taps, 0);
      await tester.pump(const Duration(milliseconds: 200));
      signal(false);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('workspace-drag-dock-opacity')),
            )
            .opacity,
        1,
      );
      expect(tester.getRect(find.byKey(const ValueKey('viewport'))), before);
      await tester.tap(find.text('底部导航'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'region disposal, retained-page inactivity and lease replacement restore dock without stale ownership',
    (tester) async {
      final controller = WorkspaceInteractionController();
      addTearDown(controller.dispose);
      var lease = controller.activate('planner:1', () => true);
      late ValueChanged<bool> callback;
      Future<void> mount({bool enabled = true, bool region = true}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: WorkspaceInteractionScope(
              controller: controller,
              lease: lease,
              child: TickerMode(
                enabled: enabled,
                child: region
                    ? WorkspaceDragRegion(
                        builder: (context, onChanged) {
                          callback = onChanged;
                          return const Text('任务');
                        },
                      )
                    : const Text('已离开'),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await mount();
      final stale = callback;
      callback(true);
      expect(controller.dragging, isTrue);
      await mount(enabled: false);
      expect(controller.dragging, isFalse);
      stale(true);
      expect(controller.dragging, isFalse);
      await mount();
      callback(true);
      expect(controller.dragging, isTrue);
      lease = controller.activate('calendar:2', () => true);
      await mount();
      expect(controller.dragging, isFalse);
      stale(true);
      expect(controller.dragging, isFalse);
      callback(true);
      expect(controller.dragging, isTrue);
      stale(false);
      expect(controller.dragging, isTrue);
      await mount(region: false);
      expect(controller.dragging, isFalse);
      callback(true);
      expect(controller.dragging, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
