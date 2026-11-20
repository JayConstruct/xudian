import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/features/settings/settings_widgets.dart';
import 'package:task_app/features/settings/ui_layout_picker.dart';

void main() {
  testWidgets('picker searches labels, target details and identifiers lazily', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showModalBottomSheet<int>(
                    isScrollControlled: true,
                    useSafeArea: true,
                    showDragHandle: true,
                    context: context,
                    builder: (_) => UiLayoutPicker<int>(
                      title: '选择兼容位置',
                      entrySearch: true,
                      choices: [
                        for (var index = 0; index < 250; index++)
                          UiLayoutChoice(
                            value: index,
                            label: '位置 $index',
                            detail: '宿主 / 槽位 $index',
                            keywords: 'module.entry.$index',
                          ),
                      ],
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('可选入口'), findsOneWidget);
    final sheetTitle = find.text('选择兼容位置');
    final openTop = tester.getTopLeft(sheetTitle).dy;
    expect(find.text('位置 249'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('layout-picker-search')),
      'module.entry.249',
    );
    await tester.pumpAndSettle();
    expect(find.text('位置 249'), findsOneWidget);
    expect(find.text('位置 0'), findsNothing);
    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.text('1 个入口'), findsOneWidget);
    final lastResult = find.widgetWithText(ListTile, '位置 249');
    final resultGroup = find.ancestor(
      of: lastResult,
      matching: find.byType(SettingsGroupSurface),
    );
    expect(
      tester.getBottomLeft(resultGroup).dy,
      closeTo(tester.getBottomLeft(lastResult).dy, 1),
    );
    final resultTop = tester.getTopLeft(sheetTitle).dy;
    expect(resultTop - openTop, closeTo(37, 1));
    await tester.enterText(
      find.byKey(const ValueKey('layout-picker-search')),
      '槽位 249',
    );
    await tester.pumpAndSettle();
    expect(find.text('位置 249'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('layout-picker-search')),
      '不存在',
    );
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的入口'), findsOneWidget);
    expect(tester.getTopLeft(sheetTitle).dy, closeTo(resultTop, 1));
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(find.text('可选入口'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('layout-picker-search')),
      '位置 249',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '位置 249'));
    await tester.pumpAndSettle();
    expect(selected, 249);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'picker can scroll and cancel at narrow width with keyboard insets',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          home: UiLayoutPicker<int>(
            title: '选择兼容位置',
            choices: [
              const UiLayoutChoice(
                value: 1,
                label: '名称很长的宿主页面与兼容槽位',
                detail: '仅展示兼容选项，选择前不会更改草稿',
              ),
              for (var index = 2; index <= 8; index++)
                UiLayoutChoice(value: index, label: '额外位置 $index'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.widgetWithText(ListTile, '额外位置 8'),
        60,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('额外位置 8').hitTestable(), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
