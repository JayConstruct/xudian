import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
// A fake platform exercises the real file picker and delayed file read boundary.
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_manager_page.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_catalog_widgets.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_management_widgets.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/ui/ui_design.dart';
import 'package:task_app/core/ui/ui_feedback.dart';
import 'package:task_app/core/ui/ui_pack_providers.dart';
import 'package:task_app/data/app_database.dart';

import 'module_catalog_test.dart' show makePackage;

class _ListStore extends CollectionStore {
  _ListStore(super.db);
  @override
  Future<List<Map<String, Object?>>> sql(
    String query, [
    List<Object?> args = const [],
  ]) async {
    if (query.contains('AS package_name')) {
      return [
        {
          'module_id': 'test.preview',
          'version': '1.0.0',
          'installed': 1,
          'enabled': 1,
          'package_kind': 'uiPack',
          'package_name': '预览测试',
          'package_description': '界面包',
        },
      ];
    }
    return super.sql(query, args);
  }
}

class _DelayedHost extends ModuleHost {
  _DelayedHost({required super.store, required super.directory});
  final previewGate = Completer<ScriptPackage>();
  @override
  Future<ScriptPackage> packageSource(String id, String version) =>
      previewGate.future;
}

class _DelayedFile extends XFile {
  _DelayedFile() : super('/tmp/selected.xmodule');
  final bytes = Completer<Uint8List>();
  bool reading = false;
  @override
  Future<Uint8List> readAsBytes() {
    reading = true;
    return bytes.future;
  }
}

class _FilePicker extends FileSelectorPlatform {
  _FilePicker(this.file);
  final XFile file;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => file;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'details and service use shared theme and spacing in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final package = await makePackage('test.details');
        final theme = AppDesign.theme(brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: ModuleDetailsDialog(
                package: package,
                dependents: const [],
                onDependency: (_) {},
              ),
            ),
          ),
        );
        final resolvedTheme = Theme.of(
          tester.element(find.byType(ModuleDetailsDialog)),
        );
        final label = tester.widget<Text>(find.text('模块 ID'));
        final value = tester.widget<SelectableText>(
          find.byWidgetPredicate(
            (widget) => widget is SelectableText && widget.data == package.id,
          ),
        );
        expect(label.style?.color, theme.colorScheme.onSurfaceVariant);
        expect(
          label.style?.fontSize,
          resolvedTheme.textTheme.labelMedium?.fontSize,
        );
        expect(value.style, resolvedTheme.textTheme.bodyMedium);
        expect(find.text(package.packageDigest), findsOneWidget);
        expect(find.textContaining('未签名包'), findsOneWidget);
        await tester.ensureVisible(find.text(package.packageDigest));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showHostService(context, {
                    'serviceId': 'data.read',
                    'majorVersion': 1,
                  }),
                  child: const Text('服务'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('服务'));
        await tester.pumpAndSettle();
        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        expect(dialog.titlePadding, AppDesign.dialogTitlePadding);
        expect(dialog.contentPadding, AppDesign.dialogContentPadding);
        expect(dialog.actionsPadding, AppDesign.dialogActionsPadding);
        expect(find.textContaining('由宿主提供，无需安装'), findsOneWidget);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('catalog filters use continuous control outlines', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme(Brightness.light),
        home: Scaffold(
          body: ModuleCatalogFilters(
            status: '全部',
            category: '全部分类',
            categories: const ['学习'],
            onStatusChanged: (_) {},
            onCategoryChanged: (_) {},
          ),
        ),
      ),
    );
    for (final id in ['status', 'category']) {
      final control = find.byKey(ValueKey('catalog-filter-$id'));
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: control, matching: find.byType(DecoratedBox)).first,
      );
      final decoration = box.decoration as ShapeDecoration;
      expect(decoration.shape, isA<RoundedSuperellipseBorder>());
      expect(
        (decoration.shape as RoundedSuperellipseBorder).borderRadius,
        BorderRadius.circular(AppDesign.compactRadius),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'host failure retries the failed provider and recovers the module list',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final store = _ListStore(db);
      final host = ModuleHost(
        store: store,
        directory: Directory('/tmp/manager-error-test'),
      );
      var attempts = 0;
      final container = ProviderContainer(
        overrides: [
          moduleHostProvider.overrideWith((_) async {
            if (++attempts == 1) throw StateError('测试宿主加载失败');
            return host;
          }),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await host.close();
        await store.close();
        await db.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppDesign.theme(Brightness.dark),
            home: const Scaffold(body: HostManagerPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.textContaining('无法加载模块管理'), findsOneWidget);
      expect(attempts, 1);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.text('预览测试'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('leaving during file read prevents publisher and install reads', (
    tester,
  ) async {
    final previous = FileSelectorPlatform.instance;
    final file = _DelayedFile();
    FileSelectorPlatform.instance = _FilePicker(file);
    addTearDown(() => FileSelectorPlatform.instance = previous);
    final db = AppDatabase(NativeDatabase.memory());
    final store = _ListStore(db);
    final host = ModuleHost(
      store: store,
      directory: Directory('/tmp/manager-import-test'),
    );
    var publisherReads = 0;
    final container = ProviderContainer(
      overrides: [
        moduleHostProvider.overrideWith((_) async => host),
        hostPublisherRegistryProvider.overrideWith((_) async {
          publisherReads++;
          throw StateError('must not read publishers after leaving');
        }),
      ],
    );
    addTearDown(() async {
      if (!file.bytes.isCompleted) file.bytes.complete(Uint8List(0));
      container.dispose();
      await host.close();
      await store.close();
      await db.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: HostManagerPage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入 .xmodule'));
    await tester.pump();
    expect(file.reading, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    file.bytes.complete(Uint8List(0));
    await tester.pump();
    expect(publisherReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'leaving during preview verification prevents disposed ref reads',
    (tester) async {
      final source = await makePackage('test.preview');
      final db = AppDatabase(NativeDatabase.memory());
      final store = _ListStore(db);
      final host = _DelayedHost(
        store: store,
        directory: Directory('/tmp/manager-preview-test'),
      );
      final container = ProviderContainer(
        overrides: [moduleHostProvider.overrideWith((_) async => host)],
      );
      addTearDown(() async {
        if (!host.previewGate.isCompleted) host.previewGate.complete(source);
        container.dispose();
        await host.close();
        await store.close();
        await db.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: HostManagerPage())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('预览 UI 包'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      host.previewGate.complete(source);
      await tester.pump();
      expect(container.exists(uiPackRegistryProvider), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
