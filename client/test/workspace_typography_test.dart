import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/ui/workspace_typography.dart';
import 'package:task_app/data/app_database.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  test('workspace title tokens retain theme font and foreground', () {
    const base = TextStyle(
      fontFamily: 'Custom',
      color: Colors.green,
      fontSize: 40,
      fontWeight: FontWeight.w300,
    );
    final style = WorkspaceTypography.titleStyle(
      const TextTheme(headlineSmall: base),
    );
    expect(style.fontSize, 24);
    expect(style.fontWeight, FontWeight.w700);
    expect(style.height, 1.15);
    expect(style.letterSpacing, -.6);
    expect(style.fontFamily, 'Custom');
    expect(style.color, Colors.green);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'script toolbar shares typography and keeps week actions at $scale',
      (tester) async {
        late AppDatabase db;
        late CollectionStore store;
        late Directory directory;
        late ModuleHost host;
        await tester.runAsync(() async {
          db = AppDatabase(NativeDatabase.memory());
          store = CollectionStore(db);
          directory = await Directory.systemTemp.createTemp('workspace-title-');
          host = ModuleHost(store: store, directory: directory);
        });
        addTearDown(() async {
          await host.close();
          await store.close();
          await db.close();
          await directory.delete(recursive: true);
        });
        await tester.runAsync(() async {
          await host.initialize();
          await host.install(
            await ScriptPackage.verify(
              await ScriptPackage.build(
                {
                  'formatVersion': 3,
                  'manifest': {
                    'id': 'test.toolbar',
                    'version': '1.0.0',
                    'hostApi': '^1.0.0',
                    'dataVersion': 1,
                  },
                  'entryPoint': 'main.js',
                  'collections': [],
                  'services': [],
                  'pages': [],
                },
                {
                  'main.js': '''
export function render({state = {}, event}) {
  const week = event?.type === 'next' ? 2 : state.week || 1;
  return {state: {week}, tree: {
    type: 'toolbar', title: `第 \${week} 周 · 跨学期课程安排`,
    event: {type: 'next'},
    leading: {label: '上一周', icon: 'chevron_left', event: {type: 'previous'}},
    actions: [{label: '下一周', icon: 'chevron_right', event: {type: 'next'}}]
  }};
}
''',
                },
              ),
              allowUnsignedLocal: true,
            ),
          );
        });
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              textTheme: const TextTheme(
                headlineSmall: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: ScriptPage(
                host: host,
                moduleId: 'test.toolbar',
                handler: 'render',
              ),
            ),
          ),
        );
        await settle(tester);
        final title = find.text('第 1 周 · 跨学期课程安排');
        expect(title, findsOneWidget);
        expect(
          tester.widget<Text>(title).style,
          WorkspaceTypography.titleStyle(
            Theme.of(tester.element(title)).textTheme,
          ),
        );
        expect(tester.widget<Text>(title).textAlign, TextAlign.center);
        expect(tester.widget<Text>(title).maxLines, 3);
        expect(
          MediaQuery.textScalerOf(tester.element(title)).scale(24),
          24 * scale,
        );
        final actionBounds = tester.getRect(find.byTooltip('下一周'));
        final titleBounds = tester.getRect(title);
        expect(titleBounds.right, lessThanOrEqualTo(actionBounds.left));
        await tester.tap(find.byTooltip('下一周'));
        await settle(tester);
        expect(find.text('第 2 周 · 跨学期课程安排'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
