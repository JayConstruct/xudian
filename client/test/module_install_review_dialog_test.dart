import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app_scroll_behavior.dart';
import 'package:task_app/core/contracts/json_values.dart';
import 'package:task_app/core/declarative/package/module_package.dart';
import 'package:task_app/core/module_catalog/module_catalog.dart';
import 'package:task_app/core/module_host/module_install_review_dialog.dart';
import 'package:task_app/core/module_host/module_package.dart';

Future<ScriptPackage> _package(
  String id, {
  required String name,
  String version = '1.0.0',
  List<Object?> dependencies = const [],
  List<Object?> services = const [],
  List<Object?> optionalServices = const [],
  List<String> permissions = const [],
  Map<String, Object?> manifestDetails = const {},
}) async => ScriptPackage.verify(
  await ScriptPackage.build(
    {
      'formatVersion': 3,
      'manifest': {
        'id': id,
        'name': name,
        'description': '$name的用途说明',
        'version': version,
        'hostApi': '^1.21.0',
        'dataVersion': 1,
        'dependencies': dependencies,
        'optionalServices': optionalServices,
        'permissions': permissions,
        ...manifestDetails,
      },
      'entryPoint': 'main.js',
      'collections': [],
      'services': services,
      'pages': [],
    },
    {'main.js': 'export function main(){return {};}'},
  ),
  allowUnsignedLocal: true,
);

Future<ScriptPackage> _market(ScriptPackage local) async {
  final key = await Ed25519().newKeyPair();
  final public = await key.extractPublicKey();
  final archive = ZipDecoder().decodeBytes(local.bytes);
  final metadataFile = archive.files.firstWhere(
    (file) => file.name == 'package.json',
  );
  final metadata = object(
    jsonDecode(utf8.decode(metadataFile.content as List<int>)),
  );
  final release = <String, Object?>{
    'channel': 'market',
    'publisherId': 'test-publisher',
    'publishedAt': '2026-10-13T00:00:00Z',
    'review': {
      'status': 'approved',
      'reviewId': 'test-review',
      'policyVersion': '1',
      'reviewedAt': '2026-10-13T00:00:00Z',
    },
  };
  final signature = await Ed25519().sign(
    utf8.encode(
      canonicalJson({
        'packageFormat': 2,
        'release': release,
        'files': metadata['files'],
      }),
    ),
    keyPair: key,
  );
  final signed = utf8.encode(
    canonicalJson({
      ...metadata,
      'release': release,
      'signature': {
        'algorithm': 'ed25519',
        'keyId': 'test-key',
        'value': base64Encode(signature.bytes),
      },
    }),
  );
  final output = Archive();
  for (final file in archive.files) {
    if (file.name != 'package.json') output.addFile(file);
  }
  output.addFile(ArchiveFile('package.json', signed.length, signed));
  return ScriptPackage.verify(
    Uint8List.fromList(ZipEncoder().encode(output)!),
    publishers: TrustedPublisherRegistry([
      TrustedPublisherKey(
        publisherId: 'test-publisher',
        keyId: 'test-key',
        publicKey: public.bytes,
      ),
    ]),
  );
}

