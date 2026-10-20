import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_catalog/module_catalog.dart';
import 'package:task_app/core/module_host/module_catalog_page.dart';
import 'package:task_app/core/module_host/module_package.dart';

import 'module_catalog_test.dart' show Fixture, makePackage;

Future<void> waitForDownloadUi(WidgetTester tester, Finder target) async {
  final elapsed = Stopwatch()..start();
  while (target.evaluate().isEmpty &&
      elapsed.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(target, findsOneWidget);
}

Future<void> openDownloadDialog(
  WidgetTester tester, {
  required ModuleCatalogClient client,
  required List<ResolvedCatalogModule> modules,
  required Completer<List<ScriptPackage>?> result,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result.complete(
                await showDialog<List<ScriptPackage>>(
                  context: context,
                  builder: (_) =>
                      ModuleDownloadDialog(client: client, modules: modules),
                ),
              );
            },
            child: const Text('开始下载'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('开始下载'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets('automatic retry shows waiting state and remains cancellable', (
    tester,
  ) async {
    late Directory directory;
    late Fixture fixture;
    late ModuleCatalogClient client;
    late List<ResolvedCatalogModule> modules;
    var attempts = 0;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('download-dns-retry-');
      fixture = Fixture(directory);
      await fixture.add(await makePackage('test.dns'));
      modules = (await ModuleDependencyResolver(
        fixture.client,
      ).resolve(requests: {'test.dns': 'any'}, installed: {})).ordered;
      client = ModuleCatalogClient(
        cacheDirectory: directory,
        transport:
            (url, {cancellation, onProgress, required maximumBytes}) async {
              attempts++;
              throw const SocketException("Failed host lookup: 'github.com'");
            },
      );
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      client.dispose();
      fixture.client.dispose();
      await tester.runAsync(() => directory.delete(recursive: true));
    });
    final result = Completer<List<ScriptPackage>?>();
    await openDownloadDialog(
      tester,
      client: client,
      modules: modules,
      result: result,
    );
    await waitForDownloadUi(tester, find.text('网络连接失败，正在等待自动重试…'));
    expect(find.text('重试'), findsNothing);
    await tester.tap(find.text('取消下载'));
    await tester.pumpAndSettle();
    expect(await result.future, isNull);
    expect(attempts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'download progress stays visible above collapsed details on narrow large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory directory;
      late Fixture fixture;
      late ModuleCatalogClient client;
      late List<ResolvedCatalogModule> modules;
      final transfer = Completer<List<int>>();
      void Function(int, int)? progress;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('download-feedback-');
        fixture = Fixture(directory);
        await fixture.add(await makePackage('test.first'));
        await fixture.add(await makePackage('test.second'));
        modules = (await ModuleDependencyResolver(fixture.client).resolve(
          requests: {'test.first': 'any', 'test.second': 'any'},
          installed: {},
        )).ordered;
        client = ModuleCatalogClient(
          cacheDirectory: directory,
          networkRetries: 0,
          transport: (url, {cancellation, onProgress, required maximumBytes}) {
            progress = onProgress;
            return transfer.future;
          },
        );
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (!transfer.isCompleted) transfer.complete([]);
        client.dispose();
        fixture.client.dispose();
        await tester.runAsync(() => directory.delete(recursive: true));
      });
      final result = Completer<List<ScriptPackage>?>();
      await openDownloadDialog(
        tester,
        client: client,
        modules: modules,
        result: result,
        textScale: 2,
      );
      await waitForDownloadUi(tester, find.text('下载中'));
      final size = modules.first.release!.size;
      progress!(size ~/ 2, size);
      await tester.pump();
      expect(find.textContaining('已完成 0/2').hitTestable(), findsOneWidget);
      expect(
        find.textContaining(modules.first.name).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('下载中').hitTestable(), findsOneWidget);
      expect(find.textContaining('整体下载进度').hitTestable(), findsOneWidget);
      final indicators = tester.widgetList<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator).hitTestable(),
      );
      expect(indicators, isNotEmpty);
      expect(
        indicators.any(
          (indicator) =>
              indicator.value != null &&
              indicator.value! > 0 &&
              indicator.value! < 1,
        ),
        isTrue,
      );
      final overallSize = modules.fold<int>(
        0,
        (sum, module) => sum + module.release!.size,
      );
      expect(
        indicators.any(
          (indicator) =>
              indicator.value != null &&
              (indicator.value! - (size ~/ 2) / overallSize).abs() < 0.00001,
        ),
        isTrue,
      );
      expect(
        find.textContaining(RegExp(r'^\d+(\.\d+)? (B|KB|MB) / ')).hitTestable(),
        findsOneWidget,
      );
      expect(find.textContaining('https://github.com/'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消下载'));
      await tester.pumpAndSettle();
      expect(await result.future, isNull);
      // A late transport completion must not reopen installation review.
      transfer.complete(
        fixture.documents[modules.first.release!.url.toString()]!,
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byType(ModuleDownloadDialog), findsNothing);
      expect(find.text('确认模块安装计划'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failure and retry retain completed packages and cancellation returns no installation plan',
    (tester) async {
      late Directory directory;
      late Fixture fixture;
      late ModuleCatalogClient client;
      late List<ResolvedCatalogModule> modules;
      final failedTransfer = Completer<List<int>>();
      final retryTransfer = Completer<List<int>>();
      final downloadedIds = <String>[];
      var secondAttempts = 0;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('download-retry-ui-');
        fixture = Fixture(directory);
        await fixture.add(await makePackage('test.first'));
        await fixture.add(await makePackage('test.second'));
        modules = (await ModuleDependencyResolver(fixture.client).resolve(
          requests: {'test.first': 'any', 'test.second': 'any'},
          installed: {},
        )).ordered;
        client = ModuleCatalogClient(
          cacheDirectory: directory,
          networkRetries: 0,
          transport: (url, {cancellation, onProgress, required maximumBytes}) {
            downloadedIds.add(url.pathSegments.last);
            if (url == modules.last.release!.url) {
              secondAttempts++;
              return secondAttempts == 1
                  ? failedTransfer.future
                  : retryTransfer.future;
            }
            return fixture.fetch(
              url,
              cancellation: cancellation,
              onProgress: onProgress,
              maximumBytes: maximumBytes,
            );
          },
        );
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (!failedTransfer.isCompleted) failedTransfer.complete([]);
        if (!retryTransfer.isCompleted) retryTransfer.complete([]);
        client.dispose();
        fixture.client.dispose();
        await tester.runAsync(() => directory.delete(recursive: true));
      });
      final result = Completer<List<ScriptPackage>?>();
      await openDownloadDialog(
        tester,
        client: client,
        modules: modules,
        result: result,
      );
      await waitForDownloadUi(tester, find.textContaining('已完成 1/2'));
      await waitForDownloadUi(tester, find.text('下载中'));
      expect(secondAttempts, 1);
      final completeProgress =
          modules.first.release!.size /
          modules.fold<int>(0, (sum, module) => sum + module.release!.size);
      expect(
        find.text('整体下载进度 ${(completeProgress * 100).floor()}%'),
        findsOneWidget,
      );
      failedTransfer.completeError(
        const SocketException("Failed host lookup: 'github.com'"),
      );
      await waitForDownloadUi(tester, find.text('重试').hitTestable());
      expect(find.textContaining('已完成 1/2'), findsOneWidget);
      expect(find.textContaining('无法解析下载服务器地址'), findsOneWidget);
      expect(
        find.textContaining("Failed host lookup: 'github.com'"),
        findsOneWidget,
      );
      await tester.tap(find.text('重试'));
      await tester.pump();
      await waitForDownloadUi(tester, find.text('下载中'));
      expect(find.textContaining('已完成 1/2'), findsOneWidget);
      expect(secondAttempts, 2);
      expect(
        find.text('整体下载进度 ${(completeProgress * 100).floor()}%'),
        findsOneWidget,
      );
      expect(
        downloadedIds.where((id) => id == 'test.first.xmodule'),
        hasLength(1),
      );
      await tester.tap(find.text('取消下载'));
      await tester.pumpAndSettle();
      expect(await result.future, isNull);
      retryTransfer.complete(
        fixture.documents[modules.last.release!.url.toString()]!,
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('确认模块安装计划'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
