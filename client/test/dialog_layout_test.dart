import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/host_dialogs.dart';
import 'package:task_app/core/ui/ui_design.dart';

const contentKey = ValueKey('dialog-content');

Future<void> mountDialog(
  WidgetTester tester, {
  required Size size,
  required Widget dialog,
  double scale = 1,
  ValueNotifier<double>? keyboard,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppDesign.theme(brightness),
      builder: (context, child) => ValueListenableBuilder<double>(
        valueListenable: keyboard ?? const AlwaysStoppedAnimation(0),
        builder: (context, inset, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: inset),
          ),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => dialog),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

AlertDialog reviewContent() => AlertDialog(
  titlePadding: AppDesign.dialogTitlePadding,
  contentPadding: AppDesign.dialogContentPadding,
  actionsPadding: AppDesign.dialogActionsPadding,
  title: const Text('确认变更'),
  content: SizedBox(
    key: contentKey,
    width: 900,
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (var i = 0; i < 20; i++) Text('第 $i 条变更，说明内容和影响')],
      ),
    ),
  ),
  actions: [
    TextButton(onPressed: () {}, child: const Text('取消')),
    FilledButton(onPressed: () {}, child: const Text('确认')),
  ],
);

void main() {
  testWidgets('standard text uses wider content within narrow safe margins', (
    tester,
  ) async {
    await mountDialog(
      tester,
      size: const Size(320, 700),
      dialog: reviewContent(),
    );
    expect(tester.getSize(find.byKey(contentKey)).width, closeTo(248, 0.1));
    expect(tester.getTopLeft(find.byKey(contentKey)).dx, closeTo(36, 0.1));
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'narrow $brightness review gains width and keeps actions usable',
      (tester) async {
        await mountDialog(
          tester,
          size: const Size(320, 700),
          dialog: reviewContent(),
          scale: 2,
          brightness: brightness,
        );
        // Flutter reduces horizontal content padding at enlarged text scales.
        expect(
          tester.getSize(find.byKey(contentKey)).width,
          greaterThanOrEqualTo(248),
        );
        expect(
          tester.getSize(find.byKey(contentKey)).width,
          lessThanOrEqualTo(288),
        );
        expect(find.text('确认').hitTestable(), findsOneWidget);
        await tester.ensureVisible(find.text('第 19 条变更，说明内容和影响'));
        expect(find.text('第 19 条变更，说明内容和影响').hitTestable(), findsOneWidget);
        expect(find.text('确认').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('wide review respects maximum width', (tester) async {
    await mountDialog(
      tester,
      size: const Size(1440, 900),
      dialog: reviewContent(),
    );
    expect(tester.getSize(find.byKey(contentKey)).width, closeTo(720, 0.1));
    expect(tester.getTopLeft(find.byKey(contentKey)).dx, closeTo(360, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape review scrolls without hiding actions', (
    tester,
  ) async {
    await mountDialog(
      tester,
      size: const Size(640, 320),
      dialog: reviewContent(),
      scale: 1.5,
    );
    expect(find.text('确认').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.text('第 19 条变更，说明内容和影响'));
    expect(find.text('第 19 条变更，说明内容和影响').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard changes preserve form draft and reachable submit', (
    tester,
  ) async {
    final keyboard = ValueNotifier<double>(0);
    addTearDown(keyboard.dispose);
    await mountDialog(
      tester,
      size: const Size(360, 800),
      keyboard: keyboard,
      dialog: HostFormDialog(
        title: '编辑内容',
        fields: [
          for (var i = 0; i < 10; i++)
            {'key': 'field$i', 'label': '字段 $i', 'type': 'text', 'value': ''},
        ],
      ),
    );
    await tester.enterText(find.byType(TextField).first, '保留输入草稿');
    keyboard.value = 300;
    await tester.pumpAndSettle();
    final first = tester.widget<TextField>(find.byType(TextField).first);
    expect(first.controller!.text, '保留输入草稿');
    await tester.ensureVisible(find.byType(TextField).last);
    expect(find.byType(TextField).last.hitTestable(), findsOneWidget);
    expect(find.text('继续').hitTestable(), findsOneWidget);
    keyboard.value = 0;
    await tester.pumpAndSettle();
    expect(first.controller!.text, '保留输入草稿');
    expect(tester.takeException(), isNull);
  });

  testWidgets('short confirmations retain intrinsic width', (tester) async {
    await mountDialog(
      tester,
      size: const Size(1440, 900),
      dialog: AlertDialog(
        title: const Text('删除？'),
        content: const Text('确认后删除。'),
        actions: [TextButton(onPressed: () {}, child: const Text('取消'))],
      ),
    );
    final content = find.text('确认后删除。');
    final surface = find
        .ancestor(of: content, matching: find.byType(Material))
        .first;
    expect(tester.getSize(surface).width, lessThan(500));
    expect(find.text('取消').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
