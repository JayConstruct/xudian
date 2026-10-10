import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
                  selected = await showDialog<int>(
                    context: context,
                    builder: (_) => UiLayoutPicker<int>(
                      title: '选择兼容位置',
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
    expect(find.text('位置 249'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('layout-picker-search')),
      'module.entry.249',
    );
    await tester.pumpAndSettle();
    expect(find.text('位置 249'), findsOneWidget);
    expect(find.text('位置 0'), findsNothing);
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
    expect(find.text('没有符合条件的兼容选项'), findsOneWidget);
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

  testWidgets('picker supports narrow large text and cancellation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      const MaterialApp(
        home: UiLayoutPicker<int>(
          title: '选择兼容位置',
          choices: [
            UiLayoutChoice(
              value: 1,
              label: '名称很长的宿主页面与兼容槽位',
              detail: '仅展示兼容选项，选择前不会更改草稿',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
