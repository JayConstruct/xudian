import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/module_source_dialog.dart';
import 'package:task_app/core/ui/ui_design.dart';

Map<String, List<String>> documents({String? source}) => prepareModuleSource({
  'definition': {
    'manifest': {'id': 'app.source.sample', 'version': '1.0.0'},
  },
  'files': {
    'main.js': utf8.encode(
      source ?? 'export function ready() { return true; }',
    ),
    'other.js': utf8.encode('// 保留其他文件\r\n'),
    'module.json': utf8.encode('{}'),
    'package.json': utf8.encode('{}'),
  },
});

Widget sourceTestApp({
  required Widget home,
  Brightness brightness = Brightness.light,
}) => ProviderScope(
  child: MaterialApp(theme: AppDesign.theme(brightness), home: home),
);

Finder get editor => find.byKey(const ValueKey('module-source-editor'));

Future<void> selectFile(WidgetTester tester, String path) async {
  await tester.tap(find.byType(DropdownButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(path).last);
  await tester.pumpAndSettle();
}

Future<void> fileAction(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('文件操作'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> settleCompute(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  test('source preparation preserves huge lines, CRLF, UTF-8 and final newline semantics', () {
    for (final source in [
      '${'中😀\r\n' * 30000}最后一行',
      '${'x' * (moduleSourcePageLength - 1)}😀${'y' * 100000}',
      '${'export const escaped = "\\n"; ' * 12000}\n',
      '',
    ]) {
      final prepared = documents(source: source);
      final pages = prepared['main.js']!;
      expect(
        pages.every((page) => page.length <= moduleSourcePageLength),
        isTrue,
      );
      expect(pages.join(), source);
      // Each fragment also round-trips independently through UTF-8. A split
      // surrogate pair would be converted into replacement characters here.
      for (final page in pages) {
        expect(utf8.decode(utf8.encode(page)), page);
      }
      final result = assembleModuleSource(prepared);
      expect((result['files'] as Map)['main.js'], source);
      expect((result['files'] as Map)['other.js'], '// 保留其他文件\r\n');
      expect((result['files'] as Map).keys, ['main.js', 'other.js']);
      expect((result['definition'] as Map)['manifest'], {
        'id': 'app.source.sample',
        'version': '1.0.0',
      });
    }
  });

  testWidgets('opens while loading and does not reload on rebuild', (
    tester,
  ) async {
    final pending = Completer<Map<String, List<String>>>();
    var loads = 0;
    await tester.pumpWidget(
      sourceTestApp(
        home: ModuleSourceDialog(
          loadDocuments: () {
            loads++;
            return pending.future;
          },
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pump();
    expect(loads, 1);
    pending.complete(documents());
    await tester.pumpAndSettle();
    expect(editor, findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'edits across pages and files and preserves a large paste in review candidate',
    (tester) async {
      final source = 'const value = 1;\r\n' * 7000;
      final prepared = documents(source: source);
      final expectedPages = [...prepared['main.js']!];
      Map<String, Object?>? result;
      await tester.pumpWidget(
        sourceTestApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await showDialog<Map<String, Object?>>(
                      context: context,
                      builder: (_) => ModuleSourceDialog(
                        loadDocuments: () async => prepared,
                      ),
                    ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final definition = tester
          .widget<TextField>(editor)
          .controller!
          .text
          .replaceFirst('1.0.0', '1.0.1');
      await tester.enterText(editor, definition);
      await selectFile(tester, 'main.js');
      expect(
        tester.widget<TextField>(editor).controller!.text.length,
        lessThanOrEqualTo(moduleSourcePageLength),
      );
      expectedPages[0] = '/* 新增 */\r\n${expectedPages[0]}';
      await tester.enterText(editor, expectedPages[0]);
      await tester.tap(find.byTooltip('下一片段'));
      await tester.pumpAndSettle();
      expectedPages[1] = expectedPages[1].replaceFirst('1', '2');
      await tester.enterText(editor, expectedPages[1]);
      await selectFile(tester, 'other.js');
      final paste = '中😀\r\n' * 20000;
      await tester.enterText(editor, paste);
      expect(
        tester.widget<TextField>(editor).controller!.text.length,
        lessThanOrEqualTo(moduleSourcePageLength),
      );
      await tester.tap(find.text('继续审核'));
      await settleCompute(tester);
      expect(result, isNotNull);
      expect(
        ((result!['definition'] as Map)['manifest'] as Map)['version'],
        '1.0.1',
      );
      expect((result!['files'] as Map)['main.js'], expectedPages.join());
      expect((result!['files'] as Map)['other.js'], paste);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('whole-file search and copy include inactive pages', (
    tester,
  ) async {
    final source = '${'x' * (moduleSourcePageLength * 10)}find_me\r\n尾部';
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      sourceTestApp(
        home: ModuleSourceDialog(
          loadDocuments: () async => documents(source: source),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await selectFile(tester, 'main.js');
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == '在当前文件中查找',
    );
    await tester.enterText(search, 'find_me');
    await tester.tap(find.byTooltip('查找下一处'));
    await settleCompute(tester);
    expect(find.text('片段 11 / 11'), findsOneWidget);
    final controller = tester.widget<TextField>(editor).controller!;
    expect(controller.selection.textInside(controller.text), 'find_me');
    await fileAction(tester, '复制完整文件');
    await settleCompute(tester);
    expect(copied, source);
    expect(
      find.descendant(
        of: find.byType(ModuleSourceDialog),
        matching: find.text('已复制完整文件'),
      ),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'copy failure keeps source and offers retry with transient success',
    (tester) async {
      var failing = true;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            if (failing) throw PlatformException(code: 'clipboard-unavailable');
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        sourceTestApp(
          home: ModuleSourceDialog(loadDocuments: () async => documents()),
        ),
      );
      await tester.pumpAndSettle();
      await selectFile(tester, 'main.js');
      await fileAction(tester, '复制完整文件');
      await settleCompute(tester);
      expect(find.text('复制失败，请重试'), findsOneWidget);
      expect(find.text('已复制完整文件'), findsNothing);
      failing = false;
      await tester.ensureVisible(find.text('重试复制'));
      await tester.tap(find.text('重试复制'));
      await settleCompute(tester);
      expect(copied, 'export function ready() { return true; }');
      expect(find.text('复制失败，请重试'), findsNothing);
      expect(find.text('已复制完整文件'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'latest search wins and deleting then recreating a filename invalidates old results',
    (tester) async {
      final requests = <Completer<List<int>?>>[];
      await tester.pumpWidget(
        sourceTestApp(
          home: ModuleSourceDialog(
            loadDocuments: () async => documents(source: 'first second'),
            findSource: (_) {
              final request = Completer<List<int>?>();
              requests.add(request);
              return request.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await selectFile(tester, 'main.js');
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == '在当前文件中查找',
      );
      await tester.enterText(search, 's');
      final searchField = tester.widget<TextField>(search);
      searchField.onSubmitted!('s');
      searchField.onSubmitted!('s');
      requests[1].complete([0, 6, 7]);
      await tester.pumpAndSettle();
      requests[0].complete([0, 3, 4]);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(editor).controller!.selection.baseOffset,
        6,
      );
      searchField.onSubmitted!('s');
      await fileAction(tester, '删除文件');
      await fileAction(tester, '新增文件');
      final path = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == '文件路径，例如 utils.js',
      );
      await tester.enterText(path, 'main.js');
      await tester.tap(find.text('新增').last);
      await tester.pumpAndSettle();
      final recreatedSelection = tester
          .widget<TextField>(editor)
          .controller!
          .selection;
      requests[2].complete([0, 6, 7]);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(editor).controller!.text, '');
      expect(
        tester.widget<TextField>(editor).controller!.selection,
        recreatedSelection,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'adds and removes draft files and keeps malformed definitions open',
    (tester) async {
      await tester.pumpWidget(
        sourceTestApp(
          home: ModuleSourceDialog(loadDocuments: () async => documents()),
        ),
      );
      await tester.pumpAndSettle();
      await fileAction(tester, '新增文件');
      final path = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == '文件路径，例如 utils.js',
      );
      await tester.enterText(path, 'helpers/new.js');
      await tester.tap(find.text('新增').last);
      await tester.pumpAndSettle();
      expect(find.text('helpers/new.js'), findsOneWidget);
      await tester.enterText(editor, '// 草稿\n');
      await fileAction(tester, '删除文件');
      expect(find.text('helpers/new.js'), findsNothing);
      await tester.enterText(editor, '{ broken');
      await tester.tap(find.text('继续审核'));
      await settleCompute(tester);
      expect(find.textContaining('模块定义无法解析'), findsOneWidget);
      expect(find.byType(ModuleSourceDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'three-digit page controls fit 320px with 2x text and a megabyte definition',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final prepared = prepareModuleSource({
        'definition': {
          'padding': '${'x' * (moduleSourcePageLength * 127)}tail',
        },
        'files': <String, Object?>{},
      });
      expect(prepared['module.json']!.length, 128);
      await tester.pumpWidget(
        sourceTestApp(
          home: ModuleSourceDialog(loadDocuments: () async => prepared),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('片段 1 / 128'), findsOneWidget);
      final search = tester.widgetList<TextField>(find.byType(TextField)).first;
      search.controller!.text = 'tail';
      search.onSubmitted!('tail');
      await settleCompute(tester);
      expect(find.text('片段 128 / 128'), findsOneWidget);
      expect(
        tester.widget<TextField>(editor).controller!.text.length,
        lessThanOrEqualTo(moduleSourcePageLength),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final (size, brightness) in [
    (const Size(390, 844), Brightness.light),
    (const Size(320, 640), Brightness.dark),
    (const Size(844, 390), Brightness.light),
  ]) {
    testWidgets(
      'source controls fit ${size.width}px $brightness with large text and keyboard',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 180);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          sourceTestApp(
            brightness: brightness,
            home: ModuleSourceDialog(loadDocuments: () async => documents()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('继续审核'), findsOneWidget);
        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        expect(dialog.insetPadding, AppDesign.dialogInsets);
        expect(dialog.titlePadding, AppDesign.dialogTitlePadding);
        expect(dialog.contentPadding, AppDesign.dialogContentPadding);
        expect(dialog.actionsPadding, AppDesign.dialogActionsPadding);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
