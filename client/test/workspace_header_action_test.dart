import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/ui_design.dart';
import 'package:task_app/core/ui/workspace_header_action.dart';

void main() {
  const actions = <Map<String, Object?>>[
    {'label': '操作历史', 'icon': 'history', 'presentation': 'inline'},
    {
      'label': '新建',
      'icon': 'add',
      'presentation': 'inline',
      'variant': 'filled',
    },
    {'label': '规划设置', 'presentation': 'menu'},
  ];

  testWidgets('icon-only new action uses a labelled 48dp filled button', (
    tester,
  ) async {
    const action = <String, Object?>{
      'label': '新建',
      'icon': 'add',
      'presentation': 'inline',
      'variant': 'filled',
      'iconOnly': true,
      'overflowOnly': true,
    };
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              expect(fittingHeaderActions(context, [action], 52), [action]);
              expect(fittingHeaderActions(context, [action], 48), isEmpty);
              return WorkspaceHeaderAction(
                action: action,
                onPressed: () => called = true,
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('新建'), findsNothing);
    final button = find.byTooltip('新建');
    expect(tester.getSize(button), const Size(48, 48));
    await tester.tap(button);
    expect(called, isTrue);
  });

  testWidgets('header keeps shortcuts callable and only uses measured space', (
    tester,
  ) async {
    var available = 180.0;
    var calls = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme(Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              final visible = fittingHeaderActions(context, actions, available);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in visible)
                    WorkspaceHeaderAction(
                      action: action,
                      onPressed: () => calls++,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    expect(find.byTooltip('操作历史'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
    expect(find.text('规划设置'), findsNothing);
    await tester.tap(find.text('新建'));
    expect(calls, 1);
    update(() => available = 105);
    await tester.pump();
    expect(find.text('新建'), findsOneWidget);
    expect(find.byTooltip('操作历史'), findsNothing);
    update(() => available = 40);
    await tester.pump();
    expect(find.text('新建'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
