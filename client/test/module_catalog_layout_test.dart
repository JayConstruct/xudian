import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/module_catalog_widgets.dart';
import 'package:task_app/core/ui/native_ui.dart';

Future<void> pumpStoreCards(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
  required List<Widget> cards,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ModuleCatalogGrid(children: cards),
        ),
      ),
    ),
  );
}

List<Widget> catalogCards() => [
  for (var i = 0; i < 6; i++)
    ModuleCatalogCard(
      key: ValueKey('module-$i'),
      name: '课程模块 $i',
      description: '按学校导入课程，并在课表中查看。',
      status: '可安装',
      version: '1.0.0',
      action: '安装',
      onDetails: () {},
      onAction: () {},
    ),
];

void main() {
  for (final (width, columns) in [(320.0, 1), (800.0, 2), (1280.0, 3)]) {
    testWidgets('store uses $columns columns at width $width', (tester) async {
      await pumpStoreCards(tester, width: width, cards: catalogCards());
      final first = find.byKey(const ValueKey('module-0'));
      final nextRow = find.byKey(ValueKey('module-$columns'));
      final firstOrigin = tester.getTopLeft(first);
      expect(tester.getTopLeft(nextRow).dx, closeTo(firstOrigin.dx, 0.1));
      expect(tester.getTopLeft(nextRow).dy, greaterThan(firstOrigin.dy));
      for (var i = 1; i < columns; i++) {
        final origin = tester.getTopLeft(find.byKey(ValueKey('module-$i')));
        expect(origin.dx, greaterThan(firstOrigin.dx));
        expect(origin.dy, closeTo(firstOrigin.dy, 0.1));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long names and purposes wrap with large text and narrow width', (
    tester,
  ) async {
    const name = '正方教务通用课程导入与校园课表同步模块';
    const purpose = '按学校导入课程，并把课程时间和教室同步到课表，供每天查看和安排任务。';
    var details = 0;
    var installs = 0;
    final semantics = tester.ensureSemantics();
    await pumpStoreCards(
      tester,
      width: 320,
      textScale: 2,
      cards: [
        ModuleCatalogCard(
          name: name,
          description: purpose,
          status: '可安装',
          version: '1.0.0',
          action: '安装',
          onDetails: () => details++,
          onAction: () => installs++,
        ),
      ],
    );
    expect(find.text(name).hitTestable(), findsOneWidget);
    expect(find.text(purpose).hitTestable(), findsOneWidget);
    expect(tester.widget<Text>(find.text(name)).maxLines, isNull);
    expect(tester.widget<Text>(find.text(purpose)).maxLines, isNull);
    expect(find.text('可安装 · 1.0.0').hitTestable(), findsOneWidget);
    expect(find.text('安装').hitTestable(), findsOneWidget);
    expect(find.text('查看详情'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('查看 $name 详情')), findsOneWidget);
      semantics.dispose();
    await tester.tap(find.text('安装'));
    expect(installs, 1);
    expect(details, 0);
    await tester.tap(find.text(name));
    expect(details, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large text reduces desktop columns rather than squeezing cards',
    (tester) async {
      await pumpStoreCards(
        tester,
        width: 800,
        textScale: 2,
        cards: catalogCards(),
      );
      final first = tester.getTopLeft(find.byKey(const ValueKey('module-0')));
      final second = tester.getTopLeft(find.byKey(const ValueKey('module-1')));
      expect(second.dx, closeTo(first.dx, 0.1));
      expect(second.dy, greaterThan(first.dy));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'update keeps installed status and the persistent open action distinct',
    (tester) async {
      var updates = 0;
      var opens = 0;
      await pumpStoreCards(
        tester,
        width: 320,
        cards: [
          ModuleCatalogCard(
            name: '课程导入',
            description: '按学校导入课程。',
            status: '已启用 · 可更新',
            version: '1.0.0 → 2.0.0',
            action: '更新',
            onAction: () => updates++,
            secondaryActions: [
              NativeUi(
                child: TextButton(
                  onPressed: () => opens++,
                  child: const Text('打开模块'),
                ),
              ),
            ],
          ),
        ],
      );
      expect(find.textContaining('已启用 · 可更新'), findsOneWidget);
      expect(find.textContaining('可安装'), findsNothing);
      expect(find.text('更新'), findsOneWidget);
      expect(find.text('打开模块'), findsOneWidget);
      await tester.tap(find.text('打开模块'));
      await tester.tap(find.text('更新'));
      expect(opens, 1);
      expect(updates, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable releases keep a readable reason and disabled install',
    (tester) async {
      await pumpStoreCards(
        tester,
        width: 320,
        cards: [
          ModuleCatalogCard(
            name: '课程导入',
            description: '按学校导入课程。',
            status: '版本索引不可用',
            version: '版本待加载',
            action: '安装',
            unavailableHint: '请刷新重试，或在商店设置中检查目录仓库。',
            onDetails: () {},
          ),
        ],
      );
      expect(find.textContaining('版本索引不可用'), findsOneWidget);
      expect(find.textContaining('请刷新重试'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
