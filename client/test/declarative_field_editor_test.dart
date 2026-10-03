import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';
import 'package:task_app/features/declarative_runtime/declarative_field_editor.dart';

void main() {
  testWidgets('field editor renders controls by field type', (tester) async {
    final module = const DeclarativeModuleParser().parse({
      'formatVersion': 1,
      'manifest': {
        'id': 'app.fields.test',
        'version': '1.0.0',
        'coreApi': '1',
      },
      'fields': [
        {'id': 'flag', 'label': '开关', 'type': 'boolean'},
        {
          'id': 'level',
          'label': '等级',
          'type': 'select',
          'config': {'options': ['A', 'B']}
        },
        {
          'id': 'tags',
          'label': '标签',
          'type': 'multiSelect',
          'config': {'options': ['X', 'Y']}
        },
        {'id': 'day', 'label': '日期', 'type': 'date'},
        {'id': 'moment', 'label': '时间', 'type': 'datetime'},
        {'id': 'score', 'label': '分数', 'type': 'number'},
        {'id': 'note', 'label': '备注', 'type': 'text'},
      ],
    });
    Map<String, Object?>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showDeclarativeFieldEditor(
                  context: context,
                  module: module,
                  current: const {},
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

    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(2));
    expect(find.byTooltip('选择日期'), findsNWidgets(2));
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.tap(find.byType(SwitchListTile));
    await tester.enterText(find.widgetWithText(TextField, '分数'), '3.5');
    await tester.enterText(find.widgetWithText(TextField, '备注'), '复习');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result?['flag'], isTrue);
    expect(result?['score'], 3.5);
    expect(result?['note'], '复习');
  });
}