void main() {
  late Directory directory;
  late ModuleCatalogClient client;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('install-review-test-');
    client = ModuleCatalogClient(cacheDirectory: directory);
  });
  tearDown(() async {
    client.dispose();
    await directory.delete(recursive: true);
  });

  Future<ModuleResolution> resolve(
    List<ScriptPackage> packages, {
    Map<String, InstalledCatalogModule> installed = const {},
  }) => ModuleDependencyResolver(client).resolve(
    requests: const {},
    installed: installed,
    localPackages: packages,
    offline: true,
  );

  Future<void> showReview(
    WidgetTester tester,
    ModuleResolution resolution,
    List<ScriptPackage> packages,
    Set<String> requestedIds,
  ) => tester.pumpWidget(
    MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: ModuleBatchReviewDialog(
          modules: resolution.ordered,
          packages: packages,
          requestedIds: requestedIds,
        ),
      ),
    ),
  );

  testWidgets(
    'dragging inside long manifest moves the outer review to the next module',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final first = await _package(
        'test.first',
        name: '第一个模块',
        manifestDetails: {
          'reviewNotes': [for (var i = 0; i < 90; i++) '完整说明字段 $i：保留供审核与复制'],
        },
      );
      final second = await _package('test.second', name: '第二个模块');
      final resolution = await resolve([first, second]);
      await showReview(
        tester,
        resolution,
        [first, second],
        {first.id, second.id},
      );
      final disclosure = find.text('技术详情与完整计划');
      await tester.ensureVisible(disclosure);
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      final view = find.byType(SingleChildScrollView);
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: view, matching: find.byType(Scrollable)).first,
      );
      final manifest = find
          .byWidgetPredicate(
            (widget) =>
                widget is SelectableText &&
                (widget.data?.startsWith('完整模块声明：') ?? false),
          )
          .first;
      final viewport = tester.getRect(view);
      // Only position the initial text body. All forward navigation below comes
      // from pointer drags originating in that body, never ensureVisible/jumpTo.
      scroll.position.jumpTo(
        scroll.position.pixels +
            tester.getTopLeft(manifest).dy -
            viewport.top -
            24,
      );
      await tester.pump();
      final start = Offset(viewport.center.dx, viewport.bottom - 40);
      expect(tester.getRect(manifest).contains(start), isTrue);
      final initial = scroll.position.pixels;
      await tester.timedDragFrom(
        start,
        const Offset(0, -180),
        const Duration(milliseconds: 250),
      );
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(initial));
      final next = find.text('2. 第二个模块');
      for (
        var attempt = 0;
        attempt < 100 && !tester.getRect(next).overlaps(viewport);
        attempt++
      ) {
        await tester.timedDragFrom(
          start,
          const Offset(0, -180),
          const Duration(milliseconds: 250),
        );
        await tester.pumpAndSettle();
      }
      expect(tester.getRect(next).overlaps(viewport), isTrue);
      for (final widget in tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      )) {
        expect(widget.enableInteractiveSelection, isNot(false));
      }
      expect(
        (tester.widget<SelectableText>(manifest).data!),
        contains('完整说明字段 89'),
      );
      expect(find.text('确认安装').hitTestable(), findsOneWidget);
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final editable = tester.state<EditableTextState>(
        find.descendant(of: manifest, matching: find.byType(EditableText)),
      );
      editable.selectAll(SelectionChangedCause.toolbar);
      editable.copySelection(SelectionChangedCause.toolbar);
      await tester.pumpAndSettle();
      expect(copied, tester.widget<SelectableText>(manifest).data);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selected purpose precedes dependency reasons and upgrade versions',
    (tester) async {
      final old = await _package(
        'test.main',
        name: '日程管理',
        permissions: ['ui'],
      );
      final main = await _package(
        'test.main',
        name: '日程管理',
        version: '2.0.0',
        dependencies: ['test.shared'],
        permissions: ['ui', 'files'],
      );
      final shared = await _package('test.shared', name: '共享日历');
      final resolution = await resolve(
        [main, shared],
        installed: {old.id: InstalledCatalogModule(old, enabled: true)},
      );
      await showReview(tester, resolution, [main, shared], {main.id});
      expect(find.text('你选择的模块'), findsOneWidget);
      expect(find.text('自动加入的依赖'), findsOneWidget);
      expect(find.text('日程管理的用途说明'), findsOneWidget);
      expect(find.text('「日程管理」需要此模块才能运行。'), findsOneWidget);
      expect(find.text('升级并启用 · 1.0.0 → 2.0.0'), findsOneWidget);
      expect(find.text('安装 1 个，升级 1 个'), findsOneWidget);
      expect(find.text('新增 1 项权限'), findsOneWidget);
      expect(find.text('新增 · 读取或保存由你选择的文本文件'), findsOneWidget);
      expect(find.text('显示模块界面、交互提示和保存界面偏好'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('日程管理的用途说明')).dy,
        lessThan(tester.getTopLeft(find.text('共享日历的用途说明')).dy),
      );
      expect(find.textContaining('SHA-256：'), findsNothing);
    },
  );

  testWidgets('enable and reused dependency have accurate Chinese actions', (
    tester,
  ) async {
    final main = await _package(
      'test.main',
      name: '日程管理',
      dependencies: ['test.shared'],
    );
    final shared = await _package('test.shared', name: '共享日历');
    final resolution = await resolve(
      [main],
      installed: {
        main.id: InstalledCatalogModule(main, enabled: false),
        shared.id: InstalledCatalogModule(shared, enabled: true),
      },
    );
    await showReview(tester, resolution, [main], {main.id});
    expect(find.text('启用 · 1.0.0'), findsOneWidget);
    expect(find.text('继续使用 · 1.0.0（无需安装）'), findsOneWidget);
    expect(find.text('继续使用 1 个，启用 1 个'), findsOneWidget);
  });

  testWidgets(
    'service access explains effects and optional access is not a dependency',
    (tester) async {
      const permission = 'services.query:test.shared/data.read@1';
      final main = await _package(
        'test.main',
        name: '日程管理',
        permissions: [permission],
        optionalServices: [
          {
            'moduleId': 'test.shared',
            'serviceId': 'data.read',
            'majorVersion': 1,
            'kind': 'query',
          },
        ],
      );
      final resolution = await resolve([main]);
      await showReview(tester, resolution, [main], {main.id});
      expect(find.text('自动加入的依赖'), findsNothing);
      expect(find.textContaining('需要此模块才能运行'), findsNothing);
      expect(find.textContaining('读取「其他模块」提供的数据'), findsOneWidget);
      expect(find.textContaining(permission), findsNothing);
    },
  );

  testWidgets(
    'details retain ordered identity source permissions and package digest',
    (tester) async {
      final main = await _package(
        'test.main',
        name: '日程管理',
        dependencies: ['test.shared'],
        permissions: ['ui', 'future.permission'],
      );
      final shared = await _package('test.shared', name: '共享日历');
      final resolution = await resolve([main, shared]);
      await showReview(tester, resolution, [main, shared], {main.id});
      expect(find.textContaining('用途未识别'), findsOneWidget);
      expect(find.textContaining('future.permission'), findsNothing);
      expect(find.text('未签名包；摘要验证不代表发布者签名'), findsNWidgets(2));
      final detail = find.text('技术详情与完整计划');
      await tester.ensureVisible(detail);
      await tester.tap(detail);
      await tester.pumpAndSettle();
      expect(find.text('1. 共享日历'), findsOneWidget);
      expect(find.text('2. 日程管理'), findsOneWidget);
      expect(find.text('模块标识：test.main'), findsOneWidget);
      expect(find.text('来源：本地模块包'), findsNWidgets(2));
      expect(find.text('全部权限标识：ui、future.permission'), findsOneWidget);
      expect(find.text('SHA-256：${main.packageDigest}'), findsOneWidget);
      expect(find.text('依赖声明：["test.shared"]'), findsOneWidget);
      expect(
        tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((widget) => widget.data)
            .join('\n'),
        contains('"hostApi": "^1.21.0"'),
      );
      expect(find.text('按依赖顺序统一执行；失败时恢复原版本、数据和启用状态。'), findsOneWidget);
    },
  );

  testWidgets('command permissions describe possible data changes', (
    tester,
  ) async {
    final shared = await _package(
      'test.shared',
      name: '共享日历',
      services: [
        {
          'id': 'data.write',
          'major': 1,
          'kind': 'command',
          'handler': 'main',
          'description': '添加共享日程',
          'input': <String, Object?>{},
          'output': <String, Object?>{},
        },
      ],
    );
    final main = await _package(
      'test.main',
      name: '日程管理',
      permissions: ['services.command:test.shared/data.write@1'],
    );
    final resolution = await resolve([main, shared]);
    await showReview(tester, resolution, [main, shared], {main.id});
    expect(find.text('新增 · 调用「共享日历」的变更服务，可能修改其数据：添加共享日程'), findsOneWidget);
    expect(find.text('「日程管理」需要此模块才能运行。'), findsOneWidget);
  });

  testWidgets('cancel returns false without confirmation', (tester) async {
    final main = await _package('test.main', name: '日程管理');
    final resolution = await resolve([main]);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => ModuleBatchReviewDialog(
                    modules: resolution.ordered,
                    packages: [main],
                    requestedIds: {main.id},
                  ),
                );
              },
              child: const Text('开始审核'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开始审核'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('verified market signatures and bundled pins are distinguished', (
    tester,
  ) async {
    final market = await _market(await _package('test.market', name: '市场模块'));
    final local = await _package('test.bundled', name: '内置模块');
    final bundled = await ScriptPackage.verify(
      local.bytes,
      preinstalledDigest: local.packageDigest,
    );
    final resolution = await resolve([market, bundled]);
    await showReview(
      tester,
      resolution,
      [market, bundled],
      {market.id, bundled.id},
    );
    expect(find.text('发布者签名已验证，发布审核已通过'), findsOneWidget);
    expect(find.text('已通过内置包摘要校验；未在此流程单独验证发布者签名'), findsOneWidget);
    expect(find.textContaining('未签名包'), findsNothing);
  });

  testWidgets('narrow large text review scrolls and confirm returns a choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final main = await _package(
      'test.main',
      name: '日程管理与课程导入辅助模块',
      permissions: ['ui', 'browser.capture', 'files', 'http'],
    );
    final resolution = await resolve([main]);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => ModuleBatchReviewDialog(
                    modules: resolution.ordered,
                    packages: [main],
                    requestedIds: {main.id},
                  ),
                );
              },
              child: const Text('开始审核'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开始审核'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('确认安装'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });
}
