import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_catalog_page.dart';
import 'package:task_app/core/module_host/module_catalog_widgets.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/ui/ui_design.dart';
import 'package:task_app/data/app_database.dart';

import 'module_catalog_test.dart' show Fixture, makePackage;

Future<void> waitForCatalog(WidgetTester tester, Finder target) async {
  final watch = Stopwatch()..start();
  while (target.evaluate().isEmpty &&
      watch.elapsed < const Duration(seconds: 8)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(target, findsOneWidget);
}

Future<void> chooseCatalogFilter(
  WidgetTester tester,
  String id,
  String value,
) async {
  await tester.tap(find.byKey(ValueKey('catalog-filter-$id')));
  await tester.pumpAndSettle();
  final item = find.widgetWithText(PopupMenuItem<String>, value);
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '360x800 store starts with search and reachable cards; filters and clearing retain behavior',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late AppDatabase db;
      late CollectionStore store;
      late ModuleHost host;
      late Directory directory;
      late Fixture fixture;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('catalog-filter-');
        db = AppDatabase(NativeDatabase.memory());
        store = CollectionStore(db);
        host = ModuleHost(
          store: store,
          directory: Directory('${directory.path}/host'),
        );
        await host.initialize();
        fixture = Fixture(Directory('${directory.path}/cache'));
        final installed = await makePackage('test.module0');
        await host.install(installed);
        await fixture.add(installed);
        await fixture.add(await makePackage('test.module0', version: '2.0.0'));
        fixture.modules['test.module0']!['category'] = '学习';
        for (var i = 1; i < 6; i++) {
          await fixture.add(await makePackage('test.module$i'));
          fixture.modules['test.module$i']!['category'] = i.isOdd ? '学习' : '效率';
        }
        fixture.sync();
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.client.dispose();
        await tester.runAsync(() async {
          await host.close();
          await store.close();
          await db.close();
          await directory.delete(recursive: true);
        });
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            moduleCatalogClientProvider.overrideWith(
              (_) async => fixture.client,
            ),
          ],
          child: MaterialApp(
            theme: AppDesign.theme(Brightness.light),
            home: ModuleCatalogPage(host: host),
          ),
        ),
      );
      await waitForCatalog(tester, find.textContaining('已启用 · 可更新'));
      // One resolved card can arrive before the remaining index cache writes.
      // Let native I/O finish before settling the loading indicator's frames.
      final watch = Stopwatch()..start();
      while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty &&
          watch.elapsed < const Duration(seconds: 8)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      final search = tester.widget<TextField>(find.byType(TextField));
      expect(search.decoration?.border, isNull);
      expect(
        Theme.of(tester.element(find.byType(TextField)))
            .inputDecorationTheme
            .border,
        isA<ShapedInputBorder>(),
      );
      expect(find.text('发现适合你的模块'), findsNothing);
      final status = find.byKey(const ValueKey('catalog-filter-status'));
      final category = find.byKey(const ValueKey('catalog-filter-category'));
      expect(
        tester.getTopLeft(status).dy,
        closeTo(tester.getTopLeft(category).dy, 0.1),
      );
      expect(tester.getSize(status).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(category).height, greaterThanOrEqualTo(48));
      final cards = find.byType(ModuleCatalogCard);
      expect(tester.getTopLeft(cards.first).dy, lessThan(260));
      expect(find.text('test.module2').hitTestable(), findsOneWidget);
      expect(tester.getBottomRight(cards.at(2)).dy, lessThanOrEqualTo(800));
      await chooseCatalogFilter(tester, 'status', '可更新');
      expect(find.text('状态：可更新'), findsOneWidget);
      expect(find.byType(ModuleCatalogCard), findsOneWidget);
      expect(find.text('test.module0'), findsOneWidget);
      expect(find.text('更新').hitTestable(), findsOneWidget);
      await chooseCatalogFilter(tester, 'category', '效率');
      expect(find.text('分类：效率'), findsOneWidget);
      expect(find.byType(ModuleCatalogCard), findsNothing);
      expect(find.text('没有符合筛选条件的模块'), findsOneWidget);
      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();
      expect(find.text('状态：全部'), findsOneWidget);
      expect(find.text('分类：全部分类'), findsOneWidget);
      expect(find.text('找到 6 个模块 · 目录共 6 个'), findsOneWidget);
      expect(find.byType(ModuleCatalogCard).evaluate().length, lessThan(6));
      await chooseCatalogFilter(tester, 'category', '学习');
      expect(find.byType(ModuleCatalogCard), findsNWidgets(4));
      await chooseCatalogFilter(tester, 'status', '未安装');
      expect(find.byType(ModuleCatalogCard), findsNWidgets(3));
      expect(find.text('test.module0'), findsNothing);
      await tester.enterText(find.byType(TextField), 'absent');
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('找到 6 个模块 · 目录共 6 个'), findsOneWidget);
      expect(find.byType(ModuleCatalogCard).evaluate().length, lessThan(6));
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, scale) in [(320.0, 2.0), (1280.0, 1.0)]) {
    testWidgets(
      'long category stays readable and selectable at $width with scale $scale',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const long = '学习课程与校园生活综合辅助工具';
        var status = '全部';
        var category = '全部分类';
        await tester.pumpWidget(
          MaterialApp(
            theme: AppDesign.theme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ModuleCatalogFilters(
                      status: status,
                      category: category,
                      categories: const [long, '效率'],
                      onStatusChanged: (value) => update(() => status = value),
                      onCategoryChanged: (value) =>
                          update(() => category = value),
                    ),
                    const SizedBox(height: 12),
                    ModuleCatalogGrid(
                      children: [
                        for (var i = 0; i < 6; i++)
                          ModuleCatalogCard(
                            name: '课程 $i',
                            description: '导入课程并查看。',
                            status: '可安装',
                            version: '1.0.0',
                            action: '安装',
                            onAction: () {},
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await chooseCatalogFilter(tester, 'category', long);
        expect(find.text('分类：$long').hitTestable(), findsOneWidget);
        final statusControl = find.byKey(
          const ValueKey('catalog-filter-status'),
        );
        final categoryControl = find.byKey(
          const ValueKey('catalog-filter-category'),
        );
        if (width == 320) {
          expect(
            tester.getTopLeft(categoryControl).dy,
            greaterThan(tester.getTopLeft(statusControl).dy),
          );
        } else {
          expect(
            tester.getTopLeft(categoryControl).dy,
            closeTo(tester.getTopLeft(statusControl).dy, 0.1),
          );
          final cards = find.byType(ModuleCatalogCard);
          expect(
            tester.getTopLeft(cards.at(1)).dy,
            closeTo(tester.getTopLeft(cards.first).dy, 0.1),
          );
        }
        await chooseCatalogFilter(tester, 'status', '可更新');
        expect(find.text('状态：可更新').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('filter selectors are reachable with keyboard focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const TextField(),
              ModuleCatalogFilters(
                status: '全部',
                category: '全部分类',
                categories: const ['学习'],
                onStatusChanged: (_) {},
                onCategoryChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PopupMenuItem<String>, '可更新'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
