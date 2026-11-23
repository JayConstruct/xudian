import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:task_app/core/module_host/host_dialogs.dart';
import 'package:task_app/core/ui/ui_design.dart';

void main() {
  testWidgets('selection sheet retains its default until confirmed', (
    tester,
  ) async {
    final results = <Map<String, Object?>?>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        theme: AppDesign.theme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showModalBottomSheet<Map<String, Object?>>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const HostFormDialog(
                    title: '选择导入目标',
                    presentation: 'sheet',
                    fullWidthActions: true,
                    fields: [
                      {
                        'key': 'target',
                        'label': '',
                        'type': 'select',
                        'value': 'new',
                        'presentation': 'list',
                        'required': true,
                        'options': [
                          {
                            'value': 'new',
                            'label': '新建课表',
                            'icon': 'add',
                            'subtitle': '将采集结果导入新课表',
                          },
                          {
                            'value': 'existing',
                            'label': '秋季课表',
                            'icon': 'calendar',
                            'subtitle': '更新已有课表',
                          },
                        ],
                      },
                    ],
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    Future<void> tap(String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    ListTile target(String label) =>
        tester.widget(find.widgetWithText(ListTile, label));
    await tap('打开');
    expect(target('新建课表').selected, isTrue);
    expect(
      tester.getSize(find.byType(OutlinedButton)).width,
      tester.getSize(find.byType(FilledButton)).width,
    );
    await tap('秋季课表');
    expect(target('秋季课表').selected, isTrue);
    expect(results, isEmpty);
    await tap('取消');
    expect(results, [null]);
    await tap('打开');
    expect(target('新建课表').selected, isTrue);
    await tap('秋季课表');
    await tap('继续');
    expect(results.last, {'target': 'existing'});
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'paired form fields adapt to text scale $scale and return both values',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        Map<String, Object?>? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppDesign.theme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<Map<String, Object?>>(
                      context: context,
                      builder: (_) => const HostFormDialog(
                        title: '课表设置',
                        presentation: 'page',
                        fullWidthActions: true,
                        fields: [
                          {
                            'key': 'start',
                            'label': '开始节次',
                            'type': 'number',
                            'presentation': 'labeled',
                            'section': '本次安排',
                            'row': 'periods',
                            'value': '1',
                          },
                          {
                            'key': 'end',
                            'label': '结束节次',
                            'type': 'number',
                            'presentation': 'labeled',
                            'row': 'periods',
                            'value': '2',
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
        final fields = find.byType(TextField);
        final startY = tester.getTopLeft(fields.first).dy,
            endY = tester.getTopLeft(fields.last).dy;
        expect(endY, scale == 1.0 ? equals(startY) : greaterThan(startY));
        await tester.enterText(fields.last, '4');
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
        expect(result, {'start': 1, 'end': 4});
        expect(tester.takeException(), isNull);
      },
    );
  }

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
