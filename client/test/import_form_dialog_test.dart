import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:task_app/core/module_host/host_dialogs.dart';
import 'package:task_app/core/ui/ui_design.dart';

void main() {
  testWidgets('semester page selects any first-week day and returns Monday', (
    tester,
  ) async {
    Map<String, Object?>? result;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        theme: AppDesign.theme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<Map<String, Object?>>(
                  context: context,
                  builder: (_) => const HostFormDialog(
                    title: '确认学期配置',
                    presentation: 'page',
                    submitLabel: '查看实际变更',
                    description: '确认后预览课程变更',
                    fields: [
                      {
                        'key': 'firstMonday',
                        'label': '第一教学周',
                        'type': 'date',
                        'value': '2026-09-07',
                        'normalizeToMonday': true,
                        'editable': false,
                        'required': true,
                        'clearable': false,
                        'helperText': '选择第一周任意一天',
                      },
                      {
                        'key': 'scope',
                        'label': '来源标识（可选）',
                        'type': 'text',
                        'value': '',
                      },
                    ],
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    await tester.tap(find.byTooltip('选择第一教学周'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('2026-09-07'), findsOneWidget);
    await tester.tap(find.text('查看实际变更'));
    await tester.pumpAndSettle();
    expect(result?['firstMonday'], '2026-09-07');
    expect(result?['scope'], '');
    expect(tester.takeException(), isNull);
  });
}
